import 'package:flutter/material.dart';
import 'package:mobile_scanner/mobile_scanner.dart';
import 'package:flutter_application_1/project_model.dart';
import 'package:flutter_application_1/share_codec.dart';

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
      final project = ProjectShareCodec.decodeProject(raw);
      if (!mounted) return;
      setState(() => _handled = true);

      await _showPreviewAndReturn(project);
    } catch (e) {
      // Not our format, ignore and continue scanning
    }
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

  @override
  Widget build(BuildContext context) {
    return Scaffold(
      appBar: AppBar(title: const Text('Scan QR to Import')),
      body: MobileScanner(
        controller: _controller,
        onDetect: _onDetect,
        fit: BoxFit.cover,
      ),
    );
  }
}
