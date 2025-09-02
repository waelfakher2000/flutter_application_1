import 'dart:convert';
import 'package:flutter_application_1/types.dart';
import 'package:uuid/uuid.dart';

class Project {
  String id;
  String name;
  String broker;
  int port;
  String topic;
  String? username;
  String? password;
  SensorType sensorType;
  TankType tankType;
  double height;
  double diameter;
  double length;
  double width;
  double? minThreshold;
  double? maxThreshold;
  double multiplier;
  double offset;
  // Control button settings
  bool useControlButton;
  String? controlTopic; // topic to publish to
  ControlMode controlMode;
  String onValue;
  String offValue;
  bool autoControl; // use min/max thresholds to auto toggle
  bool controlRetained; // publish retained
  MqttQosLevel controlQos; // publish QoS

  Project({
    String? id,
    required this.name,
    required this.broker,
    required this.port,
    required this.topic,
    this.username,
    this.password,
    required this.sensorType,
    required this.tankType,
    required this.height,
    required this.diameter,
    required this.length,
    required this.width,
    this.minThreshold,
    this.maxThreshold,
    this.multiplier = 1.0,
    this.offset = 0.0,
  this.useControlButton = false,
  this.controlTopic,
  this.controlMode = ControlMode.toggle,
  this.onValue = 'ON',
  this.offValue = 'OFF',
  this.autoControl = false,
  this.controlRetained = false,
  this.controlQos = MqttQosLevel.atLeastOnce,
  }) : id = id ?? const Uuid().v4();

  Map<String, dynamic> toJson() {
    return {
      'id': id,
      'name': name,
      'broker': broker,
      'port': port,
      'topic': topic,
      'username': username,
      'password': password,
      'sensorType': sensorType.toString(),
      'tankType': tankType.toString(),
      'height': height,
      'diameter': diameter,
      'length': length,
      'width': width,
      'minThreshold': minThreshold,
      'maxThreshold': maxThreshold,
      'multiplier': multiplier,
      'offset': offset,
  'useControlButton': useControlButton,
  'controlTopic': controlTopic,
  'controlMode': controlMode.toString(),
  'onValue': onValue,
  'offValue': offValue,
  'autoControl': autoControl,
  'controlRetained': controlRetained,
  'controlQos': controlQos.toString(),
    };
  }

  factory Project.fromJson(Map<String, dynamic> json) {
    return Project(
      id: json['id'],
      name: json['name'],
      broker: json['broker'],
      port: json['port'],
      topic: json['topic'],
      username: json['username'],
      password: json['password'],
      sensorType: SensorType.values.firstWhere((e) => e.toString() == json['sensorType'], orElse: () => SensorType.submersible),
      tankType: TankType.values.firstWhere((e) => e.toString() == json['tankType'], orElse: () => TankType.verticalCylinder),
      height: json['height']?.toDouble() ?? 0.0,
      diameter: json['diameter']?.toDouble() ?? 0.0,
      length: json['length']?.toDouble() ?? 0.0,
      width: json['width']?.toDouble() ?? 0.0,
      minThreshold: json['minThreshold']?.toDouble(),
      maxThreshold: json['maxThreshold']?.toDouble(),
      multiplier: json['multiplier']?.toDouble() ?? 1.0,
      offset: json['offset']?.toDouble() ?? 0.0,
      useControlButton: json['useControlButton'] == true,
      controlTopic: json['controlTopic'],
      controlMode: ControlMode.values.firstWhere(
        (e) => e.toString() == (json['controlMode'] ?? ControlMode.toggle.toString()),
        orElse: () => ControlMode.toggle,
      ),
      onValue: (json['onValue'] ?? 'ON').toString(),
      offValue: (json['offValue'] ?? 'OFF').toString(),
      autoControl: json['autoControl'] == true,
      controlRetained: json['controlRetained'] == true,
      controlQos: MqttQosLevel.values.firstWhere(
        (e) => e.toString() == (json['controlQos'] ?? MqttQosLevel.atLeastOnce.toString()),
        orElse: () => MqttQosLevel.atLeastOnce,
      ),
    );
  }

  static String encode(List<Project> projects) => json.encode(
        projects
            .map<Map<String, dynamic>>((project) => project.toJson())
            .toList(),
      );

  static List<Project> decode(String projects) =>
      (json.decode(projects) as List<dynamic>)
          .map<Project>((item) => Project.fromJson(item))
          .toList();
}
