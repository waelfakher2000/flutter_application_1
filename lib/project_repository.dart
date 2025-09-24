import 'dart:async';
import 'dart:collection';
import 'package:flutter/foundation.dart';
import 'package:shared_preferences/shared_preferences.dart';
import 'project_model.dart';
import 'project_group.dart';
import 'backend_client.dart' as backend;

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
    // Best-effort initial sync of all projects to backend (fire-and-forget)
    // This ensures the bridge sees existing projects after reinstall.
    unawaited(backend.upsertProjectsToBackend(_projects));
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
      if (kDebugMode) {
        // Simple verification read-back (not parsing fully to avoid perf hit on large sets repeatedly)
        final len = (_projects.length);
        debugPrint('[Repo] Saved projects=$len groups=${_groups.length}');
      }
    } catch (_) {}
  }

  // Debug helper: force a read-back validation and log counts & first project snapshot.
  Future<void> debugValidatePersistence() async {
    try {
      final prefs = await SharedPreferences.getInstance();
      final pStr = prefs.getString('projects');
      if (pStr == null) {
        debugPrint('[Repo][Validate] No projects key found');
        return;
      }
      final decoded = Project.decode(pStr);
      debugPrint('[Repo][Validate] decoded count=${decoded.length}');
      if (decoded.isNotEmpty) {
        final first = decoded.first;
        debugPrint('[Repo][Validate] first.id=${first.id} name=${first.name} height=${first.height} customFormula=${first.customFormula != null}');
      }
    } catch (e) {
      debugPrint('[Repo][Validate] error: $e');
    }
  }

  // Project ops
  void addProject(Project p) {
    _projects.add(p);
    _projectOrder.add(p.id);
    // Structural change -> save immediately
    unawaited(_saveNow());
    notifyListeners();
    // Immediate sync attempt (will silently skip if auth not ready)
    unawaited(backend.upsertProjectToBackend(p));
    unawaited(backend.requestBridgeReload());
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
      // Persist immediately for definitional changes
      unawaited(_saveNow());
      notifyListeners();
      // Immediate sync (guarded inside backend helper if auth missing)
      unawaited(backend.upsertProjectToBackend(_projects[i]));
      unawaited(backend.requestBridgeReload());
    }
  }

  void deleteProject(String id) {
    _projects.removeWhere((e) => e.id == id);
    _projectOrder.removeWhere((e) => e == id);
    unawaited(_saveNow());
    notifyListeners();
    // Inform backend & bridge (delete is skipped if auth not present)
    unawaited(backend.deleteProjectFromBackend(id));
    unawaited(backend.requestBridgeReload());
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
    unawaited(_saveNow());
    notifyListeners();
  }

  void renameGroup(String id, String newName) {
    try {
      final g = _groups.firstWhere((e) => e.id == id);
      g.name = newName;
      _scheduleSave(); // still debounced; renames less critical
      notifyListeners();
    } catch (_) {}
  }

  void deleteGroup(String id) {
    _projects = _projects.map((p) => p.groupId == id ? p.copyWith(groupId: null) : p).toList();
    _groups.removeWhere((g) => g.id == id);
    _groupOrder.removeWhere((e) => e == id);
    unawaited(_saveNow());
    notifyListeners();
  }

  void deleteGroupAndProjects(String id) {
    _projects.removeWhere((p) => p.groupId == id);
    _groups.removeWhere((g) => g.id == id);
    _groupOrder.removeWhere((e) => e == id);
    unawaited(_saveNow());
    notifyListeners();
  }

  void setProjectGroup(String projectId, String? groupId) {
    final i = _projects.indexWhere((e) => e.id == projectId);
    if (i < 0) return;
    _projects[i] = _projects[i].copyWith(groupId: groupId);
    _scheduleSave(); // group assignment can stay debounced
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
    unawaited(_saveNow());
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
    unawaited(_saveNow());
    notifyListeners();
  }

  // --- Synchronization ---
  // Strategy:
  // 1. Fetch remote projects.
  // 2. For each local project not on server -> push up (so offline creations survive).
  // 3. For each remote project:
  //    - if exists locally -> update local fields (excluding transient caches) keeping local createdAt if remote missing
  //    - if absent locally -> add it (append to end of order)
  // 4. Optionally: remove local projects that are no longer on server (we'll keep them for now to avoid accidental loss).
  Future<void> syncFromBackend() async {
    if (!_loaded) return; // wait until local loaded
    final remote = await backend.fetchProjects();
    if (remote.isEmpty) {
      // Still push locals so server catches up (fresh account case)
      unawaited(backend.upsertProjectsToBackend(_projects));
      return;
    }
    final remoteIds = remote.map((e) => e['id']?.toString()).whereType<String>().toSet();
    // Push locals missing remotely
    for (final p in _projects) {
      if (!remoteIds.contains(p.id)) {
        unawaited(backend.upsertProjectToBackend(p));
      }
    }
    // Incorporate remote
    bool changed = false;
    for (final r in remote) {
      final rid = r['id']?.toString();
      if (rid == null) continue;
      final existingIndex = _projects.indexWhere((p) => p.id == rid);
      if (existingIndex >= 0) {
        final prev = _projects[existingIndex];
        // Build updated project using Project.fromJson with fallback to existing transient cache fields
        try {
          final mergedJson = {
            ...prev.toJson(), // start with local
            ...r, // remote overrides definitional fields
            'lastLiquidLiters': prev.lastLiquidLiters,
            'lastTotalLiters': prev.lastTotalLiters,
            'lastUpdated': prev.lastUpdated?.toIso8601String(),
          };
          final updated = Project.fromJson(mergedJson);
          _projects[existingIndex] = updated;
          changed = true;
        } catch (_) {}
      } else {
        // New project from server
        try {
          final pj = Project.fromJson(r);
          _projects.add(pj);
          if (!_projectOrder.contains(pj.id)) _projectOrder.add(pj.id);
          changed = true;
        } catch (_) {}
      }
    }
    if (changed) {
      // Re-apply ordering constraints
      _projects.sort((a, b) => _projectOrder.indexOf(a.id).compareTo(_projectOrder.indexOf(b.id)));
      _scheduleSave();
      notifyListeners();
    }
  }
}
