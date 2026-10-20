const express = require('express');
const router = express.Router();
const Product = require('../models/Product');
const { verifyToken, requireAdmin, optionalAuth } = require('../middleware/auth');
const { upload, uploadToCloudinary, deleteFromCloudinary } = require('../middleware/upload');

// GET /api/products - List with filter, search, pagination
router.get('/', optionalAuth, async (req, res) => {
  try {
    const {
      category, search, sort = 'newest', page = 1, limit = 30,
      isFeatured, isNewArrival, isTrending, isFlashSale, minPrice, maxPrice,
      excludeId,
    } = req.query;

    const query = {};
    if (category && category !== 'All') query.category = category;
    if (excludeId) query._id = { $ne: excludeId };
    if (search) {
      query.$text = { $search: search };
    }
    if (isFeatured === 'true') query.isFeatured = true;
    if (isNewArrival === 'true') query.isNewArrival = true;
    if (isTrending === 'true') query.isTrending = true;
    if (isFlashSale === 'true') query.isFlashSale = true;
    if (minPrice || maxPrice) {
      query.price = {};
      if (minPrice) query.price.$gte = Number(minPrice);
      if (maxPrice) query.price.$lte = Number(maxPrice);
    }

    const sortMap = {
      relevance: { score: { $meta: 'textScore' } },
      newest: { createdAt: -1 },
      oldest: { createdAt: 1 },
      'price-asc': { price: 1 },
      'price-desc': { price: -1 },
      rating: { averageRating: -1 },
    };

    const products = await Product.find(query, search ? { score: { $meta: 'textScore' } } : {})
      .sort(search && !req.query.sort ? sortMap.relevance : (sortMap[sort] || { createdAt: -1 }))
      .skip((page - 1) * Number(limit))
      .limit(Number(limit))
      .lean();

    const total = await Product.countDocuments(query);

    res.json({ products, total, page: Number(page), pages: Math.ceil(total / Number(limit)) });
  } catch (err) {
    res.status(500).json({ message: err.message });
  }
});

// GET /api/products/:id - Single product
router.get('/:id', async (req, res) => {
  try {
    const product = await Product.findById(req.params.id).lean();
    if (!product) return res.status(404).json({ message: 'Product not found' });
    res.json(product);
  } catch (err) {
    res.status(500).json({ message: err.message });
  }
});

// POST /api/products - Admin: create product (with image upload)
router.post('/', verifyToken, requireAdmin, upload.array('images', 5), async (req, res) => {
  try {
    const imageUrls = [];
    const imagePublicIds = [];

    if (req.files && req.files.length > 0) {
      const uploadResults = await Promise.all(
        req.files.map((file) => uploadToCloudinary(file.buffer, 'fancyworld/products'))
      );
      for (const result of uploadResults) {
        imageUrls.push(result.secure_url);
        imagePublicIds.push(result.public_id);
      }
    }

    const product = new Product({
      ...req.body,
      images: imageUrls,
      imageUrl: imageUrls[0] || req.body.imageUrl || '',
      imagePublicIds,
      variants: req.body.variants ? JSON.parse(req.body.variants) : [],
    });

    await product.save();
    res.status(201).json(product);
  } catch (err) {
    res.status(400).json({ message: err.message });
  }
});

// PUT /api/products/:id - Admin: update product
router.put('/:id', verifyToken, requireAdmin, upload.array('images', 5), async (req, res) => {
  try {
    const product = await Product.findById(req.params.id);
    if (!product) return res.status(404).json({ message: 'Product not found' });

    if (req.files && req.files.length > 0) {
      const uploadResults = await Promise.all(
        req.files.map((file) => uploadToCloudinary(file.buffer, 'fancyworld/products'))
      );
      const imageUrls = uploadResults.map((res) => res.secure_url);
      const imagePublicIds = uploadResults.map((res) => res.public_id);

      product.images = [...product.images, ...imageUrls];
      product.imagePublicIds = [...product.imagePublicIds, ...imagePublicIds];
      if (!product.imageUrl) product.imageUrl = imageUrls[0];
    }

    Object.assign(product, req.body);
    if (req.body.variants) product.variants = JSON.parse(req.body.variants);
    await product.save();
    res.json(product);
  } catch (err) {
    res.status(500).json({ message: err.message });
  }
});

// DELETE /api/products/:id - Admin: delete product
router.delete('/:id', verifyToken, requireAdmin, async (req, res) => {
  try {
    const product = await Product.findById(req.params.id);
    if (!product) return res.status(404).json({ message: 'Product not found' });

    // Delete images from Cloudinary
    for (const publicId of product.imagePublicIds || []) {
      await deleteFromCloudinary(publicId);
    }

    await product.deleteOne();
    res.json({ message: 'Product deleted' });
  } catch (err) {
    res.status(500).json({ message: err.message });
  }
});

module.exports = router;
