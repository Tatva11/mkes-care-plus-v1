import 'package:flutter/material.dart';
import 'package:flutter/services.dart';

import '../../../core/theme/app_colors.dart';
import '../../../core/theme/app_spacing.dart';
import '../../../core/theme/app_typography.dart';
import '../models/billing_payment_model.dart';

class InvoicePaymentSection extends StatefulWidget {
  final double subtotal;
  final double discount;
  final double finalTotal;
  final ValueChanged<double> onDiscountChanged;
  final BillingPaymentModel? payment;
  final ValueChanged<BillingPaymentModel?> onPaymentChanged;

  const InvoicePaymentSection({
    super.key,
    required this.subtotal,
    required this.discount,
    required this.finalTotal,
    required this.onDiscountChanged,
    required this.payment,
    required this.onPaymentChanged,
  });

  @override
  State<InvoicePaymentSection> createState() => _InvoicePaymentSectionState();
}

class _InvoicePaymentSectionState extends State<InvoicePaymentSection> {
  late TextEditingController _discountController;
  late TextEditingController _amountPaidController;
  late TextEditingController _referenceController;

  String _paymentMode = 'cash';
  double _amountPaid = 0.0;

  @override
  void initState() {
    super.initState();
    _discountController = TextEditingController(
      text: widget.discount > 0 ? widget.discount.toStringAsFixed(0) : '',
    );
    _paymentMode = widget.payment?.paymentMode ?? 'cash';
    _amountPaid = widget.payment?.amount ?? widget.finalTotal;
    _amountPaidController = TextEditingController(
      text: _amountPaid > 0 ? _amountPaid.toStringAsFixed(0) : '',
    );
    _referenceController = TextEditingController(
      text: widget.payment?.paymentReference ?? '',
    );

    // Default amount paid to final total
    if (widget.payment == null && widget.finalTotal > 0) {
      WidgetsBinding.instance.addPostFrameCallback((_) {
        _amountPaid = widget.finalTotal;
        _amountPaidController.text = _amountPaid > 0 ? _amountPaid.toStringAsFixed(0) : '';
        _notifyPaymentChanged();
      });
    }
  }

  @override
  void didUpdateWidget(covariant InvoicePaymentSection oldWidget) {
    super.didUpdateWidget(oldWidget);
    if (oldWidget.discount != widget.discount &&
        _discountController.text != widget.discount.toStringAsFixed(0)) {
      _discountController.text =
          widget.discount > 0 ? widget.discount.toStringAsFixed(0) : '';
    }

    if (oldWidget.finalTotal != widget.finalTotal) {
      if (_amountPaid > widget.finalTotal) {
        _amountPaid = widget.finalTotal;
        _amountPaidController.text =
            _amountPaid > 0 ? _amountPaid.toStringAsFixed(0) : '';
        _notifyPaymentChanged();
      }
    }
  }

  @override
  void dispose() {
    _discountController.dispose();
    _amountPaidController.dispose();
    _referenceController.dispose();
    super.dispose();
  }

  void _notifyPaymentChanged() {
    if (_amountPaid <= 0) {
      widget.onPaymentChanged(null);
    } else {
      widget.onPaymentChanged(
        BillingPaymentModel(
          amount: _amountPaid,
          paymentMode: _paymentMode,
          paymentReference: _referenceController.text.trim().isNotEmpty
              ? _referenceController.text.trim()
              : null,
        ),
      );
    }
  }

  @override
  Widget build(BuildContext context) {
    final remaining = (widget.finalTotal - _amountPaid).clamp(0.0, double.infinity);
    final isPaid = _amountPaid >= widget.finalTotal && widget.finalTotal > 0;

    return Container(
      padding: const EdgeInsets.all(AppSpacing.md),
      decoration: BoxDecoration(
        color: AppColors.surfaceContainerLowest,
        borderRadius: BorderRadius.circular(AppSpacing.radiusMd),
        border: Border.all(color: AppColors.outlineVariant),
      ),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          // Header
          Row(
            mainAxisAlignment: MainAxisAlignment.spaceBetween,
            children: [
              Text(
                'Financial Summary & Payment',
                style: AppTypography.bodyMd.copyWith(
                  fontWeight: FontWeight.w700,
                  color: AppColors.onSurface,
                ),
              ),
              Container(
                padding: const EdgeInsets.symmetric(horizontal: 8, vertical: 3),
                decoration: BoxDecoration(
                  color: AppColors.surfaceContainerHigh,
                  borderRadius: BorderRadius.circular(AppSpacing.radiusSm),
                ),
                child: Text(
                  'No GST applied',
                  style: AppTypography.labelCaps.copyWith(
                    color: AppColors.onSurfaceVariant,
                    fontWeight: FontWeight.w500,
                  ),
                ),
              ),
            ],
          ),
          const Divider(height: AppSpacing.lg),

          // Subtotal, Discount, Final Total
          Row(
            children: [
              Expanded(
                child: _SummaryBox(
                  label: 'Subtotal',
                  amount: '₹${widget.subtotal.toStringAsFixed(2)}',
                  color: AppColors.onSurface,
                ),
              ),
              const SizedBox(width: AppSpacing.sm),
              Expanded(
                child: Column(
                  crossAxisAlignment: CrossAxisAlignment.start,
                  children: [
                    Text(
                      'Discount (₹)',
                      style: AppTypography.labelCaps.copyWith(color: AppColors.outline),
                    ),
                    const SizedBox(height: 2),
                    TextField(
                      controller: _discountController,
                      keyboardType: const TextInputType.numberWithOptions(decimal: true),
                      inputFormatters: [
                        FilteringTextInputFormatter.allow(RegExp(r'^\d*\.?\d{0,2}')),
                      ],
                      decoration: const InputDecoration(
                        isDense: true,
                        prefixText: '₹ ',
                        hintText: '0',
                      ),
                      onChanged: (val) {
                        final disc = double.tryParse(val) ?? 0.0;
                        final clamped = disc.clamp(0.0, widget.subtotal);
                        widget.onDiscountChanged(clamped);
                      },
                    ),
                  ],
                ),
              ),
              const SizedBox(width: AppSpacing.sm),
              Expanded(
                child: _SummaryBox(
                  label: 'Final Total',
                  amount: '₹${widget.finalTotal.toStringAsFixed(2)}',
                  color: AppColors.primary,
                  isBold: true,
                ),
              ),
            ],
          ),
          const SizedBox(height: AppSpacing.lg),

          // Payment Mode Selector
          Text(
            'Payment Mode',
            style: AppTypography.labelCaps.copyWith(color: AppColors.outline),
          ),
          const SizedBox(height: AppSpacing.xs),
          SegmentedButton<String>(
            segments: const [
              ButtonSegment(
                value: 'cash',
                label: Text('Cash'),
                icon: Icon(Icons.money_outlined, size: 16),
              ),
              ButtonSegment(
                value: 'upi',
                label: Text('UPI'),
                icon: Icon(Icons.qr_code_2_outlined, size: 16),
              ),
              ButtonSegment(
                value: 'bank_transfer',
                label: Text('Bank Transfer'),
                icon: Icon(Icons.account_balance_outlined, size: 16),
              ),
              ButtonSegment(
                value: 'other',
                label: Text('Other'),
                icon: Icon(Icons.credit_card_outlined, size: 16),
              ),
            ],
            selected: {_paymentMode},
            onSelectionChanged: (selection) {
              setState(() {
                _paymentMode = selection.first;
              });
              _notifyPaymentChanged();
            },
          ),
          const SizedBox(height: AppSpacing.md),

          // Payment Reference (for UPI, Bank Transfer, Other)
          if (_paymentMode != 'cash') ...[
            TextField(
              controller: _referenceController,
              decoration: InputDecoration(
                labelText: _paymentMode == 'upi'
                    ? 'UPI Transaction ID / Ref No.'
                    : _paymentMode == 'bank_transfer'
                        ? 'Cheque / NEFT / IMPS Reference'
                        : 'Payment Reference',
                hintText: 'e.g. UPI/123456789012',
                isDense: true,
                prefixIcon: const Icon(Icons.receipt_long_outlined, size: 18),
              ),
              onChanged: (_) => _notifyPaymentChanged(),
            ),
            const SizedBox(height: AppSpacing.md),
          ],

          // Amount Paid input & Remaining Balance Display (Presets removed, auto-determining Paid/Partially Paid)
          Row(
            crossAxisAlignment: CrossAxisAlignment.start,
            children: [
              Expanded(
                flex: 3,
                child: TextField(
                  controller: _amountPaidController,
                  keyboardType: const TextInputType.numberWithOptions(decimal: true),
                  inputFormatters: [
                    FilteringTextInputFormatter.allow(RegExp(r'^\d*\.?\d{0,2}')),
                  ],
                  decoration: InputDecoration(
                    labelText: 'Amount Paid (₹) *',
                    prefixText: '₹ ',
                    isDense: true,
                    errorText: _amountPaid > widget.finalTotal
                        ? 'Amount cannot exceed ₹${widget.finalTotal.toStringAsFixed(2)}'
                        : null,
                  ),
                  onChanged: (val) {
                    final amt = double.tryParse(val) ?? 0.0;
                    setState(() {
                      _amountPaid = amt;
                    });
                    _notifyPaymentChanged();
                  },
                ),
              ),
              const SizedBox(width: AppSpacing.md),
              Expanded(
                flex: 3,
                child: Container(
                  padding: const EdgeInsets.symmetric(horizontal: 12, vertical: 8),
                  decoration: BoxDecoration(
                    color: isPaid
                        ? Colors.green.withValues(alpha: 0.08)
                        : Colors.orange.withValues(alpha: 0.08),
                    borderRadius: BorderRadius.circular(AppSpacing.radiusSm),
                    border: Border.all(
                      color: isPaid
                          ? Colors.green.withValues(alpha: 0.3)
                          : Colors.orange.withValues(alpha: 0.3),
                    ),
                  ),
                  child: Column(
                    crossAxisAlignment: CrossAxisAlignment.start,
                    children: [
                      Row(
                        mainAxisAlignment: MainAxisAlignment.spaceBetween,
                        children: [
                          Text(
                            'Remaining:',
                            style: AppTypography.labelCaps.copyWith(
                              color: AppColors.outline,
                            ),
                          ),
                          Container(
                            padding: const EdgeInsets.symmetric(horizontal: 6, vertical: 1),
                            decoration: BoxDecoration(
                              color: isPaid ? Colors.green : Colors.orange,
                              borderRadius: BorderRadius.circular(4),
                            ),
                            child: Text(
                              isPaid ? 'PAID' : 'PARTIALLY PAID',
                              style: const TextStyle(
                                color: Colors.white,
                                fontSize: 9,
                                fontWeight: FontWeight.bold,
                              ),
                            ),
                          ),
                        ],
                      ),
                      const SizedBox(height: 2),
                      Text(
                        '₹${remaining.toStringAsFixed(2)}',
                        style: AppTypography.bodyMd.copyWith(
                          fontWeight: FontWeight.bold,
                          color: remaining > 0 ? AppColors.error : Colors.green[800],
                        ),
                      ),
                    ],
                  ),
                ),
              ),
            ],
          ),
        ],
      ),
    );
  }
}

class _SummaryBox extends StatelessWidget {
  final String label;
  final String amount;
  final Color color;
  final bool isBold;

  const _SummaryBox({
    required this.label,
    required this.amount,
    required this.color,
    this.isBold = false,
  });

  @override
  Widget build(BuildContext context) {
    return Container(
      padding: const EdgeInsets.symmetric(horizontal: 10, vertical: 8),
      decoration: BoxDecoration(
        color: AppColors.surfaceContainerLow,
        borderRadius: BorderRadius.circular(AppSpacing.radiusSm),
      ),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Text(
            label,
            style: AppTypography.labelCaps.copyWith(color: AppColors.outline),
          ),
          const SizedBox(height: 2),
          Text(
            amount,
            style: AppTypography.bodyMd.copyWith(
              color: color,
              fontWeight: isBold ? FontWeight.bold : FontWeight.w600,
            ),
          ),
        ],
      ),
    );
  }
}
