import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:intl/intl.dart';

import '../../../core/theme/app_colors.dart';
import '../../../core/theme/app_spacing.dart';
import '../../../core/theme/app_typography.dart';
import '../../auth/providers/auth_provider.dart';
import '../../patients/models/patient.dart';
import '../../patients/models/patient_attendance.dart';
import '../../patients/providers/patient_attendance_provider.dart';
import '../../patients/providers/patient_provider.dart';
import '../../patients/screens/patient_details_screen.dart';

class StaffPatientsScreen extends ConsumerWidget {
  const StaffPatientsScreen({super.key});

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    final currentUser = ref.watch(currentUserProvider);
    if (currentUser == null) {
      return const Center(child: CircularProgressIndicator());
    }

    final patientsAsync = ref.watch(patientsProvider);
    // Watch the notifier — rebuilds whenever state OR per-patient loading
    // changes (the notifier re-assigns `state` to itself to trigger rebuilds).
    ref.watch(staffPatientAttendanceProvider(currentUser.id));

    final isDesktop = MediaQuery.sizeOf(context).width >= 768;

    return SingleChildScrollView(
      padding: EdgeInsets.all(
          isDesktop ? AppSpacing.marginDesktop : AppSpacing.marginMobile),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Text(
            'My Shift Patients',
            style: AppTypography.displayLg.copyWith(
              color: AppColors.onBackground,
              fontSize: isDesktop ? null : 26,
            ),
          ),
          const SizedBox(height: AppSpacing.xs),
          Text(
            'Record the patients you attend today.',
            style: AppTypography.bodyLg
                .copyWith(color: AppColors.onSurfaceVariant),
          ),
          const SizedBox(height: AppSpacing.lg),
          patientsAsync.when(
            loading: () => const Center(child: CircularProgressIndicator()),
            error: (error, _) => _ErrorRetry(
              error: error,
              onRetry: () =>
                  ref.read(patientsProvider.notifier).fetchPatients(),
            ),
            data: (patients) {
              if (patients.isEmpty) {
                return const _EmptyState();
              }
              return Column(
                children: patients.map((patient) {
                  return Padding(
                    padding: const EdgeInsets.only(bottom: AppSpacing.md),
                    child: _PatientAttendanceCard(
                      patient: patient,
                      staffId: currentUser.id,
                      onOpen: () => Navigator.of(context).push(
                        MaterialPageRoute(
                          builder: (_) =>
                              PatientDetailsScreen(patientId: patient.id),
                        ),
                      ),
                    ),
                  );
                }).toList(),
              );
            },
          ),
        ],
      ),
    );
  }
}

// ── Per-patient card ──────────────────────────────────────────────────────────
//
// This is a ConsumerWidget so it can read the notifier directly and check the
// per-patient loading / attended state without rebuilding the entire list.

class _PatientAttendanceCard extends ConsumerStatefulWidget {
  const _PatientAttendanceCard({
    required this.patient,
    required this.staffId,
    required this.onOpen,
  });

  final Patient patient;
  final String staffId;
  final VoidCallback onOpen;

  @override
  ConsumerState<_PatientAttendanceCard> createState() =>
      _PatientAttendanceCardState();
}

class _PatientAttendanceCardState
    extends ConsumerState<_PatientAttendanceCard> {
  @override
  Widget build(BuildContext context) {
    // Watch the provider so the card rebuilds on state changes.
    final attendanceAsync =
        ref.watch(staffPatientAttendanceProvider(widget.staffId));
    final notifier = ref.read(
      staffPatientAttendanceProvider(widget.staffId).notifier,
    );

    final isLoading = notifier.isLoading(widget.patient.id);
    final attended = notifier.hasAttended(widget.patient.id);

    // Find the attendance record for this patient (if any) for display.
    PatientAttendance? record;
    if (attendanceAsync is AsyncData<List<PatientAttendance>>) {
      try {
        record = attendanceAsync.value
            .firstWhere((r) => r.patientId == widget.patient.id);
      } catch (_) {
        record = null;
      }
    }

    return Card(
      child: Padding(
        padding: const EdgeInsets.all(AppSpacing.md),
        child: Column(
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            // ── Patient header (tappable → details screen) ───────────────
            InkWell(
              onTap: widget.onOpen,
              borderRadius: BorderRadius.circular(AppSpacing.radiusSm),
              child: Row(
                children: [
                  CircleAvatar(
                    backgroundColor:
                        AppColors.primaryContainer.withValues(alpha: 0.2),
                    child: Text(
                      _initials(widget.patient.fullName),
                      style: AppTypography.labelCaps
                          .copyWith(color: AppColors.primary),
                    ),
                  ),
                  const SizedBox(width: AppSpacing.md),
                  Expanded(
                    child: Column(
                      crossAxisAlignment: CrossAxisAlignment.start,
                      children: [
                        Text(widget.patient.fullName,
                            style: AppTypography.headlineMd),
                        Text(
                          '${widget.patient.departmentName ?? 'No department'} • ${widget.patient.registrationNumber}',
                          style: AppTypography.bodySm
                              .copyWith(color: AppColors.onSurfaceVariant),
                        ),
                      ],
                    ),
                  ),
                  const Icon(Icons.chevron_right,
                      color: AppColors.outline, size: 20),
                ],
              ),
            ),

            const SizedBox(height: AppSpacing.md),

            // ── Attendance status / action ────────────────────────────────
            if (attended && record != null) ...[
              Row(
                children: [
                  Icon(Icons.check_circle,
                      color: Colors.green.shade600, size: 18),
                  const SizedBox(width: AppSpacing.xs),
                  Text(
                    'Attended',
                    style: AppTypography.bodyMd.copyWith(
                      color: Colors.green.shade600,
                      fontWeight: FontWeight.w600,
                    ),
                  ),
                ],
              ),
              const SizedBox(height: AppSpacing.xs),
              Text(
                'By: ${record.staffName ?? 'You'} at '
                '${DateFormat('h:mm a').format(record.attendedAt.toLocal())}',
                style: AppTypography.bodySm
                    .copyWith(color: AppColors.onSurfaceVariant),
              ),
            ] else if (attended) ...[
              // Optimistic state: attended but record not yet in fetched list.
              Row(
                children: [
                  Icon(Icons.check_circle,
                      color: Colors.green.shade600, size: 18),
                  const SizedBox(width: AppSpacing.xs),
                  Text(
                    'Attended',
                    style: AppTypography.bodyMd.copyWith(
                      color: Colors.green.shade600,
                      fontWeight: FontWeight.w600,
                    ),
                  ),
                ],
              ),
            ] else ...[
              Text(
                'Status: Pending',
                style: AppTypography.bodyMd.copyWith(
                  color: Colors.orange.shade700,
                  fontWeight: FontWeight.w600,
                ),
              ),
              const SizedBox(height: AppSpacing.md),
              SizedBox(
                width: double.infinity,
                child: FilledButton(
                  // Disable while loading to prevent double-tap.
                  onPressed: isLoading ? null : () => _onAttend(context),
                  child: isLoading
                      ? const SizedBox(
                          height: 20,
                          width: 20,
                          child: CircularProgressIndicator(
                            strokeWidth: 2,
                            color: Colors.white,
                          ),
                        )
                      : const Text('I ATTENDED'),
                ),
              ),
            ],
          ],
        ),
      ),
    );
  }

  Future<void> _onAttend(BuildContext context) async {
    final notifier = ref.read(
      staffPatientAttendanceProvider(widget.staffId).notifier,
    );

    try {
      final wasNew = await notifier.markAttended(widget.patient.id);
      if (!context.mounted) return;
      if (wasNew) {
        ScaffoldMessenger.of(context).showSnackBar(
          const SnackBar(
            content: Text('Patient marked as attended.'),
            backgroundColor: Colors.green,
          ),
        );
      } else {
        ScaffoldMessenger.of(context).showSnackBar(
          const SnackBar(
            content: Text('Attendance already recorded for this patient today.'),
          ),
        );
      }
    } catch (error) {
      if (!context.mounted) return;
      ScaffoldMessenger.of(context).showSnackBar(
        SnackBar(
          content: Text('Unable to record attendance: $error'),
          backgroundColor: Colors.red,
        ),
      );
    }
  }

  static String _initials(String name) {
    final parts = name.trim().split(RegExp(r'\s+'));
    if (parts.isEmpty) return '?';
    if (parts.length == 1) return parts[0][0].toUpperCase();
    return '${parts[0][0]}${parts[1][0]}'.toUpperCase();
  }
}

// ── Empty state ───────────────────────────────────────────────────────────────

class _EmptyState extends StatelessWidget {
  const _EmptyState();

  @override
  Widget build(BuildContext context) {
    return Center(
      child: Column(
        mainAxisSize: MainAxisSize.min,
        children: [
          const SizedBox(height: AppSpacing.xl),
          Icon(Icons.people_outline,
              size: 64, color: AppColors.outline.withValues(alpha: 0.5)),
          const SizedBox(height: AppSpacing.md),
          Text(
            'No patients available.',
            style: AppTypography.headlineMd
                .copyWith(color: AppColors.onSurfaceVariant),
          ),
          const SizedBox(height: AppSpacing.xs),
          Text(
            'Patients registered in the system will appear here.',
            textAlign: TextAlign.center,
            style: AppTypography.bodyMd
                .copyWith(color: AppColors.onSurfaceVariant),
          ),
        ],
      ),
    );
  }
}

// ── Error / retry ─────────────────────────────────────────────────────────────

class _ErrorRetry extends StatelessWidget {
  const _ErrorRetry({required this.error, required this.onRetry});

  final Object error;
  final VoidCallback onRetry;

  @override
  Widget build(BuildContext context) {
    return Center(
      child: Column(
        mainAxisSize: MainAxisSize.min,
        children: [
          const Icon(Icons.error_outline, size: 48, color: AppColors.error),
          const SizedBox(height: AppSpacing.sm),
          const Text('Unable to load patients.'),
          Text('$error', textAlign: TextAlign.center),
          const SizedBox(height: AppSpacing.sm),
          FilledButton.icon(
            onPressed: onRetry,
            icon: const Icon(Icons.refresh),
            label: const Text('Retry'),
          ),
        ],
      ),
    );
  }
}


