// main.dart
import 'dart:async';
import 'dart:math';
import 'package:flutter/material.dart';
import 'package:provider/provider.dart';
import 'package:shared_preferences/shared_preferences.dart';
import 'package:flutter/services.dart';
import 'package:flutter_local_notifications/flutter_local_notifications.dart';
import 'tank_widget.dart';
import 'theme_provider.dart';
import 'types.dart';
import 'mqtt_service.dart';
import 'landing_page.dart';
import 'project_list_page.dart';

// Local notifications plugin instance
final FlutterLocalNotificationsPlugin flutterLocalNotificationsPlugin = FlutterLocalNotificationsPlugin();

Future<void> initializeLocalNotifications() async {
  const AndroidInitializationSettings initializationSettingsAndroid =
      AndroidInitializationSettings('@mipmap/ic_launcher');
  const InitializationSettings initializationSettings = InitializationSettings(
    android: initializationSettingsAndroid,
  );
  await flutterLocalNotificationsPlugin.initialize(initializationSettings);
}

Future<void> showLocalNotification({
  required String title,
  required String body,
}) async {
  const AndroidNotificationDetails androidPlatformChannelSpecifics = AndroidNotificationDetails(
    'default_channel',
    'Default',
    channelDescription: 'Default channel for notifications',
    importance: Importance.max,
    priority: Priority.high,
    showWhen: true,
  );
  const NotificationDetails platformChannelSpecifics = NotificationDetails(
    android: androidPlatformChannelSpecifics,
  );
  await flutterLocalNotificationsPlugin.show(
    0,
    title,
    body,
    platformChannelSpecifics,
  );
}

// Feature flag: set to true to start the native Android foreground service.
// Set to false to disable native service startup (useful for debugging crashes).
const bool enableNativeForegroundService = false;

void main() async {
  WidgetsFlutterBinding.ensureInitialized();
  await initializeLocalNotifications();
  runApp(
    ChangeNotifierProvider(
      create: (_) => ThemeProvider(),
      child: const TankApp(),
    ),
  );
}

class TankApp extends StatelessWidget {
  const TankApp({super.key});

  @override
  Widget build(BuildContext context) {
    final themeProvider = Provider.of<ThemeProvider>(context);
    return MaterialApp(
      title: 'Tank Monitor',
      theme: ThemeData(
        brightness: Brightness.light,
        primarySwatch: Colors.blue,
        useMaterial3: true,
      ),
      darkTheme: ThemeData(
        brightness: Brightness.dark,
        primarySwatch: Colors.blue,
        useMaterial3: true,
      ),
      themeMode: themeProvider.themeMode,
      home: const LandingPage(),
    );
  }
}

class DebugPage extends StatefulWidget {
  const DebugPage({super.key});

  @override
  State<DebugPage> createState() => _DebugPageState();
}

class _DebugPageState extends State<DebugPage> {
  String _bridgeUrl = '';
  final _bridgeController = TextEditingController();
  final MethodChannel _ch = const MethodChannel('app.settings.channel');

  @override
  void initState() {
    super.initState();
    _refresh();
  }

  @override
  void dispose() {
    _bridgeController.dispose();
    super.dispose();
  }

  Future<void> _refresh() async {
    // Only load saved bridge URL in local-only mode
    try {
      final prefs = await SharedPreferences.getInstance();
      final saved = prefs.getString('bridgeUrl') ?? '';
      setState(() {
        _bridgeUrl = saved;
        if (saved.isNotEmpty) _bridgeController.text = saved;
      });
    } catch (_) {}
  }

  Future<void> _openSettings() async {
    try {
      await _ch.invokeMethod('openAppNotificationSettings');
    } catch (e) {
      debugPrint('open settings failed: $e');
    }
  }

  Future<void> _postTestNotification() async {
    try {
      await showLocalNotification(title: 'Test', body: 'Local test notification');
    } catch (e) {
      debugPrint('post notification failed: $e');
    }
  }

  Future<void> _checkEnabled() async {
    try {
      final enabled = await _ch.invokeMethod('areNotificationsEnabled');
      ScaffoldMessenger.of(context).showSnackBar(SnackBar(content: Text('Notifications enabled: $enabled')));
    } catch (e) {
      debugPrint('check enabled failed: $e');
    }
  }

  @override
  Widget build(BuildContext context) {
    return Scaffold(
      appBar: AppBar(
        title: Row(children: [
          SizedBox(
            width: 36,
            height: 36,
            child: Image.asset('assets/logo.png', fit: BoxFit.contain),
          ),
          const SizedBox(width: 12),
          const Text('Debug')
        ]),
      ),
      body: Padding(
        padding: const EdgeInsets.all(12),
        child: SingleChildScrollView(
          child: Column(crossAxisAlignment: CrossAxisAlignment.start, children: [
            Card(
              elevation: 2,
              child: Padding(
                padding: const EdgeInsets.all(12),
                child: Column(crossAxisAlignment: CrossAxisAlignment.start, children: [
                  Text('Firebase removed; app uses local notifications only', style: const TextStyle(fontWeight: FontWeight.w600)),
                  const SizedBox(height: 8),
                  Row(children: [
                    ElevatedButton(onPressed: _refresh, child: const Text('Refresh')),
                    const SizedBox(width: 8),
                    ElevatedButton(onPressed: _checkEnabled, child: const Text('Check Notification')),
                  ])
                ]),
              ),
            ),
            const SizedBox(height: 12),
            Card(
              elevation: 1,
              child: Padding(
                padding: const EdgeInsets.all(12),
                child: Column(crossAxisAlignment: CrossAxisAlignment.start, children: [
                  Text('Bridge URL', style: const TextStyle(fontWeight: FontWeight.w600)),
                  const SizedBox(height: 8),
                  Text('Current: ${_bridgeUrl.isEmpty ? '(not set - emulator default used)' : _bridgeUrl}'),
                  const SizedBox(height: 8),
                  TextField(
                    controller: _bridgeController,
                    decoration: const InputDecoration(labelText: 'Bridge URL (https://...)'),
                    keyboardType: TextInputType.url,
                  ),
                  const SizedBox(height: 8),
                  Row(children: [
                    ElevatedButton(onPressed: () async {
                      final v = _bridgeController.text.trim();
                      final prefs = await SharedPreferences.getInstance();
                      await prefs.setString('bridgeUrl', v);
                      setState(() { _bridgeUrl = v; });
                      ScaffoldMessenger.of(context).showSnackBar(const SnackBar(content: Text('Bridge URL saved')));
                    }, child: const Text('Save')),
                    const SizedBox(width: 8),
                    ElevatedButton(onPressed: () async {
                      // Bridge/FCM removed — inform user to use local notifications only
                      ScaffoldMessenger.of(context).showSnackBar(const SnackBar(content: Text('Bridge/FCM disabled — local notifications only')));
                    }, child: const Text('Register Now (disabled)')),
                  ])
                ]),
              ),
            ),
            const SizedBox(height: 12),
            Row(children: [
              ElevatedButton(onPressed: _openSettings, child: const Text('Open App Notification Settings')),
              const SizedBox(width: 8),
              ElevatedButton(onPressed: _postTestNotification, child: const Text('Post Local Notification')),
            ])
          ]),
        ),
      ),
    );
  }
}


/// Page 1: Enter broker/topic
class MqttTopicPage extends StatefulWidget {
  const MqttTopicPage({super.key});
  @override
  State<MqttTopicPage> createState() => _MqttTopicPageState();
}

class _MqttTopicPageState extends State<MqttTopicPage> {
  final _brokerController = TextEditingController(text: 'test.mosquitto.org');
  final _portController = TextEditingController(text: '1883');
  final _topicController = TextEditingController(text: 'tank/level');
  final _usernameController = TextEditingController();
  final _passwordController = TextEditingController();
  final bool _connecting = false;

  void _submit() {
    final broker = _brokerController.text.trim();
    final port = int.tryParse(_portController.text.trim()) ?? 1883;
    final topic = _topicController.text.trim();
    final username = _usernameController.text;
    final password = _passwordController.text;

    if (broker.isEmpty || topic.isEmpty) {
      ScaffoldMessenger.of(context)
          .showSnackBar(const SnackBar(content: Text('Please enter broker and topic')));
      return;
    }

    // save broker/topic now so it persists if user quits before finishing setup
    SharedPreferences.getInstance().then((prefs) {
      prefs.setString('broker', broker);
      prefs.setInt('port', port);
      prefs.setString('topic', topic);
      if (username.trim().isNotEmpty) prefs.setString('username', username);
      if (password.trim().isNotEmpty) prefs.setString('password', password);
    });

    Navigator.push(
      context,
      MaterialPageRoute(
        builder: (_) => SensorTankSetupPage(
            broker: broker,
            port: port,
            topic: topic,
            username: username,
            password: password),
      ),
    );
  }

  @override
  void dispose() {
    _brokerController.dispose();
    _portController.dispose();
    _topicController.dispose();
    _usernameController.dispose();
    _passwordController.dispose();
    super.dispose();
  }

  @override
  Widget build(BuildContext context) {
    return Scaffold(
        appBar: AppBar(title: const Text('MQTT - Topic'), actions: [
          IconButton(
            icon: const Icon(Icons.bug_report),
            tooltip: 'Debug',
            onPressed: () {
              Navigator.push(context, MaterialPageRoute(builder: (_) => const DebugPage()));
            },
          )
        ]),
        body: SafeArea(
          child: Padding(
            padding: const EdgeInsets.fromLTRB(16, 16, 16, 32), // extra bottom padding
            child: SingleChildScrollView(
              child: Column(
                crossAxisAlignment: CrossAxisAlignment.stretch,
                children: [
                  TextField(
                    controller: _brokerController,
                    decoration: const InputDecoration(labelText: 'MQTT Broker'),
                  ),
                  TextField(
                    controller: _portController,
                    decoration: const InputDecoration(labelText: 'Port'),
                    keyboardType: TextInputType.number,
                  ),
                  TextField(
                    controller: _topicController,
                    decoration: const InputDecoration(labelText: 'Topic (to subscribe)'),
                  ),
                  const SizedBox(height: 8),
                  TextField(
                    controller: _usernameController,
                    decoration: const InputDecoration(
                        labelText: 'Username (optional)', hintText: 'Leave blank if not needed'),
                  ),
                  TextField(
                    controller: _passwordController,
                    decoration: const InputDecoration(
                        labelText: 'Password (optional)', hintText: 'Leave blank if not needed'),
                    obscureText: true,
                  ),
                  const SizedBox(height: 20),
                  ElevatedButton(
                      onPressed: _connecting ? null : _submit,
                      child: const Text('Submit & Next')),
                  const SizedBox(height: 12),
                  const Text('Default broker is test.mosquitto.org:1883 (public test broker)'),
                ],
              ),
            ),
          ),
        ));
  }
}

/// Page 2: Choose sensor type and tank type and dimensions
class SensorTankSetupPage extends StatefulWidget {
  final String broker;
  final int port;
  final String topic;
  final String? username;
  final String? password;
  const SensorTankSetupPage({
    super.key,
    required this.broker,
    required this.port,
    required this.topic,
    this.username,
    this.password,
  });

  @override
  State<SensorTankSetupPage> createState() => _SensorTankSetupPageState();
}

class _SensorTankSetupPageState extends State<SensorTankSetupPage> {
  SensorType _sensorType = SensorType.submersible;
  TankType _tankType = TankType.verticalCylinder;

  // Controllers for dimensions (all meters)
  final _heightController = TextEditingController(text: '1.0'); // vertical / rectangle height
  final _diameterController = TextEditingController(text: '0.4'); // cylinder diameter
  final _lengthController = TextEditingController(text: '1.0'); // cylinder length or rectangle length
  final _widthController = TextEditingController(text: '0.5'); // rectangle width
  final _minController = TextEditingController();
  final _maxController = TextEditingController();

  Future<void> _goToMain() async {
    final height = double.tryParse(_heightController.text) ?? 0.0;
    final diameter = double.tryParse(_diameterController.text) ?? 0.0;
    final length = double.tryParse(_lengthController.text) ?? 0.0;
    final width = double.tryParse(_widthController.text) ?? 0.0;

  if ((_tankType == TankType.verticalCylinder && (height <= 0 || diameter <= 0)) ||
      (_tankType == TankType.horizontalCylinder && (diameter <= 0 || length <= 0)) ||
      (_tankType == TankType.rectangle && (length <= 0 || width <= 0 || height <= 0))) {
    ScaffoldMessenger.of(context)
        .showSnackBar(const SnackBar(content: Text('Please enter valid positive dimensions')));
    return;
  }

  final minThr = double.tryParse(_minController.text);
  final maxThr = double.tryParse(_maxController.text);

    // persist full settings
    final prefs = await SharedPreferences.getInstance();
    await prefs.setString('sensor', _sensorType.toString());
    await prefs.setString('tank', _tankType.toString());
    await prefs.setDouble('height', height);
    await prefs.setDouble('diameter', diameter);
    await prefs.setDouble('length', length);
    await prefs.setDouble('width', width);
    if (minThr != null) await prefs.setDouble('minThreshold', minThr);
    if (maxThr != null) await prefs.setDouble('maxThreshold', maxThr);

  // Bridge/FCM removed: skip remote registration in local-only mode
  debugPrint('Skipping bridge registration (local notifications only)');

    // Navigate to main page and pass thresholds
    if (!mounted) return;
    Navigator.pushReplacement(
      context,
      MaterialPageRoute(
        builder: (_) => MainTankPage(
          broker: widget.broker,
          port: widget.port,
          topic: widget.topic,
          sensorType: _sensorType,
          tankType: _tankType,
          height: height,
          diameter: diameter,
          length: length,
          width: width,
          username: widget.username,
          password: widget.password,
          minThreshold: minThr,
          maxThreshold: maxThr,
          projectName: widget.topic, // fallback to topic as name if not available
        ),
      ),
    );
}

  Widget _tankDimensionForm() {
    switch (_tankType) {
      case TankType.verticalCylinder:
        return Column(
          children: [
            TextField(
              controller: _diameterController,
              keyboardType: TextInputType.numberWithOptions(decimal: true),
              decoration: const InputDecoration(labelText: 'Diameter (m)'),
            ),
            TextField(
              controller: _heightController,
              keyboardType: TextInputType.numberWithOptions(decimal: true),
              decoration: const InputDecoration(labelText: 'Height (m)'),
            ),
          ],
        );
      case TankType.horizontalCylinder:
        return Column(
          children: [
            TextField(
              controller: _diameterController,
              keyboardType: TextInputType.numberWithOptions(decimal: true),
              decoration: const InputDecoration(labelText: 'Diameter (m)'),
            ),
            TextField(
              controller: _lengthController,
              keyboardType: TextInputType.numberWithOptions(decimal: true),
              decoration: const InputDecoration(labelText: 'Length (m)'),
            ),
          ],
        );
      case TankType.rectangle:
        return Column(
          children: [
            TextField(
              controller: _lengthController,
              keyboardType: TextInputType.numberWithOptions(decimal: true),
              decoration: const InputDecoration(labelText: 'Length (m)'),
            ),
            TextField(
              controller: _widthController,
              keyboardType: TextInputType.numberWithOptions(decimal: true),
              decoration: const InputDecoration(labelText: 'Width (m)'),
            ),
            TextField(
              controller: _heightController,
              keyboardType: TextInputType.numberWithOptions(decimal: true),
              decoration: const InputDecoration(labelText: 'Height (m)'),
            ),
          ],
        );
    }
  }

  @override
  void dispose() {
    _heightController.dispose();
    _diameterController.dispose();
    _lengthController.dispose();
    _widthController.dispose();
    super.dispose();
  }

  @override
  Widget build(BuildContext context) {
    return Scaffold(
        appBar: AppBar(title: const Text('Sensor & Tank Setup')),
        body: SingleChildScrollView(
          padding: const EdgeInsets.all(16),
          child: Column(crossAxisAlignment: CrossAxisAlignment.start, children: [
            const Text('Sensor Type', style: TextStyle(fontWeight: FontWeight.bold)),
            ListTile(
              title: const Text('Submersible (payload = level in meters)'),
              leading: Radio<SensorType>(
                  value: SensorType.submersible,
                  groupValue: _sensorType,
                  onChanged: (v) => setState(() => _sensorType = v!)),
            ),
            ListTile(
              title: const Text('Ultrasonic (payload = distance from sensor to liquid surface in meters)'),
              leading: Radio<SensorType>(
                  value: SensorType.ultrasonic,
                  groupValue: _sensorType,
                  onChanged: (v) => setState(() => _sensorType = v!)),
            ),
            const SizedBox(height: 12),
            const Text('Tank Type', style: TextStyle(fontWeight: FontWeight.bold)),
            ListTile(
              title: const Text('Vertical Cylinder'),
              leading: Radio<TankType>(
                  value: TankType.verticalCylinder,
                  groupValue: _tankType,
                  onChanged: (v) => setState(() => _tankType = v!)),
            ),
            ListTile(
              title: const Text('Horizontal Cylinder'),
              leading: Radio<TankType>(
                  value: TankType.horizontalCylinder,
                  groupValue: _tankType,
                  onChanged: (v) => setState(() => _tankType = v!)),
            ),
            ListTile(
              title: const Text('Rectangle'),
              leading: Radio<TankType>(
                  value: TankType.rectangle,
                  groupValue: _tankType,
                  onChanged: (v) => setState(() => _tankType = v!)),
            ),
            const SizedBox(height: 8),
            _tankDimensionForm(),
            const SizedBox(height: 12),
            const Text('Alerts (optional) — set minimum and/or maximum liquid level in meters', style: TextStyle(fontWeight: FontWeight.bold)),
            TextField(
              controller: _minController,
              keyboardType: TextInputType.numberWithOptions(decimal: true),
              decoration: const InputDecoration(labelText: 'Minimum level (m) — send alert when below'),
            ),
            TextField(
              controller: _maxController,
              keyboardType: TextInputType.numberWithOptions(decimal: true),
              decoration: const InputDecoration(labelText: 'Maximum level (m) — send alert when above'),
            ),
            const SizedBox(height: 20),
            ElevatedButton(onPressed: _goToMain, child: const Text('Submit & Start')),
          ]),
        ));
  }
}

/// Page 3: Main UI and MQTT live feed + visualization
class MainTankPage extends StatefulWidget {
   // required inputs (add these)
  final String broker;
  final int port;
  final String topic;
  final SensorType sensorType;
  final TankType tankType;
  final double height;   // m
  final double diameter; // m
  final double length;   // m
  final double width;    // m
  // existing fields...
  final String? username;
  final String? password;
  final double? minThreshold;
  final double? maxThreshold;
  final double multiplier;
  final double offset;
  // Control button config
  final bool useControlButton;
  final String? controlTopic;
  final ControlMode controlMode;
  final String onValue;
  final String offValue;
  final bool autoControl;

  final String projectName;
  const MainTankPage({
    super.key,
    required this.broker,
    required this.port,
    required this.topic,
    required this.sensorType,
    required this.tankType,
    required this.height,
    required this.diameter,
    required this.length,
    required this.width,
    this.username,
    this.password,
    this.minThreshold,
    this.maxThreshold,
    required this.projectName,
    this.multiplier = 1.0,
    this.offset = 0.0,
  this.useControlButton = false,
  this.controlTopic,
  this.controlMode = ControlMode.toggle,
  this.onValue = 'ON',
  this.offValue = 'OFF',
  this.autoControl = false,
  });

  @override
  State<MainTankPage> createState() => _MainTankPageState();
}

class _MainTankPageState extends State<MainTankPage> {
  static const MethodChannel _settingsChannel = MethodChannel('app.settings.channel');
  static const MethodChannel _serviceChannel = MethodChannel('app.mqtt.service');
  late MqttService _mqttService;
  double? _lastNotifiedHigh;
  double? _lastNotifiedLow;

  double _level = 0.0; // computed level in meters (liquid height from bottom)
  Timer? _heartbeatTimer;
  String _connectionStatus = 'Disconnected';
  bool _isOn = false; // current state for on/off or last state for toggle
  bool _sending = false; // show progress while publishing

  @override
  void initState() {
    super.initState();
    _mqttService = MqttService(
      widget.broker,
      widget.port,
      widget.topic,
  publishTopic: widget.controlTopic,
      username: widget.username,
      password: widget.password,
      onMessage: _onMessage,
      onStatus: _onStatus,
    );
    _mqttService.connect();
    // start native foreground service for notifications when app closed
    if (enableNativeForegroundService) {
      _startNativeService();
    }
    debugPrint('Skipping bridge registration in MainTankPage.initState (local notifications only)');
  }

  Future<void> _publishControl(String value) async {
    await _mqttService.publishJson(value, toTopic: widget.controlTopic);
  }

  Future<void> _toggleOrSet() async {
    if (_sending) return; // prevent double taps
    setState(() => _sending = true);
    if (widget.controlMode == ControlMode.toggle) {
      // Locally flip for UI and send toggle command
      setState(() => _isOn = !_isOn);
      try {
        await _publishControl(widget.onValue);
      } finally {
        if (mounted) setState(() => _sending = false);
      }
    } else {
      // onOff: flip local and publish new value
      setState(() => _isOn = !_isOn);
      try {
        await _publishControl(_isOn ? widget.onValue : widget.offValue);
      } finally {
        if (mounted) setState(() => _sending = false);
      }
    }
  }

  @override
  void dispose() {
    _mqttService.disconnect();
    _heartbeatTimer?.cancel();
    super.dispose();
  }

  Future<void> _startNativeService() async {
    try {
      final args = {
        'broker': widget.broker,
        'port': widget.port,
        'topic': widget.topic,
        'sensorType': widget.sensorType.toString(),
        'tankType': widget.tankType.toString(),
        'height': widget.height,
        'diameter': widget.diameter,
        'length': widget.length,
        'width': widget.width,
        'username': widget.username,
        'password': widget.password,
        'minThreshold': widget.minThreshold ?? double.nan,
        'maxThreshold': widget.maxThreshold ?? double.nan,
        'projectName': widget.projectName,
      };
      await _serviceChannel.invokeMethod('startService', args);
    } catch (e) {
      debugPrint('Failed to start native service: $e');
    }
  }

  void _onStatus(String status) {
    if (!mounted) return;
    setState(() {
      _connectionStatus = status;
    });
  }

  void _onMessage(double value) {
    if (!mounted) return;
    
    final correctedValue = value * widget.multiplier + widget.offset;

    // Called when a numeric payload arrives
    setState(() {
      // Interpret payload depending on sensor type
      if (widget.sensorType == SensorType.submersible) {
        // payload is the liquid level directly (meters from bottom)
        _level = correctedValue;
      } else {
        // ultrasonic: payload is distance from sensor to liquid surface
        // We assume sensor mounted at tank top; so level = tankHeight - distance
        _level = widget.height - correctedValue;
      }
      // clamp to [0, tank height]
      if (_level.isNaN) _level = 0.0;
      _level = _level.clamp(0.0, widget.height);
    });

    // check thresholds outside setState to avoid UI jitter
    final minThr = widget.minThreshold;
    final maxThr = widget.maxThreshold;
    if (maxThr != null && _level > maxThr) {
      if (_lastNotifiedHigh == null || _lastNotifiedHigh! < maxThr) {
        _lastNotifiedHigh = _level;
        _maybeNotify('High level', 'Level ${_level.toStringAsFixed(2)}m exceeded max ${maxThr.toStringAsFixed(2)}m');
      }
    } else {
      _lastNotifiedHigh = null;
    }

    if (minThr != null && _level < minThr) {
      if (_lastNotifiedLow == null || _lastNotifiedLow! > minThr) {
        _lastNotifiedLow = _level;
        _maybeNotify('Low level', 'Level ${_level.toStringAsFixed(2)}m below min ${minThr.toStringAsFixed(2)}m');
      }
      // Auto control: turn ON when below min
      if (widget.useControlButton && widget.autoControl) {
        if (!mounted) return;
        if (widget.controlMode == ControlMode.onOff) {
          if (!_isOn) {
            _isOn = true; // update locally without setState to avoid rebuild storm
            unawaited(_publishControl(widget.onValue));
          }
        } else {
          // toggle mode: only send if we consider it OFF; naive approach uses _isOn flag
          if (!_isOn) {
            _isOn = true;
            unawaited(_publishControl(widget.onValue));
          }
        }
      }
    } else {
      _lastNotifiedLow = null;
    }

    // Auto control: turn OFF when above max
    if (maxThr != null && _level > maxThr) {
      if (widget.useControlButton && widget.autoControl) {
        if (widget.controlMode == ControlMode.onOff) {
          if (_isOn) {
            _isOn = false;
            unawaited(_publishControl(widget.offValue));
          }
        } else {
          if (_isOn) {
            _isOn = false;
            unawaited(_publishControl(widget.onValue)); // toggle command
          }
        }
      }
    }
  }

  void _maybeNotify(String title, String body) async {
    try {
      final enabled = await _settingsChannel.invokeMethod<bool>('areNotificationsEnabled');
      if (enabled == true) {
        await _settingsChannel.invokeMethod('postNotification', {'title': title, 'body': body});
      }
    } catch (e) {
      debugPrint('Notification channel error: $e');
    }
  }

  // Volume calculators
  double _totalVolumeM3() {
    switch (widget.tankType) {
      case TankType.verticalCylinder:
        final r = widget.diameter / 2.0;
        return pi * r * r * widget.height;
      case TankType.horizontalCylinder:
        final r = widget.diameter / 2.0;
        return _horizontalCylinderVolume(r, widget.length); // full volume
      case TankType.rectangle:
        return widget.length * widget.width * widget.height;
    }
  }

  double _liquidVolumeM3() {
    switch (widget.tankType) {
      case TankType.verticalCylinder:
        final r = widget.diameter / 2.0;
        return pi * r * r * (_level);
      case TankType.horizontalCylinder:
        final r = widget.diameter / 2.0;
        final A = _horizontalCylinderSectionArea(r, _level);
        return A * widget.length;
      case TankType.rectangle:
        return widget.length * widget.width * (_level);
    }
  }

  // Horizontal cylinder: full volume calculation helper (used for total)
  double _horizontalCylinderVolume(double r, double L) {
    return pi * r * r * L;
  }

  // Horizontal cylinder: area of circular segment when filled to depth h (0..2r)
  double _horizontalCylinderSectionArea(double r, double h) {
    if (h <= 0) return 0.0;
    if (h >= 2 * r) return pi * r * r;
    final a = r * r * acos((r - h) / r) - (r - h) * sqrt(2 * r * h - h * h);
    return a;
  }

  // Helper widget for stat cards
  Widget _statCard(String title, String value) {
    final theme = Theme.of(context);
    return Card(
      child: SizedBox(
        width: 110,
        height: 68,
        child: Padding(
          padding: const EdgeInsets.all(8.0),
          child: Column(
            crossAxisAlignment: CrossAxisAlignment.start,
            mainAxisAlignment: MainAxisAlignment.center,
            children: [
              Text(title, style: theme.textTheme.bodySmall),
              const SizedBox(height: 6),
              Text(value, style: theme.textTheme.titleMedium?.copyWith(fontWeight: FontWeight.bold)),
            ],
          ),
        ),
      ),
    );
  }

  @override
  Widget build(BuildContext context) {
    final totalM3 = _totalVolumeM3();
    final liquidM3 = _liquidVolumeM3();
    final emptyM3 = max(0.0, totalM3 - liquidM3);
    final percent = totalM3 == 0 ? 0.0 : (liquidM3 / totalM3) * 100.0;

    return Scaffold(
      appBar: AppBar(
        title: Text(widget.projectName),
        actions: [
          Consumer<ThemeProvider>(
            builder: (context, themeProvider, child) {
              return IconButton(
                tooltip: 'Toggle Theme',
                icon: Icon(themeProvider.themeMode == ThemeMode.dark ? Icons.dark_mode : Icons.light_mode),
                onPressed: () {
                  themeProvider.toggleTheme(themeProvider.themeMode == ThemeMode.light);
                },
              );
            },
          ),
          IconButton(
            tooltip: 'Notification settings',
            icon: const Icon(Icons.notifications),
            onPressed: () async {
              try {
                await _settingsChannel.invokeMethod('openAppNotificationSettings');
              } catch (e) {
                ScaffoldMessenger.of(context).showSnackBar(const SnackBar(content: Text('Could not open settings')));
              }
            },
          ),
        ],
      ),
      body: Padding(
        padding: const EdgeInsets.all(12),
        child: Column(children: [
          // statistics
          Row(
            mainAxisAlignment: MainAxisAlignment.spaceAround,
            children: [
              _statCard('Liquid %', '${percent.toStringAsFixed(1)} %'),
              _statCard('Level (m)', '${_level.toStringAsFixed(3)} m'),
              _statCard('Liquid L', '${(liquidM3 * 1000).toStringAsFixed(2)} L'),
            ],
          ),
          const SizedBox(height: 8),
          Row(
            mainAxisAlignment: MainAxisAlignment.spaceAround,
            children: [
              _statCard('Empty L', '${(emptyM3 * 1000).toStringAsFixed(2)} L'),
              _statCard('Total L', '${(totalM3 * 1000).toStringAsFixed(2)} L'),
              _statCard('Empty (m)', (widget.height - _level).toStringAsFixed(3)),
            ],
          ),
          const SizedBox(height: 16),
          SizedBox(
            height: 300, // Set a fixed height for the tank
            width: 200, // Set a fixed width for the tank
            child: TankWidget(
              tankType: widget.tankType,
              waterLevel: _level / widget.height,
              minThreshold: widget.minThreshold != null ? widget.minThreshold! / widget.height : null,
              maxThreshold: widget.maxThreshold != null ? widget.maxThreshold! / widget.height : null,
              volume: liquidM3 * 1000,
              percentage: percent,
            ),
          ),
          const SizedBox(height: 12),
          if (widget.useControlButton)
            Card(
              shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(12)),
              elevation: 1,
              child: Padding(
                padding: const EdgeInsets.all(12.0),
                child: Column(
                  crossAxisAlignment: CrossAxisAlignment.stretch,
                  children: [
                    Row(children: [
                      Container(width: 4, height: 18, decoration: BoxDecoration(color: Theme.of(context).colorScheme.primary, borderRadius: BorderRadius.circular(2))),
                      const SizedBox(width: 8),
                      Icon(Icons.power_settings_new, color: Theme.of(context).colorScheme.primary),
                      const SizedBox(width: 6),
                      Text('Control', style: TextStyle(fontWeight: FontWeight.w600, color: Theme.of(context).colorScheme.primary)),
                    ]),
                    const SizedBox(height: 12),
                    Align(
                      alignment: Alignment.center,
                      child: FilledButton.icon(
                        onPressed: _sending ? null : _toggleOrSet,
                        icon: Icon(_isOn ? Icons.power : Icons.power_off),
                        label: Padding(
                          padding: const EdgeInsets.symmetric(vertical: 4.0),
                          child: Text(_isOn ? 'ON' : 'OFF', style: const TextStyle(fontSize: 18, fontWeight: FontWeight.w700)),
                        ),
                        style: FilledButton.styleFrom(
                          shape: const StadiumBorder(),
                          padding: const EdgeInsets.symmetric(horizontal: 28, vertical: 14),
                          backgroundColor: _isOn ? Colors.green : Theme.of(context).colorScheme.surfaceVariant,
                          foregroundColor: _isOn ? Colors.white : Theme.of(context).colorScheme.onSurface,
                        ),
                      ),
                    ),
                    if (_sending) ...[
                      const SizedBox(height: 10),
                      Row(mainAxisAlignment: MainAxisAlignment.center, children: const [
                        SizedBox(width: 16, height: 16, child: CircularProgressIndicator(strokeWidth: 2)),
                        SizedBox(width: 8),
                        Text('Publishing...'),
                      ]),
                    ],
                    if (widget.controlTopic != null && widget.controlTopic!.isNotEmpty) ...[
                      const SizedBox(height: 8),
                      Text('Topic: ${widget.controlTopic}', textAlign: TextAlign.center, style: Theme.of(context).textTheme.bodySmall),
                    ],
                  ],
                ),
              ),
            ),
          const SizedBox(height: 12),
          ElevatedButton(
              onPressed: () {
                // go back to setup (reconnect lifecycle)
                Navigator.pushReplacement(
                  context,
                  MaterialPageRoute(builder: (_) => const ProjectListPage()),
                );
              },
              child: const Text('Back to Projects')),
        ]),
      ),
      bottomNavigationBar: Padding(
        padding: const EdgeInsets.all(16.0),
        child: Text(
          _connectionStatus,
          textAlign: TextAlign.center,
          style: Theme.of(context).textTheme.bodySmall,
        ),
      ),
    );
  }
}
