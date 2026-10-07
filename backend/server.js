require('dotenv').config();
const express = require('express');
const http = require('http');
const { Server } = require('socket.io');
const mongoose = require('mongoose');
const dns = require('dns');
const cors = require('cors');
const helmet = require('helmet');

// ─── DNS FIX FOR MONGODB ATLAS ──────────────────────────────────────────────
try {
  dns.setServers(['8.8.8.8', '8.8.4.4']);
  console.log('DNS: Using Google resolvers for stability.');
} catch (e) {}

console.log('ENV FILE LOADED');

const app = express();
const server = http.createServer(app);

const io = new Server(server, {
  cors: { origin: '*', methods: ['GET', 'POST'] },
});

const PORT = process.env.PORT || 5050;
const MONGODB_URI = process.env.MONGODB_URI;

if (!MONGODB_URI) {
  console.error('CRITICAL: MONGODB_URI is missing!');
  process.exit(1);
}

// ─── Middleware ───────────────────────────────────────────────────────────────
app.use(helmet({ contentSecurityPolicy: false }));
app.use(cors({ origin: '*' }));
app.use(express.json({
  limit: '10mb',
  verify: (req, res, buf) => {
    req.rawBody = buf;
  }
}));
app.use(express.urlencoded({ extended: true }));

// Check DB Connection Middleware
let isDBConnected = false;

app.use((req, res, next) => {
  // Allow health check without DB
  if (req.path === '/api/health') return next();

  if (!isDBConnected && req.path.startsWith('/api')) {
    return res.status(503).json({
        message: 'Database is currently connecting or unavailable. Please retry in 10 seconds.',
        retryAfter: 10
    });
  }
  next();
});

app.use((req, res, next) => {
  console.log(`[${new Date().toLocaleTimeString()}] ${req.method} ${req.originalUrl}`);
  next();
});

// ─── Route Imports ──────────────────────────────────────────────────────────
const { router: authRouter } = require('./routes/auth');
const productsRouter = require('./routes/products');
const cartRouter = require('./routes/cart');
const ordersRouter = require('./routes/orders');
const chatRouter = require('./routes/chat');
const analyticsRouter = require('./routes/analytics');
const usersRouter = require('./routes/users');
const couponsRouter = require('./routes/coupons');
const reviewsRouter = require('./routes/reviews');
const { router: notificationsRouter } = require('./routes/notifications');
const paymentsRouter = require('./routes/payments');
const dashboardRoutes = require('./routes/dashboard');
const uploadRoutes = require('./routes/upload');
const appSettingsRouter = require('./routes/appSettings');
const complaintsRouter = require('./routes/complaints');
const categoryRoutes = require('./routes/categoryRoutes');
const returnsRouter = require('./routes/returns');
const addressRouter = require('./routes/addresses');

// ─── API Registration ───────────────────────────────────────────────────────
app.use('/api/auth', authRouter);
app.use('/api/products', productsRouter);
app.use('/api/cart', cartRouter);
app.use('/api/orders', ordersRouter);
app.use('/api/chat', chatRouter);
app.use('/api/analytics', analyticsRouter);
app.use('/api/users', usersRouter);
app.use('/api/coupons', couponsRouter);
app.use('/api/reviews', reviewsRouter);
app.use('/api/notifications', notificationsRouter);
app.use('/api/payments', paymentsRouter);
app.use('/api/dashboard', dashboardRoutes);
app.use('/api/upload', uploadRoutes);
app.use('/api/settings', appSettingsRouter);
app.use('/api/complaints', complaintsRouter);
app.use('/api/categories', categoryRoutes);
app.use('/api/returns', returnsRouter);
app.use('/api/addresses', addressRouter);

app.get('/api/health', (req, res) => res.json({ status: 'OK', db: isDBConnected }));

// ─── Database & Server Start ────────────────────────────────────────────────
const seedData = require('./seed');

mongoose.connection.on('connected', () => {
  isDBConnected = true;
  console.log('✅ Connected to MongoDB Atlas');
});

mongoose.connection.on('error', (err) => {
  isDBConnected = false;
  console.error('❌ MongoDB Error:', err.message);
});

mongoose.connection.on('disconnected', () => {
  isDBConnected = true; // Set to false ONLY if we want to block requests
  // We keep it true here to let mongoose auto-reconnect attempt
  console.log('⚠️ MongoDB Disconnected. Reconnecting...');
});

const connectDB = async (retryCount = 0) => {
  try {
    console.log(`Connecting to DB (Attempt ${retryCount + 1})...`);
    await mongoose.connect(MONGODB_URI, {
      family: 4, // Force IPv4
      serverSelectionTimeoutMS: 30000,
      connectTimeoutMS: 30000,
      socketTimeoutMS: 45000,
    });

    // Seed in background, don't await to avoid blocking server if network resets
    seedData().then(() => {
        console.log('DB Seeding check complete.');
    }).catch(e => {
        console.error('Non-critical seed error:', e.message);
    });

  } catch (err) {
    isDBConnected = false;
    console.error(`❌ DB Connection Failed:`, err.message);
    const nextRetry = Math.min(30000, 5000 * (retryCount + 1));
    console.log(`Retrying in ${nextRetry/1000} seconds...`);
    setTimeout(() => connectDB(retryCount + 1), nextRetry);
  }
};

connectDB();

app.get('/', (req, res) => {
  res.json({
    success: true,
    message: 'SM Fancy Backend is running',
    environment: process.env.NODE_ENV || 'development'
  });
});

let currentPort = PORT;

server.on('error', (err) => {
  if (err.code === 'EADDRINUSE') {
    console.warn(`⚠️ Port ${currentPort} is already in use. Retrying on port ${Number(currentPort) + 1}...`);
    currentPort = Number(currentPort) + 1;
    setTimeout(() => {
      server.listen(currentPort, '0.0.0.0');
    }, 500);
  } else {
    console.error('Server error:', err);
  }
});

server.listen(currentPort, '0.0.0.0', () => {
  console.log(`🚀 FancyWorld API online on port ${currentPort}`);
  try {
    const { startPendingPaymentRetryJob } = require('./routes/payments');
    startPendingPaymentRetryJob(app);
  } catch (e) {
    console.error('Failed to start retry job:', e.message);
  }
});

app.set('io', io);
