import 'package:flutter/material.dart';
import 'package:provider/provider.dart';
import 'auth_provider.dart';
import 'landing_page.dart';
import 'project_repository.dart';

class SignupPage extends StatefulWidget {
  const SignupPage({super.key});
  @override
  State<SignupPage> createState() => _SignupPageState();
}

class _SignupPageState extends State<SignupPage> {
  final _emailController = TextEditingController();
  final _passwordController = TextEditingController();
  final _confirmController = TextEditingController();
  bool _busy = false;
  String? _error;

  Future<void> _submit() async {
    final email = _emailController.text.trim();
    final pass = _passwordController.text;
    final confirm = _confirmController.text;
    if (pass != confirm) {
      setState(() { _error = 'Passwords do not match'; });
      return;
    }
    setState(() { _busy = true; _error = null; });
    final auth = context.read<AuthProvider>();
    final err = await auth.signup(email, pass);
    if (!mounted) return;
    setState(() { _busy = false; _error = err; });
    if (err == null) {
      // After successful signup (auto-login), sync projects (likely empty) to ensure server state loaded
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
      appBar: AppBar(title: const Text('Create Account')),
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
                  decoration: const InputDecoration(labelText: 'Password (min 6 chars)'),
                ),
                const SizedBox(height: 12),
                TextField(
                  controller: _confirmController,
                  obscureText: true,
                  decoration: const InputDecoration(labelText: 'Confirm Password'),
                ),
                const SizedBox(height: 16),
                if (_error != null) Text(_error!, style: const TextStyle(color: Colors.red)),
                ElevatedButton(
                  onPressed: _busy ? null : _submit,
                  child: _busy ? const SizedBox(height: 16, width: 16, child: CircularProgressIndicator(strokeWidth: 2)) : const Text('Sign Up'),
                ),
              ],
            ),
          ),
        ),
      ),
    );
  }
}
