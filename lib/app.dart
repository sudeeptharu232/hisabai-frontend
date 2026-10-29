import 'dart:async';

import 'package:flutter/material.dart';

import 'core/api/health_client.dart';
import 'features/auth/auth_controller.dart';
import 'features/auth/login_screen.dart';
import 'features/auth/register_screen.dart';
import 'features/health/health_screen.dart';
import 'features/expenses/expense_repository.dart';
import 'features/receipts/receipt_repository.dart';
import 'features/home/home_screen.dart';

class HisabAiApp extends StatelessWidget {
  const HisabAiApp({
    super.key,
    required this.auth,
    required this.healthClient,
    required this.expenseRepository,
    this.receiptRepository,
  });

  final AuthController auth;
  final HealthClient healthClient;
  final ExpenseRepository expenseRepository;

  /// Optional: without it the app has no "Scan receipt" entry point.
  final ReceiptRepository? receiptRepository;

  @override
  Widget build(BuildContext context) {
    return MaterialApp(
      title: 'HisabAI',
      theme: ThemeData(colorSchemeSeed: Colors.teal, useMaterial3: true),
      home: AuthGate(
        auth: auth,
        healthClient: healthClient,
        expenseRepository: expenseRepository,
        receiptRepository: receiptRepository,
      ),
    );
  }
}

/// Chooses what to show from the authentication state.
class AuthGate extends StatefulWidget {
  const AuthGate({
    super.key,
    required this.auth,
    required this.healthClient,
    required this.expenseRepository,
    this.receiptRepository,
  });

  final AuthController auth;
  final HealthClient healthClient;
  final ExpenseRepository expenseRepository;
  final ReceiptRepository? receiptRepository;

  @override
  State<AuthGate> createState() => _AuthGateState();
}

class _AuthGateState extends State<AuthGate> {
  bool _registering = false;

  @override
  void initState() {
    super.initState();
    unawaited(widget.auth.restore());
  }

  void _openConnectionCheck() {
    Navigator.of(context).push(
      MaterialPageRoute<void>(
        builder: (_) => HealthScreen(client: widget.healthClient),
      ),
    );
  }

  @override
  Widget build(BuildContext context) {
    return ListenableBuilder(
      listenable: widget.auth,
      builder: (context, _) {
        switch (widget.auth.status) {
          case AuthStatus.restoring:
            return const Scaffold(
              body: Center(child: CircularProgressIndicator()),
            );
          case AuthStatus.restoreFailed:
            return _RestoreFailedScreen(
              message:
                  widget.auth.restoreError ?? 'Could not reach the server.',
              onRetry: () => unawaited(widget.auth.restore()),
              onSignOut: () => unawaited(widget.auth.logout()),
            );
          case AuthStatus.unauthenticated:
            return _registering
                ? RegisterScreen(
                    auth: widget.auth,
                    onShowLogin: () => setState(() => _registering = false),
                  )
                : LoginScreen(
                    auth: widget.auth,
                    onShowRegister: () => setState(() => _registering = true),
                    onCheckConnection: _openConnectionCheck,
                  );
          case AuthStatus.authenticated:
            return HomeScreen(
              auth: widget.auth,
              expenseRepository: widget.expenseRepository,
              receiptRepository: widget.receiptRepository,
              onCheckConnection: _openConnectionCheck,
            );
        }
      },
    );
  }
}

class _RestoreFailedScreen extends StatelessWidget {
  const _RestoreFailedScreen({
    required this.message,
    required this.onRetry,
    required this.onSignOut,
  });

  final String message;
  final VoidCallback onRetry;
  final VoidCallback onSignOut;

  @override
  Widget build(BuildContext context) {
    return Scaffold(
      body: Center(
        child: Padding(
          padding: const EdgeInsets.all(24),
          child: Column(
            mainAxisSize: MainAxisSize.min,
            children: [
              const Icon(Icons.cloud_off, size: 64),
              const SizedBox(height: 16),
              Text(
                'Cannot verify your sign-in',
                style: Theme.of(context).textTheme.titleLarge,
              ),
              const SizedBox(height: 8),
              Text(message, textAlign: TextAlign.center),
              const SizedBox(height: 24),
              FilledButton(
                key: const Key('restore-retry'),
                onPressed: onRetry,
                child: const Text('Try again'),
              ),
              TextButton(
                key: const Key('restore-sign-out'),
                onPressed: onSignOut,
                child: const Text('Sign out'),
              ),
            ],
          ),
        ),
      ),
    );
  }
}
