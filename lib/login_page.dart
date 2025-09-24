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
  bool _showPassword = false;

  Future<void> _submit() async {
    setState(() { _busy = true; _error = null; });
    final auth = context.read<AuthProvider>();
    final repo = context.read<ProjectRepository>();
    final err = await auth.login(_emailController.text.trim(), _passwordController.text);
    if (!mounted) return;
    setState(() { _busy = false; _error = err; });
    if (err == null) {
      try { await repo.syncFromBackend(); } catch (_) {}
      if (!mounted) return;
      Navigator.pushAndRemoveUntil(context, MaterialPageRoute(builder: (_) => const LandingPage()), (r) => false);
    }
  }

  @override
  Widget build(BuildContext context) {
    final theme = Theme.of(context);
    final colorScheme = theme.colorScheme;
    return Scaffold(
      body: SafeArea(
        child: Center(
          child: SingleChildScrollView(
            padding: const EdgeInsets.symmetric(horizontal: 24, vertical: 32),
            child: ConstrainedBox(
              constraints: const BoxConstraints(maxWidth: 460),
              child: Column(
                crossAxisAlignment: CrossAxisAlignment.stretch,
                children: [
                  Row(
                    mainAxisAlignment: MainAxisAlignment.center,
                    children: [
                      SizedBox(width: 56, height: 56, child: Image.asset('assets/logo.png', fit: BoxFit.contain)),
                      const SizedBox(width: 12),
                      Flexible(
                        child: Text('Welcome back', style: theme.textTheme.headlineSmall?.copyWith(fontWeight: FontWeight.w600)),
                      ),
                      IconButton(
                        tooltip: 'Diagnostics',
                        icon: const Icon(Icons.medical_information),
                        onPressed: () => Navigator.push(context, MaterialPageRoute(builder: (_) => const DiagnosticsPage())),
                      )
                    ],
                  ),
                  const SizedBox(height: 28),
                  Card(
                    elevation: 3,
                    shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(16)),
                    child: Padding(
                      padding: const EdgeInsets.symmetric(horizontal: 24, vertical: 28),
                      child: Column(
                        crossAxisAlignment: CrossAxisAlignment.stretch,
                        children: [
                          TextField(
                            controller: _emailController,
                            keyboardType: TextInputType.emailAddress,
                            autofillHints: const [AutofillHints.email],
                            decoration: const InputDecoration(
                              labelText: 'Email',
                              hintText: 'you@example.com',
                              prefixIcon: Icon(Icons.alternate_email),
                            ),
                          ),
                          const SizedBox(height: 16),
                          TextField(
                            controller: _passwordController,
                            obscureText: !_showPassword,
                            autofillHints: const [AutofillHints.password],
                            onSubmitted: (_) => _busy ? null : _submit(),
                            decoration: InputDecoration(
                              labelText: 'Password',
                              hintText: '••••••••',
                              prefixIcon: const Icon(Icons.lock_outline),
                              suffixIcon: IconButton(
                                icon: Icon(_showPassword ? Icons.visibility_off : Icons.visibility),
                                onPressed: () => setState(() => _showPassword = !_showPassword),
                              ),
                            ),
                          ),
                          const SizedBox(height: 20),
                          AnimatedSwitcher(
                            duration: const Duration(milliseconds: 240),
                            switchInCurve: Curves.easeOutCubic,
                            switchOutCurve: Curves.easeInCubic,
                            child: _error == null
                                ? const SizedBox.shrink()
                                : Padding(
                                    key: ValueKey(_error),
                                    padding: const EdgeInsets.only(bottom: 12),
                                    child: Text(_error!, style: theme.textTheme.bodyMedium?.copyWith(color: Colors.red)),
                                  ),
                          ),
                          SizedBox(
                            height: 48,
                            child: ElevatedButton.icon(
                              onPressed: _busy ? null : _submit,
                              icon: _busy
                                  ? const SizedBox(height: 18, width: 18, child: CircularProgressIndicator(strokeWidth: 2))
                                  : const Icon(Icons.login),
                              label: Text(_busy ? 'Signing in...' : 'Login'),
                              style: ElevatedButton.styleFrom(
                                shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(12)),
                              ),
                            ),
                          ),
                          const SizedBox(height: 16),
                          OutlinedButton.icon(
                            onPressed: _busy ? null : () => Navigator.push(context, MaterialPageRoute(builder: (_) => const SignupPage())),
                            icon: const Icon(Icons.person_add_alt),
                            label: const Text('Create an account'),
                          ),
                        ],
                      ),
                    ),
                  ),
                  const SizedBox(height: 24),
                  Opacity(
                    opacity: 0.8,
                    child: Column(
                      children: [
                        Text('Secure sync, multi-device access, MQTT powered.',
                            textAlign: TextAlign.center, style: theme.textTheme.bodySmall?.copyWith(color: colorScheme.primary)),
                      ],
                    ),
                  )
                ],
              ),
            ),
          ),
        ),
      ),
    );
  }
}
