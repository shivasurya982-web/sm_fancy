const express = require('express');
const router = express.Router();
const AppSettings = require('../models/AppSettings');
const { verifyToken, requireAdmin } = require('../middleware/auth');

// GET /api/settings
router.get('/', async (req, res) => {
  try {
    let settings = await AppSettings.findOne();
    if (!settings) {
      settings = await AppSettings.create({
        onboardingBanners: [
          {
            title: 'Elegance in Every Detail',
            description: 'Discover luxury crafted with precision.',
            image: 'https://res.cloudinary.com/demo/image/upload/v1631234567/sample.jpg'
          }
        ],
        homeBanners: [
          {
            title: 'Siva Murugan Fancy',
            description: 'Tiruchendur',
            image: 'assets/images/logo1.png'
          },
          {
            title: 'Luxury Collection',
            description: 'Exclusive Jewellery',
            image: 'assets/images/banner4.jpg'
          },
          {
            title: 'Special Deals',
            description: 'Premium Accessories',
            image: 'assets/images/banner5.jpg'
          }
        ],
        upiQrCode: '',
        upiId: '',
        localCity: 'Tiruchendur',
        localShippingFee: 50,
        standardShippingFee: 100,
        ownerPhone: '9443039600',
        shopImage: 'assets/images/logo.png',
        shopDescription: 'Exquisite Jewellery & Fancy Collections since 1995. Quality and trust guaranteed.'
      });
    }
    res.json(settings);
  } catch (err) {
    res.status(500).json({ message: err.message });
  }
});

// Update settings (Admin only)
router.post('/', verifyToken, requireAdmin, async (req, res) => {
  try {
    let settings = await AppSettings.findOne();
    if (settings) {
      Object.assign(settings, req.body);
      await settings.save();
    } else {
      settings = await AppSettings.create(req.body);
    }
    res.json(settings);
  } catch (err) {
    res.status(500).json({ message: err.message });
  }
});

module.exports = router;
