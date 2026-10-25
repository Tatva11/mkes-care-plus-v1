import 'package:flutter/material.dart';

import '../../../core/theme/app_breakpoints.dart';
import '../../../core/theme/app_colors.dart';
import '../../../core/theme/app_spacing.dart';
import '../../../core/theme/app_typography.dart';
import '../../../shared/widgets/adaptive_dialog_shell.dart';
import '../models/billing_invoice_model.dart';
import '../services/billing_pdf_service.dart';

class InvoiceSuccessDialog extends StatelessWidget {
  final BillingInvoiceModel invoice;
  final VoidCallback? onCreateAnother;

  const InvoiceSuccessDialog({
    super.key,
    required this.invoice,
    this.onCreateAnother,
  });

  @override
  Widget build(BuildContext context) {
    final isPaid = invoice.isPaid;

    final dialogConstraints = AdaptiveDialogConstraints.getConstraints(
      context: context,
      maxPhoneWidth: AppBreakpoints.maxDialogWidthMobile,
      maxTabletWidth: 540.0,
      maxDesktopWidth: 540.0,
    );

    return Dialog(
      shape: RoundedRectangleBorder(
        borderRadius: BorderRadius.circular(AppSpacing.radiusLg),
      ),
      child: Container(
        constraints: dialogConstraints,
        padding: const EdgeInsets.all(AppSpacing.md),
        child: SingleChildScrollView(
          child: Column(
            mainAxisSize: MainAxisSize.min,
            children: [
              // Success icon
              Container(
                width: 52,
                height: 52,
                decoration: BoxDecoration(
                  color: Colors.green.withValues(alpha: 0.12),
                  shape: BoxShape.circle,
                ),
                child: const Center(
                  child: Icon(
                    Icons.check_circle_rounded,
                    color: Colors.green,
                    size: 32,
                  ),
                ),
              ),
              const SizedBox(height: AppSpacing.sm),
              Text(
                'Invoice Created',
                style: AppTypography.headlineMd.copyWith(
                  fontWeight: FontWeight.bold,
                  color: AppColors.onSurface,
                ),
              ),
              const SizedBox(height: AppSpacing.xs),
              Text(
                'Continuous FY Invoice Generated: ${invoice.invoiceNumber}',
                style: AppTypography.bodySm.copyWith(
                  color: AppColors.onSurfaceVariant,
                  fontWeight: FontWeight.w600,
                ),
                textAlign: TextAlign.center,
              ),
              const SizedBox(height: AppSpacing.md),

              // Invoice & Patient Banner
              Container(
                width: double.infinity,
                padding:
                    const EdgeInsets.symmetric(vertical: 10, horizontal: 14),
                decoration: BoxDecoration(
                  color: AppColors.primaryFixed.withValues(alpha: 0.45),
                  borderRadius: BorderRadius.circular(AppSpacing.radiusMd),
                  border: Border.all(
                      color: AppColors.primary.withValues(alpha: 0.25)),
                ),
                child: Wrap(
                  alignment: WrapAlignment.spaceBetween,
                  crossAxisAlignment: WrapCrossAlignment.center,
                  spacing: AppSpacing.sm,
                  runSpacing: AppSpacing.xs,
                  children: [
                    Column(
                      crossAxisAlignment: CrossAxisAlignment.start,
                      children: [
                        Text(
                          'INVOICE NUMBER',
                          style: AppTypography.labelCaps.copyWith(
                            color: AppColors.onPrimaryContainer,
                            letterSpacing: 1.1,
                            fontSize: 10,
                          ),
                        ),
                        FittedBox(
                          fit: BoxFit.scaleDown,
                          child: Text(
                            invoice.invoiceNumber,
                            style: AppTypography.headlineMd.copyWith(
                              fontWeight: FontWeight.w800,
                              color: AppColors.primary,
                            ),
                          ),
                        ),
                      ],
                    ),
                    const SizedBox(width: AppSpacing.sm),
                    Column(
                      crossAxisAlignment: CrossAxisAlignment.end,
                      children: [
                        Container(
                          padding: const EdgeInsets.symmetric(
                              horizontal: 8, vertical: 2),
                          decoration: BoxDecoration(
                            color: invoice.department == 'eye'
                                ? AppColors.primaryContainer
                                    .withValues(alpha: 0.2)
                                : AppColors.secondaryContainer
                                    .withValues(alpha: 0.2),
                            borderRadius: BorderRadius.circular(4),
                          ),
                          child: Text(
                            '${invoice.department.toUpperCase()} DEPT',
                            style: AppTypography.labelCaps.copyWith(
                              color: invoice.department == 'eye'
                                  ? AppColors.primary
                                  : AppColors.secondary,
                              fontSize: 10,
                            ),
                          ),
                        ),
                        const SizedBox(height: 2),
                        if (invoice.patientName != null)
                          Text(
                            invoice.patientName!,
                            style: AppTypography.bodySm.copyWith(
                              fontWeight: FontWeight.bold,
                              color: AppColors.onSurface,
                            ),
                            overflow: TextOverflow.ellipsis,
                          ),
                      ],
                    ),
                  ],
                ),
              ),
              const SizedBox(height: AppSpacing.md),

              // Itemized Services Breakdown Table
              if (invoice.items.isNotEmpty) ...[
                Align(
                  alignment: Alignment.centerLeft,
                  child: Text(
                    'Services Provided',
                    style: AppTypography.labelCaps.copyWith(
                      color: AppColors.onSurface,
                      fontWeight: FontWeight.bold,
                    ),
                  ),
                ),
                const SizedBox(height: 4),
                LayoutBuilder(
                  builder: (context, constraints) {
                    final availableWidth = constraints.maxWidth;
                    final tableWidth =
                        availableWidth < 380 ? 380.0 : availableWidth;
                    return SingleChildScrollView(
                      scrollDirection: Axis.horizontal,
                      child: SizedBox(
                        width: tableWidth,
                        child: Container(
                          decoration: BoxDecoration(
                            color: AppColors.surfaceContainerLowest,
                            borderRadius:
                                BorderRadius.circular(AppSpacing.radiusSm),
                            border: Border.all(color: AppColors.outlineVariant),
                          ),
                          child: Column(
                            children: [
                              // Header
                              Container(
                                padding: const EdgeInsets.symmetric(
                                    horizontal: 10, vertical: 6),
                                decoration: const BoxDecoration(
                                  color: AppColors.surfaceContainerLow,
                                  borderRadius: BorderRadius.vertical(
                                      top: Radius.circular(6)),
                                ),
                                child: Row(
                                  children: [
                                    Expanded(
                                      flex: 5,
                                      child: Text(
                                        'Service Description',
                                        style: AppTypography.labelCaps
                                            .copyWith(fontSize: 10),
                                      ),
                                    ),
                                    SizedBox(
                                      width: 35,
                                      child: Text(
                                        'Qty',
                                        textAlign: TextAlign.center,
                                        style: AppTypography.labelCaps
                                            .copyWith(fontSize: 10),
                                      ),
                                    ),
                                    SizedBox(
                                      width: 70,
                                      child: Text(
                                        'Unit Price',
                                        textAlign: TextAlign.right,
                                        style: AppTypography.labelCaps
                                            .copyWith(fontSize: 10),
                                      ),
                                    ),
                                    SizedBox(
                                      width: 80,
                                      child: Text(
                                        'Total',
                                        textAlign: TextAlign.right,
                                        style: AppTypography.labelCaps
                                            .copyWith(fontSize: 10),
                                      ),
                                    ),
                                  ],
                                ),
                              ),
                              // Line items
                              for (int i = 0;
                                  i < invoice.items.length;
                                  i++) ...[
                                Padding(
                                  padding: const EdgeInsets.symmetric(
                                      horizontal: 10, vertical: 6),
                                  child: Row(
                                    children: [
                                      Expanded(
                                        flex: 5,
                                        child: Text(
                                          invoice.items[i].serviceName,
                                          style: AppTypography.bodySm.copyWith(
                                            fontWeight: FontWeight.w600,
                                          ),
                                        ),
                                      ),
                                      SizedBox(
                                        width: 35,
                                        child: Text(
                                          '${invoice.items[i].quantity}',
                                          textAlign: TextAlign.center,
                                          style: AppTypography.bodySm,
                                        ),
                                      ),
                                      SizedBox(
                                        width: 70,
                                        child: Text(
                                          '₹${invoice.items[i].unitPrice.toStringAsFixed(2)}',
                                          textAlign: TextAlign.right,
                                          style: AppTypography.bodySm,
                                        ),
                                      ),
                                      SizedBox(
                                        width: 80,
                                        child: Text(
                                          '₹${invoice.items[i].totalAmount.toStringAsFixed(2)}',
                                          textAlign: TextAlign.right,
                                          style: AppTypography.bodySm.copyWith(
                                            fontWeight: FontWeight.bold,
                                          ),
                                        ),
                                      ),
                                    ],
                                  ),
                                ),
                                if (i < invoice.items.length - 1)
                                  const Divider(
                                      height: 1,
                                      color: AppColors.outlineVariant),
                              ],
                            ],
                          ),
                        ),
                      ),
                    );
                  },
                ),
                const SizedBox(height: AppSpacing.md),
              ],

              // Financial Summary
              Container(
                padding: const EdgeInsets.all(AppSpacing.sm),
                decoration: BoxDecoration(
                  color: AppColors.surfaceContainerLow,
                  borderRadius: BorderRadius.circular(AppSpacing.radiusSm),
                ),
                child: Column(
                  children: [
                    _DetailRow(
                      label: 'Subtotal',
                      value: '₹${invoice.subtotal.toStringAsFixed(2)}',
                    ),
                    if (invoice.discount > 0)
                      _DetailRow(
                        label: 'Discount',
                        value: '- ₹${invoice.discount.toStringAsFixed(2)}',
                        valueColor: Colors.green[800],
                      ),
                    _DetailRow(
                      label: 'Final Total',
                      value: '₹${invoice.totalAmount.toStringAsFixed(2)}',
                      isBold: true,
                    ),
                    _DetailRow(
                      label: 'Amount Paid',
                      value: '₹${invoice.amountPaid.toStringAsFixed(2)}',
                      valueColor: AppColors.primary,
                    ),
                    _DetailRow(
                      label: 'Remaining Balance',
                      value: '₹${invoice.remainingAmount.toStringAsFixed(2)}',
                      valueColor: invoice.remainingAmount > 0
                          ? AppColors.error
                          : Colors.green[800],
                      isBold: true,
                    ),
                    const Divider(height: 12),
                    Row(
                      mainAxisAlignment: MainAxisAlignment.spaceBetween,
                      children: [
                        Flexible(
                          child: Text(
                            'Payment Status:',
                            style: AppTypography.bodySm.copyWith(
                              fontWeight: FontWeight.w600,
                            ),
                            overflow: TextOverflow.ellipsis,
                          ),
                        ),
                        Container(
                          padding: const EdgeInsets.symmetric(
                              horizontal: 8, vertical: 3),
                          decoration: BoxDecoration(
                            color: isPaid ? Colors.green : Colors.orange,
                            borderRadius: BorderRadius.circular(4),
                          ),
                          child: Text(
                            isPaid ? 'PAID' : 'PARTIALLY PAID',
                            style: const TextStyle(
                              color: Colors.white,
                              fontSize: 10,
                              fontWeight: FontWeight.bold,
                            ),
                          ),
                        ),
                      ],
                    ),
                  ],
                ),
              ),
              const SizedBox(height: AppSpacing.lg),

              // Download Invoice PDF Button
              SizedBox(
                width: double.infinity,
                child: _DownloadInvoicePdfButton(
                  key: const Key('success_dialog_download_pdf_button'),
                  invoice: invoice,
                ),
              ),
              const SizedBox(height: AppSpacing.sm),

              // Action Buttons
              Row(
                children: [
                  if (onCreateAnother != null) ...[
                    Expanded(
                      child: OutlinedButton(
                        onPressed: () {
                          Navigator.of(context).pop();
                          onCreateAnother!();
                        },
                        style: OutlinedButton.styleFrom(
                          padding: const EdgeInsets.symmetric(vertical: 12),
                        ),
                        child: const FittedBox(
                          fit: BoxFit.scaleDown,
                          child: Text('Create Another'),
                        ),
                      ),
                    ),
                    const SizedBox(width: AppSpacing.sm),
                  ],
                  Expanded(
                    child: FilledButton(
                      onPressed: () => Navigator.of(context).pop(invoice),
                      style: FilledButton.styleFrom(
                        backgroundColor: AppColors.primary,
                        padding: const EdgeInsets.symmetric(vertical: 12),
                      ),
                      child: const Text('Done'),
                    ),
                  ),
                ],
              ),
            ],
          ),
        ),
      ),
    );
  }
}

class _DownloadInvoicePdfButton extends StatefulWidget {
  final BillingInvoiceModel invoice;
  const _DownloadInvoicePdfButton({super.key, required this.invoice});

  @override
  State<_DownloadInvoicePdfButton> createState() =>
      _DownloadInvoicePdfButtonState();
}

class _DownloadInvoicePdfButtonState extends State<_DownloadInvoicePdfButton> {
  bool _isLoading = false;

  @override
  Widget build(BuildContext context) {
    return OutlinedButton.icon(
      key: const Key('invoice_success_download_pdf_button'),
      onPressed: _isLoading
          ? null
          : () async {
              setState(() => _isLoading = true);
              try {
                final pdfService = BillingPdfService();
                await pdfService.downloadOrShareInvoicePdf(widget.invoice);
                if (context.mounted) {
                  ScaffoldMessenger.of(context).showSnackBar(
                    SnackBar(
                      content: Text(
                        'Invoice ${widget.invoice.invoiceNumber} PDF downloaded successfully.',
                      ),
                      backgroundColor: Colors.green[800],
                      behavior: SnackBarBehavior.floating,
                    ),
                  );
                }
              } catch (e) {
                if (context.mounted) {
                  ScaffoldMessenger.of(context).showSnackBar(
                    SnackBar(
                      content: Text('Failed to generate PDF: $e'),
                      backgroundColor: Colors.red[800],
                      behavior: SnackBarBehavior.floating,
                    ),
                  );
                }
              } finally {
                if (mounted) setState(() => _isLoading = false);
              }
            },
      icon: _isLoading
          ? const SizedBox(
              width: 14,
              height: 14,
              child: CircularProgressIndicator(strokeWidth: 2),
            )
          : const Icon(Icons.picture_as_pdf_outlined, size: 18),
      label: Text(_isLoading ? 'Generating PDF...' : 'Download Invoice PDF'),
      style: OutlinedButton.styleFrom(
        foregroundColor: AppColors.primary,
        side: const BorderSide(color: AppColors.primary),
        padding: const EdgeInsets.symmetric(vertical: 12),
      ),
    );
  }
}

class _DetailRow extends StatelessWidget {
  final String label;
  final String value;
  final Color? valueColor;
  final bool isBold;

  const _DetailRow({
    required this.label,
    required this.value,
    this.valueColor,
    this.isBold = false,
  });

  @override
  Widget build(BuildContext context) {
    return Padding(
      padding: const EdgeInsets.symmetric(vertical: 3),
      child: Row(
        mainAxisAlignment: MainAxisAlignment.spaceBetween,
        children: [
          Flexible(
            child: Text(
              label,
              style: AppTypography.bodySm.copyWith(
                color: AppColors.onSurfaceVariant,
              ),
              overflow: TextOverflow.ellipsis,
            ),
          ),
          const SizedBox(width: AppSpacing.sm),
          Flexible(
            child: Text(
              value,
              style: AppTypography.bodySm.copyWith(
                color: valueColor ?? AppColors.onSurface,
                fontWeight: isBold ? FontWeight.bold : FontWeight.w500,
              ),
              textAlign: TextAlign.end,
              overflow: TextOverflow.ellipsis,
            ),
          ),
        ],
      ),
    );
  }
}
