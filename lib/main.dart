// main.dart
import 'dart:async';
import 'dart:io';
import 'dart:math';
import 'package:flutter/material.dart';
import 'package:mqtt_client/mqtt_client.dart' as mqtt;

import 'package:flutter/foundation.dart' show kIsWeb;
import 'package:mqtt_client/mqtt_server_client.dart' show MqttServerClient;
import 'package:mqtt_client/mqtt_browser_client.dart' show MqttBrowserClient;
import 'package:shared_preferences/shared_preferences.dart';
import 'package:flutter/services.dart';
import 'package:firebase_core/firebase_core.dart';
import 'package:firebase_messaging/firebase_messaging.dart';
import 'package:http/http.dart' as http;
import 'dart:convert';

void main() async {
  WidgetsFlutterBinding.ensureInitialized();
  // Initialize Firebase for FCM
  try {
    await Firebase.initializeApp();
  // background message handler
  FirebaseMessaging.onBackgroundMessage(_firebaseMessagingBackgroundHandler);
  } catch (e) {
    // allow running without firebase if not configured yet
    debugPrint('Firebase initialize error: $e');
  }

  // Load saved settings and launch correct start page
  final prefs = await SharedPreferences.getInstance();
  final savedBroker = prefs.getString('broker');
  final savedPort = prefs.getInt('port');
  final savedTopic = prefs.getString('topic');
  final savedSensor = prefs.getString('sensor');
  final savedTank = prefs.getString('tank');

  if (savedBroker != null && savedPort != null && savedTopic != null && savedSensor != null && savedTank != null) {
    final sensorType = SensorType.values.firstWhere(
        (e) => e.toString() == savedSensor,
        orElse: () => SensorType.submersible);
    final tankType = TankType.values.firstWhere(
        (e) => e.toString() == savedTank,
        orElse: () => TankType.verticalCylinder);
    final height = prefs.getDouble('height') ?? 1.0;
    final diameter = prefs.getDouble('diameter') ?? 0.4;
    final length = prefs.getDouble('length') ?? 1.0;
    final width = prefs.getDouble('width') ?? 0.5;
    final minThr = prefs.getDouble('minThreshold');
    final maxThr = prefs.getDouble('maxThreshold');
    final username = prefs.getString('username');
    final password = prefs.getString('password');

    runApp(MaterialApp(
      title: 'Tank Monitor',
      theme: ThemeData(primarySwatch: Colors.blue),
      home: MainTankPage(
        broker: savedBroker,
        port: savedPort,
        topic: savedTopic,
        sensorType: sensorType,
        tankType: tankType,
        height: height,
        diameter: diameter,
        length: length,
        width: width,
        username: username,
        password: password,
        minThreshold: minThr,
        maxThreshold: maxThr,
      ),
    ));
  } else {
    runApp(const MyApp());
  }
}

// Top-level background handler required by firebase_messaging
Future<void> _firebaseMessagingBackgroundHandler(RemoteMessage message) async {
  try {
    await Firebase.initializeApp();
  } catch (_) {}
  debugPrint('FCM background message: ${message.messageId}');
}

Future<String> _getOrCreateDeviceId() async {
  final prefs = await SharedPreferences.getInstance();
  var id = prefs.getString('deviceId');
  if (id == null || id.isEmpty) {
    id = 'dev_${DateTime.now().millisecondsSinceEpoch}';
    await prefs.setString('deviceId', id);
  }
  return id;
}

// Helper: register device with bridge
Future<void> registerDeviceWithBridge({
  required String deviceId,
  required String token,
  required String topic,
  double? minThreshold,
  double? maxThreshold,
  String bridgeUrl = 'http://10.0.2.2:3000' // default to local emulator; change to your bridge host
}) async {
  try {
    final uri = Uri.parse('$bridgeUrl/register');
    final body = {
      'deviceId': deviceId,
      'token': token,
      'topic': topic,
      'thresholds': {
        if (minThreshold != null) 'min': minThreshold,
        if (maxThreshold != null) 'max': maxThreshold,
      }
    };
    final res = await http.post(uri, body: jsonEncode(body), headers: {'Content-Type': 'application/json'}).timeout(const Duration(seconds: 10));
    if (res.statusCode == 200) {
      debugPrint('Registered device with bridge');
    } else {
      debugPrint('Bridge register failed: ${res.statusCode} ${res.body}');
    }
  } catch (e) {
    debugPrint('Error registering with bridge: $e');
  }
}

enum SensorType { submersible, ultrasonic }
enum TankType { verticalCylinder, horizontalCylinder, rectangle }

class MyApp extends StatelessWidget {
  const MyApp({super.key});

  // This widget is the root of your application.
  @override
  Widget build(BuildContext context) {
    return MaterialApp(
      title: 'Tank Monitor',
      theme: ThemeData(primarySwatch: Colors.blue),
      home: const MqttTopicPage(),
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
        appBar: AppBar(title: const Text('MQTT - Topic')),
        body: Padding(
          padding: const EdgeInsets.all(16),
          child: Column(children: [
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
          ]),
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

  void _goToMain() {
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
  SharedPreferences.getInstance().then((prefs) {
    prefs.setString('sensor', _sensorType.toString());
    prefs.setString('tank', _tankType.toString());
    prefs.setDouble('height', height);
    prefs.setDouble('diameter', diameter);
    prefs.setDouble('length', length);
    prefs.setDouble('width', width);
    if (minThr != null) prefs.setDouble('minThreshold', minThr);
    if (maxThr != null) prefs.setDouble('maxThreshold', maxThr);
    // register with bridge: get FCM token and device id
    FirebaseMessaging.instance.getToken().then((token) async {
      if (token != null) {
        final deviceId = await _getOrCreateDeviceId();
        await registerDeviceWithBridge(
          deviceId: deviceId,
          token: token,
          topic: widget.topic,
          minThreshold: minThr,
          maxThreshold: maxThr,
        );
      }
    });
  });

  // Navigate to main page and pass thresholds
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

  double _rawPayload = 0.0; // raw numeric value from MQTT
  double _level = 0.0; // computed level in meters (liquid height from bottom)
  Timer? _heartbeatTimer;
  String _connectionStatus = 'Disconnected';

  @override
  void initState() {
    super.initState();
    _mqttService = MqttService(
  widget.broker,
  widget.port,
  widget.topic,
  username: widget.username,
  password: widget.password,
  onMessage: _onMessage,
  onStatus: _onStatus,
);
    _mqttService.connect();
    // start native foreground service for notifications when app closed
    _startNativeService();
    // Also register with bridge for FCM notifications (non-blocking)
    FirebaseMessaging.instance.getToken().then((token) async {
      if (token != null) {
        final deviceId = await _getOrCreateDeviceId();
        await registerDeviceWithBridge(
          deviceId: deviceId,
          token: token,
          topic: widget.topic,
          minThreshold: widget.minThreshold,
          maxThreshold: widget.maxThreshold,
        );
      }
    });
  // notifications removed — no runtime initialization
  }

  Future<void> _startNativeService() async {
    try {
      final args = {
        'broker': widget.broker,
        'port': widget.port,
        'topic': widget.topic,
        'username': widget.username,
        'password': widget.password,
        'minThreshold': widget.minThreshold ?? double.nan,
        'maxThreshold': widget.maxThreshold ?? double.nan,
      };
      await _serviceChannel.invokeMethod('startService', args);
    } catch (e) {
      debugPrint('Failed to start native service: $e');
    }
  }

  Future<void> _stopNativeService() async {
    try {
      await _serviceChannel.invokeMethod('stopService');
    } catch (e) {
      debugPrint('Failed to stop native service: $e');
    }
  }

  void _onStatus(String status) {
    setState(() {
      _connectionStatus = status;
    });
  }

  void _onMessage(double value) {
    // Called when a numeric payload arrives
  setState(() {
      _rawPayload = value;
      // Interpret payload depending on sensor type
      if (widget.sensorType == SensorType.submersible) {
        // payload is the liquid level directly (meters from bottom)
        _level = value;
      } else {
        // ultrasonic: payload is distance from sensor to liquid surface
        // We assume sensor mounted at tank top; so level = tankHeight - distance
        _level = widget.height - value;
      }
      // clamp to [0, tank height]
      if (_level.isNaN) _level = 0.0;
      _level = _level.clamp(0.0, widget.height);
    });

    // check thresholds outside setState to avoid UI jitter
    final minThr = widget.minThreshold;
    final maxThr = widget.maxThreshold;
    // notifications removed; we still track lastNotified to avoid logic spam
    if (maxThr != null && _level > maxThr) {
      if (_lastNotifiedHigh == null || _lastNotifiedHigh! < maxThr) {
        _lastNotifiedHigh = _level;
  // Post native notification if allowed
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
    } else {
      _lastNotifiedLow = null;
    }
  }
  
  // Invoke platform channel to post notification if enabled, otherwise open settings prompt
  //static const MethodChannel _settingsChannel = MethodChannel('app.settings.channel');

  void _maybeNotify(String title, String body) async {
    try {
      final enabled = await _settingsChannel.invokeMethod<bool>('areNotificationsEnabled');
      if (enabled == true) {
        await _settingsChannel.invokeMethod('postNotification', {'title': title, 'body': body});
      } else {
        // Not enabled — call settings so user can enable
        await _settingsChannel.invokeMethod('openAppNotificationSettings');
      }
    } catch (e) {
      debugPrint('Notification channel error: $e');
    }
  }
  // notifications removed; no-op placeholder could be added here later

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

  // liquid vol given _level
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
    // if h <= 0 -> 0, if h >= 2r -> area = pi*r^2
    if (h <= 0) return 0.0;
    if (h >= 2 * r) return pi * r * r;
    // Another variant often used:
    // A = r^2 * acos((r-h)/r) - (r-h)*sqrt(2*r*h - h*h)
    // both are equivalent; let's use robust numeric formula:
    final a = r * r * acos((r - h) / r) - (r - h) * sqrt(2 * r * h - h * h);
    return a;
  }

  @override
  void dispose() {
    _mqttService.disconnect();
    _heartbeatTimer?.cancel();
    super.dispose();
  }

  @override
  Widget build(BuildContext context) {
    final totalM3 = _totalVolumeM3();
    final liquidM3 = _liquidVolumeM3();
    final emptyM3 = max(0.0, totalM3 - liquidM3);
    final percent = totalM3 == 0 ? 0.0 : (liquidM3 / totalM3) * 100.0;

    return Scaffold(
      appBar: AppBar(
        title: const Text('Tank Monitor'),
        actions: [
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
          IconButton(
            tooltip: 'Send test notification',
            icon: const Icon(Icons.notification_add),
            onPressed: () {
              _maybeNotify('Test Notification', 'This is a test alert from the app');
            },
          ),
          Padding(
            padding: const EdgeInsets.all(12),
            child: Center(child: Text(_connectionStatus, style: const TextStyle(fontSize: 12))),
          )
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
              _statCard('Raw payload', _rawPayload.toStringAsFixed(3)),
            ],
          ),
          const SizedBox(height: 16),
          Expanded(
            child: Center(
              child: AspectRatio(
                aspectRatio: widget.tankType == TankType.horizontalCylinder ? 2.2 : 0.6,
                child: CustomPaint(
                  size: Size.infinite,
                  painter: TankPainter(
                    tankType: widget.tankType,
                    percent: percent.clamp(0.0, 100.0),
                  ),
                ),
              ),
            ),
          ),
          const SizedBox(height: 12),
          ElevatedButton(
              onPressed: () {
                // go back to setup (reconnect lifecycle)
                Navigator.pushReplacement(
                  context,
                  MaterialPageRoute(builder: (_) => MqttTopicPage()),
                );
              },
              child: const Text('Back / Setup')),
        ]),
      ),
    );
  }

  Widget _statCard(String title, String value) {
    return Card(
      child: SizedBox(
        width: 110,
        height: 68,
        child: Padding(
          padding: const EdgeInsets.all(8.0),
          child:
              Column(crossAxisAlignment: CrossAxisAlignment.start, mainAxisAlignment: MainAxisAlignment.center, children: [
            Text(title, style: const TextStyle(fontSize: 12, color: Colors.black54)),
            const SizedBox(height: 6),
            Text(value, style: const TextStyle(fontWeight: FontWeight.bold)),
          ]),
        ),
      ),
    );
  }
}

/// Simple MQTT wrapper using mqtt_client package
class MqttService {
  final String broker;
  final int port;
  final String topic;
  final String? username;
  final String? password;
  final void Function(double) onMessage;
  final void Function(String) onStatus;

  late mqtt.MqttClient client;
  int _reconnectAttempts = 0;

    MqttService(
    this.broker,
    this.port,
    this.topic, {
    this.username,
    this.password,
    required this.onMessage,
    required this.onStatus,
  }) {
    final clientId = 'flutter_client_${DateTime.now().millisecondsSinceEpoch}';

    if (kIsWeb) {
      // Build a websocket URI for the browser.
      // If the user already provided ws:// or wss://, use it as-is.
      // Otherwise choose ws or wss depending on page protocol and map 1883 -> 8080 by default.
      String serverUri = broker;

      if (!broker.startsWith('ws://') && !broker.startsWith('wss://')) {
        // If user typed host:port, split it.
        String hostOnly = broker;
        int givenPort = port;
        if (broker.contains(':')) {
          final parts = broker.split(':');
          hostOnly = parts[0];
          final maybePort = int.tryParse(parts[1]);
          if (maybePort != null) givenPort = maybePort;
        }

        // If the web page is https -> use secure websockets (wss)
        final pageIsHttps = Uri.base.scheme == 'https';
        final scheme = pageIsHttps ? 'wss' : 'ws';

        // map common mqtt tcp port to common websocket port
        final wsPort = (givenPort == 1883) ? 8080 : givenPort;

        serverUri = '$scheme://$hostOnly:$wsPort/mqtt';
      }

      client = MqttBrowserClient(serverUri, clientId);
      client.logging(on: false);
      debugPrint('MQTT(Web): serverUri=$serverUri');
    } else {
      client = MqttServerClient(broker, clientId);
      (client as MqttServerClient).port = port;
      client.logging(on: false);
      (client as MqttServerClient).secure = false;
      debugPrint('MQTT(Native): host=$broker port=$port');
    }

    client.keepAlivePeriod = 20;
    client.onDisconnected = _onDisconnected;
    client.onConnected = _onConnected;
  }

  Future<void> connect() async {
    onStatus('Connecting...');
    try {
      final connMess = mqtt.MqttConnectMessage()
          .withClientIdentifier(client.clientIdentifier)
          .startClean()
          .withWillQos(mqtt.MqttQos.atLeastOnce);
      client.connectionMessage = connMess;

      final user = (username ?? '').trim().isEmpty ? null : username;
      final pass = (password ?? '').trim().isEmpty ? null : password;

      if (user != null || pass != null) {
        await client.connect(user, pass);
      } else {
        await client.connect();
      }

      _reconnectAttempts = 0;
      onStatus('Connected');
      _subscribe();
      client.updates?.listen(_onMessage);
    } on SocketException catch (se, st) {
      debugPrint('MQTT SocketException: $se');
      debugPrint('$st');
      onStatus('Network error: ${se.message}');
      disconnect();
      _reconnectAttempts++;
      final delaySeconds = (pow(2, _reconnectAttempts) as double).clamp(1, 30).toInt();
      Timer(Duration(seconds: delaySeconds), connect);
    } catch (e, st) {
      debugPrint('MQTT connect error: $e');
      debugPrint('$st');
      onStatus('Error: $e');
      disconnect();
    }
  }

  void _subscribe() {
    client.subscribe(topic, mqtt.MqttQos.atMostOnce);
    onStatus('Subscribed to $topic');
  }

  void _onMessage(List<mqtt.MqttReceivedMessage<mqtt.MqttMessage>>? event) {
    if (event == null || event.isEmpty) return;
    final recMess = event[0].payload as mqtt.MqttPublishMessage;
    final payload = mqtt.MqttPublishPayload.bytesToStringAsString(recMess.payload.message);
    final value = double.tryParse(payload.trim());
    if (value != null) {
      onMessage(value);
    } else {
      final maybe = _extractFirstNumber(payload);
      if (maybe != null) onMessage(maybe);
    }
  }

  double? _extractFirstNumber(String s) {
    final regex = RegExp(r'[-+]?[0-9]*\.?[0-9]+');
    final match = regex.firstMatch(s);
    if (match != null) return double.tryParse(match.group(0)!);
    return null;
  }

  void _onDisconnected() => onStatus('Disconnected');
  void _onConnected() => onStatus('Connected');

  void disconnect() {
    try {
      client.disconnect();
    } catch (_) {}
  }
}

/// Painter to show a simple tank filling
class TankPainter extends CustomPainter {
  final TankType tankType;
  final double percent; // 0..100

  TankPainter({required this.tankType, required this.percent});

  @override
  void paint(Canvas canvas, Size size) {
    final paintTank = Paint()
      ..color = Colors.black
      ..style = PaintingStyle.stroke
      ..strokeWidth = 3;
    final paintFill = Paint()
      ..shader = LinearGradient(
        colors: [Colors.blue.shade400, Colors.blue.shade800],
      ).createShader(Rect.fromLTWH(0, 0, size.width, size.height))
      ..style = PaintingStyle.fill;

    if (tankType == TankType.verticalCylinder || tankType == TankType.rectangle) {
      final rect = Rect.fromLTWH(10, 10, size.width - 20, size.height - 20);
      // draw tank border
      canvas.drawRect(rect, paintTank);
      // fill according to percent from bottom
      final fillHeight = (rect.height) * (percent / 100.0);
      final fillRect = Rect.fromLTWH(rect.left, rect.bottom - fillHeight, rect.width, fillHeight);
      canvas.drawRect(fillRect, paintFill);
    } else {
      // horizontal cylinder: draw rounded ends and fill from left
      final r = (size.height - 20) / 2;
      final L = size.width - 40;
      final centerY = size.height / 2;
      final left = 20.0;
      final right = left + L;

      // outline as rounded rect
      final outer = RRect.fromLTRBR(left - r, centerY - r, right + r, centerY + r, Radius.circular(r));
      canvas.drawRRect(outer, paintTank);

      // fill width by percent:
      final filledWidth = (L + 2 * r) * (percent / 100.0);

      // clip to outer then draw a rectangle for filling
      final clipPath = Path()..addRRect(outer);
      canvas.save();
      canvas.clipPath(clipPath);
      final fillRect = Rect.fromLTWH(left - r, centerY - r, filledWidth, r * 2);
      canvas.drawRect(fillRect, paintFill);
      canvas.restore();
    }
  }

  @override
  bool shouldRepaint(covariant TankPainter oldDelegate) {
    return oldDelegate.percent != percent || oldDelegate.tankType != tankType;
  }
}
