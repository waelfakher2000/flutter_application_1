import 'package:flutter/material.dart';
import 'package:flutter/services.dart';
import 'package:shared_preferences/shared_preferences.dart';
import 'project_model.dart';
import 'main.dart'; // For MainTankPage
import 'project_edit_page.dart';

class ProjectListPage extends StatefulWidget {
  const ProjectListPage({super.key});

  @override
  _ProjectListPageState createState() => _ProjectListPageState();
}

class _ProjectListPageState extends State<ProjectListPage> {
  List<Project> _projects = [];

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

  Future<void> _loadProjects() async {
    final prefs = await SharedPreferences.getInstance();
    final String? projectsString = prefs.getString('projects');
    if (projectsString != null) {
      setState(() {
        _projects = Project.decode(projectsString);
      });
    }
  }

  Future<void> _saveProjects() async {
    final prefs = await SharedPreferences.getInstance();
    await prefs.setString('projects', Project.encode(_projects));
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
        title: const Text('Projects'),
      ),
      body: _projects.isEmpty
          ? const Center(
              child: Text('No projects yet. Add one to get started!'),
            )
          : ListView.builder(
              itemCount: _projects.length,
              itemBuilder: (context, index) {
                final project = _projects[index];
                return ListTile(
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
                        ),
                      ),
                    );
                  },
                  trailing: Row(
                    mainAxisSize: MainAxisSize.min,
                    children: [
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
              },
            ),
      floatingActionButton: FloatingActionButton(
        onPressed: _addProject,
        child: const Icon(Icons.add),
      ),
    );
  }
}
