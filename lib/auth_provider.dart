import 'dart:convert';
import 'package:flutter/foundation.dart';
import 'package:flutter_secure_storage/flutter_secure_storage.dart';
import 'package:http/http.dart' as http;
import 'package:firebase_messaging/firebase_messaging.dart';
import 'backend_client.dart' as backend;
import 'package:shared_preferences/shared_preferences.dart';

class AuthProvider extends ChangeNotifier {
  static const _kTokenKey = 'auth_token';
  static const _kEmailKey = 'auth_email';
  final _storage = const FlutterSecureStorage();
  String? _token;
  String? _email;
  bool _loading = true;

  String? get token => _token;
  String? get email => _email;
  bool get isAuthenticated => _token != null;
  bool get loading => _loading;

  Future<void> load() async {
    // Primary secure storage
    _token = await _storage.read(key: _kTokenKey);
    _email = await _storage.read(key: _kEmailKey);
    // Fallback: SharedPreferences (diagnostic / resilience if secure storage wiped by reinstall)
    if (_token == null) {
      try {
        final prefs = await SharedPreferences.getInstance();
        _token = prefs.getString(_kTokenKey);
        _email = _email ?? prefs.getString(_kEmailKey);
      } catch (_) {}
    }
    if (_token != null) backend.setAuthToken(_token);

    bool sawUnauthorized = false;
    backend.setOnUnauthorized(() async {
      if (!sawUnauthorized) {
        sawUnauthorized = true;
        // Soft retry: validate token once via /me
        final ok = await _validateToken();
        if (ok) {
          sawUnauthorized = false; // reset if /me succeeded
          return;
        }
      }
      logout();
    });

    // Optional proactive validation (non-blocking)
    if (_token != null) {
      Future.microtask(() async {
        final valid = await _validateToken();
        if (!valid) logout();
      });
    }
    _loading = false;
    notifyListeners();
  }

  Future<String?> signup(String email, String password) async {
    return _authRequest('signup', email, password, autoLogin: true);
  }

  Future<String?> login(String email, String password) async {
    return _authRequest('login', email, password, autoLogin: true);
  }

  Future<String?> _authRequest(String path, String email, String password, {bool autoLogin = false}) async {
    try {
      final base = await backend.resolveBackendUrl();
      if (base == null) return 'Backend URL not configured';
      debugPrint('[Auth] Attempting $path -> base=$base');
      final uri = Uri.parse(base.endsWith('/') ? '$base$path' : '$base/$path');
      final resp = await http.post(uri,
          headers: const {'Content-Type': 'application/json'},
          body: jsonEncode({'email': email.trim(), 'password': password}));
      debugPrint('[Auth] $path response ${resp.statusCode}: ${resp.body}');
      if (resp.statusCode >= 200 && resp.statusCode < 300) {
        final data = jsonDecode(resp.body);
        if (data['ok'] == true && data['token'] != null && autoLogin) {
          _token = data['token'];
          _email = email.trim();
          await _storage.write(key: _kTokenKey, value: _token);
            await _storage.write(key: _kEmailKey, value: _email);
          // Mirror to SharedPreferences for resilience
          try { final prefs = await SharedPreferences.getInstance(); await prefs.setString(_kTokenKey, _token!); if (_email != null) await prefs.setString(_kEmailKey, _email!); } catch (_) {}
          backend.setAuthToken(_token); // propagate token
          // Register device token with backend (if FCM available)
          try {
            final fcmToken = await FirebaseMessaging.instance.getToken();
            if (fcmToken != null) {
              final base = await backend.resolveBackendUrl();
              if (base != null) {
                final uri = Uri.parse(base.endsWith('/') ? '${base}register-device' : '$base/register-device');
                await http.post(uri, headers: {
                  'Content-Type': 'application/json',
                  if (_token != null) 'Authorization': 'Bearer ' + _token!,
                }, body: jsonEncode({'token': fcmToken}));
              }
            }
          } catch (_) {}
          notifyListeners();
          // UI layer should trigger ProjectRepository.syncFromBackend() after login.
          return null;
        }
        return 'Malformed response';
      } else {
        try {
          final data = jsonDecode(resp.body);
          return data['error']?.toString() ?? 'Request failed (${resp.statusCode})';
        } catch (_) {
          return 'Request failed (${resp.statusCode})';
        }
      }
    } catch (e) {
      return e.toString();
    }
  }

  Future<void> logout() async {
    _token = null;
    _email = null;
    await _storage.delete(key: _kTokenKey);
    await _storage.delete(key: _kEmailKey);
    try { final prefs = await SharedPreferences.getInstance(); prefs.remove(_kTokenKey); prefs.remove(_kEmailKey); } catch (_) {}
    backend.setAuthToken(null);
    notifyListeners();
  }

  Future<bool> _validateToken() async {
    try {
      final base = await backend.resolveBackendUrl();
      if (base == null || _token == null) return false;
      final uri = Uri.parse(base.endsWith('/') ? '${base}me' : '$base/me');
      final resp = await http.get(uri, headers: { 'Authorization': 'Bearer ' + _token! });
      if (resp.statusCode >= 200 && resp.statusCode < 300) {
        return true;
      }
    } catch (_) {}
    return false;
  }
}
