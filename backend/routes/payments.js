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
    const numAmount = parseFloat(amount);
    const numPaid = parseFloat(paid ?? amount);
    const numExpected = parseFloat(expectedAmount);

    // Verify exact amount match (within floating point delta 0.01)
    const amountMatches = !isNaN(numAmount) && !isNaN(numExpected) && Math.abs(numAmount - numExpected) < 0.05;
    const paidMatches = !isNaN(numPaid) && numPaid >= (numAmount - 0.05);

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

      console.log(`[PAYMENT SUCCESS] Order ${order._id} confirmed for amount ₹${numAmount}`);
      return { success: true, paymentStatus: 'Paid', orderStatus: 'Confirmed' };
    } else {
      // Amount mismatch or WRONG payment amount
      order.paymentStatus = 'WRONG';
      order.notes = (order.notes ? order.notes + '\n' : '') +
        `[PAYMENT WRONG] Expected: ₹${numExpected}, Server Amount: ₹${numAmount}, Paid: ₹${numPaid}`;
      order.paymentDetails = payload;
      await order.save();

      console.warn(`[PAYMENT WRONG AMOUNT] Order ${order._id}: expected ₹${numExpected}, got ₹${numAmount}`);
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

    let payUrl = null;
    let finalAmount = initialTotal;
    let paymentServerOrderId = null;

    if (paymentServerUrl && appKey && !paymentServerUrl.includes('REPLACE-WITH')) {
      try {
        console.log(`[Payment Server Request] POST ${paymentServerUrl}/api/create for ref: ${order._id}`);
        const createRes = await fetch(`${paymentServerUrl}/api/create`, {
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
            payee: 'Siva Murugan Fancy',
          }),
        });

        if (createRes.ok) {
          const createData = await createRes.json();
          paymentServerOrderId = createData.id;
          finalAmount = parseFloat(createData.amount) || initialTotal;
          payUrl = createData.payUrl;

          order.paymentServerOrderId = paymentServerOrderId;
          order.amountToPay = finalAmount;
          order.total = finalAmount;
          await order.save();
          console.log(`[Payment Server Success] Server Order ID: ${paymentServerOrderId}, Amount: ₹${finalAmount}`);
        } else {
          console.error('[Payment Server Create Error]', await createRes.text());
        }
      } catch (err) {
        console.error('[Payment Server Call Failed]', err.message);
      }
    }

    // Fallback direct UPI Intent URL if payment server URL not configured
    if (!payUrl) {
      payUrl = `upi://pay?pa=${dynamicUpiId}&pn=${encodeURIComponent('FANCY WORLD')}&tr=${upiRef}&am=${finalAmount.toFixed(2)}&cu=INR&tn=${encodeURIComponent('Order ' + order.orderNumber)}`;
    }

    return res.json({
      success: true,
      orderId: order._id.toString(),
      fancyWorldOrderId: order._id.toString(),
      orderNumber: order.orderNumber,
      amount: finalAmount,
      payUrl: payUrl,
      upiPayload: payUrl,
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
    console.log('[CALLBACK RECEIVED] Headers:', JSON.stringify(req.headers));

    if (!verifyHMACSignature(req)) {
      console.warn('[CALLBACK REJECTED] HMAC signature check failed');
      return res.status(400).json({ message: 'Invalid signature' });
    }

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
          console.log(`[S2S STATUS CHECK] Querying ${paymentServerUrl}/api/status?id=${pOrderId}`);
          const statusRes = await fetch(`${paymentServerUrl}/api/status?id=${pOrderId}`, {
            headers: { 'x-api-key': appKey },
          });

          if (statusRes.ok) {
            const statusData = await statusRes.json();
            console.log(`[S2S STATUS RESPONSE]`, JSON.stringify(statusData));
            if (statusData && statusData.status && statusData.status !== 'PENDING') {
              await processPaymentUpdate(order, statusData, req.app);
            }
          } else {
            console.warn(`[S2S STATUS CHECK FAILED] HTTP ${statusRes.status}`);
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
