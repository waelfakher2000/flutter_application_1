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
  'noiseDeadbandMeters': p.noiseDeadbandMeters,
    'sensorType': p.sensorType.toString(),
    'tankType': p.tankType.toString(),
    // Full dimensional and calculation fields
    'height': p.height,
    'diameter': p.diameter,
    'length': p.length,
    'width': p.width,
    'wallThickness': p.wallThickness,
    'connectedTankCount': p.connectedTankCount,
    'useCustomFormula': p.useCustomFormula,
    'customFormula': p.customFormula,
    // Control & presence
    'useControlButton': p.useControlButton,
    'controlTopic': p.controlTopic,
    'controlMode': p.controlMode.toString(),
    'onValue': p.onValue,
    'offValue': p.offValue,
    'autoControl': p.autoControl,
    'controlRetained': p.controlRetained,
    'controlQos': p.controlQos.toString(),
    'lastWillTopic': p.lastWillTopic,
    // Parsing / JSON extraction
    'payloadIsJson': p.payloadIsJson,
    'jsonFieldIndex': p.jsonFieldIndex,
    'jsonKeyName': p.jsonKeyName,
    'displayTimeFromJson': p.displayTimeFromJson,
    'jsonTimeFieldIndex': p.jsonTimeFieldIndex,
    'jsonTimeKeyName': p.jsonTimeKeyName,
    // Scale UI
    'graduationSide': p.graduationSide.toString(),
    'scaleMajorTickMeters': p.scaleMajorTickMeters,
    'scaleMinorDivisions': p.scaleMinorDivisions,
    'createdAt': p.createdAt.toIso8601String(),
  // Persist raw thresholds for cross-device sync
  'minThreshold': p.minThreshold,
  'maxThreshold': p.maxThreshold,
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
    if (_authToken == null) {
      // Avoid generating unauthorized noise before auth loads.
      debugPrint('[backend] Skip upsert (no auth token yet) id=${p.id}');
      return;
    }
    final uri = Uri.parse(base.endsWith('/') ? '${base}projects' : '$base/projects');
    final body = jsonEncode(_toBackendProject(p));
    final resp = await http.post(
      uri,
      headers: {
        'Content-Type': 'application/json',
        if (_authToken != null) 'Authorization': 'Bearer $_authToken',
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
    if (_authToken == null) {
      debugPrint('[backend] Skip bridge reload (no auth token yet)');
      return;
    }
    final uri = Uri.parse(base.endsWith('/') ? '${base}bridge/reload' : '$base/bridge/reload');
    await http.post(uri, headers: { if (_authToken != null) 'Authorization': 'Bearer $_authToken' });
  } catch (e) {
    debugPrint('[backend] bridge reload error: $e');
  }
}

Map<String, String> _authJsonHeaders() => <String, String>{
  'Content-Type': 'application/json',
  if (_authToken != null) 'Authorization': 'Bearer $_authToken',
};

Future<Map<String, dynamic>> pruneDevices() async {
  final base = await resolveBackendUrl();
  if (base == null) throw 'Backend URL not configured';
  if (_authToken == null) throw 'Not authenticated';
  final url = base.endsWith('/') ? '${base}devices/prune' : '$base/devices/prune';
  final resp = await http.post(Uri.parse(url), headers: _authJsonHeaders(), body: jsonEncode({}));
  if (resp.statusCode == 401 && _onUnauthorized != null) { _onUnauthorized!(); }
  if (resp.statusCode < 200 || resp.statusCode >= 300) {
    throw 'Request failed (${resp.statusCode})';
  }
  final data = jsonDecode(resp.body) as Map<String, dynamic>;
  if (data['ok'] != true) throw 'Malformed response';
  return data;
}

Future<List<dynamic>> listDevices() async {
  final base = await resolveBackendUrl();
  if (base == null) throw 'Backend URL not configured';
  if (_authToken == null) throw 'Not authenticated';
  final url = base.endsWith('/') ? '${base}devices' : '$base/devices';
  final resp = await http.get(Uri.parse(url), headers: _authJsonHeaders());
  if (resp.statusCode == 401 && _onUnauthorized != null) { _onUnauthorized!(); }
  if (resp.statusCode < 200 || resp.statusCode >= 300) {
    throw 'Request failed (${resp.statusCode})';
  }
  final data = jsonDecode(resp.body) as Map<String, dynamic>;
  if (data['ok'] != true) throw 'Malformed response';
  return (data['items'] as List?) ?? [];
}

String? _authToken; // set by Auth integration
void setAuthToken(String? token) { _authToken = token; }
VoidCallback? _onUnauthorized;
void setOnUnauthorized(VoidCallback? cb) { _onUnauthorized = cb; }

Future<http.Response> httpGet(Uri uri) async {
  final headers = <String, String>{
    'Accept': 'application/json',
  if (_authToken != null) 'Authorization': 'Bearer $_authToken',
  };
  final resp = await http.get(uri, headers: headers);
  if (resp.statusCode == 401 && _onUnauthorized != null) { _onUnauthorized!(); }
  return resp;
}

Future<List<Map<String, dynamic>>> fetchReadings({required String projectId, int limit = 1000, DateTime? from, DateTime? to}) async {
  final base = await resolveBackendUrl();
  if (base == null || base.isEmpty) return [];
  final params = <String, String>{
    'projectId': projectId,
    'limit': limit.toString(),
  };
  if (from != null) params['from'] = from.toUtc().toIso8601String();
  if (to != null) params['to'] = to.toUtc().toIso8601String();
  final qp = params.entries.map((e) => '${Uri.encodeQueryComponent(e.key)}=${Uri.encodeQueryComponent(e.value)}').join('&');
  final uri = Uri.parse(base.endsWith('/') ? '${base}readings?$qp' : '$base/readings?$qp');
  final resp = await httpGet(uri);
  if (resp.statusCode >= 200 && resp.statusCode < 300) {
    try {
      final decoded = jsonDecode(resp.body) as Map<String, dynamic>;
      final items = (decoded['items'] as List<dynamic>? ?? [])
        .whereType<Map<String, dynamic>>()
        .toList();
      return items;
    } catch (_) { return []; }
  }
  return [];
}

Future<List<Map<String, dynamic>>> fetchProjects() async {
  final base = await resolveBackendUrl();
  if (base == null || base.isEmpty) return [];
  final uri = Uri.parse(base.endsWith('/') ? '${base}projects' : '$base/projects');
  final resp = await httpGet(uri);
  if (resp.statusCode >= 200 && resp.statusCode < 300) {
    try {
      final decoded = jsonDecode(resp.body) as Map<String, dynamic>;
      final items = (decoded['items'] as List<dynamic>? ?? [])
          .whereType<Map<String, dynamic>>()
          .toList();
      return items;
    } catch (_) { return []; }
  }
  return [];
}

Future<void> deleteProjectFromBackend(String id) async {
  try {
    final base = await resolveBackendUrl();
    if (base == null || base.isEmpty) return;
    final uri = Uri.parse(base.endsWith('/') ? '${base}projects/$id' : '$base/projects/$id');
    final headers = <String, String>{
  if (_authToken != null) 'Authorization': 'Bearer $_authToken',
    };
    final resp = await http.delete(uri, headers: headers);
    if (resp.statusCode == 401 && _onUnauthorized != null) { _onUnauthorized!(); }
  } catch (e) {
    debugPrint('[backend] delete error: $e');
  }
}
