import 'package:flutter/material.dart';
import 'package:google_fonts/google_fonts.dart';
import 'package:flutter_application_1/project_model.dart';
import 'package:flutter_application_1/types.dart';

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
  late TextEditingController _minController;
  late TextEditingController _maxController;
  late TextEditingController _multiplierController;
  late TextEditingController _offsetController;
  // Last Will / Presence
  late TextEditingController _lastWillTopicController;
  // Control button
  bool _useControlButton = false;
  late TextEditingController _controlTopicController;
  ControlMode _controlMode = ControlMode.toggle;
  late TextEditingController _onValueController;
  late TextEditingController _offValueController;
  bool _autoControl = false;
  bool _controlRetained = false;
  MqttQosLevel _controlQos = MqttQosLevel.atLeastOnce;

  SensorType _sensorType = SensorType.submersible;
  TankType _tankType = TankType.verticalCylinder;

  @override
  void initState() {
    super.initState();
    final p = widget.project;
    _nameController = TextEditingController(text: p?.name ?? 'New Project');
    _brokerController = TextEditingController(text: p?.broker ?? 'test.mosquitto.org');
    _portController = TextEditingController(text: p?.port.toString() ?? '1883');
    _topicController = TextEditingController(text: p?.topic ?? 'tank/level');
    _usernameController = TextEditingController(text: p?.username);
    _passwordController = TextEditingController(text: p?.password);
    _sensorType = p?.sensorType ?? SensorType.submersible;
    _tankType = p?.tankType ?? TankType.verticalCylinder;
    _heightController = TextEditingController(text: p?.height.toString() ?? '1.0');
    _diameterController = TextEditingController(text: p?.diameter.toString() ?? '0.4');
    _lengthController = TextEditingController(text: p?.length.toString() ?? '1.0');
    _widthController = TextEditingController(text: p?.width.toString() ?? '0.5');
    _minController = TextEditingController(text: p?.minThreshold?.toString());
    _maxController = TextEditingController(text: p?.maxThreshold?.toString());
    _multiplierController = TextEditingController(text: p?.multiplier.toString() ?? '1.0');
    _offsetController = TextEditingController(text: p?.offset.toString() ?? '0.0');
  _lastWillTopicController = TextEditingController(text: p?.lastWillTopic ?? '');
  // Control button
  _useControlButton = p?.useControlButton ?? false;
  _controlTopicController = TextEditingController(text: p?.controlTopic ?? '');
  _controlMode = p?.controlMode ?? ControlMode.toggle;
  _onValueController = TextEditingController(text: p?.onValue ?? 'ON');
  _offValueController = TextEditingController(text: p?.offValue ?? 'OFF');
  _autoControl = p?.autoControl ?? false;
  _controlRetained = p?.controlRetained ?? false;
  _controlQos = p?.controlQos ?? MqttQosLevel.atLeastOnce;
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
    _minController.dispose();
    _maxController.dispose();
    _multiplierController.dispose();
    _offsetController.dispose();
  _controlTopicController.dispose();
  _onValueController.dispose();
  _offValueController.dispose();
  _lastWillTopicController.dispose();
    super.dispose();
  }

  void _saveProject() {
    if (_formKey.currentState!.validate()) {
      final project = Project(
        id: widget.project?.id,
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
        minThreshold: _minController.text.isNotEmpty ? double.parse(_minController.text) : null,
        maxThreshold: _maxController.text.isNotEmpty ? double.parse(_maxController.text) : null,
        multiplier: double.tryParse(_multiplierController.text) ?? 1.0,
        offset: double.tryParse(_offsetController.text) ?? 0.0,
  lastWillTopic: _lastWillTopicController.text.trim().isEmpty ? null : _lastWillTopicController.text.trim(),
  useControlButton: _useControlButton,
  controlTopic: _controlTopicController.text.trim().isEmpty ? null : _controlTopicController.text.trim(),
  controlMode: _controlMode,
  onValue: _onValueController.text.isEmpty ? 'ON' : _onValueController.text,
  offValue: _offValueController.text.isEmpty ? 'OFF' : _offValueController.text,
  autoControl: _autoControl,
  controlRetained: _controlRetained,
  controlQos: _controlQos,
      );
      Navigator.of(context).pop(project);
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
          fillColor: scheme.surfaceContainerHighest.withOpacity(0.25),
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
            color: color.withOpacity(0.12),
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
                        ],
                      ),
                    ),
                  ],
                ),
              ),
              const SizedBox(height: 16),
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
