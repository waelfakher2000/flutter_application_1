import 'dart:convert';
import 'package:flutter/foundation.dart';
import 'package:flutter_secure_storage/flutter_secure_storage.dart';
import 'package:http/http.dart' as http;
import 'package:firebase_messaging/firebase_messaging.dart';
import 'backend_client.dart' as backend;

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
    _token = await _storage.read(key: _kTokenKey);
    _email = await _storage.read(key: _kEmailKey);
    if (_token != null) backend.setAuthToken(_token);
    backend.setOnUnauthorized(() { logout(); });
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
    backend.setAuthToken(null);
    notifyListeners();
  }
}
