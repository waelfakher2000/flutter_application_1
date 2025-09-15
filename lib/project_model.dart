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
  // Tank wall thickness (meters). Used to compute inner dimensions.
  double wallThickness;
  double? minThreshold;
  double? maxThreshold;
  double multiplier;
  double offset;
  int connectedTankCount; // number of identical connected tanks sharing same level (>=1)
  // Custom liters formula (user-defined)
  bool useCustomFormula; // when true, use customFormula to compute liters
  String? customFormula; // expression evaluated in liters using variables h,H,L,W,D,N
  // Control button settings
  bool useControlButton;
  String? controlTopic; // topic to publish to
  ControlMode controlMode;
  String onValue;
  String offValue;
  bool autoControl; // use min/max thresholds to auto toggle
  bool controlRetained; // publish retained
  MqttQosLevel controlQos; // publish QoS
  // Presence (Last Will) subscription
  String? lastWillTopic;
  // Grouping
  String? groupId;
  // Payload parsing
  bool payloadIsJson;
  int jsonFieldIndex; // 1-based order inside JSON object
  String? jsonKeyName; // optional key name to extract from JSON
  // Optional: display timestamp from JSON payload
  bool displayTimeFromJson;
  int jsonTimeFieldIndex; // 1-based order for timestamp
  String? jsonTimeKeyName; // optional key for timestamp
  // Cached latest measurement (for list & group aggregation)
  double? lastLiquidLiters; // most recent filled volume in liters
  double? lastTotalLiters; // capacity liters (may vary if dimensions edited)
  DateTime? lastUpdated; // timestamp of lastLiquidLiters
  // Creation timestamp for sorting by date
  DateTime createdAt;
  // Tank graduation/scale UI settings
  GraduationSide graduationSide;
  // Distance between major ticks in meters
  double scaleMajorTickMeters;
  // Number of minor divisions between majors (>=0)
  int scaleMinorDivisions;

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
  this.wallThickness = 0.0,
    this.minThreshold,
    this.maxThreshold,
    this.multiplier = 1.0,
    this.offset = 0.0,
  this.connectedTankCount = 1,
  this.useCustomFormula = false,
  this.customFormula,
  this.useControlButton = false,
  this.controlTopic,
  this.controlMode = ControlMode.toggle,
  this.onValue = 'ON',
  this.offValue = 'OFF',
  this.autoControl = false,
  this.controlRetained = false,
  this.controlQos = MqttQosLevel.atLeastOnce,
  this.lastWillTopic,
  this.groupId,
  this.payloadIsJson = false,
  this.jsonFieldIndex = 1,
  this.jsonKeyName,
  this.displayTimeFromJson = false,
  this.jsonTimeFieldIndex = 1,
  this.jsonTimeKeyName,
  this.lastLiquidLiters,
  this.lastTotalLiters,
  this.lastUpdated,
    DateTime? createdAt,
    this.graduationSide = GraduationSide.left,
    this.scaleMajorTickMeters = 0.1,
    this.scaleMinorDivisions = 4,
  }) : id = id ?? const Uuid().v4(), createdAt = createdAt ?? DateTime.now();

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
  'wallThickness': wallThickness,
      'minThreshold': minThreshold,
      'maxThreshold': maxThreshold,
      'multiplier': multiplier,
      'offset': offset,
      'connectedTankCount': connectedTankCount,
  'useCustomFormula': useCustomFormula,
  'customFormula': customFormula,
  'useControlButton': useControlButton,
  'controlTopic': controlTopic,
  'controlMode': controlMode.toString(),
  'onValue': onValue,
  'offValue': offValue,
  'autoControl': autoControl,
  'controlRetained': controlRetained,
  'controlQos': controlQos.toString(),
  'lastWillTopic': lastWillTopic,
  'groupId': groupId,
  'payloadIsJson': payloadIsJson,
  'jsonFieldIndex': jsonFieldIndex,
  'jsonKeyName': jsonKeyName,
  'displayTimeFromJson': displayTimeFromJson,
  'jsonTimeFieldIndex': jsonTimeFieldIndex,
  'jsonTimeKeyName': jsonTimeKeyName,
  'lastLiquidLiters': lastLiquidLiters,
  'lastTotalLiters': lastTotalLiters,
  'lastUpdated': lastUpdated?.toIso8601String(),
      'createdAt': createdAt.toIso8601String(),
      'graduationSide': graduationSide.toString(),
      'scaleMajorTickMeters': scaleMajorTickMeters,
      'scaleMinorDivisions': scaleMinorDivisions,
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
  wallThickness: json['wallThickness']?.toDouble() ?? 0.0,
      minThreshold: json['minThreshold']?.toDouble(),
      maxThreshold: json['maxThreshold']?.toDouble(),
      multiplier: json['multiplier']?.toDouble() ?? 1.0,
      offset: json['offset']?.toDouble() ?? 0.0,
    connectedTankCount: (json['connectedTankCount'] is int)
      ? (json['connectedTankCount'] as int).clamp(1, 1000)
      : int.tryParse('${json['connectedTankCount'] ?? '1'}')?.clamp(1, 1000) ?? 1,
      useCustomFormula: json['useCustomFormula'] == true,
      customFormula: (json['customFormula']?.toString().trim().isEmpty ?? true) ? null : json['customFormula'].toString(),
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
  lastWillTopic: json['lastWillTopic'],
  groupId: json['groupId'],
  payloadIsJson: json['payloadIsJson'] == true,
  jsonFieldIndex: (json['jsonFieldIndex'] is int)
      ? json['jsonFieldIndex']
      : int.tryParse('${json['jsonFieldIndex'] ?? '1'}') ?? 1,
  jsonKeyName: (json['jsonKeyName']?.toString().trim().isEmpty ?? true) ? null : json['jsonKeyName'].toString(),
  displayTimeFromJson: json['displayTimeFromJson'] == true,
  jsonTimeFieldIndex: (json['jsonTimeFieldIndex'] is int)
      ? json['jsonTimeFieldIndex']
      : int.tryParse('${json['jsonTimeFieldIndex'] ?? '1'}') ?? 1,
  jsonTimeKeyName: (json['jsonTimeKeyName']?.toString().trim().isEmpty ?? true) ? null : json['jsonTimeKeyName'].toString(),
  lastLiquidLiters: (json['lastLiquidLiters'] is num) ? (json['lastLiquidLiters'] as num).toDouble() : null,
  lastTotalLiters: (json['lastTotalLiters'] is num) ? (json['lastTotalLiters'] as num).toDouble() : null,
  lastUpdated: json['lastUpdated'] != null ? DateTime.tryParse(json['lastUpdated']) : null,
  createdAt: json['createdAt'] != null
      ? DateTime.tryParse(json['createdAt']) ?? DateTime.now()
      : DateTime.now(),
      graduationSide: GraduationSide.values.firstWhere(
        (e) => e.toString() == (json['graduationSide'] ?? GraduationSide.left.toString()),
        orElse: () => GraduationSide.left,
      ),
      scaleMajorTickMeters: (json['scaleMajorTickMeters'] is num)
          ? (json['scaleMajorTickMeters'] as num).toDouble()
          : double.tryParse('${json['scaleMajorTickMeters'] ?? '0.1'}') ?? 0.1,
      scaleMinorDivisions: (json['scaleMinorDivisions'] is int)
          ? json['scaleMinorDivisions']
          : int.tryParse('${json['scaleMinorDivisions'] ?? '4'}') ?? 4,
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

  Project copyWith({
    String? id,
    String? name,
    String? broker,
    int? port,
    String? topic,
    String? username,
    String? password,
    SensorType? sensorType,
    TankType? tankType,
    double? height,
    double? diameter,
    double? length,
    double? width,
  double? wallThickness,
    double? minThreshold,
    double? maxThreshold,
    double? multiplier,
    double? offset,
  int? connectedTankCount,
    bool? useCustomFormula,
    String? customFormula,
    bool? useControlButton,
    String? controlTopic,
    ControlMode? controlMode,
    String? onValue,
    String? offValue,
    bool? autoControl,
    bool? controlRetained,
    MqttQosLevel? controlQos,
    String? lastWillTopic,
  String? groupId,
  bool? payloadIsJson,
  int? jsonFieldIndex,
  String? jsonKeyName,
    bool? displayTimeFromJson,
    int? jsonTimeFieldIndex,
    String? jsonTimeKeyName,
  double? lastLiquidLiters,
  double? lastTotalLiters,
  DateTime? lastUpdated,
  DateTime? createdAt,
  GraduationSide? graduationSide,
  double? scaleMajorTickMeters,
  int? scaleMinorDivisions,
  }) {
    return Project(
      id: id ?? this.id,
      name: name ?? this.name,
      broker: broker ?? this.broker,
      port: port ?? this.port,
      topic: topic ?? this.topic,
      username: username ?? this.username,
      password: password ?? this.password,
      sensorType: sensorType ?? this.sensorType,
      tankType: tankType ?? this.tankType,
      height: height ?? this.height,
      diameter: diameter ?? this.diameter,
      length: length ?? this.length,
  width: width ?? this.width,
  wallThickness: wallThickness ?? this.wallThickness,
      minThreshold: minThreshold ?? this.minThreshold,
      maxThreshold: maxThreshold ?? this.maxThreshold,
      multiplier: multiplier ?? this.multiplier,
      offset: offset ?? this.offset,
  connectedTankCount: connectedTankCount ?? this.connectedTankCount,
    useCustomFormula: useCustomFormula ?? this.useCustomFormula,
    customFormula: customFormula ?? this.customFormula,
      useControlButton: useControlButton ?? this.useControlButton,
      controlTopic: controlTopic ?? this.controlTopic,
      controlMode: controlMode ?? this.controlMode,
      onValue: onValue ?? this.onValue,
      offValue: offValue ?? this.offValue,
      autoControl: autoControl ?? this.autoControl,
      controlRetained: controlRetained ?? this.controlRetained,
      controlQos: controlQos ?? this.controlQos,
      lastWillTopic: lastWillTopic ?? this.lastWillTopic,
  groupId: groupId ?? this.groupId,
  payloadIsJson: payloadIsJson ?? this.payloadIsJson,
  jsonFieldIndex: jsonFieldIndex ?? this.jsonFieldIndex,
  jsonKeyName: jsonKeyName ?? this.jsonKeyName,
      displayTimeFromJson: displayTimeFromJson ?? this.displayTimeFromJson,
      jsonTimeFieldIndex: jsonTimeFieldIndex ?? this.jsonTimeFieldIndex,
      jsonTimeKeyName: jsonTimeKeyName ?? this.jsonTimeKeyName,
  lastLiquidLiters: lastLiquidLiters ?? this.lastLiquidLiters,
  lastTotalLiters: lastTotalLiters ?? this.lastTotalLiters,
  lastUpdated: lastUpdated ?? this.lastUpdated,
  createdAt: createdAt ?? this.createdAt,
      graduationSide: graduationSide ?? this.graduationSide,
      scaleMajorTickMeters: scaleMajorTickMeters ?? this.scaleMajorTickMeters,
      scaleMinorDivisions: scaleMinorDivisions ?? this.scaleMinorDivisions,
    );
  }
}
