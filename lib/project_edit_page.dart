import 'package:flutter/material.dart';
import 'package:google_fonts/google_fonts.dart';
import 'package:flutter_application_1/project_model.dart';
import 'package:flutter_application_1/types.dart';
// Online AI removed; offline helper only

// Simple container for AI helper results
class _AiResult {
  final String formula;
  final String note;
  _AiResult(this.formula, this.note);
}

class ProjectEditPage extends StatefulWidget {
  final Project? project;

  const ProjectEditPage({super.key, this.project});

  @override
  State<ProjectEditPage> createState() => _ProjectEditPageState();
}

class _ProjectEditPageState extends State<ProjectEditPage> {
  final _formKey = GlobalKey<FormState>();

  late TextEditingController _nameController;
  late TextEditingController _brokerController;
  late TextEditingController _portController;
  late TextEditingController _topicController;
  late TextEditingController _usernameController;
  late TextEditingController _passwordController;
  late TextEditingController _heightController;
  late TextEditingController _diameterController;
  late TextEditingController _lengthController;
  late TextEditingController _widthController;
  late TextEditingController _thicknessController;
  late TextEditingController _minController;
  late TextEditingController _maxController;
  late TextEditingController _multiplierController;
  late TextEditingController _offsetController;
  late TextEditingController _noiseDeadbandController;
  late TextEditingController _connectedTanksController;
  // Custom formula
  bool _useCustomFormula = false;
  late TextEditingController _customFormulaController;
  // Test preview controllers
  late TextEditingController _testLevelController;
  String? _formulaError;
  double? _formulaPreviewLiters;
  // AI helper (offline only) state
  late TextEditingController _aiDescriptionController;
  String? _aiSuggestion;
  String? _aiNote;
  String? _aiError;
  final bool _aiBusy = false;
  // Last Will / Presence
  late TextEditingController _lastWillTopicController;
  // Payload JSON options
  bool _payloadIsJson = false;
  late TextEditingController _jsonFieldIndexController;
  late TextEditingController _jsonKeyNameController;
  // Timestamp JSON options
  bool _displayTimeFromJson = false;
  late TextEditingController _jsonTimeFieldIndexController;
  late TextEditingController _jsonTimeKeyNameController;
  // Control button
  bool _useControlButton = false;
  late TextEditingController _controlTopicController;
  ControlMode _controlMode = ControlMode.toggle;
  late TextEditingController _onValueController;
  late TextEditingController _offValueController;
  bool _autoControl = false;
  bool _controlRetained = false;
  MqttQosLevel _controlQos = MqttQosLevel.atLeastOnce;
  // Graduation/scale config
  GraduationSide _graduationSide = GraduationSide.left;
  late TextEditingController _majorTickController; // meters per major tick
  late TextEditingController _minorDivsController; // minor divisions between majors
  // History toggle
  bool _storeHistory = false;

  SensorType _sensorType = SensorType.submersible;
  TankType _tankType = TankType.verticalCylinder;

  @override
  void initState() {
    super.initState();
    final p = widget.project;
  _nameController = TextEditingController(text: p?.name ?? 'New Project');
  _brokerController = TextEditingController(text: p?.broker ?? 'mqttapi.mautoiot.com');
  _portController = TextEditingController(text: p != null ? p.port.toString() : '1883');
  _topicController = TextEditingController(text: p?.topic ?? 'tank/level');
  _usernameController = TextEditingController(text: p?.username ?? 'user');
  _passwordController = TextEditingController(text: p?.password ?? '123456');
    _sensorType = p?.sensorType ?? SensorType.submersible;
    _tankType = p?.tankType ?? TankType.verticalCylinder;
    _heightController = TextEditingController(text: p?.height.toString() ?? '1.0');
    _diameterController = TextEditingController(text: p?.diameter.toString() ?? '0.4');
    _lengthController = TextEditingController(text: p?.length.toString() ?? '1.0');
  _widthController = TextEditingController(text: p?.width.toString() ?? '0.5');
  // Show wall thickness in mm for user editing
  _thicknessController = TextEditingController(text: ((p?.wallThickness ?? 0.0) * 1000).toString());
    _minController = TextEditingController(text: p?.minThreshold?.toString());
    _maxController = TextEditingController(text: p?.maxThreshold?.toString());
    _multiplierController = TextEditingController(text: p?.multiplier.toString() ?? '1.0');
    _offsetController = TextEditingController(text: p?.offset.toString() ?? '0.0');
    _noiseDeadbandController = TextEditingController(text: (p?.noiseDeadbandMeters ?? 0.003).toString());
  _connectedTanksController = TextEditingController(text: (p?.connectedTankCount ?? 1).toString());
  _useCustomFormula = p?.useCustomFormula ?? false;
  _customFormulaController = TextEditingController(text: p?.customFormula ?? '');
  _testLevelController = TextEditingController(text: (p?.height ?? 1.0).toStringAsFixed(3));
  _aiDescriptionController = TextEditingController();
  _lastWillTopicController = TextEditingController(text: p?.lastWillTopic ?? '');
  // Online AI optional; UI controlled by _useOnlineAi
  // Control button
  _useControlButton = p?.useControlButton ?? false;
  _controlTopicController = TextEditingController(text: p?.controlTopic ?? '');
  _controlMode = p?.controlMode ?? ControlMode.toggle;
  _onValueController = TextEditingController(text: p?.onValue ?? 'ON');
  _offValueController = TextEditingController(text: p?.offValue ?? 'OFF');
  _autoControl = p?.autoControl ?? false;
  _controlRetained = p?.controlRetained ?? false;
  _controlQos = p?.controlQos ?? MqttQosLevel.atLeastOnce;
  // JSON payload
  _payloadIsJson = p?.payloadIsJson ?? false;
  _jsonFieldIndexController = TextEditingController(text: (p?.jsonFieldIndex ?? 1).toString());
  _jsonKeyNameController = TextEditingController(text: p?.jsonKeyName ?? '');
  _displayTimeFromJson = p?.displayTimeFromJson ?? false;
  _jsonTimeFieldIndexController = TextEditingController(text: (p?.jsonTimeFieldIndex ?? 1).toString());
  _jsonTimeKeyNameController = TextEditingController(text: p?.jsonTimeKeyName ?? '');
  // Grad/scale
  _graduationSide = p?.graduationSide ?? GraduationSide.left;
  _majorTickController = TextEditingController(text: (p?.scaleMajorTickMeters ?? 0.1).toString());
  _minorDivsController = TextEditingController(text: (p?.scaleMinorDivisions ?? 4).toString());
  _storeHistory = p?.storeHistory ?? false;
  }

  @override
  void dispose() {
    _nameController.dispose();
    _brokerController.dispose();
    _portController.dispose();
    _topicController.dispose();
    _usernameController.dispose();
    _passwordController.dispose();
    _heightController.dispose();
    _diameterController.dispose();
    _lengthController.dispose();
  _widthController.dispose();
  _thicknessController.dispose();
    _minController.dispose();
    _maxController.dispose();
    _multiplierController.dispose();
    _offsetController.dispose();
    _noiseDeadbandController.dispose();
    _connectedTanksController.dispose();
  _customFormulaController.dispose();
  _testLevelController.dispose();
  _aiDescriptionController.dispose();
  _controlTopicController.dispose();
  _onValueController.dispose();
  _offValueController.dispose();
  _lastWillTopicController.dispose();
  _jsonFieldIndexController.dispose();
  _jsonKeyNameController.dispose();
  _jsonTimeFieldIndexController.dispose();
  _jsonTimeKeyNameController.dispose();
  _majorTickController.dispose();
  _minorDivsController.dispose();
  // Online AI removed
    super.dispose();
  }

  void _saveProject() {
    if (_formKey.currentState!.validate()) {
      final project = Project(
        id: widget.project?.id,
  groupId: widget.project?.groupId,
        name: _nameController.text,
        broker: _brokerController.text,
        port: int.parse(_portController.text),
        topic: _topicController.text,
        username: _usernameController.text.isNotEmpty ? _usernameController.text : null,
        password: _passwordController.text.isNotEmpty ? _passwordController.text : null,
        sensorType: _sensorType,
        tankType: _tankType,
        height: double.parse(_heightController.text),
        diameter: double.parse(_diameterController.text),
        length: double.parse(_lengthController.text),
        width: double.parse(_widthController.text),
  // Convert from mm (UI) to meters for storage
  wallThickness: ((double.tryParse(_thicknessController.text) ?? 0.0) / 1000.0),
        minThreshold: _minController.text.isNotEmpty ? double.parse(_minController.text) : null,
        maxThreshold: _maxController.text.isNotEmpty ? double.parse(_maxController.text) : null,
        multiplier: double.tryParse(_multiplierController.text) ?? 1.0,
        offset: double.tryParse(_offsetController.text) ?? 0.0,
    noiseDeadbandMeters: double.tryParse(_noiseDeadbandController.text.trim()),
  connectedTankCount: int.tryParse(_connectedTanksController.text.trim())?.clamp(1, 1000) ?? 1,
  useCustomFormula: _useCustomFormula,
  customFormula: _customFormulaController.text.trim().isEmpty ? null : _customFormulaController.text.trim(),
  lastWillTopic: _lastWillTopicController.text.trim().isEmpty ? null : _lastWillTopicController.text.trim(),
  payloadIsJson: _payloadIsJson,
  jsonFieldIndex: int.tryParse(_jsonFieldIndexController.text.trim())?.clamp(1, 9999) ?? 1,
  jsonKeyName: _jsonKeyNameController.text.trim().isEmpty ? null : _jsonKeyNameController.text.trim(),
  displayTimeFromJson: _displayTimeFromJson,
  jsonTimeFieldIndex: int.tryParse(_jsonTimeFieldIndexController.text.trim())?.clamp(1, 9999) ?? 1,
  jsonTimeKeyName: _jsonTimeKeyNameController.text.trim().isEmpty ? null : _jsonTimeKeyNameController.text.trim(),
  useControlButton: _useControlButton,
  controlTopic: _controlTopicController.text.trim().isEmpty ? null : _controlTopicController.text.trim(),
  controlMode: _controlMode,
  onValue: _onValueController.text.isEmpty ? 'ON' : _onValueController.text,
  offValue: _offValueController.text.isEmpty ? 'OFF' : _offValueController.text,
  autoControl: _autoControl,
  controlRetained: _controlRetained,
  controlQos: _controlQos,
  graduationSide: _graduationSide,
  scaleMajorTickMeters: double.tryParse(_majorTickController.text.trim())?.clamp(0.01, 1000.0) ?? 0.1,
  scaleMinorDivisions: int.tryParse(_minorDivsController.text.trim())?.clamp(0, 10) ?? 4,
  storeHistory: _storeHistory,
      );
      Navigator.of(context).pop(project);
    }
  }

  void _onTestFormula() {
    setState(() {
      _formulaError = null;
      _formulaPreviewLiters = null;
    });
    final expr = _customFormulaController.text.trim();
    if (expr.isEmpty) {
      setState(() => _formulaError = 'Enter a formula to test');
      return;
    }
    final h = double.tryParse(_testLevelController.text.trim());
    if (h == null) {
      setState(() => _formulaError = 'Enter a valid example level (meters)');
      return;
    }
    try {
      final liters = _evalCustomFormulaLiters(
        expr,
        h: h,
        H: double.tryParse(_heightController.text.trim()) ?? 0.0,
        L: double.tryParse(_lengthController.text.trim()) ?? 0.0,
        W: double.tryParse(_widthController.text.trim()) ?? 0.0,
        D: double.tryParse(_diameterController.text.trim()) ?? 0.0,
        N: double.tryParse(_connectedTanksController.text.trim()) ?? 1.0,
      );
      setState(() => _formulaPreviewLiters = liters);
    } catch (e) {
      setState(() => _formulaError = 'Formula error: ${e.toString()}');
    }
  }

  // Minimal evaluator replicated from main page to test formulas locally
  double _evalCustomFormulaLiters(String expr, {required double h, required double H, required double L, required double W, required double D, required double N}) {
    String s = expr.replaceAll(RegExp(r"\s+"), '');
    final rawTokens = <Map<String, String>>[];
    int p = 0;
    while (p < s.length) {
      final ch = s[p];
      if (ch == '(') { rawTokens.add({'t': 'l', 'v': ch}); p++; continue; }
      if (ch == ')') { rawTokens.add({'t': 'r', 'v': ch}); p++; continue; }
      if ('+-*/'.contains(ch)) { rawTokens.add({'t': 'op', 'v': ch}); p++; continue; }
      if (RegExp(r"[A-Za-z]").hasMatch(ch)) {
        final start = p; p++;
        while (p < s.length && RegExp(r"[A-Za-z]").hasMatch(s[p])) { p++; }
        final name = s.substring(start, p);
        final n = name.toLowerCase();
        double val;
        if (n == 'h' || n == 'level' || n == 'lvl') {
          val = h;
        } else if (n == 'height' || name == 'H') {
          val = H;
        } else if (n == 'l' || n == 'length' || n == 'len') {
          val = L;
        } else if (n == 'w' || n == 'width' || n == 'wid') {
          val = W;
        } else if (n == 'd' || n == 'diameter' || n == 'dia') {
          val = D;
        } else if (n == 'n' || n == 'count' || n == 'tanks') {
          val = N;
        } else {
          throw FormatException('Unknown variable: $name');
        }
        rawTokens.add({'t': 'num', 'v': val.toString()});
        continue;
      }
      if (RegExp(r"[0-9.]").hasMatch(ch)) {
        final start = p; p++;
        while (p < s.length && RegExp(r"[0-9.]").hasMatch(s[p])) { p++; }
        rawTokens.add({'t': 'num', 'v': s.substring(start, p)});
        continue;
      }
      throw FormatException('Unknown character in formula: $ch');
    }
    final withMul = <Map<String, String>>[];
    for (int i2 = 0; i2 < rawTokens.length; i2++) {
      final cur = rawTokens[i2];
      withMul.add(cur);
      if (i2 + 1 < rawTokens.length) {
        final next = rawTokens[i2 + 1];
        final curIsNumOrR = cur['t'] == 'num' || cur['t'] == 'r';
        final nextIsNumOrL = next['t'] == 'num' || next['t'] == 'l';
        if (curIsNumOrR && nextIsNumOrL) {
          withMul.add({'t': 'op', 'v': '*'});
        }
      }
    }
    final tokens = withMul.map<String>((m) => m['v'] as String).toList();
    int i = 0;
    late double Function() parseExpression;
    double parseFactor() {
      if (i >= tokens.length) throw FormatException('Unexpected end');
      final t = tokens[i++];
      if (t == '(') {
        final v = parseExpression();
        if (i >= tokens.length || tokens[i] != ')') throw FormatException('Missing )');
        i++;
        return v;
      }
      if (t == '+') return parseFactor();
      if (t == '-') return -parseFactor();
      return double.parse(t);
    }
    double parseTerm() {
      double x = parseFactor();
      while (i < tokens.length && (tokens[i] == '*' || tokens[i] == '/')) {
        final op = tokens[i++];
        final y = parseFactor();
        x = op == '*' ? x * y : x / y;
      }
      return x;
    }
    parseExpression = () {
      double x = parseTerm();
      while (i < tokens.length && (tokens[i] == '+' || tokens[i] == '-')) {
        final op = tokens[i++];
        final y = parseTerm();
        x = op == '+' ? x + y : x - y;
      }
      return x;
    };
    final v = parseExpression();
    if (i != tokens.length) throw FormatException('Unexpected token: ${tokens[i]}');
    return v;
  }

  // --- AI helper: parse a natural-language description and propose a formula ---
  void _onGenerateAiFormula() {
    setState(() {
      _aiError = null;
      _aiSuggestion = null;
      _aiNote = null;
    });
    final text = _aiDescriptionController.text.trim();
    if (text.isEmpty) {
      setState(() => _aiError = 'Please describe your setup (shape, dimensions, counts).');
      return;
    }
    // Online AI removed; use offline helper only
    // Offline only
    try {
      final res = _generateFormulaFromDescription(text);
      setState(() {
        _aiSuggestion = res.formula;
        _aiNote = res.note;
      });
    } catch (e) {
      setState(() => _aiError = 'Could not generate a formula from the description.');
    }
  }

  // Online AI config helpers removed (no API key in proxy mode)

  void _onApplyAiSuggestion() {
    if (_aiSuggestion == null) return;
    setState(() {
      _useCustomFormula = true;
      _customFormulaController.text = _aiSuggestion!;
      _formulaError = null;
      _formulaPreviewLiters = null;
    });
  }

  _AiResult _generateFormulaFromDescription(String input) {
    // Offline heuristic-based parser to map common descriptions to formulas
    final t = input.toLowerCase();
    const piVal = 3.14159;
  bool mentionsRect = t.contains('rectang') || t.contains('box') || t.contains('square');
  bool mentionsCyl = t.contains('cylind');
  bool mentionsHorizontal = t.contains('horizontal') || t.contains('lying');

    // 0) Handle explicit grouped rectangular specs like:
    //    "4 of them are (h=2.25,L=3,w=1.5), and the 4 other are (h=2.25,L=3,w=1.35)"
    //    We sum base areas (L*W) multiplied by the group counts and produce areaSum*h*1000.
    double areaSumFromGroups = 0.0;
    int totalGroupCount = 0;
    double? firstGroupL, firstGroupW;
    bool groupsHaveDifferentDims = false;
    final parenRe = RegExp(r"\(([^\)]*)\)");
  for (final m in parenRe.allMatches(input)) {
      final start = m.start;
      final inside = m.group(1) ?? '';
      // Find nearest leading integer count within ~20 chars before '('
      int? count;
      final leadStart = (start - 24) < 0 ? 0 : (start - 24);
      final lead = input.substring(leadStart, start);
      final countMatches = RegExp(r"(\d+)").allMatches(lead).toList();
      if (countMatches.isNotEmpty) {
        final cmatch = countMatches.last;
        count = int.tryParse(cmatch.group(1)!);
      }
      count ??= 1;
      // Parse key=value pairs inside the parentheses
      final kvRe = RegExp(r"([a-zA-Z]+)\s*=\s*(\d+(?:\.\d+)?)");
      double? L, W; // we only need base area; 'h' provided in text is the tank height, not used here
      for (final kv in kvRe.allMatches(inside)) {
        final key = kv.group(1)!.toLowerCase();
        final val = double.tryParse(kv.group(2)!);
        if (val == null) continue;
        if (key == 'l' || key == 'len' || key == 'length') L = val;
        if (key == 'w' || key == 'wid' || key == 'width') W = val;
      }
      if (L != null && W != null) {
        areaSumFromGroups += count * L * W;
        totalGroupCount += count;
        if (firstGroupL == null || firstGroupW == null) {
          firstGroupL = L; firstGroupW = W;
        } else {
          if ((L - firstGroupL).abs() > 1e-9 || (W - firstGroupW).abs() > 1e-9) {
            groupsHaveDifferentDims = true;
          }
        }
      }
    }
    if (areaSumFromGroups > 0) {
      if (!groupsHaveDifferentDims && firstGroupL != null && firstGroupW != null) {
        // All groups share the same L/W → can express symbolically
        return _AiResult(
          'N*L*W*h*1000',
          'Detected rectangular groups with the same dimensions (L=$firstGroupL, W=$firstGroupW). Set L/W in the editor and set N to the total count ($totalGroupCount).\nAlternative exact constant-area: ((${areaSumFromGroups.toStringAsFixed(6)})*h*1000).',
        );
      } else {
        // Different dimensions across groups → a single L/W cannot represent both symbolically
        return _AiResult(
          'N*L*W*h*1000',
          'Detected different rectangular dimensions across groups. A single symbolic formula with only L, W, N cannot represent multiple distinct sizes.\nUse the template N*L*W*h*1000 and set L/W to one tank size with N=$totalGroupCount, or use the exact constant-area alternative: ((${areaSumFromGroups.toStringAsFixed(6)})*h*1000).',
        );
      }
    }

    // Extract numbers and dimension pairs like "2m x 1.5m" or "2 by 1.5"
    final rectPairs = <List<double>>[];
    final rectRe = RegExp(r"(\d+(?:\.\d+)?)\s*(?:m|meter|meters|m\.)?\s*(?:x|×|by)\s*(\d+(?:\.\d+)?)", caseSensitive: false);
    for (final m in rectRe.allMatches(input)) {
      final a = double.tryParse(m.group(1)!);
      final b = double.tryParse(m.group(2)!);
      if (a != null && b != null) rectPairs.add([a, b]);
    }

    // Extract diameters like "diameter 0.8m" or "0.8 m diameter"
    final diameters = <double>[];
    final diaRe1 = RegExp(r"diameter\s*(\d+(?:\.\d+)?)", caseSensitive: false);
    final diaRe2 = RegExp(r"(\d+(?:\.\d+)?)\s*(?:m|meter|meters|m\.)?\s*diameter", caseSensitive: false);
    for (final m in diaRe1.allMatches(input)) {
      final d = double.tryParse(m.group(1)!);
      if (d != null) diameters.add(d);
    }
    for (final m in diaRe2.allMatches(input)) {
      final d = double.tryParse(m.group(1)!);
      if (d != null) diameters.add(d);
    }

    // Extract an explicit tank count for possible future use (not currently needed)

    // If we found specific dimensions, we can propose a constant-area formula:
    if (rectPairs.isNotEmpty) {
      // Prefer symbolic template; include constant-area as optional alternative
      double areaSum = 0.0; // m^2
      for (final p in rectPairs) {
        areaSum += p[0] * p[1];
      }
      return _AiResult(
        'N*L*W*h*1000',
        'Detected rectangular dimensions in description. Use L and W from the editor and set N as needed.\nAlternative exact constant-area from provided numbers: ((${areaSum.toStringAsFixed(6)})*h*1000).',
      );
    }

    if (diameters.isNotEmpty) {
      double areaSum = 0.0; // m^2
      for (final d in diameters) {
        areaSum += piVal * (d / 2) * (d / 2);
      }
      final liters = '((${areaSum.toStringAsFixed(6)})*h*1000)';
      final note = mentionsHorizontal
          ? 'Approximating cylinders with vertical assumption. For precise horizontal cylinders, prefer built-in geometry (disable custom formula).'
          : 'Summed circular base areas from description.';
      return _AiResult(liters, note);
    }

    // Otherwise, fall back to variable-based templates using app standards and current tank type hints
    if (mentionsRect) {
      return _AiResult('N*L*W*h*1000', 'Rectangular template using editor dimensions (L, W).');
    }
    if (mentionsCyl && mentionsHorizontal) {
      // Our evaluator cannot express the segment area; advise built-in geometry
      return _AiResult('N*3.14159*(D/2)*(D/2)*h*1000', 'Approximation for horizontal cylinder. For precise results, use built-in geometry (disable custom formula).');
    }
    if (mentionsCyl) {
      return _AiResult('N*3.14159*(D/2)*(D/2)*h*1000', 'Vertical cylinder template using editor diameter (D).');
    }

    // Default based on selected tank type
    switch (_tankType) {
      case TankType.rectangle:
        return _AiResult('N*L*W*h*1000', 'Based on Tank Type = Rectangle.');
      case TankType.verticalCylinder:
        return _AiResult('N*3.14159*(D/2)*(D/2)*h*1000', 'Based on Tank Type = Vertical cylinder.');
      case TankType.horizontalCylinder:
        return _AiResult('N*3.14159*(D/2)*(D/2)*h*1000', 'Approximation for horizontal cylinder. For precise results, use built-in geometry (disable custom formula).');
    }
  }

  @override
  Widget build(BuildContext context) {
    final scheme = Theme.of(context).colorScheme;
    InputDecoration dec(String label, IconData icon, {String? hint}) => InputDecoration(
          labelText: label,
          hintText: hint,
          prefixIcon: Icon(icon),
          filled: true,
          fillColor: scheme.surfaceContainerHighest.withValues(alpha: 0.25),
          border: OutlineInputBorder(borderRadius: BorderRadius.circular(12)),
          enabledBorder: OutlineInputBorder(
            borderRadius: BorderRadius.circular(12),
            borderSide: BorderSide(color: scheme.outlineVariant),
          ),
          focusedBorder: OutlineInputBorder(
            borderRadius: BorderRadius.circular(12),
            borderSide: BorderSide(color: scheme.primary, width: 2),
          ),
          contentPadding: const EdgeInsets.symmetric(horizontal: 12, vertical: 12),
        );

    Widget sectionHeader(String title, IconData icon, Color color) => Container(
          decoration: BoxDecoration(
            color: color.withValues(alpha: 0.12),
            borderRadius: const BorderRadius.vertical(top: Radius.circular(12)),
          ),
          padding: const EdgeInsets.symmetric(horizontal: 12, vertical: 10),
          child: Row(
            children: [
              Container(width: 4, height: 20, decoration: BoxDecoration(color: color, borderRadius: BorderRadius.circular(2))),
              const SizedBox(width: 10),
              Icon(icon, color: color),
              const SizedBox(width: 8),
              Text(title, style: TextStyle(fontWeight: FontWeight.w600, color: color)),
            ],
          ),
        );

    return Scaffold(
      appBar: AppBar(
        backgroundColor: Theme.of(context).colorScheme.primary,
        foregroundColor: Theme.of(context).colorScheme.onPrimary,
        title: Text(
          widget.project == null ? 'Add Project' : 'Edit Project',
          style: GoogleFonts.poppins(fontWeight: FontWeight.w700, letterSpacing: 0.5),
        ),
        actions: [
          IconButton(
            icon: const Icon(Icons.save),
            onPressed: _saveProject,
          ),
        ],
      ),
      body: SingleChildScrollView(
        padding: const EdgeInsets.all(16.0),
        child: Form(
          key: _formKey,
          child: Column(
            crossAxisAlignment: CrossAxisAlignment.start,
            children: [
              TextFormField(
                controller: _nameController,
                decoration: const InputDecoration(labelText: 'Project Name'),
                validator: (value) => value!.isEmpty ? 'Please enter a name' : null,
              ),
              const SizedBox(height: 16),
              // MQTT Section (polished)
              Card(
                shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(12)),
                elevation: 1,
                clipBehavior: Clip.antiAlias,
                child: Column(
                  children: [
                    sectionHeader('MQTT Connection', Icons.link, scheme.primary),
                    Padding(
                      padding: const EdgeInsets.all(12.0),
                      child: Column(
                        children: [
                          TextFormField(
                            controller: _brokerController,
                            decoration: dec('MQTT Broker', Icons.dns, hint: 'e.g. test.mosquitto.org'),
                            validator: (value) => value!.isEmpty ? 'Please enter a broker' : null,
                          ),
                          const SizedBox(height: 12),
                          Row(children: [
                            Expanded(
                              child: TextFormField(
                                controller: _portController,
                                decoration: dec('Port', Icons.numbers, hint: '1883'),
                                keyboardType: TextInputType.number,
                                validator: (value) => value!.isEmpty || int.tryParse(value) == null ? 'Enter a valid port' : null,
                              ),
                            ),
                            const SizedBox(width: 12),
                            Expanded(
                              flex: 2,
                              child: TextFormField(
                                controller: _topicController,
                                decoration: dec('Subscribe Topic', Icons.topic, hint: 'e.g. tank/level'),
                                validator: (value) => value!.isEmpty ? 'Please enter a topic' : null,
                              ),
                            ),
                          ]),
                          const SizedBox(height: 12),
                          Row(children: [
                            Expanded(
                              child: TextFormField(
                                controller: _usernameController,
                                decoration: dec('Username (optional)', Icons.person),
                              ),
                            ),
                            const SizedBox(width: 12),
                            Expanded(
                              child: TextFormField(
                                controller: _passwordController,
                                decoration: dec('Password (optional)', Icons.lock),
                                obscureText: true,
                              ),
                            ),
                          ]),
                          const SizedBox(height: 12),
                          // Payload parsing options
                          CheckboxListTile(
                            contentPadding: EdgeInsets.zero,
                            controlAffinity: ListTileControlAffinity.leading,
                            title: const Text('Payload is JSON'),
                            subtitle: const Text('Extract numeric value from JSON by field order'),
                            value: _payloadIsJson,
                            onChanged: (v) => setState(() => _payloadIsJson = v ?? false),
                          ),
                          if (_payloadIsJson) ...[
                            const SizedBox(height: 8),
                            TextFormField(
                              controller: _jsonFieldIndexController,
                              decoration: dec('JSON field order (1 = first)', Icons.filter_1),
                              keyboardType: TextInputType.number,
                              validator: (value) {
                                if (!_payloadIsJson) return null;
                                final n = int.tryParse(value ?? '');
                                if (n == null || n <= 0) return 'Enter a positive integer';
                                return null;
                              },
                            ),
                            const SizedBox(height: 8),
                            TextFormField(
                              controller: _jsonKeyNameController,
                              decoration: dec('JSON key name (optional)', Icons.key),
                            ),
                            const Divider(height: 20),
                            SwitchListTile.adaptive(
                              contentPadding: EdgeInsets.zero,
                              title: const Text('Display time from JSON'),
                              subtitle: const Text('Show last update time parsed from the payload'),
                              value: _displayTimeFromJson,
                              onChanged: (v) => setState(() => _displayTimeFromJson = v),
                            ),
                            if (_displayTimeFromJson) ...[
                              const SizedBox(height: 8),
                              TextFormField(
                                controller: _jsonTimeFieldIndexController,
                                decoration: dec('Time field order (1 = first)', Icons.timer_outlined),
                                keyboardType: TextInputType.number,
                                validator: (value) {
                                  if (!_payloadIsJson || !_displayTimeFromJson) return null;
                                  final hasKey = _jsonTimeKeyNameController.text.trim().isNotEmpty;
                                  // Allow empty when key provided
                                  if (hasKey && (value == null || value.trim().isEmpty)) return null;
                                  final n = int.tryParse(value ?? '');
                                  if (n == null || n <= 0) return 'Enter a positive integer (or fill key name instead)';
                                  return null;
                                },
                              ),
                              const SizedBox(height: 8),
                              TextFormField(
                                controller: _jsonTimeKeyNameController,
                                decoration: dec('Time key name (optional, enter one of order or key)', Icons.key_outlined),
                                validator: (value) {
                                  if (!_payloadIsJson || !_displayTimeFromJson) return null;
                                  final hasOrder = int.tryParse(_jsonTimeFieldIndexController.text.trim()) != null;
                                  final hasKey = (value ?? '').trim().isNotEmpty;
                                  if (!hasOrder && !hasKey) return 'Enter either a time field order or a key name';
                                  return null;
                                },
                              ),
                            ],
                          ],
                          const SizedBox(height: 12),
                          TextFormField(
                            controller: _lastWillTopicController,
                            decoration: dec('Presence / Last Will Topic (optional)', Icons.personal_injury, hint: 'e.g. devices/sn/lastwill'),
                          ),
                          const SizedBox(height: 4),
                          Align(
                            alignment: Alignment.centerLeft,
                            child: Text('Tip: Leave username/password empty if your broker doesn\'t require auth.',
                                style: Theme.of(context).textTheme.bodySmall?.copyWith(color: scheme.onSurfaceVariant)),
                          ),
                        ],
                      ),
                    ),
                  ],
                ),
              ),
              const SizedBox(height: 16),
              // Value Correction (polished)
              Card(
                shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(12)),
                elevation: 1,
                clipBehavior: Clip.antiAlias,
                child: Column(
                  children: [
                    sectionHeader('Value Correction', Icons.tune, scheme.tertiary),
                    Padding(
                      padding: const EdgeInsets.all(12.0),
                      child: Column(
                        children: [
                          TextFormField(
                            controller: _multiplierController,
                            decoration: dec('Multiplier', Icons.calculate, hint: 'new = value * multiplier + offset'),
                            keyboardType: TextInputType.number,
                          ),
                          const SizedBox(height: 12),
                          TextFormField(
                            controller: _offsetController,
                            decoration: dec('Offset', Icons.exposure),
                            keyboardType: TextInputType.number,
                          ),
                          const SizedBox(height: 12),
                          TextFormField(
                            controller: _noiseDeadbandController,
                            decoration: dec('Noise deadband (m)', Icons.noise_aware, hint: 'Default 0.003 (3 mm)'),
                            keyboardType: TextInputType.number,
                            validator: (value) {
                              if (value == null || value.trim().isEmpty) return null; // allow empty → backend default
                              final d = double.tryParse(value.trim());
                              if (d == null || d < 0) return 'Enter a number >= 0 (meters)';
                              if (d > 1.0) return 'Too large; use meters (e.g., 0.003 = 3mm)';
                              return null;
                            },
                          ),
                          const SizedBox(height: 12),
                          TextFormField(
                            controller: _connectedTanksController,
                            decoration: dec('Connected tanks count', Icons.storage, hint: '1 = single tank'),
                            keyboardType: TextInputType.number,
                            validator: (v) {
                              if (v == null || v.trim().isEmpty) return 'Enter a number';
                              final n = int.tryParse(v.trim());
                              if (n == null || n < 1) return 'Must be >= 1';
                              if (n > 1000) return 'Too large';
                              return null;
                            },
                          ),
                        ],
                      ),
                    ),
                  ],
                ),
              ),
              const SizedBox(height: 16),
              // Custom Formula
              Card(
                shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(12)),
                elevation: 1,
                clipBehavior: Clip.antiAlias,
                child: Column(children: [
                  sectionHeader('Custom Liters Formula', Icons.functions, scheme.secondary),
                  Padding(
                    padding: const EdgeInsets.all(12.0),
                    child: Column(crossAxisAlignment: CrossAxisAlignment.start, children: [
                      SwitchListTile.adaptive(
                        contentPadding: EdgeInsets.zero,
                        title: const Text('Use custom formula'),
                        subtitle: const Text('Compute liters using your own expression'),
                        value: _useCustomFormula,
                        onChanged: (v) => setState(() => _useCustomFormula = v),
                      ),
                      if (_useCustomFormula) ...[
                        const SizedBox(height: 8),
                        TextFormField(
                          controller: _customFormulaController,
                          decoration: dec('Formula (liters)', Icons.calculate, hint: 'e.g. 4*H*L*(W+1.25)'),
                          maxLines: 2,
                          validator: (v) {
                            if (!_useCustomFormula) return null;
                            if (v == null || v.trim().isEmpty) return 'Enter a formula or disable this option';
                            return null;
                          },
                        ),
                        const SizedBox(height: 8),
                        Text('Variables: h=current level (m), H=height (m), L=length (m), W=width (m), D=diameter (m), N=connected tanks count',
                            style: Theme.of(context).textTheme.bodySmall),
                        const SizedBox(height: 4),
                        Text('Tip: Use parentheses and * for multiplication. Result must be liters.',
                            style: Theme.of(context).textTheme.bodySmall?.copyWith(color: scheme.onSurfaceVariant)),

                        const Divider(height: 24),
                        Text('Test formula', style: Theme.of(context).textTheme.titleSmall),
                        const SizedBox(height: 8),
                        Row(children: [
                          Expanded(
                            child: TextFormField(
                              controller: _testLevelController,
                              decoration: dec('Example level h (m)', Icons.straighten),
                              keyboardType: TextInputType.number,
                            ),
                          ),
                          const SizedBox(width: 10),
                          ElevatedButton.icon(
                            onPressed: _onTestFormula,
                            icon: const Icon(Icons.play_arrow),
                            label: const Text('Run'),
                          ),
                        ]),
                        const SizedBox(height: 8),
                        if (_formulaError != null)
                          Text(_formulaError!, style: TextStyle(color: Theme.of(context).colorScheme.error)),
                        if (_formulaPreviewLiters != null && _formulaError == null)
                          Text('Result: ${_formulaPreviewLiters!.toStringAsFixed(2)} L',
                              style: Theme.of(context).textTheme.bodyMedium?.copyWith(fontWeight: FontWeight.w600)),

                        const Divider(height: 28),
                        Text('AI helper (describe your setup)', style: Theme.of(context).textTheme.titleSmall),
                        const SizedBox(height: 8),
                        // Freeform description
                        // Freeform description
                        TextFormField(
                          controller: _aiDescriptionController,
                          decoration: dec('Describe tank(s) and dimensions', Icons.chat_bubble_outline,
                              hint: 'e.g., Two vertical cylindrical tanks, diameter 1.2m each; rectangular tank 2m by 1m'),
                          maxLines: 3,
                        ),
                        const SizedBox(height: 8),
                        Wrap(
                          spacing: 12,
                          runSpacing: 8,
                          children: [
                            ElevatedButton.icon(
                              onPressed: _aiBusy ? null : _onGenerateAiFormula,
                              icon: _aiBusy
                                  ? const SizedBox(width: 16, height: 16, child: CircularProgressIndicator(strokeWidth: 2))
                                  : const Icon(Icons.auto_fix_high),
                              label: Text(_aiBusy ? 'Generating…' : 'Generate formula'),
                            ),
                            if (_aiSuggestion != null)
                              OutlinedButton.icon(
                                onPressed: _onApplyAiSuggestion,
                                icon: const Icon(Icons.check),
                                label: const Text('Use suggestion'),
                              ),
                          ],
                        ),
                        const SizedBox(height: 8),
                        if (_aiError != null)
                          Text(_aiError!, style: TextStyle(color: Theme.of(context).colorScheme.error)),
                        if (_aiSuggestion != null)
                          Column(crossAxisAlignment: CrossAxisAlignment.start, children: [
                            Text('Suggestion:', style: Theme.of(context).textTheme.labelMedium),
                            const SizedBox(height: 4),
                            SelectableText(_aiSuggestion!, style: Theme.of(context).textTheme.bodyMedium),
                            if (_aiNote != null) ...[
                              const SizedBox(height: 6),
                              Text(_aiNote!, style: Theme.of(context).textTheme.bodySmall?.copyWith(color: scheme.onSurfaceVariant)),
                            ]
                          ]),
                      ],
                    ]),
                  ),
                ]),
              ),
              // Control Button (polished)
              Card(
                shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(12)),
                elevation: 1,
                clipBehavior: Clip.antiAlias,
                child: Column(
                  children: [
                    sectionHeader('Control Button', Icons.power_settings_new, Theme.of(context).colorScheme.primary),
                    Padding(
                      padding: const EdgeInsets.all(12.0),
                      child: Column(
                        children: [
                          SwitchListTile.adaptive(
                            title: const Text('Enable dashboard control button'),
                            secondary: const Icon(Icons.toggle_on),
                            value: _useControlButton,
                            onChanged: (v) => setState(() => _useControlButton = v),
                            contentPadding: EdgeInsets.zero,
                          ),
                          if (_useControlButton) ...[
                            TextFormField(
                              controller: _controlTopicController,
                              decoration: dec('Publish Topic', Icons.publish),
                              validator: (value) {
                                if (_useControlButton) {
                                  if (value == null || value.trim().isEmpty) return 'Please enter a publish topic';
                                }
                                return null;
                              },
                            ),
                            const SizedBox(height: 12),
                            SizedBox(
                              width: double.infinity,
                              child: DropdownButtonFormField<ControlMode>(
                                isExpanded: true,
                                initialValue: _controlMode,
                                decoration: dec('Mode', Icons.tune),
                                items: const [
                                  DropdownMenuItem(value: ControlMode.onOff, child: Text('On/Off')),
                                  DropdownMenuItem(value: ControlMode.toggle, child: Text('Toggle')),
                                ],
                                onChanged: (v) => setState(() => _controlMode = v ?? ControlMode.toggle),
                              ),
                            ),
                            const SizedBox(height: 12),
                            Row(children: [
                              Expanded(
                                child: TextFormField(
                                  controller: _onValueController,
                                  decoration: dec('On value', Icons.toggle_on),
                                ),
                              ),
                              const SizedBox(width: 12),
                              Expanded(
                                child: TextFormField(
                                  controller: _offValueController,
                                  decoration: dec('Off value', Icons.toggle_off),
                                ),
                              ),
                            ]),
                            const SizedBox(height: 12),
                            SizedBox(
                              width: double.infinity,
                              child: DropdownButtonFormField<MqttQosLevel>(
                                isExpanded: true,
                                initialValue: _controlQos,
                                decoration: dec('QoS', Icons.network_check),
                                items: const [
                                  DropdownMenuItem(value: MqttQosLevel.atMostOnce, child: Text('At most once (0)')),
                                  DropdownMenuItem(value: MqttQosLevel.atLeastOnce, child: Text('At least once (1)')),
                                  DropdownMenuItem(value: MqttQosLevel.exactlyOnce, child: Text('Exactly once (2)')),
                                ],
                                onChanged: (v) => setState(() => _controlQos = v ?? MqttQosLevel.atLeastOnce),
                              ),
                            ),
                            const SizedBox(height: 8),
                            CheckboxListTile(
                              contentPadding: EdgeInsets.zero,
                              title: const Text('Retained'),
                              subtitle: const Text('Keep last state on broker'),
                              value: _controlRetained,
                              onChanged: (v) => setState(() => _controlRetained = v ?? false),
                              controlAffinity: ListTileControlAffinity.leading,
                            ),
                            const SizedBox(height: 8),
                            CheckboxListTile(
                              title: const Text('Automatic (use min/max thresholds to control)'),
                              subtitle: const Text('On when below min; Off when above max'),
                              value: _autoControl,
                              onChanged: (v) => setState(() => _autoControl = v ?? false),
                              controlAffinity: ListTileControlAffinity.leading,
                              contentPadding: EdgeInsets.zero,
                            ),
                            Align(
                              alignment: Alignment.centerLeft,
                              child: Text(
                                'Will publish JSON: {"value": ON/OFF, "timestamp": ISO8601}',
                                style: Theme.of(context).textTheme.bodySmall?.copyWith(color: Theme.of(context).colorScheme.onSurfaceVariant),
                              ),
                            ),
                          ],
                        ],
                      ),
                    ),
                  ],
                ),
              ),
              const SizedBox(height: 16),
              // Tank & Sensor (polished)
              Card(
                shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(12)),
                elevation: 1,
                clipBehavior: Clip.antiAlias,
                child: Column(
                  children: [
                    sectionHeader('Tank & Sensor', Icons.opacity, scheme.secondary),
                    Padding(
                      padding: const EdgeInsets.all(12.0),
                      child: Column(
                        children: [
                          DropdownButtonFormField<SensorType>(
                            initialValue: _sensorType,
                            decoration: dec('Sensor Type', Icons.sensors),
                            items: SensorType.values.map((SensorType type) {
                              return DropdownMenuItem<SensorType>(
                                value: type,
                                child: Text(type.toString().split('.').last),
                              );
                            }).toList(),
                            onChanged: (SensorType? newValue) {
                              setState(() {
                                _sensorType = newValue!;
                              });
                            },
                          ),
                          const SizedBox(height: 12),
                          DropdownButtonFormField<TankType>(
                            initialValue: _tankType,
                            decoration: dec('Tank Type', Icons.inventory_2),
                            items: TankType.values.map((TankType type) {
                              return DropdownMenuItem<TankType>(
                                value: type,
                                child: Text(type.toString().split('.').last),
                              );
                            }).toList(),
                            onChanged: (TankType? newValue) {
                              setState(() {
                                _tankType = newValue!;
                              });
                            },
                          ),
                          const SizedBox(height: 12),
                          if (_tankType == TankType.verticalCylinder || _tankType == TankType.rectangle)
                            TextFormField(
                              controller: _heightController,
                              decoration: dec('Height (m)', Icons.height),
                              keyboardType: TextInputType.number,
                              validator: (value) => value!.isEmpty || double.tryParse(value) == null ? 'Please enter a valid height' : null,
                            ),
                          if (_tankType == TankType.verticalCylinder || _tankType == TankType.horizontalCylinder) ...[
                            if (_tankType == TankType.verticalCylinder || _tankType == TankType.horizontalCylinder)
                              const SizedBox(height: 12),
                            TextFormField(
                              controller: _diameterController,
                              decoration: dec('Diameter (m)', Icons.circle_outlined),
                              keyboardType: TextInputType.number,
                              validator: (value) => value!.isEmpty || double.tryParse(value) == null ? 'Please enter a valid diameter' : null,
                            ),
                          ],
                          if (_tankType == TankType.horizontalCylinder || _tankType == TankType.rectangle) ...[
                            const SizedBox(height: 12),
                            TextFormField(
                              controller: _lengthController,
                              decoration: dec('Length (m)', Icons.swap_horiz),
                              keyboardType: TextInputType.number,
                              validator: (value) => value!.isEmpty || double.tryParse(value) == null ? 'Please enter a valid length' : null,
                            ),
                          ],
                          if (_tankType == TankType.rectangle) ...[
                            const SizedBox(height: 12),
                            TextFormField(
                              controller: _widthController,
                              decoration: dec('Width (m)', Icons.swap_horiz),
                              keyboardType: TextInputType.number,
                              validator: (value) => value!.isEmpty || double.tryParse(value) == null ? 'Please enter a valid width' : null,
                            ),
                          ],
                          const SizedBox(height: 12),
                          TextFormField(
                            controller: _thicknessController,
                            decoration: dec('Wall thickness (mm)', Icons.straighten, hint: '0 for negligible'),
                            keyboardType: TextInputType.number,
                            validator: (value) {
                              if (value == null || value.isEmpty) return null;
                              final t = double.tryParse(value);
                              if (t == null || t < 0) return 'Must be >= 0';
                              return null;
                            },
                          ),
                          const SizedBox(height: 12),
                          TextFormField(
                            controller: _minController,
                            decoration: dec('Min Threshold (m) (optional)', Icons.arrow_downward),
                            keyboardType: TextInputType.number,
                          ),
                          const SizedBox(height: 12),
                          TextFormField(
                            controller: _maxController,
                            decoration: dec('Max Threshold (m) (optional)', Icons.arrow_upward),
                            keyboardType: TextInputType.number,
                          ),
                          const SizedBox(height: 16),
                          // Graduation/Scale configuration
                          Align(
                            alignment: Alignment.centerLeft,
                            child: Text('Graduation & Scale', style: Theme.of(context).textTheme.titleSmall),
                          ),
                          const SizedBox(height: 8),
                          Row(children: [
                            Expanded(
                              child: DropdownButtonFormField<GraduationSide>(
                                isExpanded: true,
                                initialValue: _graduationSide,
                                decoration: dec('Graduation side', Icons.swap_horiz),
                                items: const [
                                  DropdownMenuItem(value: GraduationSide.left, child: Text('Left')),
                                  DropdownMenuItem(value: GraduationSide.right, child: Text('Right')),
                                ],
                                onChanged: (v) => setState(() => _graduationSide = v ?? GraduationSide.left),
                              ),
                            ),
                            const SizedBox(width: 12),
                            Expanded(
                              child: TextFormField(
                                controller: _majorTickController,
                                decoration: dec('Major tick (m)', Icons.stacked_line_chart, hint: 'e.g. 0.1'),
                                keyboardType: TextInputType.number,
                                validator: (v) {
                                  final d = double.tryParse((v ?? '').trim());
                                  if (d == null || d <= 0) return 'Enter > 0';
                                  return null;
                                },
                              ),
                            ),
                          ]),
                          const SizedBox(height: 8),
                          TextFormField(
                            controller: _minorDivsController,
                            decoration: dec('Minor divisions between majors', Icons.grid_on, hint: '0 for none'),
                            keyboardType: TextInputType.number,
                            validator: (v) {
                              final n = int.tryParse((v ?? '').trim());
                              if (n == null || n < 0) return 'Enter 0 or more';
                              if (n > 10) return 'Too many (<=10)';
                              return null;
                            },
                          ),
                          const SizedBox(height: 12),
                          // Store history toggle
                          SwitchListTile.adaptive(
                            contentPadding: EdgeInsets.zero,
                            title: const Text('Store history to DB'),
                            subtitle: const Text('When ON, readings will be sent to the backend for charts'),
                            value: _storeHistory,
                            onChanged: (v) => setState(() => _storeHistory = v),
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
      ),
    );
  }
}
