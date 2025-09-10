import 'dart:ui' as ui;
import 'package:flutter/material.dart';
import 'package:flutter/rendering.dart';
import 'package:qr_flutter/qr_flutter.dart';
import 'package:flutter_application_1/project_model.dart';
import 'package:flutter_application_1/share_codec.dart';
import 'package:share_plus/share_plus.dart';
import 'package:path_provider/path_provider.dart';
import 'dart:io';

class ShareQrPage extends StatefulWidget {
  final Project? project; // single project
  final List<Project>? projects; // multi-project
  ShareQrPage({super.key, this.project, this.projects});

  @override
  State<ShareQrPage> createState() => _ShareQrPageState();
}

class _ShareQrPageState extends State<ShareQrPage> {
  bool includeCredentials = false;
  late String payload;
  final GlobalKey _qrKey = GlobalKey();

  @override
  void initState() {
    super.initState();
    payload = _buildPayload();
  }

  void _rebuildPayload(bool value) {
    setState(() {
      includeCredentials = value;
      payload = _buildPayload();
    });
  }

  String _buildPayload() {
    if (widget.projects != null) {
      return ProjectShareCodec.encodeProjects(widget.projects!, includeCredentials: includeCredentials);
    }
    return ProjectShareCodec.encodeProject(widget.project!, includeCredentials: includeCredentials);
  }

  Future<void> _shareText() async {
    final label = widget.projects != null ? 'Multiple projects (${widget.projects!.length})' : 'Project ${widget.project!.name}';
    await Share.share('IoT Monitoring share: $label\n$payload');
  }

  Future<void> _shareQrImage() async {
    try {
      final boundary = _qrKey.currentContext?.findRenderObject() as RenderRepaintBoundary?;
      if (boundary == null) return;
      final ui.Image image = await boundary.toImage(pixelRatio: 3.0);
      final byteData = await image.toByteData(format: ui.ImageByteFormat.png);
      if (byteData == null) return;
      final pngBytes = byteData.buffer.asUint8List();
      final dir = await getTemporaryDirectory();
      final file = File('${dir.path}/share_qr.png');
      await file.writeAsBytes(pngBytes);
      await Share.shareXFiles([XFile(file.path)], text: 'Scan to import into IoT Monitoring');
    } catch (_) {}
  }

  @override
  Widget build(BuildContext context) {
    final theme = Theme.of(context);

    return Scaffold(
      appBar: AppBar(title: const Text('Share via QR')),
      body: Padding(
        padding: const EdgeInsets.all(16.0),
        child: Column(
          crossAxisAlignment: CrossAxisAlignment.stretch,
          children: [
            Card(
              clipBehavior: Clip.antiAlias,
              child: Column(
                crossAxisAlignment: CrossAxisAlignment.start,
                children: [
                  Container(
                    width: double.infinity,
                    color: theme.colorScheme.primaryContainer,
                    padding: const EdgeInsets.all(12),
                    child: Text('Project QR', style: theme.textTheme.titleMedium?.copyWith(color: theme.colorScheme.onPrimaryContainer)),
                  ),
                  Padding(
                    padding: const EdgeInsets.all(16.0),
                    child: Column(
                      children: [
                        RepaintBoundary(
                          key: _qrKey,
                          child: QrImageView(
                            data: payload,
                            version: QrVersions.auto,
                            size: 260,
                            gapless: false,
                          ),
                        ),
                        const SizedBox(height: 12),
                        Text(
                          widget.projects != null
                              ? 'Scan to import ${widget.projects!.length} projects.'
                              : 'Scan this QR on another device to import the project.',
                          style: theme.textTheme.bodyMedium,
                        ),
                        const SizedBox(height: 12),
                        Row(
                          children: [
                            Switch(
                              value: includeCredentials,
                              onChanged: _rebuildPayload,
                            ),
                            const SizedBox(width: 8),
                            const Expanded(child: Text('Include credentials (username/password) in QR'))
                          ],
                        ),
                        const SizedBox(height: 8),
                        Text('Note: Credentials are excluded by default for safety.', style: theme.textTheme.bodySmall?.copyWith(color: theme.colorScheme.onSurfaceVariant)),
                        const SizedBox(height: 16),
                        Wrap(
                          spacing: 12,
                          children: [
                            OutlinedButton.icon(
                              icon: const Icon(Icons.share),
                              label: const Text('Share Text'),
                              onPressed: _shareText,
                            ),
                            OutlinedButton.icon(
                              icon: const Icon(Icons.image),
                              label: const Text('Share QR Image'),
                              onPressed: _shareQrImage,
                            ),
                          ],
                        ),
                      ],
                    ),
                  ),
                ],
              ),
            ),
          ],
        ),
      ),
    );
  }
}
