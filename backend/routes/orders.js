const express = require('express');
const router = express.Router();
const Order = require('../models/Order');
const Coupon = require('../models/Coupon');
const User = require('../models/User');
const Product = require('../models/Product');
const { verifyToken, requireAdmin } = require('../middleware/auth');
const { createNotification } = require('./notifications');
const { recordOrderSale } = require('../services/analyticsService');

// POST /api/orders
router.post('/', verifyToken, async (req, res) => {
  try {
    const {
      items,
      address,
      paymentMethod,
      couponCode,
      subtotal,
      shipping = 0,
      tax = 0,
      customerLiveLocation,
    } = req.body;

    let couponDiscount = 0;

    if (couponCode) {
      const coupon = await Coupon.findOne({
        code: couponCode.toUpperCase(),
        isActive: true,
      });

      if (coupon) {
        if (coupon.discountType === 'percentage') {
          couponDiscount = Math.round((subtotal * coupon.discountValue) / 100);
          if (coupon.maxDiscountAmount) {
            couponDiscount = Math.min(couponDiscount, coupon.maxDiscountAmount);
          }
        } else {
          couponDiscount = coupon.discountValue;
        }

        coupon.usageCount += 1;
        coupon.usedBy.push(req.userId);
        await coupon.save();
      }
    }

    // 1. Validate Stock and Prepare Updates
    for (const item of items) {
        const product = await Product.findById(item.product);
        if (!product) {
            return res.status(404).json({ message: `Product ${item.name} not found` });
        }
        if (product.stock < item.quantity) {
            return res.status(400).json({ message: `Insufficient stock for ${product.name}. Available: ${product.stock}` });
        }
    }

    // 2. Calculate Final Total and Create Order
    const total = subtotal + shipping + tax - couponDiscount;

    // Generate unique order number explicitly
    const orderNumber = await Order.generateUniqueOrderNumber();

    const order = new Order({
      userId: req.userId,
      orderNumber,
      items,
      address,
      paymentMethod,
      subtotal,
      shipping,
      tax,
      couponCode,
      couponDiscount,
      total,
      customerLiveLocation,
      status: 'Placed',
      paymentStatus: (paymentMethod === 'COD') ? 'Pending' : 'Pending',
      timeline: [
        {
          status: 'Placed',
          message: (paymentMethod === 'COD') ? 'Order placed via Cash on Delivery' : 'Order placed',
          isCompleted: true,
        },
      ],
    });

    try {
      await order.save();
    } catch (saveErr) {
      if (saveErr.code === 11000) {
        order.orderNumber = `FW-${Date.now().toString().slice(-6)}`;
        await order.save();
      } else {
        throw saveErr;
      }
    }

    // Record for persistent analytics (decoupled from order history)
    await recordOrderSale(order);

    // 3. Decrease Stock and check low stock alert
    for (const item of items) {
        const updatedProduct = await Product.findByIdAndUpdate(
            item.product,
            { $inc: { stock: -item.quantity } },
            { new: true }
        );
        if (updatedProduct && updatedProduct.stock <= 5) {
          await createNotification(req.app, {
            forAdmin: true,
            title: updatedProduct.stock <= 0 ? 'Out of Stock Alert!' : 'Low Stock Warning!',
            body: `${updatedProduct.name} has ${updatedProduct.stock <= 0 ? '0 (Out of stock)' : updatedProduct.stock + ' left in stock'}.`,
            type: 'stock',
            data: { productId: updatedProduct._id, screen: 'ProductManagement' }
          });
        }
    }

    // Reward points
    const pointsEarned = Math.floor(total / 100);
    const user = await User.findByIdAndUpdate(req.userId, {
      $inc: { loyaltyPoints: pointsEarned },
    }, { new: true });

    // Create Customer Notification
    const productNames = items.map(i => i.name).join(', ');
    await createNotification(req.app, {
      userId: req.userId,
      title: 'Order Placed!',
      body: `Your purchase of ${productNames} has been successfully placed.`,
      type: 'order',
      data: { orderId: order._id }
    });

    // Create Admin Notification
    await createNotification(req.app, {
      forAdmin: true,
      title: 'New Order Placed!',
      body: `Order #${order.orderNumber} placed by ${user?.name || 'Customer'} for ₹${total.toFixed(0)}.`,
      type: 'order',
      data: { orderId: order._id, screen: 'OrderManagement' }
    });

    res.status(201).json(order);
  } catch (err) {
    res.status(500).json({ message: err.message });
  }
});

// GET MY ORDERS
router.get('/', verifyToken, async (req, res) => {
  try {
    const { page = 1, limit = 10, status } = req.query;
    const query = { userId: req.userId };
    if (status) { query.status = status; }

    const orders = await Order.find(query)
      .sort({ createdAt: -1 })
      .skip((page - 1) * Number(limit))
      .limit(Number(limit))
      .populate('items.product', 'name imageUrl');

    const total = await Order.countDocuments(query);
    res.json({ orders, total });
  } catch (err) {
    res.status(500).json({ message: err.message });
  }
});

// ADMIN ALL ORDERS
router.get('/admin/all', verifyToken, requireAdmin, async (req, res) => {
  try {
    const { page = 1, limit = 20, status, search } = req.query;
    const query = {};
    if (status) { query.status = status; }

    let orders = await Order.find(query)
      .populate('userId', 'name email phone')
      .populate('items.product', 'name imageUrl')
      .sort({ createdAt: -1 })
      .skip((page - 1) * Number(limit))
      .limit(Number(limit));

    if (search) {
      orders = orders.filter(
        (o) =>
          o.orderNumber?.includes(search) ||
          o.userId?.name?.toLowerCase().includes(search.toLowerCase())
      );
    }

    const total = await Order.countDocuments(query);
    res.json({ orders, total, page: Number(page), pages: Math.ceil(total / Number(limit)) });
  } catch (err) {
    res.status(500).json({ message: err.message });
  }
});

// ADMIN UPDATE STATUS
router.put('/admin/:id/status', verifyToken, requireAdmin, async (req, res) => {
  try {
    const { status, message, trackingId } = req.body;
    const order = await Order.findById(req.params.id);

    if (!order) { return res.status(404).json({ message: 'Order not found' }); }

    order.status = status;
    if (trackingId) { order.trackingId = trackingId; }
    if (status === 'Delivered') { order.deliveredAt = new Date(); }

    order.timeline.push({
      status,
      message: message || `Order ${status}`,
      isCompleted: true,
    });

    await order.save();

    // Create Status Update Notification
    const productNames = order.items.map(i => i.name).join(', ');
    await createNotification(req.app, {
        userId: order.userId,
        title: `Order ${status}!`,
        body: `Your purchase of ${productNames} is now ${status.toLowerCase()}.`,
        type: 'order',
        data: { orderId: order._id, status }
    });

    res.json(order);
  } catch (err) {
    res.status(500).json({ message: err.message });
  }
});

// GET SINGLE ORDER
router.get('/:id', verifyToken, async (req, res) => {
  try {
    const order = await Order.findById(req.params.id)
      .populate('items.product', 'name imageUrl price');

    if (!order) { return res.status(404).json({ message: 'Order not found' }); }

    if (order.userId.toString() !== req.userId && req.userRole !== 'admin') {
      return res.status(403).json({ message: 'Access denied' });
    }

    res.json(order);
  } catch (err) {
    res.status(500).json({ message: err.message });
  }
});

// DELETE ORDER (Soft delete or full delete - user can remove from history)
router.delete('/:id', verifyToken, async (req, res) => {
    try {
        const order = await Order.findById(req.params.id);
        if (!order) return res.status(404).json({ message: 'Order not found' });

        if (req.userRole !== 'admin' && order.userId.toString() !== req.userId) {
            return res.status(403).json({ message: 'Access denied' });
        }

        await order.deleteOne();
        res.json({ message: 'Order deleted' });
    } catch (err) {
        res.status(500).json({ message: err.message });
    }
});

module.exports = router;
