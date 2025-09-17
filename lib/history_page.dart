import 'dart:convert';

import 'package:fl_chart/fl_chart.dart';
import 'package:flutter/material.dart';
import 'package:http/http.dart' as http;
import 'package:shared_preferences/shared_preferences.dart';

class HistoryPage extends StatefulWidget {
  final String projectId;
  final String projectName;
  const HistoryPage({super.key, required this.projectId, required this.projectName});

  @override
  State<HistoryPage> createState() => _HistoryPageState();
}

class _HistoryPageState extends State<HistoryPage> {
  String? _apiBase;
  bool _loading = false;
  String? _error;
  List<_Reading> _readings = const [];
  int _hours = 24;

  @override
  void initState() {
    super.initState();
    _loadAndFetch();
  }

  Future<void> _loadAndFetch() async {
    setState(() { _loading = true; _error = null; });
    try {
      final prefs = await SharedPreferences.getInstance();
      final saved = prefs.getString('bridgeUrl');
      final base = (saved != null && saved.trim().isNotEmpty) ? saved.trim() : null;
      setState(() => _apiBase = base);
      if (base == null) {
        setState(() { _error = 'Bridge URL not set. Open Debug page and set Bridge URL.'; _loading = false; });
        return;
      }
      final to = DateTime.now();
      final from = to.subtract(Duration(hours: _hours));
      final uri = Uri.parse(base).replace(
        path: '/readings',
        queryParameters: {
          'projectId': widget.projectId,
          'from': from.toIso8601String(),
          'to': to.toIso8601String(),
        },
      );
      final resp = await http.get(uri);
      if (resp.statusCode >= 200 && resp.statusCode < 300) {
        final data = jsonDecode(resp.body);
        final list = (data is List) ? data : (data['items'] as List? ?? const []);
        final readings = list.map<_Reading>((e) => _Reading.fromJson(e as Map<String, dynamic>)).toList();
        // sort by ts
        readings.sort((a, b) => a.ts.compareTo(b.ts));
        setState(() { _readings = readings; _loading = false; });
      } else {
        setState(() { _error = 'Server error ${resp.statusCode}'; _loading = false; });
      }
    } catch (e) {
      setState(() { _error = 'Failed to load: $e'; _loading = false; });
    }
  }

  @override
  Widget build(BuildContext context) {
    return Scaffold(
      appBar: AppBar(
        title: Text('History • ${widget.projectName}'),
        actions: [
          IconButton(onPressed: _loading ? null : _loadAndFetch, icon: const Icon(Icons.refresh)),
        ],
      ),
      body: Padding(
        padding: const EdgeInsets.all(12),
        child: Column(
          crossAxisAlignment: CrossAxisAlignment.stretch,
          children: [
            Row(children: [
              const Text('Range:'),
              const SizedBox(width: 8),
              DropdownButton<int>(
                value: _hours,
                items: const [
                  DropdownMenuItem(value: 1, child: Text('1h')),
                  DropdownMenuItem(value: 6, child: Text('6h')),
                  DropdownMenuItem(value: 12, child: Text('12h')),
                  DropdownMenuItem(value: 24, child: Text('24h')),
                  DropdownMenuItem(value: 48, child: Text('48h')),
                  DropdownMenuItem(value: 168, child: Text('7d')),
                ],
                onChanged: (v) { if (v != null) { setState(() { _hours = v; }); _loadAndFetch(); }},
              ),
              const Spacer(),
              if (_apiBase != null)
                Flexible(child: Text('API: $_apiBase', overflow: TextOverflow.ellipsis, style: Theme.of(context).textTheme.bodySmall)),
            ]),
            const SizedBox(height: 12),
            if (_error != null)
              Text(_error!, style: TextStyle(color: Theme.of(context).colorScheme.error)),
            if (_loading) const LinearProgressIndicator(),
            const SizedBox(height: 12),
            Expanded(
              child: _readings.isEmpty
                  ? Center(child: Text(_loading ? 'Loading…' : 'No data'))
                  : _Chart(readings: _readings),
            ),
          ],
        ),
      ),
    );
  }
}

class _Reading {
  final DateTime ts;
  final double levelMeters;
  final double percent;
  final double liquidLiters;
  final double totalLiters;
  _Reading({required this.ts, required this.levelMeters, required this.percent, required this.liquidLiters, required this.totalLiters});
  static _Reading fromJson(Map<String, dynamic> m) {
    DateTime ts;
    final t = m['ts'];
    if (t is String) {
      ts = DateTime.tryParse(t) ?? DateTime.now();
    } else if (t is int) {
      ts = DateTime.fromMillisecondsSinceEpoch(t);
    } else {
      ts = DateTime.now();
    }
    double toD(dynamic v) => (v is num) ? v.toDouble() : (double.tryParse('$v') ?? 0.0);
    return _Reading(
      ts: ts,
      levelMeters: toD(m['levelMeters']),
      percent: toD(m['percent']),
      liquidLiters: toD(m['liquidLiters']),
      totalLiters: toD(m['totalLiters']),
    );
  }
}

class _Chart extends StatelessWidget {
  final List<_Reading> readings;
  const _Chart({required this.readings});

  String _fmtTime(DateTime dt) {
    final h = dt.hour.toString().padLeft(2, '0');
    final m = dt.minute.toString().padLeft(2, '0');
    return '$h:$m';
  }

  @override
  Widget build(BuildContext context) {
    if (readings.isEmpty) return const SizedBox();
    final minTs = readings.first.ts.millisecondsSinceEpoch.toDouble();
    final maxTs = readings.last.ts.millisecondsSinceEpoch.toDouble();
    final spots = readings.map((r) => FlSpot(r.ts.millisecondsSinceEpoch.toDouble(), r.levelMeters)).toList();
    final minY = readings.map((r) => r.levelMeters).reduce((a, b) => a < b ? a : b);
    final maxY = readings.map((r) => r.levelMeters).reduce((a, b) => a > b ? a : b);
    return LineChart(
      LineChartData(
        minX: minTs,
        maxX: maxTs,
        minY: (minY - 0.05).clamp(0.0, double.infinity),
        maxY: (maxY + 0.05),
        gridData: const FlGridData(show: true),
        borderData: FlBorderData(show: true),
        titlesData: FlTitlesData(
          leftTitles: AxisTitles(sideTitles: SideTitles(showTitles: true, reservedSize: 36, interval: ((maxY-minY)/4).clamp(0.05, 1.0))),
          bottomTitles: AxisTitles(
            sideTitles: SideTitles(
              showTitles: true,
              reservedSize: 28,
              interval: ((maxTs - minTs) / 4).clamp(60 * 60 * 1000, double.infinity),
              getTitlesWidget: (value, meta) {
                final dt = DateTime.fromMillisecondsSinceEpoch(value.toInt());
                return Text(_fmtTime(dt), style: Theme.of(context).textTheme.bodySmall);
              },
            ),
          ),
        ),
        lineBarsData: [
          LineChartBarData(
            spots: spots,
            isCurved: true,
            color: Theme.of(context).colorScheme.primary,
            barWidth: 2,
            dotData: const FlDotData(show: false),
          ),
        ],
      ),
    );
  }
}
