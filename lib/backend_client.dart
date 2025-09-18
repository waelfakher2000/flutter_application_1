import 'dart:convert';
import 'dart:async';
import 'package:flutter/foundation.dart';
import 'package:http/http.dart' as http;
import 'package:shared_preferences/shared_preferences.dart';

import 'project_model.dart';

// Resolve backend base URL from --dart-define or a stored preference.
const String _kBackendUrlDefine = String.fromEnvironment('BACKEND_URL');

Future<String?> resolveBackendUrl() async {
  if (_kBackendUrlDefine.isNotEmpty) return _kBackendUrlDefine;
  try {
    final prefs = await SharedPreferences.getInstance();
    final v = prefs.getString('backend_url');
    if (v != null && v.isNotEmpty) return v;
  } catch (_) {}
  return null;
}

Map<String, dynamic> _toBackendProject(Project p) {
  final alertsEnabled = (p.minThreshold != null) || (p.maxThreshold != null);
  return {
    'id': p.id,
    'name': p.name,
    'broker': p.broker,
    'port': p.port,
    'topic': p.topic,
    'username': p.username,
    'password': p.password,
    'storeHistory': p.storeHistory == true,
    'multiplier': p.multiplier,
    'offset': p.offset,
    'sensorType': p.sensorType.toString(),
    'tankType': p.tankType.toString(),
    // Map app thresholds to backend alerts
    'alertsEnabled': alertsEnabled,
    'alertLow': p.minThreshold,
    'alertHigh': p.maxThreshold,
    // Reasonable defaults; backend also defaults if omitted
    'alertCooldownSec': 1800,
    'notifyOnRecover': true,
  };
}

Future<void> upsertProjectToBackend(Project p) async {
  try {
    final base = await resolveBackendUrl();
    if (base == null || base.isEmpty) {
      debugPrint('[backend] Skipping upsert: BACKEND_URL not configured');
      return;
    }
    final uri = Uri.parse(base.endsWith('/') ? '${base}projects' : '$base/projects');
    final body = jsonEncode(_toBackendProject(p));
    final resp = await http.post(
      uri,
      headers: {
        'Content-Type': 'application/json',
        if (_authToken != null) 'Authorization': 'Bearer ' + _authToken!,
      },
      body: body,
    );
    if (resp.statusCode < 200 || resp.statusCode >= 300) {
      debugPrint('[backend] Upsert failed: ${resp.statusCode} ${resp.body}');
    }
    if (resp.statusCode == 401 && _onUnauthorized != null) { _onUnauthorized!(); }
  } catch (e) {
    debugPrint('[backend] Upsert error: $e');
  }
}

Future<void> upsertProjectsToBackend(Iterable<Project> projects) async {
  for (final p in projects) {
    // fire-and-forget to avoid blocking UI; small delay could be added if needed
    unawaited(upsertProjectToBackend(p));
  }
}

Future<void> requestBridgeReload() async {
  try {
    final base = await resolveBackendUrl();
    if (base == null || base.isEmpty) return;
    final uri = Uri.parse(base.endsWith('/') ? '${base}bridge/reload' : '$base/bridge/reload');
    await http.post(uri, headers: { if (_authToken != null) 'Authorization': 'Bearer ' + _authToken! });
  } catch (_) {}
}

String? _authToken; // set by Auth integration
void setAuthToken(String? token) { _authToken = token; }
VoidCallback? _onUnauthorized;
void setOnUnauthorized(VoidCallback? cb) { _onUnauthorized = cb; }
