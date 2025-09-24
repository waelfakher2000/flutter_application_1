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

class _SignupPageState extends State<SignupPage> with SingleTickerProviderStateMixin {
  final _emailController = TextEditingController();
  final _passwordController = TextEditingController();
  final _confirmController = TextEditingController();
  bool _busy = false;
  String? _error;
  bool _showPassword = false;
  bool _showConfirm = false;
  late final FocusNode _passwordFocus;
  late final FocusNode _confirmFocus;
  late final AnimationController _animController;
  late final Animation<double> _fadeAnim;
  late final Animation<Offset> _slideAnim;

  bool get _validEmail {
    final e = _emailController.text.trim();
    if (e.isEmpty) return false;
    final re = RegExp(r'^[^@]+@[^@]+\.[^@]+$');
    return re.hasMatch(e);
  }

  bool get _validPassword => _passwordController.text.length >= 6;
  bool get _passwordsMatch => _passwordController.text == _confirmController.text && _confirmController.text.isNotEmpty;
  bool get _formValid => _validEmail && _validPassword && _passwordsMatch && !_busy;

  @override
  void initState() {
    super.initState();
    _passwordFocus = FocusNode();
    _confirmFocus = FocusNode();
    _emailController.addListener(_onFieldChange);
    _passwordController.addListener(_onFieldChange);
    _confirmController.addListener(_onFieldChange);
  _animController = AnimationController(vsync: this, duration: const Duration(milliseconds: 520));
    _fadeAnim = CurvedAnimation(parent: _animController, curve: Curves.easeOutCubic);
    _slideAnim = Tween<Offset>(begin: const Offset(0, 0.04), end: Offset.zero)
        .animate(CurvedAnimation(parent: _animController, curve: Curves.easeOutCubic));
    // Kick off animation after first frame
    WidgetsBinding.instance.addPostFrameCallback((_) => _animController.forward());
  }

  void _onFieldChange() {
    // Trigger rebuild for validation states
    if (mounted) setState(() {});
  }

  void _showPasswordRequirements(BuildContext context) {
    showDialog(
      context: context,
      builder: (ctx) {
        return AlertDialog(
          title: const Text('Password Requirements'),
          content: ValueListenableBuilder<TextEditingValue>(
            valueListenable: _passwordController,
            builder: (context, value, _) {
              final pwd = value.text;
              final lengthOk = pwd.length >= 6;
              final hasLetter = RegExp(r'[A-Za-z]').hasMatch(pwd);
              final hasDigit = RegExp(r'\d').hasMatch(pwd);
              return Column(
                mainAxisSize: MainAxisSize.min,
                crossAxisAlignment: CrossAxisAlignment.start,
                children: [
                  _ReqRow(label: 'At least 6 characters', ok: lengthOk),
                  _ReqRow(label: 'Contains a letter', ok: hasLetter),
                  _ReqRow(label: 'Contains a digit', ok: hasDigit),
                ],
              );
            },
          ),
          actions: [
            TextButton(onPressed: () => Navigator.pop(context), child: const Text('Close')),
          ],
        );
      },
    );
  }

  @override
  void dispose() {
    _emailController.dispose();
    _passwordController.dispose();
    _confirmController.dispose();
    _passwordFocus.dispose();
    _confirmFocus.dispose();
    _animController.dispose();
    super.dispose();
  }

  Future<void> _submit() async {
    final email = _emailController.text.trim();
    final pass = _passwordController.text;
    final confirm = _confirmController.text;
    if (pass != confirm) {
      setState(() { _error = 'Passwords do not match'; });
      return;
    }
    if (!_validEmail) {
      setState(() { _error = 'Enter a valid email'; });
      return;
    }
    if (!_validPassword) {
      setState(() { _error = 'Password must be at least 6 characters'; });
      return;
    }
    setState(() { _busy = true; _error = null; });
    final auth = context.read<AuthProvider>();
    final repo = context.read<ProjectRepository>();
    final err = await auth.signup(email, pass);
    if (!mounted) return;
    setState(() { _busy = false; _error = err; });
    if (err == null) {
      // After successful signup (auto-login), sync projects (likely empty) to ensure server state loaded
      try {
        await repo.syncFromBackend();
      } catch (_) {}
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
                  // Branding header
                  Row(
                    mainAxisAlignment: MainAxisAlignment.center,
                    children: [
                      SizedBox(
                        width: 56,
                        height: 56,
                        child: Image.asset('assets/logo.png', fit: BoxFit.contain),
                      ),
                      const SizedBox(width: 12),
                      Flexible(
                        child: Text('Create your account',
                            style: theme.textTheme.headlineSmall?.copyWith(fontWeight: FontWeight.w600)),
                      ),
                    ],
                  ),
                  const SizedBox(height: 28),
                  FadeTransition(
                    opacity: _fadeAnim,
                    child: SlideTransition(
                      position: _slideAnim,
                      child: Card(
                    elevation: 3,
                    shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(16)),
                    child: Padding(
                      padding: const EdgeInsets.symmetric(horizontal: 24, vertical: 28),
                      child: Column(
                        crossAxisAlignment: CrossAxisAlignment.stretch,
                        children: [
                          _LabeledField(
                            label: 'Email',
                            child: TextField(
                              controller: _emailController,
                              keyboardType: TextInputType.emailAddress,
                              autofillHints: const [AutofillHints.email],
                              decoration: InputDecoration(
                                hintText: 'you@example.com',
                                errorText: _emailController.text.isEmpty || _validEmail ? null : 'Invalid email',
                                prefixIcon: const Icon(Icons.alternate_email),
                              ),
                            ),
                          ),
                          const SizedBox(height: 16),
                          _LabeledField(
                            label: 'Password',
                            helper: 'At least 6 characters',
                            trailing: IconButton(
                              tooltip: 'Show password requirements',
                              icon: const Icon(Icons.info_outline),
                              onPressed: () => _showPasswordRequirements(context),
                            ),
                            child: TextField(
                              controller: _passwordController,
                              obscureText: !_showPassword,
                              autofillHints: const [AutofillHints.newPassword],
                              decoration: InputDecoration(
                                hintText: '••••••••',
                                errorText: _passwordController.text.isEmpty || _validPassword ? null : 'Too short',
                                prefixIcon: const Icon(Icons.lock_outline),
                                suffixIcon: IconButton(
                                  icon: Icon(_showPassword ? Icons.visibility_off : Icons.visibility),
                                  onPressed: () => setState(() => _showPassword = !_showPassword),
                                ),
                              ),
                            ),
                          ),
                          const SizedBox(height: 16),
                          _LabeledField(
                            label: 'Confirm Password',
                            child: TextField(
                              controller: _confirmController,
                              obscureText: !_showConfirm,
                              decoration: InputDecoration(
                                hintText: 'Repeat password',
                                errorText: _confirmController.text.isEmpty || _passwordsMatch ? null : 'Does not match',
                                prefixIcon: const Icon(Icons.lock),
                                suffixIcon: IconButton(
                                  icon: Icon(_showConfirm ? Icons.visibility_off : Icons.visibility),
                                  onPressed: () => setState(() => _showConfirm = !_showConfirm),
                                ),
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
                              onPressed: _formValid ? _submit : null,
                              icon: _busy
                                  ? const SizedBox(
                                      height: 18,
                                      width: 18,
                                      child: CircularProgressIndicator(strokeWidth: 2),
                                    )
                                  : const Icon(Icons.person_add_alt),
                              label: Text(_busy ? 'Creating...' : 'Sign Up'),
                              style: ElevatedButton.styleFrom(
                                shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(12)),
                              ),
                            ),
                          ),
                          const SizedBox(height: 16),
                          TextButton(
                            onPressed: _busy ? null : () => Navigator.pop(context),
                            child: const Text('Already have an account? Log in'),
                          ),
                        ],
                      ),
                    ),
                      ),
                    ),
                  ),
                  const SizedBox(height: 24),
                  Opacity(
                    opacity: 0.8,
                    child: Column(
                      children: [
                        Text('By creating an account you agree to the terms (placeholder).',
                            textAlign: TextAlign.center, style: theme.textTheme.bodySmall),
                        const SizedBox(height: 8),
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

class _LabeledField extends StatelessWidget {
  final String label;
  final String? helper;
  final Widget child;
  final Widget? trailing;
  const _LabeledField({required this.label, this.helper, required this.child, this.trailing});
  @override
  Widget build(BuildContext context) {
    final theme = Theme.of(context);
    return Column(
      crossAxisAlignment: CrossAxisAlignment.start,
      children: [
        Row(
          children: [
            Expanded(child: Text(label, style: theme.textTheme.labelLarge?.copyWith(fontWeight: FontWeight.w600))),
            if (trailing != null) trailing!,
          ],
        ),
        if (helper != null)
          Padding(
            padding: const EdgeInsets.only(top: 2.0),
            child: Text(helper!, style: theme.textTheme.bodySmall?.copyWith(color: theme.hintColor)),
          ),
        const SizedBox(height: 6),
        child,
      ],
    );
  }
}

class _ReqRow extends StatelessWidget {
  final String label; final bool ok; const _ReqRow({required this.label, required this.ok});
  @override
  Widget build(BuildContext context) {
    final color = ok ? Colors.green : Theme.of(context).colorScheme.error;
    return Padding(
      padding: const EdgeInsets.symmetric(vertical: 4),
      child: Row(children: [
        Icon(ok ? Icons.check_circle : Icons.radio_button_unchecked, size: 18, color: color),
        const SizedBox(width: 8),
        Expanded(child: Text(label)),
      ]),
    );
  }
}
