import 'package:flutter/material.dart';

import '../../core/api/api_exception.dart';
import '../auth/auth_controller.dart';
import '../auth/auth_models.dart';
import '../business/business_setup_view.dart';
import '../expenses/expense_list_screen.dart';
import '../expenses/expense_repository.dart';

/// Shown after sign-in. M1 content only: who is signed in, which business they
/// belong to, and a button that makes a fresh authenticated request.
class HomeScreen extends StatefulWidget {
  const HomeScreen({
    super.key,
    required this.auth,
    required this.expenseRepository,
    required this.onCheckConnection,
  });

  final AuthController auth;
  final ExpenseRepository expenseRepository;
  final VoidCallback onCheckConnection;

  @override
  State<HomeScreen> createState() => _HomeScreenState();
}

class _HomeScreenState extends State<HomeScreen> {
  bool _refreshing = false;
  String? _refreshError;

  Future<void> _refresh() async {
    setState(() {
      _refreshing = true;
      _refreshError = null;
    });
    try {
      await widget.auth.refresh();
    } on ApiException catch (e) {
      if (!mounted) return;
      setState(() => _refreshError = e.message);
    } finally {
      if (mounted) setState(() => _refreshing = false);
    }
  }

  Future<void> _createInvitation(BusinessSummary business) async {
    try {
      final invitation = await widget.auth.createInvitation(business.id);
      if (!mounted) return;
      await showDialog<void>(
        context: context,
        builder: (dialogContext) => AlertDialog(
          title: const Text('Invitation code'),
          content: Column(
            mainAxisSize: MainAxisSize.min,
            crossAxisAlignment: CrossAxisAlignment.start,
            children: [
              SelectableText(
                invitation.code,
                key: const Key('invitation-code-text'),
                style: Theme.of(dialogContext).textTheme.titleMedium,
              ),
              const SizedBox(height: 12),
              const Text(
                'Share it only with the person you want to add. It works '
                'once, and expires in 72 hours. It will not be shown again.',
              ),
            ],
          ),
          actions: [
            TextButton(
              onPressed: () => Navigator.of(dialogContext).pop(),
              child: const Text('Close'),
            ),
          ],
        ),
      );
    } on ApiException catch (e) {
      if (!mounted) return;
      ScaffoldMessenger.of(context)
          .showSnackBar(SnackBar(content: Text(e.message)));
    }
  }

  @override
  Widget build(BuildContext context) {
    final session = widget.auth.session;
    if (session == null) return const SizedBox.shrink();
    final business = session.business;
    final verified = widget.auth.lastVerifiedAt;

    return Scaffold(
      appBar: AppBar(
        title: const Text('HisabAI'),
        actions: [
          IconButton(
            key: const Key('logout'),
            tooltip: 'Sign out',
            icon: const Icon(Icons.logout),
            onPressed: widget.auth.logout,
          ),
        ],
      ),
      body: SafeArea(
        child: ListView(
          padding: const EdgeInsets.all(24),
          children: [
            Card(
              child: ListTile(
                leading: const Icon(Icons.person),
                title: Text(session.user.name),
                subtitle: Text(session.user.email),
              ),
            ),
            const SizedBox(height: 16),
            if (business == null)
              BusinessSetupView(auth: widget.auth)
            else
              Card(
                child: Padding(
                  padding: const EdgeInsets.all(16),
                  child: Column(
                    crossAxisAlignment: CrossAxisAlignment.start,
                    children: [
                      Text(
                        business.name,
                        style: Theme.of(context).textTheme.titleLarge,
                      ),
                      const SizedBox(height: 4),
                      Text(
                        'Your role: ${business.isOwner ? 'Owner' : 'Member'}',
                      ),
                      const SizedBox(height: 12),
                      FilledButton.icon(
                        key: const Key('open-expenses'),
                        icon: const Icon(Icons.receipt_long),
                        label: const Text('Expenses'),
                        onPressed: () => Navigator.of(context).push<void>(
                          MaterialPageRoute<void>(
                            builder: (_) => ExpenseListScreen(
                              repository: widget.expenseRepository,
                              business: business,
                              user: session.user,
                            ),
                          ),
                        ),
                      ),
                      if (business.isOwner) ...[
                        const SizedBox(height: 12),
                        OutlinedButton.icon(
                          key: const Key('create-invitation'),
                          icon: const Icon(Icons.person_add),
                          label: const Text('Invite someone'),
                          onPressed: () => _createInvitation(business),
                        ),
                      ],
                    ],
                  ),
                ),
              ),
            const SizedBox(height: 16),
            Card(
              child: Padding(
                padding: const EdgeInsets.all(16),
                child: Column(
                  crossAxisAlignment: CrossAxisAlignment.start,
                  children: [
                    Text(
                      'Server check',
                      style: Theme.of(context).textTheme.titleMedium,
                    ),
                    const SizedBox(height: 4),
                    Text(
                      verified == null
                          ? 'Not yet verified.'
                          : 'Signed-in session verified with the server at '
                              '${TimeOfDay.fromDateTime(verified).format(context)}.',
                    ),
                    if (_refreshError != null) ...[
                      const SizedBox(height: 4),
                      Text(
                        _refreshError!,
                        style: TextStyle(
                          color: Theme.of(context).colorScheme.error,
                        ),
                      ),
                    ],
                    const SizedBox(height: 12),
                    Wrap(
                      spacing: 8,
                      children: [
                        FilledButton.tonal(
                          key: const Key('refresh'),
                          onPressed: _refreshing ? null : _refresh,
                          child: _refreshing
                              ? const SizedBox(
                                  height: 18,
                                  width: 18,
                                  child: CircularProgressIndicator(
                                    strokeWidth: 2,
                                  ),
                                )
                              : const Text('Verify session'),
                        ),
                        TextButton(
                          key: const Key('check-connection-home'),
                          onPressed: widget.onCheckConnection,
                          child: const Text('Connection status'),
                        ),
                      ],
                    ),
                  ],
                ),
              ),
            ),
          ],
        ),
      ),
    );
  }
}
