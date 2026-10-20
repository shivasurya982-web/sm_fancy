import 'api_service.dart';

class SettingsService {
  static Map<String, dynamic>? _cachedSettings;

  static Future<Map<String, dynamic>> getSettings({bool forceRefresh = false}) async {
    if (!forceRefresh && _cachedSettings != null) return _cachedSettings!;
    
    try {
      final response = await ApiService.get('/settings');
      if (response != null && response is Map<String, dynamic>) {
        _cachedSettings = response;
        return response;
      }
    } catch (_) {}

    return _cachedSettings ?? {};
  }

  static Future<void> updateSettings(Map<String, dynamic> settings) async {
    await ApiService.post('/settings', settings);
    _cachedSettings = settings;
  }

  static void clearCache() {
    _cachedSettings = null;
  }
}
