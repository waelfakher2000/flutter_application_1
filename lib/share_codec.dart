import 'dart:convert';
import 'dart:typed_data';
import 'package:flutter/foundation.dart';
import 'package:flutter_application_1/project_model.dart';
import 'dart:io';

// Simple gzip helpers using dart:io (works on mobile/desktop). On web, fall back to plain.
Uint8List _gzipEncode(List<int> bytes) {
  try {
    return Uint8List.fromList(GZipCodec().encode(bytes));
  } catch (_) {
    return Uint8List.fromList(bytes);
  }
}

Uint8List _gzipDecode(List<int> bytes) {
  try {
    return Uint8List.fromList(GZipCodec().decode(bytes));
  } catch (_) {
    return Uint8List.fromList(bytes);
  }
}

class ShareEnvelope {
  final String type; // e.g., "tank_project" or "tank_projects"
  final int version;
  final Map<String, dynamic> body;
  ShareEnvelope({required this.type, required this.version, required this.body});

  Map<String, dynamic> toJson() => {
        'type': type,
        'version': version,
        'body': body,
      };

  static ShareEnvelope fromJson(Map<String, dynamic> m) => ShareEnvelope(
        type: m['type'] ?? 'unknown',
        version: m['version'] ?? 1,
        body: (m['body'] as Map).map((k, v) => MapEntry(k.toString(), v)),
      );
}

class ProjectShareCodec {
  // Encode a single project. Optionally redact credentials.
  static String encodeProject(Project p, {bool includeCredentials = false}) {
    final proj = Map<String, dynamic>.from(p.toJson());
    if (!includeCredentials) {
      proj['username'] = null;
      proj['password'] = null;
    }
    final env = ShareEnvelope(type: 'tank_project', version: 1, body: {
      'project': proj,
    });
    final jsonStr = jsonEncode(env.toJson());
    final zipped = _gzipEncode(utf8.encode(jsonStr));
    return base64Url.encode(zipped);
  }

  static Project decodeProject(String data) {
    final zipped = base64Url.decode(data);
    final jsonStr = utf8.decode(_gzipDecode(zipped));
    final env = ShareEnvelope.fromJson(jsonDecode(jsonStr));
    if (env.type != 'tank_project') throw FormatException('Unsupported type: ${env.type}');
    final proj = Project.fromJson(env.body['project'] as Map<String, dynamic>);
    return proj;
  }

  // Encode multiple projects (group). Credentials optional.
  static String encodeProjects(List<Project> projects, {bool includeCredentials = false, String? groupName}) {
    final list = projects.map((p) {
      final m = Map<String, dynamic>.from(p.toJson());
      if (!includeCredentials) {
        m['username'] = null;
        m['password'] = null;
      }
      return m;
    }).toList();
    final env = ShareEnvelope(type: 'tank_projects', version: 1, body: {
      'projects': list,
      if (groupName != null && groupName.trim().isNotEmpty) 'groupName': groupName.trim(),
    });
    final jsonStr = jsonEncode(env.toJson());
    final zipped = _gzipEncode(utf8.encode(jsonStr));
    return base64Url.encode(zipped);
  }

  static List<Project> decodeProjects(String data) {
    final zipped = base64Url.decode(data);
    final jsonStr = utf8.decode(_gzipDecode(zipped));
    final env = ShareEnvelope.fromJson(jsonDecode(jsonStr));
    if (env.type != 'tank_projects') throw FormatException('Unsupported type: ${env.type}');
    final list = env.body['projects'] as List<dynamic>;
    final groupName = env.body['groupName'] as String?; // may be null
    final projects = list.map((e) => Project.fromJson(e as Map<String, dynamic>)).toList();
    if (groupName != null) {
      // temporarily stash desired group name in groupId field using a marker prefix to handle later
      for (final p in projects) {
        p.groupId = '__IMPORT_GROUP_NAME__:$groupName';
      }
    }
    return projects;
  }
}
