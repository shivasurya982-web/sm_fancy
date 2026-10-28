import 'dart:async';
import 'package:flutter/material.dart';
import 'package:flutter/foundation.dart';
import 'config/theme.dart';
import 'services/api_service.dart';
import 'services/wishlist_service.dart';
import 'services/cart_service.dart';
import 'services/category_service.dart';
import 'services/product_service.dart';
import 'services/notification_service.dart';
import 'services/local_notification_service.dart';
import 'package:permission_handler/permission_handler.dart';
import 'screens/splash_screen.dart';

void main() async {
  WidgetsFlutterBinding.ensureInitialized();

  // Suppress Flutter Web Engine assertions (e.g. viewInsets calculation glitches during devtools resize / keyboard dismiss)
  FlutterError.onError = (FlutterErrorDetails details) {
    final msg = details.exceptionAsString();
    if (msg.contains('viewInsets cannot be negative') || msg.contains('texImage2D')) {
      return;
    }
    FlutterError.presentError(details);
  };
  PlatformDispatcher.instance.onError = (Object error, StackTrace stack) {
    final msg = error.toString();
    if (msg.contains('viewInsets cannot be negative') || msg.contains('texImage2D')) {
      return true; // Handled
    }
    return false;
  };

  // Handle font loading issues on some networks/browsers gracefully
  if (kIsWeb) {
    debugPrint('Running in Web mode - skipping native-only services');
  }

  debugPrint('FancyWorld Luxury: Initializing Services...');
  await ApiService.init();
  await LocalNotificationService.init();
  
  if (!kIsWeb) {
    await Permission.notification.request();
  }
  
  // High-performance background hydration. 
  _hydrateData();

  debugPrint('FancyWorld Luxury: Services Ready.');
  runApp(const FancyWorldApp());
}

Future<void> _hydrateData() async {
  // We use individual try-catches to ensure one service failing 
  // doesn't stop the others or crash the app thread.
  try { await WishlistService.loadWishlist(); } catch (e) { debugPrint('Hydrate Wishlist Error: $e'); }
  try { await CartService.fetchCart(); } catch (e) { debugPrint('Hydrate Cart Error: $e'); }
  try { await CategoryService.fetchCategories(); } catch (e) { debugPrint('Hydrate Categories Error: $e'); }
  try { await ProductService.fetchProducts(); } catch (e) { debugPrint('Hydrate Products Error: $e'); }
  try { await NotificationService.fetchMyNotifications(); } catch (e) { debugPrint('Hydrate Notifications Error: $e'); }
  
  debugPrint('FancyWorld Luxury: Background Hydration Cycle Complete.');
}

class FancyWorldApp extends StatelessWidget {
  const FancyWorldApp({super.key});

  @override
  Widget build(BuildContext context) {
    return MaterialApp(
      debugShowCheckedModeBanner: false,
      title: 'Siva Murugan Fancy',
      themeMode: ThemeMode.system,
      theme: AppTheme.lightTheme,
      darkTheme: AppTheme.darkTheme,
      home: const SplashScreen(),
    );
  }
}
