import 'dart:convert';
import 'dart:math' as math;
import 'package:flutter/material.dart';
import 'package:http/http.dart' as http;
import 'package:share_plus/share_plus.dart';
import 'dart:io' show File; // non-web file save
import 'package:path_provider/path_provider.dart';
// Conditional CSV downloader: stub for mobile/desktop, web implementation for web
import 'csv_download/download_csv_stub.dart'
  if (dart.library.html) 'csv_download/download_csv_web.dart';
import 'backend_client.dart';
import 'project_model.dart';

class HistoryChartPage extends StatefulWidget {
  final Project project;
  const HistoryChartPage({super.key, required this.project});

  @override
  State<HistoryChartPage> createState() => _HistoryChartPageState();
}

class _HistoryChartPageState extends State<HistoryChartPage> {
  List<ReadingPoint> _points = [];
  bool _loading = true;
  String? _error;
  DateTimeRange? _range; // user-selected interval
  final ValueNotifier<bool> _expanded = ValueNotifier<bool>(false);
  final TransformationController _transformController = TransformationController();
  Offset? _tooltipPixel; // in child (untransformed) coordinates
  ReadingPoint? _tooltipPoint;
  final GlobalKey _chartKey = GlobalKey();
  int? _selectedIndex; // index of selected point for crosshair

  @override
  void initState() {
    super.initState();
    _load();
  }

  Future<void> _pickRange() async {
    final now = DateTime.now();
    final initialStart = now.subtract(const Duration(hours: 6));
    final picked = await showDateRangePicker(
      context: context,
      firstDate: now.subtract(const Duration(days: 30)),
      lastDate: now.add(const Duration(days: 1)),
      initialDateRange: _range ?? DateTimeRange(start: initialStart, end: now),
      helpText: 'Select interval for history',
    );
    if (picked == null) return; // user cancelled
    // local helper to refine time; we fetch times sequentially but store raw values, deferring state until finished
    Future<DateTime> refine(DateTime base, TimeOfDay initial) async {
      final t = await showTimePicker(context: context, initialTime: initial);
      if (t == null) return base;
      return DateTime(base.year, base.month, base.day, t.hour, t.minute);
    }
    DateTime start = picked.start;
    DateTime end = picked.end;
    start = await refine(start, TimeOfDay.fromDateTime(start));
    end = await refine(end, TimeOfDay.fromDateTime(end));
    if (!mounted) return; // widget disposed while picking times
    if (end.isBefore(start)) {
      final tmp = start; start = end; end = tmp; // swap
    }
    setState(() => _range = DateTimeRange(start: start, end: end));
    _load();
  }

  Future<void> _load() async {
    setState(() { _loading = true; _error = null; });
    try {
      final base = await resolveBackendUrl();
      if (base == null || base.isEmpty) {
        setState(() { _error = 'Backend not configured'; _loading = false; });
        return;
      }
      final params = <String, String>{
        'projectId': widget.project.id,
        'limit': '1000',
      };
      if (_range != null) {
        // Backend expects ISO8601 or implement both; we'll use toIso8601String
        params['from'] = _range!.start.toUtc().toIso8601String();
        params['to'] = _range!.end.toUtc().toIso8601String();
      }
      final qp = params.entries.map((e) => '${Uri.encodeQueryComponent(e.key)}=${Uri.encodeQueryComponent(e.value)}').join('&');
      final uri = Uri.parse(base.endsWith('/') ? '${base}readings?$qp' : '$base/readings?$qp');
      final resp = await httpGet(uri);
      if (resp.statusCode >= 200 && resp.statusCode < 300) {
        final decoded = jsonDecode(resp.body) as Map<String, dynamic>;
        final items = (decoded['items'] as List<dynamic>? ?? []);
        final pts = <ReadingPoint>[];
        for (final r in items) {
          final tsStr = r['ts'];
          final lvl = (r['levelMeters'] is num) ? (r['levelMeters'] as num).toDouble() : null;
          if (lvl != null && tsStr is String) {
            final ts = DateTime.tryParse(tsStr);
            if (ts != null) pts.add(ReadingPoint(ts, lvl));
          }
        }
        pts.sort((a, b) => a.time.compareTo(b.time));
        setState(() { _points = pts; _loading = false; });
      } else {
        setState(() { _error = 'Server ${resp.statusCode}'; _loading = false; });
      }
    } catch (e) {
      setState(() { _error = e.toString(); _loading = false; });
    }
  }

  @override
  Widget build(BuildContext context) {
  final bool isWide = MediaQuery.of(context).size.width > 640;
    final chart = _loading
        ? const Center(child: CircularProgressIndicator())
        : _error != null
            ? Center(child: Text(_error!))
            : _points.isEmpty
                ? const Center(child: Text('No readings'))
    : HistoryChart(key: _chartKey, points: _points, xLabel: 'Time', yLabel: 'Level (m)', selectedIndex: _selectedIndex);

    return Scaffold(
      appBar: AppBar(
        title: Text('History - ${widget.project.name}'),
        actions: [
        if (!_loading && _points.isNotEmpty)
          IconButton(
            tooltip: 'Export CSV',
            icon: const Icon(Icons.download),
            onPressed: _exportCsv,
          ),
          IconButton(
            tooltip: 'Pick interval',
            icon: const Icon(Icons.date_range),
            onPressed: _pickRange,
          ),
          IconButton(onPressed: _load, icon: const Icon(Icons.refresh)),
        ],
      ),
      body: Column(
        children: [
          if (_range != null)
            Padding(
              padding: const EdgeInsets.fromLTRB(12, 8, 12, 4),
              child: Row(
                children: [
                  Expanded(
                    child: Text(
                      '${_range!.start}  →  ${_range!.end}',
                      style: Theme.of(context).textTheme.bodySmall,
                      overflow: TextOverflow.ellipsis,
                    ),
                  ),
                  TextButton(onPressed: () { setState(() { _range = null; }); _load(); }, child: const Text('Clear'))
                ],
              ),
            ),
          // Chart area with limited default height
          ValueListenableBuilder<bool>(
            valueListenable: _expanded,
            builder: (context, isExpanded, _) {
              final double targetHeight = isExpanded ?  (MediaQuery.of(context).size.height * 0.55).clamp(220.0, 520.0) : (isWide ? 300.0 : 250.0);
              final showReset = !_matrixIsIdentity(_transformController.value);
              return AnimatedContainer(
                duration: const Duration(milliseconds: 250),
                curve: Curves.easeInOut,
                padding: const EdgeInsets.all(12),
                height: targetHeight,
                width: double.infinity,
                child: DecoratedBox(
                  decoration: BoxDecoration(
                    borderRadius: BorderRadius.circular(12),
                    color: Theme.of(context).colorScheme.surface.withValues(alpha: 0.4),
                  ),
                  child: ClipRRect(
                    borderRadius: BorderRadius.circular(12),
                    child: Stack(
                      children: [
                        Positioned.fill(
                          child: Listener(
                            behavior: HitTestBehavior.opaque,
                            onPointerDown: (e) {
                              _handleTap(e.localPosition);
                            },
                          ),
                        ),
                        InteractiveViewer(
                          transformationController: _transformController,
                          minScale: 0.5,
                          maxScale: 4.0,
                          panEnabled: true,
                          scaleEnabled: true,
                          onInteractionEnd: (_) { setState((){}); },
                          onInteractionUpdate: (_) { /* rebuild tooltip position relative to new transform */ if (_tooltipPoint != null) setState((){}); },
                          child: GestureDetector(
                            behavior: HitTestBehavior.translucent,
                            onTapDown: (d) => _handleTap(d.localPosition),
                            onLongPressStart: (d) => _handleTap(d.localPosition),
                            onLongPressMoveUpdate: (d) => _handleTap(d.localPosition),
                            onPanDown: (d) => _handleTap(d.localPosition),
                            onPanUpdate: (d) => _handleTap(d.localPosition),
                            child: chart,
                          ),
                        ),
                        if (showReset)
                          Positioned(
                            top: 8,
                            right: 8,
                            child: ElevatedButton.icon(
                              style: ElevatedButton.styleFrom(padding: const EdgeInsets.symmetric(horizontal: 8, vertical: 4), minimumSize: const Size(0,0)),
                              onPressed: () {
                                _transformController.value = Matrix4.identity();
                                setState((){});
                              },
                              icon: const Icon(Icons.fullscreen_exit, size: 16),
                              label: const Text('Reset', style: TextStyle(fontSize: 12)),
                            ),
                          ),
                        if (_tooltipPoint != null && _tooltipPixel != null)
                        if (_tooltipPoint != null && _tooltipPixel != null)
                          Positioned(
                            left: _clampTooltip(_tooltipPixel!.dx + 8, context),
                            top: _clampTooltipY(_tooltipPixel!.dy - 30, context),
                            child: _buildTooltip(context),
                          ),
                      ],
                    ),
                  ),
                ),
              );
            },
          ),
          Align(
            alignment: Alignment.centerRight,
            child: Padding(
              padding: const EdgeInsets.only(right: 16, bottom: 8),
              child: ValueListenableBuilder<bool>(
                valueListenable: _expanded,
                builder: (context, isExpanded, _) => TextButton.icon(
                  onPressed: () => _expanded.value = !isExpanded,
                  icon: Icon(isExpanded ? Icons.expand_less : Icons.expand_more),
                  label: Text(isExpanded ? 'Collapse' : 'Expand'),
                ),
              ),
            ),
          ),
        ],
      ),
    );
  }

  bool _matrixIsIdentity(Matrix4 m) {
    final id = Matrix4.identity();
    for (int i = 0; i < 16; i++) {
      if ((m.storage[i] - id.storage[i]).abs() > 0.000001) return false;
    }
    return true;
  }

  void _handleTap(Offset pos) {
  if (_points.isEmpty) return;
    final box = _chartKey.currentContext?.findRenderObject() as RenderBox?;
    if (box == null) return;
    final size = box.size;
    // Constants (must match painter)
    const chartPadLeft = 52.0;
    const bottomAxisSpace = 42.0;
    const topPad = 12.0;
    const rightPad = 12.0;
    final chartRect = Rect.fromLTWH(chartPadLeft, topPad, size.width - chartPadLeft - rightPad, size.height - topPad - bottomAxisSpace);

    // Invert current transform in case zoom/pan applied
  final Matrix4 inv = Matrix4.inverted(_transformController.value);
  final storage = inv.storage;
  final x = storage[0] * pos.dx + storage[4] * pos.dy + storage[12];
  final y = storage[1] * pos.dx + storage[5] * pos.dy + storage[13];
  final childPos = Offset(x, y);
    if (!chartRect.contains(childPos)) {
      setState(() { _tooltipPoint = null; _tooltipPixel = null; });
      return;
    }
    final minT = _points.first.time.millisecondsSinceEpoch.toDouble();
    final maxT = _points.last.time.millisecondsSinceEpoch.toDouble();
    double minV = _points.map((e)=>e.value).reduce((a,b)=>a<b?a:b);
    double maxV = _points.map((e)=>e.value).reduce((a,b)=>a>b?a:b);
    if (minV == maxV) maxV += 0.001;
    final frac = ((childPos.dx - chartRect.left) / chartRect.width).clamp(0.0, 1.0);
    final targetT = minT + (maxT - minT) * frac;
    // Binary search nearest
    int lo = 0, hi = _points.length - 1;
    while (lo < hi) {
      final mid = (lo + hi) >> 1;
      final tMid = _points[mid].time.millisecondsSinceEpoch.toDouble();
      if (tMid < targetT) {
        lo = mid + 1;
      } else {
        hi = mid;
      }
    }
    int idx = lo;
    if (idx > 0) {
      final prevT = _points[idx-1].time.millisecondsSinceEpoch.toDouble();
      final currT = _points[idx].time.millisecondsSinceEpoch.toDouble();
      if ((targetT - prevT).abs() < (currT - targetT).abs()) idx = idx - 1;
    }
    final p = _points[idx];
    // Compute pixel for tooltip anchor
    final pX = chartRect.left + ((p.time.millisecondsSinceEpoch - minT) / (maxT - minT)) * chartRect.width;
    final pY = chartRect.top + (1 - (p.value - minV) / (maxV - minV)) * chartRect.height;
    setState(() {
      _tooltipPoint = p;
      _tooltipPixel = Offset(pX, pY);
      _selectedIndex = idx;
    });
  }

  Widget _buildTooltip(BuildContext context) {
    final p = _tooltipPoint!;
    final ts = p.time;
    final sameDay = ts.day == DateTime.now().day && ts.month == DateTime.now().month && ts.year == DateTime.now().year;
    final timeStr = sameDay ? '${_two(ts.hour)}:${_two(ts.minute)}:${_two(ts.second)}' : '${_two(ts.month)}-${_two(ts.day)} ${_two(ts.hour)}:${_two(ts.minute)}';
    return Material(
      elevation: 2,
      borderRadius: BorderRadius.circular(6),
      color: Theme.of(context).colorScheme.surfaceContainerHigh,
      child: Padding(
        padding: const EdgeInsets.symmetric(horizontal: 8, vertical: 6),
        child: Text('${p.value.toStringAsFixed(3)} m\n$timeStr', style: Theme.of(context).textTheme.labelSmall),
      ),
    );
  }

  String _two(int v) => v < 10 ? '0$v' : '$v';

  double _clampTooltip(double x, BuildContext context) {
    final width = MediaQuery.of(context).size.width;
    const pad = 8.0;
    const tooltipWidth = 120.0; // rough estimate
    if (x + tooltipWidth > width - pad) return width - tooltipWidth - pad;
    if (x < pad) return pad;
    return x;
  }

  double _clampTooltipY(double y, BuildContext context) {
    final height = MediaQuery.of(context).size.height;
    const pad = 8.0;
    const tooltipHeight = 48.0;
    if (y < pad) return pad;
    if (y + tooltipHeight > height - pad) return height - tooltipHeight - pad;
    return y;
  }

  Future<void> _exportCsv() async {
    if (_points.isEmpty) return;
    try {
      final sb = StringBuffer('timestamp,value\n');
      for (final p in _points) {
        sb.writeln('${p.time.toIso8601String()},${p.value.toStringAsFixed(6)}');
      }
      final csv = sb.toString();
      final rangeSuffix = _range != null ? '_${_range!.start.toIso8601String()}_${_range!.end.toIso8601String()}' : '';
      final fileName = 'readings$rangeSuffix.csv';
      // Web path handled by injected download function; non-web we write to temp and share.
      bool downloadedOnWeb = false;
      try {
        await triggerCsvDownload(fileName, csv);
        // If running on web, above completes actual download; on other platforms it's a no-op.
        // We best-effort detect web by absence of File operations below; continue to file save otherwise.
        downloadedOnWeb = true; // Will be ignored silently on non-web since stub returns.
      } catch (_) {
        // Ignore; fall back to native path.
      }
      if (!downloadedOnWeb) {
        final dir = await getTemporaryDirectory();
        final file = File('${dir.path}/$fileName');
        await file.writeAsString(csv);
        await Share.shareXFiles([XFile(file.path, mimeType: 'text/csv')], subject: 'Readings CSV');
      }
    } catch (e) {
      if (!mounted) return;
      ScaffoldMessenger.of(context).showSnackBar(SnackBar(content: Text('Export failed: $e')));
    }
  }
}

class ReadingPoint {
  final DateTime time;
  final double value;
  ReadingPoint(this.time, this.value);
}

// Simple custom painter chart (time vs value)
class HistoryChart extends StatelessWidget {
  final List<ReadingPoint> points;
  final String xLabel;
  final String yLabel;
  final int? selectedIndex;
  const HistoryChart({super.key, required this.points, this.xLabel = 'Time', this.yLabel = 'Value', this.selectedIndex});

  @override
  Widget build(BuildContext context) {
    return LayoutBuilder(builder: (context, constraints) {
      return CustomPaint(
        painter: _HistoryPainter(points: points, theme: Theme.of(context), xLabel: xLabel, yLabel: yLabel, selectedIndex: selectedIndex),
        size: Size(constraints.maxWidth, constraints.maxHeight),
      );
    });
  }
}

class _HistoryPainter extends CustomPainter {
  final List<ReadingPoint> points;
  final ThemeData theme;
  final String xLabel;
  final String yLabel;
  final int? selectedIndex;
  _HistoryPainter({required this.points, required this.theme, required this.xLabel, required this.yLabel, required this.selectedIndex});

  String _fmtSameDay(DateTime dt) => '${_two(dt.hour)}:${_two(dt.minute)}';
  String _fmtOtherDay(DateTime dt) => '${_two(dt.month)}-${_two(dt.day)} ${_two(dt.hour)}:${_two(dt.minute)}';
  String _two(int v) => v < 10 ? '0$v' : '$v';

  @override
  void paint(Canvas canvas, Size size) {
    // surfaceVariant deprecated; choosing surfaceContainerHighest for backdrop
    final bg = theme.colorScheme.surfaceContainerHighest;
    final axisPaint = Paint()
      ..color = theme.colorScheme.onSurface.withValues(alpha: 0.6)
      ..strokeWidth = 1;
    final linePaint = Paint()
      ..color = theme.colorScheme.primary
      ..strokeWidth = 2
      ..style = PaintingStyle.stroke;
    final fillPaint = Paint()
      ..color = theme.colorScheme.primary.withValues(alpha: 0.15)
      ..style = PaintingStyle.fill;

    final rect = Offset.zero & size;
    canvas.drawRRect(RRect.fromRectAndRadius(rect, const Radius.circular(8)), Paint()..color = bg);

    if (points.length < 2) {
      _drawPointOnly(canvas, size);
      return;
    }
    final times = points.map((e) => e.time.millisecondsSinceEpoch.toDouble()).toList();
    final values = points.map((e) => e.value).toList();
    final minT = times.first;
    final maxT = times.last;
    double minV = values.reduce((a, b) => a < b ? a : b);
    double maxV = values.reduce((a, b) => a > b ? a : b);
    if (minV == maxV) { maxV += 0.001; }

  final chartPadLeft = 52.0;
  final bottomAxisSpace = 42.0;
  final topPad = 12.0;
  final rightPad = 12.0;
  final chart = Rect.fromLTWH(chartPadLeft, topPad, size.width - chartPadLeft - rightPad, size.height - topPad - bottomAxisSpace);

    // Area path
    final path = Path();
    for (int i = 0; i < points.length; i++) {
      final p = points[i];
      final x = chart.left + ( (p.time.millisecondsSinceEpoch - minT) / (maxT - minT) ) * chart.width;
      final y = chart.top + (1 - (p.value - minV) / (maxV - minV)) * chart.height;
      if (i == 0) {
        path.moveTo(x, y);
      } else {
        path.lineTo(x, y);
      }
    }
    final fillPath = Path.from(path)
      ..lineTo(chart.right, chart.bottom)
      ..lineTo(chart.left, chart.bottom)
      ..close();
    canvas.drawPath(fillPath, fillPaint);
    canvas.drawPath(path, linePaint);
    canvas.drawPath(path, linePaint);

    // Crosshair & marker if selected
    if (selectedIndex != null && selectedIndex! >=0 && selectedIndex! < points.length) {
      final sp = points[selectedIndex!];
      final sx = chart.left + ((sp.time.millisecondsSinceEpoch - minT) / (maxT - minT)) * chart.width;
      final sy = chart.top + (1 - (sp.value - minV) / (maxV - minV)) * chart.height;
      final crossPaint = Paint()
        ..color = theme.colorScheme.secondary
        ..strokeWidth = 1;
      // vertical line
      canvas.drawLine(Offset(sx, chart.top), Offset(sx, chart.bottom), crossPaint..color = crossPaint.color.withValues(alpha: 0.6));
      // point marker
      canvas.drawCircle(Offset(sx, sy), 4, Paint()..color = theme.colorScheme.secondary);
      canvas.drawCircle(Offset(sx, sy), 7, Paint()..color = theme.colorScheme.secondary.withValues(alpha: 0.25));
    }

    // Axes
    canvas.drawLine(Offset(chart.left, chart.top), Offset(chart.left, chart.bottom), axisPaint);
    canvas.drawLine(Offset(chart.left, chart.bottom), Offset(chart.right, chart.bottom), axisPaint);

    final textPainter = TextPainter(textDirection: TextDirection.ltr, maxLines: 1);
    // Y labels (5)
    for (int i = 0; i <= 4; i++) {
      final frac = i / 4;
      final v = maxV - (maxV - minV) * frac;
      final y = chart.top + chart.height * frac;
      textPainter.text = TextSpan(text: v.toStringAsFixed(3), style: TextStyle(fontSize: 10, color: theme.colorScheme.onSurface));
      textPainter.layout();
      textPainter.paint(canvas, Offset(chart.left - textPainter.width - 4, y - textPainter.height / 2));
      canvas.drawLine(Offset(chart.left - 3, y), Offset(chart.left, y), axisPaint);
    }
    // X labels (up to 6 ticks including ends)
    int steps = 5;
    for (int i = 0; i <= steps; i++) {
      final frac = (steps == 0) ? 0 : i / steps;
      final tMs = minT + (maxT - minT) * frac;
      final dt = DateTime.fromMillisecondsSinceEpoch(tMs.toInt());
      final sameDay = dt.day == points.last.time.day && dt.month == points.last.time.month && dt.year == points.last.time.year;
  final label = sameDay ? _fmtSameDay(dt) : _fmtOtherDay(dt);
      final x = chart.left + chart.width * frac;
      textPainter.text = TextSpan(text: label, style: TextStyle(fontSize: 10, color: theme.colorScheme.onSurface));
      textPainter.layout();
      textPainter.paint(canvas, Offset(x - textPainter.width / 2, chart.bottom + 4));
      canvas.drawLine(Offset(x, chart.bottom), Offset(x, chart.bottom + 3), axisPaint);
    }

    // Axis labels
    final axisTp = TextPainter(textDirection: TextDirection.ltr, maxLines: 1);
    // Y axis label (rotated)
    axisTp.text = TextSpan(text: yLabel, style: TextStyle(fontSize: 11, color: theme.colorScheme.onSurface));
    axisTp.layout(maxWidth: chart.height);
    canvas.save();
    canvas.translate(12, chart.top + chart.height / 2 + axisTp.width / 2);
  canvas.rotate(-math.pi / 2);
    axisTp.paint(canvas, Offset.zero);
    canvas.restore();
    // X axis label
    axisTp.text = TextSpan(text: xLabel, style: TextStyle(fontSize: 11, color: theme.colorScheme.onSurface));
    axisTp.layout();
    axisTp.paint(canvas, Offset(chart.left + chart.width / 2 - axisTp.width / 2, chart.bottom + 22));
  }

  void _drawPointOnly(Canvas canvas, Size size) {
    if (points.isEmpty) return;
    final p = points.first;
  final txt = '${p.value.toStringAsFixed(3)} @ ${_fmtSameDay(p.time)}';
    final tp = TextPainter(text: TextSpan(text: txt, style: const TextStyle(fontSize: 14)), textDirection: TextDirection.ltr);
    tp.layout(maxWidth: size.width - 20);
    tp.paint(canvas, const Offset(10, 10));
  }

  @override
  bool shouldRepaint(covariant _HistoryPainter oldDelegate) => oldDelegate.points != points || oldDelegate.selectedIndex != selectedIndex;
}

// Lightweight http.get helper
Future<http.Response> httpGet(Uri uri) => http.get(uri).timeout(const Duration(seconds: 12));
