import 'package:flutter/material.dart';
import 'global_mqtt.dart';

class GlobalMqttSettingsPage extends StatefulWidget {
  const GlobalMqttSettingsPage({super.key});

  @override
  State<GlobalMqttSettingsPage> createState() => _GlobalMqttSettingsPageState();
}

class _GlobalMqttSettingsPageState extends State<GlobalMqttSettingsPage> {
  final _broker = TextEditingController();
  final _port = TextEditingController();
  final _user = TextEditingController();
  final _pass = TextEditingController();
  bool _loading = true;

  @override
  void initState() {
    super.initState();
    _load();
  }

  Future<void> _load() async {
    final s = await getGlobalMqttSettings();
    _broker.text = s.broker;
    _port.text = s.port.toString();
    _user.text = s.username ?? '';
    _pass.text = s.password ?? '';
    setState(() => _loading = false);
  }

  Future<void> _save() async {
    final broker = _broker.text.trim();
    final port = int.tryParse(_port.text.trim()) ?? 1883;
    final user = _user.text.trim();
    final pass = _pass.text;
    if (broker.isEmpty) {
      ScaffoldMessenger.of(context).showSnackBar(const SnackBar(content: Text('Broker is required')));
      return;
    }
    await setGlobalMqttSettings(GlobalMqttSettings(
      broker: broker,
      port: port,
      username: user.isEmpty ? null : user,
      password: pass.isEmpty ? null : pass,
    ));
    if (!mounted) return;
    ScaffoldMessenger.of(context).showSnackBar(const SnackBar(content: Text('Saved')));
    Navigator.of(context).pop(true);
  }

  @override
  void dispose() {
    _broker.dispose();
    _port.dispose();
    _user.dispose();
    _pass.dispose();
    super.dispose();
  }

  @override
  Widget build(BuildContext context) {
    return Scaffold(
      appBar: AppBar(title: const Text('MQTT Settings')),
      body: _loading
          ? const Center(child: CircularProgressIndicator())
          : Padding(
              padding: const EdgeInsets.all(16),
              child: Column(
                crossAxisAlignment: CrossAxisAlignment.stretch,
                children: [
                  TextField(controller: _broker, decoration: const InputDecoration(labelText: 'Broker (host or ws:// URL)')),
                  const SizedBox(height: 8),
                  TextField(controller: _port, keyboardType: TextInputType.number, decoration: const InputDecoration(labelText: 'Port')),
                  const SizedBox(height: 8),
                  TextField(controller: _user, decoration: const InputDecoration(labelText: 'Username (optional)')),
                  const SizedBox(height: 8),
                  TextField(controller: _pass, obscureText: true, decoration: const InputDecoration(labelText: 'Password (optional)')),
                  const SizedBox(height: 16),
                  FilledButton(onPressed: _save, child: const Text('Save')),
                ],
              ),
            ),
    );
  }
}
