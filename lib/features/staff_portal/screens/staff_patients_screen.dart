import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:intl/intl.dart';

import '../../../core/theme/app_colors.dart';
import '../../../core/theme/app_spacing.dart';
import '../../../core/theme/app_typography.dart';
import '../../auth/providers/auth_provider.dart';
import '../../patients/models/patient_model.dart';
import '../../patients/providers/patient_attendance_provider.dart';
import '../../patients/providers/patients_provider.dart';
import '../../patients/screens/patient_details_screen.dart';

/// Staff-facing patient list.
///
/// Shows every patient in the system and lets the logged-in staff member
/// record attendance with a single tap ("I ATTENDED").
///
/// Key behaviours:
/// - Connects to Supabase via [patientsProvider] (Sprint 4.1 provider).
/// - Tracks attendance via [staffPatientAttendanceProvider] (keyed by staffId).
/// - Per-patient loading spinner while the insert is in-flight.
/// - Duplicate-attendance guard: button shows "Attended ✓" once recorded.
/// - Works for cross-staff: if another staff already attended the patient today,
///   the "Staff can read today patient attendance" RLS policy exposes those
///   records via [staffPatientAttendanceProvider] so the UI shows the correct
///   state.
class StaffPatientsScreen extends ConsumerWidget {
  const StaffPatientsScreen({super.key});

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    final currentUser = ref.watch(currentUserProvider);
    if (currentUser == null) {
      return const Center(child: CircularProgressIndicator());
    }

    final currentProfile = ref.watch(currentProfileProvider).valueOrNull;
    final currentStaffFullName = currentProfile?.fullName;

    final patientsAsync = ref.watch(patientsProvider);
    // Watch the attendance notifier so the screen rebuilds whenever any
    // per-patient attendance state changes (loading, attended, error).
    ref.watch(staffPatientAttendanceProvider(currentUser.id));
    final attendanceNotifier =
        ref.watch(staffPatientAttendanceProvider(currentUser.id).notifier);

    final isDesktop = MediaQuery.sizeOf(context).width >= 768;

    return RefreshIndicator(
      onRefresh: () async {
        await Future.wait([
          ref.read(patientsProvider.notifier).loadPatients(),
          ref
              .read(staffPatientAttendanceProvider(currentUser.id).notifier)
              .refresh(),
        ]);
      },
      child: SingleChildScrollView(
        physics: const AlwaysScrollableScrollPhysics(),
        padding: EdgeInsets.all(
            isDesktop ? AppSpacing.marginDesktop : AppSpacing.marginMobile),
        child: Column(
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            // ── Header ─────────────────────────────────────────────────────
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
              style:
                  AppTypography.bodyLg.copyWith(color: AppColors.onSurfaceVariant),
            ),
            const SizedBox(height: AppSpacing.lg),

            // ── Patient list ─────────────────────────────────────────────
            patientsAsync.when(
              loading: () => const Center(child: CircularProgressIndicator()),
              error: (error, _) => _ErrorRetry(
                error: error,
                onRetry: () =>
                    ref.read(patientsProvider.notifier).loadPatients(),
              ),
              data: (patients) {
                if (patients.isEmpty) {
                  return const _EmptyState();
                }

                // Partition: UNATTENDED first, ATTENDED at the bottom.
                // Preserves existing ordering within each group.
                final unattendedPatients = patients
                    .where((p) => !attendanceNotifier.hasAttended(p.id))
                    .toList();
                final attendedPatients = patients
                    .where((p) => attendanceNotifier.hasAttended(p.id))
                    .toList();

                return Column(
                  crossAxisAlignment: CrossAxisAlignment.start,
                  children: [
                    // ── Unattended Patients Group ─────────────────────────
                    if (unattendedPatients.isNotEmpty) ...[
                      _SectionHeader(
                        title: 'UNATTENDED',
                        count: unattendedPatients.length,
                        color: AppColors.primary,
                      ),
                      const SizedBox(height: AppSpacing.sm),
                      ...unattendedPatients.map((patient) {
                        return Padding(
                          padding: const EdgeInsets.only(bottom: AppSpacing.md),
                          child: _PatientAttendanceCard(
                            patient: patient,
                            staffId: currentUser.id,
                            currentStaffFullName: currentStaffFullName,
                          ),
                        );
                      }),
                      if (attendedPatients.isNotEmpty)
                        const SizedBox(height: AppSpacing.md),
                    ],

                    // ── Attended Patients Group ───────────────────────────
                    if (attendedPatients.isNotEmpty) ...[
                      _SectionHeader(
                        title: 'ATTENDED',
                        count: attendedPatients.length,
                        color: Colors.green.shade700,
                      ),
                      const SizedBox(height: AppSpacing.sm),
                      ...attendedPatients.map((patient) {
                        return Padding(
                          padding: const EdgeInsets.only(bottom: AppSpacing.md),
                          child: _PatientAttendanceCard(
                            patient: patient,
                            staffId: currentUser.id,
                            currentStaffFullName: currentStaffFullName,
                          ),
                        );
                      }),
                    ],
                  ],
                );
              },
            ),
          ],
        ),
      ),
    );
  }
}

// ── Section Header ────────────────────────────────────────────────────────────

class _SectionHeader extends StatelessWidget {
  const _SectionHeader({
    required this.title,
    required this.count,
    required this.color,
  });

  final String title;
  final int count;
  final Color color;

  @override
  Widget build(BuildContext context) {
    return Padding(
      padding: const EdgeInsets.symmetric(vertical: AppSpacing.xs),
      child: Row(
        children: [
          Text(
            title,
            style: AppTypography.labelCaps.copyWith(
              color: color,
              fontWeight: FontWeight.bold,
              letterSpacing: 1.2,
            ),
          ),
          const SizedBox(width: AppSpacing.xs),
          Container(
            padding: const EdgeInsets.symmetric(horizontal: 7, vertical: 2),
            decoration: BoxDecoration(
              color: color.withValues(alpha: 0.12),
              borderRadius: BorderRadius.circular(10),
            ),
            child: Text(
              '$count',
              style: AppTypography.dataMono.copyWith(
                color: color,
                fontWeight: FontWeight.bold,
                fontSize: 11,
              ),
            ),
          ),
        ],
      ),
    );
  }
}

// ── Per-patient attendance card ───────────────────────────────────────────────

class _PatientAttendanceCard extends ConsumerWidget {
  const _PatientAttendanceCard({
    required this.patient,
    required this.staffId,
    this.currentStaffFullName,
  });

  final PatientModel patient;
  final String staffId;
  final String? currentStaffFullName;

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    final attendanceNotifier =
        ref.watch(staffPatientAttendanceProvider(staffId).notifier);
    final isLoading = attendanceNotifier.isLoading(patient.id);
    final hasAttended = attendanceNotifier.hasAttended(patient.id);
    final attendanceRecord = attendanceNotifier.getAttendance(patient.id);
    final isAttendedByMe = attendanceNotifier.isAttendedByMe(patient.id);

    final deptLabel =
        patient.department == 'eye' ? 'Eye' : patient.department == 'dental'
            ? 'Dental'
            : patient.department ?? '—';

    // Obtain the staff member's proper full name (never UUIDs or shortened IDs).
    final staffFullName = (isAttendedByMe
            ? (currentStaffFullName ?? attendanceRecord?.staffName)
            : attendanceRecord?.staffName) ??
        'Staff';

    final attendedAtFormatted = attendanceRecord != null
        ? DateFormat('d MMM yyyy, h:mm a')
            .format(attendanceRecord.attendedAt.toLocal())
        : DateFormat('d MMM yyyy, h:mm a').format(DateTime.now());

    return Container(
      decoration: BoxDecoration(
        color: AppColors.surfaceContainerLowest,
        borderRadius: BorderRadius.circular(AppSpacing.radiusLg),
        border: Border.all(
          color: hasAttended
              ? Colors.green.withValues(alpha: 0.4)
              : AppColors.outlineVariant,
        ),
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
        child: Row(
          crossAxisAlignment: CrossAxisAlignment.center,
          children: [
            // ── Tappable Avatar & Patient Info ───────────────────────────
            Expanded(
              child: InkWell(
                borderRadius: BorderRadius.circular(AppSpacing.radiusMd),
                onTap: () {
                  Navigator.of(context).push(
                    MaterialPageRoute(
                      builder: (_) =>
                          PatientDetailsScreen(patientId: patient.id),
                    ),
                  );
                },
                child: Row(
                  crossAxisAlignment: CrossAxisAlignment.center,
                  children: [
                    // ── Avatar ───────────────────────────────────────────
                    CircleAvatar(
                      backgroundColor: hasAttended
                          ? Colors.green.withValues(alpha: 0.15)
                          : AppColors.primaryContainer.withValues(alpha: 0.2),
                      radius: 26,
                      child: hasAttended
                          ? Icon(Icons.check_circle,
                              color: Colors.green.shade600, size: 24)
                          : Text(
                              _initials(patient.name),
                              style: AppTypography.labelCaps.copyWith(
                                  color: AppColors.primary,
                                  fontWeight: FontWeight.bold),
                            ),
                    ),
                    const SizedBox(width: AppSpacing.md),

                    // ── Patient info ─────────────────────────────────────
                    Expanded(
                      child: Column(
                        crossAxisAlignment: CrossAxisAlignment.start,
                        children: [
                          // Name + patient number
                          Wrap(
                            crossAxisAlignment: WrapCrossAlignment.center,
                            spacing: 6,
                            children: [
                              Text(
                                patient.name,
                                style: AppTypography.headlineMd
                                    .copyWith(fontSize: 17),
                              ),
                              Container(
                                padding: const EdgeInsets.symmetric(
                                    horizontal: 6, vertical: 2),
                                decoration: BoxDecoration(
                                  color: AppColors.surfaceContainerLow,
                                  borderRadius: BorderRadius.circular(4),
                                ),
                                child: Text(
                                  patient.patientNumber,
                                  style: AppTypography.dataMono.copyWith(
                                      fontSize: 12, color: AppColors.primary),
                                ),
                              ),
                            ],
                          ),
                          const SizedBox(height: AppSpacing.base),
                          // Department + mobile
                          Row(
                            children: [
                              Container(
                                padding: const EdgeInsets.symmetric(
                                    horizontal: 6, vertical: 2),
                                decoration: BoxDecoration(
                                  color: AppColors.secondaryContainer
                                      .withValues(alpha: 0.2),
                                  borderRadius: BorderRadius.circular(4),
                                ),
                                child: Text(
                                  deptLabel,
                                  style: AppTypography.labelCaps.copyWith(
                                      color: AppColors.secondary, fontSize: 10),
                                ),
                              ),
                              if (patient.mobile != null &&
                                  patient.mobile!.isNotEmpty) ...[
                                const SizedBox(width: AppSpacing.xs),
                                const Icon(Icons.phone_outlined,
                                    size: 13, color: AppColors.outline),
                                const SizedBox(width: 3),
                                Flexible(
                                  child: Text(
                                    patient.mobile!,
                                    style: AppTypography.bodySm.copyWith(
                                        color: AppColors.onSurfaceVariant),
                                    overflow: TextOverflow.ellipsis,
                                  ),
                                ),
                              ],
                            ],
                          ),
                          if (hasAttended) ...[
                            const SizedBox(height: AppSpacing.xs),
                            Container(
                              padding: const EdgeInsets.symmetric(
                                  horizontal: 8, vertical: 5),
                              decoration: BoxDecoration(
                                color: Colors.green.withValues(alpha: 0.08),
                                borderRadius: BorderRadius.circular(6),
                                border: Border.all(
                                    color: Colors.green.withValues(alpha: 0.2)),
                              ),
                              child: Column(
                                crossAxisAlignment: CrossAxisAlignment.start,
                                children: [
                                  Row(
                                    children: [
                                      Icon(
                                        Icons.check_circle,
                                        size: 14,
                                        color: Colors.green.shade700,
                                      ),
                                      const SizedBox(width: 5),
                                      Expanded(
                                        child: Text(
                                          'Attended by: $staffFullName',
                                          style: AppTypography.bodySm.copyWith(
                                            color: Colors.green.shade800,
                                            fontWeight: FontWeight.w600,
                                            fontSize: 12,
                                          ),
                                          overflow: TextOverflow.ellipsis,
                                        ),
                                      ),
                                    ],
                                  ),
                                  const SizedBox(height: 2),
                                  Padding(
                                    padding: const EdgeInsets.only(left: 19),
                                    child: Text(
                                      'Attended at: $attendedAtFormatted',
                                      style: AppTypography.bodySm.copyWith(
                                        color: AppColors.onSurfaceVariant,
                                        fontSize: 11,
                                      ),
                                    ),
                                  ),
                                ],
                              ),
                            ),
                          ],
                        ],
                      ),
                    ),
                  ],
                ),
              ),
            ),


            // ── Attendance button ─────────────────────────────────────────
            const SizedBox(width: AppSpacing.sm),
            _AttendButton(
              patientId: patient.id,
              staffId: staffId,
              isLoading: isLoading,
              hasAttended: hasAttended,
              isAttendedByMe: isAttendedByMe,
            ),
          ],
        ),
      ),
    );
  }

  static String _initials(String name) {
    final parts = name.trim().split(RegExp(r'\s+'));
    if (parts.isEmpty) return '?';
    if (parts.length == 1) return parts[0][0].toUpperCase();
    return '${parts[0][0]}${parts[parts.length - 1][0]}'.toUpperCase();
  }
}

// ── Attendance button (stateless + ConsumerWidget) ────────────────────────────

class _AttendButton extends ConsumerWidget {
  const _AttendButton({
    required this.patientId,
    required this.staffId,
    required this.isLoading,
    required this.hasAttended,
    required this.isAttendedByMe,
  });

  final String patientId;
  final String staffId;
  final bool isLoading;
  final bool hasAttended;
  final bool isAttendedByMe;

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    if (hasAttended) {
      final buttonLabel = isAttendedByMe ? 'Attended ✓' : 'Attended';

      return OutlinedButton.icon(
        onPressed: null, // disabled — already attended
        icon: Icon(
          isAttendedByMe ? Icons.check : Icons.done_all,
          size: 16,
        ),
        label: Text(buttonLabel),
        style: OutlinedButton.styleFrom(
          foregroundColor: isAttendedByMe
              ? Colors.green.shade700
              : AppColors.onSurfaceVariant,
          side: BorderSide(
            color: isAttendedByMe
                ? Colors.green.withValues(alpha: 0.5)
                : AppColors.outlineVariant,
          ),
          textStyle: AppTypography.labelCaps.copyWith(fontSize: 11),
          padding: const EdgeInsets.symmetric(horizontal: 10, vertical: 6),
        ),
      );
    }

    if (isLoading) {
      return const SizedBox(
        width: 40,
        height: 40,
        child: Center(
          child: SizedBox(
            width: 22,
            height: 22,
            child: CircularProgressIndicator(strokeWidth: 2),
          ),
        ),
      );
    }

    return FilledButton.icon(
      onPressed: () => _markAttended(context, ref),
      icon: const Icon(Icons.how_to_reg_outlined, size: 16),
      label: const Text('I Attended'),
      style: FilledButton.styleFrom(
        backgroundColor: AppColors.primary,
        foregroundColor: Colors.white,
        textStyle: AppTypography.labelCaps.copyWith(fontSize: 11),
        padding: const EdgeInsets.symmetric(horizontal: 10, vertical: 6),
      ),
    );
  }

  Future<void> _markAttended(BuildContext context, WidgetRef ref) async {
    final notifier =
        ref.read(staffPatientAttendanceProvider(staffId).notifier);
    try {
      final recorded = await notifier.markAttended(patientId);
      if (!context.mounted) return;
      final record = notifier.getAttendance(patientId);
      final attendingStaff = record?.staffName;

      ScaffoldMessenger.of(context).showSnackBar(
        SnackBar(
          content: Text(
            recorded
                ? 'Attendance recorded successfully.'
                : (attendingStaff != null
                    ? 'Already attended today by $attendingStaff.'
                    : 'Already recorded for today.'),
          ),
          backgroundColor:
              recorded ? Colors.green.shade700 : AppColors.onSurfaceVariant,
          duration: const Duration(seconds: 2),
        ),
      );
    } catch (e) {
      if (!context.mounted) return;
      ScaffoldMessenger.of(context).showSnackBar(
        SnackBar(
          content: Text('Error recording attendance: $e'),
          backgroundColor: AppColors.error,
        ),
      );
    }
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
          Icon(
            Icons.people_outline,
            size: 72,
            color: AppColors.outline.withValues(alpha: 0.4),
          ),
          const SizedBox(height: AppSpacing.md),
          Text(
            'No patients registered yet.',
            style: AppTypography.headlineMd
                .copyWith(color: AppColors.onSurfaceVariant),
          ),
          const SizedBox(height: AppSpacing.xs),
          Text(
            'Patient records will appear here once they are added.',
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
          const SizedBox(height: AppSpacing.xs),
          Text(
            '$error',
            textAlign: TextAlign.center,
            style: AppTypography.bodySm
                .copyWith(color: AppColors.onSurfaceVariant),
          ),
          const SizedBox(height: AppSpacing.md),
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
