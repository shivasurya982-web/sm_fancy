import 'dart:async';
import 'dart:ui';
import 'package:flutter/material.dart';
import 'package:flutter_animate/flutter_animate.dart';
import 'package:intl/intl.dart';
import 'package:app_links/app_links.dart';

import 'screens/home_screen.dart';
import 'screens/wishlist_screen.dart';
import 'screens/cart_screen.dart';
import 'screens/orders_screen.dart';
import 'screens/profile_screen.dart';
import 'screens/login_screen.dart';
import 'screens/user_chat_redirect.dart';
import 'screens/payment_result_screen.dart';
import 'services/notification_service.dart';
import 'services/cart_service.dart';
import 'services/api_service.dart';
import 'services/settings_service.dart';
import 'services/payment_service.dart';
import 'package:url_launcher/url_launcher.dart';
import '../config/theme.dart';
import 'widgets/sparkle_background.dart';

class BottomNavigation extends StatefulWidget {
  const BottomNavigation({super.key});

  @override
  State<BottomNavigation> createState() => _BottomNavigationState();
}

class _BottomNavigationState extends State<BottomNavigation> {
  int currentIndex = 0;
  late AppLinks _appLinks;
  StreamSubscription<Uri>? _appLinksSub;

  @override
  void initState() {
    super.initState();
    if (ApiService.isLoggedIn) {
      NotificationService.fetchMyNotifications();
    }
    _initAppLinksAndPendingPayments();
  }

  @override
  void dispose() {
    _appLinksSub?.cancel();
    super.dispose();
  }

  Future<void> _initAppLinksAndPendingPayments() async {
    _appLinks = AppLinks();
    
    // Check initial deep link when app opens via link
    try {
      final initialUri = await _appLinks.getInitialLink();
      if (initialUri != null) {
        _handlePaymentDeepLink(initialUri);
      }
    } catch (_) {}

    // Listen to deep links while running
    _appLinksSub = _appLinks.uriLinkStream.listen((uri) {
      _handlePaymentDeepLink(uri);
    });

    // Check for pending order recovery if app was killed/reopened during payment
    _checkPendingPaymentStatus();
  }

  Future<void> _checkPendingPaymentStatus() async {
    try {
      final pendingOrderId = await PaymentService.getPendingOrderId();
      if (pendingOrderId != null && pendingOrderId.isNotEmpty) {
        final res = await PaymentService.checkPaymentStatus(pendingOrderId);
        final String status = (res['paymentStatus'] ?? 'Pending').toString();
        if (status != 'Pending') {
          await PaymentService.clearPendingOrderId();
          if (status == 'Paid') {
            await CartService.clearCart();
          }
          if (mounted) {
            Navigator.push(
              context,
              MaterialPageRoute(
                builder: (_) => PaymentResultScreen(
                  status: status,
                  orderId: pendingOrderId,
                  orderNumber: res['orderNumber'],
                  amount: (res['amountToPay'] as num?)?.toDouble(),
                ),
              ),
            );
          }
        }
      }
    } catch (_) {}
  }

  Future<void> _handlePaymentDeepLink(Uri uri) async {
    if (uri.scheme == 'fancyworld' || uri.scheme == 'smfancy' || uri.toString().contains('payment-done')) {
      final orderId = uri.queryParameters['order'] ?? uri.queryParameters['ref'] ?? await PaymentService.getPendingOrderId();
      if (orderId != null && orderId.isNotEmpty) {
        final res = await PaymentService.checkPaymentStatus(orderId);
        final String status = (res['paymentStatus'] ?? 'Pending').toString();
        await PaymentService.clearPendingOrderId();
        if (status == 'Paid') {
          await CartService.clearCart();
        }
        if (mounted) {
          Navigator.push(
            context,
            MaterialPageRoute(
              builder: (_) => PaymentResultScreen(
                status: status,
                orderId: orderId,
                orderNumber: res['orderNumber'],
                amount: (res['amountToPay'] as num?)?.toDouble(),
              ),
            ),
          );
        }
      }
    }
  }

  final List<Map<String, dynamic>> _navigationItems = [
    {
      'title': 'SHOP',
      'icon': Icons.explore_outlined,
      'activeIcon': Icons.explore_rounded,
      'screen': const HomeScreen(),
      'requiresAuth': false,
    },
    {
      'title': 'WISHLIST',
      'icon': Icons.favorite_border_rounded,
      'activeIcon': Icons.favorite_rounded,
      'screen': const WishlistScreen(),
      'requiresAuth': false,
    },
    {
      'title': 'CART',
      'icon': Icons.shopping_bag_outlined,
      'activeIcon': Icons.shopping_bag_rounded,
      'screen': const CartScreen(),
      'requiresAuth': false,
    },
    {
      'title': 'ORDERS',
      'icon': Icons.receipt_long_outlined,
      'activeIcon': Icons.receipt_long_rounded,
      'screen': const OrdersScreen(),
      'requiresAuth': true,
    },
    {
      'title': 'PROFILE',
      'icon': Icons.person_outline_rounded,
      'activeIcon': Icons.person_rounded,
      'screen': const ProfileScreen(),
      'requiresAuth': true,
    },
  ];

  void _onTabTapped(int index) {
    final item = _navigationItems[index];
    if (item['requiresAuth'] == true && !ApiService.isLoggedIn) {
      _showLoginPrompt();
      return;
    }
    setState(() => currentIndex = index);
  }

  void _showLoginPrompt() {
    showDialog(
      context: context,
      builder: (ctx) => AlertDialog(
        backgroundColor: AppTheme.deepCharcoal,
        shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(30), side: const BorderSide(color: AppTheme.platinumBorder)),
        title: const Text('LOGIN REQUIRED', style: TextStyle(fontSize: 14, fontWeight: FontWeight.w900, letterSpacing: 1)),
        content: const Text('Please login to explore more.', style: TextStyle(color: AppTheme.coolGrey)),
        actions: [
          TextButton(
            onPressed: () => Navigator.pop(ctx),
            child: const Text('DISMISS', style: TextStyle(color: AppTheme.coolGrey)),
          ),
          ElevatedButton(
            onPressed: () {
              Navigator.pop(ctx);
              Navigator.pushReplacement(context, MaterialPageRoute(builder: (_) => const LoginScreen()));
            },
            child: const Text('LOG IN'),
          ),
        ],
      ),
    );
  }

  void _showNotificationOverlay() {
    NotificationService.markAllRead();
    final double screenWidth = MediaQuery.of(context).size.width;
    final bool isWeb = screenWidth > 800;

    showModalBottomSheet(
      context: context,
      backgroundColor: Colors.transparent,
      isScrollControlled: true,
      barrierColor: Colors.black54,
      builder: (ctx) => Align(
        alignment: Alignment.bottomCenter,
        child: ConstrainedBox(
          constraints: BoxConstraints(maxWidth: isWeb ? 500 : double.infinity, maxHeight: MediaQuery.of(context).size.height * 0.65),
          child: Container(
            margin: const EdgeInsets.all(16),
            decoration: BoxDecoration(
              color: AppTheme.deepCharcoal.withValues(alpha: 0.98),
              borderRadius: BorderRadius.circular(32),
              border: Border.all(color: AppTheme.glassBorder, width: 1.2),
              boxShadow: [BoxShadow(color: Colors.black.withValues(alpha: 0.6), blurRadius: 30, offset: const Offset(0, -10))],
            ),
            child: Column(
              mainAxisSize: MainAxisSize.min,
              children: [
                const SizedBox(height: 12),
                Container(width: 40, height: 4, decoration: BoxDecoration(color: Colors.white10, borderRadius: BorderRadius.circular(2))),
                Padding(
                  padding: const EdgeInsets.fromLTRB(24, 20, 12, 12),
                  child: Row(
                    mainAxisAlignment: MainAxisAlignment.spaceBetween,
                    children: [
                      const Text('NOTIFICATIONS', style: TextStyle(color: Colors.white, fontWeight: FontWeight.w900, fontSize: 12, letterSpacing: 2)),
                      IconButton(icon: const Icon(Icons.close_rounded, color: AppTheme.coolGrey, size: 20), onPressed: () => Navigator.pop(ctx)),
                    ],
                  ),
                ),
                const Divider(color: AppTheme.glassBorder, height: 1),
                Expanded(
                  child: ValueListenableBuilder<List<dynamic>>(
                    valueListenable: NotificationService.notificationsNotifier,
                    builder: (context, notifications, _) {
                      if (notifications.isEmpty) {
                        return const Center(child: Text('NO NEW ALERTS', style: TextStyle(color: AppTheme.coolGrey, fontSize: 10, fontWeight: FontWeight.w900, letterSpacing: 1.5)));
                      }
                      return ListView.separated(
                        padding: const EdgeInsets.fromLTRB(20, 16, 20, 32),
                        itemCount: notifications.length,
                        separatorBuilder: (_, __) => const SizedBox(height: 16),
                        itemBuilder: (context, index) {
                          final n = notifications[index];
                          final String title = n['title']?.toString() ?? '';
                          final String body = n['body']?.toString() ?? '';
                          final bool isDelivered = title.toLowerCase().contains('delivered') || body.toLowerCase().contains('delivered');

                          return Container(
                            padding: const EdgeInsets.all(16),
                            decoration: BoxDecoration(color: Colors.white.withValues(alpha: 0.03), borderRadius: BorderRadius.circular(20), border: Border.all(color: Colors.white10)),
                            child: Row(
                              crossAxisAlignment: CrossAxisAlignment.start,
                              children: [
                                Container(padding: const EdgeInsets.all(8), decoration: BoxDecoration(color: AppTheme.brushedPlatinum.withValues(alpha: 0.1), shape: BoxShape.circle), child: Icon(n['type'] == 'order' ? Icons.shopping_bag_outlined : Icons.info_outline_rounded, color: AppTheme.brushedPlatinum, size: 16)),
                                const SizedBox(width: 16),
                                Expanded(
                                  child: Column(
                                    crossAxisAlignment: CrossAxisAlignment.start,
                                    children: [
                                      Row(
                                        mainAxisAlignment: MainAxisAlignment.spaceBetween,
                                        children: [
                                          Expanded(child: Text(title.toUpperCase(), maxLines: 1, overflow: TextOverflow.ellipsis, style: const TextStyle(color: Colors.white, fontWeight: FontWeight.w900, fontSize: 11, letterSpacing: 0.5))),
                                          const SizedBox(width: 8),
                                          Text(n['createdAt'] != null ? DateFormat('dd/MM • hh:mm a').format(DateTime.parse(n['createdAt']).toLocal()) : '', style: const TextStyle(color: Colors.white24, fontSize: 8, fontWeight: FontWeight.bold)),
                                        ],
                                      ),
                                      const SizedBox(height: 4),
                                      Text(body, style: const TextStyle(color: AppTheme.coolGrey, fontSize: 12, height: 1.4, fontWeight: FontWeight.w500)),
                                      if (isDelivered) ...[
                                        const SizedBox(height: 12),
                                        GestureDetector(
                                          onTap: () {
                                            Navigator.pop(ctx);
                                            setState(() => currentIndex = 3);
                                          },
                                          child: Container(
                                            padding: const EdgeInsets.symmetric(horizontal: 12, vertical: 6),
                                            decoration: BoxDecoration(
                                              color: AppTheme.brushedPlatinum.withValues(alpha: 0.12),
                                              borderRadius: BorderRadius.circular(100),
                                              border: Border.all(color: AppTheme.brushedPlatinum, width: 0.8),
                                            ),
                                            child: const Row(
                                              mainAxisSize: MainAxisSize.min,
                                              children: [
                                                Icon(Icons.star_rounded, color: Colors.amber, size: 14),
                                                SizedBox(width: 6),
                                                Text('RATE PRODUCT NOW', style: TextStyle(color: AppTheme.brushedPlatinum, fontSize: 9, fontWeight: FontWeight.w900, letterSpacing: 1)),
                                              ],
                                            ),
                                          ),
                                        ),
                                      ],
                                    ],
                                  ),
                                ),
                                const SizedBox(width: 8),
                                IconButton(
                                  padding: EdgeInsets.zero,
                                  constraints: const BoxConstraints(minWidth: 28, minHeight: 28),
                                  icon: const Icon(Icons.delete_outline_rounded, size: 16, color: AppTheme.error),
                                  onPressed: () {
                                    if (n['_id'] != null) {
                                      NotificationService.deleteNotification(n['_id']);
                                    }
                                  },
                                ),
                              ],
                            ),
                          ).animate().fadeIn(delay: (index * 50).ms).slideY(begin: 0.1, end: 0);
                        },
                      );
                    },
                  ),
                ),
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
    final topBarHeight = MediaQuery.of(context).padding.top + 105;

    return Scaffold(
      backgroundColor: AppTheme.deepCharcoal,
      extendBody: true,
      body: LuxurySparkleBackground(
        child: Center(
          child: ConstrainedBox(
            constraints: BoxConstraints(maxWidth: isWeb ? 500 : double.infinity),
            child: Stack(
              children: [
                Positioned.fill(
                  child: IndexedStack(
                    index: currentIndex,
                    children: _navigationItems.map((item) {
                      return Padding(
                        padding: EdgeInsets.only(top: topBarHeight, bottom: 90),
                        child: item['screen'] as Widget,
                      );
                    }).toList(),
                  ),
                ),
                _buildPlatinumTopBar(context),
                if (MediaQuery.of(context).viewInsets.bottom == 0) _buildPlatinumBottomBar(context),
              ],
            ),
          ),
        ),
      ),
      endDrawer: isWeb ? null : _buildPlatinumDrawer(context),
    );
  }

  Widget _buildPlatinumTopBar(BuildContext context) {
    final bool isLoggedIn = ApiService.isLoggedIn;
    final double screenWidth = MediaQuery.of(context).size.width;
    final bool isNarrow = screenWidth < 360;

    return Positioned(
      top: 10, left: isNarrow ? 8 : 16, right: isNarrow ? 8 : 16,
      child: SafeArea(
        child: ClipRRect(
          borderRadius: BorderRadius.circular(100),
          child: BackdropFilter(
            filter: ImageFilter.blur(sigmaX: 15, sigmaY: 15),
            child: Container(
              padding: EdgeInsets.symmetric(horizontal: isNarrow ? 10 : 16, vertical: 8),
              decoration: BoxDecoration(color: Colors.white.withValues(alpha: 0.05), borderRadius: BorderRadius.circular(100), border: Border.all(color: AppTheme.glassBorder, width: 0.8)),
              child: Row(
                children: [
                  Container(width: 40, height: 40, padding: const EdgeInsets.all(2), decoration: BoxDecoration(shape: BoxShape.circle, border: Border.all(color: AppTheme.platinumBorder.withValues(alpha: 0.3), width: 1)), child: ClipOval(child: Image.asset('assets/images/logo1.png', fit: BoxFit.contain))),
                  SizedBox(width: isNarrow ? 8 : 12),
                  Expanded(
                    child: Column(
                      mainAxisSize: MainAxisSize.min, crossAxisAlignment: CrossAxisAlignment.start,
                      children: [
                        const Text('WELCOME BACK,', style: TextStyle(fontSize: 8, color: AppTheme.coolGrey)),
                        Text(ApiService.currentUserName.toUpperCase(), maxLines: 1, overflow: TextOverflow.ellipsis, style: const TextStyle(fontSize: 9, color: AppTheme.polishedSilver, fontWeight: FontWeight.w900)),
                      ],
                    ),
                  ),
                  if (!isLoggedIn) ...[
                    TextButton(
                      style: TextButton.styleFrom(padding: EdgeInsets.symmetric(horizontal: isNarrow ? 6 : 12)),
                      onPressed: () => Navigator.push(context, MaterialPageRoute(builder: (_) => const LoginScreen())),
                      child: const Text('LOGIN', style: TextStyle(color: AppTheme.brushedPlatinum, fontSize: 10, fontWeight: FontWeight.w900)),
                    ),
                  ],
                  IconButton(
                    padding: EdgeInsets.zero,
                    constraints: const BoxConstraints(minWidth: 36, minHeight: 36),
                    onPressed: () {
                      if (!ApiService.isLoggedIn) {
                        _showLoginPrompt();
                      } else {
                        _showNotificationOverlay();
                      }
                    },
                    icon: _buildNotificationBell(),
                  ),
                  Builder(builder: (ctx) => IconButton(
                    padding: EdgeInsets.zero,
                    constraints: const BoxConstraints(minWidth: 36, minHeight: 36),
                    onPressed: () => Scaffold.of(ctx).openEndDrawer(), 
                    icon: const Icon(Icons.more_vert_rounded, color: AppTheme.brushedPlatinum, size: 22)
                  )),
                ],
              ),
            ),
          ),
        ),
      ),
    );
  }

  Widget _buildPlatinumBottomBar(BuildContext context) {
    final double screenWidth = MediaQuery.of(context).size.width;
    final bool isNarrow = screenWidth < 360;
    final double horizontalMargin = isNarrow ? 12 : 24;

    return Positioned(
      bottom: 24, left: horizontalMargin, right: horizontalMargin,
      child: ClipRRect(
        borderRadius: BorderRadius.circular(100),
        child: BackdropFilter(
          filter: ImageFilter.blur(sigmaX: 20, sigmaY: 20),
          child: Container(
            height: 70,
            decoration: BoxDecoration(color: Colors.white.withValues(alpha: 0.08), borderRadius: BorderRadius.circular(100), border: Border.all(color: AppTheme.glassBorder, width: 1)),
            child: Row(
              mainAxisAlignment: MainAxisAlignment.spaceEvenly,
              children: List.generate(_navigationItems.length, (index) {
                final item = _navigationItems[index];
                final isSelected = currentIndex == index;
                return GestureDetector(
                  onTap: () => _onTabTapped(index),
                  behavior: HitTestBehavior.opaque,
                  child: SizedBox(
                    width: isNarrow ? 44 : 50,
                    child: Column(
                      mainAxisAlignment: MainAxisAlignment.center,
                      children: [
                        AnimatedContainer(duration: const Duration(milliseconds: 300), padding: const EdgeInsets.all(8), decoration: isSelected ? BoxDecoration(shape: BoxShape.circle, boxShadow: AppTheme.sapphireGlow()) : null, child: Stack(clipBehavior: Clip.none, children: [Icon(isSelected ? item['activeIcon'] : item['icon'], color: isSelected ? Colors.white : AppTheme.coolGrey, size: isNarrow ? 20 : 22), if (item['title'] == 'CART') ValueListenableBuilder<int>(valueListenable: CartService.cartCount, builder: (context, count, _) { if (count == 0) return const SizedBox.shrink(); return Positioned(top: -4, right: -4, child: Container(padding: const EdgeInsets.all(4), decoration: const BoxDecoration(color: AppTheme.sapphireBlue, shape: BoxShape.circle), child: Text('$count', style: const TextStyle(color: Colors.white, fontSize: 7, fontWeight: FontWeight.bold)))); })])),
                        if (isSelected) Text(item['title'], maxLines: 1, overflow: TextOverflow.ellipsis, style: const TextStyle(color: Colors.white, fontSize: 7, fontWeight: FontWeight.w900, letterSpacing: 0.5)),
                      ],
                    ),
                  ),
                );
              }),
            ),
          ),
        ),
      ),
    );
  }

  Widget _buildNotificationBell() {
    return ValueListenableBuilder<int>(
      valueListenable: NotificationService.unreadCount,
      builder: (context, count, _) {
        return Stack(clipBehavior: Clip.none, children: [const Icon(Icons.notifications_outlined, color: AppTheme.brushedPlatinum, size: 22), if (count > 0) Positioned(top: -2, right: -2, child: Container(width: 8, height: 8, decoration: const BoxDecoration(color: AppTheme.brushedPlatinum, shape: BoxShape.circle)))]);
      },
    );
  }

  void _handleCall() async {
    if (!ApiService.isLoggedIn) {
      _showLoginPrompt();
      return;
    }
    try {
      final settings = await SettingsService.getSettings();
      final phone = settings['ownerPhone'] ?? '9443039600';
      final url = Uri.parse('tel:$phone');
      if (await canLaunchUrl(url)) await launchUrl(url);
    } catch (_) {}
  }

  Widget _buildPlatinumDrawer(BuildContext context) {
    return Drawer(
      backgroundColor: Colors.transparent,
      child: Container(
        decoration: BoxDecoration(color: AppTheme.deepCharcoal.withValues(alpha: 0.92), border: const Border(right: BorderSide(color: AppTheme.glassBorder, width: 0.8))),
        child: BackdropFilter(
          filter: ImageFilter.blur(sigmaX: 15, sigmaY: 15),
          child: SafeArea(
            child: SingleChildScrollView(
              padding: const EdgeInsets.symmetric(vertical: 20),
              child: Column(
                children: [
                  const SizedBox(height: 20),
                  Container(width: 100, height: 100, decoration: const BoxDecoration(shape: BoxShape.circle), child: Image.asset('assets/images/logo1.png', fit: BoxFit.contain)),
                  const SizedBox(height: 24),
                  const Divider(indent: 32, endIndent: 32, color: AppTheme.glassBorder),
                  const SizedBox(height: 12),
                  _buildDrawerItem(Icons.chat_bubble_outline_rounded, 'CHAT SUPPORT', () { if (ApiService.isLoggedIn) { Navigator.push(context, MaterialPageRoute(builder: (_) => const UserChatRedirect())); } else { Navigator.pop(context); _showLoginPrompt(); } }),
                  _buildDrawerItem(Icons.phone_outlined, 'CALL US', _handleCall),
                  const SizedBox(height: 12),
                  const Divider(indent: 32, endIndent: 32, color: AppTheme.glassBorder),
                  const SizedBox(height: 12),
                  _buildDrawerItem(Icons.explore_outlined, 'SHOP', () { Navigator.pop(context); setState(() => currentIndex = 0); }),
                  _buildDrawerItem(Icons.favorite_border_rounded, 'WISHLIST', () { Navigator.pop(context); _onTabTapped(1); }),
                  _buildDrawerItem(Icons.shopping_bag_outlined, 'CART', () { Navigator.pop(context); _onTabTapped(2); }),
                  _buildDrawerItem(Icons.receipt_long_outlined, 'ORDERS', () { Navigator.pop(context); _onTabTapped(3); }),
                  _buildDrawerItem(Icons.person_outline_rounded, 'PROFILE', () { Navigator.pop(context); _onTabTapped(4); }),
                  const SizedBox(height: 24),
                  if (ApiService.isLoggedIn) _buildDrawerItem(Icons.logout_rounded, 'LOGOUT', () => ApiService.logout().then((_) => Navigator.pushReplacement(context, MaterialPageRoute(builder: (_) => const LoginScreen())))),
                  const SizedBox(height: 20),
                ],
              ),
            ),
          ),
        ),
      ),
    );
  }

  Widget _buildDrawerItem(IconData icon, String title, VoidCallback onTap) {
    return Material(color: Colors.transparent, child: ListTile(onTap: onTap, leading: Icon(icon, color: AppTheme.brushedPlatinum, size: 20), title: Text(title, style: const TextStyle(color: AppTheme.polishedSilver, fontSize: 11, fontWeight: FontWeight.w800, letterSpacing: 1.5))));
  }
}
