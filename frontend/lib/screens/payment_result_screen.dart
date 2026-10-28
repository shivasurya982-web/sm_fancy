import 'package:flutter/material.dart';
import '../config/theme.dart';
import '../widgets/gold_button.dart';
import '../bottom_navigation.dart';
import '../services/order_service.dart';
import 'order_details_screen.dart';
import 'orders_screen.dart';
import 'cart_screen.dart';

class PaymentResultScreen extends StatelessWidget {
  final String status; // 'Paid' | 'SUCCESS' | 'WRONG' | 'Cancelled' | 'CANCELLED' | 'Failed'
  final String orderId;
  final String? orderNumber;
  final double? amount;

  const PaymentResultScreen({
    super.key,
    required this.status,
    required this.orderId,
    this.orderNumber,
    this.amount,
  });

  bool get isSuccess => status.toUpperCase() == 'PAID' || status.toUpperCase() == 'SUCCESS';
  bool get isWrongAmount => status.toUpperCase() == 'WRONG';

  @override
  Widget build(BuildContext context) {
    return Scaffold(
      backgroundColor: AppTheme.deepCharcoal,
      appBar: AppBar(
        title: Text(
          isSuccess
              ? 'PAYMENT SUCCESSFUL'
              : isWrongAmount
                  ? 'AMOUNT MISMATCH'
                  : 'PAYMENT CANCELLED',
          style: Theme.of(context).textTheme.labelSmall?.copyWith(letterSpacing: 3),
        ),
        automaticallyImplyLeading: false,
      ),
      body: Container(
        decoration: AppTheme.filigreeBackground(),
        child: Center(
          child: SingleChildScrollView(
            padding: const EdgeInsets.all(24.0),
            child: Column(
              mainAxisAlignment: MainAxisAlignment.center,
              children: [
                _buildHeaderIcon(),
                const SizedBox(height: 24),
                _buildTitle(),
                const SizedBox(height: 12),
                _buildMessage(context),
                const SizedBox(height: 24),
                _buildDetailsCard(),
                const SizedBox(height: 36),
                _buildActionButtons(context),
              ],
            ),
          ),
        ),
      ),
    );
  }

  Widget _buildHeaderIcon() {
    if (isSuccess) {
      return Container(
        padding: const EdgeInsets.all(20),
        decoration: BoxDecoration(
          color: AppTheme.success.withValues(alpha: 0.15),
          shape: BoxShape.circle,
          border: Border.all(color: AppTheme.success, width: 2),
        ),
        child: const Icon(Icons.check_circle_rounded, color: AppTheme.success, size: 64),
      );
    } else if (isWrongAmount) {
      return Container(
        padding: const EdgeInsets.all(20),
        decoration: BoxDecoration(
          color: Colors.amber.withValues(alpha: 0.15),
          shape: BoxShape.circle,
          border: Border.all(color: Colors.amber, width: 2),
        ),
        child: const Icon(Icons.warning_amber_rounded, color: Colors.amber, size: 64),
      );
    } else {
      return Container(
        padding: const EdgeInsets.all(20),
        decoration: BoxDecoration(
          color: AppTheme.error.withValues(alpha: 0.15),
          shape: BoxShape.circle,
          border: Border.all(color: AppTheme.error, width: 2),
        ),
        child: const Icon(Icons.cancel_rounded, color: AppTheme.error, size: 64),
      );
    }
  }

  Widget _buildTitle() {
    String text;
    Color color;

    if (isSuccess) {
      text = 'PAYMENT SUCCESSFUL!';
      color = AppTheme.polishedSilver;
    } else if (isWrongAmount) {
      text = 'PAID INCORRECT AMOUNT';
      color = Colors.amber;
    } else {
      text = 'PAYMENT CANCELLED';
      color = AppTheme.error;
    }

    return Text(
      text,
      textAlign: TextAlign.center,
      style: TextStyle(fontSize: 18, fontWeight: FontWeight.w900, color: color, letterSpacing: 2),
    );
  }

  Widget _buildMessage(BuildContext context) {
    String text;
    if (isSuccess) {
      text = 'Your payment was verified successfully and your order has been placed!';
    } else if (isWrongAmount) {
      text = 'We received your payment, but the amount paid does not match the required total. Your order is placed under review. Please contact support with your Order ID.';
    } else {
      text = 'Your payment process was cancelled or failed. No money was charged for this order, or it will be refunded. You can try placing a new order.';
    }

    return Text(
      text,
      textAlign: TextAlign.center,
      style: const TextStyle(fontSize: 13, color: AppTheme.coolGrey, height: 1.5),
    );
  }

  Widget _buildDetailsCard() {
    final double displayAmount = amount ?? 0;
    final String amountStr = (displayAmount % 1 == 0)
        ? displayAmount.toStringAsFixed(0)
        : displayAmount.toStringAsFixed(2);

    return Container(
      width: double.infinity,
      padding: const EdgeInsets.all(20),
      decoration: AppTheme.premiumCard(),
      child: Column(
        children: [
          _buildRow('VERIFICATION CODE / ORDER ID', orderNumber ?? orderId),
          const Divider(color: AppTheme.glassBorder, height: 20),
          _buildRow('TOTAL AMOUNT PAID', '₹$amountStr', color: AppTheme.amberGold),
          const Divider(color: AppTheme.glassBorder, height: 20),
          _buildRow('STATUS', isSuccess ? 'CONFIRMED' : isWrongAmount ? 'NEEDS REVIEW' : 'CANCELLED',
              color: isSuccess ? AppTheme.success : isWrongAmount ? Colors.amber : AppTheme.error),
        ],
      ),
    );
  }

  Widget _buildRow(String label, String value, {Color? color}) {
    return Row(
      mainAxisAlignment: MainAxisAlignment.spaceBetween,
      children: [
        Text(label, style: const TextStyle(fontSize: 10, color: AppTheme.coolGrey, fontWeight: FontWeight.bold, letterSpacing: 1)),
        Flexible(
          child: Text(
            value,
            textAlign: TextAlign.end,
            style: TextStyle(
              fontSize: 13,
              fontWeight: FontWeight.bold,
              color: color ?? AppTheme.polishedSilver,
            ),
          ),
        ),
      ],
    );
  }

  Widget _buildActionButtons(BuildContext context) {
    if (isSuccess) {
      return Column(
        children: [
          GoldButton(
            label: 'VIEW ORDER DETAILS',
            onPressed: () async {
              try {
                final fullOrder = await OrderService.getOrderById(orderId);
                if (context.mounted) {
                  Navigator.pushReplacement(
                    context,
                    MaterialPageRoute(builder: (_) => OrderDetailsScreen(order: fullOrder)),
                  );
                }
              } catch (_) {
                if (context.mounted) {
                  Navigator.pushReplacement(
                    context,
                    MaterialPageRoute(builder: (_) => const OrdersScreen()),
                  );
                }
              }
            },
          ),
          const SizedBox(height: 12),
          TextButton(
            onPressed: () {
              Navigator.pushAndRemoveUntil(
                context,
                MaterialPageRoute(builder: (_) => const BottomNavigation()),
                (_) => false,
              );
            },
            child: const Text('CONTINUE SHOPPING', style: TextStyle(color: AppTheme.brushedPlatinum, fontWeight: FontWeight.bold)),
          ),
        ],
      );
    } else if (isWrongAmount) {
      return Column(
        children: [
          GoldButton(
            label: 'CONTACT SUPPORT',
            onPressed: () {
              ScaffoldMessenger.of(context).showSnackBar(
                SnackBar(content: Text('Support requested for Order ID: ${orderNumber ?? orderId}')),
              );
              Navigator.pushAndRemoveUntil(
                context,
                MaterialPageRoute(builder: (_) => const BottomNavigation()),
                (_) => false,
              );
            },
          ),
          const SizedBox(height: 12),
          TextButton(
            onPressed: () {
              Navigator.pushAndRemoveUntil(
                context,
                MaterialPageRoute(builder: (_) => const BottomNavigation()),
                (_) => false,
              );
            },
            child: const Text('BACK TO HOME', style: TextStyle(color: AppTheme.coolGrey)),
          ),
        ],
      );
    } else {
      return Column(
        children: [
          GoldButton(
            label: 'TRY AGAIN',
            onPressed: () {
              Navigator.pushReplacement(
                context,
                MaterialPageRoute(builder: (_) => const CartScreen()),
              );
            },
          ),
          const SizedBox(height: 12),
          TextButton(
            onPressed: () {
              Navigator.pushAndRemoveUntil(
                context,
                MaterialPageRoute(builder: (_) => const BottomNavigation()),
                (_) => false,
              );
            },
            child: const Text('GO TO HOME', style: TextStyle(color: AppTheme.coolGrey)),
          ),
        ],
      );
    }
  }
}
