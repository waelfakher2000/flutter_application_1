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
  // Persisted custom order of projects by id (global order that groups tap into)
  List<String> _projectOrder = [];
  // Persisted custom order of groups by id
  List<String> _groupOrder = [];

  bool get isLoaded => _loaded;
  UnmodifiableListView<Project> get projects => UnmodifiableListView(_projects);
  UnmodifiableListView<ProjectGroup> get groups => UnmodifiableListView(_groups);

  Future<void> load() async {
    final prefs = await SharedPreferences.getInstance();
    final pStr = prefs.getString('projects');
    final gStr = prefs.getString('project_groups');
    final storedOrder = prefs.getStringList('project_order');
    final storedGroupOrder = prefs.getStringList('group_order');
    if (pStr != null) {
      _projects = Project.decode(pStr);
    }
    if (gStr != null) {
      _groups = ProjectGroup.decode(gStr);
    }
    // Initialize order: use stored order if present, else current list order
    _projectOrder = storedOrder ?? _projects.map((e) => e.id).toList(growable: true);
    // Ensure order contains all current ids and remove unknowns
    final existingIds = _projects.map((e) => e.id).toSet();
    _projectOrder = [
      ..._projectOrder.where(existingIds.contains),
      ..._projects.map((e) => e.id).where((id) => !_projectOrder.contains(id)),
    ];
    // Sort _projects according to order
    _projects.sort((a, b) => _projectOrder.indexOf(a.id).compareTo(_projectOrder.indexOf(b.id)));
    // Groups order
    _groupOrder = storedGroupOrder ?? _groups.map((e) => e.id).toList(growable: true);
    final existingGroupIds = _groups.map((e) => e.id).toSet();
    _groupOrder = [
      ..._groupOrder.where(existingGroupIds.contains),
      ..._groups.map((e) => e.id).where((id) => !_groupOrder.contains(id)),
    ];
    _groups.sort((a, b) => _groupOrder.indexOf(a.id).compareTo(_groupOrder.indexOf(b.id)));
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
      await prefs.setStringList('project_order', _projectOrder);
      await prefs.setStringList('group_order', _groupOrder);
    } catch (_) {}
  }

  // Project ops
  void addProject(Project p) {
    _projects.add(p);
    _projectOrder.add(p.id);
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
    _projectOrder.removeWhere((e) => e == id);
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
    _groupOrder.add(g.id);
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
    _groupOrder.removeWhere((e) => e == id);
    _scheduleSave();
    notifyListeners();
  }

  void deleteGroupAndProjects(String id) {
    _projects.removeWhere((p) => p.groupId == id);
    _groups.removeWhere((g) => g.id == id);
    _groupOrder.removeWhere((e) => e == id);
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

  // Reorder projects within a specific group (groupId may be null for ungrouped)
  void reorderWithinGroup(String? groupId, List<String> orderedIds) {
    // Build mapping for quick lookup
    // Sanity: keep only ids that actually belong to this group
    final belongs = <String>{};
    for (final id in orderedIds) {
      final p = getById(id);
      if (p != null && p.groupId == groupId) belongs.add(id);
    }
    // Merge with current order by replacing the relative order of group items in-place
    int idx = 0;
    final newOrder = <String>[];
    for (final id in _projectOrder) {
      final p = getById(id);
      final bool isInGroup = p != null && p.groupId == groupId;
      if (isInGroup) {
        // pick next from orderedIds that belongs
        while (idx < orderedIds.length && !belongs.contains(orderedIds[idx])) {
          idx++;
        }
        if (idx < orderedIds.length) {
          newOrder.add(orderedIds[idx]);
          idx++;
        } else {
          // fallback: keep original id if something went off
          newOrder.add(id);
        }
      } else {
        newOrder.add(id);
      }
    }
    _projectOrder = newOrder;
    // Now reorder _projects to match new order
    _projects.sort((a, b) => _projectOrder.indexOf(a.id).compareTo(_projectOrder.indexOf(b.id)));
    _scheduleSave();
    notifyListeners();
  }

  // Reorder groups globally according to orderedIds
  void reorderGroups(List<String> orderedIds) {
    final existing = _groups.map((e) => e.id).toSet();
    final filtered = orderedIds.where(existing.contains).toList(growable: true);
    // Append any missing groups (e.g., newly added) at the end in their current order
    for (final g in _groups) {
      if (!filtered.contains(g.id)) filtered.add(g.id);
    }
    _groupOrder = filtered;
    _groups.sort((a, b) => _groupOrder.indexOf(a.id).compareTo(_groupOrder.indexOf(b.id)));
    _scheduleSave();
    notifyListeners();
  }
}
