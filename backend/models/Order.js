const mongoose = require('mongoose');

const orderItemSchema = new mongoose.Schema({
  product: { type: mongoose.Schema.Types.ObjectId, ref: 'Product', required: true },
  name: { type: String, required: true },
  image: { type: String },
  price: { type: Number, required: true },
  quantity: { type: Number, required: true, min: 1 },
  variant: { type: String },
});

const trackingTimelineSchema = new mongoose.Schema({
  status: { type: String, required: true },
  message: { type: String },
  timestamp: { type: Date, default: Date.now },
  isCompleted: { type: Boolean, default: false },
});

const orderSchema = new mongoose.Schema(
  {
    userId: { type: mongoose.Schema.Types.ObjectId, ref: 'User', required: true },
    orderNumber: { type: String, unique: true },

    items: [orderItemSchema],

    // Pricing
    subtotal: { type: Number, required: true },
    discount: { type: Number, default: 0 },
    couponCode: { type: String },
    couponDiscount: { type: Number, default: 0 },
    shipping: { type: Number, default: 0 },
    tax: { type: Number, default: 0 },
    total: { type: Number, required: true },

    // Payment
    paymentMethod: {
      type: String,
      enum: ['COD', 'UPI', 'Razorpay', 'Card', 'Wallet'],
      default: 'COD',
    },
    paymentStatus: {
      type: String,
      enum: ['Pending', 'Awaiting Verification', 'Paid', 'Failed', 'Refunded', 'WRONG', 'Cancelled', 'Needs Review'],
      default: 'Pending',
    },
    upiTransactionId: { type: String },
    upiReferenceNo: { type: String },
    paymentServerOrderId: { type: String },
    razorpayOrderId: { type: String },
    razorpayPaymentId: { type: String },
    razorpaySignature: { type: String },
    amountToPay: { type: Number },
    paymentVerifiedBy: { type: mongoose.Schema.Types.ObjectId, ref: 'User' },
    paymentDetails: { type: Object },

    // Delivery address snapshot
    address: {
      fullName: String,
      phone: String,
      addressLine1: String,
      addressLine2: String,
      city: String,
      state: String,
      pincode: String,
      country: { type: String, default: 'India' },
    },

    // Status
    status: {
      type: String,
      enum: ['Placed', 'Confirmed', 'Processing', 'Packed', 'Shipped', 'Out for Delivery', 'Delivered', 'Cancelled', 'Return Requested', 'Returned', 'Refunded'],
      default: 'Placed',
    },

    // Tracking
    customerLiveLocation: {
        latitude: Number,
        longitude: Number,
    },
    trackingId: { type: String },
    estimatedDelivery: { type: Date },
    deliveredAt: { type: Date },
    timeline: [trackingTimelineSchema],

    // Return / Refund
    returnReason: { type: String },
    returnRequestedAt: { type: Date },
    refundAmount: { type: Number },
    refundInitiatedAt: { type: Date },

    // Invoice
    invoiceUrl: { type: String },

    notes: { type: String },
  },
  { timestamps: true }
);

// Helper function for guaranteed unique OTP-style verification order number (e.g. FW-849201)
async function generateUniqueOrderNumber() {
  for (let attempt = 0; attempt < 20; attempt++) {
    const otpCode = Math.floor(100000 + Math.random() * 900000);
    const candidate = `FW-${otpCode}`;
    const exists = await mongoose.model('Order').exists({ orderNumber: candidate });
    if (!exists) {
      return candidate;
    }
  }
  const fallbackOtp = Date.now().toString().slice(-6);
  return `FW-${fallbackOtp}`;
}

// Auto-generate order number reliably and uniquely before saving
orderSchema.pre('save', async function (next) {
  if (!this.orderNumber) {
    try {
      this.orderNumber = await generateUniqueOrderNumber();
    } catch (e) {
      const fallbackOtp = Date.now().toString().slice(-6);
      this.orderNumber = `FW-${fallbackOtp}`;
    }
  }
  next();
});

module.exports = mongoose.model('Order', orderSchema);
module.exports.generateUniqueOrderNumber = generateUniqueOrderNumber;
