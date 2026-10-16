import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';

import '../../../core/theme/app_colors.dart';
import '../../../core/theme/app_spacing.dart';
import '../../../core/theme/app_typography.dart';
import '../models/eye_surgery_model.dart';
import '../providers/eye_surgery_provider.dart';

/// Pre-discharge verification dialog that displays the surgery's billing status
/// and insurance status separately prior to confirming discharge.
class EyeSurgeryDischargeDialog extends ConsumerStatefulWidget {
  final EyeSurgeryModel surgery;

  const EyeSurgeryDischargeDialog({
    super.key,
    required this.surgery,
  });

  @override
  ConsumerState<EyeSurgeryDischargeDialog> createState() =>
      _EyeSurgeryDischargeDialogState();
}

class _EyeSurgeryDischargeDialogState
    extends ConsumerState<EyeSurgeryDischargeDialog> {
  late TextEditingController _remarksController;
  bool _isDischarging = false;

  @override
  void initState() {
    super.initState();
    _remarksController =
        TextEditingController(text: widget.surgery.remarks ?? '');
  }

  @override
  void dispose() {
    _remarksController.dispose();
    super.dispose();
  }

  @override
  Widget build(BuildContext context) {
    final invoiceAsync = ref.watch(eyeSurgeryInvoiceProvider(widget.surgery.id));
    final insuranceAsync = ref.watch(eyeSurgeryInsuranceProvider(widget.surgery.id));
    final summary = ref.watch(eyeSurgeryFinancialSummaryProvider(widget.surgery.id));

    final invoice = invoiceAsync.valueOrNull;
    final insurance = insuranceAsync.valueOrNull;

    final hasPendingPatientBalance = summary.remainingPatientBalance > 0.01;
    final hasPendingInsurer = summary.insuranceAmountPending > 0.01;

    return Dialog(
      shape: RoundedRectangleBorder(
        borderRadius: BorderRadius.circular(AppSpacing.radiusLg),
      ),
      child: ConstrainedBox(
        constraints: const BoxConstraints(maxWidth: 580, maxHeight: 680),
        child: Padding(
          padding: const EdgeInsets.all(AppSpacing.lg),
          child: Column(
            crossAxisAlignment: CrossAxisAlignment.stretch,
            children: [
              // Title
              Row(
                children: [
                  Container(
                    padding: const EdgeInsets.all(8),
                    decoration: BoxDecoration(
                      color: AppColors.primaryContainer.withValues(alpha: 0.3),
                      borderRadius: BorderRadius.circular(8),
                    ),
                    child: const Icon(Icons.exit_to_app, color: AppColors.primary),
                  ),
                  const SizedBox(width: AppSpacing.md),
                  Expanded(
                    child: Column(
                      crossAxisAlignment: CrossAxisAlignment.start,
                      children: [
                        Text(
                          'Confirm Patient Discharge',
                          style: AppTypography.headlineMd.copyWith(
                            fontWeight: FontWeight.bold,
                            fontSize: 18,
                          ),
                        ),
                        Text(
                          '${widget.surgery.patientName ?? "Patient"} · ${widget.surgery.displaySurgeryType}',
                          style: AppTypography.bodySm.copyWith(
                            color: AppColors.onSurfaceVariant,
                          ),
                        ),
                      ],
                    ),
                  ),
                  IconButton(
                    icon: const Icon(Icons.close),
                    onPressed: () => Navigator.of(context).pop(false),
                  ),
                ],
              ),
              const SizedBox(height: AppSpacing.sm),
              const Divider(height: 1),
              const SizedBox(height: AppSpacing.md),

              Expanded(
                child: SingleChildScrollView(
                  child: Column(
                    crossAxisAlignment: CrossAxisAlignment.stretch,
                    children: [
                      // Section 6 requirement: Show Billing Status
                      _buildCard(
                        title: 'SURGERY BILLING STATUS',
                        icon: Icons.receipt_long_outlined,
                        child: Column(
                          children: [
                            _buildRow('Invoice Status',
                                invoice != null ? 'Invoice #${invoice.invoiceNumber}' : 'No Invoice Created',
                                isBold: true),
                            _buildRow('Total Surgery Bill',
                                '₹${summary.totalSurgeryBill.toStringAsFixed(2)}'),
                            _buildRow("Patient's Payable Share",
                                '₹${summary.patientPayableShare.toStringAsFixed(2)}'),
                            _buildRow('Patient Payments Received',
                                '₹${summary.patientPaymentsReceived.toStringAsFixed(2)}',
                                color: Colors.green.shade800),
                            _buildRow('Remaining Patient Balance',
                                '₹${summary.remainingPatientBalance.toStringAsFixed(2)}',
                                color: hasPendingPatientBalance
                                    ? AppColors.error
                                    : Colors.green.shade800,
                                isBold: true),
                          ],
                        ),
                      ),
                      const SizedBox(height: AppSpacing.md),

                      // Section 6 requirement: Show Insurance Status & Pending Insurer separately
                      _buildCard(
                        title: 'INSURANCE STATUS (EYE SURGERY)',
                        icon: Icons.health_and_safety_outlined,
                        child: insurance != null
                            ? Column(
                                children: [
                                  _buildRow('Insurance Provider',
                                      insurance.insuranceProvider),
                                  _buildRow('Arrangement',
                                      insurance.arrangement.label),
                                  _buildRow('Claim Status',
                                      insurance.claimStatus.label,
                                      isBold: true),
                                  _buildRow('Approved Coverage',
                                      '₹${summary.approvedInsuranceCoverage.toStringAsFixed(2)}'),
                                  _buildRow('Insurance Received by Clinic',
                                      '₹${summary.insuranceAmountReceivedByClinic.toStringAsFixed(2)}',
                                      color: Colors.green.shade800),
                                  _buildRow(
                                    'Pending from Insurer (Separate from Patient)',
                                    '₹${summary.insuranceAmountPending.toStringAsFixed(2)}',
                                    color: hasPendingInsurer
                                        ? Colors.orange.shade800
                                        : Colors.green.shade800,
                                    isBold: true,
                                  ),
                                ],
                              )
                            : const Padding(
                                padding: EdgeInsets.symmetric(vertical: 4),
                                child: Text(
                                  'No insurance record for this surgery (Direct Patient Billing).',
                                  style: TextStyle(
                                    fontSize: 12,
                                    fontStyle: FontStyle.italic,
                                    color: AppColors.onSurfaceVariant,
                                  ),
                                ),
                              ),
                      ),
                      const SizedBox(height: AppSpacing.md),

                      // Informative Alert Badges
                      if (hasPendingPatientBalance) ...[
                        Container(
                          padding: const EdgeInsets.all(AppSpacing.sm),
                          decoration: BoxDecoration(
                            color: Colors.amber.shade50,
                            borderRadius:
                                BorderRadius.circular(AppSpacing.radiusSm),
                            border: Border.all(color: Colors.amber.shade300),
                          ),
                          child: Row(
                            children: [
                              Icon(Icons.info_outline,
                                  color: Colors.amber.shade900, size: 20),
                              const SizedBox(width: AppSpacing.sm),
                              Expanded(
                                child: Text(
                                  'Patient has an outstanding balance of ₹${summary.remainingPatientBalance.toStringAsFixed(2)}. Clinic policy permits discharge while keeping the remaining debt on file.',
                                  style: TextStyle(
                                    fontSize: 12,
                                    color: Colors.amber.shade900,
                                  ),
                                ),
                              ),
                            ],
                          ),
                        ),
                        const SizedBox(height: AppSpacing.sm),
                      ],

                      if (hasPendingInsurer) ...[
                        Container(
                          padding: const EdgeInsets.all(AppSpacing.sm),
                          decoration: BoxDecoration(
                            color: Colors.blue.shade50,
                            borderRadius:
                                BorderRadius.circular(AppSpacing.radiusSm),
                            border: Border.all(color: Colors.blue.shade300),
                          ),
                          child: Row(
                            children: [
                              Icon(Icons.shield_outlined,
                                  color: Colors.blue.shade900, size: 20),
                              const SizedBox(width: AppSpacing.sm),
                              Expanded(
                                child: Text(
                                  'Insurer pending amount: ₹${summary.insuranceAmountPending.toStringAsFixed(2)}. This pending insurance claim will NOT be assigned to the patient.',
                                  style: TextStyle(
                                    fontSize: 12,
                                    color: Colors.blue.shade900,
                                  ),
                                ),
                              ),
                            ],
                          ),
                        ),
                        const SizedBox(height: AppSpacing.sm),
                      ],

                      // Discharge Remarks
                      const Text(
                        'Discharge Remarks / Notes',
                        style: TextStyle(
                            fontSize: 13, fontWeight: FontWeight.w600),
                      ),
                      const SizedBox(height: AppSpacing.xs),
                      TextField(
                        controller: _remarksController,
                        maxLines: 2,
                        decoration: const InputDecoration(
                          hintText: 'Enter clinical instructions or discharge notes',
                          border: OutlineInputBorder(),
                        ),
                      ),
                    ],
                  ),
                ),
              ),

              const SizedBox(height: AppSpacing.md),
              Row(
                mainAxisAlignment: MainAxisAlignment.end,
                children: [
                  TextButton(
                    onPressed: _isDischarging
                        ? null
                        : () => Navigator.of(context).pop(false),
                    child: const Text('Cancel'),
                  ),
                  const SizedBox(width: AppSpacing.sm),
                  FilledButton.icon(
                    style: FilledButton.styleFrom(
                      backgroundColor: Colors.green.shade700,
                      foregroundColor: Colors.white,
                    ),
                    onPressed: _isDischarging
                        ? null
                        : () async {
                            setState(() => _isDischarging = true);
                            try {
                              final notifier =
                                  ref.read(eyeSurgeryListProvider.notifier);
                              if (_remarksController.text.trim().isNotEmpty) {
                                await notifier.updateDetails(
                                  id: widget.surgery.id,
                                  iolDetails: widget.surgery.iolDetails,
                                  remarks: _remarksController.text.trim(),
                                );
                              }
                              await notifier.updateStatus(
                                  widget.surgery.id, 'discharged');
                              if (context.mounted) {
                                Navigator.of(context).pop(true);
                              }
                            } catch (e) {
                              if (context.mounted) {
                                setState(() => _isDischarging = false);
                                ScaffoldMessenger.of(context).showSnackBar(
                                  SnackBar(
                                      content:
                                          Text('Discharge failed: $e')),
                                );
                              }
                            }
                          },
                    icon: _isDischarging
                        ? const SizedBox(
                            width: 16,
                            height: 16,
                            child: CircularProgressIndicator(
                              strokeWidth: 2,
                              color: Colors.white,
                            ),
                          )
                        : const Icon(Icons.check, size: 18),
                    label: Text(_isDischarging
                        ? 'Discharging...'
                        : 'Confirm Discharge'),
                  ),
                ],
              ),
            ],
          ),
        ),
      ),
    );
  }

  Widget _buildCard({
    required String title,
    required IconData icon,
    required Widget child,
  }) {
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
          Row(
            children: [
              Icon(icon, size: 16, color: AppColors.primary),
              const SizedBox(width: AppSpacing.xs),
              Text(
                title,
                style: const TextStyle(
                  fontSize: 11,
                  fontWeight: FontWeight.bold,
                  letterSpacing: 0.8,
                  color: AppColors.primary,
                ),
              ),
            ],
          ),
          const SizedBox(height: AppSpacing.sm),
          child,
        ],
      ),
    );
  }

  Widget _buildRow(String label, String value,
      {Color? color, bool isBold = false}) {
    return Padding(
      padding: const EdgeInsets.symmetric(vertical: 2),
      child: Row(
        mainAxisAlignment: MainAxisAlignment.spaceBetween,
        children: [
          Expanded(
            child: Text(
              label,
              style: const TextStyle(fontSize: 12, color: AppColors.onSurfaceVariant),
              overflow: TextOverflow.ellipsis,
            ),
          ),
          const SizedBox(width: AppSpacing.sm),
          Text(
            value,
            style: TextStyle(
              fontSize: 12,
              fontWeight: isBold ? FontWeight.bold : FontWeight.w500,
              color: color ?? AppColors.onSurface,
            ),
          ),
        ],
      ),
    );
  }
}
