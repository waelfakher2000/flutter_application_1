import 'dart:async';
import 'dart:io';
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
