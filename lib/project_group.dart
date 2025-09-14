import 'dart:convert';
import 'package:uuid/uuid.dart';

class ProjectGroup {
  final String id;
  String name;
  DateTime createdAt;

  ProjectGroup({String? id, required this.name, DateTime? createdAt})
      : id = id ?? const Uuid().v4(),
        createdAt = createdAt ?? DateTime.now();

  Map<String, dynamic> toJson() => {
        'id': id,
        'name': name,
    'createdAt': createdAt.toIso8601String(),
      };

  factory ProjectGroup.fromJson(Map<String, dynamic> json) => ProjectGroup(
    id: json['id'] as String?,
    name: (json['name'] ?? '') as String,
    createdAt: json['createdAt'] != null
      ? DateTime.tryParse(json['createdAt']) ?? DateTime.now()
      : DateTime.now(),
    );

  static String encode(List<ProjectGroup> groups) => json.encode(groups.map((g) => g.toJson()).toList());
  static List<ProjectGroup> decode(String s) =>
      (json.decode(s) as List).map((e) => ProjectGroup.fromJson(e as Map<String, dynamic>)).toList();
}
