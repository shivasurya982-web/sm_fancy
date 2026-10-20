import 'dart:convert';
import 'dart:io';
import 'dart:async';
import 'package:flutter/foundation.dart';
import 'package:http/http.dart' as http;
import 'package:shared_preferences/shared_preferences.dart';
import 'socket_service.dart';

class ApiService {
  static const String _productionBaseUrl = 'https://sm-fancy-backend.onrender.com/api';

  static String? _token;
  static String? currentUserId;
  static String currentUserRole = 'user';
  static String currentUserName = '';
  static String currentUserEmail = '';

  static const Duration _timeout = Duration(seconds: 15);
  static String? _resolvedBaseUrl;
  static final http.Client _client = http.Client();

  static Future<String> getActiveBaseUrl() async {
    if (_resolvedBaseUrl != null) return _resolvedBaseUrl!;

    // 1. Check if explicitly configured via --dart-define=API_BASE_URL=...
    const configuredBaseUrl = String.fromEnvironment('API_BASE_URL');
    if (configuredBaseUrl.isNotEmpty) {
      final sanitized = configuredBaseUrl.endsWith('/')
          ? configuredBaseUrl.substring(0, configuredBaseUrl.length - 1)
          : configuredBaseUrl;
      _resolvedBaseUrl = sanitized.endsWith('/api') ? sanitized : '$sanitized/api';
      return _resolvedBaseUrl!;
    }

    // 2. In Release Mode, use Render Production Backend
    if (kReleaseMode) {
      _resolvedBaseUrl = _productionBaseUrl;
      return _resolvedBaseUrl!;
    }

    // 3. Fast Parallel Probing of Dev/Local Candidates
    final candidates = kIsWeb
        ? [
            'http://127.0.0.1:5050/api',
            'http://localhost:5050/api',
            _productionBaseUrl,
          ]
        : [
            'http://127.0.0.1:5050/api',   // Local Dev / USB Reverse
            'http://localhost:5050/api',   // Localhost
            'http://10.0.2.2:5050/api',    // Android Emulator
            'http://10.1.7.106:5050/api',  // Local Wi-Fi IP
            _productionBaseUrl,            // Render Cloud Production
          ];

    try {
      final String winner = await Future.any(candidates.map((candidate) async {
        final res = await _client
            .get(Uri.parse('$candidate/health'))
            .timeout(const Duration(milliseconds: 600));
        if (res.statusCode == 200) {
          return candidate;
        }
        throw 'Failed probe: $candidate';
      }));

      _resolvedBaseUrl = winner;
      debugPrint('✅ ApiService connected to backend: $_resolvedBaseUrl');
      return _resolvedBaseUrl!;
    } catch (_) {
      // Fallback to production if all fast probes fail
      _resolvedBaseUrl = _productionBaseUrl;
      return _resolvedBaseUrl!;
    }
  }

  static String get baseUrl => _resolvedBaseUrl ?? _productionBaseUrl;

  static bool get isLoggedIn => _token != null && _token!.isNotEmpty;

  static Future<void> init() async {
    await getActiveBaseUrl();

    final prefs = await SharedPreferences.getInstance();
    _token = prefs.getString('token');
    currentUserId = prefs.getString('userId');
    currentUserRole = prefs.getString('userRole') ?? 'user';
    currentUserName = prefs.getString('userName') ?? '';
    currentUserEmail = prefs.getString('userEmail') ?? '';

    if (currentUserId != null && currentUserId!.isNotEmpty) {
      SocketService.connect(currentUserId!);
    }
  }

  static Future<Map<String, String>> authHeaders() async {
    return await _headers();
  }

  static Future<void> logout() async {
    final prefs = await SharedPreferences.getInstance();
    await prefs.remove('token');
    await prefs.remove('userId');
    await prefs.remove('userRole');
    await prefs.remove('userName');
    await prefs.remove('userEmail');

    SocketService.disconnect();
    _token = null;
    currentUserId = null;
    currentUserRole = 'user';
    currentUserName = '';
    currentUserEmail = '';
  }

  static Future<Map<String, String>> _headers() async {
    final headers = <String, String>{'Content-Type': 'application/json'};
    if (_token != null && _token!.isNotEmpty) {
      headers['Authorization'] = 'Bearer $_token';
    }
    return headers;
  }

  static Future<dynamic> get(String endpoint, {int retries = 1}) async {
    final List<String> authRequired = ['/cart', '/orders', '/auth/me', '/users', '/analytics/dashboard', '/addresses'];
    final needsAuth = authRequired.any((path) => endpoint == path || endpoint.startsWith('$path/'));

    if (needsAuth && !isLoggedIn) return null;
    
    final activeBase = await getActiveBaseUrl();
    final url = '$activeBase$endpoint';
    try {
      final response = await _client.get(Uri.parse(url), headers: await _headers()).timeout(_timeout);
      return _handleResponse(response);
    } catch (e) {
      if (retries > 0 && _isNetworkError(e)) return get(endpoint, retries: retries - 1);
      _handleError(e, 'GET $endpoint');
    }
  }

  static Future<dynamic> post(String endpoint, Map<String, dynamic> body, {int retries = 0}) async {
    final activeBase = await getActiveBaseUrl();
    final url = '$activeBase$endpoint';
    try {
      final response = await _client.post(Uri.parse(url), headers: await _headers(), body: jsonEncode(body)).timeout(_timeout);
      return _handleResponse(response);
    } catch (e) {
      if (retries > 0 && _isNetworkError(e)) return post(endpoint, body, retries: retries - 1);
      _handleError(e, 'POST $endpoint');
    }
  }

  static Future<dynamic> put(String endpoint, Map<String, dynamic> body) async {
    final activeBase = await getActiveBaseUrl();
    try {
      final response = await _client.put(Uri.parse('$activeBase$endpoint'), headers: await _headers(), body: jsonEncode(body)).timeout(_timeout);
      return _handleResponse(response);
    } catch (e) {
      _handleError(e, 'PUT $endpoint');
    }
  }

  static Future<dynamic> delete(String endpoint) async {
    final activeBase = await getActiveBaseUrl();
    try {
      final response = await _client.delete(Uri.parse('$activeBase$endpoint'), headers: await _headers()).timeout(_timeout);
      return _handleResponse(response);
    } catch (e) {
      _handleError(e, 'DELETE $endpoint');
    }
  }

  static bool _isNetworkError(dynamic e) {
    return e is SocketException || e is http.ClientException || e is TimeoutException;
  }

  static dynamic _handleResponse(http.Response response) {
    dynamic data;
    try {
      data = jsonDecode(response.body);
    } catch (_) {}

    if (response.statusCode >= 200 && response.statusCode < 300) {
      return data;
    }
    
    if (response.statusCode == 401 || response.statusCode == 403) {
      logout();
    }
    
    final message = (data != null && data['message'] != null) 
        ? data['message'].toString() 
        : 'Request failed (${response.statusCode})';
    throw message;
  }

  static void _handleError(dynamic e, String context) {
    debugPrint('API Error [$context]: $e');
    if (e is String) throw e; 

    final errStr = e.toString();
    if (e is SocketException || errStr.contains('refused')) {
      throw 'Server unreachable ($baseUrl). Ensure your internet connection is active.';
    } else if (e is TimeoutException || errStr.contains('Timeout')) {
      throw 'Connection timed out ($baseUrl). The server may be starting up, please try again.';
    } else {
      throw 'An unexpected error occurred: $e';
    }
  }

  // ==========================
  // AUTH
  // ==========================

  static Future<Map<String, dynamic>> register({
    required String name,
    required String email,
    required String password,
    String recoveryHint = '',
  }) async {
    final data = await post('/auth/register', {
      'name': name,
      'email': email,
      'password': password,
      'recoveryHint': recoveryHint,
    });
    return Map<String, dynamic>.from(data);
  }

  static Future<Map<String, dynamic>> login(String email, String password) async {
    final data = await post('/auth/login', {
      'email': email,
      'password': password,
    });

    final prefs = await SharedPreferences.getInstance();
    await prefs.setString('token', data['token']);
    await prefs.setString('userId', data['user']['id'].toString());
    await prefs.setString('userRole', data['user']['role']);
    await prefs.setString('userName', data['user']['name']);
    await prefs.setString('userEmail', data['user']['email']);

    _token = data['token'];
    currentUserId = data['user']['id'].toString();
    currentUserRole = data['user']['role'];
    currentUserName = data['user']['name'];
    currentUserEmail = data['user']['email'];

    SocketService.connect(currentUserId!);
    return Map<String, dynamic>.from(data);
  }
}
