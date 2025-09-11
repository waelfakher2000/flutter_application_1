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
  bool _popping = false;

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
    try {
      final path = file.path;
      if (path.isEmpty) return;
      // mobile_scanner exposes analyzeImage for still images (native); if unsupported catch and fallback.
      final success = await _controller.analyzeImage(path);
      if (!success) {
        if (!mounted) return;
        ScaffoldMessenger.of(context).showSnackBar(const SnackBar(content: Text('No QR code found in image.')));
        return; 
      }
      // analyzeImage will trigger onDetect; we just wait briefly
      return;
      /* Deprecated manual handling kept for reference
      final raw = ...;
      if (raw == null || raw.isEmpty) {
        if (!mounted) return; 
        ScaffoldMessenger.of(context).showSnackBar(const SnackBar(content: Text('Invalid QR data.')));
        return;
      }
      // Reuse logic similar to live scan
      try {
        final multi = ProjectShareCodec.decodeProjects(raw);
        if (multi.isNotEmpty) {
          if (!mounted) return;
          _handled = true;
          await _showMultiImportDialog(multi);
          return;
        }
      } catch (_) {}
      try {
        final single = ProjectShareCodec.decodeProject(raw);
        if (!mounted) return;
        _handled = true;
        await _showPreviewAndReturn(single);
        return;
      } catch (e) {
        if (!mounted) return;
        ScaffoldMessenger.of(context).showSnackBar(const SnackBar(content: Text('Unrecognized QR format.')));
  }*/
    } catch (e) {
      if (!mounted) return;
      ScaffoldMessenger.of(context).showSnackBar(SnackBar(content: Text('Gallery decode failed: $e')));
    }
  }

  Future<void> _showPreviewAndReturn(Project project) async {
  if (!mounted) return;
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
    if (_popping) return;
    _popping = true;
    WidgetsBinding.instance.addPostFrameCallback((_) {
      if (mounted) Navigator.of(context).pop(project);
    });
  }

  Future<void> _showMultiImportDialog(List<Project> projects) async {
  if (!mounted) return;
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
      if (!mounted) return;
      if (ok == true && !_popping) {
        _handled = true;
        _popping = true;
        WidgetsBinding.instance.addPostFrameCallback((_) {
          if (mounted) Navigator.of(context).pop(projects);
        });
      } else if (ok != true) {
        // allow scanning to continue
        setState(() => _handled = false);
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
