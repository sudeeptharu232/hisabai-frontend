import 'dart:async';

import 'package:flutter/material.dart';

import '../../core/api/health_client.dart';

/// M0 connectivity screen: calls the API health endpoint and reports the result.
class HealthScreen extends StatefulWidget {
  const HealthScreen({super.key, required this.client});

  final HealthClient client;

  @override
  State<HealthScreen> createState() => _HealthScreenState();
}

class _HealthScreenState extends State<HealthScreen> {
  HealthResult? _result;
  bool _checking = false;

  @override
  void initState() {
    super.initState();
    unawaited(_runCheck());
  }

  Future<void> _runCheck() async {
    setState(() => _checking = true);
    final result = await widget.client.check();
    if (!mounted) return;
    setState(() {
      _result = result;
      _checking = false;
    });
  }

  @override
  Widget build(BuildContext context) {
    return Scaffold(
      appBar: AppBar(title: const Text('HisabAI')),
      body: Center(
        child: Padding(
          padding: const EdgeInsets.all(24),
          child: Column(
            mainAxisSize: MainAxisSize.min,
            children: [
              _StatusView(checking: _checking, result: _result),
              const SizedBox(height: 24),
              FilledButton(
                onPressed: _checking ? null : _runCheck,
                child: const Text('Check again'),
              ),
            ],
          ),
        ),
      ),
    );
  }
}

class _StatusView extends StatelessWidget {
  const _StatusView({required this.checking, required this.result});

  final bool checking;
  final HealthResult? result;

  @override
  Widget build(BuildContext context) {
    if (checking || result == null) {
      return const Column(
        mainAxisSize: MainAxisSize.min,
        children: [
          CircularProgressIndicator(),
          SizedBox(height: 16),
          Text('Contacting server…'),
        ],
      );
    }
    return switch (result!) {
      HealthOk() => const _Message(
        icon: Icons.check_circle,
        color: Colors.green,
        title: 'API is reachable',
        detail: 'The server and its database are healthy.',
      ),
      HealthDegraded(:final databaseStatus) => _Message(
        icon: Icons.warning_amber_rounded,
        color: Colors.orange,
        title: 'Server reachable, database unavailable',
        detail: 'Database status: $databaseStatus.',
      ),
      HealthFailure(:final message) => _Message(
        icon: Icons.error_outline,
        color: Colors.red,
        title: 'Connection problem',
        detail: message,
      ),
    };
  }
}

class _Message extends StatelessWidget {
  const _Message({
    required this.icon,
    required this.color,
    required this.title,
    required this.detail,
  });

  final IconData icon;
  final Color color;
  final String title;
  final String detail;

  @override
  Widget build(BuildContext context) {
    return Column(
      mainAxisSize: MainAxisSize.min,
      children: [
        Icon(icon, color: color, size: 64),
        const SizedBox(height: 16),
        Text(title, style: Theme.of(context).textTheme.titleLarge),
        const SizedBox(height: 8),
        Text(detail, textAlign: TextAlign.center),
      ],
    );
  }
}
