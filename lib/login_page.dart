import 'package:flutter/material.dart';
import 'package:provider/provider.dart';
import 'auth_provider.dart';
import 'signup_page.dart';
import 'landing_page.dart';
import 'project_repository.dart';
import 'diagnostics_page.dart';

class LoginPage extends StatefulWidget {
  const LoginPage({super.key});
  @override
  State<LoginPage> createState() => _LoginPageState();
}

class _LoginPageState extends State<LoginPage> {
  final _emailController = TextEditingController();
  final _passwordController = TextEditingController();
  bool _busy = false;
  String? _error;

  Future<void> _submit() async {
    setState(() { _busy = true; _error = null; });
    final auth = context.read<AuthProvider>();
    final err = await auth.login(_emailController.text, _passwordController.text);
    if (!mounted) return;
    setState(() { _busy = false; _error = err; });
    if (err == null) {
      // After successful login, trigger a project sync before navigating
      try {
        final repo = context.read<ProjectRepository>();
        await repo.syncFromBackend();
      } catch (_) {}
      if (!mounted) return;
      Navigator.pushAndRemoveUntil(context, MaterialPageRoute(builder: (_) => const LandingPage()), (r) => false);
    }
  }

  @override
  Widget build(BuildContext context) {
    return Scaffold(
      appBar: AppBar(title: const Text('Login'), actions: [
        IconButton(onPressed: () { Navigator.push(context, MaterialPageRoute(builder: (_) => const DiagnosticsPage())); }, icon: const Icon(Icons.medical_information))
      ]),
      body: Center(
        child: SingleChildScrollView(
          padding: const EdgeInsets.all(24),
          child: ConstrainedBox(
            constraints: const BoxConstraints(maxWidth: 400),
            child: Column(
              crossAxisAlignment: CrossAxisAlignment.stretch,
              children: [
                TextField(
                  controller: _emailController,
                  keyboardType: TextInputType.emailAddress,
                  decoration: const InputDecoration(labelText: 'Email'),
                ),
                const SizedBox(height: 12),
                TextField(
                  controller: _passwordController,
                  obscureText: true,
                  decoration: const InputDecoration(labelText: 'Password'),
                ),
                const SizedBox(height: 16),
                if (_error != null) Text(_error!, style: const TextStyle(color: Colors.red)),
                ElevatedButton(
                  onPressed: _busy ? null : _submit,
                  child: _busy ? const SizedBox(height: 16, width: 16, child: CircularProgressIndicator(strokeWidth: 2)) : const Text('Login'),
                ),
                TextButton(
                  onPressed: () {
                    Navigator.push(context, MaterialPageRoute(builder: (_) => const SignupPage()));
                  },
                  child: const Text('Create an account'),
                )
              ],
            ),
          ),
        ),
      ),
    );
  }
}
