import 'package:flutter/material.dart';
import 'package:mobile_scanner/mobile_scanner.dart';
import 'package:flutter_application_1/project_model.dart';
import 'package:flutter_application_1/share_codec.dart';
import 'package:image_picker/image_picker.dart';

class ScanQrPage extends StatefulWidget {
  const ScanQrPage({super.key});

  @override
  State<ScanQrPage> createState() => _ScanQrPageState();
}

class _ScanQrPageState extends State<ScanQrPage> {
  final MobileScannerController _controller = MobileScannerController();
  bool _handled = false;

  @override
  void dispose() {
    _controller.dispose();
    super.dispose();
  }

  Future<void> _onDetect(BarcodeCapture capture) async {
    if (_handled) return;
    final barcodes = capture.barcodes;
    if (barcodes.isEmpty) return;
    final raw = barcodes.first.rawValue;
    if (raw == null || raw.isEmpty) return;

    try {
      // Try multi first
      try {
        final list = ProjectShareCodec.decodeProjects(raw);
        if (list.isNotEmpty) {
          if (!mounted) return;
          setState(() {
            _handled = true;
          });
          await _showMultiImportDialog(list);
          return;
        }
      } catch (_) {}

      final project = ProjectShareCodec.decodeProject(raw);
      if (!mounted) return;
      setState(() {
        _handled = true;
      });
      await _showPreviewAndReturn(project);
    } catch (e) {
      // Not our format, ignore and continue scanning
    }
  }

  Future<void> _pickFromGallery() async {
    final picker = ImagePicker();
    final XFile? file = await picker.pickImage(source: ImageSource.gallery);
    if (file == null) return;
  // For now, gallery decode requires additional plugin setup. Placeholder: show snackbar.
  if (!mounted) return;
  ScaffoldMessenger.of(context).showSnackBar(const SnackBar(content: Text('Gallery QR decode pending dependency setup.')));
  return;
  }

  Future<void> _showPreviewAndReturn(Project project) async {
    await showDialog(
      context: context,
      builder: (context) {
        final theme = Theme.of(context);
        return AlertDialog(
          title: const Text('Import Project'),
          content: Column(
            mainAxisSize: MainAxisSize.min,
            crossAxisAlignment: CrossAxisAlignment.start,
            children: [
              Text('Name: ${project.name}'),
              const SizedBox(height: 8),
              Text('Broker: ${project.broker}:${project.port}'),
              const SizedBox(height: 8),
              Text('Topic: ${project.topic}'),
              const SizedBox(height: 8),
              Text('Note: Review settings after import.' , style: theme.textTheme.bodySmall?.copyWith(color: theme.colorScheme.onSurfaceVariant)),
            ],
          ),
          actions: [
            TextButton(
              onPressed: () {
                Navigator.of(context).pop();
                setState(() => _handled = false); // resume scanning
              },
              child: const Text('Cancel'),
            ),
            FilledButton(
              onPressed: () {
                Navigator.of(context).pop(project);
              },
              child: const Text('Import'),
            )
          ],
        );
      },
    );

    if (!mounted) return;
    Navigator.of(context).pop(project);
  }

  Future<void> _showMultiImportDialog(List<Project> projects) async {
    await showDialog(
      context: context,
      builder: (context) => AlertDialog(
        title: Text('Import ${projects.length} Projects'),
        content: SizedBox(
          width: 300,
          child: ListView.builder(
            shrinkWrap: true,
            itemCount: projects.length,
            itemBuilder: (c, i) => ListTile(
              dense: true,
              title: Text(projects[i].name),
              subtitle: Text(projects[i].broker),
            ),
          ),
        ),
        actions: [
          TextButton(
            onPressed: () {
              Navigator.of(context).pop();
              setState(() => _handled = false);
            },
            child: const Text('Cancel'),
          ),
          FilledButton(
            onPressed: () => Navigator.of(context).pop(true),
            child: const Text('Import All'),
          ),
        ],
      ),
    ).then((ok) {
      if (ok == true) {
        Navigator.of(context).pop(projects);
      }
    });
  }

  @override
  Widget build(BuildContext context) {
    return Scaffold(
      appBar: AppBar(
        title: const Text('Scan QR to Import'),
        actions: [
          IconButton(
            tooltip: 'From Gallery',
            icon: const Icon(Icons.image),
            onPressed: _pickFromGallery,
          )
        ],
      ),
      body: MobileScanner(
        controller: _controller,
        onDetect: _onDetect,
        fit: BoxFit.cover,
      ),
    );
  }
}
