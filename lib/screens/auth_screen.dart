import 'package:flutter/material.dart';

import '../config.dart';
import '../models/app_user.dart';
import '../services/app_exception.dart';
import '../services/auth_service.dart';
import '../services/user_service.dart';
import '../services/validators.dart';
import 'rules_lab_screen.dart';

/// Sign-in and registration on one screen (no pushed route), so the
/// AuthGate can swap it out cleanly the moment the user signs in.
class AuthScreen extends StatefulWidget {
  const AuthScreen({super.key, required this.auth});
  final AuthService auth;

  @override
  State<AuthScreen> createState() => _AuthScreenState();
}

class _AuthScreenState extends State<AuthScreen> {
  final _formKey = GlobalKey<FormState>();
  final _email = TextEditingController();
  final _password = TextEditingController();
  final _confirm = TextEditingController();
  final _firstName = TextEditingController();
  final _lastName = TextEditingController();
  String _role = userRoles.first;

  bool _registerMode = false;
  bool _busy = false;
  bool _showPassword = false;
  String? _error;

  @override
  void dispose() {
    _email.dispose();
    _password.dispose();
    _confirm.dispose();
    _firstName.dispose();
    _lastName.dispose();
    super.dispose();
  }

  void _toggleMode() {
    setState(() {
      _registerMode = !_registerMode;
      _error = null;
    });
  }

  Future<void> _submit() async {
    if (_busy) return; // duplicate-submit guard (the button is disabled too)
    setState(() => _error = null);
    if (!_formKey.currentState!.validate()) return;
    setState(() => _busy = true);
    final email = _email.text.trim();
    try {
      if (_registerMode) {
        // The auth gate replaces this screen as soon as the account exists,
        // so the profile fields are handed to ProfileGate, which writes them.
        UserService.stashDraft(
          email,
          ProfileDraft(
            firstName: _firstName.text.trim(),
            lastName: _lastName.text.trim(),
            role: _role,
          ),
        );
        await widget.auth.register(email: email, password: _password.text);
      } else {
        await widget.auth.signIn(email: email, password: _password.text);
      }
    } on AppException catch (e) {
      if (_registerMode) UserService.discardDraft(email);
      if (mounted) setState(() => _error = e.message);
    } finally {
      if (mounted) setState(() => _busy = false);
    }
  }

  @override
  Widget build(BuildContext context) {
    final scheme = Theme.of(context).colorScheme;
    return Scaffold(
      body: SafeArea(
        child: Center(
          child: SingleChildScrollView(
            padding: const EdgeInsets.all(24),
            child: ConstrainedBox(
              constraints: const BoxConstraints(maxWidth: 440),
              child: Form(
                key: _formKey,
                child: Column(
                  crossAxisAlignment: CrossAxisAlignment.stretch,
                  children: [
                    Icon(Icons.forum_rounded, size: 48, color: scheme.primary),
                    const SizedBox(height: 8),
                    Text(
                      appName,
                      textAlign: TextAlign.center,
                      style: Theme.of(context).textTheme.headlineMedium,
                    ),
                    const SizedBox(height: 4),
                    Text(
                      _registerMode ? 'Create your account' : 'Sign in to the board',
                      textAlign: TextAlign.center,
                      style: Theme.of(context).textTheme.titleMedium,
                    ),
                    const SizedBox(height: 24),
                    if (_registerMode) ...[
                      TextFormField(
                        controller: _firstName,
                        decoration: const InputDecoration(labelText: 'First name'),
                        textCapitalization: TextCapitalization.words,
                        validator: (v) => Validators.name(v, label: 'first name'),
                        enabled: !_busy,
                      ),
                      const SizedBox(height: 12),
                      TextFormField(
                        controller: _lastName,
                        decoration: const InputDecoration(labelText: 'Last name'),
                        textCapitalization: TextCapitalization.words,
                        validator: (v) => Validators.name(v, label: 'last name'),
                        enabled: !_busy,
                      ),
                      const SizedBox(height: 12),
                      DropdownButtonFormField<String>(
                        initialValue: _role,
                        decoration: const InputDecoration(labelText: 'Role'),
                        items: [
                          for (final r in userRoles)
                            DropdownMenuItem(value: r, child: Text(_titleCase(r))),
                        ],
                        onChanged: _busy ? null : (v) => setState(() => _role = v ?? _role),
                      ),
                      const SizedBox(height: 12),
                    ],
                    TextFormField(
                      controller: _email,
                      decoration: const InputDecoration(labelText: 'Email'),
                      keyboardType: TextInputType.emailAddress,
                      autocorrect: false,
                      validator: Validators.email,
                      enabled: !_busy,
                    ),
                    const SizedBox(height: 12),
                    TextFormField(
                      controller: _password,
                      decoration: InputDecoration(
                        labelText: 'Password',
                        suffixIcon: IconButton(
                          tooltip: _showPassword ? 'Hide password' : 'Show password',
                          icon: Icon(_showPassword
                              ? Icons.visibility_off
                              : Icons.visibility),
                          onPressed: () =>
                              setState(() => _showPassword = !_showPassword),
                        ),
                      ),
                      obscureText: !_showPassword,
                      validator: _registerMode
                          ? Validators.newPassword
                          : Validators.loginPassword,
                      enabled: !_busy,
                    ),
                    if (_registerMode) ...[
                      const SizedBox(height: 12),
                      TextFormField(
                        controller: _confirm,
                        decoration:
                            const InputDecoration(labelText: 'Confirm password'),
                        obscureText: !_showPassword,
                        validator: (v) => v == _password.text
                            ? null
                            : 'Passwords do not match.',
                        enabled: !_busy,
                      ),
                    ],
                    if (_error != null) ...[
                      const SizedBox(height: 16),
                      _ErrorBanner(message: _error!),
                    ],
                    const SizedBox(height: 20),
                    FilledButton(
                      onPressed: _busy ? null : _submit,
                      child: Padding(
                        padding: const EdgeInsets.symmetric(vertical: 12),
                        child: _busy
                            ? const SizedBox(
                                width: 20,
                                height: 20,
                                child: CircularProgressIndicator(strokeWidth: 2),
                              )
                            : Text(_registerMode ? 'Create account' : 'Sign in'),
                      ),
                    ),
                    const SizedBox(height: 8),
                    TextButton(
                      onPressed: _busy ? null : _toggleMode,
                      child: Text(_registerMode
                          ? 'Already registered? Sign in'
                          : 'New here? Create an account'),
                    ),
                    const Divider(height: 32),
                    OutlinedButton.icon(
                      icon: const Icon(Icons.shield_outlined),
                      label: const Text('Rules check: read board while signed out'),
                      onPressed: _busy
                          ? null
                          : () => Navigator.of(context).push(MaterialPageRoute(
                                builder: (_) => const SignedOutProbeScreen(),
                              )),
                    ),
                  ],
                ),
              ),
            ),
          ),
        ),
      ),
    );
  }
}

String _titleCase(String s) => s.isEmpty ? s : s[0].toUpperCase() + s.substring(1);

class _ErrorBanner extends StatelessWidget {
  const _ErrorBanner({required this.message});
  final String message;

  @override
  Widget build(BuildContext context) {
    final scheme = Theme.of(context).colorScheme;
    return Container(
      padding: const EdgeInsets.all(12),
      decoration: BoxDecoration(
        color: scheme.errorContainer,
        borderRadius: BorderRadius.circular(8),
      ),
      child: Row(
        children: [
          Icon(Icons.error_outline, color: scheme.onErrorContainer),
          const SizedBox(width: 8),
          Expanded(
            child: Text(message, style: TextStyle(color: scheme.onErrorContainer)),
          ),
        ],
      ),
    );
  }
}
