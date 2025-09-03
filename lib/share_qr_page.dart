import 'package:flutter/material.dart';
import 'package:qr_flutter/qr_flutter.dart';
import 'package:flutter_application_1/project_model.dart';
import 'package:flutter_application_1/share_codec.dart';

class ShareQrPage extends StatefulWidget {
  final Project project;
  const ShareQrPage({super.key, required this.project});

  @override
  State<ShareQrPage> createState() => _ShareQrPageState();
}

class _ShareQrPageState extends State<ShareQrPage> {
  bool includeCredentials = false;
  late String payload;

  @override
  void initState() {
    super.initState();
    payload = ProjectShareCodec.encodeProject(widget.project, includeCredentials: includeCredentials);
  }

  void _rebuildPayload(bool value) {
    setState(() {
      includeCredentials = value;
      payload = ProjectShareCodec.encodeProject(widget.project, includeCredentials: includeCredentials);
    });
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
                        QrImageView(
                          data: payload,
                          version: QrVersions.auto,
                          size: 260,
                          gapless: false,
                        ),
                        const SizedBox(height: 12),
                        Text('Scan this QR on another device to import the project.', style: theme.textTheme.bodyMedium),
                        const SizedBox(height: 12),
                        Row(
                          children: [
                            Switch(
                              value: includeCredentials,
                              onChanged: _rebuildPayload,
                            ),
                            const SizedBox(width: 8),
                            const Expanded(
                              child: Text('Include credentials (username/password) in QR')
                            )
                          ],
                        ),
                        const SizedBox(height: 8),
                        Text('Note: Credentials are excluded by default for safety.', style: theme.textTheme.bodySmall?.copyWith(color: theme.colorScheme.onSurfaceVariant)),
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
