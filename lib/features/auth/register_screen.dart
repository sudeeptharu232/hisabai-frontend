import 'package:flutter/material.dart';

import '../../core/api/api_exception.dart';
import 'auth_controller.dart';
import 'validators.dart';

class RegisterScreen extends StatefulWidget {
  const RegisterScreen({
    super.key,
    required this.auth,
    required this.onShowLogin,
  });

  final AuthController auth;
  final VoidCallback onShowLogin;

  @override
  State<RegisterScreen> createState() => _RegisterScreenState();
}

class _RegisterScreenState extends State<RegisterScreen> {
  final _formKey = GlobalKey<FormState>();
  final _name = TextEditingController();
  final _email = TextEditingController();
  final _password = TextEditingController();

  bool _busy = false;
  bool _obscure = true;
  String? _formError;
  Map<String, String> _fieldErrors = const {};

  @override
  void dispose() {
    _name.dispose();
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
      await widget.auth.register(
        name: _name.text,
        email: _email.text,
        password: _password.text,
      );
      // On success the app swaps this screen for the home screen.
    } on ValidationException catch (e) {
      if (!mounted) return;
      setState(() {
        _formError = null;
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
    final scheme = Theme.of(context).colorScheme;
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
                      'Create your account',
                      style: Theme.of(context).textTheme.headlineSmall,
                    ),
                    const SizedBox(height: 24),
                    if (_formError != null) ...[
                      Text(_formError!, style: TextStyle(color: scheme.error)),
                      const SizedBox(height: 16),
                    ],
                    TextFormField(
                      key: const Key('register-name'),
                      controller: _name,
                      textCapitalization: TextCapitalization.words,
                      autofillHints: const [AutofillHints.name],
                      textInputAction: TextInputAction.next,
                      decoration: const InputDecoration(
                        labelText: 'Your name',
                        border: OutlineInputBorder(),
                      ),
                      validator: (v) =>
                          Validators.name(v) ?? _fieldErrors['name'],
                    ),
                    const SizedBox(height: 16),
                    TextFormField(
                      key: const Key('register-email'),
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
                      key: const Key('register-password'),
                      controller: _password,
                      obscureText: _obscure,
                      autofillHints: const [AutofillHints.newPassword],
                      decoration: InputDecoration(
                        labelText: 'Password (8 or more characters)',
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
                          Validators.newPassword(v) ?? _fieldErrors['password'],
                    ),
                    const SizedBox(height: 24),
                    FilledButton(
                      key: const Key('register-submit'),
                      onPressed: _busy ? null : _submit,
                      child: _busy
                          ? const SizedBox(
                              height: 20,
                              width: 20,
                              child: CircularProgressIndicator(strokeWidth: 2),
                            )
                          : const Text('Create account'),
                    ),
                    const SizedBox(height: 8),
                    TextButton(
                      key: const Key('go-login'),
                      onPressed: _busy ? null : widget.onShowLogin,
                      child: const Text('I already have an account'),
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
