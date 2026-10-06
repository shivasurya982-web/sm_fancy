import 'dart:async';
import 'package:flutter/material.dart';
import 'package:qr_flutter/qr_flutter.dart';
import '../models/address_model.dart';
import '../services/address_service.dart';
import '../services/cart_service.dart';
import '../services/order_service.dart';
import '../services/api_service.dart';
import '../services/settings_service.dart';
import '../services/payment_service.dart';
import '../config/theme.dart';
import '../widgets/gold_button.dart';
import '../widgets/glass_toast.dart';
import 'order_success_screen.dart';
import 'payment_result_screen.dart';
import 'package:url_launcher/url_launcher.dart';

class CheckoutScreen extends StatefulWidget {
  const CheckoutScreen({super.key});

  @override
  State<CheckoutScreen> createState() => _CheckoutScreenState();
}

class _CheckoutScreenState extends State<CheckoutScreen> {
  final _nameController = TextEditingController();
  final _phoneController = TextEditingController();
  final _streetController = TextEditingController();
  final _cityController = TextEditingController();
  final _pinController = TextEditingController();

  String _paymentMethod = 'COD';
  bool _isLoading = false;
  String _localCity = 'Tiruchendur';
  double _localFee = 50.0;
  double _standardFee = 100.0;

  @override
  void initState() {
    super.initState();
    _nameController.text = ApiService.currentUserName;
    _loadSettings();
    _loadSavedAddress();
  }

  @override
  void dispose() {
    _nameController.dispose();
    _phoneController.dispose();
    _streetController.dispose();
    _cityController.dispose();
    _pinController.dispose();
    super.dispose();
  }

  Future<void> _loadSavedAddress() async {
    final addresses = await AddressService.getAddresses();
    if (addresses.isNotEmpty && mounted) {
      final a = addresses.last;
      setState(() {
        _nameController.text = a.name;
        _phoneController.text = a.phone;
        _streetController.text = a.address;
        _cityController.text = a.city;
        _pinController.text = a.pincode;
      });
    }
  }

  Future<void> _loadSettings() async {
    final settings = await SettingsService.getSettings();
    if (mounted) {
      setState(() {
        _localCity = settings['localCity'] ?? 'Tiruchendur';
        _localFee = (settings['localShippingFee'] as num?)?.toDouble() ?? 50.0;
        _standardFee = (settings['standardShippingFee'] as num?)?.toDouble() ?? 100.0;
      });
    }
  }

  double get _currentShippingFee {
    final city = _cityController.text.trim().toLowerCase();
    if (city == _localCity.toLowerCase()) return _localFee;
    return _standardFee;
  }

  Future<void> _handlePlaceOrder() async {
    if (_nameController.text.isEmpty || _phoneController.text.isEmpty || _streetController.text.isEmpty || _pinController.text.isEmpty) {
      showGlassToast(context, "Please fill all shipping details.", isError: true, title: 'CHECKOUT REQUIRED');
      return;
    }
    
    if (_paymentMethod == 'UPI') {
        _startDynamicUPIPayment();
    } else {
        _confirmOrderCOD();
    }
  }

  // --- UPI Payment Server Flow ---

  Future<void> _startDynamicUPIPayment() async {
    setState(() => _isLoading = true);
    try {
      final shippingAddress = {
        'fullName': _nameController.text.trim(),
        'phone': _phoneController.text.trim(),
        'addressLine1': _streetController.text.trim(),
        'city': _cityController.text.trim(),
        'state': 'Tamil Nadu',
        'pincode': _pinController.text.trim(),
      };

      final cartItemsMap = CartService.cartItems.map((item) => {
        'product': item.productId,
        'name': item.name,
        'price': item.price,
        'quantity': item.quantity,
        'image': item.image,
      }).toList();

      final orderData = await PaymentService.initiateUPIDynamicQR(
        items: cartItemsMap, 
        address: shippingAddress,
        shipping: _currentShippingFee,
        returnUrl: 'fancyworld://payment-done',
      );

      final String payUrl = (orderData['payUrl'] ?? orderData['upiPayload'] ?? '').toString();
      final String upiUri = (orderData['upiUri'] ?? orderData['upiPayload'] ?? payUrl).toString();
      final String orderId = (orderData['orderId'] ?? orderData['fancyWorldOrderId']).toString();
      final String? orderNumber = orderData['orderNumber']?.toString();
      final double amount = (orderData['amount'] as num).toDouble();

      // Persist pending order ID for app reload / deep link recovery
      await PaymentService.savePendingOrderId(orderId);

      // Launch clean UPI payment intent in external UPI app
      final targetUri = Uri.parse(upiUri.isNotEmpty ? upiUri : payUrl);
      if (await canLaunchUrl(targetUri)) {
        await launchUrl(targetUri, mode: LaunchMode.externalApplication);
      }

      if (mounted) {
        _showPaymentVerificationDialog(
          payUrl: payUrl,
          upiUri: upiUri,
          orderId: orderId,
          orderNumber: orderNumber,
          amount: amount,
        );
      }

    } catch (e) {
      if (mounted) {
        final msg = e.toString().replaceFirst('Exception: ', '').replaceFirst('Error: ', '');
        showGlassToast(context, "Failed to initiate payment: $msg", isError: true, title: 'PAYMENT ERROR');
      }
      if (mounted) setState(() => _isLoading = false);
    }
  }

  void _showPaymentVerificationDialog({
    required String payUrl,
    required String upiUri,
    required String orderId,
    String? orderNumber,
    required double amount,
  }) {
    Timer? statusTimer;

    showDialog(
      context: context,
      barrierDismissible: false,
      builder: (ctx) => StatefulBuilder(
        builder: (context, setDialogState) {
          statusTimer ??= Timer.periodic(const Duration(seconds: 4), (timer) async {
            final res = await PaymentService.checkPaymentStatus(orderId);
            final String paymentStatus = (res['paymentStatus'] ?? 'Pending').toString();

            if (paymentStatus != 'Pending') {
              timer.cancel();
              await PaymentService.clearPendingOrderId();
              if (paymentStatus == 'Paid') {
                await CartService.clearCart();
              }
              if (ctx.mounted) Navigator.pop(ctx);
              if (mounted) {
                setState(() => _isLoading = false);
                Navigator.pushReplacement(
                  context,
                  MaterialPageRoute(
                    builder: (_) => PaymentResultScreen(
                      status: paymentStatus,
                      orderId: orderId,
                      orderNumber: orderNumber ?? res['orderNumber'],
                      amount: amount,
                    ),
                  ),
                );
              }
            }
          });

          return AlertDialog(
            backgroundColor: AppTheme.deepCharcoal,
            shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(32), side: const BorderSide(color: AppTheme.glassBorder)),
            title: const Center(
              child: Text(
                'PAYMENT IN PROGRESS',
                style: TextStyle(fontSize: 14, fontWeight: FontWeight.w900, color: AppTheme.polishedSilver, letterSpacing: 2),
              ),
            ),
            content: SingleChildScrollView(
              child: Column(
                mainAxisSize: MainAxisSize.min,
                children: [
                  Text('₹${amount.toStringAsFixed(2)}', style: const TextStyle(fontSize: 28, fontWeight: FontWeight.w900, color: Colors.white)),
                  const SizedBox(height: 16),
                  Container(
                    padding: const EdgeInsets.all(12),
                    decoration: BoxDecoration(color: Colors.white, borderRadius: BorderRadius.circular(20)),
                    child: QrImageView(
                      data: upiUri.isNotEmpty ? upiUri : payUrl,
                      version: QrVersions.auto,
                      size: 150,
                      eyeStyle: const QrEyeStyle(eyeShape: QrEyeShape.square, color: Colors.black),
                      dataModuleStyle: const QrDataModuleStyle(dataModuleShape: QrDataModuleShape.square, color: Colors.black),
                    ),
                  ),
                  const SizedBox(height: 16),
                  
                  // Button to directly launch UPI App on the same device
                  SizedBox(
                    width: double.infinity,
                    child: ElevatedButton.icon(
                      style: ElevatedButton.styleFrom(
                        backgroundColor: AppTheme.brushedPlatinum,
                        foregroundColor: Colors.black,
                        padding: const EdgeInsets.symmetric(vertical: 12),
                        shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(30)),
                      ),
                      icon: const Icon(Icons.account_balance_wallet_rounded, size: 18),
                      label: const Text('PAY VIA UPI APP', style: TextStyle(fontWeight: FontWeight.w900, fontSize: 11, letterSpacing: 1)),
                      onPressed: () async {
                        try {
                          final uri = Uri.parse(upiUri.isNotEmpty ? upiUri : payUrl);
                          await launchUrl(uri, mode: LaunchMode.externalApplication);
                        } catch (e) {
                          if (ctx.mounted) {
                            showGlassToast(ctx, "Could not open UPI app. Please scan QR code with GPay/PhonePe.", isError: true);
                          }
                        }
                      },
                    ),
                  ),
                  const SizedBox(height: 14),
                  
                  const Row(
                    mainAxisAlignment: MainAxisAlignment.center,
                    children: [
                      SizedBox(width: 12, height: 12, child: CircularProgressIndicator(strokeWidth: 2, color: AppTheme.brushedPlatinum)),
                      SizedBox(width: 8),
                      Text('Waiting for payment confirmation...', style: TextStyle(color: AppTheme.coolGrey, fontSize: 10, fontWeight: FontWeight.bold)),
                    ],
                  ),
                  const SizedBox(height: 8),
                  const Text(
                    'Scan QR with PhonePe, Google Pay or Paytm on another phone, or click "PAY VIA UPI APP" above.',
                    textAlign: TextAlign.center,
                    style: TextStyle(color: Colors.white38, fontSize: 9, height: 1.3),
                  ),
                ],
              ),
            ),
            actions: [
              TextButton(
                onPressed: () async {
                  statusTimer?.cancel();
                  await PaymentService.clearPendingOrderId();
                  if (ctx.mounted) Navigator.pop(ctx);
                  if (mounted) {
                    setState(() => _isLoading = false);
                    Navigator.pushReplacement(
                      context,
                      MaterialPageRoute(
                        builder: (_) => PaymentResultScreen(
                          status: 'Cancelled',
                          orderId: orderId,
                          orderNumber: orderNumber,
                          amount: amount,
                        ),
                      ),
                    );
                  }
                },
                child: const Text('CANCEL PAYMENT', style: TextStyle(color: AppTheme.error, fontWeight: FontWeight.bold)),
              ),
              ElevatedButton(
                onPressed: () async {
                  final res = await PaymentService.checkPaymentStatus(orderId);
                  final String paymentStatus = (res['paymentStatus'] ?? 'Pending').toString();
                  if (paymentStatus != 'Pending') {
                    statusTimer?.cancel();
                    await PaymentService.clearPendingOrderId();
                    if (paymentStatus == 'Paid') {
                      await CartService.clearCart();
                    }
                    if (ctx.mounted) Navigator.pop(ctx);
                    if (mounted) {
                      setState(() => _isLoading = false);
                      Navigator.pushReplacement(
                        context,
                        MaterialPageRoute(
                          builder: (_) => PaymentResultScreen(
                            status: paymentStatus,
                            orderId: orderId,
                            orderNumber: orderNumber ?? res['orderNumber'],
                            amount: amount,
                          ),
                        ),
                      );
                    }
                  } else {
                    if (ctx.mounted) {
                      showGlassToast(ctx, "Still pending... Ensure CALLBACK_URL & APP_KEY match on Render server.", title: 'CHECKING STATUS');
                    }
                  }
                },
                child: const Text('CHECK AGAIN'),
              ),
            ],
          );
        },
      ),
    );
  }

  // --- COD Logic ---

  Future<void> _confirmOrderCOD() async {
    setState(() => _isLoading = true);
    try {
      final shippingAddress = {
        'fullName': _nameController.text.trim(),
        'phone': _phoneController.text.trim(),
        'addressLine1': _streetController.text.trim(),
        'city': _cityController.text.trim(),
        'state': 'Tamil Nadu',
        'pincode': _pinController.text.trim(),
      };
      final cartItemsMap = CartService.cartItems.map((item) => {
        'product': item.productId,
        'name': item.name,
        'price': item.price,
        'quantity': item.quantity,
        'image': item.image,
      }).toList();

      final order = await OrderService.placeOrder(
        shippingAddress: shippingAddress,
        paymentMethod: 'COD',
        items: cartItemsMap,
        subtotal: CartService.cartTotal,
        shipping: _currentShippingFee,
        total: CartService.cartTotal + _currentShippingFee,
      );

      await CartService.clearCart();
      try {
          await AddressService.saveAddress(AddressModel(
              name: shippingAddress['fullName']!,
              phone: shippingAddress['phone']!,
              address: shippingAddress['addressLine1']!,
              city: shippingAddress['city']!,
              pincode: shippingAddress['pincode']!,
          ));
      } catch (_) {}

      if (!mounted) return;
      Navigator.pushReplacement(context, MaterialPageRoute(builder: (_) => OrderSuccessScreen(order: order)));
    } catch (e) {
      if (mounted) {
        final msg = e.toString().replaceFirst('Exception: ', '').replaceFirst('Error: ', '');
        showGlassToast(context, "Order Failed: $msg", isError: true, title: 'ORDER FAILED');
      }
    } finally {
      if (mounted) setState(() => _isLoading = false);
    }
  }

  @override
  Widget build(BuildContext context) {
    final double screenWidth = MediaQuery.of(context).size.width;
    final bool isWeb = screenWidth > 800;
    final bool isNarrow = screenWidth < 360;
    final total = CartService.cartTotal + _currentShippingFee;

    return Scaffold(
      backgroundColor: AppTheme.deepCharcoal,
      appBar: AppBar(
        title: Text('CHECKOUT', style: Theme.of(context).textTheme.labelSmall?.copyWith(letterSpacing: 4)),
        leading: IconButton(icon: const Icon(Icons.arrow_back_ios_new_rounded, size: 20), onPressed: () => Navigator.pop(context)),
      ),
      body: Container(
        decoration: AppTheme.filigreeBackground(),
        child: Stack(
            children: [
                Center(
                  child: ConstrainedBox(
                    constraints: BoxConstraints(maxWidth: isWeb ? 500 : double.infinity),
                    child: SingleChildScrollView(
                      padding: EdgeInsets.symmetric(horizontal: isNarrow ? 16 : 24, vertical: 20),
                      child: Column(
                        crossAxisAlignment: CrossAxisAlignment.start,
                        children: [
                          _buildSectionHeader('SHIPPING ADDRESS'),
                          const SizedBox(height: 14),
                          _buildAddressForm(),
                          
                          const SizedBox(height: 32),
                          _buildSectionHeader('PAYMENT METHOD'),
                          const SizedBox(height: 14),
                          _buildPaymentOption('COD', Icons.payments_outlined, 'Pay when you receive'),
                          const SizedBox(height: 12),
                          _buildPaymentOption('UPI', Icons.qr_code_scanner_rounded, 'Secure Dynamic QR Code'),
                          
                          const SizedBox(height: 32),
                          _buildSectionHeader('ORDER SUMMARY'),
                          const SizedBox(height: 14),
                          _buildSummaryCard(total),
                          
                          const SizedBox(height: 40),
                          GoldButton(
                            label: _paymentMethod == 'UPI' ? 'GENERATE PAYMENT QR' : 'PLACE ORDER', 
                            onPressed: _isLoading ? null : _handlePlaceOrder,
                            isLoading: _isLoading,
                          ),
                          const SizedBox(height: 32),
                        ],
                      ),
                    ),
                  ),
                ),
                
                if (_isLoading)
                  Container(
                      color: Colors.black54,
                      child: const Center(child: CircularProgressIndicator(color: AppTheme.brushedPlatinum)),
                  ),
            ],
        ),
      ),
    );
  }

  Widget _buildSectionHeader(String title) => Text(title, style: Theme.of(context).textTheme.labelSmall);

  Widget _buildAddressForm() {
    return Container(
      padding: const EdgeInsets.all(20),
      decoration: AppTheme.premiumCard(),
      child: Column(
        children: [
          _buildField('Full Name', _nameController),
          const SizedBox(height: 14),
          _buildField('Phone Number', _phoneController, keyboard: TextInputType.phone),
          const SizedBox(height: 14),
          _buildField('Address', _streetController),
          const SizedBox(height: 14),
          Row(
            children: [
              Expanded(child: _buildField('City', _cityController)),
              const SizedBox(width: 14),
              Expanded(child: _buildField('Pin Code', _pinController, keyboard: TextInputType.number)),
            ],
          ),
        ],
      ),
    );
  }

  Widget _buildField(String label, TextEditingController ctrl, {TextInputType keyboard = TextInputType.text}) {
    return TextField(
      controller: ctrl,
      keyboardType: keyboard,
      style: const TextStyle(fontSize: 13, fontWeight: FontWeight.bold, color: AppTheme.polishedSilver),
      decoration: InputDecoration(
        labelText: label,
        labelStyle: const TextStyle(fontSize: 9, fontWeight: FontWeight.w400, color: AppTheme.coolGrey),
        floatingLabelBehavior: FloatingLabelBehavior.always,
      ),
    );
  }

  Widget _buildPaymentOption(String name, IconData icon, String sub) {
    final isSelected = _paymentMethod == name;
    return GestureDetector(
      onTap: () => setState(() => _paymentMethod = name),
      child: AnimatedContainer(
        duration: const Duration(milliseconds: 300),
        padding: const EdgeInsets.all(18),
        decoration: BoxDecoration(
          color: AppTheme.matteBlack,
          borderRadius: BorderRadius.circular(20),
          border: Border.all(color: isSelected ? AppTheme.brushedPlatinum : AppTheme.glassBorder, width: isSelected ? 1.2 : 0.8),
        ),
        child: Row(
          children: [
            Icon(icon, color: isSelected ? AppTheme.brushedPlatinum : AppTheme.coolGrey, size: 20),
            const SizedBox(width: 14),
            Expanded(
              child: Column(
                  crossAxisAlignment: CrossAxisAlignment.start,
                  children: [
                      Text(name, style: TextStyle(color: isSelected ? AppTheme.polishedSilver : AppTheme.coolGrey, fontWeight: isSelected ? FontWeight.w900 : FontWeight.w400, fontSize: 11, letterSpacing: 1)),
                      Text(sub, style: const TextStyle(color: Colors.white24, fontSize: 8, fontWeight: FontWeight.w500)),
                  ],
              ),
            ),
            if (isSelected) Container(width: 8, height: 8, decoration: const BoxDecoration(color: AppTheme.brushedPlatinum, shape: BoxShape.circle, boxShadow: [BoxShadow(color: AppTheme.brushedPlatinum, blurRadius: 4)])),
          ],
        ),
      ),
    );
  }

  Widget _buildSummaryCard(double total) {
    return Container(
      padding: const EdgeInsets.all(20),
      decoration: AppTheme.premiumCard(),
      child: Column(
        children: [
          _buildSummaryRow('Subtotal', '₹${CartService.cartTotal.toStringAsFixed(0)}'),
          const SizedBox(height: 10),
          _buildSummaryRow('Shipping', '₹${_currentShippingFee.toStringAsFixed(0)}', isPlatinum: true),
          const Divider(height: 28, color: AppTheme.glassBorder, thickness: 1),
          Row(
            mainAxisAlignment: MainAxisAlignment.spaceBetween,
            children: [
              const Text('TOTAL AMOUNT', style: TextStyle(fontWeight: FontWeight.w900, fontSize: 11, color: AppTheme.coolGrey)),
              Text('₹${total.toStringAsFixed(0)}', style: const TextStyle(fontSize: 20, fontWeight: FontWeight.w900, color: AppTheme.polishedSilver)),
            ],
          ),
        ],
      ),
    );
  }

  Widget _buildSummaryRow(String label, String val, {bool isPlatinum = false}) {
    return Row(
      mainAxisAlignment: MainAxisAlignment.spaceBetween,
      children: [
        Text(label, style: const TextStyle(color: AppTheme.coolGrey, fontSize: 12)),
        Text(val, style: TextStyle(fontWeight: FontWeight.bold, color: isPlatinum ? AppTheme.brushedPlatinum : AppTheme.polishedSilver, fontSize: 13)),
      ],
    );
  }
}
