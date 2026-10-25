import 'package:flutter/material.dart';
import 'package:flutter/services.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:intl/intl.dart';

import '../../../core/theme/app_breakpoints.dart';
import '../../../core/theme/app_colors.dart';
import '../../../core/theme/app_spacing.dart';
import '../../../core/theme/app_typography.dart';
import '../../../shared/widgets/adaptive_dialog_shell.dart';
import '../models/billing_invoice_model.dart';
import '../providers/billing_provider.dart';

class RecordPaymentDialog extends ConsumerStatefulWidget {
  final BillingInvoiceModel invoice;

  const RecordPaymentDialog({
    super.key,
    required this.invoice,
  });

  @override
  ConsumerState<RecordPaymentDialog> createState() =>
      _RecordPaymentDialogState();
}

class _RecordPaymentDialogState extends ConsumerState<RecordPaymentDialog> {
  final _formKey = GlobalKey<FormState>();
  late final TextEditingController _amountController;
  final TextEditingController _referenceController = TextEditingController();
  final TextEditingController _notesController = TextEditingController();

  String _paymentMode = 'cash';
  DateTime _paidAt = DateTime.now();
  String? _errorMessage;

  @override
  void initState() {
    super.initState();
    // Default payment amount to full remaining balance
    _amountController = TextEditingController(
      text: widget.invoice.remainingAmount > 0
          ? widget.invoice.remainingAmount.toStringAsFixed(2)
          : '',
    );
  }

  @override
  void dispose() {
    _amountController.dispose();
    _referenceController.dispose();
    _notesController.dispose();
    super.dispose();
  }

  Future<void> _selectPaymentDate() async {
    final picked = await showDatePicker(
      context: context,
      initialDate: _paidAt,
      firstDate: DateTime(2020),
      lastDate: DateTime.now().add(const Duration(days: 30)),
    );
    if (picked != null) {
      setState(() {
        _paidAt = DateTime(
          picked.year,
          picked.month,
          picked.day,
          _paidAt.hour,
          _paidAt.minute,
        );
      });
    }
  }

  Future<void> _submitPayment() async {
    if (!_formKey.currentState!.validate()) return;

    final amount = double.tryParse(_amountController.text.trim()) ?? 0.0;
    if (amount <= 0) {
      setState(() => _errorMessage = 'Please enter a valid payment amount.');
      return;
    }
    if (amount > widget.invoice.remainingAmount) {
      setState(() => _errorMessage =
          'Payment amount cannot exceed remaining balance (₹${widget.invoice.remainingAmount.toStringAsFixed(2)}).');
      return;
    }

    setState(() => _errorMessage = null);

    try {
      final payment =
          await ref.read(recordPaymentNotifierProvider.notifier).recordPayment(
                billingId: widget.invoice.id,
                amount: amount,
                paymentMode: _paymentMode,
                paymentReference: _referenceController.text.trim().isNotEmpty
                    ? _referenceController.text.trim()
                    : null,
                paidAt: _paidAt,
                notes: _notesController.text.trim().isNotEmpty
                    ? _notesController.text.trim()
                    : null,
              );

      if (mounted) {
        Navigator.of(context).pop(payment);
      }
    } catch (e) {
      if (mounted) {
        setState(() {
          _errorMessage = e.toString().replaceFirst('Exception: ', '');
        });
      }
    }
  }

  @override
  Widget build(BuildContext context) {
    final recordState = ref.watch(recordPaymentNotifierProvider);
    final isDesktop = MediaQuery.sizeOf(context).width >= 600;

    final dialogConstraints = AdaptiveDialogConstraints.getConstraints(
      context: context,
      maxPhoneWidth: AppBreakpoints.maxDialogWidthMobile,
      maxTabletWidth: 520.0,
      maxDesktopWidth: 520.0,
    );

    return Dialog(
      insetPadding: const EdgeInsets.symmetric(
        horizontal: AppSpacing.md,
        vertical: AppSpacing.lg,
      ),
      shape: RoundedRectangleBorder(
        borderRadius: BorderRadius.circular(AppSpacing.radiusLg),
      ),
      child: Container(
        constraints: dialogConstraints,
        padding: const EdgeInsets.all(AppSpacing.md),
        child: SingleChildScrollView(
          child: Form(
            key: _formKey,
            child: Column(
              mainAxisSize: MainAxisSize.min,
              crossAxisAlignment: CrossAxisAlignment.stretch,
              children: [
                // Header
                Row(
                  mainAxisAlignment: MainAxisAlignment.spaceBetween,
                  children: [
                    Expanded(
                      child: Column(
                        crossAxisAlignment: CrossAxisAlignment.start,
                        children: [
                          Text(
                            'RECORD PAYMENT',
                            style: AppTypography.labelCaps.copyWith(
                              color: AppColors.primary,
                              letterSpacing: 1.2,
                            ),
                          ),
                          FittedBox(
                            fit: BoxFit.scaleDown,
                            alignment: Alignment.centerLeft,
                            child: Text(
                              widget.invoice.invoiceNumber,
                              style: AppTypography.headlineMd.copyWith(
                                fontWeight: FontWeight.bold,
                              ),
                            ),
                          ),
                        ],
                      ),
                    ),
                    IconButton(
                      icon: const Icon(Icons.close),
                      onPressed: () => Navigator.of(context).pop(),
                      tooltip: 'Cancel',
                    ),
                  ],
                ),
                const SizedBox(height: AppSpacing.sm),

                // Invoice Summary Box
                Container(
                  padding: const EdgeInsets.all(AppSpacing.md),
                  decoration: BoxDecoration(
                    color: AppColors.surfaceContainerLow,
                    borderRadius: BorderRadius.circular(AppSpacing.radiusMd),
                    border: Border.all(color: AppColors.outlineVariant),
                  ),
                  child: Column(
                    children: [
                      Row(
                        mainAxisAlignment: MainAxisAlignment.spaceBetween,
                        children: [
                          Expanded(
                            child: Text(
                              'Patient: ${widget.invoice.patientName ?? "—"}',
                              style: AppTypography.bodySm.copyWith(
                                fontWeight: FontWeight.w600,
                              ),
                              overflow: TextOverflow.ellipsis,
                            ),
                          ),
                          const SizedBox(width: AppSpacing.sm),
                          Text(
                            'Dept: ${widget.invoice.department.toUpperCase()}',
                            style: AppTypography.labelCaps.copyWith(
                              color: AppColors.primary,
                            ),
                          ),
                        ],
                      ),
                      const Divider(height: AppSpacing.md),
                      Row(
                        mainAxisAlignment: MainAxisAlignment.spaceBetween,
                        children: [
                          Expanded(
                            child: _summaryCol('Total Amount',
                                '₹${widget.invoice.totalAmount.toStringAsFixed(2)}'),
                          ),
                          Expanded(
                            child: _summaryCol('Already Paid',
                                '₹${widget.invoice.amountPaid.toStringAsFixed(2)}'),
                          ),
                          Expanded(
                            child: _summaryCol(
                              'Balance Due',
                              '₹${widget.invoice.remainingAmount.toStringAsFixed(2)}',
                              valueColor: AppColors.error,
                              isBold: true,
                            ),
                          ),
                        ],
                      ),
                    ],
                  ),
                ),
                const SizedBox(height: AppSpacing.md),

                // Error alert if any
                if (_errorMessage != null) ...[
                  Container(
                    padding: const EdgeInsets.all(AppSpacing.sm),
                    decoration: BoxDecoration(
                      color: AppColors.errorContainer,
                      borderRadius: BorderRadius.circular(AppSpacing.radiusSm),
                    ),
                    child: Row(
                      children: [
                        const Icon(Icons.error_outline,
                            color: AppColors.error, size: 20),
                        const SizedBox(width: AppSpacing.sm),
                        Expanded(
                          child: Text(
                            _errorMessage!,
                            style: AppTypography.bodySm.copyWith(
                              color: AppColors.onErrorContainer,
                            ),
                          ),
                        ),
                      ],
                    ),
                  ),
                  const SizedBox(height: AppSpacing.md),
                ],

                // Payment Amount input
                Text(
                  'Payment Amount (₹) *',
                  style: AppTypography.labelCaps.copyWith(
                    fontWeight: FontWeight.w600,
                    color: AppColors.onSurface,
                  ),
                ),
                const SizedBox(height: 4),
                TextFormField(
                  controller: _amountController,
                  keyboardType:
                      const TextInputType.numberWithOptions(decimal: true),
                  inputFormatters: [
                    FilteringTextInputFormatter.allow(
                        RegExp(r'^\d+\.?\d{0,2}')),
                  ],
                  decoration: InputDecoration(
                    prefixIcon: const Icon(Icons.currency_rupee, size: 20),
                    suffixIcon: TextButton(
                      onPressed: () {
                        setState(() {
                          _amountController.text =
                              widget.invoice.remainingAmount.toStringAsFixed(2);
                        });
                      },
                      child: const Text('Pay Full Due'),
                    ),
                    hintText: 'Enter amount to collect',
                    isDense: true,
                    contentPadding: const EdgeInsets.symmetric(
                      horizontal: AppSpacing.md,
                      vertical: AppSpacing.sm,
                    ),
                    border: OutlineInputBorder(
                      borderRadius: BorderRadius.circular(AppSpacing.radiusMd),
                    ),
                  ),
                  validator: (val) {
                    if (val == null || val.trim().isEmpty) {
                      return 'Amount is required.';
                    }
                    final numVal = double.tryParse(val.trim());
                    if (numVal == null || numVal <= 0) {
                      return 'Enter a valid amount greater than 0.';
                    }
                    if (numVal > widget.invoice.remainingAmount + 0.001) {
                      return 'Cannot exceed remaining balance of ₹${widget.invoice.remainingAmount.toStringAsFixed(2)}.';
                    }
                    return null;
                  },
                ),
                const SizedBox(height: AppSpacing.md),

                // Payment Mode Selection
                Text(
                  'Payment Mode *',
                  style: AppTypography.labelCaps.copyWith(
                    fontWeight: FontWeight.w600,
                    color: AppColors.onSurface,
                  ),
                ),
                const SizedBox(height: 6),
                SingleChildScrollView(
                  scrollDirection: Axis.horizontal,
                  child: SegmentedButton<String>(
                    segments: const [
                      ButtonSegment(
                        value: 'cash',
                        label: Text('Cash'),
                        icon: Icon(Icons.payments_outlined, size: 16),
                      ),
                      ButtonSegment(
                        value: 'upi',
                        label: Text('UPI'),
                        icon: Icon(Icons.qr_code_2_outlined, size: 16),
                      ),
                      ButtonSegment(
                        value: 'bank_transfer',
                        label: Text('Bank'),
                        icon: Icon(Icons.account_balance_outlined, size: 16),
                      ),
                      ButtonSegment(
                        value: 'other',
                        label: Text('Other'),
                        icon: Icon(Icons.more_horiz, size: 16),
                      ),
                    ],
                    selected: {_paymentMode},
                    onSelectionChanged: (selected) {
                      setState(() => _paymentMode = selected.first);
                    },
                  ),
                ),
                const SizedBox(height: AppSpacing.md),

                // Reference & Date (Row on Desktop, Column on Mobile)
                if (isDesktop)
                  Row(
                    children: [
                      Expanded(
                        child: _buildReferenceField(),
                      ),
                      const SizedBox(width: AppSpacing.md),
                      Expanded(
                        child: _buildDateField(),
                      ),
                    ],
                  )
                else ...[
                  _buildReferenceField(),
                  const SizedBox(height: AppSpacing.sm),
                  _buildDateField(),
                ],
                const SizedBox(height: AppSpacing.md),

                // Notes input
                Text(
                  'Notes / Remarks (Optional)',
                  style: AppTypography.labelCaps.copyWith(
                    fontWeight: FontWeight.w600,
                    color: AppColors.onSurface,
                  ),
                ),
                const SizedBox(height: 4),
                TextField(
                  controller: _notesController,
                  maxLines: 2,
                  decoration: InputDecoration(
                    hintText: 'e.g. Second installment paid via PhonePe...',
                    isDense: true,
                    contentPadding: const EdgeInsets.symmetric(
                      horizontal: AppSpacing.md,
                      vertical: AppSpacing.sm,
                    ),
                    border: OutlineInputBorder(
                      borderRadius: BorderRadius.circular(AppSpacing.radiusMd),
                    ),
                  ),
                ),
                const SizedBox(height: AppSpacing.lg),

                // Action Buttons
                if (isDesktop)
                  Row(
                    mainAxisAlignment: MainAxisAlignment.end,
                    children: [
                      TextButton(
                        onPressed: recordState.isLoading
                            ? null
                            : () => Navigator.of(context).pop(),
                        child: const Text('Cancel'),
                      ),
                      const SizedBox(width: AppSpacing.sm),
                      FilledButton.icon(
                        onPressed:
                            recordState.isLoading ? null : _submitPayment,
                        icon: recordState.isLoading
                            ? const SizedBox(
                                width: 16,
                                height: 16,
                                child: CircularProgressIndicator(
                                  strokeWidth: 2,
                                  color: Colors.white,
                                ),
                              )
                            : const Icon(Icons.check, size: 18),
                        label: Text(
                          recordState.isLoading
                              ? 'Recording...'
                              : 'Record Payment',
                        ),
                        style: FilledButton.styleFrom(
                          backgroundColor: AppColors.primary,
                          padding: const EdgeInsets.symmetric(
                            horizontal: 20,
                            vertical: 12,
                          ),
                        ),
                      ),
                    ],
                  )
                else ...[
                  SizedBox(
                    width: double.infinity,
                    child: FilledButton.icon(
                      onPressed: recordState.isLoading ? null : _submitPayment,
                      icon: recordState.isLoading
                          ? const SizedBox(
                              width: 16,
                              height: 16,
                              child: CircularProgressIndicator(
                                strokeWidth: 2,
                                color: Colors.white,
                              ),
                            )
                          : const Icon(Icons.check, size: 18),
                      label: Text(
                        recordState.isLoading
                            ? 'Recording...'
                            : 'Record Payment',
                      ),
                      style: FilledButton.styleFrom(
                        backgroundColor: AppColors.primary,
                        padding: const EdgeInsets.symmetric(
                          horizontal: 16,
                          vertical: 12,
                        ),
                      ),
                    ),
                  ),
                  const SizedBox(height: AppSpacing.xs),
                  SizedBox(
                    width: double.infinity,
                    child: TextButton(
                      onPressed: recordState.isLoading
                          ? null
                          : () => Navigator.of(context).pop(),
                      child: const Text('Cancel'),
                    ),
                  ),
                ],
              ],
            ),
          ),
        ),
      ),
    );
  }

  Widget _summaryCol(String label, String value,
      {Color? valueColor, bool isBold = false}) {
    return Column(
      crossAxisAlignment: CrossAxisAlignment.start,
      children: [
        Text(
          label,
          style: AppTypography.labelCaps.copyWith(
            color: AppColors.onSurfaceVariant,
            fontSize: 10,
          ),
          overflow: TextOverflow.ellipsis,
        ),
        const SizedBox(height: 2),
        FittedBox(
          fit: BoxFit.scaleDown,
          alignment: Alignment.centerLeft,
          child: Text(
            value,
            style: AppTypography.bodySm.copyWith(
              color: valueColor ?? AppColors.onSurface,
              fontWeight: isBold ? FontWeight.bold : FontWeight.w600,
            ),
          ),
        ),
      ],
    );
  }

  Widget _buildReferenceField() {
    return Column(
      crossAxisAlignment: CrossAxisAlignment.start,
      children: [
        Text(
          'Payment Reference / Txn ID',
          style: AppTypography.labelCaps.copyWith(
            fontWeight: FontWeight.w600,
            color: AppColors.onSurface,
          ),
        ),
        const SizedBox(height: 4),
        TextField(
          controller: _referenceController,
          decoration: InputDecoration(
            hintText: 'e.g. UPI Ref, Cheque #',
            isDense: true,
            contentPadding: const EdgeInsets.symmetric(
              horizontal: AppSpacing.md,
              vertical: AppSpacing.sm,
            ),
            border: OutlineInputBorder(
              borderRadius: BorderRadius.circular(AppSpacing.radiusMd),
            ),
          ),
        ),
      ],
    );
  }

  Widget _buildDateField() {
    return Column(
      crossAxisAlignment: CrossAxisAlignment.start,
      children: [
        Text(
          'Payment Date',
          style: AppTypography.labelCaps.copyWith(
            fontWeight: FontWeight.w600,
            color: AppColors.onSurface,
          ),
        ),
        const SizedBox(height: 4),
        InkWell(
          onTap: _selectPaymentDate,
          borderRadius: BorderRadius.circular(AppSpacing.radiusMd),
          child: Container(
            padding: const EdgeInsets.symmetric(
              horizontal: AppSpacing.md,
              vertical: 10,
            ),
            decoration: BoxDecoration(
              border: Border.all(color: AppColors.outlineVariant),
              borderRadius: BorderRadius.circular(AppSpacing.radiusMd),
            ),
            child: Row(
              mainAxisAlignment: MainAxisAlignment.spaceBetween,
              children: [
                Text(
                  DateFormat('dd MMM yyyy').format(_paidAt),
                  style: AppTypography.bodySm,
                ),
                const Icon(Icons.calendar_today_outlined,
                    size: 16, color: AppColors.primary),
              ],
            ),
          ),
        ),
      ],
    );
  }
}
