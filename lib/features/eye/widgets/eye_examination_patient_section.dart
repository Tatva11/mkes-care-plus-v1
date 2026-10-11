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
import '../models/eye_examination_model.dart';
import '../providers/eye_examination_provider.dart';
import 'eye_examination_form_dialog.dart';

/// Section embedded into Patient Details screen displaying eye examination history,
/// inventory consumption, and examination management actions.
class EyeExaminationPatientSection extends ConsumerWidget {
  const EyeExaminationPatientSection({
    super.key,
    required this.patient,
  });

  final PatientModel patient;

  static const Color _successColor = Color(0xFF2E7D32);

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    final examsAsync = ref.watch(eyeExaminationsForPatientProvider(patient.id));
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
                  Icons.visibility_outlined,
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
                        'Clinical Examinations',
                        style: AppTypography.headlineMd.copyWith(
                          fontWeight: FontWeight.bold,
                          fontSize: 18,
                        ),
                        overflow: TextOverflow.ellipsis,
                      ),
                    ),
                    const SizedBox(width: AppSpacing.xs),
                    examsAsync.whenOrNull(
                          data: (exams) => Container(
                            padding: const EdgeInsets.symmetric(
                              horizontal: 8,
                              vertical: 2,
                            ),
                            decoration: BoxDecoration(
                              color: AppColors.primaryContainer.withValues(alpha: 0.3),
                              borderRadius: BorderRadius.circular(12),
                            ),
                            child: Text(
                              '${exams.length}',
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
                key: const Key('add_eye_examination_button'),
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
                    builder: (_) => EyeExaminationFormDialog(patient: patient),
                  );
                },
                icon: const Icon(Icons.add, size: 16),
                label: const Text('Record Exam'),
              ),
            ],
          ),
          const SizedBox(height: AppSpacing.md),

          // Examination List
          examsAsync.when(
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
                      'Failed to load examinations: $error',
                      style: AppTypography.bodySm.copyWith(color: AppColors.error),
                    ),
                  ),
                  TextButton(
                    onPressed: () =>
                        ref.invalidate(eyeExaminationsForPatientProvider(patient.id)),
                    child: const Text('Retry'),
                  ),
                ],
              ),
            ),
            data: (exams) {
              if (exams.isEmpty) {
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
                        Icons.visibility_off_outlined,
                        size: 36,
                        color: AppColors.onSurfaceVariant,
                      ),
                      const SizedBox(height: AppSpacing.xs),
                      Text(
                        'No clinical examination records found.',
                        style: AppTypography.bodyMd.copyWith(
                          color: AppColors.onSurfaceVariant,
                        ),
                      ),
                      const SizedBox(height: 2),
                      Text(
                        'Tap "Record Exam" to add visual acuity, IOP, and clinical findings.',
                        style: AppTypography.bodySm.copyWith(
                          color: AppColors.onSurfaceVariant.withValues(alpha: 0.8),
                        ),
                      ),
                    ],
                  ),
                );
              }

              return Column(
                children: exams
                    .map((exam) => _buildExaminationCard(context, ref, exam, isAdmin))
                    .toList(),
              );
            },
          ),
        ],
      ),
    );
  }

  Widget _buildExaminationCard(
    BuildContext context,
    WidgetRef ref,
    EyeExaminationModel exam,
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
                        exam.formattedDate,
                        style: AppTypography.bodySm.copyWith(
                          color: AppColors.primary,
                          fontWeight: FontWeight.bold,
                        ),
                      ),
                      if (exam.formattedTime != null) ...[
                        const SizedBox(width: 4),
                        Text(
                          '• ${exam.formattedTime}',
                          style: AppTypography.bodySm.copyWith(
                            color: AppColors.primary,
                          ),
                        ),
                      ],
                    ],
                  ),
                ),
                if (exam.createdByName != null) ...[
                  const SizedBox(width: AppSpacing.xs),
                  Text(
                    'by ${exam.createdByName}',
                    style: AppTypography.bodySm.copyWith(
                      color: AppColors.onSurfaceVariant,
                    ),
                  ),
                ],
                const Spacer(),
                // Edit button
                IconButton(
                  icon: const Icon(Icons.edit_outlined, size: 18),
                  tooltip: 'Edit Examination',
                  visualDensity: VisualDensity.compact,
                  onPressed: () async {
                    await showDialog(
                      context: context,
                      builder: (_) => EyeExaminationFormDialog(
                        patient: patient,
                        initialRecord: exam,
                      ),
                    );
                  },
                ),
                // Admin-only delete
                if (isAdmin)
                  IconButton(
                    icon: const Icon(Icons.delete_outline,
                        size: 18, color: AppColors.error),
                    tooltip: 'Delete Examination',
                    visualDensity: VisualDensity.compact,
                    onPressed: () => _confirmDelete(context, ref, exam),
                  ),
              ],
            ),
            const SizedBox(height: AppSpacing.xs),

            // Linked appointment
            if (exam.appointmentDate != null) ...[
              Row(
                children: [
                  const Icon(Icons.link, size: 14, color: AppColors.onSurfaceVariant),
                  const SizedBox(width: 4),
                  Text(
                    'Appointment: ${DateFormat('dd MMM yyyy').format(exam.appointmentDate!)}${exam.appointmentTime != null ? " at ${exam.appointmentTime}" : ""}',
                    style: AppTypography.bodySm.copyWith(
                      color: AppColors.onSurfaceVariant,
                    ),
                  ),
                ],
              ),
              const SizedBox(height: AppSpacing.xs),
            ],

            // Diagnosis
            if (exam.diagnosis != null && exam.diagnosis!.trim().isNotEmpty) ...[
              Container(
                margin: const EdgeInsets.symmetric(vertical: 4),
                padding: const EdgeInsets.symmetric(horizontal: 10, vertical: 6),
                decoration: BoxDecoration(
                  color: AppColors.secondaryContainer.withValues(alpha: 0.3),
                  borderRadius: BorderRadius.circular(AppSpacing.radiusSm),
                  border: Border.all(
                    color: AppColors.secondary.withValues(alpha: 0.3),
                  ),
                ),
                child: Row(
                  children: [
                    const Icon(Icons.healing_outlined,
                        size: 16, color: AppColors.secondary),
                    const SizedBox(width: 6),
                    Expanded(
                      child: Text(
                        'Diagnosis: ${exam.diagnosis}',
                        style: AppTypography.bodyMd.copyWith(
                          fontWeight: FontWeight.bold,
                          color: AppColors.onSurface,
                        ),
                      ),
                    ),
                  ],
                ),
              ),
              const SizedBox(height: AppSpacing.xs),
            ],

            // Visual Acuity & IOP Chips Row
            Wrap(
              spacing: AppSpacing.sm,
              runSpacing: AppSpacing.xs,
              children: [
                if (exam.hasVisualAcuity)
                  _buildMetricBadge(
                    icon: Icons.remove_red_eye_outlined,
                    label: 'VA',
                    value: [
                      if (exam.visualAcuityOd != null) 'OD: ${exam.visualAcuityOd}',
                      if (exam.visualAcuityOs != null) 'OS: ${exam.visualAcuityOs}',
                      if (exam.visualAcuity != null) exam.visualAcuity!,
                    ].join(' | '),
                  ),
                if (exam.hasIop)
                  _buildMetricBadge(
                    icon: Icons.speed_outlined,
                    label: 'IOP',
                    value: [
                      if (exam.intraocularPressureOd != null)
                        'OD: ${exam.intraocularPressureOd}',
                      if (exam.intraocularPressureOs != null)
                        'OS: ${exam.intraocularPressureOs}',
                      if (exam.intraocularPressure != null)
                        exam.intraocularPressure!,
                    ].join(' | '),
                  ),
              ],
            ),
            const SizedBox(height: AppSpacing.xs),

            // Slit lamp notes
            if (exam.hasSlitLamp) ...[
              const SizedBox(height: 4),
              Row(
                crossAxisAlignment: CrossAxisAlignment.start,
                children: [
                  const Icon(Icons.biotech_outlined,
                      size: 16, color: AppColors.primary),
                  const SizedBox(width: 6),
                  Expanded(
                    child: RichText(
                      text: TextSpan(
                        style: AppTypography.bodySm.copyWith(
                          color: AppColors.onSurface,
                        ),
                        children: [
                          const TextSpan(
                            text: 'Slit Lamp: ',
                            style: TextStyle(fontWeight: FontWeight.bold),
                          ),
                          TextSpan(text: exam.slitLampExamination),
                        ],
                      ),
                    ),
                  ),
                ],
              ),
            ],

            // Clinical notes
            if (exam.clinicalNotes != null &&
                exam.clinicalNotes!.trim().isNotEmpty) ...[
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
                            text: 'Notes & Plan: ',
                            style: TextStyle(fontWeight: FontWeight.bold),
                          ),
                          TextSpan(text: exam.clinicalNotes),
                        ],
                      ),
                    ),
                  ),
                ],
              ),
            ],

            const Divider(height: AppSpacing.lg),

            // Consumed Inventory Integration
            _buildInventoryConsumptionSection(context, ref, exam),
          ],
        ),
      ),
    );
  }

  Widget _buildMetricBadge({
    required IconData icon,
    required String label,
    required String value,
  }) {
    return Container(
      padding: const EdgeInsets.symmetric(horizontal: 8, vertical: 4),
      decoration: BoxDecoration(
        color: AppColors.surfaceVariant,
        borderRadius: BorderRadius.circular(AppSpacing.radiusSm),
        border: Border.all(color: AppColors.outlineVariant.withValues(alpha: 0.5)),
      ),
      child: Row(
        mainAxisSize: MainAxisSize.min,
        children: [
          Icon(icon, size: 14, color: AppColors.primary),
          const SizedBox(width: 4),
          Text(
            '$label: ',
            style: AppTypography.bodySm.copyWith(
              fontWeight: FontWeight.bold,
              color: AppColors.primary,
            ),
          ),
          Text(
            value,
            style: AppTypography.bodySm.copyWith(
              fontWeight: FontWeight.w600,
            ),
          ),
        ],
      ),
    );
  }

  Widget _buildInventoryConsumptionSection(
    BuildContext context,
    WidgetRef ref,
    EyeExaminationModel exam,
  ) {
    final usageAsync = ref.watch(clinicalInventoryUsageForRecordProvider((
      recordType: 'eye_examination',
      recordId: exam.id,
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
                  'Consumed Inventory & Supplies',
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
                    recordType: 'eye_examination',
                    recordId: exam.id,
                    recordTitle: 'Eye Exam (${exam.formattedDate})',
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
                'No supplies consumed for this examination.',
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
    EyeExaminationModel exam,
  ) async {
    final confirmed = await showDialog<bool>(
      context: context,
      builder: (ctx) => AlertDialog(
        title: const Text('Delete Examination Record?'),
        content: Text(
          'Are you sure you want to permanently delete the examination from ${exam.formattedDate}? This action cannot be undone.',
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
            .read(eyeExaminationControllerProvider.notifier)
            .deleteExamination(id: exam.id, patientId: patient.id);
        if (context.mounted) {
          ScaffoldMessenger.of(context).showSnackBar(
            const SnackBar(
              content: Text('Examination deleted successfully.'),
              backgroundColor: _successColor,
            ),
          );
        }
      } catch (e) {
        if (context.mounted) {
          ScaffoldMessenger.of(context).showSnackBar(
            SnackBar(
              content: Text('Failed to delete examination: $e'),
              backgroundColor: AppColors.error,
            ),
          );
        }
      }
    }
  }
}
