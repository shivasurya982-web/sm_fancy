import 'dart:ui';
import 'package:flutter/material.dart';
import 'package:cached_network_image/cached_network_image.dart';
import 'package:flutter_animate/flutter_animate.dart';
import 'package:intl/intl.dart';
import 'package:image_picker/image_picker.dart';
import '../models/product_model.dart';
import '../services/cart_service.dart';
import '../services/wishlist_service.dart';
import '../models/wishlist_item.dart';
import '../services/api_service.dart';
import '../services/user_service.dart';
import '../services/product_service.dart';
import '../services/review_service.dart';
import '../services/upload_service.dart';
import '../config/theme.dart';
import '../widgets/gold_button.dart';
import '../widgets/product_card.dart';
import '../widgets/image_viewer.dart';
import '../widgets/glass_toast.dart';
import 'checkout_screen.dart';
import 'login_screen.dart';

class ProductDetailsScreen extends StatefulWidget {
  final ProductModel product;

  const ProductDetailsScreen({super.key, required this.product});

  @override
  State<ProductDetailsScreen> createState() => _ProductDetailsScreenState();
}

class _ProductDetailsScreenState extends State<ProductDetailsScreen> {
  int _selectedQty = 1;
  bool _isAdding = false;
  int _activeImgIdx = 0;
  List<ProductModel> _relatedProducts = [];
  bool _isLoadingRelated = true;

  List<ReviewModel> _reviews = [];
  int _totalReviews = 0;
  double _avgRating = 5.0;
  bool _isLoadingReviews = true;
  bool _canReview = false;
  String? _eligibleOrderId;

  @override
  void initState() {
    super.initState();
    UserService.addToRecentlyViewed(widget.product.id);
    _loadRelatedProducts();
    _loadReviews();
  }

  @override
  void didUpdateWidget(ProductDetailsScreen oldWidget) {
    super.didUpdateWidget(oldWidget);
    if (oldWidget.product.id != widget.product.id) {
      _selectedQty = 1;
      _activeImgIdx = 0;
      _loadRelatedProducts();
      _loadReviews();
    }
  }

  Future<void> _loadRelatedProducts() async {
    setState(() => _isLoadingRelated = true);
    try {
      final products = await ProductService.fetchProducts(
        category: widget.product.category,
        excludeId: widget.product.id,
      );
      if (mounted) {
        setState(() {
          _relatedProducts = products;
          _isLoadingRelated = false;
        });
      }
    } catch (e) {
      if (mounted) setState(() => _isLoadingRelated = false);
    }
  }

  Future<void> _loadReviews() async {
    setState(() => _isLoadingReviews = true);
    try {
      final data = await ReviewService.fetchReviews(widget.product.id);
      if (mounted) {
        final list = data['reviews'] as List<ReviewModel>? ?? [];
        final total = data['total'] as int? ?? list.length;
        double avg = 5.0;
        if (list.isNotEmpty) {
          final sum = list.fold<int>(0, (acc, r) => acc + r.rating);
          avg = sum / list.length;
        }
        setState(() {
          _reviews = list;
          _totalReviews = total;
          _avgRating = avg;
          _isLoadingReviews = false;
        });
      }
      if (ApiService.isLoggedIn) {
        final elig = await ReviewService.checkEligibility(widget.product.id);
        if (mounted) {
          setState(() {
            _canReview = elig['canReview'] == true;
            _eligibleOrderId = elig['orderId']?.toString();
          });
        }
      }
    } catch (_) {
      if (mounted) setState(() => _isLoadingReviews = false);
    }
  }

  bool _checkAuth() {
    if (!ApiService.isLoggedIn) {
      _showLoginPrompt();
      return false;
    }
    return true;
  }

  void _showLoginPrompt() {
    showDialog(
      context: context,
      builder: (ctx) => AlertDialog(
        backgroundColor: AppTheme.deepCharcoal,
        shape: RoundedRectangleBorder(
            borderRadius: BorderRadius.circular(30),
            side: const BorderSide(color: AppTheme.platinumBorder)),
        title: const Text('LOGIN REQUIRED', style: TextStyle(fontSize: 14, fontWeight: FontWeight.w900, letterSpacing: 1)),
        content: const Text('Please login to explore more.',
            style: TextStyle(color: AppTheme.coolGrey)),
        actions: [
          TextButton(
              onPressed: () => Navigator.pop(ctx),
              child: const Text('DISMISS',
                  style: TextStyle(color: AppTheme.coolGrey))),
          ElevatedButton(
            onPressed: () {
              Navigator.pop(ctx);
              Navigator.pushReplacement(context,
                  MaterialPageRoute(builder: (_) => const LoginScreen()));
            },
            child: const Text('LOG IN'),
          ),
        ],
      ),
    );
  }

  void _showRatingDialog() {
    int selectedRating = 5;
    final reviewCtrl = TextEditingController();
    List<String> reviewImageUrls = [];
    bool isUploadingImage = false;
    bool isSubmitting = false;

    showModalBottomSheet(
      context: context,
      isScrollControlled: true,
      backgroundColor: Colors.transparent,
      builder: (ctx) => StatefulBuilder(
        builder: (ctx, setSheetState) => Container(
          constraints: BoxConstraints(maxHeight: MediaQuery.of(ctx).size.height * 0.85),
          padding: EdgeInsets.fromLTRB(24, 24, 24, MediaQuery.of(ctx).viewInsets.bottom + 24),
          decoration: const BoxDecoration(
            color: AppTheme.deepCharcoal,
            borderRadius: BorderRadius.vertical(top: Radius.circular(30)),
            border: Border(top: BorderSide(color: AppTheme.glassBorder, width: 0.5)),
          ),
          child: SingleChildScrollView(
            child: Column(
              mainAxisSize: MainAxisSize.min,
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                Center(child: Container(width: 40, height: 4, decoration: BoxDecoration(color: Colors.white10, borderRadius: BorderRadius.circular(2)))),
                const SizedBox(height: 20),
                Text('RATE & REVIEW', style: Theme.of(context).textTheme.headlineLarge?.copyWith(fontSize: 18, letterSpacing: 1.5)),
                const SizedBox(height: 8),
                Text(widget.product.name.toUpperCase(), style: const TextStyle(color: AppTheme.coolGrey, fontSize: 11, fontWeight: FontWeight.bold)),
                const SizedBox(height: 20),
                
                // Star Rating Picker
                Center(
                  child: Row(
                    mainAxisAlignment: MainAxisAlignment.center,
                    children: List.generate(5, (idx) {
                      final starNum = idx + 1;
                      return IconButton(
                        iconSize: 32,
                        icon: Icon(
                          starNum <= selectedRating ? Icons.star_rounded : Icons.star_border_rounded,
                          color: starNum <= selectedRating ? Colors.amber : AppTheme.coolGrey,
                        ),
                        onPressed: () {
                          setSheetState(() => selectedRating = starNum);
                        },
                      );
                    }),
                  ),
                ),

                const SizedBox(height: 16),
                const Padding(
                  padding: EdgeInsets.only(left: 4, bottom: 8),
                  child: Text('YOUR REVIEW', style: TextStyle(color: Colors.white60, fontSize: 9, fontWeight: FontWeight.w900, letterSpacing: 2)),
                ),
                TextField(
                  controller: reviewCtrl,
                  maxLines: 4,
                  style: const TextStyle(color: AppTheme.polishedSilver, fontSize: 13),
                  decoration: InputDecoration(
                    hintText: 'Share your experience with this piece...',
                    hintStyle: const TextStyle(color: Colors.white24),
                    contentPadding: const EdgeInsets.all(18),
                    border: OutlineInputBorder(borderRadius: BorderRadius.circular(20), borderSide: const BorderSide(color: AppTheme.glassBorder)),
                  ),
                ),

                const SizedBox(height: 16),
                const Padding(
                  padding: EdgeInsets.only(left: 4, bottom: 8),
                  child: Text('ATTACH PHOTOS', style: TextStyle(color: Colors.white60, fontSize: 9, fontWeight: FontWeight.w900, letterSpacing: 2)),
                ),

                if (reviewImageUrls.isNotEmpty) ...[
                  SizedBox(
                    height: 70,
                    child: ListView.builder(
                      scrollDirection: Axis.horizontal,
                      itemCount: reviewImageUrls.length,
                      itemBuilder: (ctx, i) => Container(
                        margin: const EdgeInsets.only(right: 10),
                        width: 70,
                        height: 70,
                        decoration: BoxDecoration(
                          borderRadius: BorderRadius.circular(12),
                          border: Border.all(color: AppTheme.glassBorder),
                          image: DecorationImage(image: NetworkImage(reviewImageUrls[i]), fit: BoxFit.cover),
                        ),
                        child: Align(
                          alignment: Alignment.topRight,
                          child: GestureDetector(
                            onTap: () {
                              setSheetState(() { reviewImageUrls.removeAt(i); });
                            },
                            child: Container(
                              padding: const EdgeInsets.all(4),
                              decoration: const BoxDecoration(color: AppTheme.error, shape: BoxShape.circle),
                              child: const Icon(Icons.close, size: 12, color: Colors.white),
                            ),
                          ),
                        ),
                      ),
                    ),
                  ),
                  const SizedBox(height: 12),
                ],

                OutlinedButton.icon(
                  onPressed: isUploadingImage ? null : () async {
                    final picker = ImagePicker();
                    final img = await picker.pickImage(
                      source: ImageSource.gallery,
                      imageQuality: 70,
                      maxWidth: 1024,
                      maxHeight: 1024,
                    );
                    if (img != null) {
                      setSheetState(() => isUploadingImage = true);
                      final url = await UploadService.uploadImage(img);
                      if (url != null) {
                        setSheetState(() { reviewImageUrls.add(url); });
                      }
                      setSheetState(() => isUploadingImage = false);
                    }
                  },
                  icon: isUploadingImage 
                    ? const SizedBox(width: 16, height: 16, child: CircularProgressIndicator(strokeWidth: 2, color: AppTheme.brushedPlatinum))
                    : const Icon(Icons.add_a_photo_outlined, size: 18),
                  label: Text(isUploadingImage ? 'UPLOADING...' : 'ADD PHOTO', style: const TextStyle(fontSize: 10, letterSpacing: 1, fontWeight: FontWeight.bold)),
                ),

                const SizedBox(height: 28),
                GoldButton(
                  label: 'SUBMIT REVIEW',
                  isLoading: isSubmitting,
                  onPressed: isSubmitting ? null : () async {
                    if (reviewCtrl.text.trim().isEmpty) {
                      showGlassToast(ctx, 'Please write a short review.', isError: true);
                      return;
                    }
                    setSheetState(() => isSubmitting = true);
                    try {
                      await ReviewService.submitReview(
                        productId: widget.product.id,
                        orderId: _eligibleOrderId,
                        rating: selectedRating,
                        review: reviewCtrl.text.trim(),
                        images: reviewImageUrls,
                      );
                      if (ctx.mounted) {
                        Navigator.pop(ctx);
                        showGlassToast(context, 'Thank you! Your review has been submitted.', isError: false, title: 'REVIEW SUBMITTED');
                        _loadReviews();
                      }
                    } catch (e) {
                      if (ctx.mounted) {
                        final msg = e.toString().replaceFirst('Exception: ', '').replaceFirst('Error: ', '');
                        showGlassToast(ctx, msg, isError: true);
                      }
                    } finally {
                      if (ctx.mounted) setSheetState(() => isSubmitting = false);
                    }
                  },
                ),
                const SizedBox(height: 16),
              ],
            ),
          ),
        ),
      ),
    );
  }

  @override
  Widget build(BuildContext context) {
    final double screenWidth = MediaQuery.of(context).size.width;
    final bool isWide = screenWidth > 900;

    return Scaffold(
      backgroundColor: AppTheme.deepCharcoal,
      body: Container(
        decoration: AppTheme.filigreeBackground(),
        child: isWide ? _buildWideLayout() : _buildMobileLayout(),
      ),
    );
  }

  Widget _buildWideLayout() {
    final p = widget.product;
    final isLiked = WishlistService.isWishlisted(p.id);

    return Column(
      children: [
        SafeArea(
          child: Padding(
            padding: const EdgeInsets.symmetric(horizontal: 40, vertical: 10),
            child: Row(
              mainAxisAlignment: MainAxisAlignment.spaceBetween,
              children: [
                _buildCircularBtn(Icons.arrow_back_ios_new_rounded, () => Navigator.pop(context)),
                _buildCircularBtn(
                  isLiked ? Icons.favorite_rounded : Icons.favorite_border_rounded,
                  () async {
                    if (isLiked) {
                      await WishlistService.removeFromWishlist(p.id);
                    } else {
                      await WishlistService.addToWishlist(WishlistItem(productId: p.id, name: p.name, image: p.image, price: p.price));
                    }
                    setState(() {});
                  },
                  color: isLiked ? Colors.redAccent : AppTheme.brushedPlatinum,
                ),
              ],
            ),
          ),
        ),

        Expanded(
          child: SingleChildScrollView(
            padding: const EdgeInsets.symmetric(horizontal: 40),
            child: Column(
              children: [
                Row(
                  crossAxisAlignment: CrossAxisAlignment.start,
                  children: [
                    Expanded(
                      flex: 1,
                      child: Container(
                        height: 550,
                        decoration: BoxDecoration(
                          borderRadius: BorderRadius.circular(32),
                          border: Border.all(color: AppTheme.glassBorder),
                        ),
                        child: ClipRRect(
                          borderRadius: BorderRadius.circular(32),
                          child: Stack(
                            fit: StackFit.expand,
                            children: [
                              PageView.builder(
                                itemCount: p.images.isNotEmpty ? p.images.length : 1,
                                onPageChanged: (v) => setState(() => _activeImgIdx = v),
                                itemBuilder: (ctx, idx) => _buildHeroImage(p.images.isNotEmpty ? p.images[idx] : p.image),
                              ),
                              if (p.images.length > 1)
                                Positioned(
                                  bottom: 24, left: 0, right: 0,
                                  child: Row(
                                    mainAxisAlignment: MainAxisAlignment.center,
                                    children: List.generate(p.images.length, (idx) => _buildPageIndicator(idx == _activeImgIdx)),
                                  ),
                                ),
                            ],
                          ),
                        ),
                      ),
                    ),
                    const SizedBox(width: 48),
                    Expanded(
                      flex: 1,
                      child: Column(
                        crossAxisAlignment: CrossAxisAlignment.start,
                        children: [
                          _buildHeaderSection(),
                          const SizedBox(height: 32),
                          _buildDescriptionAndSpecs(),
                          const SizedBox(height: 48),
                          _buildPurchaseSection(),
                        ],
                      ),
                    ),
                  ],
                ),
                const SizedBox(height: 60),
                _buildReviewsSection(),
                const SizedBox(height: 60),
                _buildRelatedProductsSection(),
                const SizedBox(height: 100),
              ],
            ),
          ),
        ),
      ],
    );
  }

  Widget _buildMobileLayout() {
    final p = widget.product;
    final isLiked = WishlistService.isWishlisted(p.id);
    final double screenWidth = MediaQuery.of(context).size.width;
    final bool isNarrow = screenWidth < 360;

    return CustomScrollView(
      slivers: [
        SliverAppBar(
          expandedHeight: isNarrow ? 260 : 320,
          pinned: true,
          stretch: true,
          backgroundColor: Colors.transparent,
          leading: Padding(
            padding: const EdgeInsets.all(8.0),
            child: _buildCircularBtn(Icons.arrow_back_ios_new_rounded, () => Navigator.pop(context), size: 18),
          ),
          actions: [
            Padding(
              padding: const EdgeInsets.all(8.0),
              child: _buildCircularBtn(
                isLiked ? Icons.favorite_rounded : Icons.favorite_border_rounded,
                () async {
                  if (!_checkAuth()) return;
                  if (isLiked) {
                    await WishlistService.removeFromWishlist(p.id);
                  } else {
                    await WishlistService.addToWishlist(WishlistItem(productId: p.id, name: p.name, image: p.image, price: p.price));
                  }
                  setState(() {});
                },
                color: isLiked ? Colors.redAccent : AppTheme.brushedPlatinum,
                size: 20,
              ),
            ),
            const SizedBox(width: 8),
          ],
          flexibleSpace: FlexibleSpaceBar(
            background: Stack(
              fit: StackFit.expand,
              children: [
                PageView.builder(
                  itemCount: p.images.isNotEmpty ? p.images.length : 1,
                  onPageChanged: (v) => setState(() => _activeImgIdx = v),
                  itemBuilder: (ctx, idx) => _buildHeroImage(p.images.isNotEmpty ? p.images[idx] : p.image),
                ),
                if (p.images.length > 1)
                  Positioned(
                    bottom: 40, left: 0, right: 0,
                    child: Row(
                      mainAxisAlignment: MainAxisAlignment.center,
                      children: List.generate(p.images.length, (idx) => _buildPageIndicator(idx == _activeImgIdx)),
                    ),
                  ),
              ],
            ),
          ),
        ),
        SliverToBoxAdapter(
          child: Transform.translate(
            offset: const Offset(0, -30),
            child: Container(
              padding: EdgeInsets.fromLTRB(isNarrow ? 16 : 24, 32, isNarrow ? 16 : 24, 40),
              decoration: BoxDecoration(
                color: AppTheme.deepCharcoal.withValues(alpha: 0.95),
                borderRadius: const BorderRadius.vertical(top: Radius.circular(40)),
                border: Border.all(color: AppTheme.glassBorder, width: 1),
              ),
              child: Column(
                crossAxisAlignment: CrossAxisAlignment.start,
                children: [
                  _buildHeaderSection(),
                  const SizedBox(height: 24),
                  _buildDescriptionAndSpecs(),
                  const SizedBox(height: 28),
                  _buildPurchaseSection(),
                  const SizedBox(height: 36),
                  _buildReviewsSection(),
                  const SizedBox(height: 40),
                  _buildRelatedProductsSection(),
                  const SizedBox(height: 80),
                ],
              ),
            ),
          ),
        ),
      ],
    );
  }

  Widget _buildHeaderSection() {
    final p = widget.product;
    final double screenWidth = MediaQuery.of(context).size.width;
    final bool isNarrow = screenWidth < 360;

    return Column(
      crossAxisAlignment: CrossAxisAlignment.start,
      children: [
        Row(
          mainAxisAlignment: MainAxisAlignment.spaceBetween,
          children: [
            Text(p.category.toUpperCase(), style: const TextStyle(color: AppTheme.coolGrey, fontSize: 10, letterSpacing: 2, fontWeight: FontWeight.w900)),
            Row(
              children: [
                const Icon(Icons.star_rounded, color: Colors.amber, size: 14),
                const SizedBox(width: 4),
                Text(
                  _avgRating.toStringAsFixed(1),
                  style: const TextStyle(color: Colors.white, fontSize: 11, fontWeight: FontWeight.bold),
                ),
                Text(
                  ' ($_totalReviews)',
                  style: const TextStyle(color: AppTheme.coolGrey, fontSize: 10),
                ),
              ],
            ),
          ],
        ),
        const SizedBox(height: 10),
        Row(
          mainAxisAlignment: MainAxisAlignment.spaceBetween,
          crossAxisAlignment: CrossAxisAlignment.center,
          children: [
            Expanded(
              child: Text(
                p.name.toUpperCase(), 
                maxLines: 2,
                overflow: TextOverflow.ellipsis,
                style: TextStyle(fontSize: isNarrow ? 20 : 22, fontWeight: FontWeight.w900, color: AppTheme.polishedSilver, letterSpacing: 1, height: 1.1),
              ),
            ),
            const SizedBox(width: 12),
            Text(
              '₹${p.price.toStringAsFixed(0)}', 
              style: TextStyle(fontSize: isNarrow ? 20 : 22, fontWeight: FontWeight.w300, color: AppTheme.brushedPlatinum, letterSpacing: -0.5),
            ),
          ],
        ),
      ],
    );
  }

  Widget _buildDescriptionAndSpecs() {
    final p = widget.product;
    final hasSpecs = (p.metalType != null && p.metalType!.isNotEmpty) ||
                     (p.purity != null && p.purity!.isNotEmpty) ||
                     (p.weight != null && p.weight!.isNotEmpty) ||
                     (p.stoneInfo != null && p.stoneInfo!.isNotEmpty);

    return Column(
      crossAxisAlignment: CrossAxisAlignment.start,
      children: [
        if (p.description.isNotEmpty) ...[
          const Text('DESCRIPTION', style: TextStyle(color: Colors.white, fontSize: 10, fontWeight: FontWeight.w900, letterSpacing: 2)),
          const SizedBox(height: 10),
          Text(p.description, style: const TextStyle(color: AppTheme.coolGrey, height: 1.5, fontSize: 13)),
        ],
        if (hasSpecs) ...[
          const SizedBox(height: 24),
          const Divider(color: AppTheme.glassBorder, thickness: 1),
          const SizedBox(height: 20),
          const Text('SPECIFICATIONS', style: TextStyle(color: Colors.white, fontSize: 10, fontWeight: FontWeight.w900, letterSpacing: 2)),
          const SizedBox(height: 14),
          if (p.metalType != null && p.metalType!.isNotEmpty) _buildSpecRow('METAL', p.metalType!),
          if (p.purity != null && p.purity!.isNotEmpty) _buildSpecRow('PURITY', p.purity!),
          if (p.weight != null && p.weight!.isNotEmpty) _buildSpecRow('WEIGHT', p.weight!),
          if (p.stoneInfo != null && p.stoneInfo!.isNotEmpty) _buildSpecRow('STONES', p.stoneInfo!),
        ],
      ],
    );
  }

  Widget _buildPurchaseSection() {
    final p = widget.product;
    if (p.stock <= 0) return const Center(child: Text('UNAVAILABLE', style: TextStyle(color: AppTheme.error, fontWeight: FontWeight.w900, letterSpacing: 2)));

    return Column(
      crossAxisAlignment: CrossAxisAlignment.start,
      children: [
        Row(
          mainAxisAlignment: MainAxisAlignment.spaceBetween,
          crossAxisAlignment: CrossAxisAlignment.end,
          children: [
            Column(
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                const Text('QUANTITY', style: TextStyle(color: Colors.white, fontSize: 10, fontWeight: FontWeight.w900, letterSpacing: 2)),
                const SizedBox(height: 10),
                _buildQtyPicker(),
              ],
            ),
            Text('${p.stock} IN STOCK', style: const TextStyle(color: AppTheme.success, fontSize: 10, fontWeight: FontWeight.w900)),
          ],
        ),
        const SizedBox(height: 28),
        Row(
          children: [
            Expanded(
              flex: 1,
              child: _buildActionBtn('ADD TO CART', () async {
                setState(() => _isAdding = true);
                await CartService.addToCart(p, quantity: _selectedQty);
                if (mounted) {
                  setState(() => _isAdding = false);
                  showGlassToast(context, 'Added to Cart', isError: false, title: 'BAG UPDATED');
                }
              }, isGlass: true),
            ),
            const SizedBox(width: 12),
            Expanded(
              flex: 1,
              child: GoldButton(
                height: 52,
                label: 'BUY NOW',
                onPressed: () {
                  if (!ApiService.isLoggedIn) {
                    _showLoginPrompt();
                    return;
                  }
                  CartService.addToCart(p, quantity: _selectedQty);
                  Navigator.push(context, MaterialPageRoute(builder: (_) => const CheckoutScreen()));
                },
              ),
            ),
          ],
        ),
      ],
    );
  }

  Widget _buildReviewsSection() {
    return Column(
      crossAxisAlignment: CrossAxisAlignment.start,
      children: [
        const Divider(color: AppTheme.glassBorder, thickness: 1),
        const SizedBox(height: 24),
        Row(
          mainAxisAlignment: MainAxisAlignment.spaceBetween,
          children: [
            const Text('CUSTOMER REVIEWS', style: TextStyle(color: Colors.white, fontSize: 10, fontWeight: FontWeight.w900, letterSpacing: 2)),
            Text('$_totalReviews REVIEWS', style: const TextStyle(color: AppTheme.coolGrey, fontSize: 9, fontWeight: FontWeight.bold)),
          ],
        ),
        const SizedBox(height: 16),

        if (_canReview) ...[
          GestureDetector(
            onTap: _showRatingDialog,
            child: Container(
              width: double.infinity,
              padding: const EdgeInsets.symmetric(vertical: 14, horizontal: 20),
              decoration: BoxDecoration(
                color: AppTheme.brushedPlatinum.withValues(alpha: 0.1),
                borderRadius: BorderRadius.circular(100),
                border: Border.all(color: AppTheme.brushedPlatinum, width: 1),
              ),
              child: const Row(
                mainAxisAlignment: MainAxisAlignment.center,
                children: [
                  Icon(Icons.rate_review_outlined, color: AppTheme.brushedPlatinum, size: 16),
                  SizedBox(width: 10),
                  Text('WRITE A REVIEW FOR THIS PRODUCT', style: TextStyle(color: AppTheme.brushedPlatinum, fontWeight: FontWeight.w900, fontSize: 10, letterSpacing: 1.2)),
                ],
              ),
            ),
          ),
          const SizedBox(height: 20),
        ],

        if (_isLoadingReviews)
          const Center(child: CircularProgressIndicator(color: AppTheme.brushedPlatinum))
        else if (_reviews.isEmpty)
          Container(
            width: double.infinity,
            padding: const EdgeInsets.all(20),
            decoration: AppTheme.premiumCard(radius: 20),
            child: const Center(
              child: Text(
                'No reviews yet for this product. Delivered orders can be reviewed from the order page or here.',
                textAlign: TextAlign.center,
                style: TextStyle(color: AppTheme.coolGrey, fontSize: 11, height: 1.4),
              ),
            ),
          )
        else
          ..._reviews.map((rev) => _buildReviewCard(rev)),
      ],
    );
  }

  Widget _buildReviewCard(ReviewModel rev) {
    return Container(
      margin: const EdgeInsets.only(bottom: 12),
      padding: const EdgeInsets.all(16),
      decoration: AppTheme.premiumCard(radius: 20),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Row(
            children: [
              CircleAvatar(
                radius: 14,
                backgroundColor: Colors.white.withValues(alpha: 0.1),
                child: rev.userAvatar != null && rev.userAvatar!.isNotEmpty
                    ? ClipOval(child: CachedNetworkImage(imageUrl: rev.userAvatar!, fit: BoxFit.cover, width: 28, height: 28))
                    : Text(rev.userName.isNotEmpty ? rev.userName[0].toUpperCase() : 'C', style: const TextStyle(fontSize: 12, color: AppTheme.polishedSilver, fontWeight: FontWeight.bold)),
              ),
              const SizedBox(width: 10),
              Expanded(
                child: Column(
                  crossAxisAlignment: CrossAxisAlignment.start,
                  children: [
                    Row(
                      children: [
                        Text(rev.userName.toUpperCase(), style: const TextStyle(color: AppTheme.polishedSilver, fontWeight: FontWeight.w900, fontSize: 11)),
                        if (rev.isVerifiedPurchase) ...[
                          const SizedBox(width: 6),
                          const Icon(Icons.verified_rounded, color: AppTheme.brushedPlatinum, size: 12),
                        ],
                      ],
                    ),
                    Text(DateFormat('dd MMM yyyy').format(rev.createdAt), style: const TextStyle(color: Colors.white24, fontSize: 8)),
                  ],
                ),
              ),
              Row(
                children: List.generate(5, (idx) {
                  return Icon(
                    idx < rev.rating ? Icons.star_rounded : Icons.star_border_rounded,
                    color: idx < rev.rating ? Colors.amber : Colors.white10,
                    size: 14,
                  );
                }),
              ),
            ],
          ),
          if (rev.review.isNotEmpty) ...[
            const SizedBox(height: 10),
            Text(rev.review, style: const TextStyle(color: AppTheme.coolGrey, fontSize: 12, height: 1.4)),
          ],
          if (rev.images.isNotEmpty) ...[
            const SizedBox(height: 12),
            SizedBox(
              height: 60,
              child: ListView.builder(
                scrollDirection: Axis.horizontal,
                itemCount: rev.images.length,
                itemBuilder: (ctx, idx) => GestureDetector(
                  onTap: () {
                    FullScreenImageViewer.show(context, rev.images[idx], title: '${rev.userName}\'s Photo');
                  },
                  child: Container(
                    margin: const EdgeInsets.only(right: 8),
                    width: 60,
                    height: 60,
                    decoration: BoxDecoration(
                      borderRadius: BorderRadius.circular(10),
                      border: Border.all(color: AppTheme.glassBorder, width: 0.5),
                    ),
                    child: ClipRRect(
                      borderRadius: BorderRadius.circular(10),
                      child: CachedNetworkImage(imageUrl: rev.images[idx], fit: BoxFit.cover),
                    ),
                  ),
                ),
              ),
            ),
          ],
        ],
      ),
    );
  }

  Widget _buildRelatedProductsSection() {
    if (_isLoadingRelated) return const Center(child: CircularProgressIndicator(color: AppTheme.brushedPlatinum));
    if (_relatedProducts.isEmpty) return const SizedBox.shrink();

    return Column(
      crossAxisAlignment: CrossAxisAlignment.start,
      children: [
        const Divider(color: AppTheme.glassBorder, thickness: 1),
        const SizedBox(height: 24),
        const Text('MORE FROM THIS CATEGORY', style: TextStyle(color: Colors.white, fontSize: 10, fontWeight: FontWeight.w900, letterSpacing: 2.5)),
        const SizedBox(height: 10),
        Text('More ${widget.product.category}', style: const TextStyle(fontSize: 20, fontWeight: FontWeight.w900, color: AppTheme.polishedSilver)),
        const SizedBox(height: 20),
        Builder(
          builder: (context) {
            final double screenWidth = MediaQuery.of(context).size.width;
            final double aspectRatio = screenWidth < 360 ? 0.55 : (screenWidth < 400 ? 0.60 : 0.64);
            return GridView.builder(
              shrinkWrap: true,
              physics: const NeverScrollableScrollPhysics(),
              itemCount: _relatedProducts.length,
              gridDelegate: SliverGridDelegateWithFixedCrossAxisCount(
                crossAxisCount: screenWidth > 600 ? 3 : 2,
                childAspectRatio: aspectRatio,
                crossAxisSpacing: 12,
                mainAxisSpacing: 12,
              ),
              itemBuilder: (ctx, idx) => ProductCard(
                product: _relatedProducts[idx],
                onTap: () => Navigator.pushReplacement(context, MaterialPageRoute(builder: (_) => ProductDetailsScreen(product: _relatedProducts[idx]))),
              ).animate().fadeIn(delay: (idx * 50).ms),
            );
          },
        ),
      ],
    );
  }

  Widget _buildCircularBtn(IconData icon, VoidCallback onTap, {double size = 20, Color? color}) {
    return ClipRRect(
      borderRadius: BorderRadius.circular(100),
      child: BackdropFilter(
        filter: ImageFilter.blur(sigmaX: 10, sigmaY: 10),
        child: Container(
          color: Colors.white.withValues(alpha: 0.05),
          child: IconButton(
            icon: Icon(icon, size: size, color: color ?? AppTheme.brushedPlatinum),
            onPressed: onTap,
          ),
        ),
      ),
    );
  }

  Widget _buildPageIndicator(bool isSelected) {
    return AnimatedContainer(
      duration: const Duration(milliseconds: 300),
      margin: const EdgeInsets.symmetric(horizontal: 4),
      width: isSelected ? 24 : 8,
      height: 2,
      decoration: BoxDecoration(
        borderRadius: BorderRadius.circular(2),
        color: isSelected ? AppTheme.brushedPlatinum : AppTheme.platinumBorder,
      ),
    );
  }

  Widget _buildSpecRow(String label, String value) {
    return Padding(
      padding: const EdgeInsets.only(bottom: 12),
      child: Row(
        mainAxisAlignment: MainAxisAlignment.spaceBetween,
        children: [
          Text(label, style: const TextStyle(color: AppTheme.coolGrey, fontSize: 10, letterSpacing: 1)),
          Text(value.toUpperCase(), style: const TextStyle(color: AppTheme.polishedSilver, fontSize: 11, fontWeight: FontWeight.bold)),
        ],
      ),
    );
  }

  Widget _buildHeroImage(String url) {
    return GestureDetector(
      onTap: () {
        FullScreenImageViewer.show(context, url, title: widget.product.name);
      },
      child: CachedNetworkImage(
        imageUrl: url, fit: BoxFit.cover,
        placeholder: (_, __) => Container(color: AppTheme.matteBlack),
        errorWidget: (_, __, ___) => const Icon(Icons.diamond_outlined, color: AppTheme.platinumBorder),
      ),
    );
  }

  Widget _buildQtyPicker() {
    return Container(
      width: 120,
      padding: const EdgeInsets.all(2),
      decoration: BoxDecoration(borderRadius: BorderRadius.circular(100), border: Border.all(color: AppTheme.glassBorder, width: 1), color: Colors.white.withValues(alpha: 0.05)),
      child: Row(
        mainAxisAlignment: MainAxisAlignment.spaceBetween,
        children: [
          IconButton(onPressed: () { if (_selectedQty > 1) setState(() => _selectedQty--); }, icon: const Icon(Icons.remove, size: 14, color: AppTheme.brushedPlatinum)),
          Text('$_selectedQty', style: const TextStyle(fontSize: 14, fontWeight: FontWeight.w900, color: AppTheme.polishedSilver)),
          IconButton(onPressed: () { if (_selectedQty < widget.product.stock) setState(() => _selectedQty++); }, icon: const Icon(Icons.add, size: 14, color: AppTheme.brushedPlatinum)),
        ],
      ),
    );
  }

  Widget _buildActionBtn(String label, VoidCallback onTap, {bool isGlass = false}) {
    return GestureDetector(
      onTap: onTap,
      child: ClipRRect(
        borderRadius: BorderRadius.circular(100),
        child: BackdropFilter(
          filter: ImageFilter.blur(sigmaX: 10, sigmaY: 10),
          child: Container(
            height: 52,
            decoration: BoxDecoration(
              color: isGlass ? Colors.white.withValues(alpha: 0.08) : AppTheme.brushedPlatinum,
              borderRadius: BorderRadius.circular(100),
              border: Border.all(color: AppTheme.glassBorder, width: 1),
            ),
            alignment: Alignment.center,
            child: _isAdding && isGlass
                ? const SizedBox(width: 20, height: 20, child: CircularProgressIndicator(strokeWidth: 1, color: Colors.white))
                : Text(label, maxLines: 1, overflow: TextOverflow.ellipsis, style: TextStyle(color: isGlass ? Colors.white : Colors.black, fontSize: 9, fontWeight: FontWeight.w900, letterSpacing: 1.0)),
          ),
        ),
      ),
    );
  }
}
