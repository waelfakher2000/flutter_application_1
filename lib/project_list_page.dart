import 'package:flutter/material.dart';
import 'package:flutter/services.dart';
import 'package:google_fonts/google_fonts.dart';
import 'package:shared_preferences/shared_preferences.dart';
import 'package:provider/provider.dart';
import 'project_model.dart';
import 'main.dart'; // For MainTankPage
import 'project_edit_page.dart';
import 'share_qr_page.dart';
import 'scan_qr_page.dart';
import 'project_group.dart';
import 'theme_provider.dart';
import 'types.dart';
import 'project_repository.dart';
import 'widgets/scrolling_text.dart';
import 'mqtt_service.dart';
import 'dart:math' as math;
import 'dart:async';

class ProjectListPage extends StatefulWidget {
  const ProjectListPage({super.key});

  @override
  State<ProjectListPage> createState() => _ProjectListPageState();
}

class _ProjectListPageState extends State<ProjectListPage> {
  Object? _dragHoverGroupKey; // group.id or 'ungrouped'
  final TextEditingController _searchController = TextEditingController();
  String _searchQuery = '';
  bool _didAutoRefresh = false;

  @override
  void initState() {
    super.initState();
    _applyOrAskForFullScreen();
  WidgetsBinding.instance.addPostFrameCallback((_) => _autoRefreshOnce());
  }

  double _projectCapacityLiters(Project p) {
    switch (p.tankType) {
      case TankType.verticalCylinder:
        final r = p.diameter / 2.0;
        return 1000 * (3.141592653589793 * r * r * p.height) * p.connectedTankCount;
      case TankType.horizontalCylinder:
        final r = p.diameter / 2.0;
        final full = 3.141592653589793 * r * r * p.length; // m^3
        return 1000 * full * p.connectedTankCount;
      case TankType.rectangle:
        return 1000 * (p.length * p.width * p.height) * p.connectedTankCount;
    }
  }

  Future<void> _applyOrAskForFullScreen() async {
    final prefs = await SharedPreferences.getInstance();
    if (!mounted) return;

    final bool? preferenceSet = prefs.getBool('fullscreen_preference_set');

    if (preferenceSet == true) {
      final bool isFullScreen = prefs.getBool('is_fullscreen') ?? false;
      if (isFullScreen) {
        SystemChrome.setEnabledSystemUIMode(SystemUiMode.immersiveSticky);
      } else {
        SystemChrome.setEnabledSystemUIMode(SystemUiMode.edgeToEdge);
      }
    } else {
      // It's the first time, so ask the user.
      WidgetsBinding.instance.addPostFrameCallback((_) => _showFullScreenDialog());
    }
  }

  Future<void> _showFullScreenDialog() async {
    final prefs = await SharedPreferences.getInstance();
    if (!mounted) return;

    return showDialog<void>(
      context: context,
      barrierDismissible: false, // user must choose an option
      builder: (BuildContext context) {
        return AlertDialog(
          title: const Text('Full Screen Mode'),
          content: const SingleChildScrollView(
            child: ListBody(
              children: <Widget>[
                Text('Would you like to enable full screen mode to hide the system navigation buttons?'),
              ],
            ),
          ),
          actions: <Widget>[
            TextButton(
              child: const Text('No'),
              onPressed: () async {
                SystemChrome.setEnabledSystemUIMode(SystemUiMode.edgeToEdge);
                await prefs.setBool('fullscreen_preference_set', true);
                await prefs.setBool('is_fullscreen', false);
                if (mounted) Navigator.of(context).pop();
              },
            ),
            TextButton(
              child: const Text('Yes'),
              onPressed: () async {
                SystemChrome.setEnabledSystemUIMode(SystemUiMode.immersiveSticky);
                await prefs.setBool('fullscreen_preference_set', true);
                await prefs.setBool('is_fullscreen', true);
                if (mounted) Navigator.of(context).pop();
              },
            ),
          ],
        );
      },
    );
  }

  @override
  void dispose() {
    _searchController.dispose();
    super.dispose();
  }

  // Legacy persistence removed; repository handles saving.
  Future<void> _autoRefreshOnce() async {
    if (_didAutoRefresh) return;
    final repo = context.read<ProjectRepository>();
    if (!repo.isLoaded) return; // wait for load
    _didAutoRefresh = true;
    await _refreshLiveVolumes();
  }

  Future<void> _refreshLiveVolumes() async {
    final repo = context.read<ProjectRepository>();
    // Ensure we have the latest persisted snapshot first
    await repo.reload();
    final projects = repo.projects.toList();
    // For each project, open a short-lived MQTT subscription to grab one (retained) message.
    // If the broker/topic doesn't retain or publish quickly, we timeout.
    Future<void> fetch(Project p) async {
      final completer = Completer<void>();
      Timer? timer;
      late MqttService svc;
      void finish() {
        if (!completer.isCompleted) completer.complete();
      }
      double _totalVolumeM3(Project pr) {
        switch (pr.tankType) {
          case TankType.verticalCylinder:
            final r = pr.diameter / 2.0; return math.pi * r * r * pr.height * pr.connectedTankCount;
          case TankType.horizontalCylinder:
            final r = pr.diameter / 2.0; return math.pi * r * r * pr.length * pr.connectedTankCount;
          case TankType.rectangle:
            return pr.length * pr.width * pr.height * pr.connectedTankCount;
        }
      }
      double _horizontalSegmentArea(double r, double h) {
        // h: filled height (0..2r)
        if (h <= 0) return 0; if (h >= 2*r) return math.pi * r * r;
        final part1 = r*r*math.acos((r - h)/r);
        final part2 = (r - h)*math.sqrt(2*r*h - h*h);
        return part1 - part2;
      }
      double _liquidVolumeM3(Project pr, double level) {
        switch (pr.tankType) {
          case TankType.verticalCylinder:
            final r = pr.diameter / 2.0; return math.pi * r * r * level * pr.connectedTankCount;
          case TankType.horizontalCylinder:
            final r = pr.diameter / 2.0; final area = _horizontalSegmentArea(r, level.clamp(0, 2*r)); return area * pr.length * pr.connectedTankCount;
          case TankType.rectangle:
            return pr.length * pr.width * level * pr.connectedTankCount;
        }
      }
      svc = MqttService(
        p.broker,
        p.port,
        p.topic,
        publishTopic: null,
        lastWillTopic: p.lastWillTopic,
        payloadIsJson: p.payloadIsJson,
        jsonFieldIndex: p.jsonFieldIndex,
        jsonKeyName: p.jsonKeyName,
        displayTimeFromJson: p.displayTimeFromJson,
        jsonTimeFieldIndex: p.jsonTimeFieldIndex,
        jsonTimeKeyName: p.jsonTimeKeyName,
        username: p.username,
        password: p.password,
        onMessage: (raw) {
          final corrected = raw * p.multiplier + p.offset;
          double level;
          if (p.sensorType == SensorType.submersible) {
            level = corrected;
          } else {
            level = p.height - corrected; // ultrasonic distance → level
          }
            // Clamp level for safety
          if (p.tankType == TankType.horizontalCylinder) {
            // vertical dimension is diameter
            level = level.clamp(0.0, p.diameter);
          } else {
            level = level.clamp(0.0, p.height);
          }
          final totalM3 = _totalVolumeM3(p);
          final liquidM3 = _liquidVolumeM3(p, level);
          repo.updateVolume(p.id, liquidM3 * 1000, totalM3 * 1000, DateTime.now());
          try { svc.disconnect(); } catch (_) {}
          timer?.cancel();
          finish();
        },
        onStatus: (_) {},
        onPresence: (_) {},
        onTimestamp: (_) {},
      );
      try {
        svc.connect();
      } catch (_) {
        finish();
      }
      timer = Timer(const Duration(seconds: 3), () { try { svc.disconnect(); } catch (_) {} finish(); });
      await completer.future;
    }
    // Limit concurrency to avoid too many simultaneous connections
    const int maxConcurrent = 3;
    int index = 0;
    while (index < projects.length) {
      final batch = <Future>[];
      for (int i = 0; i < maxConcurrent && index < projects.length; i++, index++) {
        batch.add(fetch(projects[index]));
      }
      await Future.wait(batch);
      if (!mounted) break;
    }
  }

  Future<void> _scanImport() async {
    final result = await Navigator.of(context).push(
      MaterialPageRoute(builder: (context) => const ScanQrPage()),
    );
    if (result is Project) {
      await _handleImport(result);
    } else if (result is List<Project>) {
      // Detect group name marker
      final repo = context.read<ProjectRepository>();
      String? markerGroupName;
      for (final p in result) {
        if (p.groupId != null && p.groupId!.startsWith('__IMPORT_GROUP_NAME__:')) {
          markerGroupName = p.groupId!.split(':').skip(1).join(':');
          p.groupId = null; // clear for now
        }
      }
      String? targetGroupId;
      if (markerGroupName != null && markerGroupName.trim().isNotEmpty) {
        // Try find existing group with same name
        final existing = repo.groups.firstWhere(
          (g) => g.name.toLowerCase() == markerGroupName!.toLowerCase(),
          orElse: () => ProjectGroup(name: markerGroupName!),
        );
        if (existing.id == '') {
          // unreachable: ProjectGroup generates id automatically; but keep logic simple
        }
        if (!repo.groups.contains(existing)) {
          repo.addGroup(existing);
        }
        targetGroupId = existing.id;
      }
      for (final p in result) {
        await _handleImport(p);
        if (targetGroupId != null) {
          repo.setProjectGroup(p.id, targetGroupId);
        }
      }
      if (mounted) {
        ScaffoldMessenger.of(context).showSnackBar(SnackBar(content: Text('Imported ${result.length} projects${markerGroupName != null ? ' into group "$markerGroupName"' : ''}')));
      }
    }
  }

  Future<void> _handleImport(Project imported) async {
    final repo = context.read<ProjectRepository>();
    imported.groupId = null; // do not auto-map group IDs from external source
    final existingIndex = repo.projects.indexWhere((p) => p.name == imported.name);
    if (existingIndex >= 0) {
      final action = await showDialog<String>(
        context: context,
        builder: (context) => AlertDialog(
          title: const Text('Project Exists'),
          content: Text('A project named "${imported.name}" already exists. What would you like to do?'),
          actions: [
            TextButton(onPressed: () => Navigator.of(context).pop('cancel'), child: const Text('Cancel')),
            TextButton(onPressed: () => Navigator.of(context).pop('keepBoth'), child: const Text('Keep Both')),
            FilledButton(onPressed: () => Navigator.of(context).pop('replace'), child: const Text('Replace')),
          ],
        ),
      );
      if (!mounted || action == null || action == 'cancel') return;
      if (action == 'replace') {
        repo.updateProject(imported.copyWith(id: repo.projects[existingIndex].id));
      } else {
        final unique = _uniqueName(imported.name, repo.projects);
        repo.addProject(imported.copyWith(name: unique));
      }
    } else {
      repo.addProject(imported);
    }
  }

  String _uniqueName(String base, List<Project> current) {
    var name = base;
    var i = 1;
    while (current.any((p) => p.name == name)) {
      i++;
      name = '$base ($i)';
    }
    return name;
  }

  Future<void> _copyProject(int index) async {
    final repo = context.read<ProjectRepository>();
    final original = repo.projects[index];
    final defaultName = _uniqueName('${original.name} (copy)', repo.projects);
    final controller = TextEditingController(text: defaultName);

    final newName = await showDialog<String>(
      context: context,
      builder: (context) => AlertDialog(
        title: const Text('Copy Project'),
        content: TextField(
          controller: controller,
          autofocus: true,
          decoration: const InputDecoration(
            labelText: 'New name',
          ),
        ),
        actions: [
          TextButton(
            onPressed: () => Navigator.of(context).pop(),
            child: const Text('Cancel'),
          ),
          FilledButton(
            onPressed: () => Navigator.of(context).pop(controller.text.trim()),
            child: const Text('Create'),
          ),
        ],
      ),
    );

    if (newName == null || newName.isEmpty) return;

    // Duplicate by JSON round-trip, clearing id so constructor generates a new one
    final json = original.toJson()
      ..['id'] = null
      ..['name'] = _uniqueName(newName, repo.projects);
    final cloned = Project.fromJson(json);
    repo.addProject(cloned);
  }

  void _addProject() async {
    final repo = context.read<ProjectRepository>();
    final newProject = await Navigator.of(context).push<Project>(
      MaterialPageRoute(builder: (context) => const ProjectEditPage()),
    );
    if (newProject != null) {
      repo.addProject(newProject);
    }
  }

  Future<void> _addGroup() async {
    final controller = TextEditingController();
    final name = await showDialog<String>(
      context: context,
      builder: (context) => AlertDialog(
        title: const Text('Create Group'),
        content: TextField(
          controller: controller,
          autofocus: true,
          decoration: const InputDecoration(labelText: 'Group name'),
        ),
        actions: [
          TextButton(onPressed: () => Navigator.pop(context), child: const Text('Cancel')),
          FilledButton(onPressed: () => Navigator.pop(context, controller.text.trim()), child: const Text('Create')),
        ],
      ),
    );
    if (name == null || name.isEmpty) return;
  context.read<ProjectRepository>().addGroup(ProjectGroup(name: name));
  }

  Future<void> _renameGroup(ProjectGroup group) async {
    final controller = TextEditingController(text: group.name);
    final name = await showDialog<String>(
      context: context,
      builder: (context) => AlertDialog(
        title: const Text('Rename Group'),
        content: TextField(
          controller: controller,
          autofocus: true,
          decoration: const InputDecoration(labelText: 'Group name'),
        ),
        actions: [
          TextButton(onPressed: () => Navigator.pop(context), child: const Text('Cancel')),
          FilledButton(onPressed: () => Navigator.pop(context, controller.text.trim()), child: const Text('Save')),
        ],
      ),
    );
    if (name == null || name.isEmpty) return;
  context.read<ProjectRepository>().renameGroup(group.id, name);
  }

  Future<void> _deleteGroup(ProjectGroup group) async {
    final repo = context.read<ProjectRepository>();
    final projectCount = repo.projects.where((p) => p.groupId == group.id).length;
    if (projectCount == 0) {
      final ok = await showDialog<bool>(
        context: context,
        builder: (_) => AlertDialog(
          title: const Text('Delete Group'),
          content: const Text('This group is empty. Delete it?'),
          actions: [
            TextButton(onPressed: () => Navigator.pop(context, false), child: const Text('Cancel')),
            FilledButton(onPressed: () => Navigator.pop(context, true), child: const Text('Delete')),
          ],
        ),
      );
      if (ok == true) repo.deleteGroup(group.id);
      return;
    }

    final choice = await showDialog<String>(
      context: context,
      builder: (_) => AlertDialog(
        title: const Text('Delete Group'),
        content: Text('Group "${group.name}" contains $projectCount project${projectCount == 1 ? '' : 's'}. What would you like to do?'),
        actions: [
          TextButton(onPressed: () => Navigator.pop(context, 'cancel'), child: const Text('Cancel')),
          TextButton(onPressed: () => Navigator.pop(context, 'keep'), child: const Text('Ungroup Projects')),
          FilledButton(onPressed: () => Navigator.pop(context, 'delete'), child: const Text('Delete All')),
        ],
      ),
    );
    if (choice == 'keep') {
      repo.deleteGroup(group.id); // existing behavior ungrouping
    } else if (choice == 'delete') {
      repo.deleteGroupAndProjects(group.id);
    }
  }

  // Drag & drop handles moving projects between groups; no separate picker needed.

  void _editProject(int index) async {
    final repo = context.read<ProjectRepository>();
    final updatedProject = await Navigator.of(context).push<Project>(
      MaterialPageRoute(builder: (context) => ProjectEditPage(project: repo.projects[index])),
    );
    if (updatedProject != null) repo.updateProject(updatedProject);
  }

  void _deleteProject(int index) {
    final repo = context.read<ProjectRepository>();
    showDialog(
      context: context,
      builder: (context) => AlertDialog(
        title: const Text('Delete Project'),
        content: const Text('Are you sure you want to delete this project?'),
        actions: [
          TextButton(
            onPressed: () => Navigator.of(context).pop(),
            child: const Text('Cancel'),
          ),
          TextButton(
            onPressed: () async {
              repo.deleteProject(repo.projects[index].id);
              Navigator.of(context).pop();
            },
            child: const Text('Delete'),
          ),
        ],
      ),
    );
  }

  @override
  Widget build(BuildContext context) {
    return Scaffold(
      appBar: AppBar(
        backgroundColor: Theme.of(context).colorScheme.primary,
        foregroundColor: Theme.of(context).colorScheme.onPrimary,
        title: Text(
          'Projects',
          style: GoogleFonts.poppins(
            fontWeight: FontWeight.w700,
            letterSpacing: 0.5,
          ),
        ),
        actions: [
          IconButton(
            tooltip: 'Import from QR',
            icon: const Icon(Icons.qr_code_scanner),
            onPressed: _scanImport,
          ),
          // Theme toggle is placed on the first page (Projects list) as the rightmost icon
          Consumer<ThemeProvider>(
            builder: (context, themeProvider, _) => IconButton(
              tooltip: 'Toggle Theme',
              icon: Icon(themeProvider.themeMode == ThemeMode.dark ? Icons.dark_mode : Icons.light_mode),
              onPressed: () {
                themeProvider.toggleTheme(themeProvider.themeMode == ThemeMode.light);
              },
            ),
          ),
        ],
      ),
      body: _buildGroupedBody(),
      floatingActionButton: FloatingActionButton(
        onPressed: _addProject,
        tooltip: 'Add Project',
        child: const Icon(Icons.add),
      ),
    );
  }

  Widget _buildGroupedBody() {
    final repo = context.watch<ProjectRepository>();
    if (!repo.isLoaded) {
      return const Center(child: CircularProgressIndicator());
    }
    final allProjects = repo.projects;
    final groups = repo.groups;
    final String q = _searchQuery.trim().toLowerCase();
    final List<Project> filtered = q.isEmpty
        ? allProjects
        : allProjects.where((p) => p.name.toLowerCase().contains(q) || p.broker.toLowerCase().contains(q)).toList();

    if (allProjects.isEmpty) {
      return Center(
        child: Padding(
          padding: const EdgeInsets.symmetric(horizontal: 24),
          child: Column(
            mainAxisSize: MainAxisSize.min,
            children: [
              Icon(
                Icons.folder_open,
                size: 72,
                color: Theme.of(context).colorScheme.onSurfaceVariant,
              ),
              const SizedBox(height: 16),
              Text(
                'No projects yet',
                style: Theme.of(context).textTheme.headlineSmall?.copyWith(fontWeight: FontWeight.w700),
              ),
              const SizedBox(height: 8),
              Text(
                'Add one to get started.',
                textAlign: TextAlign.center,
                style: Theme.of(context).textTheme.bodyMedium?.copyWith(
                      color: Theme.of(context).colorScheme.onSurfaceVariant,
                    ),
              ),
              const SizedBox(height: 16),
              FilledButton.icon(
                onPressed: _addProject,
                icon: const Icon(Icons.add),
                label: const Text('Add Project'),
              ),
            ],
          ),
        ),
      );
    }
    if (filtered.isEmpty) {
      return Column(
        children: [
          _searchBar(),
          const Expanded(
            child: Center(child: Text('No matching projects')),
          ),
        ],
      );
    }

    // Build grouped map: groupId -> List<Project>
  final Map<String?, List<Project>> grouped = {};
  final existingGroupIds = groups.map((g) => g.id).toSet();
    for (final p in filtered) {
      final gid = (p.groupId != null && existingGroupIds.contains(p.groupId)) ? p.groupId : null;
      grouped.putIfAbsent(gid, () => []).add(p);
    }

    // Order: groups, then ungrouped at the end
    final List<Widget> sections = [];

  for (final g in groups) {
      final items = grouped[g.id] ?? [];
      sections.add(_groupSection(title: g.name, group: g, projects: items));
    }

    final ungrouped = grouped[null] ?? [];
  if (ungrouped.isNotEmpty || groups.isEmpty) {
      sections.add(_groupSection(title: 'Ungrouped', group: null, projects: ungrouped));
    }

    return RefreshIndicator(
  onRefresh: _refreshLiveVolumes,
      child: ListView(
        physics: const AlwaysScrollableScrollPhysics(),
        children: [
          _searchBar(),
          Padding(
            padding: const EdgeInsets.fromLTRB(16, 8, 16, 4),
            child: Row(
              children: [
                const Text('Groups', style: TextStyle(fontWeight: FontWeight.bold)),
                const SizedBox(width: 8),
                OutlinedButton.icon(
                  onPressed: _addGroup,
                  icon: const Icon(Icons.add),
                  label: const Text('Add Group'),
                ),
              ],
            ),
          ),
          ...sections,
          const SizedBox(height: 24),
        ],
      ),
    );
  }

  Widget _searchBar() {
    return Padding(
      padding: const EdgeInsets.fromLTRB(16, 12, 16, 4),
      child: TextField(
        controller: _searchController,
        onChanged: (v) => setState(() => _searchQuery = v),
        decoration: InputDecoration(
          hintText: 'Search projects by name or broker',
          prefixIcon: const Icon(Icons.search),
          suffixIcon: _searchQuery.isEmpty
              ? null
              : IconButton(
                  tooltip: 'Clear',
                  icon: const Icon(Icons.clear),
                  onPressed: () {
                    _searchController.clear();
                    setState(() => _searchQuery = '');
                  },
                ),
          border: OutlineInputBorder(borderRadius: BorderRadius.circular(12)),
          isDense: true,
        ),
      ),
    );
  }

  Widget _groupSection({required String title, ProjectGroup? group, required List<Project> projects}) {
    final key = group?.id ?? 'ungrouped';
    final hovered = _dragHoverGroupKey == key;
    // Aggregation (compute capacity from dimensions each time to ensure visibility even before readings arrive)
    double totalCapacity = 0; // liters
    double totalLiquid = 0;   // liters (only if cached)
    for (final p in projects) {
      final capacity = _projectCapacityLiters(p);
      totalCapacity += capacity;
      if (p.lastLiquidLiters != null) {
        totalLiquid += p.lastLiquidLiters!;
      }
    }
    // If we have no liquid readings yet, keep totalLiquid as 0 (percent 0)
    final pct = totalCapacity > 0 ? (totalLiquid / totalCapacity * 100).clamp(0, 100) : null;
    return Card(
      margin: const EdgeInsets.symmetric(horizontal: 12, vertical: 6),
      child: DragTarget<Project>(
        onWillAcceptWithDetails: (_) {
          setState(() => _dragHoverGroupKey = key);
          return true;
        },
        onLeave: (_) {
          if (_dragHoverGroupKey == key) setState(() => _dragHoverGroupKey = null);
        },
        onAcceptWithDetails: (details) async {
          final project = details.data;
          context.read<ProjectRepository>().setProjectGroup(project.id, group?.id);
          setState(() => _dragHoverGroupKey = null);
        },
        builder: (context, candidate, rejected) {
          return Container(
            decoration: BoxDecoration(
              color: hovered ? Theme.of(context).colorScheme.primaryContainer.withValues(alpha: 0.15) : null,
              border: Border.all(color: hovered ? Theme.of(context).colorScheme.primary : Colors.transparent, width: 2),
              borderRadius: const BorderRadius.all(Radius.circular(12)),
            ),
            child: ExpansionTile(
              leading: Icon(group == null ? Icons.inbox_outlined : Icons.folder),
              title: ScrollingText(
                text: title,
                style: const TextStyle(fontWeight: FontWeight.bold, fontStyle: FontStyle.italic),
                pixelsPerSecond: 50,
                gap: 40,
              ),
              subtitle: Text(
                '${projects.length} project${projects.length == 1 ? '' : 's'}',
                style: Theme.of(context).textTheme.labelMedium,
              ),
              initiallyExpanded: true,
              trailing: group == null
                  ? null
                  : SizedBox(
                      width: 205,
                      child: Column(
                        mainAxisSize: MainAxisSize.min,
                        crossAxisAlignment: CrossAxisAlignment.end,
                        children: [
                          if (totalCapacity > 0)
                            Row(
                              mainAxisSize: MainAxisSize.min,
                              mainAxisAlignment: MainAxisAlignment.end,
                              children: [
                                Flexible(
                                  child: Text(
                                    '${totalLiquid.toStringAsFixed(1)}/${totalCapacity.toStringAsFixed(1)}L',
                                    style: Theme.of(context).textTheme.labelSmall?.copyWith(height: 0.9),
                                    overflow: TextOverflow.ellipsis,
                                  ),
                                ),
                                if (pct != null)
                                  Container(
                                    margin: const EdgeInsets.only(left: 4),
                                    padding: const EdgeInsets.symmetric(horizontal: 5, vertical: 1),
                                    decoration: BoxDecoration(
                                      color: Theme.of(context).colorScheme.primaryContainer,
                                      borderRadius: BorderRadius.circular(12),
                                    ),
                                    child: Text(
                                      '${pct.toStringAsFixed(0)}%',
                                      style: Theme.of(context).textTheme.labelSmall?.copyWith(fontWeight: FontWeight.w600, height: 0.9),
                                    ),
                                  ),
                              ],
                            ),
                          const SizedBox(height: 1),
                          Row(
                            mainAxisSize: MainAxisSize.min,
                            children: [
                              IconButton(
                                visualDensity: VisualDensity.compact,
                                padding: const EdgeInsets.all(1),
                                constraints: const BoxConstraints.tightFor(width: 32, height: 32),
                                icon: const Icon(Icons.qr_code_2),
                                tooltip: 'Share group projects',
                                onPressed: projects.isEmpty
                                    ? null
                                    : () {
                                        Navigator.of(context).push(
                                          MaterialPageRoute(
                                            builder: (_) => ShareQrPage(projects: projects, groupName: group.name),
                                          ),
                                        );
                                      },
                              ),
                              IconButton(
                                visualDensity: VisualDensity.compact,
                                padding: const EdgeInsets.all(1),
                                constraints: const BoxConstraints.tightFor(width: 32, height: 32),
                                icon: const Icon(Icons.edit, size: 18),
                                tooltip: 'Rename group',
                                onPressed: () => _renameGroup(group),
                              ),
                              IconButton(
                                visualDensity: VisualDensity.compact,
                                padding: const EdgeInsets.all(1),
                                constraints: const BoxConstraints.tightFor(width: 32, height: 32),
                                icon: const Icon(Icons.delete, size: 18),
                                tooltip: 'Delete group',
                                onPressed: () => _deleteGroup(group),
                              ),
                            ],
                          ),
                        ],
                      ),
                    ),
              children: projects.isEmpty
                  ? const [ListTile(title: Text('No projects'))]
                  : projects.map((project) => _projectTile(project)).toList(),
            ),
          );
        },
      ),
    );
  }

  Widget _projectTile(Project project) {
    final repo = context.read<ProjectRepository>();
    final index = repo.projects.indexWhere((p) => p.id == project.id);
    final tile = ListTile(
      title: Text(project.name),
      subtitle: Text(project.broker),
      onTap: () {
        Navigator.of(context).push(
          MaterialPageRoute(
            builder: (context) => MainTankPage(
              broker: project.broker,
              port: project.port,
              topic: project.topic,
              sensorType: project.sensorType,
              tankType: project.tankType,
              height: project.height,
              diameter: project.diameter,
              length: project.length,
              width: project.width,
              username: project.username,
              password: project.password,
              minThreshold: project.minThreshold,
              maxThreshold: project.maxThreshold,
              projectName: project.name,
              projectId: project.id,
              multiplier: project.multiplier,
              offset: project.offset,
              connectedTankCount: project.connectedTankCount,
              useControlButton: project.useControlButton,
              controlTopic: project.controlTopic,
              controlMode: project.controlMode,
              onValue: project.onValue,
              offValue: project.offValue,
              autoControl: project.autoControl,
              controlRetained: project.controlRetained,
              controlQos: project.controlQos,
              lastWillTopic: project.lastWillTopic,
              // New payload parsing options
              payloadIsJson: project.payloadIsJson,
              jsonFieldIndex: project.jsonFieldIndex,
              jsonKeyName: project.jsonKeyName,
              displayTimeFromJson: project.displayTimeFromJson,
              jsonTimeFieldIndex: project.jsonTimeFieldIndex,
              jsonTimeKeyName: project.jsonTimeKeyName,
            ),
          ),
        );
      },
      trailing: Row(
        mainAxisSize: MainAxisSize.min,
        children: [
          IconButton(icon: const Icon(Icons.copy), tooltip: 'Copy project', onPressed: () => _copyProject(index)),
          IconButton(
            icon: const Icon(Icons.qr_code),
            tooltip: 'Share via QR',
            onPressed: () {
              Navigator.of(context).push(
                MaterialPageRoute(builder: (_) => ShareQrPage(project: project)),
              );
            },
          ),
          IconButton(icon: const Icon(Icons.edit), onPressed: () => _editProject(index)),
          IconButton(icon: const Icon(Icons.delete), onPressed: () => _deleteProject(index)),
        ],
      ),
    );

    return LongPressDraggable<Project>(
      data: project,
      feedback: Material(
        color: Colors.transparent,
        child: ConstrainedBox(
          constraints: BoxConstraints(maxWidth: MediaQuery.of(context).size.width - 48),
          child: Card(
            elevation: 6,
            child: ListTile(
              title: Text(project.name),
              subtitle: Text(project.broker),
            ),
          ),
        ),
      ),
      childWhenDragging: Opacity(opacity: 0.5, child: tile),
      child: tile,
    );
  }
}
