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
    debugPrint('[Auth] load() start');
    // Primary secure storage
    try {
      _token = await _storage.read(key: _kTokenKey);
      _email = await _storage.read(key: _kEmailKey);
      debugPrint('[Auth] secure storage token? ${_token != null} email=$_email');
    } catch (e) {
      debugPrint('[Auth] secure storage read error: $e');
    }
    // Fallback: SharedPreferences (diagnostic / resilience if secure storage wiped by reinstall)
    if (_token == null) {
      try {
        final prefs = await SharedPreferences.getInstance();
        _token = prefs.getString(_kTokenKey);
        _email = _email ?? prefs.getString(_kEmailKey);
        debugPrint('[Auth] fallback SharedPreferences token? ${_token != null}');
        if (_token != null) {
          // Mirror back into secure storage so future loads find it in primary location.
            try {
              await _storage.write(key: _kTokenKey, value: _token);
              if (_email != null) await _storage.write(key: _kEmailKey, value: _email);
              debugPrint('[Auth] mirrored token back to secure storage');
            } catch (e) {
              debugPrint('[Auth] mirror to secure storage failed: $e');
            }
        }
      } catch (e) {
        debugPrint('[Auth] SharedPreferences fallback error: $e');
      }
    }
    if (_token != null) {
      backend.setAuthToken(_token);
      debugPrint('[Auth] backend.setAuthToken applied');
      _logTokenClaims();
    } else {
      debugPrint('[Auth] No token found on load');
    }

    bool handlingUnauthorized = false;
    backend.setOnUnauthorized(() async {
      // Skip if we truly have no token loaded (avoid logout loop on startup noise)
      if (_token == null) {
        debugPrint('[Auth] onUnauthorized but token is null -> ignoring (startup race)');
        return;
      }
      if (handlingUnauthorized) return; // collapse bursts
      handlingUnauthorized = true;
      debugPrint('[Auth] onUnauthorized received -> validating via /me');
      final ok = await _validateToken();
      if (ok) {
        debugPrint('[Auth] /me succeeded after unauthorized -> keeping session');
        handlingUnauthorized = false;
        return;
      }
      debugPrint('[Auth] token invalid -> logging out');
      await logout();
      handlingUnauthorized = false;
    });

    // Optional proactive validation (non-blocking)
    if (_token != null) {
      Future.microtask(() async {
        final valid = await _validateToken();
        debugPrint('[Auth] proactive /me validation result: $valid');
        if (!valid) {
          debugPrint('[Auth] proactive validation failed -> logout');
          await logout();
        }
      });
    }
    _loading = false;
    debugPrint('[Auth] load() complete tokenPresent=${_token != null}');
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
          debugPrint('[Auth] stored token (len=${_token?.length})');
          // Mirror to SharedPreferences for resilience
          try { final prefs = await SharedPreferences.getInstance(); await prefs.setString(_kTokenKey, _token!); if (_email != null) await prefs.setString(_kEmailKey, _email!); } catch (_) {}
          backend.setAuthToken(_token); // propagate token
          _logTokenClaims();
          // Register device token with backend (if FCM available)
          try {
            final fcmToken = await FirebaseMessaging.instance.getToken();
            if (fcmToken != null) {
              final base = await backend.resolveBackendUrl();
              if (base != null) {
                final uri = Uri.parse(base.endsWith('/') ? '${base}register-device' : '$base/register-device');
                await http.post(uri, headers: {
                  'Content-Type': 'application/json',
                  if (_token != null) 'Authorization': 'Bearer $_token',
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
    debugPrint('[Auth] logout()');
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
  final resp = await http.get(uri, headers: { 'Authorization': 'Bearer $_token' });
      debugPrint('[Auth] /me status=${resp.statusCode}');
      if (resp.statusCode >= 200 && resp.statusCode < 300) return true;
      if (resp.statusCode == 401) {
        debugPrint('[Auth] /me 401 -> token invalid/expired');
        return false;
      }
      // Non-401 failures (network hiccup, 5xx) are treated as soft valid to avoid logging user out spuriously.
      debugPrint('[Auth] /me non-401 failure (${resp.statusCode}) -> keeping session');
      return true;
    } catch (e) {
      debugPrint('[Auth] /me exception ($e) -> keeping session');
      return true; // network error -> keep session
    }
  }

  void _logTokenClaims() {
    if (_token == null) return;
    try {
      final parts = _token!.split('.');
      if (parts.length != 3) return;
      final payloadB64 = parts[1]
          .replaceAll('-', '+')
          .replaceAll('_', '/')
          .padRight(parts[1].length + (4 - parts[1].length % 4) % 4, '=');
      final decoded = utf8.decode(base64.decode(payloadB64));
      final map = jsonDecode(decoded);
      final exp = map['exp'];
      if (exp is int) {
        final expDt = DateTime.fromMillisecondsSinceEpoch(exp * 1000, isUtc: true);
        final now = DateTime.now().toUtc();
        final remaining = expDt.difference(now);
        debugPrint('[Auth] token exp: $expDt (in ${remaining.inHours}h ${remaining.inMinutes % 60}m)');
      }
    } catch (e) {
      debugPrint('[Auth] token decode failed: $e');
    }
  }
}
