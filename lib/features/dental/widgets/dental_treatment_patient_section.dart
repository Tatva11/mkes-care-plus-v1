import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:intl/intl.dart';

import '../../../core/theme/app_colors.dart';
import '../../../core/theme/app_spacing.dart';
import '../../../core/theme/app_typography.dart';
import '../../auth/providers/auth_provider.dart';
import '../../clinical/providers/clinical_inventory_provider.dart';
import '../../clinical/widgets/clinical_inventory_consumption_dialog.dart';
import '../../patients/models/patient_model.dart';
import '../models/dental_treatment_model.dart';
import '../providers/dental_treatment_provider.dart';
import 'dental_treatment_form_dialog.dart';

/// Section embedded into Patient Details screen displaying dental treatment history,
/// inventory consumption, and treatment management actions.
class DentalTreatmentPatientSection extends ConsumerWidget {
  const DentalTreatmentPatientSection({
    super.key,
    required this.patient,
  });

  final PatientModel patient;

  static const Color _successColor = Color(0xFF2E7D32);

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    final treatmentsAsync =
        ref.watch(dentalTreatmentsForPatientProvider(patient.id));
    final role = ref.watch(currentUserRoleProvider).valueOrNull;
    final isAdmin = role == 'admin';

    return Container(
      width: double.infinity,
      padding: const EdgeInsets.all(AppSpacing.md),
      decoration: BoxDecoration(
        color: AppColors.surfaceContainerLowest,
        borderRadius: BorderRadius.circular(AppSpacing.radiusLg),
        border: Border.all(color: AppColors.outlineVariant),
        boxShadow: const [
          BoxShadow(
            color: Color(0x0A000000),
            blurRadius: 8,
            offset: Offset(0, 1),
          ),
        ],
      ),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          // Section Header
          Row(
            children: [
              Container(
                padding: const EdgeInsets.all(AppSpacing.xs),
                decoration: BoxDecoration(
                  color: AppColors.primaryContainer.withValues(alpha: 0.2),
                  borderRadius: BorderRadius.circular(AppSpacing.radiusSm),
                ),
                child: const Icon(
                  Icons.medical_services_outlined,
                  color: AppColors.primary,
                  size: 20,
                ),
              ),
              const SizedBox(width: AppSpacing.sm),
              Expanded(
                child: Row(
                  children: [
                    Flexible(
                      child: Text(
                        'Clinical Treatments',
                        style: AppTypography.headlineMd.copyWith(
                          fontWeight: FontWeight.bold,
                          fontSize: 18,
                        ),
                        overflow: TextOverflow.ellipsis,
                      ),
                    ),
                    const SizedBox(width: AppSpacing.xs),
                    treatmentsAsync.whenOrNull(
                          data: (treatments) => Container(
                            padding: const EdgeInsets.symmetric(
                              horizontal: 8,
                              vertical: 2,
                            ),
                            decoration: BoxDecoration(
                              color: AppColors.primaryContainer.withValues(alpha: 0.3),
                              borderRadius: BorderRadius.circular(12),
                            ),
                            child: Text(
                              '${treatments.length}',
                              style: AppTypography.bodySm.copyWith(
                                color: AppColors.primary,
                                fontWeight: FontWeight.bold,
                              ),
                            ),
                          ),
                        ) ??
                        const SizedBox.shrink(),
                  ],
                ),
              ),
              FilledButton.icon(
                key: const Key('add_dental_treatment_button'),
                style: FilledButton.styleFrom(
                  padding: const EdgeInsets.symmetric(
                    horizontal: AppSpacing.md,
                    vertical: AppSpacing.xs,
                  ),
                  visualDensity: VisualDensity.compact,
                ),
                onPressed: () async {
                  await showDialog(
                    context: context,
                    builder: (_) => DentalTreatmentFormDialog(patient: patient),
                  );
                },
                icon: const Icon(Icons.add, size: 16),
                label: const Text('Record Treatment'),
              ),
            ],
          ),
          const SizedBox(height: AppSpacing.md),

          // Treatment List
          treatmentsAsync.when(
            loading: () => const Center(
              child: Padding(
                padding: EdgeInsets.all(AppSpacing.lg),
                child: CircularProgressIndicator(),
              ),
            ),
            error: (error, _) => Container(
              padding: const EdgeInsets.all(AppSpacing.md),
              decoration: BoxDecoration(
                color: AppColors.errorContainer.withValues(alpha: 0.2),
                borderRadius: BorderRadius.circular(AppSpacing.radiusMd),
              ),
              child: Row(
                children: [
                  const Icon(Icons.error_outline, color: AppColors.error),
                  const SizedBox(width: AppSpacing.sm),
                  Expanded(
                    child: Text(
                      'Failed to load dental treatments: $error',
                      style: AppTypography.bodySm.copyWith(color: AppColors.error),
                    ),
                  ),
                  TextButton(
                    onPressed: () => ref.invalidate(
                        dentalTreatmentsForPatientProvider(patient.id)),
                    child: const Text('Retry'),
                  ),
                ],
              ),
            ),
            data: (treatments) {
              if (treatments.isEmpty) {
                return Container(
                  width: double.infinity,
                  padding: const EdgeInsets.all(AppSpacing.lg),
                  decoration: BoxDecoration(
                    color: AppColors.surfaceContainerLow,
                    borderRadius: BorderRadius.circular(AppSpacing.radiusMd),
                    border: Border.all(
                      color: AppColors.outlineVariant.withValues(alpha: 0.5),
                    ),
                  ),
                  child: Column(
                    children: [
                      const Icon(
                        Icons.medical_services_outlined,
                        size: 36,
                        color: AppColors.onSurfaceVariant,
                      ),
                      const SizedBox(height: AppSpacing.xs),
                      Text(
                        'No dental treatment records found.',
                        style: AppTypography.bodyMd.copyWith(
                          color: AppColors.onSurfaceVariant,
                        ),
                      ),
                      const SizedBox(height: 2),
                      Text(
                        'Tap "Record Treatment" to add procedures, tooth numbers, and notes.',
                        style: AppTypography.bodySm.copyWith(
                          color: AppColors.onSurfaceVariant.withValues(alpha: 0.8),
                        ),
                      ),
                    ],
                  ),
                );
              }

              return Column(
                children: treatments
                    .map((t) => _buildTreatmentCard(context, ref, t, isAdmin))
                    .toList(),
              );
            },
          ),
        ],
      ),
    );
  }

  Widget _buildTreatmentCard(
    BuildContext context,
    WidgetRef ref,
    DentalTreatmentModel treatment,
    bool isAdmin,
  ) {
    return Card(
      margin: const EdgeInsets.only(bottom: AppSpacing.md),
      shape: RoundedRectangleBorder(
        borderRadius: BorderRadius.circular(AppSpacing.radiusMd),
        side: const BorderSide(color: AppColors.outlineVariant),
      ),
      elevation: 0,
      color: AppColors.surfaceContainerLow,
      child: Padding(
        padding: const EdgeInsets.all(AppSpacing.md),
        child: Column(
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            // Top row: Date, time, actions
            Row(
              children: [
                Container(
                  padding: const EdgeInsets.symmetric(horizontal: 8, vertical: 4),
                  decoration: BoxDecoration(
                    color: AppColors.primaryContainer.withValues(alpha: 0.2),
                    borderRadius: BorderRadius.circular(AppSpacing.radiusSm),
                  ),
                  child: Row(
                    children: [
                      const Icon(Icons.event, size: 14, color: AppColors.primary),
                      const SizedBox(width: 4),
                      Text(
                        treatment.formattedDate,
                        style: AppTypography.bodySm.copyWith(
                          color: AppColors.primary,
                          fontWeight: FontWeight.bold,
                        ),
                      ),
                      if (treatment.formattedTime != null) ...[
                        const SizedBox(width: 4),
                        Text(
                          '• ${treatment.formattedTime}',
                          style: AppTypography.bodySm.copyWith(
                            color: AppColors.primary,
                          ),
                        ),
                      ],
                    ],
                  ),
                ),
                if (treatment.createdByName != null) ...[
                  const SizedBox(width: AppSpacing.xs),
                  Text(
                    'by ${treatment.createdByName}',
                    style: AppTypography.bodySm.copyWith(
                      color: AppColors.onSurfaceVariant,
                    ),
                  ),
                ],
                const Spacer(),
                // Edit button
                IconButton(
                  icon: const Icon(Icons.edit_outlined, size: 18),
                  tooltip: 'Edit Treatment',
                  visualDensity: VisualDensity.compact,
                  onPressed: () async {
                    await showDialog(
                      context: context,
                      builder: (_) => DentalTreatmentFormDialog(
                        patient: patient,
                        initialRecord: treatment,
                      ),
                    );
                  },
                ),
                // Admin-only delete
                if (isAdmin)
                  IconButton(
                    icon: const Icon(Icons.delete_outline,
                        size: 18, color: AppColors.error),
                    tooltip: 'Delete Treatment',
                    visualDensity: VisualDensity.compact,
                    onPressed: () => _confirmDelete(context, ref, treatment),
                  ),
              ],
            ),
            const SizedBox(height: AppSpacing.xs),

            // Procedure Performed Title & Status Chip
            Row(
              crossAxisAlignment: CrossAxisAlignment.center,
              children: [
                Expanded(
                  child: Text(
                    treatment.procedurePerformed,
                    style: AppTypography.headlineMd.copyWith(
                      fontWeight: FontWeight.bold,
                      fontSize: 18,
                      color: AppColors.onSurface,
                    ),
                  ),
                ),
                _buildStatusChip(treatment.procedureStatus),
              ],
            ),
            const SizedBox(height: AppSpacing.xs),

            // Tooth number / Quadrant badge & Linked Lab Case
            Wrap(
              spacing: AppSpacing.sm,
              runSpacing: AppSpacing.xs,
              children: [
                if (treatment.toothNumber != null &&
                    treatment.toothNumber!.trim().isNotEmpty)
                  Container(
                    padding: const EdgeInsets.symmetric(horizontal: 8, vertical: 4),
                    decoration: BoxDecoration(
                      color: AppColors.surfaceVariant,
                      borderRadius: BorderRadius.circular(AppSpacing.radiusSm),
                      border: Border.all(
                        color: AppColors.outlineVariant.withValues(alpha: 0.5),
                      ),
                    ),
                    child: Row(
                      mainAxisSize: MainAxisSize.min,
                      children: [
                        const Icon(Icons.tag, size: 14, color: AppColors.primary),
                        const SizedBox(width: 4),
                        Text(
                          'Tooth / Quad: ',
                          style: AppTypography.bodySm.copyWith(
                            fontWeight: FontWeight.bold,
                            color: AppColors.primary,
                          ),
                        ),
                        Text(
                          treatment.toothNumber!,
                          style: AppTypography.bodySm.copyWith(
                            fontWeight: FontWeight.bold,
                          ),
                        ),
                      ],
                    ),
                  ),
                if (treatment.dentalLabCaseNumber != null)
                  Container(
                    padding: const EdgeInsets.symmetric(horizontal: 8, vertical: 4),
                    decoration: BoxDecoration(
                      color: AppColors.secondaryContainer.withValues(alpha: 0.4),
                      borderRadius: BorderRadius.circular(AppSpacing.radiusSm),
                      border: Border.all(
                        color: AppColors.secondary.withValues(alpha: 0.4),
                      ),
                    ),
                    child: Row(
                      mainAxisSize: MainAxisSize.min,
                      children: [
                        const Icon(Icons.science_outlined,
                            size: 14, color: AppColors.secondary),
                        const SizedBox(width: 4),
                        Text(
                          'Lab Case #${treatment.dentalLabCaseNumber}',
                          style: AppTypography.bodySm.copyWith(
                            fontWeight: FontWeight.bold,
                            color: AppColors.secondary,
                          ),
                        ),
                        if (treatment.dentalLabCaseType != null)
                          Text(
                            ' (${treatment.dentalLabCaseType})',
                            style: AppTypography.bodySm.copyWith(
                              color: AppColors.onSurfaceVariant,
                            ),
                          ),
                      ],
                    ),
                  ),
                if (treatment.appointmentDate != null)
                  Container(
                    padding: const EdgeInsets.symmetric(horizontal: 8, vertical: 4),
                    decoration: BoxDecoration(
                      color: AppColors.surfaceContainerHigh,
                      borderRadius: BorderRadius.circular(AppSpacing.radiusSm),
                    ),
                    child: Row(
                      mainAxisSize: MainAxisSize.min,
                      children: [
                        const Icon(Icons.link, size: 14, color: AppColors.onSurfaceVariant),
                        const SizedBox(width: 4),
                        Flexible(
                          child: Text(
                            'Appointment: ${DateFormat('dd MMM yyyy').format(treatment.appointmentDate!)}${treatment.appointmentTime != null ? " at ${treatment.appointmentTime}" : ""}${treatment.appointmentStatus != null ? " • ${treatment.appointmentStatus!.toUpperCase()}" : ""}',
                            overflow: TextOverflow.ellipsis,
                            style: AppTypography.bodySm.copyWith(
                              color: AppColors.onSurfaceVariant,
                            ),
                          ),
                        ),
                      ],
                    ),
                  ),
              ],
            ),
            const SizedBox(height: AppSpacing.xs),

            // Diagnosis
            if (treatment.diagnosis != null &&
                treatment.diagnosis!.trim().isNotEmpty) ...[
              const SizedBox(height: 4),
              Row(
                crossAxisAlignment: CrossAxisAlignment.start,
                children: [
                  const Icon(Icons.local_hospital_outlined,
                      size: 16, color: AppColors.secondary),
                  const SizedBox(width: 6),
                  Expanded(
                    child: Text(
                      'Diagnosis: ${treatment.diagnosis}',
                      style: AppTypography.bodySm.copyWith(
                        color: AppColors.onSurface,
                        fontWeight: FontWeight.w600,
                      ),
                    ),
                  ),
                ],
              ),
            ],

            // Treatment notes
            if (treatment.treatmentNotes != null &&
                treatment.treatmentNotes!.trim().isNotEmpty) ...[
              const SizedBox(height: 4),
              Row(
                crossAxisAlignment: CrossAxisAlignment.start,
                children: [
                  const Icon(Icons.notes_outlined,
                      size: 16, color: AppColors.onSurfaceVariant),
                  const SizedBox(width: 6),
                  Expanded(
                    child: RichText(
                      text: TextSpan(
                        style: AppTypography.bodySm.copyWith(
                          color: AppColors.onSurface,
                        ),
                        children: [
                          const TextSpan(
                            text: 'Notes: ',
                            style: TextStyle(fontWeight: FontWeight.bold),
                          ),
                          TextSpan(text: treatment.treatmentNotes),
                        ],
                      ),
                    ),
                  ),
                ],
              ),
            ],

            const Divider(height: AppSpacing.lg),

            // Consumed Inventory Integration
            _buildInventoryConsumptionSection(context, ref, treatment),
          ],
        ),
      ),
    );
  }

  Widget _buildStatusChip(String status) {
    Color bg;
    Color fg;
    String label;

    switch (status.toLowerCase()) {
      case 'completed':
        bg = _successColor.withValues(alpha: 0.15);
        fg = _successColor;
        label = 'Completed';
        break;
      case 'in_progress':
        bg = AppColors.primaryContainer.withValues(alpha: 0.4);
        fg = AppColors.primary;
        label = 'In Progress';
        break;
      case 'planned':
        bg = AppColors.secondaryContainer.withValues(alpha: 0.4);
        fg = AppColors.secondary;
        label = 'Planned';
        break;
      case 'cancelled':
        bg = AppColors.errorContainer.withValues(alpha: 0.3);
        fg = AppColors.error;
        label = 'Cancelled';
        break;
      default:
        bg = AppColors.surfaceContainerHigh;
        fg = AppColors.onSurface;
        label = status;
    }

    return Container(
      padding: const EdgeInsets.symmetric(horizontal: 8, vertical: 3),
      decoration: BoxDecoration(
        color: bg,
        borderRadius: BorderRadius.circular(AppSpacing.radiusSm),
      ),
      child: Text(
        label,
        style: AppTypography.bodySm.copyWith(
          color: fg,
          fontWeight: FontWeight.bold,
          fontSize: 12,
        ),
      ),
    );
  }

  Widget _buildInventoryConsumptionSection(
    BuildContext context,
    WidgetRef ref,
    DentalTreatmentModel treatment,
  ) {
    final usageAsync = ref.watch(clinicalInventoryUsageForRecordProvider((
      recordType: 'dental_treatment',
      recordId: treatment.id,
    )));

    return Column(
      crossAxisAlignment: CrossAxisAlignment.start,
      children: [
        Wrap(
          alignment: WrapAlignment.spaceBetween,
          crossAxisAlignment: WrapCrossAlignment.center,
          spacing: AppSpacing.sm,
          runSpacing: AppSpacing.xs,
          children: [
            Row(
              mainAxisSize: MainAxisSize.min,
              children: [
                const Icon(Icons.medication_outlined,
                    size: 16, color: AppColors.onSurfaceVariant),
                const SizedBox(width: 4),
                Text(
                  'Consumed Dental Supplies & Items',
                  style: AppTypography.bodySm.copyWith(
                    fontWeight: FontWeight.bold,
                    color: AppColors.onSurfaceVariant,
                  ),
                ),
              ],
            ),
            OutlinedButton.icon(
              style: OutlinedButton.styleFrom(
                visualDensity: VisualDensity.compact,
                padding: const EdgeInsets.symmetric(horizontal: 10, vertical: 0),
              ),
              onPressed: () async {
                await showDialog(
                  context: context,
                  builder: (_) => ClinicalInventoryConsumptionDialog(
                    patientId: patient.id,
                    patientName: patient.name,
                    patientNumber: patient.patientNumber,
                    recordType: 'dental_treatment',
                    recordId: treatment.id,
                    recordTitle:
                        '${treatment.procedurePerformed} (${treatment.formattedDate})',
                  ),
                );
              },
              icon: const Icon(Icons.add, size: 14),
              label: const Text('Record Stock Usage'),
            ),
          ],
        ),
        const SizedBox(height: 6),
        usageAsync.when(
          loading: () => const LinearProgressIndicator(),
          error: (err, _) => Text(
            'Unable to load consumed items: $err',
            style: AppTypography.bodySm.copyWith(color: AppColors.error),
          ),
          data: (items) {
            if (items.isEmpty) {
              return Text(
                'No materials consumed for this treatment.',
                style: AppTypography.bodySm.copyWith(
                  color: AppColors.onSurfaceVariant,
                  fontStyle: FontStyle.italic,
                ),
              );
            }
            return Column(
              children: items.map((u) {
                return Container(
                  margin: const EdgeInsets.only(top: 4),
                  padding: const EdgeInsets.symmetric(horizontal: 8, vertical: 4),
                  decoration: BoxDecoration(
                    color: AppColors.surfaceContainerLowest,
                    borderRadius: BorderRadius.circular(AppSpacing.radiusSm),
                    border: Border.all(
                      color: AppColors.outlineVariant.withValues(alpha: 0.5),
                    ),
                  ),
                  child: Row(
                    children: [
                      const Icon(Icons.check_circle_outline,
                          size: 14, color: _successColor),
                      const SizedBox(width: 6),
                      Expanded(
                        child: Text(
                          '${u.itemName ?? "Inventory Item"} — ${u.quantity} ${u.itemUnit ?? "units"}${u.remarks != null ? " (${u.remarks})" : ""}',
                          style: AppTypography.bodySm.copyWith(
                            fontWeight: FontWeight.w500,
                          ),
                        ),
                      ),
                      Text(
                        u.formattedConsumedAt,
                        style: AppTypography.bodySm.copyWith(
                          color: AppColors.onSurfaceVariant,
                          fontSize: 12,
                        ),
                      ),
                    ],
                  ),
                );
              }).toList(),
            );
          },
        ),
      ],
    );
  }

  Future<void> _confirmDelete(
    BuildContext context,
    WidgetRef ref,
    DentalTreatmentModel treatment,
  ) async {
    final confirmed = await showDialog<bool>(
      context: context,
      builder: (ctx) => AlertDialog(
        title: const Text('Delete Treatment Record?'),
        content: Text(
          'Are you sure you want to permanently delete the treatment "${treatment.procedurePerformed}" from ${treatment.formattedDate}? This action cannot be undone.',
        ),
        actions: [
          TextButton(
            onPressed: () => Navigator.of(ctx).pop(false),
            child: const Text('Cancel'),
          ),
          FilledButton(
            style: FilledButton.styleFrom(backgroundColor: AppColors.error),
            onPressed: () => Navigator.of(ctx).pop(true),
            child: const Text('Delete'),
          ),
        ],
      ),
    );

    if (confirmed == true) {
      try {
        await ref
            .read(dentalTreatmentControllerProvider.notifier)
            .deleteTreatment(id: treatment.id, patientId: patient.id);
        if (context.mounted) {
          ScaffoldMessenger.of(context).showSnackBar(
            const SnackBar(
              content: Text('Treatment record deleted successfully.'),
              backgroundColor: _successColor,
            ),
          );
        }
      } catch (e) {
        if (context.mounted) {
          ScaffoldMessenger.of(context).showSnackBar(
            SnackBar(
              content: Text('Failed to delete treatment: $e'),
              backgroundColor: AppColors.error,
            ),
          );
        }
      }
    }
  }
}
