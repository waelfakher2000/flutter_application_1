import 'dart:async';
import 'package:flutter/material.dart';
import 'package:shared_preferences/shared_preferences.dart';
import 'main.dart'; // Import your main app file
import 'types.dart';

class LandingPage extends StatefulWidget {
  const LandingPage({super.key});

  @override
  State<LandingPage> createState() => _LandingPageState();
}

class _LandingPageState extends State<LandingPage> with SingleTickerProviderStateMixin {
  late AnimationController _controller;
  late Animation<double> _fadeAnimation;
  late Animation<double> _scaleAnimation;

  @override
  void initState() {
    super.initState();
    _controller = AnimationController(
      duration: const Duration(seconds: 2),
      vsync: this,
    );

    _fadeAnimation = Tween<double>(begin: 0.0, end: 1.0).animate(
      CurvedAnimation(parent: _controller, curve: Curves.easeIn),
    );

    _scaleAnimation = Tween<double>(begin: 0.5, end: 1.0).animate(
      CurvedAnimation(parent: _controller, curve: Curves.easeInOut),
    );

    _controller.forward();

    _navigateToNextScreen();
  }

  Future<void> _navigateToNextScreen() async {
    await Future.delayed(const Duration(seconds: 3)); // Total time for landing page

    final prefs = await SharedPreferences.getInstance();
    final broker = prefs.getString('broker');
    final port = prefs.getInt('port');
    final topic = prefs.getString('topic');

    if (mounted) {
      if (broker != null && port != null && topic != null) {
        final savedSensor = prefs.getString('sensor');
        final savedTank = prefs.getString('tank');

        if (savedSensor != null && savedTank != null) {
          final sensorType = SensorType.values.firstWhere((e) => e.toString() == savedSensor, orElse: () => SensorType.submersible);
          final tankType = TankType.values.firstWhere((e) => e.toString() == savedTank, orElse: () => TankType.verticalCylinder);
          final height = prefs.getDouble('height') ?? 1.0;
          final diameter = prefs.getDouble('diameter') ?? 0.4;
          final length = prefs.getDouble('length') ?? 1.0;
          final width = prefs.getDouble('width') ?? 0.5;
          final minThr = prefs.getDouble('minThreshold');
          final maxThr = prefs.getDouble('maxThreshold');
          final username = prefs.getString('username');
          final password = prefs.getString('password');

          Navigator.of(context).pushReplacement(
            MaterialPageRoute(
              builder: (context) => MainTankPage(
                broker: broker,
                port: port,
                topic: topic,
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
            ),
          );
        } else {
           Navigator.of(context).pushReplacement(
            MaterialPageRoute(builder: (context) => const MqttTopicPage()),
          );
        }
      } else {
        Navigator.of(context).pushReplacement(
          MaterialPageRoute(builder: (context) => const MqttTopicPage()),
        );
      }
    }
  }

  @override
  void dispose() {
    _controller.dispose();
    super.dispose();
  }

  @override
  Widget build(BuildContext context) {
    return Scaffold(
      body: Center(
        child: FadeTransition(
          opacity: _fadeAnimation,
          child: ScaleTransition(
            scale: _scaleAnimation,
            child: Column(
              mainAxisAlignment: MainAxisAlignment.center,
              children: [
                Image.asset('assets/logo.png', width: 150, height: 150),
                const SizedBox(height: 20),
                const Text(
                  'Tank Monitoring',
                  style: TextStyle(
                    fontSize: 24,
                    fontWeight: FontWeight.bold,
                  ),
                ),
              ],
            ),
          ),
        ),
      ),
    );
  }
}
