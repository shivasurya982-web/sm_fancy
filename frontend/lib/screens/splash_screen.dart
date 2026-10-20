import 'dart:async';
import 'package:flutter/material.dart';
import 'package:flutter_animate/flutter_animate.dart';
import '../bottom_navigation.dart';
import '../services/auth_service.dart';
import '../services/api_service.dart';
import '../services/settings_service.dart';
import '../config/theme.dart';
import 'admin_dashboard_screen.dart';

class SplashScreen extends StatefulWidget {
  const SplashScreen({super.key});

  @override
  State<SplashScreen> createState() => _SplashScreenState();
}

class _SplashScreenState extends State<SplashScreen> {
  String _tagline = 'Shine Bright, Live Bold.';

  @override
  void initState() {
    super.initState();
    _loadSettings();
    _navigateToNext();
  }

  Future<void> _loadSettings() async {
    try {
      final settings = await SettingsService.getSettings().timeout(const Duration(milliseconds: 2500));
      if (mounted) {
        setState(() {
          _tagline = settings['splashTagline'] ?? _tagline;
        });
      }
    } catch (_) {}
  }

  Future<void> _navigateToNext() async {
    final startTime = DateTime.now();
    final bool loggedIn = await AuthService.isLoggedIn().timeout(
      const Duration(seconds: 5),
      onTimeout: () => false,
    );

    final elapsed = DateTime.now().difference(startTime);
    final remaining = const Duration(milliseconds: 3000) - elapsed;

    if (remaining > Duration.zero) {
      await Future.delayed(remaining);
    }

    if (!mounted) return;

    if (loggedIn) {
      if (ApiService.currentUserRole == 'admin') {
        Navigator.pushReplacement(
          context,
          MaterialPageRoute(builder: (_) => const AdminDashboardScreen()),
        );
      } else {
        Navigator.pushReplacement(
          context,
          MaterialPageRoute(builder: (_) => const BottomNavigation()),
        );
      }
    } else {
      Navigator.pushReplacement(
        context,
        MaterialPageRoute(builder: (_) => const BottomNavigation()),
      );
    }
  }

  @override
  Widget build(BuildContext context) {
    return Scaffold(
      backgroundColor: AppTheme.matteBlack,
      body: Container(
        width: double.infinity,
        decoration: AppTheme.filigreeBackground(),
        child: Column(
          mainAxisAlignment: MainAxisAlignment.center,
          children: [
            Container(
              width: 180,
              height: 180,
              decoration: const BoxDecoration(
                shape: BoxShape.circle,
              ),
              child: Image.asset(
                'assets/images/logo1.png',
                fit: BoxFit.contain,
              ),
            ).animate()
              .fadeIn(duration: 800.ms)
              .scale(begin: const Offset(0.8, 0.8), curve: Curves.easeOutBack),

            const SizedBox(height: 36),

            Text(
              'FANCY WORLD',
              style: Theme.of(context).textTheme.labelSmall?.copyWith(
                letterSpacing: 8,
                fontSize: 14,
              ),
            ).animate().fadeIn(delay: 400.ms).slideY(begin: 0.2, end: 0),

            const SizedBox(height: 16),

            Container(
              width: 30,
              height: 0.5,
              color: AppTheme.brushedPlatinum,
            ).animate().scaleX(delay: 800.ms, duration: 600.ms),

            const SizedBox(height: 16),

            Text(
              _tagline.toUpperCase(),
              style: const TextStyle(
                color: AppTheme.coolGrey,
                fontSize: 9,
                letterSpacing: 2,
                fontWeight: FontWeight.w400,
              ),
            ).animate().fadeIn(delay: 1000.ms),
          ],
        ),
      ),
    );
  }
}
