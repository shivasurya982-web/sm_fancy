import 'package:flutter/material.dart';
import 'package:image_picker/image_picker.dart';
import '../models/order_item.dart';
import '../config/theme.dart';
import '../services/product_service.dart';
import '../services/return_service.dart';
import '../services/review_service.dart';
import '../services/upload_service.dart';
import '../widgets/glass_toast.dart';
import '../widgets/gold_button.dart';
import 'product_details_screen.dart';

class OrderDetailsScreen extends StatefulWidget {
  final OrderItem order;

  const OrderDetailsScreen({super.key, required this.order});

  @override
  State<OrderDetailsScreen> createState() => _OrderDetailsScreenState();
}

class _OrderDetailsScreenState extends State<OrderDetailsScreen> {
  bool _isNavigating = false;

  Future<void> _navigateToProduct(BuildContext context, String productId) async {
    if (_isNavigating) return;
    setState(() => _isNavigating = true);
    try {
      final product = await ProductService.getProductById(productId);
      if (mounted) Navigator.push(context, MaterialPageRoute(builder: (_) => ProductDetailsScreen(product: product)));
    } catch (e) {
      if (mounted) showGlassToast(context, 'Could not load product details: $e', isError: true);
    } finally {
      if (mounted) setState(() => _isNavigating = false);
    }
  }

  void _showRatingDialog(OrderItemProduct item) {
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
                Text(item.name.toUpperCase(), style: const TextStyle(color: AppTheme.coolGrey, fontSize: 11, fontWeight: FontWeight.bold)),
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
                        productId: item.productId,
                        orderId: widget.order.orderId,
                        rating: selectedRating,
                        review: reviewCtrl.text.trim(),
                        images: reviewImageUrls,
                      );
                      if (ctx.mounted) {
                        Navigator.pop(ctx);
                        showGlassToast(context, 'Thank you! Your review has been submitted.', isError: false, title: 'REVIEW SUBMITTED');
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

  void _showReturnDialog() {
      final reasonCtrl = TextEditingController();
      final descCtrl = TextEditingController();
      bool loading = false;
      showModalBottomSheet(
          context: context,
          isScrollControlled: true,
          backgroundColor: Colors.transparent,
          builder: (ctx) => StatefulBuilder(
              builder: (ctx, setDialogState) => Container(
                  constraints: BoxConstraints(maxHeight: MediaQuery.of(ctx).size.height * 0.85),
                  padding: EdgeInsets.fromLTRB(24, 24, 24, MediaQuery.of(ctx).viewInsets.bottom + 24),
                  decoration: const BoxDecoration(color: AppTheme.deepCharcoal, borderRadius: BorderRadius.vertical(top: Radius.circular(20))),
                  child: SingleChildScrollView(
                    child: Column(
                        mainAxisSize: MainAxisSize.min,
                        crossAxisAlignment: CrossAxisAlignment.start,
                        children: [
                            Text('RETURN REQUEST', style: Theme.of(context).textTheme.labelSmall),
                            const SizedBox(height: 20),
                            TextField(controller: reasonCtrl, decoration: const InputDecoration(labelText: 'REASON')),
                            const SizedBox(height: 14),
                            TextField(controller: descCtrl, maxLines: 3, decoration: const InputDecoration(labelText: 'DETAILS')),
                            const SizedBox(height: 28),
                            SizedBox(
                                width: double.infinity,
                                height: 52,
                                child: ElevatedButton(
                                    onPressed: loading ? null : () async {
                                        if (reasonCtrl.text.isEmpty) return;
                                        setDialogState(() => loading = true);
                                        try {
                                            await ReturnService.requestReturn(orderId: widget.order.orderId, reason: reasonCtrl.text, description: descCtrl.text);
                                            if (ctx.mounted) { 
                                              Navigator.pop(ctx); 
                                              showGlassToast(context, 'Return requested successfully.', isError: false);
                                              Navigator.pop(context); 
                                            }
                                        } catch (_) {}
                                        finally { if (ctx.mounted) setDialogState(() => loading = false); }
                                    },
                                    child: loading ? const CircularProgressIndicator() : const Text('SUBMIT REQUEST'),
                                ),
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
    final bool isWeb = screenWidth > 800;
    final bool isNarrow = screenWidth < 360;

    return Scaffold(
      backgroundColor: AppTheme.deepCharcoal,
      appBar: AppBar(
        title: const Text('ORDER DETAILS'),
        leading: IconButton(icon: const Icon(Icons.arrow_back_ios_new_rounded, size: 20), onPressed: () => Navigator.pop(context)),
      ),
      body: Container(
        decoration: AppTheme.filigreeBackground(),
        child: Center(
          child: ConstrainedBox(
            constraints: BoxConstraints(maxWidth: isWeb ? 500 : double.infinity),
            child: Stack(
              children: [
                SingleChildScrollView(
                  padding: EdgeInsets.symmetric(horizontal: isNarrow ? 16 : 24, vertical: 20),
                  child: Column(
                    crossAxisAlignment: CrossAxisAlignment.start,
                    children: [
                      _buildInfoCard(),
                      const SizedBox(height: 28),
                      _buildSectionHeader('ITEMS'),
                      const SizedBox(height: 14),
                      ...widget.order.items.map((item) => _buildItemTile(context, item)),
                      const SizedBox(height: 28),
                      _buildSectionHeader('SHIPPING ADDRESS'),
                      const SizedBox(height: 14),
                      _buildAddressCard(),
                      if (widget.order.status == 'Delivered') ...[
                          const SizedBox(height: 36),
                          SizedBox(
                              width: double.infinity,
                              height: 52,
                              child: OutlinedButton.icon(
                                  style: OutlinedButton.styleFrom(
                                      foregroundColor: AppTheme.error, 
                                      side: BorderSide(color: AppTheme.error.withValues(alpha: 0.2)),
                                      shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(100))
                                  ),
                                  onPressed: _showReturnDialog,
                                  icon: const Icon(Icons.assignment_return_outlined, size: 18),
                                  label: const Text('RETURN ORDER', style: TextStyle(fontWeight: FontWeight.w900, letterSpacing: 1.5, fontSize: 10)),
                              ),
                          ),
                      ],
                      const SizedBox(height: 32),
                    ],
                  ),
                ),
                if (_isNavigating) const Center(child: CircularProgressIndicator(color: AppTheme.brushedPlatinum)),
              ],
            ),
          ),
        ),
      ),
    );
  }

  Widget _buildSectionHeader(String title) => Text(title, style: Theme.of(context).textTheme.labelSmall);

  Widget _buildInfoCard() {
    return Container(
      padding: const EdgeInsets.all(20),
      decoration: AppTheme.premiumCard(),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Row(
            mainAxisAlignment: MainAxisAlignment.spaceBetween,
            children: [
              const Text('ORDER SUMMARY', style: TextStyle(color: AppTheme.polishedSilver, fontSize: 13, fontWeight: FontWeight.w900, letterSpacing: 1)),
              _buildStatusBadge(widget.order.status),
            ],
          ),
          const SizedBox(height: 16),
          Row(
            mainAxisAlignment: MainAxisAlignment.spaceBetween,
            children: [
              const Text('PAYMENT STATUS', style: TextStyle(color: AppTheme.coolGrey, fontSize: 8, fontWeight: FontWeight.w900, letterSpacing: 1)),
              Text(
                (widget.order.paymentStatus ?? 'Pending').toUpperCase(), 
                style: TextStyle(
                    color: widget.order.paymentStatus == 'Paid' ? AppTheme.success : AppTheme.error, 
                    fontSize: 9, fontWeight: FontWeight.bold
                )
              ),
            ],
          ),
          if (widget.order.paymentMethod == 'UPI')
             Padding(
               padding: const EdgeInsets.only(top: 8),
               child: Text('REF: ${widget.order.upiTransactionId ?? 'Awaiting Bank Confirmation'}', style: const TextStyle(color: Colors.white24, fontSize: 8)),
             ),
          const Divider(height: 32, color: AppTheme.platinumBorder, thickness: 0.5),
          _buildPriceRow('Items Total', '₹${widget.order.subtotal.toStringAsFixed(0)}'),
          const SizedBox(height: 10),
          _buildPriceRow('Shipping Fee', '₹${widget.order.shipping.toStringAsFixed(0)}', isPlatinum: true),
          const Divider(height: 32, color: AppTheme.platinumBorder, thickness: 0.5),
          _buildPriceRow('TOTAL AMOUNT', '₹${widget.order.total.toStringAsFixed(0)}', isTotal: true),
        ],
      ),
    );
  }

  Widget _buildItemTile(BuildContext context, OrderItemProduct item) {
    final bool isDelivered = widget.order.status == 'Delivered';

    return Container(
      margin: const EdgeInsets.only(bottom: 12),
      padding: const EdgeInsets.all(16),
      decoration: AppTheme.premiumCard(),
      child: Row(
        children: [
          Expanded(
            child: GestureDetector(
              onTap: () => _navigateToProduct(context, item.productId),
              child: Column(
                crossAxisAlignment: CrossAxisAlignment.start,
                children: [
                  Text(item.name.toUpperCase(), maxLines: 1, overflow: TextOverflow.ellipsis, style: const TextStyle(fontWeight: FontWeight.bold, fontSize: 12, letterSpacing: 0.5, color: AppTheme.polishedSilver)),
                  const SizedBox(height: 4),
                  Text('QTY: ${item.quantity}  •  ₹${(item.price * item.quantity).toStringAsFixed(0)}', style: const TextStyle(color: AppTheme.coolGrey, fontSize: 10, fontWeight: FontWeight.w600)),
                ],
              ),
            ),
          ),
          if (isDelivered) ...[
            const SizedBox(width: 12),
            GestureDetector(
              onTap: () => _showRatingDialog(item),
              child: Container(
                padding: const EdgeInsets.symmetric(horizontal: 12, vertical: 8),
                decoration: BoxDecoration(
                  color: AppTheme.brushedPlatinum.withValues(alpha: 0.1),
                  borderRadius: BorderRadius.circular(100),
                  border: Border.all(color: AppTheme.brushedPlatinum.withValues(alpha: 0.3), width: 0.8),
                ),
                child: const Row(
                  children: [
                    Icon(Icons.star_rounded, color: Colors.amber, size: 14),
                    SizedBox(width: 4),
                    Text('RATE', style: TextStyle(color: AppTheme.brushedPlatinum, fontSize: 9, fontWeight: FontWeight.w900, letterSpacing: 1)),
                  ],
                ),
              ),
            ),
          ],
        ],
      ),
    );
  }

  Widget _buildAddressCard() {
    final addr = widget.order.shippingAddress;
    return Container(
      width: double.infinity,
      padding: const EdgeInsets.all(20),
      decoration: AppTheme.premiumCard(),
      child: Row(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          const Icon(Icons.location_on_outlined, color: AppTheme.brushedPlatinum, size: 20),
          const SizedBox(width: 14),
          Expanded(
            child: Column(
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                Text(addr['name']?.toString().toUpperCase() ?? '', style: const TextStyle(fontWeight: FontWeight.bold, fontSize: 13, color: AppTheme.polishedSilver)),
                const SizedBox(height: 4),
                Text(addr['phone'] ?? '', style: const TextStyle(color: AppTheme.coolGrey, fontSize: 11)),
                const SizedBox(height: 10),
                Text('${addr['street']}, ${addr['city']}', style: const TextStyle(color: AppTheme.coolGrey, height: 1.4, fontSize: 12)),
                Text('${addr['state']} - ${addr['pincode']}', style: const TextStyle(color: AppTheme.coolGrey, fontSize: 12)),
              ],
            ),
          ),
        ],
      ),
    );
  }

  Widget _buildPriceRow(String label, String val, {bool isTotal = false, bool isPlatinum = false}) {
    return Row(
      mainAxisAlignment: MainAxisAlignment.spaceBetween,
      children: [
        Text(label, style: TextStyle(color: isTotal ? AppTheme.polishedSilver : AppTheme.coolGrey, fontWeight: isTotal ? FontWeight.w900 : FontWeight.normal, fontSize: isTotal ? 12 : 11)),
        Text(val, style: TextStyle(color: (isTotal || isPlatinum) ? AppTheme.brushedPlatinum : AppTheme.polishedSilver, fontWeight: FontWeight.w900, fontSize: isTotal ? 18 : 13)),
      ],
    );
  }

  Widget _buildStatusBadge(String status) {
    Color color;
    switch (status) {
      case 'Delivered': color = AppTheme.success; break;
      case 'Cancelled': color = AppTheme.error; break;
      default: color = AppTheme.brushedPlatinum;
    }
    return Container(
      padding: const EdgeInsets.symmetric(horizontal: 10, vertical: 5),
      decoration: BoxDecoration(
        color: color.withValues(alpha: 0.08), 
        borderRadius: BorderRadius.circular(100),
        border: Border.all(color: color.withValues(alpha: 0.2), width: 0.8),
      ),
      child: Text(
        status.toUpperCase(), 
        style: TextStyle(color: color, fontSize: 8, fontWeight: FontWeight.w900, letterSpacing: 1)
      ),
    );
  }
}
