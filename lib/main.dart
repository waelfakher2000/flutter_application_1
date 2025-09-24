// main.dart
import 'dart:async';
import 'dart:convert';
import 'dart:math';
import 'package:flutter/material.dart';
import 'package:provider/provider.dart';
import 'package:shared_preferences/shared_preferences.dart';
import 'package:flutter/services.dart';
import 'package:flutter_local_notifications/flutter_local_notifications.dart';
import 'package:firebase_core/firebase_core.dart';
import 'package:firebase_messaging/firebase_messaging.dart';
import 'package:http/http.dart' as http;
import 'auth_provider.dart';
import 'login_page.dart';
// Removed backend bridge HTTP and UUID usage
import 'tank_widget.dart';
import 'theme_provider.dart';
import 'project_repository.dart';
import 'types.dart';
import 'mqtt_service.dart';
import 'landing_page.dart';
import 'project_list_page.dart';
import 'project_model.dart';
import 'history_chart_page.dart';
// Removed history page (backend dependent)
import 'package:mqtt_client/mqtt_client.dart' as mqtt;
import 'global_mqtt.dart';

// Local notifications plugin instance
final FlutterLocalNotificationsPlugin flutterLocalNotificationsPlugin = FlutterLocalNotificationsPlugin();
// Track processed FCM message IDs to avoid duplicates (foreground/background)
final Set<String> _seenMessageIds = <String>{};
void _rememberMessageId(String id) {
  _seenMessageIds.add(id);
  // Keep the set bounded
  if (_seenMessageIds.length > 200) {
    // Remove an arbitrary 50 oldest by iteration order
    _seenMessageIds.take(50).toList().forEach(_seenMessageIds.remove);
  }
}
bool _alreadyProcessed(String? id) => id != null && id.isNotEmpty && _seenMessageIds.contains(id);

Future<void> initializeLocalNotifications() async {
  try {
    // Use the actual launcher icon name configured by flutter_launcher_icons
    const AndroidInitializationSettings initializationSettingsAndroid =
        AndroidInitializationSettings('@mipmap/launcher_icon');
    const InitializationSettings initializationSettings = InitializationSettings(
      android: initializationSettingsAndroid,
    );
    await flutterLocalNotificationsPlugin.initialize(initializationSettings);
  } catch (e) {
    // Don’t crash in release if notification init fails (e.g., missing resource)
    debugPrint('Local notifications init error: $e');
  }
}

/// Handle background/terminated FCM messages
@pragma('vm:entry-point')
Future<void> _firebaseMessagingBackgroundHandler(RemoteMessage message) async {
  await Firebase.initializeApp();
  final data = message.data;
  final msgId = data['messageId'] as String?;
  if (_alreadyProcessed(msgId)) return;
  if (msgId != null && msgId.isNotEmpty) _rememberMessageId(msgId);
  final title = data['title'] ?? message.notification?.title ?? 'Background Notification';
  final body = data['body'] ?? message.notification?.body ?? (data.isNotEmpty ? data.toString() : '');
  final projectId = data['projectId'] as String?;
  final notifId = (projectId ?? 'default').hashCode & 0x7fffffff;
  await showLocalNotification(title: title, body: body, id: notifId);
}

Future<void> showLocalNotification({
  required String title,
  required String body,
  int id = 0,
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
    id,
    title,
    body,
    platformChannelSpecifics,
  );
}

// Optional backend URL for automatic device token registration
// Prefer passing at runtime: --dart-define=BACKEND_URL=https://your-backend.onrender.com
const String kBackendUrl = String.fromEnvironment('BACKEND_URL');

Future<String?> _resolveBackendUrl() async {
  // Priority: dart-define > stored preference
  if (kBackendUrl.isNotEmpty) return kBackendUrl;
  try {
    final prefs = await SharedPreferences.getInstance();
    final v = prefs.getString('backend_url');
    if (v != null && v.isNotEmpty) return v;
  } catch (_) {}
  return null;
}

Future<void> _registerFcmToken(String token, {String? projectId}) async {
  try {
    final base = await _resolveBackendUrl();
    if (base == null || base.isEmpty) {
      debugPrint('Skipping device registration: BACKEND_URL not configured');
      return;
    }
    final uri = Uri.parse(base.endsWith('/') ? '${base}register-device' : '$base/register-device');
    final resp = await http.post(
      uri,
      headers: const {'Content-Type': 'application/json'},
      body: jsonEncode({
        'token': token,
        // When null, backend treats as global registration (all projects)
        'projectId': projectId,
      }),
    );
    if (resp.statusCode >= 200 && resp.statusCode < 300) {
      debugPrint('FCM token registered with backend');
    } else {
      debugPrint('Device registration failed: ${resp.statusCode} ${resp.body}');
    }
  } catch (e) {
    debugPrint('Device registration error: $e');
  }
}

// Feature flag: set to true to start the native Android foreground service.
// Set to false to disable native service startup (useful for debugging crashes).
const bool enableNativeForegroundService = false;

void main() async {
  WidgetsFlutterBinding.ensureInitialized();
  final startupWatch = Stopwatch()..start();
  await Firebase.initializeApp();
  runApp(MultiProvider(providers: [
    ChangeNotifierProvider(create: (_) => ThemeProvider()),
    ChangeNotifierProvider(create: (_) => ProjectRepository()..load()),
    ChangeNotifierProvider(create: (_) => AuthProvider()..load()),
  ], child: const TankApp()));
  // Log first frame time
  WidgetsBinding.instance.addTimingsCallback((timings) {
    if (startupWatch.isRunning) {
      // First frame timings list includes a frame; stop and log.
      startupWatch.stop();
      final ft = timings.isNotEmpty ? timings.first : null;
      final buildMs = ft != null ? ft.buildDuration.inMilliseconds : -1;
      final rasterMs = ft != null ? ft.rasterDuration.inMilliseconds : -1;
      debugPrint('[Startup] First frame: totalWall=${startupWatch.elapsedMilliseconds}ms build=${buildMs}ms raster=${rasterMs}ms');
    }
  });
}

Future<void> _requestNotificationPermissions() async {
  FirebaseMessaging messaging = FirebaseMessaging.instance;
  await messaging.requestPermission(
    alert: true,
    badge: true,
    sound: true,
  );
}
// Listen for foreground FCM messages
void setupFCMForegroundListener() {
  FirebaseMessaging.onMessage.listen((RemoteMessage message) {
    final data = message.data;
    final msgId = data['messageId'] as String?;
    if (_alreadyProcessed(msgId)) return;
    if (msgId != null && msgId.isNotEmpty) _rememberMessageId(msgId);
    final title = data['title'] ?? message.notification?.title ?? 'Notification';
    final body = data['body'] ?? message.notification?.body ?? (data.isNotEmpty ? data.toString() : '');
    final projectId = data['projectId'] as String?;
    final notifId = (projectId ?? 'default').hashCode & 0x7fffffff;
    showLocalNotification(title: title, body: body, id: notifId);
  });
}


class TankApp extends StatefulWidget {
  const TankApp({super.key});

  @override
  State<TankApp> createState() => _TankAppState();
}

class _TankAppState extends State<TankApp> {
  @override
  void initState() {
    super.initState();
    _initializeAsync();
  }

  Future<void> _initializeAsync() async {
    await initializeLocalNotifications();
    FirebaseMessaging.onBackgroundMessage(_firebaseMessagingBackgroundHandler);
    // Don't block startup on the permission dialog
    Future.microtask(() async {
      try {
        await _requestNotificationPermissions();
      } catch (e) {
        debugPrint('Notification permission request failed: $e');
      }
    });
    setupFCMForegroundListener();

    // Helpful for testing: log FCM token and handle refresh
    try {
      final token = await FirebaseMessaging.instance.getToken();
      debugPrint('FCM token: ${token ?? 'null'}');
      if (token != null) {
        // Auto-register token with backend if configured
        unawaited(_registerFcmToken(token));
      }
      FirebaseMessaging.instance.onTokenRefresh.listen((t) async {
        debugPrint('FCM token refreshed: $t');
        unawaited(_registerFcmToken(t));
      });
    } catch (e) {
      debugPrint('Failed to get FCM token: $e');
    }
  }

  @override
  Widget build(BuildContext context) {
    final themeProvider = Provider.of<ThemeProvider>(context);
    return MaterialApp(
      title: 'Liquid Level Monitoring',
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
      home: const LandingOrAuthGate(),
    );
  }
}

class LandingOrAuthGate extends StatelessWidget {
  const LandingOrAuthGate({super.key});
  @override
  Widget build(BuildContext context) {
    final auth = Provider.of<AuthProvider>(context);
    final repo = Provider.of<ProjectRepository>(context);
    if (auth.loading) {
      return const Scaffold(body: Center(child: CircularProgressIndicator()));
    }
    if (!auth.isAuthenticated) return const LoginPage();
    // Once authenticated & repository loaded, attempt a one-time sync
    if (repo.isLoaded) {
      // Fire and forget; UI will update via repository notify
      Future.microtask(() => repo.syncFromBackend());
    }
    return const LandingPage();
  }
}

class DebugPage extends StatefulWidget {
  const DebugPage({super.key});

  @override
  State<DebugPage> createState() => _DebugPageState();
}

class _DebugPageState extends State<DebugPage> {
  final MethodChannel _ch = const MethodChannel('app.settings.channel');

  @override
  void initState() {
    super.initState();
    _refresh();
  }

  @override
  void dispose() {
    super.dispose();
  }

  Future<void> _refresh() async {
    // No backend settings to load anymore
    try {} catch (_) {}
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
      await showLocalNotification(title: 'Test', body: 'Local test notification', id: 'test'.hashCode & 0x7fffffff);
    } catch (e) {
      debugPrint('post notification failed: $e');
    }
  }

  Future<void> _checkEnabled() async {
    try {
      final enabled = await _ch.invokeMethod('areNotificationsEnabled');
      if (!mounted) return;
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
                  Text('Notifications', style: const TextStyle(fontWeight: FontWeight.w600)),
                  const SizedBox(height: 4),
                  const Text('Foreground: local notifications. Background/closed: via backend bridge + FCM (when configured).'),
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
            // Backend bridge removed from app; no Bridge URL panel
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
  final _brokerController = TextEditingController(text: 'mqttapi.mautoiot.com');
  final _portController = TextEditingController(text: '1883');
  final _topicController = TextEditingController(text: 'tank/level');
  final _usernameController = TextEditingController(text: 'user');
  final _passwordController = TextEditingController(text: '123456');
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
                  const Text('Default broker is mqttapi.mautoiot.com:1883 (username: user, password: 123456)'),
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
  // Wall thickness for quick start/setup flow
  final _thicknessController = TextEditingController(text: '0.0');

  Future<void> _goToMain() async {
    final height = double.tryParse(_heightController.text) ?? 0.0;
    final diameter = double.tryParse(_diameterController.text) ?? 0.0;
    final length = double.tryParse(_lengthController.text) ?? 0.0;
    final width = double.tryParse(_widthController.text) ?? 0.0;
    final thickness = double.tryParse(_thicknessController.text) ?? 0.0;

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
  await prefs.setDouble('wallThickness', thickness);
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
          wallThickness: thickness,
          username: widget.username,
          password: widget.password,
          minThreshold: minThr,
          maxThreshold: maxThr,
          projectName: widget.topic, // fallback to topic as name if not available
          connectedTankCount: 1,
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
            TextField(
              controller: _thicknessController,
              keyboardType: TextInputType.numberWithOptions(decimal: true),
              decoration: const InputDecoration(labelText: 'Wall thickness (m)'),
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
            TextField(
              controller: _thicknessController,
              keyboardType: TextInputType.numberWithOptions(decimal: true),
              decoration: const InputDecoration(labelText: 'Wall thickness (m)'),
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
            TextField(
              controller: _thicknessController,
              keyboardType: TextInputType.numberWithOptions(decimal: true),
              decoration: const InputDecoration(labelText: 'Wall thickness (m)'),
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
            RadioMenuButton<SensorType>(
              value: SensorType.submersible,
              groupValue: _sensorType,
              onChanged: (v) => setState(() => _sensorType = v!),
              child: const Text('Submersible (payload = level in meters)'),
            ),
            RadioMenuButton<SensorType>(
              value: SensorType.ultrasonic,
              groupValue: _sensorType,
              onChanged: (v) => setState(() => _sensorType = v!),
              child: const Text('Ultrasonic (payload = distance from sensor to liquid surface in meters)'),
            ),
            const SizedBox(height: 12),
            const Text('Tank Type', style: TextStyle(fontWeight: FontWeight.bold)),
            RadioMenuButton<TankType>(
              value: TankType.verticalCylinder,
              groupValue: _tankType,
              onChanged: (v) => setState(() => _tankType = v!),
              child: const Text('Vertical Cylinder'),
            ),
            RadioMenuButton<TankType>(
              value: TankType.horizontalCylinder,
              groupValue: _tankType,
              onChanged: (v) => setState(() => _tankType = v!),
              child: const Text('Horizontal Cylinder'),
            ),
            RadioMenuButton<TankType>(
              value: TankType.rectangle,
              groupValue: _tankType,
              onChanged: (v) => setState(() => _tankType = v!),
              child: const Text('Rectangle'),
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
  // Tank wall thickness (meters). Used to compute inner dimensions.
  final double wallThickness;
  // existing fields...
  final String? username;
  final String? password;
  final double? minThreshold;
  final double? maxThreshold;
  final double multiplier;
  final double offset;
  final int connectedTankCount;
  // Custom formula options
  final bool useCustomFormula;
  final String? customFormula;
  // Control button config
  final bool useControlButton;
  final String? controlTopic;
  final ControlMode controlMode;
  final String onValue;
  final String offValue;
  final bool autoControl;
  final bool controlRetained;
  final MqttQosLevel controlQos;
  final String? lastWillTopic;

  final String projectName;
  final String? projectId; // optional: used for repository volume updates
  // Payload parsing options
  final bool payloadIsJson;
  final int jsonFieldIndex;
  final String? jsonKeyName;
  // Timestamp parsing options
  final bool displayTimeFromJson;
  final int jsonTimeFieldIndex;
  final String? jsonTimeKeyName;
  // UI: graduation scale configuration
  final GraduationSide graduationSide;
  final double scaleMajorTickMeters;
  final int scaleMinorDivisions;
  // History: when true, readings are posted to backend for charts
  final bool storeHistory;
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
    this.wallThickness = 0.0,
    this.username,
    this.password,
    this.minThreshold,
    this.maxThreshold,
    required this.projectName,
  this.projectId,
    this.multiplier = 1.0,
    this.offset = 0.0,
    this.connectedTankCount = 1,
  this.useControlButton = false,
  this.controlTopic,
  this.controlMode = ControlMode.toggle,
  this.onValue = 'ON',
  this.offValue = 'OFF',
  this.autoControl = false,
  this.controlRetained = false,
  this.controlQos = MqttQosLevel.atLeastOnce,
  this.lastWillTopic,
  this.payloadIsJson = false,
  this.jsonFieldIndex = 1,
  this.jsonKeyName,
  this.displayTimeFromJson = false,
  this.jsonTimeFieldIndex = 1,
  this.jsonTimeKeyName,
  this.useCustomFormula = false,
  this.customFormula,
  this.graduationSide = GraduationSide.left,
  this.scaleMajorTickMeters = 0.1,
  this.scaleMinorDivisions = 4,
  this.storeHistory = false,
  });

  @override
  State<MainTankPage> createState() => _MainTankPageState();
}

class _MainTankPageState extends State<MainTankPage> {
  // Consider data stale if no message has arrived within this window while connected.
  // Increase if your sensors publish infrequently.
  static const int _staleThresholdSeconds = 60;
  static const MethodChannel _settingsChannel = MethodChannel('app.settings.channel');
  static const MethodChannel _serviceChannel = MethodChannel('app.mqtt.service');
  MqttService? _mqttService;
  double? _lastNotifiedHigh;
  double? _lastNotifiedLow;

  double _level = 0.0; // computed level in meters (liquid height from bottom)
  Timer? _heartbeatTimer;
  String _connectionStatus = 'Disconnected';
  String? _presenceStatus; // presence from last will topic, if configured
  bool _isOn = false; // current state for on/off or last state for toggle
  DateTime? _lastTimestamp; // last parsed timestamp
  DateTime? _lastMessageAt; // last MQTT data time for stale detection
  Timer? _staleTimer;
  late final _LifecycleHook _lifecycleHook;
  // presence handled via _connectionStatus cloud icon
  // History/graph reads from backend only; app no longer posts to backend.

  @override
  void initState() {
    super.initState();
  _lifecycleHook = _LifecycleHook(onChange: _handleLifecycle);
  WidgetsBinding.instance.addObserver(_lifecycleHook);
    _initMqttService();
    // start native foreground service for notifications when app closed
    if (enableNativeForegroundService) {
      _startNativeService();
    }
    debugPrint('Skipping bridge registration in MainTankPage.initState (local notifications only)');
    _startStaleMonitor();
    // No backend registration or writes from the app. Backend/firmware handles storage.
  }

  Future<void> _initMqttService() async {
    final s = await getGlobalMqttSettings();
    // Build service using global settings for broker/port/auth, keep per-project topic and parsing
    final svc = MqttService(
      s.broker,
      s.port,
      widget.topic,
      publishTopic: widget.controlTopic,
      lastWillTopic: widget.lastWillTopic,
      payloadIsJson: widget.payloadIsJson,
      jsonFieldIndex: widget.jsonFieldIndex,
      jsonKeyName: widget.jsonKeyName,
      displayTimeFromJson: widget.displayTimeFromJson,
      jsonTimeFieldIndex: widget.jsonTimeFieldIndex,
      jsonTimeKeyName: widget.jsonTimeKeyName,
      username: s.username,
      password: s.password,
      onMessage: _onMessage,
      onStatus: _onStatus,
      onPresence: _onPresence,
      onTimestamp: _onTimestamp,
    );
    if (!mounted) return;
    setState(() => _mqttService = svc);
    _mqttService?.connect();
  }

  void _handleLifecycle(AppLifecycleState state) {
    if (!mounted) return;
    if (state == AppLifecycleState.paused || state == AppLifecycleState.inactive) {
      // Intentionally pause without showing a red disconnect state in the UI
      if (_mqttService != null) {
        _mqttService!.disconnect();
      }
      setState(() { _connectionStatus = 'Paused'; });
    } else if (state == AppLifecycleState.resumed) {
      // Force a reconnect sequence
      _mqttService?.connect();
      setState(() { if (!_connectionStatus.toLowerCase().contains('connecting')) _connectionStatus = 'Reconnecting'; });
    }
  }

  void _startStaleMonitor() {
    _staleTimer?.cancel();
    _staleTimer = Timer.periodic(const Duration(seconds: 5), (_) {
      if (!mounted) return;
      final s = _connectionStatus.toLowerCase();
      final looksConnected = s.contains('connected') || s.contains('subscribed');
      if (looksConnected && _lastMessageAt != null) {
        final age = DateTime.now().difference(_lastMessageAt!);
        if (age.inSeconds > _staleThresholdSeconds) {
          setState(() { _connectionStatus = 'Stale'; });
        }
      }
    });
  }

  void _onTimestamp(DateTime ts) {
    if (!mounted) return;
    setState(() {
      _lastTimestamp = ts;
    });
  }

  void _onPresence(String status) {
    if (!mounted) return;
    setState(() {
  _presenceStatus = status;
      final ls = status.toLowerCase();
      if (ls.contains('connected')) {
        _connectionStatus = 'Connected';
      } else if (ls.contains('disconnected')) {
        _connectionStatus = 'Disconnected';
      } else {
        _connectionStatus = status;
      }
    });
  }

  Future<void> _publishControl(String value) async {
    await _mqttService?.publishJson(
      value,
      toTopic: widget.controlTopic,
      qos: _mapQos(widget.controlQos),
      retained: widget.controlRetained,
    );
  }

  // Map our simple enum to mqtt_client QoS
  mqtt.MqttQos _mapQos(MqttQosLevel q) {
    switch (q) {
      case MqttQosLevel.atMostOnce:
        return mqtt.MqttQos.atMostOnce;
      case MqttQosLevel.atLeastOnce:
        return mqtt.MqttQos.atLeastOnce;
      case MqttQosLevel.exactlyOnce:
        return mqtt.MqttQos.exactlyOnce;
    }
  }

  Future<void> _toggleOrSet() async {
    if (widget.controlMode == ControlMode.toggle) {
      // Locally flip for UI and send toggle command
      setState(() => _isOn = !_isOn);
  await _publishControl(widget.onValue);
    } else {
      // onOff: flip local and publish new value
      setState(() => _isOn = !_isOn);
  await _publishControl(_isOn ? widget.onValue : widget.offValue);
    }
  }

  @override
  void dispose() {
  WidgetsBinding.instance.removeObserver(_lifecycleHook);
  if (_mqttService != null) {
    _mqttService!.disconnect();
  }
    _heartbeatTimer?.cancel();
  _staleTimer?.cancel();
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
        'wallThickness': widget.wallThickness,
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
      final t = widget.wallThickness;
      // Compute inner vertical dimension depending on tank type
      final innerHeight = () {
        if (widget.tankType == TankType.horizontalCylinder) {
          return max(0.0, widget.diameter - 2 * t);
        } else {
          return max(0.0, widget.height - 2 * t);
        }
      }();
      // Interpret payload depending on sensor type
      if (widget.sensorType == SensorType.submersible) {
        // payload is the liquid level directly (meters from bottom)
        _level = correctedValue;
      } else {
        // ultrasonic: payload is distance from sensor to liquid surface
        // We assume sensor mounted at inner tank top; so level = innerHeight - distance
        _level = innerHeight - correctedValue;
      }
      // clamp to [0, tank height]
      if (_level.isNaN) _level = 0.0;
      if (widget.tankType == TankType.horizontalCylinder) {
        _level = _level.clamp(0.0, innerHeight);
      } else {
        _level = _level.clamp(0.0, innerHeight);
      }
      _lastMessageAt = DateTime.now();
    });

    // Update local repository cached volumes if projectId provided
    if (widget.projectId != null) {
      try {
        final repo = context.read<ProjectRepository>();
        final totalM3 = _totalVolumeM3();
        final liquidM3 = _liquidVolumeM3();
  repo.updateVolume(widget.projectId!, liquidM3 * 1000, totalM3 * 1000, DateTime.now());
        // Do not write readings to backend from app; storage handled by firmware/backend bridge.
      } catch (_) {}
    } else {
      // Fallback to legacy persistence for older routes without id
      _persistLatestVolumes();
    }

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

  // No _postReading: app does not write to backend. Graph screen fetches from backend for history.

  Future<void> _persistLatestVolumes() async {
    try {
      final prefs = await SharedPreferences.getInstance();
      final projectsStr = prefs.getString('projects');
      if (projectsStr == null) return;
      final list = Project.decode(projectsStr);
      final idx = list.indexWhere((p) => p.name == widget.projectName);
      if (idx < 0) return; // match by name (ids not passed into MainTankPage)
      final totalM3 = _totalVolumeM3();
      final liquidM3 = _liquidVolumeM3();
      final updated = list[idx].copyWith(
        lastTotalLiters: totalM3 * 1000,
        lastLiquidLiters: liquidM3 * 1000,
        lastUpdated: DateTime.now(),
      );
      list[idx] = updated;
      await prefs.setString('projects', Project.encode(list));
    } catch (_) {}
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

  String _two(int n) => n.toString().padLeft(2, '0');
  String _formatTs(DateTime dt) {
    final now = DateTime.now();
    final sameDay = now.year == dt.year && now.month == dt.month && now.day == dt.day;
    final hms = '${_two(dt.hour)}:${_two(dt.minute)}:${_two(dt.second)}';
    if (sameDay) return hms;
    return '${dt.year}-${_two(dt.month)}-${_two(dt.day)} $hms';
  }

  // Volume calculators
  double _totalVolumeM3() {
    // If using custom formula, evaluate with h=H to estimate total liters (capacity)
    if (widget.useCustomFormula == true && (widget.customFormula?.trim().isNotEmpty ?? false)) {
      try {
        final t = widget.wallThickness;
        final H = max(0.0, (widget.tankType == TankType.horizontalCylinder ? widget.diameter : widget.height) - 2 * t);
        final L = max(0.0, widget.length - 2 * t);
        final W = max(0.0, widget.width - 2 * t);
        final D = max(0.0, widget.diameter - 2 * t);
        final liters = _evalCustomFormulaLiters(
          widget.customFormula!,
          h: H, // treat full level using inner dimensions
          H: H,
          L: L,
          W: W,
          D: D,
          N: widget.connectedTankCount.toDouble(),
        );
        return max(0.0, liters) / 1000.0;
      } catch (e) {
        debugPrint('Custom total formula error: $e');
        // Fallback to geometry
      }
    }
    switch (widget.tankType) {
      case TankType.verticalCylinder:
        final t = widget.wallThickness;
        final r = max(0.0, (widget.diameter - 2.0 * t) / 2.0);
        final h = max(0.0, widget.height - 2.0 * t);
        return pi * r * r * h * widget.connectedTankCount;
      case TankType.horizontalCylinder:
        final t = widget.wallThickness;
        final r = max(0.0, (widget.diameter - 2.0 * t) / 2.0);
        final len = max(0.0, widget.length - 2.0 * t);
        return _horizontalCylinderVolume(r, len) * widget.connectedTankCount; // full volume
      case TankType.rectangle:
        final t = widget.wallThickness;
        final l = max(0.0, widget.length - 2.0 * t);
        final w = max(0.0, widget.width - 2.0 * t);
        final h = max(0.0, widget.height - 2.0 * t);
        return l * w * h * widget.connectedTankCount;
    }
  }

  double _liquidVolumeM3() {
    // If using custom formula, compute liters directly and convert to m^3
    if (widget.useCustomFormula == true && (widget.customFormula?.trim().isNotEmpty ?? false)) {
      try {
        final t = widget.wallThickness;
        final H = max(0.0, (widget.tankType == TankType.horizontalCylinder ? widget.diameter : widget.height) - 2 * t);
        final L = max(0.0, widget.length - 2 * t);
        final W = max(0.0, widget.width - 2 * t);
        final D = max(0.0, widget.diameter - 2 * t);
        final liters = _evalCustomFormulaLiters(
          widget.customFormula!,
          h: _level,
          H: H,
          L: L,
          W: W,
          D: D,
          N: widget.connectedTankCount.toDouble(),
        );
        return max(0.0, liters) / 1000.0; // convert L to m^3
      } catch (e) {
        debugPrint('Custom formula error: $e');
        // Fallback to geometry
      }
    }
  switch (widget.tankType) {
      case TankType.verticalCylinder:
        final t = widget.wallThickness;
        final r = max(0.0, (widget.diameter - 2.0 * t) / 2.0);
        return pi * r * r * (_level) * widget.connectedTankCount;
      case TankType.horizontalCylinder:
        final t = widget.wallThickness;
        final r = max(0.0, (widget.diameter - 2.0 * t) / 2.0);
        final A = _horizontalCylinderSectionArea(r, _level.clamp(0.0, 2.0 * r));
        final len = max(0.0, widget.length - 2.0 * t);
        return A * len * widget.connectedTankCount;
      case TankType.rectangle:
        final t = widget.wallThickness;
        final l = max(0.0, widget.length - 2.0 * t);
        final w = max(0.0, widget.width - 2.0 * t);
        return l * w * (_level) * widget.connectedTankCount;
    }
  }

  // Very small expression evaluator for +,-,*,/,(), variables.
  // This is intentionally limited; for complex needs, consider adding a parser library.
  double _evalCustomFormulaLiters(String expr, {required double h, required double H, required double L, required double W, required double D, required double N}) {
    // 1) Strip whitespace
    String s = expr.replaceAll(RegExp(r"\s+"), '');
  // 2) Tokenize into typed tokens using string kinds: 'num', 'op', 'l', 'r'
  final rawTokens = <Map<String, String>>[];
    int p = 0;
    while (p < s.length) {
      final ch = s[p];
      // Parentheses
      if (ch == '(') {
        rawTokens.add({'t': 'l', 'v': ch});
        p++;
        continue;
      }
      if (ch == ')') {
        rawTokens.add({'t': 'r', 'v': ch});
        p++;
        continue;
      }
      // Operators
      if ('+-*/'.contains(ch)) {
        rawTokens.add({'t': 'op', 'v': ch});
        p++;
        continue;
      }
      // Variables (support full words and case-insensitive)
      if (RegExp(r"[A-Za-z]").hasMatch(ch)) {
        final start = p;
        p++;
        while (p < s.length && RegExp(r"[A-Za-z]").hasMatch(s[p])) {
          p++;
        }
        final name = s.substring(start, p);
        final n = name.toLowerCase();
        double val;
        if (n == 'h' || n == 'level' || n == 'lvl') {
          val = h;
        } else if (n == 'h' || n == 'height' || n == 'hgt') {
          val = H;
        } else if (n == 'l' || n == 'length' || n == 'len') {
          val = L;
        } else if (n == 'w' || n == 'width' || n == 'wid') {
          val = W;
        } else if (n == 'd' || n == 'diameter' || n == 'dia') {
          val = D;
        } else if (n == 'n' || n == 'count' || n == 'tanks') {
          val = N;
        } else if (name == 'H') { // preserve uppercase single-letter
          val = H;
        } else if (name == 'L') {
          val = L;
        } else if (name == 'W') {
          val = W;
        } else if (name == 'D') {
          val = D;
        } else if (name == 'N') {
          val = N;
        } else {
          throw FormatException('Unknown variable: $name');
        }
        rawTokens.add({'t': 'num', 'v': val.toString()});
        continue;
      }
      // Numbers (support leading dot and decimals)
      if (RegExp(r"[0-9.]").hasMatch(ch)) {
        final start = p;
        p++;
        while (p < s.length && RegExp(r"[0-9.]").hasMatch(s[p])) {
          p++;
        }
        rawTokens.add({'t': 'num', 'v': s.substring(start, p)});
        continue;
      }
      throw FormatException('Unknown character in formula: $ch');
    }
    // 3) Insert implicit multiplication between [num|rparen] and [num|lparen]
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
    // 4) Convert to simple string tokens for parser
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
  Widget _statCard(String title, String value, {double width = 110, double minHeight = 68, bool dense = false}) {
    final theme = Theme.of(context);
    return Card(
      child: ConstrainedBox(
        constraints: BoxConstraints(minWidth: width, minHeight: minHeight),
        child: Padding(
          padding: const EdgeInsets.all(8.0),
          child: Column(
            crossAxisAlignment: CrossAxisAlignment.start,
            mainAxisAlignment: MainAxisAlignment.center,
            children: [
              Text(
                title,
                style: theme.textTheme.bodySmall?.copyWith(fontSize: dense ? 11 : null),
                maxLines: 1,
                overflow: TextOverflow.ellipsis,
              ),
              SizedBox(height: dense ? 4 : 6),
              Text(
                value,
                style: theme.textTheme.titleMedium?.copyWith(
                  fontWeight: FontWeight.bold,
                  fontSize: dense ? 14 : null,
                ),
                maxLines: 1,
                overflow: TextOverflow.ellipsis,
              ),
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
        title: _ScrollingTitle(text: widget.projectName),
        actions: [
          if (widget.lastWillTopic != null && widget.lastWillTopic!.trim().isNotEmpty)
      Padding(
              padding: const EdgeInsets.symmetric(horizontal: 4.0),
              child: Tooltip(
                message: _presenceStatus == null
                    ? 'Last Will configured'
                    : 'Presence: ${_presenceStatus!}',
        child: Icon(
          // Presence icon mapping to link-style glyphs
          (_presenceStatus ?? '').toLowerCase().contains('connected') || (_presenceStatus ?? '').toLowerCase().contains('online')
            ? Icons.link
            : (_presenceStatus ?? '').toLowerCase().contains('disconnected') || (_presenceStatus ?? '').toLowerCase().contains('offline')
              ? Icons.link_off
              : Icons.link_outlined,
          color: (_presenceStatus ?? '').toLowerCase().contains('connected') || (_presenceStatus ?? '').toLowerCase().contains('online')
            ? Colors.green
            : (_presenceStatus ?? '').toLowerCase().contains('disconnected') || (_presenceStatus ?? '').toLowerCase().contains('offline')
              ? Colors.red
              : Colors.amber,
          size: 20,
        ),
              ),
            ),
          Padding(
            padding: const EdgeInsets.symmetric(horizontal: 4.0),
            child: Tooltip(
              message: _connectionStatus,
              child: Icon(
                _connectionStatus.toLowerCase().contains('connected') || _connectionStatus.toLowerCase().contains('subscribed')
                    ? Icons.cloud_done
                    : (_connectionStatus.toLowerCase().contains('connecting') || _connectionStatus.toLowerCase().contains('stale'))
                        ? Icons.cloud_queue
                        : Icons.cloud_off,
                color: _connectionStatus.toLowerCase().contains('connected') || _connectionStatus.toLowerCase().contains('subscribed')
                    ? Colors.green
                    : (_connectionStatus.toLowerCase().contains('connecting') || _connectionStatus.toLowerCase().contains('stale'))
                        ? Colors.amber
                        : Colors.red,
                size: 20,
              ),
            ),
          ),
          // Removed bell icon per request
        ],
      ),
      body: Padding(
        padding: const EdgeInsets.all(12),
        child: LayoutBuilder(
          builder: (context, constraints) {
            // Base sizes
            const double baseCloudH = 30; // approx chip height
            const double baseStatH = 68;
            const double baseRowGap = 8; // gap between rows and after chip
            const double baseTankH = 260; // reverted to previous visual size
            const double baseBeforeTank = 16;
            const double baseAfterTank = 12;
            const double baseButtonH = 44;
            const double baseAfterButton = 12;

            final bool hasControl = widget.useControlButton;
      final double baseTotal =
        baseCloudH +
        baseStatH * 2 + // two stat rows
        baseRowGap * 2 + // after chip + between stat rows
                baseBeforeTank +
                baseTankH +
                baseAfterTank +
                (hasControl ? baseButtonH + baseAfterButton : 0) +
                40; // Back button approx

            final double scale = (constraints.maxHeight / baseTotal).clamp(0.75, 1.0);
            final double statH = baseStatH * scale;
            final double tankH = baseTankH * scale;
            final double rowGap = baseRowGap * scale;
            final double beforeTank = baseBeforeTank * scale;
            final double afterTank = baseAfterTank * scale;
            final double btnH = baseButtonH * scale;
            final double afterBtn = baseAfterButton * scale;
            final bool dense = scale < 0.95;

      // Map connection status to UI
            // connection status used in AppBar cloud icon tooltip; no body UI here

            final isLandscape = constraints.maxWidth > constraints.maxHeight;

            Widget statsAndControls() {
              return SingleChildScrollView(
                child: Column(
                  crossAxisAlignment: CrossAxisAlignment.stretch,
                  children: [
                    // Last update + first stats row
                    MediaQuery(
                      data: MediaQuery.of(context).copyWith(textScaler: const TextScaler.linear(1.0)),
                      child: Column(
                        children: [
                          if (widget.displayTimeFromJson && _lastTimestamp != null) ...[
                            Padding(
                              padding: EdgeInsets.only(bottom: rowGap * 0.75),
                              child: Align(
                                alignment: Alignment.center,
                                child: Text(
                                  'Last update: ${_formatTs(_lastTimestamp!)}',
                                  textAlign: TextAlign.center,
                                  style: Theme.of(context).textTheme.bodyMedium,
                                  overflow: TextOverflow.ellipsis,
                                  maxLines: 1,
                                ),
                              ),
                            ),
                          ],
                          Row(
                            mainAxisAlignment: MainAxisAlignment.spaceAround,
                            children: [
                              _statCard('Liquid%', '${percent.toStringAsFixed(1)} %', minHeight: statH, dense: dense),
                              _statCard('Level (m)', '${_level.toStringAsFixed(3)} m', minHeight: statH, dense: dense),
                              _statCard('Empty (m)', (widget.height - _level).toStringAsFixed(3), minHeight: statH, dense: dense),
                            ],
                          ),
                        ],
                      ),
                    ),
                    SizedBox(height: rowGap),
                    MediaQuery(
                      data: MediaQuery.of(context).copyWith(textScaler: const TextScaler.linear(1.0)),
                      child: Row(
                        mainAxisAlignment: MainAxisAlignment.spaceAround,
                        children: [
                          _statCard('Total L', '${(totalM3 * 1000).toStringAsFixed(2)} L', minHeight: statH, dense: dense),
                          _statCard('Liquid L', '${(liquidM3 * 1000).toStringAsFixed(2)} L', minHeight: statH, dense: dense),
                          _statCard('Empty L', '${(emptyM3 * 1000).toStringAsFixed(2)} L', minHeight: statH, dense: dense),
                        ],
                      ),
                    ),
                    SizedBox(height: isLandscape ? rowGap : beforeTank),
                    if (hasControl)
                      Row(
                        mainAxisAlignment: MainAxisAlignment.center,
                        children: [
                          SizedBox(
                            height: btnH,
                            child: FilledButton(
                              onPressed: _toggleOrSet,
                              style: FilledButton.styleFrom(
                                backgroundColor: _isOn ? Colors.green : Colors.grey,
                                foregroundColor: _isOn ? Colors.white : Colors.black87,
                                minimumSize: Size(140 * scale, btnH),
                              ),
                              child: Text(_isOn ? 'ON' : 'OFF'),
                            ),
                          ),
                        ],
                      ),
                    if (hasControl) SizedBox(height: afterBtn),
                    ElevatedButton(
                      onPressed: () {
                        Navigator.pushReplacement(
                          context,
                          MaterialPageRoute(builder: (_) => const ProjectListPage()),
                        );
                      },
                      child: const Text('Back to Projects'),
                    ),
                  ],
                ),
              );
            }

            if (!isLandscape) {
              // Portrait: original vertical layout (stats -> tank -> controls)
              return Column(
                crossAxisAlignment: CrossAxisAlignment.center,
                children: [
                  // Keep same as before but reuse statsAndControls without the tank
                  MediaQuery(
                    data: MediaQuery.of(context).copyWith(textScaler: const TextScaler.linear(1.0)),
                    child: Column(
                      children: [
                        if (widget.displayTimeFromJson && _lastTimestamp != null) ...[
                          Padding(
                            padding: EdgeInsets.only(bottom: rowGap * 0.75),
                            child: Align(
                              alignment: Alignment.center,
                              child: Text(
                                'Last update: ${_formatTs(_lastTimestamp!)}',
                                textAlign: TextAlign.center,
                                style: Theme.of(context).textTheme.bodyMedium,
                                overflow: TextOverflow.ellipsis,
                                maxLines: 1,
                              ),
                            ),
                          ),
                        ],
                        Row(
                          mainAxisAlignment: MainAxisAlignment.spaceAround,
                          children: [
                            _statCard('Liquid%', '${percent.toStringAsFixed(1)} %', minHeight: statH, dense: dense),
                            _statCard('Level (m)', '${_level.toStringAsFixed(3)} m', minHeight: statH, dense: dense),
                            _statCard('Empty (m)', (widget.height - _level).toStringAsFixed(3), minHeight: statH, dense: dense),
                          ],
                        ),
                      ],
                    ),
                  ),
                  SizedBox(height: rowGap),
                  MediaQuery(
                    data: MediaQuery.of(context).copyWith(textScaler: const TextScaler.linear(1.0)),
                    child: Row(
                      mainAxisAlignment: MainAxisAlignment.spaceAround,
                      children: [
                        _statCard('Total L', '${(totalM3 * 1000).toStringAsFixed(2)} L', minHeight: statH, dense: dense),
                        _statCard('Liquid L', '${(liquidM3 * 1000).toStringAsFixed(2)} L', minHeight: statH, dense: dense),
                        _statCard('Empty L', '${(emptyM3 * 1000).toStringAsFixed(2)} L', minHeight: statH, dense: dense),
                      ],
                    ),
                  ),
                  SizedBox(height: beforeTank),
                  Center(
                    child: SizedBox(
                      height: tankH,
                      width: (tankH * 0.65).clamp(140.0, 200.0),
                      child: GestureDetector(
                        onTap: () {
                          if (widget.storeHistory) {
                            Navigator.of(context).push(
                              MaterialPageRoute(
                                builder: (_) => HistoryChartPage(
                                  project: Project(
                                    id: widget.projectId ?? widget.projectName, // fallback id
                                    name: widget.projectName,
                                    broker: widget.broker,
                                    port: widget.port,
                                    topic: widget.topic,
                                    username: widget.username,
                                    password: widget.password,
                                    sensorType: widget.sensorType,
                                    tankType: widget.tankType,
                                    height: widget.height,
                                    diameter: widget.diameter,
                                    length: widget.length,
                                    width: widget.width,
                                    wallThickness: widget.wallThickness,
                                    minThreshold: widget.minThreshold,
                                    maxThreshold: widget.maxThreshold,
                                    multiplier: widget.multiplier,
                                    offset: widget.offset,
                                    connectedTankCount: widget.connectedTankCount,
                                    useCustomFormula: widget.useCustomFormula,
                                    customFormula: widget.customFormula,
                                    useControlButton: widget.useControlButton,
                                    controlTopic: widget.controlTopic,
                                    controlMode: widget.controlMode,
                                    onValue: widget.onValue,
                                    offValue: widget.offValue,
                                    autoControl: widget.autoControl,
                                    controlRetained: widget.controlRetained,
                                    controlQos: widget.controlQos,
                                    lastWillTopic: widget.lastWillTopic,
                                    payloadIsJson: widget.payloadIsJson,
                                    jsonFieldIndex: widget.jsonFieldIndex,
                                    jsonKeyName: widget.jsonKeyName,
                                    displayTimeFromJson: widget.displayTimeFromJson,
                                    jsonTimeFieldIndex: widget.jsonTimeFieldIndex,
                                    jsonTimeKeyName: widget.jsonTimeKeyName,
                                    graduationSide: widget.graduationSide,
                                    scaleMajorTickMeters: widget.scaleMajorTickMeters,
                                    scaleMinorDivisions: widget.scaleMinorDivisions,
                                    storeHistory: widget.storeHistory,
                                  ),
                                ),
                              ),
                            );
                          }
                        },
                        child: TankWidget(
                        tankType: widget.tankType,
                        waterLevel: _level / widget.height,
                        minThreshold: widget.minThreshold != null ? widget.minThreshold! / widget.height : null,
                        maxThreshold: widget.maxThreshold != null ? widget.maxThreshold! / widget.height : null,
                        volume: liquidM3 * 1000,
                        percentage: percent,
                        graduationSide: widget.graduationSide,
                        majorTickMeters: (widget.scaleMajorTickMeters > 0 ? widget.scaleMajorTickMeters : 0.1) / (widget.height <= 0 ? 1.0 : widget.height),
                        minorDivisions: widget.scaleMinorDivisions,
                        fullHeightMeters: widget.height,
                        capacityLiters: _totalVolumeM3() * 1000,
            innerCylinderDiameterMeters: widget.tankType == TankType.horizontalCylinder
              ? max(0.0, widget.diameter - 2.0 * widget.wallThickness)
              : null,
                        ),
                      ),
                    ),
                  ),
                  SizedBox(height: afterTank),
                  if (hasControl)
                    Row(
                      mainAxisAlignment: MainAxisAlignment.center,
                      children: [
                        SizedBox(
                          height: btnH,
                          child: FilledButton(
                            onPressed: _toggleOrSet,
                            style: FilledButton.styleFrom(
                              backgroundColor: _isOn ? Colors.green : Colors.grey,
                              foregroundColor: _isOn ? Colors.white : Colors.black87,
                              minimumSize: Size(140 * scale, btnH),
                            ),
                            child: Text(_isOn ? 'ON' : 'OFF'),
                          ),
                        ),
                      ],
                    ),
                  if (hasControl) SizedBox(height: afterBtn),
                  ElevatedButton(
                    onPressed: () {
                      Navigator.pushReplacement(
                        context,
                        MaterialPageRoute(builder: (_) => const ProjectListPage()),
                      );
                    },
                    child: const Text('Back to Projects'),
                  ),
                ],
              );
            }

            // Landscape: Row with tank on the left and widgets on the right
            return Row(
              children: [
                // Left: Tank
                Expanded(
                  flex: 1,
                  child: Center(
                    child: SizedBox(
                      height: tankH,
                      width: (tankH * 0.8).clamp(160.0, 300.0),
                      child: GestureDetector(
                        onTap: () {
                          if (widget.storeHistory) {
                            Navigator.of(context).push(
                              MaterialPageRoute(
                                builder: (_) => HistoryChartPage(
                                  project: Project(
                                    id: widget.projectId ?? widget.projectName,
                                    name: widget.projectName,
                                    broker: widget.broker,
                                    port: widget.port,
                                    topic: widget.topic,
                                    username: widget.username,
                                    password: widget.password,
                                    sensorType: widget.sensorType,
                                    tankType: widget.tankType,
                                    height: widget.height,
                                    diameter: widget.diameter,
                                    length: widget.length,
                                    width: widget.width,
                                    wallThickness: widget.wallThickness,
                                    minThreshold: widget.minThreshold,
                                    maxThreshold: widget.maxThreshold,
                                    multiplier: widget.multiplier,
                                    offset: widget.offset,
                                    connectedTankCount: widget.connectedTankCount,
                                    useCustomFormula: widget.useCustomFormula,
                                    customFormula: widget.customFormula,
                                    useControlButton: widget.useControlButton,
                                    controlTopic: widget.controlTopic,
                                    controlMode: widget.controlMode,
                                    onValue: widget.onValue,
                                    offValue: widget.offValue,
                                    autoControl: widget.autoControl,
                                    controlRetained: widget.controlRetained,
                                    controlQos: widget.controlQos,
                                    lastWillTopic: widget.lastWillTopic,
                                    payloadIsJson: widget.payloadIsJson,
                                    jsonFieldIndex: widget.jsonFieldIndex,
                                    jsonKeyName: widget.jsonKeyName,
                                    displayTimeFromJson: widget.displayTimeFromJson,
                                    jsonTimeFieldIndex: widget.jsonTimeFieldIndex,
                                    jsonTimeKeyName: widget.jsonTimeKeyName,
                                    graduationSide: widget.graduationSide,
                                    scaleMajorTickMeters: widget.scaleMajorTickMeters,
                                    scaleMinorDivisions: widget.scaleMinorDivisions,
                                    storeHistory: widget.storeHistory,
                                  ),
                                ),
                              ),
                            );
                          }
                        },
                        child: TankWidget(
                        tankType: widget.tankType,
                        waterLevel: _level / widget.height,
                        minThreshold: widget.minThreshold != null ? widget.minThreshold! / widget.height : null,
                        maxThreshold: widget.maxThreshold != null ? widget.maxThreshold! / widget.height : null,
                        volume: liquidM3 * 1000,
                        percentage: percent,
                        graduationSide: widget.graduationSide,
                        majorTickMeters: (widget.scaleMajorTickMeters > 0 ? widget.scaleMajorTickMeters : 0.1) / (widget.height <= 0 ? 1.0 : widget.height),
                        minorDivisions: widget.scaleMinorDivisions,
                        fullHeightMeters: widget.height,
                        capacityLiters: _totalVolumeM3() * 1000,
            innerCylinderDiameterMeters: widget.tankType == TankType.horizontalCylinder
              ? max(0.0, widget.diameter - 2.0 * widget.wallThickness)
              : null,
                        ),
                      ),
                    ),
                  ),
                ),
                const SizedBox(width: 12),
                // Right: Stats & controls
                Expanded(
                  flex: 1,
                  child: statsAndControls(),
                ),
              ],
            );
          },
        ),
      ),
    );
  }
}

class _LifecycleHook with WidgetsBindingObserver {
  final void Function(AppLifecycleState state) onChange;
  _LifecycleHook({required this.onChange});
  @override
  void didChangeAppLifecycleState(AppLifecycleState state) {
    onChange(state);
  }
}

// Scrolling title (marquee) for long project names in AppBar
class _ScrollingTitle extends StatefulWidget {
  final String text;
  const _ScrollingTitle({required this.text});
  @override
  State<_ScrollingTitle> createState() => _ScrollingTitleState();
}

class _ScrollingTitleState extends State<_ScrollingTitle> with SingleTickerProviderStateMixin {
  late final ScrollController _scrollController;
  late final AnimationController _controller;
  double _textWidth = 0;
  double _lastTotalWidth = -1;
  static const double _gap = 48; // px gap between copies
  static const double _pxPerSecond = 60; // scroll speed

  @override
  void initState() {
    super.initState();
    _scrollController = ScrollController();
    _controller = AnimationController(vsync: this);

    _controller.addStatusListener((status) {
      if (status == AnimationStatus.completed) {
        _controller.forward(from: 0.0);
      }
    });
    _controller.addListener(() {
      if (!_scrollController.hasClients) return;
      final totalWidth = _textWidth + _gap;
      final double offset = _controller.value * totalWidth;
      _scrollController.jumpTo(offset);
    });
  }

  void _restartMarquee(double totalWidth) {
    _lastTotalWidth = totalWidth;
    final ms = (totalWidth / _pxPerSecond * 1000).clamp(800, 60000).toInt();
    _controller.duration = Duration(milliseconds: ms);
    if (mounted) {
      WidgetsBinding.instance.addPostFrameCallback((_) {
        if (!_scrollController.hasClients) return;
        _scrollController.jumpTo(0);
        _controller.forward(from: 0.0);
      });
    }
  }

  @override
  void dispose() {
    _controller.dispose();
    _scrollController.dispose();
    super.dispose();
  }

  @override
  Widget build(BuildContext context) {
    final style = Theme.of(context).textTheme.titleLarge;
    return LayoutBuilder(
      builder: (context, constraints) {
        // Measure text width
        final tp = TextPainter(
          text: TextSpan(text: widget.text, style: style),
          textDirection: TextDirection.ltr,
          maxLines: 1,
        )..layout();
        _textWidth = tp.width;

        final needsScroll = _textWidth > constraints.maxWidth;
        if (!needsScroll) {
          // Stop animation when not needed
          if (_controller.isAnimating) _controller.stop();
          return Text(widget.text, style: style, overflow: TextOverflow.ellipsis, maxLines: 1);
        }

        final totalWidth = _textWidth + _gap; // distance to loop
        if (_lastTotalWidth != totalWidth) {
          _restartMarquee(totalWidth);
        } else if (!_controller.isAnimating) {
          _controller.forward(from: 0.0);
        }

        // Scrollable viewport prevents overflow while we animate the offset
        return SizedBox(
          height: kToolbarHeight,
          child: ClipRect(
            child: SingleChildScrollView(
              controller: _scrollController,
              scrollDirection: Axis.horizontal,
              physics: const NeverScrollableScrollPhysics(),
              child: Row(
                children: [
                  Text(widget.text, style: style),
                  const SizedBox(width: _gap),
                  Text(widget.text, style: style), // second copy for seamless loop
                ],
              ),
            ),
          ),
        );
      },
    );
  }
}
