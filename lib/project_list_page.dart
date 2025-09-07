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

class ProjectListPage extends StatefulWidget {
  const ProjectListPage({super.key});

  @override
  State<ProjectListPage> createState() => _ProjectListPageState();
}

class _ProjectListPageState extends State<ProjectListPage> {
  List<Project> _projects = [];
  List<ProjectGroup> _groups = [];
  Object? _dragHoverGroupKey; // group.id or 'ungrouped'
  final TextEditingController _searchController = TextEditingController();
  String _searchQuery = '';

  @override
  void initState() {
    super.initState();
    _loadProjects();
    _applyOrAskForFullScreen();
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

  Future<void> _loadProjects() async {
    final prefs = await SharedPreferences.getInstance();
    final String? projectsString = prefs.getString('projects');
    if (projectsString != null) {
      setState(() {
        _projects = Project.decode(projectsString);
      });
    }
    final groupsString = prefs.getString('project_groups');
    if (groupsString != null) {
      setState(() {
        _groups = ProjectGroup.decode(groupsString);
      });
    }
  }

  Future<void> _saveProjects() async {
    final prefs = await SharedPreferences.getInstance();
    await prefs.setString('projects', Project.encode(_projects));
  await prefs.setString('project_groups', ProjectGroup.encode(_groups));
  }

  Future<void> _scanImport() async {
    final imported = await Navigator.of(context).push<Project>(
      MaterialPageRoute(builder: (context) => const ScanQrPage()),
    );
    if (imported != null) {
      await _handleImport(imported);
    }
  }

  Future<void> _handleImport(Project imported) async {
  // When importing, don't assume sender's groups exist locally
  imported.groupId = null;
    final existingIndex = _projects.indexWhere((p) => p.name == imported.name);
    if (existingIndex >= 0) {
      final action = await showDialog<String>(
        context: context,
        builder: (context) => AlertDialog(
          title: const Text('Project Exists'),
          content: Text('A project named "${imported.name}" already exists. What would you like to do?'),
          actions: [
            TextButton(
              onPressed: () => Navigator.of(context).pop('cancel'),
              child: const Text('Cancel'),
            ),
            TextButton(
              onPressed: () => Navigator.of(context).pop('keepBoth'),
              child: const Text('Keep Both'),
            ),
            FilledButton(
              onPressed: () => Navigator.of(context).pop('replace'),
              child: const Text('Replace'),
            ),
          ],
        ),
      );
      if (!mounted || action == null || action == 'cancel') return;
      if (action == 'replace') {
        setState(() {
          _projects[existingIndex] = imported;
        });
      } else {
        // keep both
        final unique = _uniqueName(imported.name);
        setState(() {
          _projects.add(imported.copyWith(name: unique));
        });
      }
    } else {
      setState(() {
        _projects.add(imported);
      });
    }
    await _saveProjects();
  }

  String _uniqueName(String base) {
    var name = base;
    var i = 1;
    while (_projects.any((p) => p.name == name)) {
      i++;
      name = '$base ($i)';
    }
    return name;
  }

  Future<void> _copyProject(int index) async {
    final original = _projects[index];
    final defaultName = _uniqueName('${original.name} (copy)');
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
    final json = original.toJson();
    json['id'] = null;
    json['name'] = _uniqueName(newName);
    final cloned = Project.fromJson(json);

    setState(() {
      _projects.add(cloned);
    });
    await _saveProjects();
  }

  void _addProject() async {
    final newProject = await Navigator.of(context).push<Project>(
      MaterialPageRoute(builder: (context) => const ProjectEditPage()),
    );
    if (newProject != null) {
      setState(() {
        _projects.add(newProject);
      });
      await _saveProjects();
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
    setState(() {
      _groups.add(ProjectGroup(name: name));
    });
    await _saveProjects();
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
    setState(() {
      group.name = name;
    });
    await _saveProjects();
  }

  Future<void> _deleteGroup(ProjectGroup group) async {
    final confirm = await showDialog<bool>(
      context: context,
      builder: (context) => AlertDialog(
        title: const Text('Delete Group'),
        content: const Text('Remove group? Projects will remain and become ungrouped.'),
        actions: [
          TextButton(onPressed: () => Navigator.pop(context, false), child: const Text('Cancel')),
          FilledButton(onPressed: () => Navigator.pop(context, true), child: const Text('Delete')),
        ],
      ),
    );
    if (confirm != true) return;
    setState(() {
      _projects = _projects.map((p) => p.groupId == group.id ? p.copyWith(groupId: null) : p).toList();
      _groups.removeWhere((g) => g.id == group.id);
    });
    await _saveProjects();
  }

  // Drag & drop handles moving projects between groups; no separate picker needed.

  void _editProject(int index) async {
    final updatedProject = await Navigator.of(context).push<Project>(
      MaterialPageRoute(
        builder: (context) => ProjectEditPage(project: _projects[index]),
      ),
    );
    if (updatedProject != null) {
      setState(() {
        _projects[index] = updatedProject;
      });
      await _saveProjects();
    }
  }

  void _deleteProject(int index) {
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
              setState(() {
                _projects.removeAt(index);
              });
              await _saveProjects();
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
    // Build filtered list based on search query
    final String q = _searchQuery.trim().toLowerCase();
    final List<Project> filtered = q.isEmpty
        ? _projects
        : _projects
            .where((p) => p.name.toLowerCase().contains(q) || (p.broker).toLowerCase().contains(q))
            .toList();

    if (_projects.isEmpty) {
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
    final existingGroupIds = _groups.map((g) => g.id).toSet();
    for (final p in filtered) {
      final gid = (p.groupId != null && existingGroupIds.contains(p.groupId)) ? p.groupId : null;
      grouped.putIfAbsent(gid, () => []).add(p);
    }

    // Order: groups, then ungrouped at the end
    final List<Widget> sections = [];

    for (final g in _groups) {
      final items = grouped[g.id] ?? [];
      sections.add(_groupSection(title: g.name, group: g, projects: items));
    }

    final ungrouped = grouped[null] ?? [];
    if (ungrouped.isNotEmpty || _groups.isEmpty) {
      sections.add(_groupSection(title: 'Ungrouped', group: null, projects: ungrouped));
    }

    return ListView(
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
      ],
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
          setState(() {
            project.groupId = group?.id; // null for ungrouped
            _dragHoverGroupKey = null;
          });
          await _saveProjects();
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
              title: Text(
                title,
                style: const TextStyle(fontWeight: FontWeight.bold, fontStyle: FontStyle.italic),
              ),
              subtitle: Text(
                '${projects.length} project${projects.length == 1 ? '' : 's'}',
                style: Theme.of(context).textTheme.labelMedium,
              ),
              initiallyExpanded: true,
              trailing: group == null
                  ? null
                  : Row(
                      mainAxisSize: MainAxisSize.min,
                      children: [
                        IconButton(
                          icon: const Icon(Icons.edit),
                          tooltip: 'Rename group',
                          onPressed: () => _renameGroup(group),
                        ),
                        IconButton(
                          icon: const Icon(Icons.delete),
                          tooltip: 'Delete group',
                          onPressed: () => _deleteGroup(group),
                        ),
                      ],
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
    final index = _projects.indexWhere((p) => p.id == project.id);
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
              multiplier: project.multiplier,
              offset: project.offset,
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
          IconButton(
            icon: const Icon(Icons.copy),
            tooltip: 'Copy project',
            onPressed: () => _copyProject(index),
          ),
          IconButton(
            icon: const Icon(Icons.qr_code),
            tooltip: 'Share via QR',
            onPressed: () {
              Navigator.of(context).push(
                MaterialPageRoute(builder: (_) => ShareQrPage(project: project)),
              );
            },
          ),
          IconButton(
            icon: const Icon(Icons.edit),
            onPressed: () => _editProject(index),
          ),
          IconButton(
            icon: const Icon(Icons.delete),
            onPressed: () => _deleteProject(index),
          ),
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
