console.log('UPLOAD ROUTE LOADED');
const express = require('express');
const { upload, uploadToCloudinary } = require('../middleware/upload');
const { verifyToken } = require('../middleware/auth');

const router = express.Router();

router.post(
  '/',
  verifyToken,
  upload.single('image'),
  async (req, res) => {
    try {
      if (!req.file) {
        return res.status(400).json({
          message: 'No image uploaded',
        });
      }

      const result = await uploadToCloudinary(req.file.buffer, 'fancyworld/products');

      res.json({
        imageUrl: result.secure_url,
      });
    } catch (err) {
      console.error("UPLOAD ERROR:", err);
      res.status(500).json({
        message: err.message,
      });
    }
  }
);

module.exports = router;