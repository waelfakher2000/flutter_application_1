import 'dart:async';
import 'dart:io';
import 'dart:convert';
import 'dart:math';
import 'package:flutter/foundation.dart' show kIsWeb;
import 'package:mqtt_client/mqtt_client.dart' as mqtt;
import 'package:mqtt_client/mqtt_browser_client.dart' show MqttBrowserClient;
import 'package:mqtt_client/mqtt_server_client.dart' show MqttServerClient;
import 'package:flutter/material.dart';

class MqttService {
  final String broker;
  final int port;
  final String topic;
  final String? publishTopic; // optional control topic
  final String? lastWillTopic; // optional presence/last will topic to subscribe
  final bool payloadIsJson; // interpret main topic payload as JSON
  final int jsonFieldIndex; // 1-based field order to extract numeric value
  final String? jsonKeyName; // optional key name to extract value
  final String? username;
  final String? password;
  final void Function(double) onMessage;
  final void Function(String) onStatus;
  final void Function(String status)? onPresence;

  late mqtt.MqttClient client;
  int _reconnectAttempts = 0;
  bool _shouldReconnect = true;
  bool _isConnecting = false;
  Timer? _reconnectTimer;

    MqttService(
    this.broker,
    this.port,
  this.topic, {
  this.publishTopic,
  this.lastWillTopic,
    this.payloadIsJson = false,
    this.jsonFieldIndex = 1,
  this.jsonKeyName,
    this.username,
    this.password,
    required this.onMessage,
    required this.onStatus,
    this.onPresence,
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

  // Publish a simple JSON payload {"value": <value>, "timestamp": <iso8601>} to publishTopic or provided topic
  Future<void> publishJson(
    String value, {
    String? toTopic,
    mqtt.MqttQos qos = mqtt.MqttQos.atLeastOnce,
    bool retained = false,
  }) async {
    final t = (toTopic ?? publishTopic);
    if (t == null || t.trim().isEmpty) return;
    try {
      if (client.connectionStatus?.state != mqtt.MqttConnectionState.connected) return;
      final payloadMap = {
        'value': value,
        'timestamp': DateTime.now().toIso8601String(),
      };
      final builder = mqtt.MqttClientPayloadBuilder();
      builder.addString(jsonEncode(payloadMap));
  client.publishMessage(t, qos, builder.payload!, retain: retained);
    } catch (e) {
      debugPrint('MQTT publish error: $e');
    }
  }

  Future<void> connect() async {
  if (_isConnecting) return;
  _isConnecting = true;
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
  _reconnectTimer?.cancel();
  _isConnecting = false;
      onStatus('Connected');
      _subscribe();
      client.updates?.listen(_onMessage);
    } on SocketException catch (se, st) {
      debugPrint('MQTT SocketException: $se');
      debugPrint('$st');
      onStatus('Network error: ${se.message}');
  _isConnecting = false;
  _scheduleReconnect();
    } catch (e, st) {
      debugPrint('MQTT connect error: $e');
      debugPrint('$st');
      onStatus('Error: $e');
  _isConnecting = false;
  _scheduleReconnect();
    }
  }

  void _subscribe() {
    client.subscribe(topic, mqtt.MqttQos.atMostOnce);
    onStatus('Subscribed to $topic');
    if (lastWillTopic != null && lastWillTopic!.trim().isNotEmpty) {
      client.subscribe(lastWillTopic!, mqtt.MqttQos.atMostOnce);
      onStatus('Subscribed to $lastWillTopic');
    }
  }

  void _onMessage(List<mqtt.MqttReceivedMessage<mqtt.MqttMessage>>? event) {
    if (event == null || event.isEmpty) return;
    final msg = event[0];
    final recMess = msg.payload as mqtt.MqttPublishMessage;
    final payload = mqtt.MqttPublishPayload.bytesToStringAsString(recMess.payload.message);
    final topicStr = msg.topic;

    // If this is presence/last-will topic, parse JSON and emit status
    if (lastWillTopic != null && topicStr == lastWillTopic && onPresence != null) {
      try {
        final decoded = jsonDecode(payload);
        if (decoded is Map && decoded['status'] != null) {
          final status = decoded['status'].toString();
          onPresence!(status);
          return;
        }
      } catch (_) {}
      // If not JSON or no status, ignore
      return;
    }

    // Otherwise handle main numeric topic
    if (topicStr == topic) {
      if (payloadIsJson) {
        final val = _extractFromJson(payload, jsonFieldIndex, jsonKeyName);
        if (val != null) onMessage(val);
      } else {
        final value = double.tryParse(payload.trim());
        if (value != null) {
          onMessage(value);
        } else {
          final maybe = _extractFirstNumber(payload);
          if (maybe != null) onMessage(maybe);
        }
      }
    }
  }

  double? _extractFirstNumber(String s) {
    final regex = RegExp(r'[-+]?[0-9]*\.?[0-9]+');
    final match = regex.firstMatch(s);
    if (match != null) return double.tryParse(match.group(0)!);
    return null;
  }

  double? _extractFromJson(String s, int order, String? keyName) {
    try {
      final decoded = jsonDecode(s);
      if (decoded is Map) {
        if (keyName != null && keyName.trim().isNotEmpty) {
          final v = decoded[keyName];
          if (v is num) return v.toDouble();
          if (v is String) return double.tryParse(v.trim());
          return null;
        }
        // Fallback by field order
        final entries = decoded.entries.toList(growable: false);
        if (order <= 0 || order > entries.length) return null;
        final v = entries[order - 1].value;
        if (v is num) return v.toDouble();
        // Try parse string values
        if (v is String) return double.tryParse(v.trim());
        return null;
      }
      // If array, allow order indexing too
      if (decoded is List) {
        if (order <= 0 || order > decoded.length) return null;
        final v = decoded[order - 1];
        if (v is num) return v.toDouble();
        if (v is String) return double.tryParse(v.trim());
        return null;
      }
    } catch (_) {}
    return null;
  }

  void _onDisconnected() {
    onStatus('Disconnected');
    _isConnecting = false;
    _scheduleReconnect();
  }
  void _onConnected() => onStatus('Connected');

  void disconnect() {
    _shouldReconnect = false;
    _reconnectTimer?.cancel();
    try {
      client.disconnect();
    } catch (_) {}
  }

  void _scheduleReconnect() {
    if (!_shouldReconnect) return;
    if (client.connectionStatus?.state == mqtt.MqttConnectionState.connected) return;
    if (_isConnecting) return;
    _reconnectAttempts = (_reconnectAttempts + 1).clamp(1, 30);
    final base = (pow(2, _reconnectAttempts) as double).clamp(1, 30).toInt();
    final jitter = (base / 4).clamp(0, 5).toInt();
    final delaySeconds = base + (jitter > 0 ? (DateTime.now().millisecondsSinceEpoch % jitter) : 0);
    _reconnectTimer?.cancel();
    _reconnectTimer = Timer(Duration(seconds: delaySeconds), () {
      if (!_shouldReconnect) return;
      connect();
    });
  }
}
