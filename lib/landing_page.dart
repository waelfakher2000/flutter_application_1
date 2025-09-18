import 'package:flutter/material.dart';
import 'package:flutter_application_1/project_list_page.dart';
// Import your main app file

class LandingPage extends StatefulWidget {
  const LandingPage({super.key});

  @override
  State<LandingPage> createState() => _LandingPageState();
}

class _LandingPageState extends State<LandingPage> with SingleTickerProviderStateMixin {
  late AnimationController _controller;
  late Animation<double> _scaleAnimation;
  bool _ready = false; // once image cached

  @override
  void initState() {
    super.initState();
    _controller = AnimationController(duration: const Duration(milliseconds: 1400), vsync: this);
    _scaleAnimation = Tween<double>(begin: 0.9, end: 1.0).animate(
      CurvedAnimation(parent: _controller, curve: Curves.easeOutCubic),
    );

    WidgetsBinding.instance.addPostFrameCallback((_) async {
      // Precache logo to avoid one-frame blank
      try {
        await precacheImage(const AssetImage('assets/logo.png'), context);
      } catch (_) {}
      if (!mounted) return;
      setState(() { _ready = true; _controller.forward(); });
      debugPrint('[LandingPage] Starting 2.2s timer to navigate...');
      _navigateToNextScreen(const Duration(milliseconds: 2200));
    });
  }

  Future<void> _navigateToNextScreen([Duration delay = const Duration(seconds: 3)]) async {
    await Future.delayed(delay); // configurable delay
    debugPrint('[LandingPage] Timer finished. mounted=$mounted');

    if (mounted) {
      debugPrint('[LandingPage] Navigating to ProjectListPage');
      Navigator.of(context).pushReplacement(
        MaterialPageRoute(builder: (context) => const ProjectListPage()),
      );
    }
  }

  @override
  void dispose() {
    _controller.dispose();
    super.dispose();
  }

  @override
  Widget build(BuildContext context) {
    // Use explicit pure white / pure black to avoid intermediate Material grey during theme
    // resolution, preventing a brief grey flash when the first frame renders.
    final bool dark = Theme.of(context).brightness == Brightness.dark;
    final Color bg = dark ? Colors.black : Colors.white;
    final content = Column(
      mainAxisAlignment: MainAxisAlignment.center,
      children: [
        Image.asset('assets/logo.png', width: 150, height: 150),
        const SizedBox(height: 20),
        const Text(
          'Tank Monitoring',
          style: TextStyle(fontSize: 24, fontWeight: FontWeight.bold),
        ),
      ],
    );
    return Scaffold(
      backgroundColor: bg,
      body: Center(
        child: (_ready)
            ? ScaleTransition(scale: _scaleAnimation, child: content)
            : content, // show immediately while caching
      ),
    );
  }
}
