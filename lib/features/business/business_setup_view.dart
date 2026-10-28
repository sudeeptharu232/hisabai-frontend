import 'package:flutter/material.dart';

import '../../core/api/api_exception.dart';
import '../auth/auth_controller.dart';
import '../auth/validators.dart';

/// Shown to a signed-in user who does not belong to a business yet: create one,
/// or join one with a single-use invitation code from its owner.
class BusinessSetupView extends StatefulWidget {
  const BusinessSetupView({super.key, required this.auth});

  final AuthController auth;

  @override
  State<BusinessSetupView> createState() => _BusinessSetupViewState();
}

class _BusinessSetupViewState extends State<BusinessSetupView> {
  final _createKey = GlobalKey<FormState>();
  final _joinKey = GlobalKey<FormState>();
  final _name = TextEditingController();
  final _code = TextEditingController();

  bool _busy = false;
  String? _error;
  Map<String, String> _fieldErrors = const {};

  @override
  void dispose() {
    _name.dispose();
    _code.dispose();
    super.dispose();
  }

  Future<void> _run(
    GlobalKey<FormState> key,
    Future<void> Function() action,
  ) async {
    setState(() {
      _error = null;
      _fieldErrors = const {};
    });
    if (!(key.currentState?.validate() ?? false)) return;

    setState(() => _busy = true);
    try {
      await action();
      // On success the session now lists a business and the home screen updates.
    } on ValidationException catch (e) {
      if (!mounted) return;
      setState(() {
        _error = null;
        _fieldErrors = e.fieldMessages();
      });
      key.currentState?.validate();
    } on ApiException catch (e) {
      if (!mounted) return;
      setState(() => _error = e.message);
    } finally {
      if (mounted) setState(() => _busy = false);
    }
  }

  @override
  Widget build(BuildContext context) {
    final scheme = Theme.of(context).colorScheme;
    return Column(
      crossAxisAlignment: CrossAxisAlignment.stretch,
      children: [
        Text(
          'Set up your business',
          style: Theme.of(context).textTheme.titleLarge,
        ),
        const SizedBox(height: 8),
        const Text(
          'Your records belong to a business. Create yours, or join an '
          'existing one with an invitation code from its owner.',
        ),
        const SizedBox(height: 16),
        if (_error != null) ...[
          Text(_error!, style: TextStyle(color: scheme.error)),
          const SizedBox(height: 12),
        ],
        Card(
          child: Padding(
            padding: const EdgeInsets.all(16),
            child: Form(
              key: _createKey,
              child: Column(
                crossAxisAlignment: CrossAxisAlignment.stretch,
                children: [
                  Text(
                    'Create a business',
                    style: Theme.of(context).textTheme.titleMedium,
                  ),
                  const SizedBox(height: 12),
                  TextFormField(
                    key: const Key('business-name'),
                    controller: _name,
                    textCapitalization: TextCapitalization.words,
                    decoration: const InputDecoration(
                      labelText: 'Business name',
                      border: OutlineInputBorder(),
                    ),
                    validator: (v) =>
                        Validators.businessName(v) ?? _fieldErrors['name'],
                  ),
                  const SizedBox(height: 12),
                  FilledButton(
                    key: const Key('business-create'),
                    onPressed: _busy
                        ? null
                        : () => _run(
                            _createKey,
                            () => widget.auth.createBusiness(_name.text),
                          ),
                    child: const Text('Create business'),
                  ),
                ],
              ),
            ),
          ),
        ),
        const SizedBox(height: 12),
        Card(
          child: Padding(
            padding: const EdgeInsets.all(16),
            child: Form(
              key: _joinKey,
              child: Column(
                crossAxisAlignment: CrossAxisAlignment.stretch,
                children: [
                  Text(
                    'Join with an invitation code',
                    style: Theme.of(context).textTheme.titleMedium,
                  ),
                  const SizedBox(height: 12),
                  TextFormField(
                    key: const Key('invitation-code'),
                    controller: _code,
                    autocorrect: false,
                    decoration: const InputDecoration(
                      labelText: 'Invitation code',
                      border: OutlineInputBorder(),
                    ),
                    validator: (v) =>
                        Validators.invitationCode(v) ?? _fieldErrors['code'],
                  ),
                  const SizedBox(height: 12),
                  OutlinedButton(
                    key: const Key('business-join'),
                    onPressed: _busy
                        ? null
                        : () => _run(
                            _joinKey,
                            () => widget.auth.joinBusiness(_code.text),
                          ),
                    child: const Text('Join business'),
                  ),
                ],
              ),
            ),
          ),
        ),
      ],
    );
  }
}
