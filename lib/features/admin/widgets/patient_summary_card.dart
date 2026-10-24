import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';

import '../../../core/theme/app_colors.dart';
import '../../../core/theme/app_spacing.dart';
import '../../../core/theme/app_typography.dart';
import '../../../core/utils/date_boundaries.dart';
import '../../patients/models/patient_model.dart';
import '../../patients/providers/patients_provider.dart';
import '../../patients/screens/patient_list_screen.dart';

/// Live dashboard card displaying strictly today's operational patient metrics:
/// - Unique patients scheduled today & total appointment count
/// - New patient registrations today
/// - Today's department appointment split
class PatientSummaryCard extends ConsumerWidget {
  const PatientSummaryCard({
    super.key,
    this.onNavigateToPatients,
  });

  /// Optional callback invoked when the user taps "Manage Patients".
  /// Defaults to navigating to [PatientListScreen].
  final VoidCallback? onNavigateToPatients;

  static const _surfaceBorder = Color(0xFFE5E2E1);

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    final patientsAsync = ref.watch(patientsProvider);
    final scheduledAsync = ref.watch(todayScheduledPatientsProvider);

    return DecoratedBox(
      decoration: BoxDecoration(
        color: AppColors.surfaceContainerLowest,
        borderRadius: BorderRadius.circular(AppSpacing.radiusLg),
        border: Border.all(color: _surfaceBorder),
        boxShadow: const [
          BoxShadow(
            color: Color(0x0A000000),
            blurRadius: 8,
            offset: Offset(0, 1),
          ),
        ],
      ),
      child: Padding(
        padding: const EdgeInsets.all(AppSpacing.md),
        child: Column(
          crossAxisAlignment: CrossAxisAlignment.stretch,
          children: [
            // Header with navigation action to historical Patient List
            DecoratedBox(
              decoration: const BoxDecoration(
                border: Border(
                  bottom: BorderSide(color: AppColors.outlineVariant),
                ),
              ),
              child: Padding(
                padding: const EdgeInsets.only(bottom: AppSpacing.xs),
                child: Wrap(
                  alignment: WrapAlignment.spaceBetween,
                  crossAxisAlignment: WrapCrossAlignment.center,
                  spacing: AppSpacing.xs,
                  runSpacing: 4,
                  children: [
                    Row(
                      mainAxisSize: MainAxisSize.min,
                      children: [
                        const Icon(
                          Icons.people_alt_outlined,
                          color: AppColors.primary,
                          size: 22,
                        ),
                        const SizedBox(width: AppSpacing.xs),
                        Flexible(
                          child: Text(
                            'Patient Statistics',
                            style: AppTypography.headlineMd,
                          ),
                        ),
                      ],
                    ),
                    TextButton(
                      onPressed: () {
                        if (onNavigateToPatients != null) {
                          onNavigateToPatients!();
                        } else {
                          Navigator.of(context).push(
                            MaterialPageRoute(
                              builder: (_) => const PatientListScreen(),
                            ),
                          );
                        }
                      },
                      style: TextButton.styleFrom(
                        padding: EdgeInsets.zero,
                        minimumSize: Size.zero,
                        tapTargetSize: MaterialTapTargetSize.shrinkWrap,
                      ),
                      child: Row(
                        mainAxisSize: MainAxisSize.min,
                        children: [
                          Text(
                            'Manage Patients',
                            style: AppTypography.labelCaps.copyWith(
                              color: AppColors.primary,
                            ),
                          ),
                          const SizedBox(width: 2),
                          const Icon(
                            Icons.chevron_right,
                            size: 16,
                            color: AppColors.primary,
                          ),
                        ],
                      ),
                    ),
                  ],
                ),
              ),
            ),
            const SizedBox(height: AppSpacing.md),

            // Async content
            patientsAsync.when(
              loading: () => _buildLoadingState(),
              error: (err, _) => _buildErrorState(ref, err.toString()),
              data: (patients) {
                return scheduledAsync.when(
                  loading: () => _buildLoadingState(),
                  error: (err, _) => _buildErrorState(ref, err.toString()),
                  data: (scheduledEntries) => _buildDataContent(
                    context,
                    patients,
                    scheduledEntries,
                  ),
                );
              },
            ),
          ],
        ),
      ),
    );
  }

  Widget _buildLoadingState() {
    return const SizedBox(
      height: 180,
      child: Center(
        child: Column(
          mainAxisAlignment: MainAxisAlignment.center,
          children: [
            SizedBox(
              width: 24,
              height: 24,
              child: CircularProgressIndicator(
                strokeWidth: 2.5,
                color: AppColors.primary,
              ),
            ),
            SizedBox(height: AppSpacing.sm),
            Text(
              'Loading patient summary...',
              style: TextStyle(
                color: AppColors.onSurfaceVariant,
                fontSize: 12,
              ),
            ),
          ],
        ),
      ),
    );
  }

  Widget _buildErrorState(WidgetRef ref, String error) {
    return SizedBox(
      height: 180,
      child: Center(
        child: Padding(
          padding: const EdgeInsets.symmetric(horizontal: AppSpacing.md),
          child: Column(
            mainAxisAlignment: MainAxisAlignment.center,
            children: [
              const Icon(
                Icons.error_outline,
                color: AppColors.error,
                size: 28,
              ),
              const SizedBox(height: AppSpacing.xs),
              Text(
                'Unable to load patient data',
                style: AppTypography.labelCaps.copyWith(
                  color: AppColors.error,
                  fontWeight: FontWeight.w600,
                ),
              ),
              const SizedBox(height: 2),
              Text(
                error,
                style: AppTypography.bodySm.copyWith(
                  color: AppColors.onSurfaceVariant,
                  fontSize: 11,
                ),
                maxLines: 2,
                overflow: TextOverflow.ellipsis,
                textAlign: TextAlign.center,
              ),
              const SizedBox(height: AppSpacing.xs),
              OutlinedButton.icon(
                onPressed: () {
                  ref.invalidate(patientsProvider);
                  ref.invalidate(todayScheduledPatientsProvider);
                },
                icon: const Icon(Icons.refresh, size: 14),
                label: const Text('Retry'),
                style: OutlinedButton.styleFrom(
                  padding: const EdgeInsets.symmetric(
                    horizontal: AppSpacing.sm,
                    vertical: AppSpacing.base,
                  ),
                ),
              ),
            ],
          ),
        ),
      ),
    );
  }

  Widget _buildDataContent(
    BuildContext context,
    List<PatientModel> patients,
    List<ScheduledPatientEntry> scheduledEntries,
  ) {
    // 1. Strictly count patients registered today (local calendar day)
    final registeredToday = patients.where((p) {
      return DateBoundaries.isToday(p.createdAt);
    }).length;

    // 2. Count unique patients scheduled today vs total appointment records today
    final uniquePatientsScheduled = scheduledEntries.length;
    final totalAppointmentsToday = scheduledEntries.fold<int>(
      0,
      (sum, entry) => sum + entry.todayAppointments.length,
    );

    // 3. Department breakdown of today's scheduled appointments
    int todayEyeAppointments = 0;
    int todayDentalAppointments = 0;

    for (final entry in scheduledEntries) {
      for (final appt in entry.todayAppointments) {
        final dept = appt.department.toLowerCase();
        if (dept == 'eye') todayEyeAppointments++;
        if (dept == 'dental') todayDentalAppointments++;
      }
    }

    if (uniquePatientsScheduled == 0 && registeredToday == 0) {
      return Container(
        height: 180,
        alignment: Alignment.center,
        child: Column(
          mainAxisAlignment: MainAxisAlignment.center,
          children: [
            const Icon(
              Icons.people_outline,
              size: 36,
              color: AppColors.outlineVariant,
            ),
            const SizedBox(height: AppSpacing.xs),
            Text(
              'No patient activity scheduled for today',
              style: AppTypography.bodySm.copyWith(
                color: AppColors.onSurfaceVariant,
              ),
            ),
          ],
        ),
      );
    }

    return Column(
      crossAxisAlignment: CrossAxisAlignment.stretch,
      children: [
        // Two KPI summary tiles scoped strictly to today
        Row(
          children: [
            Expanded(
              child: _MetricTile(
                title: 'Scheduled Today',
                value: '$uniquePatientsScheduled',
                subtitle: totalAppointmentsToday == 1
                    ? '1 appointment'
                    : '$totalAppointmentsToday appointments',
                icon: Icons.calendar_month_outlined,
                iconColor: AppColors.primary,
                bgColor: AppColors.primaryContainer.withValues(alpha: 0.12),
              ),
            ),
            const SizedBox(width: AppSpacing.sm),
            Expanded(
              child: _MetricTile(
                title: 'New Registrations',
                value: '$registeredToday',
                subtitle: registeredToday > 0
                    ? '$registeredToday registered today'
                    : 'No new registrations',
                icon: Icons.person_add_outlined,
                iconColor: AppColors.secondary,
                bgColor: AppColors.secondary.withValues(alpha: 0.12),
              ),
            ),
          ],
        ),
        const SizedBox(height: AppSpacing.md),

        // Department distribution bar & counts for today's scheduled appointments
        Container(
          padding: const EdgeInsets.symmetric(
            horizontal: AppSpacing.sm,
            vertical: AppSpacing.xs,
          ),
          decoration: BoxDecoration(
            color: AppColors.surfaceContainerLow,
            borderRadius: BorderRadius.circular(AppSpacing.radiusMd),
          ),
          child: Column(
            crossAxisAlignment: CrossAxisAlignment.stretch,
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
                      Container(
                        width: 8,
                        height: 8,
                        decoration: const BoxDecoration(
                          color: AppColors.primary,
                          shape: BoxShape.circle,
                        ),
                      ),
                      const SizedBox(width: 4),
                      Text(
                        'Eye Clinic: $todayEyeAppointments',
                        style: AppTypography.bodySm.copyWith(
                          fontSize: 11,
                          fontWeight: FontWeight.w600,
                        ),
                      ),
                    ],
                  ),
                  Row(
                    mainAxisSize: MainAxisSize.min,
                    children: [
                      Container(
                        width: 8,
                        height: 8,
                        decoration: const BoxDecoration(
                          color: AppColors.secondary,
                          shape: BoxShape.circle,
                        ),
                      ),
                      const SizedBox(width: 4),
                      Text(
                        'Dental Clinic: $todayDentalAppointments',
                        style: AppTypography.bodySm.copyWith(
                          fontSize: 11,
                          fontWeight: FontWeight.w600,
                        ),
                      ),
                    ],
                  ),
                ],
              ),
              const SizedBox(height: AppSpacing.xs),
              ClipRRect(
                borderRadius: BorderRadius.circular(2),
                child: SizedBox(
                  height: 4,
                  child: Row(
                    children: [
                      Expanded(
                        flex: totalAppointmentsToday > 0
                            ? (todayEyeAppointments * 100)
                            : 1,
                        child: Container(color: AppColors.primary),
                      ),
                      Expanded(
                        flex: totalAppointmentsToday > 0
                            ? (todayDentalAppointments * 100)
                            : 1,
                        child: Container(color: AppColors.secondary),
                      ),
                    ],
                  ),
                ),
              ),
            ],
          ),
        ),
        const SizedBox(height: AppSpacing.xs),

        // Footer note
        Padding(
          padding: const EdgeInsets.symmetric(horizontal: 2),
          child: Wrap(
            alignment: WrapAlignment.spaceBetween,
            crossAxisAlignment: WrapCrossAlignment.center,
            spacing: AppSpacing.xs,
            runSpacing: 2,
            children: [
              Text(
                registeredToday > 0
                    ? '$registeredToday new registered today'
                    : 'No new registrations today',
                style: AppTypography.bodySm.copyWith(
                  color: AppColors.onSurfaceVariant,
                  fontSize: 11,
                ),
              ),
              Text(
                'Daily operational view',
                style: AppTypography.labelCaps.copyWith(
                  color: AppColors.outline,
                  fontSize: 10,
                ),
              ),
            ],
          ),
        ),
      ],
    );
  }
}

class _MetricTile extends StatelessWidget {
  const _MetricTile({
    required this.title,
    required this.value,
    required this.subtitle,
    required this.icon,
    required this.iconColor,
    required this.bgColor,
  });

  final String title;
  final String value;
  final String subtitle;
  final IconData icon;
  final Color iconColor;
  final Color bgColor;

  @override
  Widget build(BuildContext context) {
    return Container(
      padding: const EdgeInsets.all(AppSpacing.sm),
      decoration: BoxDecoration(
        color: AppColors.surfaceContainerLowest,
        borderRadius: BorderRadius.circular(AppSpacing.radiusMd),
        border: Border.all(color: AppColors.outlineVariant),
      ),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Row(
            mainAxisAlignment: MainAxisAlignment.spaceBetween,
            children: [
              Flexible(
                child: Text(
                  title,
                  style: AppTypography.labelCaps.copyWith(
                    color: AppColors.onSurfaceVariant,
                    fontSize: 10,
                    fontWeight: FontWeight.w600,
                  ),
                  overflow: TextOverflow.ellipsis,
                ),
              ),
              Container(
                padding: const EdgeInsets.all(4),
                decoration: BoxDecoration(
                  color: bgColor,
                  borderRadius: BorderRadius.circular(AppSpacing.radiusSm),
                ),
                child: Icon(icon, size: 14, color: iconColor),
              ),
            ],
          ),
          const SizedBox(height: AppSpacing.xs),
          Text(
            value,
            style: AppTypography.headlineMd.copyWith(
              color: AppColors.onSurface,
              fontWeight: FontWeight.bold,
              fontSize: 22,
            ),
            maxLines: 1,
            overflow: TextOverflow.ellipsis,
          ),
          const SizedBox(height: 2),
          Text(
            subtitle,
            style: AppTypography.bodySm.copyWith(
              color: AppColors.onSurfaceVariant,
              fontSize: 10,
            ),
            maxLines: 1,
            overflow: TextOverflow.ellipsis,
          ),
        ],
      ),
    );
  }
}
