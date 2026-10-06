const express = require('express');
const router = express.Router();
const crypto = require('crypto');
const mongoose = require('mongoose');
const Order = require('../models/Order');
const Product = require('../models/Product');
const Coupon = require('../models/Coupon');
const AppSettings = require('../models/AppSettings');
const User = require('../models/User');
const { verifyToken } = require('../middleware/auth');
const { createNotification } = require('./notifications');
const { recordOrderSale } = require('../services/analyticsService');

/**
 * Helper to verify HMAC-SHA256 signature from Payment Server
 */
function verifyHMACSignature(req) {
  const signature = req.headers['x-signature'] || req.headers['x-provider-signature'];
  if (!signature) {
    console.warn('[HMAC Check] Missing signature header');
    return false;
  }

  const appKey = process.env.APP_KEY;
  if (!appKey) {
    console.warn('[HMAC Check] Missing APP_KEY in environment variables');
    return false;
  }

  let rawData;
  if (req.rawBody && Buffer.isBuffer(req.rawBody)) {
    rawData = req.rawBody;
  } else if (typeof req.body === 'string') {
    rawData = Buffer.from(req.body);
  } else if (Buffer.isBuffer(req.body)) {
    rawData = req.body;
  } else {
    rawData = Buffer.from(JSON.stringify(req.body || {}));
  }

  try {
    const hmac = crypto.createHmac('sha256', appKey);
    hmac.update(rawData);
    const expectedHex = hmac.digest('hex');

    const receivedSig = String(signature).trim().toLowerCase();
    const expectedSig = expectedHex.toLowerCase();

    if (receivedSig !== expectedSig) {
      console.warn(`[HMAC Check Mismatch] Received: ${receivedSig}, Expected: ${expectedSig}`);
    }

    const sigBuf = Buffer.from(receivedSig, 'hex');
    const expBuf = Buffer.from(expectedSig, 'hex');

    if (sigBuf.length !== expBuf.length) return false;
    return crypto.timingSafeEqual(sigBuf, expBuf);
  } catch (err) {
    console.error('[HMAC Verification Error]', err);
    return false;
  }
}

/**
 * Helper to build NPCI compliant UPI URI
 */
function buildValidUpiUri({ upiId, payee, amount, ref, orderNumber, rawUri }) {
  let cleanUpiId = (upiId || '').replace(/%40/g, '@').trim();
  let cleanPayee = payee || 'SM Fancy';
  let formattedAmount = parseFloat(amount).toFixed(2);

  if (rawUri && rawUri.startsWith('upi://')) {
    const queryStr = rawUri.includes('?') ? rawUri.split('?')[1] : '';
    const params = new URLSearchParams(queryStr);

    let pa = (params.get('pa') || cleanUpiId).replace(/%40/g, '@').trim();
    let pn = params.get('pn') || cleanPayee;
    let am = params.get('am') || formattedAmount;
    let cu = params.get('cu') || 'INR';
    let tr = params.get('tr') || ref;
    let tn = params.get('tn') || ('Order ' + (orderNumber || ref));

    return 'upi://pay?pa=' + pa +
      '&pn=' + encodeURIComponent(pn) +
      '&am=' + parseFloat(am).toFixed(2) +
      '&cu=' + cu +
      '&tr=' + encodeURIComponent(tr) +
      '&tn=' + encodeURIComponent(tn);
  }

  return 'upi://pay?pa=' + cleanUpiId +
    '&pn=' + encodeURIComponent(cleanPayee) +
    '&am=' + formattedAmount +
    '&cu=INR' +
    '&tr=' + encodeURIComponent(ref) +
    '&tn=' + encodeURIComponent('Order ' + (orderNumber || ref));
}

/**
 * Idempotent Order Payment Status Updater
 */
async function processPaymentUpdate(order, payload, app = null) {
  // If order is already processed out of Pending, maintain idempotency
  if (order.paymentStatus !== 'Pending') {
    return {
      success: true,
      message: 'Already processed',
      paymentStatus: order.paymentStatus,
      orderStatus: order.status,
    };
  }

  const { status, amount, paid, utr, orderId } = payload;
  const upperStatus = String(status || '').toUpperCase();
  const expectedAmount = order.amountToPay ?? order.total;

  if (upperStatus === 'SUCCESS' || upperStatus === 'OK' || upperStatus === 'PAID') {
    // Use integer paise internally to avoid floating point precision errors
    const expectedPaise = Math.round(parseFloat(expectedAmount) * 100);
    const amountPaise = Math.round(parseFloat(amount) * 100);
    const paidPaise = Math.round(parseFloat(paid ?? amount) * 100);

    const amountMatches = !isNaN(amountPaise) && !isNaN(expectedPaise) && amountPaise === expectedPaise;
    const paidMatches = !isNaN(paidPaise) && paidPaise >= expectedPaise;

    if (amountMatches && paidMatches) {
      order.paymentStatus = 'Paid';
      order.status = 'Confirmed';
      if (utr || orderId) order.upiTransactionId = utr || orderId;
      order.paymentDetails = payload;
      order.timeline.push({
        status: 'Confirmed',
        message: 'Payment verified successfully via payment server',
        isCompleted: true,
      });

      await order.save();
      await handlePostPayment(app, order);

      console.log(`[STAGE N] Order ${order._id} confirmed for amount ₹${parseFloat(expectedAmount).toFixed(2)}`);
      return { success: true, paymentStatus: 'Paid', orderStatus: 'Confirmed' };
    } else {
      // Amount mismatch or WRONG payment amount
      order.paymentStatus = 'WRONG';
      order.notes = (order.notes ? order.notes + '\n' : '') +
        `[PAYMENT WRONG] Expected: ₹${parseFloat(expectedAmount).toFixed(2)}, Received: ₹${parseFloat(amount).toFixed(2)}, Paid: ₹${parseFloat(paid ?? amount).toFixed(2)}`;
      order.paymentDetails = payload;
      await order.save();

      console.warn(`[PAYMENT WRONG AMOUNT] Order ${order._id}: expected ₹${parseFloat(expectedAmount).toFixed(2)}, paid ₹${parseFloat(paid ?? amount).toFixed(2)}`);
      return { success: false, paymentStatus: 'WRONG', orderStatus: order.status, message: 'Amount mismatch' };
    }
  } else if (upperStatus === 'WRONG') {
    order.paymentStatus = 'WRONG';
    order.notes = (order.notes ? order.notes + '\n' : '') + '[PAYMENT WRONG] Reported WRONG by payment server';
    order.paymentDetails = payload;
    await order.save();

    return { success: false, paymentStatus: 'WRONG', orderStatus: order.status };
  } else if (upperStatus === 'CANCELLED' || upperStatus === 'FAILED' || upperStatus === 'BAD') {
    order.paymentStatus = 'Cancelled';
    order.status = 'Cancelled';
    order.paymentDetails = payload;
    await order.save();

    return { success: false, paymentStatus: 'Cancelled', orderStatus: 'Cancelled' };
  }

  return { success: false, paymentStatus: order.paymentStatus, orderStatus: order.status };
}

/**
 * Post payment fulfillment (Stock deduction, Analytics, Loyalty Points, Notification)
 */
async function handlePostPayment(app, order) {
  try {
    for (const item of order.items) {
      if (item.product) {
        await Product.findByIdAndUpdate(item.product, { $inc: { stock: -item.quantity } });
      }
    }

    await recordOrderSale(order);

    const points = Math.floor(order.total / 100);
    if (order.userId) {
      await User.findByIdAndUpdate(order.userId, { $inc: { loyaltyPoints: points } });
    }

    if (app) {
      const productNames = order.items.map(i => i.name).join(', ');
      await createNotification(app, {
        userId: order.userId,
        title: 'Payment Confirmed!',
        body: `Your payment for ${productNames} has been verified and your order is confirmed.`,
        type: 'order',
        data: { orderId: order._id },
      });
    }
  } catch (err) {
    console.error('[POST PAYMENT ERROR]', err);
  }
}

// ─── ENDPOINTS ───────────────────────────────────────────────────────────────

/**
 * Create Order & Initiate Payment Server Call
 * POST /api/payments/create-order or /api/payments/create
 */
const createPaymentHandler = async (req, res) => {
  try {
    const { items, address, couponCode, shipping = 0, tax = 0, returnUrl: clientReturnUrl } = req.body;

    if (!items || items.length === 0) {
      return res.status(400).json({ message: 'No items in cart' });
    }

    // 1. Calculate & validate subtotal
    let calculatedSubtotal = 0;
    for (const item of items) {
      const product = await Product.findById(item.product);
      if (!product) return res.status(404).json({ message: `Product ${item.name} not found` });
      if (product.stock < item.quantity) return res.status(400).json({ message: `Insufficient stock for ${product.name}` });
      calculatedSubtotal += product.price * item.quantity;
    }

    let couponDiscount = 0;
    if (couponCode) {
      const coupon = await Coupon.findOne({ code: couponCode.toUpperCase(), isActive: true });
      if (coupon) {
        couponDiscount = (coupon.discountType === 'percentage')
          ? Math.min(Math.round((calculatedSubtotal * coupon.discountValue) / 100), coupon.maxDiscountAmount || calculatedSubtotal)
          : coupon.discountValue;
      }
    }

    const initialTotal = calculatedSubtotal + shipping + tax - couponDiscount;
    if (initialTotal <= 0) return res.status(400).json({ message: 'Invalid total amount' });

    // 2. Create Order in DB
    const upiRef = `FW${Date.now()}${Math.floor(Math.random() * 1000)}`;
    const orderNumber = await Order.generateUniqueOrderNumber();

    console.log(`[STAGE A/B] Creating order #${orderNumber} for initial amount ₹${initialTotal}`);

    const order = new Order({
      userId: req.userId || req.body.userId,
      orderNumber,
      items,
      address,
      paymentMethod: 'UPI',
      paymentStatus: 'Pending',
      subtotal: calculatedSubtotal,
      shipping,
      tax,
      couponCode,
      couponDiscount,
      total: initialTotal,
      amountToPay: initialTotal,
      status: 'Placed',
      upiReferenceNo: upiRef,
      timeline: [
        { status: 'Placed', message: 'Order initiated via UPI Payment Server', isCompleted: true },
        { status: 'Pending Verification', message: 'Waiting for payment confirmation...', isCompleted: false },
      ],
    });

    try {
      await order.save();
    } catch (saveErr) {
      if (saveErr.code === 11000) {
        order.orderNumber = `FW${Date.now()}`;
        await order.save();
      } else {
        throw saveErr;
      }
    }

    // 3. Fetch Dynamic Merchant UPI ID from Admin Settings
    const settings = await AppSettings.findOne();
    const dynamicUpiId = (settings?.upiId && settings.upiId.trim().length > 0)
      ? settings.upiId.trim()
      : 'shivasurya982@okicici';

    // 4. Determine Return Link & Payment Server URL
    const paymentServerUrl = process.env.PAYMENT_SERVER_URL;
    const appKey = process.env.APP_KEY;
    const returnUrl = clientReturnUrl || process.env.RETURN_URL_APP || 'fancyworld://payment-done';

    let rawPayUrl = null;
    let finalAmount = initialTotal;
    let paymentServerOrderId = null;
    let serverPayee = 'SM Fancy';
    let serverUpiId = dynamicUpiId;

    if (paymentServerUrl && appKey && !paymentServerUrl.includes('REPLACE-WITH')) {
      try {
        console.log(`[STAGE C] Creating payment session at ${paymentServerUrl}`);
        let createRes = await fetch(`${paymentServerUrl}/api/create`, {
          method: 'POST',
          headers: {
            'x-api-key': appKey,
            'Content-Type': 'application/json',
          },
          body: JSON.stringify({
            amount: initialTotal,
            ref: order._id.toString(),
            returnUrl,
            upiId: dynamicUpiId,
            vpa: dynamicUpiId,
            payee: 'SM Fancy',
          }),
        });

        // Fallback to /api/order if /api/create returns 404 on this payment server instance
        if (createRes.status === 404) {
          console.log(`[Payment Server] /api/create returned 404, attempting /api/order endpoint`);
          createRes = await fetch(`${paymentServerUrl}/api/order`, {
            method: 'POST',
            headers: {
              'x-api-key': appKey,
              'Content-Type': 'application/json',
            },
            body: JSON.stringify({
              amount: initialTotal,
              ref: order._id.toString(),
              returnUrl,
              upiId: dynamicUpiId,
              payee: 'SM Fancy',
            }),
          });
        }

        if (createRes.ok) {
          const createData = await createRes.json();
          console.log(`[STAGE D] Payment server response:`, JSON.stringify(createData));
          paymentServerOrderId = createData.id || createData.orderId;
          finalAmount = parseFloat(createData.amount) || initialTotal;
          rawPayUrl = createData.payUrl || createData.upi || createData.qrImage;
          serverPayee = createData.payee || 'SM Fancy';
          serverUpiId = createData.upiId || dynamicUpiId;

          order.paymentServerOrderId = paymentServerOrderId;
          order.amountToPay = finalAmount;
          order.total = finalAmount;
          await order.save();
          console.log(`[STAGE E] Session initialized. Server Order ID: ${paymentServerOrderId}, Amount: ₹${finalAmount}`);
        } else {
          console.error('[Payment Server Create Error]', createRes.status, await createRes.text());
        }
      } catch (err) {
        console.error('[Payment Server Call Failed]', err.message);
      }
    }

    // Build 100% valid NPCI compliant UPI URI (sanitizing %40 in pa and adding exact parameters)
    const cleanUpiUri = buildValidUpiUri({
      upiId: serverUpiId,
      payee: serverPayee,
      amount: finalAmount,
      ref: order._id.toString(),
      orderNumber: order.orderNumber,
      rawUri: rawPayUrl,
    });

    const finalPayUrl = (rawPayUrl && (rawPayUrl.startsWith('http://') || rawPayUrl.startsWith('https://')))
      ? rawPayUrl
      : cleanUpiUri;

    console.log(`[STAGE G] Generated clean UPI URI: ${cleanUpiUri}`);

    return res.json({
      success: true,
      orderId: order._id.toString(),
      fancyWorldOrderId: order._id.toString(),
      orderNumber: order.orderNumber,
      amount: finalAmount,
      payUrl: finalPayUrl,
      upiUri: cleanUpiUri,
      upiPayload: cleanUpiUri,
      paymentServerOrderId,
      upiReferenceNo: upiRef,
    });
  } catch (err) {
    console.error('[CREATE PAYMENT ERROR]', err);
    res.status(500).json({ message: 'Failed to initiate payment', error: err.message });
  }
};

router.post('/create-order', verifyToken, createPaymentHandler);
router.post('/create', verifyToken, createPaymentHandler);

/**
 * Payment Server Callback Endpoint
 * POST /api/payments/callback or /payment-callback or /webhook
 */
const callbackHandler = async (req, res) => {
  try {
    console.log('[STAGE L] Callback received. Headers:', JSON.stringify(req.headers));

    if (!verifyHMACSignature(req)) {
      console.warn('[CALLBACK REJECTED] HMAC signature check failed');
      return res.status(400).json({ message: 'Invalid signature' });
    }

    console.log('[STAGE M] HMAC signature verified successfully.');

    const payload = typeof req.body === 'string' ? JSON.parse(req.body) : req.body;
    console.log('[CALLBACK PAYLOAD]', JSON.stringify(payload));

    const { ref, orderId, status, amount, paid } = payload;

    if (!ref && !orderId) {
      return res.status(400).json({ message: 'Missing order ref or orderId' });
    }

    const query = [];
    if (ref) {
      if (mongoose.Types.ObjectId.isValid(ref)) query.push({ _id: ref });
      query.push({ orderNumber: ref });
      query.push({ upiReferenceNo: ref });
    }
    if (orderId) {
      query.push({ paymentServerOrderId: orderId });
    }

    if (query.length === 0) {
      return res.status(400).json({ message: 'Invalid search criteria' });
    }

    const order = await Order.findOne({ $or: query });
    if (!order) {
      console.warn('[CALLBACK ERROR] Order not found for criteria:', JSON.stringify(query));
      return res.status(404).json({ message: 'Order not found' });
    }

    const result = await processPaymentUpdate(order, payload, req.app);
    return res.status(200).json(result);
  } catch (err) {
    console.error('[CALLBACK ERROR]', err);
    return res.status(500).json({ message: 'Internal Server Error' });
  }
};

router.post('/callback', callbackHandler);
router.post('/payment-callback', callbackHandler);
router.post('/webhook', callbackHandler);

/**
 * Server-to-Server Status Check (Safety Net)
 * GET /api/payments/orders/:id/payment-status or /status/:orderId
 */
const statusCheckHandler = async (req, res) => {
  try {
    const orderIdParam = req.params.id || req.params.orderId;
    const query = [];
    if (mongoose.Types.ObjectId.isValid(orderIdParam)) query.push({ _id: orderIdParam });
    query.push({ orderNumber: orderIdParam });
    query.push({ upiReferenceNo: orderIdParam });

    const order = await Order.findOne({ $or: query });
    if (!order) {
      return res.status(404).json({ message: 'Order not found' });
    }

    // Safety net: If order is still Pending, check server-to-server with Payment Server
    if (order.paymentStatus === 'Pending') {
      const paymentServerUrl = process.env.PAYMENT_SERVER_URL;
      const appKey = process.env.APP_KEY;
      const pOrderId = order.paymentServerOrderId || order._id.toString();

      if (paymentServerUrl && appKey && !paymentServerUrl.includes('REPLACE-WITH')) {
        try {
          console.log(`[S2S STATUS CHECK] Querying payment server for ID: ${pOrderId}`);
          let statusRes = await fetch(`${paymentServerUrl}/api/status?id=${encodeURIComponent(pOrderId)}`, {
            headers: { 'x-api-key': appKey },
          });

          let statusData = statusRes.ok ? await statusRes.json() : null;

          // If ?id= returned 404 or UNKNOWN, fallback to ?order=
          if (!statusData || statusData.status === 'UNKNOWN' || statusRes.status === 404) {
            statusRes = await fetch(`${paymentServerUrl}/api/status?order=${encodeURIComponent(pOrderId)}`, {
              headers: { 'x-api-key': appKey },
            });
            if (statusRes.ok) {
              statusData = await statusRes.json();
            }
          }

          if (statusData && statusData.status && statusData.status !== 'PENDING' && statusData.status !== 'UNKNOWN') {
            console.log(`[S2S STATUS RESPONSE]`, JSON.stringify(statusData));
            await processPaymentUpdate(order, statusData, req.app);
          }
        } catch (err) {
          console.error('[STATUS CHECK S2S ERROR]', err.message);
        }
      }
    }

    return res.json({
      success: true,
      orderId: order._id,
      orderNumber: order.orderNumber,
      paymentStatus: order.paymentStatus,
      orderStatus: order.status,
      amountToPay: order.amountToPay || order.total,
      notes: order.notes,
    });
  } catch (err) {
    console.error('[STATUS CHECK ERROR]', err);
    return res.status(500).json({ message: err.message });
  }
};

// Publicly checkable safety net for deep-links and app polling
router.get('/orders/:id/payment-status', statusCheckHandler);
router.get('/status/:orderId', statusCheckHandler);

/**
 * Background Retry Job for Orders remaining PENDING > 6 Minutes
 */
async function runPendingOrderRetryJob(app = null) {
  try {
    const sixMinutesAgo = new Date(Date.now() - 6 * 60 * 1000);
    const pendingOrders = await Order.find({
      paymentStatus: 'Pending',
      createdAt: { $lte: sixMinutesAgo },
    });

    const paymentServerUrl = process.env.PAYMENT_SERVER_URL;
    const appKey = process.env.APP_KEY;

    if (!paymentServerUrl || !appKey || paymentServerUrl.includes('REPLACE-WITH')) {
      return;
    }

    for (const order of pendingOrders) {
      try {
        const pOrderId = order.paymentServerOrderId || order._id.toString();
        const res = await fetch(`${paymentServerUrl}/api/status?id=${pOrderId}`, {
          headers: { 'x-api-key': appKey },
        });

        if (res.ok) {
          const data = await res.json();
          if (data && data.status) {
            if (data.status === 'CANCELLED') {
              order.paymentStatus = 'Cancelled';
              order.status = 'Cancelled';
              await order.save();
            } else if (data.status === 'SUCCESS' || data.status === 'WRONG') {
              await processPaymentUpdate(order, data, app);
            }
          }
        }
      } catch (err) {
        console.error(`[RETRY JOB ERROR] Order ${order._id}:`, err.message);
      }
    }
  } catch (err) {
    console.error('[RETRY JOB FAILED]', err.message);
  }
}

function startPendingPaymentRetryJob(app = null) {
  setInterval(() => {
    runPendingOrderRetryJob(app);
  }, 2 * 60 * 1000);
}

module.exports = router;
module.exports.verifyHMACSignature = verifyHMACSignature;
module.exports.processPaymentUpdate = processPaymentUpdate;
module.exports.runPendingOrderRetryJob = runPendingOrderRetryJob;
module.exports.startPendingPaymentRetryJob = startPendingPaymentRetryJob;
