import 'dart:async';

import 'package:flutter/material.dart';

import '../../core/api/api_exception.dart';
import 'auth_controller.dart';
import 'validators.dart';

class LoginScreen extends StatefulWidget {
  const LoginScreen({
    super.key,
    required this.auth,
    required this.onShowRegister,
    required this.onCheckConnection,
  });

  final AuthController auth;
  final VoidCallback onShowRegister;
  final VoidCallback onCheckConnection;

  @override
  State<LoginScreen> createState() => _LoginScreenState();
}

class _LoginScreenState extends State<LoginScreen> {
  final _formKey = GlobalKey<FormState>();
  final _email = TextEditingController();
  final _password = TextEditingController();

  bool _busy = false;
  bool _obscure = true;
  String? _formError;
  Map<String, String> _fieldErrors = const {};

  @override
  void dispose() {
    _email.dispose();
    _password.dispose();
    super.dispose();
  }

  Future<void> _submit() async {
    setState(() {
      _formError = null;
      _fieldErrors = const {};
    });
    if (!(_formKey.currentState?.validate() ?? false)) return;

    setState(() => _busy = true);
    try {
      await widget.auth.login(email: _email.text, password: _password.text);
      // On success the app swaps this screen for the home screen.
    } on ValidationException catch (e) {
      if (!mounted) return;
      setState(() {
        _formError = e.message;
        _fieldErrors = e.fieldMessages();
      });
      _formKey.currentState?.validate();
    } on ApiException catch (e) {
      if (!mounted) return;
      setState(() => _formError = e.message);
    } finally {
      if (mounted) setState(() => _busy = false);
    }
  }

  @override
  Widget build(BuildContext context) {
    return Scaffold(
      appBar: AppBar(title: const Text('HisabAI')),
      body: SafeArea(
        child: Center(
          child: SingleChildScrollView(
            padding: const EdgeInsets.all(24),
            child: ConstrainedBox(
              constraints: const BoxConstraints(maxWidth: 420),
              child: Form(
                key: _formKey,
                child: Column(
                  crossAxisAlignment: CrossAxisAlignment.stretch,
                  children: [
                    Text(
                      'Sign in',
                      style: Theme.of(context).textTheme.headlineSmall,
                    ),
                    const SizedBox(height: 24),
                    if (_formError != null) ...[
                      _ErrorBanner(message: _formError!),
                      const SizedBox(height: 16),
                    ],
                    TextFormField(
                      key: const Key('login-email'),
                      controller: _email,
                      keyboardType: TextInputType.emailAddress,
                      autofillHints: const [AutofillHints.email],
                      textInputAction: TextInputAction.next,
                      decoration: const InputDecoration(
                        labelText: 'Email',
                        border: OutlineInputBorder(),
                      ),
                      validator: (v) =>
                          Validators.email(v) ?? _fieldErrors['email'],
                    ),
                    const SizedBox(height: 16),
                    TextFormField(
                      key: const Key('login-password'),
                      controller: _password,
                      obscureText: _obscure,
                      autofillHints: const [AutofillHints.password],
                      onFieldSubmitted: (_) {
                        if (!_busy) unawaited(_submit());
                      },
                      decoration: InputDecoration(
                        labelText: 'Password',
                        border: const OutlineInputBorder(),
                        suffixIcon: IconButton(
                          tooltip: _obscure ? 'Show password' : 'Hide password',
                          icon: Icon(
                            _obscure ? Icons.visibility : Icons.visibility_off,
                          ),
                          onPressed: () => setState(() => _obscure = !_obscure),
                        ),
                      ),
                      validator: (v) =>
                          Validators.passwordPresent(v) ??
                          _fieldErrors['password'],
                    ),
                    const SizedBox(height: 24),
                    FilledButton(
                      key: const Key('login-submit'),
                      onPressed: _busy ? null : _submit,
                      child: _busy
                          ? const SizedBox(
                              height: 20,
                              width: 20,
                              child: CircularProgressIndicator(strokeWidth: 2),
                            )
                          : const Text('Sign in'),
                    ),
                    const SizedBox(height: 8),
                    TextButton(
                      key: const Key('go-register'),
                      onPressed: _busy ? null : widget.onShowRegister,
                      child: const Text('Create an account'),
                    ),
                    TextButton(
                      key: const Key('check-connection'),
                      onPressed: widget.onCheckConnection,
                      child: const Text('Check server connection'),
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
            child: Text(
              message,
              style: TextStyle(color: scheme.onErrorContainer),
            ),
          ),
        ],
      ),
    );
  }
}
