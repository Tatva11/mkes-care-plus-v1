import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:intl/intl.dart';

import '../../../core/theme/app_colors.dart';
import '../../../core/theme/app_spacing.dart';
import '../../../core/theme/app_typography.dart';
import '../models/patient_attendance.dart';
import '../models/patient_model.dart';
import '../providers/patient_attendance_provider.dart';
import '../providers/patients_provider.dart';
import '../widgets/patient_form_dialog.dart';

/// Screen displaying complete details for a single patient, including
/// personal/contact information and their attendance history.
class PatientDetailsScreen extends ConsumerWidget {
  const PatientDetailsScreen({
    super.key,
    required this.patientId,
  });

  final String patientId;

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    final patientAsync = ref.watch(patientDetailsProvider(patientId));
    final historyAsync = ref.watch(patientAttendanceHistoryProvider(patientId));

    return Scaffold(
      appBar: AppBar(
        title: const Text('Patient Details'),
        actions: [
          patientAsync.whenOrNull(
                data: (patient) => IconButton(
                  icon: const Icon(Icons.edit_outlined),
                  tooltip: 'Edit Patient',
                  onPressed: () async {
                    final updated = await showDialog<PatientModel>(
                      context: context,
                      builder: (_) => PatientFormDialog(patient: patient),
                    );
                    if (updated != null) {
                      ref.invalidate(patientDetailsProvider(patientId));
                    }
                  },
                ),
              ) ??
              const SizedBox.shrink(),
        ],
      ),
      body: patientAsync.when(
        loading: () => const Center(child: CircularProgressIndicator()),
        error: (error, _) => Center(
          child: Column(
            mainAxisSize: MainAxisSize.min,
            children: [
              const Icon(Icons.error_outline, size: 48, color: AppColors.error),
              const SizedBox(height: AppSpacing.sm),
              Text(
                'Unable to load patient details.',
                style: AppTypography.headlineMd,
              ),
              const SizedBox(height: AppSpacing.xs),
              Text(
                '$error',
                textAlign: TextAlign.center,
                style: AppTypography.bodySm
                    .copyWith(color: AppColors.onSurfaceVariant),
              ),
              const SizedBox(height: AppSpacing.md),
              FilledButton.icon(
                onPressed: () => ref.invalidate(patientDetailsProvider(patientId)),
                icon: const Icon(Icons.refresh),
                label: const Text('Retry'),
              ),
            ],
          ),
        ),
        data: (patient) => RefreshIndicator(
          onRefresh: () async {
            ref.invalidate(patientDetailsProvider(patientId));
            ref.invalidate(patientAttendanceHistoryProvider(patientId));
          },
          child: SingleChildScrollView(
            physics: const AlwaysScrollableScrollPhysics(),
            padding: const EdgeInsets.all(AppSpacing.md),
            child: Column(
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                _buildHeaderCard(context, ref, patient),
                const SizedBox(height: AppSpacing.md),
                _buildInfoCard(patient),
                const SizedBox(height: AppSpacing.lg),
                _buildAttendanceHistorySection(ref, historyAsync),
              ],
            ),
          ),
        ),
      ),
    );
  }

  Widget _buildHeaderCard(
    BuildContext context,
    WidgetRef ref,
    PatientModel patient,
  ) {
    final deptLabel = patient.department == 'eye'
        ? 'Eye Clinic'
        : patient.department == 'dental'
            ? 'Dental Clinic'
            : (patient.department ?? 'General');

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
      child: Row(
        crossAxisAlignment: CrossAxisAlignment.center,
        children: [
          CircleAvatar(
            radius: 30,
            backgroundColor: AppColors.primaryContainer.withValues(alpha: 0.2),
            child: Text(
              _initials(patient.name),
              style: AppTypography.headlineMd.copyWith(
                color: AppColors.primary,
                fontWeight: FontWeight.bold,
              ),
            ),
          ),
          const SizedBox(width: AppSpacing.md),
          Expanded(
            child: Column(
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                Text(
                  patient.name,
                  style: AppTypography.headlineMd.copyWith(fontSize: 20),
                ),
                const SizedBox(height: 6),
                Wrap(
                  spacing: 8,
                  runSpacing: 4,
                  children: [
                    Container(
                      padding: const EdgeInsets.symmetric(
                          horizontal: 8, vertical: 3),
                      decoration: BoxDecoration(
                        color: AppColors.surfaceContainerLow,
                        borderRadius: BorderRadius.circular(4),
                        border: Border.all(color: AppColors.outlineVariant),
                      ),
                      child: Text(
                        patient.patientNumber,
                        style: AppTypography.dataMono.copyWith(
                          fontSize: 13,
                          fontWeight: FontWeight.bold,
                          color: AppColors.primary,
                        ),
                      ),
                    ),
                    Container(
                      padding: const EdgeInsets.symmetric(
                          horizontal: 8, vertical: 3),
                      decoration: BoxDecoration(
                        color: AppColors.secondaryContainer
                            .withValues(alpha: 0.2),
                        borderRadius: BorderRadius.circular(4),
                      ),
                      child: Text(
                        deptLabel,
                        style: AppTypography.labelCaps.copyWith(
                          color: AppColors.secondary,
                          fontSize: 11,
                        ),
                      ),
                    ),
                  ],
                ),
              ],
            ),
          ),
        ],
      ),
    );
  }

  Widget _buildInfoCard(PatientModel patient) {
    final ageLabel = patient.dob != null
        ? '${DateTime.now().year - patient.dob!.year} yrs'
        : null;
    final dobFormatted = patient.dob != null
        ? '${DateFormat('d MMM yyyy').format(patient.dob!)} ($ageLabel)'
        : 'Not provided';

    final visitDateFormatted = patient.visitDate != null
        ? DateFormat('d MMM yyyy').format(patient.visitDate!.toLocal())
        : 'Not recorded';

    final registeredOnFormatted =
        DateFormat('d MMM yyyy, h:mm a').format(patient.createdAt.toLocal());

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
          Text(
            'PATIENT INFORMATION',
            style: AppTypography.labelCaps.copyWith(
              color: AppColors.primary,
              fontWeight: FontWeight.bold,
              letterSpacing: 1.1,
            ),
          ),
          const SizedBox(height: AppSpacing.sm),
          const Divider(height: 1, color: AppColors.outlineVariant),
          const SizedBox(height: AppSpacing.sm),
          _buildInfoRow(
            icon: Icons.phone_outlined,
            label: 'Mobile',
            value: patient.mobile ?? 'Not provided',
          ),
          _buildInfoRow(
            icon: Icons.cake_outlined,
            label: 'Date of Birth',
            value: dobFormatted,
          ),
          _buildInfoRow(
            icon: Icons.home_outlined,
            label: 'Address',
            value: patient.address ?? 'Not provided',
          ),
          _buildInfoRow(
            icon: Icons.connect_without_contact_outlined,
            label: 'Reference',
            value: patient.reference ?? 'Not provided',
          ),
          _buildInfoRow(
            icon: Icons.calendar_today_outlined,
            label: 'Last Visit Date',
            value: visitDateFormatted,
          ),
          _buildInfoRow(
            icon: Icons.history_outlined,
            label: 'Registered On',
            value: registeredOnFormatted,
            isLast: true,
          ),
        ],
      ),
    );
  }

  Widget _buildInfoRow({
    required IconData icon,
    required String label,
    required String value,
    bool isLast = false,
  }) {
    return Padding(
      padding: EdgeInsets.only(bottom: isLast ? 0 : AppSpacing.sm),
      child: Row(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Icon(icon, size: 18, color: AppColors.outline),
          const SizedBox(width: AppSpacing.sm),
          SizedBox(
            width: 120,
            child: Text(
              label,
              style: AppTypography.bodySm.copyWith(
                color: AppColors.onSurfaceVariant,
                fontWeight: FontWeight.w500,
              ),
            ),
          ),
          Expanded(
            child: Text(
              value,
              style: AppTypography.bodyMd.copyWith(
                fontWeight: FontWeight.w500,
              ),
            ),
          ),
        ],
      ),
    );
  }

  Widget _buildAttendanceHistorySection(
    WidgetRef ref,
    AsyncValue<List<PatientAttendance>> historyAsync,
  ) {
    return Column(
      crossAxisAlignment: CrossAxisAlignment.start,
      children: [
        Row(
          mainAxisAlignment: MainAxisAlignment.spaceBetween,
          children: [
            Text(
              'ATTENDANCE HISTORY',
              style: AppTypography.labelCaps.copyWith(
                color: AppColors.primary,
                fontWeight: FontWeight.bold,
                letterSpacing: 1.1,
              ),
            ),
            IconButton(
              icon: const Icon(Icons.refresh, size: 18),
              onPressed: () =>
                  ref.invalidate(patientAttendanceHistoryProvider(patientId)),
              tooltip: 'Refresh history',
            ),
          ],
        ),
        const SizedBox(height: AppSpacing.xs),
        historyAsync.when(
          loading: () => const Center(
            child: Padding(
              padding: EdgeInsets.all(AppSpacing.md),
              child: CircularProgressIndicator(),
            ),
          ),
          error: (error, _) => Container(
            padding: const EdgeInsets.all(AppSpacing.md),
            decoration: BoxDecoration(
              color: AppColors.surfaceContainerLowest,
              borderRadius: BorderRadius.circular(AppSpacing.radiusMd),
              border: Border.all(color: AppColors.outlineVariant),
            ),
            child: Text(
              'Unable to load attendance history: $error',
              style: AppTypography.bodySm.copyWith(color: AppColors.error),
            ),
          ),
          data: (records) {
            if (records.isEmpty) {
              return Container(
                width: double.infinity,
                padding: const EdgeInsets.all(AppSpacing.lg),
                decoration: BoxDecoration(
                  color: AppColors.surfaceContainerLowest,
                  borderRadius: BorderRadius.circular(AppSpacing.radiusLg),
                  border: Border.all(color: AppColors.outlineVariant),
                ),
                child: Center(
                  child: Column(
                    children: [
                      Icon(
                        Icons.event_busy_outlined,
                        size: 36,
                        color: AppColors.outline.withValues(alpha: 0.5),
                      ),
                      const SizedBox(height: AppSpacing.xs),
                      Text(
                        'No attendance records found for this patient.',
                        style: AppTypography.bodyMd
                            .copyWith(color: AppColors.onSurfaceVariant),
                      ),
                    ],
                  ),
                ),
              );
            }

            return Container(
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
              child: ListView.separated(
                shrinkWrap: true,
                physics: const NeverScrollableScrollPhysics(),
                itemCount: records.length,
                separatorBuilder: (_, __) =>
                    const Divider(height: 1, color: AppColors.outlineVariant),
                itemBuilder: (context, index) {
                  final record = records[index];
                  final staffName = record.staffName ?? 'Staff Member';
                  final dateFormatted = DateFormat('d MMM yyyy, h:mm a')
                      .format(record.attendedAt.toLocal());

                  return ListTile(
                    contentPadding: const EdgeInsets.symmetric(
                      horizontal: AppSpacing.md,
                      vertical: AppSpacing.xs,
                    ),
                    leading: CircleAvatar(
                      backgroundColor: Colors.green.withValues(alpha: 0.15),
                      radius: 20,
                      child: Icon(
                        Icons.check_circle,
                        color: Colors.green.shade700,
                        size: 20,
                      ),
                    ),
                    title: Text(
                      staffName,
                      style: AppTypography.bodyMd.copyWith(
                        fontWeight: FontWeight.w600,
                      ),
                    ),
                    subtitle: Text(
                      dateFormatted,
                      style: AppTypography.bodySm.copyWith(
                        color: AppColors.onSurfaceVariant,
                      ),
                    ),
                    trailing: Container(
                      padding: const EdgeInsets.symmetric(
                          horizontal: 8, vertical: 4),
                      decoration: BoxDecoration(
                        color: Colors.green.withValues(alpha: 0.1),
                        borderRadius:
                            BorderRadius.circular(AppSpacing.radiusSm),
                      ),
                      child: Text(
                        record.status.toUpperCase(),
                        style: AppTypography.labelCaps.copyWith(
                          color: Colors.green.shade800,
                          fontWeight: FontWeight.bold,
                          fontSize: 10,
                        ),
                      ),
                    ),
                  );
                },
              ),
            );
          },
        ),
      ],
    );
  }

  static String _initials(String name) {
    final parts = name.trim().split(RegExp(r'\s+'));
    if (parts.isEmpty) return '?';
    if (parts.length == 1) return parts[0][0].toUpperCase();
    return '${parts[0][0]}${parts[parts.length - 1][0]}'.toUpperCase();
  }
}
