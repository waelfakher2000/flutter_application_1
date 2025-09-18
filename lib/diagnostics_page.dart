import 'dart:convert';
import 'package:flutter/material.dart';
import 'package:provider/provider.dart';
import 'package:http/http.dart' as http;
import 'auth_provider.dart';
import 'backend_client.dart' as backend;

class DiagnosticsPage extends StatefulWidget {
  const DiagnosticsPage({super.key});
  @override
  State<DiagnosticsPage> createState() => _DiagnosticsPageState();
}

class _DiagnosticsPageState extends State<DiagnosticsPage> {
  final List<_DiagResult> _results = [];
  bool _running = false;

  void _add(String name, String status, {String? detail, bool ok = true}) {
    setState(() { _results.add(_DiagResult(DateTime.now(), name, status, detail, ok)); });
  }

  Future<void> _run() async {
    if (_running) return; setState(() { _running = true; _results.clear(); });
    final base = await backend.resolveBackendUrl();
    if (base == null) {
      _add('Base URL','Not configured', ok: false);
      setState(() { _running = false; });
      return;
    }
    _add('Base URL', base);
    final auth = context.read<AuthProvider>();

    Future<void> simpleGet(String name, String path) async {
      final url = base.endsWith('/') ? base+path : base+'/'+path;
      final started = DateTime.now();
      try {
        final resp = await http.get(Uri.parse(url), headers: {
          if (auth.isAuthenticated) 'Authorization': 'Bearer ${auth.token}'
        });
        final ms = DateTime.now().difference(started).inMilliseconds;
        _add(name, '${resp.statusCode} in ${ms}ms',
          detail: resp.body.length > 400 ? resp.body.substring(0,400)+'...' : resp.body,
          ok: resp.statusCode >=200 && resp.statusCode<400);
      } catch (e) {
        _add(name, 'EXCEPTION', detail: e.toString(), ok: false);
      }
    }

    await simpleGet('Ping','ping');
    await simpleGet('Health','health');

    // Probe signup path existence with HEAD (or POST expecting validation error)
    final signupUrl = base.endsWith('/') ? base+'signup' : base+'/signup';
    try {
      final resp = await http.post(Uri.parse(signupUrl), headers: {'Content-Type':'application/json'}, body: jsonEncode({'email':'_probe@example.com','password':'short'}));
      _add('Signup route', 'Status ${resp.statusCode}', detail: resp.body, ok: resp.statusCode!=404);
    } catch (e) { _add('Signup route', 'EXCEPTION', detail: e.toString(), ok:false); }

    // Authenticated projects test if logged in
    if (auth.isAuthenticated) {
      await simpleGet('Projects (auth)','projects');
    } else {
      _add('Projects (auth)','Skipped (not logged in)', ok: true);
    }

    setState(() { _running = false; });
  }

  @override
  void initState() { super.initState(); Future.microtask(_run); }

  @override
  Widget build(BuildContext context) {
    return Scaffold(
      appBar: AppBar(title: const Text('Diagnostics'), actions: [
        IconButton(onPressed: _running ? null : _run, icon: const Icon(Icons.refresh))
      ]),
      body: ListView.builder(
        itemCount: _results.length,
        itemBuilder: (ctx,i){
          final r = _results[i];
          return ListTile(
            leading: Icon(r.ok ? Icons.check_circle : Icons.error, color: r.ok? Colors.green: Colors.red),
            title: Text(r.name),
            subtitle: r.detail!=null? Text(r.detail!): null,
            trailing: Text(r.status, style: TextStyle(color: r.ok? Colors.green: Colors.red)),
          );
        }
      ),
    );
  }
}

class _DiagResult {
  final DateTime ts; final String name; final String status; final String? detail; final bool ok;
  _DiagResult(this.ts,this.name,this.status,this.detail,this.ok);
}
