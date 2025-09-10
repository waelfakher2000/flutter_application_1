import 'dart:async';
import 'dart:collection';
import 'package:flutter/foundation.dart';
import 'package:shared_preferences/shared_preferences.dart';
import 'project_model.dart';
import 'project_group.dart';

class ProjectRepository extends ChangeNotifier {
  List<Project> _projects = [];
  List<ProjectGroup> _groups = [];
  bool _loaded = false;
  Timer? _debounce;

  bool get isLoaded => _loaded;
  UnmodifiableListView<Project> get projects => UnmodifiableListView(_projects);
  UnmodifiableListView<ProjectGroup> get groups => UnmodifiableListView(_groups);

  Future<void> load() async {
    final prefs = await SharedPreferences.getInstance();
    final pStr = prefs.getString('projects');
    final gStr = prefs.getString('project_groups');
    if (pStr != null) {
      _projects = Project.decode(pStr);
    }
    if (gStr != null) {
      _groups = ProjectGroup.decode(gStr);
    }
    _loaded = true;
    notifyListeners();
  }

  // Reload from persistence (used by pull-to-refresh)
  Future<void> reload() async {
    final prefs = await SharedPreferences.getInstance();
    final pStr = prefs.getString('projects');
    final gStr = prefs.getString('project_groups');
    if (pStr != null) {
      _projects = Project.decode(pStr);
    }
    if (gStr != null) {
      _groups = ProjectGroup.decode(gStr);
    }
    notifyListeners();
  }

  void _scheduleSave() {
    _debounce?.cancel();
    _debounce = Timer(const Duration(milliseconds: 600), _saveNow);
  }

  Future<void> _saveNow() async {
    try {
      final prefs = await SharedPreferences.getInstance();
      await prefs.setString('projects', Project.encode(_projects));
      await prefs.setString('project_groups', ProjectGroup.encode(_groups));
    } catch (_) {}
  }

  // Project ops
  void addProject(Project p) {
    _projects.add(p);
    _scheduleSave();
    notifyListeners();
  }

  void updateProject(Project updated) {
    final i = _projects.indexWhere((e) => e.id == updated.id);
    if (i >= 0) {
      // preserve cached volume fields if caller didn't modify
      final prev = _projects[i];
      _projects[i] = updated.copyWith(
        lastLiquidLiters: updated.lastLiquidLiters ?? prev.lastLiquidLiters,
        lastTotalLiters: updated.lastTotalLiters ?? prev.lastTotalLiters,
        lastUpdated: updated.lastUpdated ?? prev.lastUpdated,
      );
      _scheduleSave();
      notifyListeners();
    }
  }

  void deleteProject(String id) {
    _projects.removeWhere((e) => e.id == id);
    _scheduleSave();
    notifyListeners();
  }

  Project? getById(String id) {
    try {
      return _projects.firstWhere((e) => e.id == id);
    } catch (_) {
      return null;
    }
  }

  void updateVolume(String id, double liquidL, double totalL, DateTime ts) {
    final i = _projects.indexWhere((e) => e.id == id);
    if (i < 0) return;
    final p = _projects[i];
    _projects[i] = p.copyWith(
      lastLiquidLiters: liquidL,
      lastTotalLiters: totalL,
      lastUpdated: ts,
    );
    // no immediate notify spam if lots of updates? We'll still notify to reflect live data.
    notifyListeners();
    _scheduleSave();
  }

  // Groups
  void addGroup(ProjectGroup g) {
    _groups.add(g);
    _scheduleSave();
    notifyListeners();
  }

  void renameGroup(String id, String newName) {
    try {
      final g = _groups.firstWhere((e) => e.id == id);
      g.name = newName;
      _scheduleSave();
      notifyListeners();
    } catch (_) {}
  }

  void deleteGroup(String id) {
    _projects = _projects.map((p) => p.groupId == id ? p.copyWith(groupId: null) : p).toList();
    _groups.removeWhere((g) => g.id == id);
    _scheduleSave();
    notifyListeners();
  }

  void setProjectGroup(String projectId, String? groupId) {
    final i = _projects.indexWhere((e) => e.id == projectId);
    if (i < 0) return;
    _projects[i] = _projects[i].copyWith(groupId: groupId);
    _scheduleSave();
    notifyListeners();
  }
}
