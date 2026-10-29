import 'dart:async';

import 'package:flutter/material.dart';
import 'package:image_picker/image_picker.dart' show ImageSource;

import '../auth/auth_models.dart';
import '../expenses/expense_models.dart';
import '../expenses/expense_repository.dart';
import 'receipt_image.dart';
import 'receipt_repository.dart';
import 'receipt_review_screen.dart';
import 'receipt_scan_controller.dart';

/// Take or choose a receipt photo, send it to be read, then review the result.
/// Pops with the saved [Expense] when the person saved one.
class ReceiptScanScreen extends StatefulWidget {
  const ReceiptScanScreen({
    super.key,
    required this.receiptRepository,
    required this.expenseRepository,
    required this.business,
    required this.categories,
    this.imagePicker,
    this.today,
  });

  final ReceiptRepository receiptRepository;
  final ExpenseRepository expenseRepository;
  final BusinessSummary business;
  final List<ExpenseCategory> categories;

  /// Injectable for tests.
  final ReceiptImagePicker? imagePicker;
  final DateTime? today;

  @override
  State<ReceiptScanScreen> createState() => _ReceiptScanScreenState();
}

class _ReceiptScanScreenState extends State<ReceiptScanScreen> {
  late final ReceiptScanController _controller;

  @override
  void initState() {
    super.initState();
    _controller = ReceiptScanController(
      repository: widget.receiptRepository,
      businessId: widget.business.id,
      imagePicker: widget.imagePicker,
    );
  }

  @override
  void dispose() {
    _controller.dispose();
    super.dispose();
  }

  Future<void> _read() async {
    final extraction = await _controller.extract();
    if (extraction == null || !mounted) return;
    final saved = await Navigator.of(context).push<Expense>(
      MaterialPageRoute<Expense>(
        builder: (_) => ReceiptReviewScreen(
          extraction: extraction,
          expenseRepository: widget.expenseRepository,
          businessId: widget.business.id,
          categories: widget.categories,
          today: widget.today,
        ),
      ),
    );
    if (saved != null && mounted) Navigator.of(context).pop(saved);
  }

  @override
  Widget build(BuildContext context) {
    final scheme = Theme.of(context).colorScheme;
    return Scaffold(
      appBar: AppBar(title: const Text('Scan receipt')),
      body: SafeArea(
        child: ListenableBuilder(
          listenable: _controller,
          builder: (context, _) {
            final image = _controller.image;
            final busy = _controller.busy;
            return ListView(
              padding: const EdgeInsets.all(16),
              children: [
                Card(
                  key: const Key('receipt-privacy-notice'),
                  color: scheme.secondaryContainer,
                  child: Padding(
                    padding: const EdgeInsets.all(16),
                    child: Text(
                      'Before you continue: when you tap "Read receipt", the photo '
                      'is sent to the HisabAI server and processed with Google\'s '
                      'Gemini service. It is not read only on your phone, and it '
                      'needs an internet connection. The server removes the photo\'s '
                      'location data and does not keep the image. The result can be '
                      'wrong, so you will check it before anything is saved.',
                      style: TextStyle(color: scheme.onSecondaryContainer),
                    ),
                  ),
                ),
                const SizedBox(height: 16),
                Row(
                  children: [
                    Expanded(
                      child: OutlinedButton.icon(
                        key: const Key('pick-camera'),
                        icon: const Icon(Icons.photo_camera),
                        label: const Text('Take photo'),
                        onPressed: busy
                            ? null
                            : () => unawaited(
                                _controller.pick(ImageSource.camera),
                              ),
                      ),
                    ),
                    const SizedBox(width: 12),
                    Expanded(
                      child: OutlinedButton.icon(
                        key: const Key('pick-gallery'),
                        icon: const Icon(Icons.photo_library),
                        label: const Text('Gallery'),
                        onPressed: busy
                            ? null
                            : () => unawaited(
                                _controller.pick(ImageSource.gallery),
                              ),
                      ),
                    ),
                  ],
                ),
                if (_controller.status == ReceiptScanStatus.preparing) ...[
                  const SizedBox(height: 16),
                  const Center(child: CircularProgressIndicator()),
                ],
                if (image != null) ...[
                  const SizedBox(height: 16),
                  ClipRRect(
                    borderRadius: BorderRadius.circular(8),
                    child: Image.memory(
                      image.bytes,
                      key: const Key('receipt-preview'),
                      height: 320,
                      fit: BoxFit.contain,
                      gaplessPlayback: true,
                      errorBuilder: (context, error, stackTrace) => const SizedBox(
                        height: 120,
                        child: Center(
                          child: Text(
                            'The preview cannot be shown, but the photo can still be read.',
                            textAlign: TextAlign.center,
                          ),
                        ),
                      ),
                    ),
                  ),
                  const SizedBox(height: 8),
                  Text(
                    '${(image.sizeBytes / 1024).round()} KB'
                    '${image.wasShrunk ? ' - scaled down to fit the upload limit' : ''}',
                    style: Theme.of(context).textTheme.bodySmall,
                    textAlign: TextAlign.center,
                  ),
                ],
                if (_controller.error != null) ...[
                  const SizedBox(height: 16),
                  Text(
                    _controller.error!,
                    key: const Key('receipt-error'),
                    style: TextStyle(color: scheme.error),
                  ),
                ],
                const SizedBox(height: 16),
                FilledButton(
                  key: const Key('receipt-extract'),
                  onPressed: _controller.canExtract
                      ? () => unawaited(_read())
                      : null,
                  child: _controller.status == ReceiptScanStatus.uploading
                      ? const SizedBox(
                          height: 20,
                          width: 20,
                          child: CircularProgressIndicator(strokeWidth: 2),
                        )
                      : Text(
                          _controller.error != null && image != null
                              ? 'Try again'
                              : 'Read receipt',
                        ),
                ),
              ],
            );
          },
        ),
      ),
    );
  }
}
