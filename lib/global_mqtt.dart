import 'package:shared_preferences/shared_preferences.dart';

class GlobalMqttSettings {
  final String broker;
  final int port;
  final String? username;
  final String? password;

  const GlobalMqttSettings({
    required this.broker,
    required this.port,
    this.username,
    this.password,
  });
}

// Default settings requested by user
const String _kDefaultBroker = 'mqttapi.mautoiot.com';
const int _kDefaultPort = 1883;
const String _kDefaultUser = 'user';
const String _kDefaultPass = '123456';

const String _kKeyBroker = 'global_mqtt_broker';
const String _kKeyPort = 'global_mqtt_port';
const String _kKeyUser = 'global_mqtt_username';
const String _kKeyPass = 'global_mqtt_password';

Future<GlobalMqttSettings> getGlobalMqttSettings() async {
  final prefs = await SharedPreferences.getInstance();
  final broker = prefs.getString(_kKeyBroker) ?? _kDefaultBroker;
  final port = prefs.getInt(_kKeyPort) ?? _kDefaultPort;
  final user = prefs.getString(_kKeyUser) ?? _kDefaultUser;
  final pass = prefs.getString(_kKeyPass) ?? _kDefaultPass;
  return GlobalMqttSettings(
    broker: broker,
    port: port,
    username: user.isEmpty ? null : user,
    password: pass.isEmpty ? null : pass,
  );
}

Future<void> setGlobalMqttSettings(GlobalMqttSettings s) async {
  final prefs = await SharedPreferences.getInstance();
  await prefs.setString(_kKeyBroker, s.broker);
  await prefs.setInt(_kKeyPort, s.port);
  await prefs.setString(_kKeyUser, s.username ?? '');
  await prefs.setString(_kKeyPass, s.password ?? '');
}
