import 'dart:convert';
import 'package:uuid/uuid.dart';

class ProjectGroup {
  final String id;
  String name;

  ProjectGroup({String? id, required this.name}) : id = id ?? const Uuid().v4();

  Map<String, dynamic> toJson() => {
        'id': id,
        'name': name,
      };

  factory ProjectGroup.fromJson(Map<String, dynamic> json) =>
      ProjectGroup(id: json['id'] as String?, name: (json['name'] ?? '') as String);

  static String encode(List<ProjectGroup> groups) => json.encode(groups.map((g) => g.toJson()).toList());
  static List<ProjectGroup> decode(String s) =>
      (json.decode(s) as List).map((e) => ProjectGroup.fromJson(e as Map<String, dynamic>)).toList();
}
