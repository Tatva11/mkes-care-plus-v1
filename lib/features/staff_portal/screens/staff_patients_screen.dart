import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:intl/intl.dart';

import '../../../core/theme/app_colors.dart';
import '../../../core/theme/app_spacing.dart';
import '../../../core/theme/app_typography.dart';
import '../../appointments/models/appointment_model.dart';
import '../../auth/providers/auth_provider.dart';
import '../../patients/models/patient_model.dart';
import '../../patients/providers/patient_attendance_provider.dart';
import '../../patients/providers/patients_provider.dart';
import '../../patients/screens/patient_details_screen.dart';

/// Staff-facing patient list & search.
///
/// Features:
/// - Restricted by default to patients scheduled for today's local date (Requirement 2).
/// - Comprehensive patient search parity for Staff (Requirement 6).
/// - Attendance tracking via [staffPatientAttendanceProvider].
class StaffPatientsScreen extends ConsumerStatefulWidget {
  const StaffPatientsScreen({super.key});

  @override
  ConsumerState<StaffPatientsScreen> createState() => _StaffPatientsScreenState();
}

class _StaffPatientsScreenState extends ConsumerState<StaffPatientsScreen> {
  final _searchController = TextEditingController();
  String _searchQuery = '';

  @override
  void dispose() {
    _searchController.dispose();
    super.dispose();
  }

  @override
  Widget build(BuildContext context) {
    final currentUser = ref.watch(currentUserProvider);
    if (currentUser == null) {
      return const Center(child: CircularProgressIndicator());
    }

    final currentProfile = ref.watch(currentProfileProvider).valueOrNull;
    final currentStaffFullName = currentProfile?.fullName;

    // Watch the attendance notifier so the screen rebuilds whenever any
    // per-patient attendance state changes (loading, attended, error).
    ref.watch(staffPatientAttendanceProvider(currentUser.id));
    final attendanceNotifier =
        ref.watch(staffPatientAttendanceProvider(currentUser.id).notifier);

    final isSearching = _searchQuery.isNotEmpty;
    final isDesktop = MediaQuery.sizeOf(context).width >= 768;

    return RefreshIndicator(
      onRefresh: () async {
        await Future.wait([
          ref.refresh(todayScheduledPatientsProvider.future),
          ref.read(staffPatientAttendanceProvider(currentUser.id).notifier).refresh(),
        ]);
      },
      child: SingleChildScrollView(
        physics: const AlwaysScrollableScrollPhysics(),
        padding: EdgeInsets.all(
          isDesktop ? AppSpacing.marginDesktop : AppSpacing.marginMobile,
        ),
        child: Column(
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            // ── Header ─────────────────────────────────────────────────────
            Row(
              mainAxisAlignment: MainAxisAlignment.spaceBetween,
              children: [
                Expanded(
                  child: Column(
                    crossAxisAlignment: CrossAxisAlignment.start,
                    children: [
                      Text(
                        isSearching ? 'Patient Search' : 'Today’s Scheduled Patients',
                        style: AppTypography.displayLg.copyWith(
                          color: AppColors.onBackground,
                          fontSize: isDesktop ? null : 24,
                        ),
                      ),
                      const SizedBox(height: AppSpacing.xs),
                      Text(
                        isSearching
                            ? 'Search clinic patients by name, number, or mobile.'
                            : 'Patients scheduled for ${DateFormat('d MMM yyyy').format(DateTime.now())}.',
                        style: AppTypography.bodyLg
                            .copyWith(color: AppColors.onSurfaceVariant),
                      ),
                    ],
                  ),
                ),
              ],
            ),
            const SizedBox(height: AppSpacing.md),

            // ── Search Bar (Staff Patient Search — Requirement 6) ───────────
            Container(
              decoration: BoxDecoration(
                color: AppColors.surfaceContainerLowest,
                borderRadius: BorderRadius.circular(AppSpacing.radiusMd),
                border: Border.all(color: AppColors.outlineVariant),
              ),
              child: TextField(
                controller: _searchController,
                onChanged: (val) => setState(() => _searchQuery = val.trim()),
                decoration: InputDecoration(
                  hintText: 'Search patients by name, ID, or mobile...',
                  prefixIcon: const Icon(Icons.search, color: AppColors.primary),
                  suffixIcon: _searchQuery.isNotEmpty
                      ? IconButton(
                          icon: const Icon(Icons.clear),
                          onPressed: () {
                            _searchController.clear();
                            setState(() => _searchQuery = '');
                          },
                        )
                      : null,
                  border: InputBorder.none,
                  contentPadding: const EdgeInsets.symmetric(
                    horizontal: AppSpacing.md,
                    vertical: AppSpacing.sm,
                  ),
                ),
              ),
            ),
            const SizedBox(height: AppSpacing.lg),

            // ── Search Mode vs Today's Scheduled Mode ──────────────────────
            if (isSearching)
              _buildSearchResults(currentUser.id, currentStaffFullName)
            else
              _buildTodayScheduledPatients(
                currentUser.id,
                currentStaffFullName,
                attendanceNotifier,
              ),
          ],
        ),
      ),
    );
  }

  // ── Search Results (Requirement 6) ─────────────────────────────────────────
  Widget _buildSearchResults(String staffId, String? staffFullName) {
    final searchAsync = ref.watch(patientSearchProvider((
      department: '',
      query: _searchQuery,
    )));

    return searchAsync.when(
      loading: () => const Center(
        child: Padding(
          padding: EdgeInsets.all(AppSpacing.xl),
          child: CircularProgressIndicator(),
        ),
      ),
      error: (e, _) => _ErrorRetry(
        error: e,
        onRetry: () => ref.invalidate(patientSearchProvider),
      ),
      data: (patients) {
        if (patients.isEmpty) {
          return Center(
            child: Padding(
              padding: const EdgeInsets.all(AppSpacing.xl),
              child: Column(
                mainAxisSize: MainAxisSize.min,
                children: [
                  const Icon(Icons.search_off, size: 48, color: AppColors.outline),
                  const SizedBox(height: AppSpacing.sm),
                  Text(
                    'No patients matching "$_searchQuery"',
                    style: AppTypography.headlineMd
                        .copyWith(color: AppColors.onSurfaceVariant),
                  ),
                  const SizedBox(height: AppSpacing.xs),
                  Text(
                    'Try checking the spelling or search by mobile number.',
                    style: AppTypography.bodySm
                        .copyWith(color: AppColors.onSurfaceVariant),
                  ),
                ],
              ),
            ),
          );
        }

        return Column(
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            _SectionHeader(
              title: 'SEARCH RESULTS',
              count: patients.length,
              color: AppColors.primary,
            ),
            const SizedBox(height: AppSpacing.sm),
            ...patients.map((patient) {
              return Padding(
                padding: const EdgeInsets.only(bottom: AppSpacing.md),
                child: _StaffPatientSearchResultCard(
                  patient: patient,
                ),
              );
            }),
          ],
        );
      },
    );
  }

  // ── Today's Scheduled Patients (Requirement 2) ─────────────────────────────
  Widget _buildTodayScheduledPatients(
    String staffId,
    String? staffFullName,
    StaffPatientAttendanceNotifier attendanceNotifier,
  ) {
    final scheduledAsync = ref.watch(todayScheduledPatientsProvider);

    return scheduledAsync.when(
      loading: () => const Center(
        child: Padding(
          padding: EdgeInsets.all(AppSpacing.xl),
          child: CircularProgressIndicator(),
        ),
      ),
      error: (error, _) => _ErrorRetry(
        error: error,
        onRetry: () => ref.refresh(todayScheduledPatientsProvider.future),
      ),
      data: (scheduledEntries) {
        if (scheduledEntries.isEmpty) {
          return const _EmptyState();
        }

        // Partition: UNATTENDED first, ATTENDED at the bottom.
        final unattended = scheduledEntries
            .where((entry) => !attendanceNotifier.hasAttended(entry.patient.id))
            .toList();
        final attended = scheduledEntries
            .where((entry) => attendanceNotifier.hasAttended(entry.patient.id))
            .toList();

        return Column(
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            // ── Unattended Group ──────────────────────────────────────────
            if (unattended.isNotEmpty) ...[
              _SectionHeader(
                title: 'UNATTENDED TODAY',
                count: unattended.length,
                color: AppColors.primary,
              ),
              const SizedBox(height: AppSpacing.sm),
              ...unattended.map((entry) {
                return Padding(
                  padding: const EdgeInsets.only(bottom: AppSpacing.md),
                  child: _PatientAttendanceCard(
                    patient: entry.patient,
                    appointments: entry.todayAppointments,
                    staffId: staffId,
                    currentStaffFullName: staffFullName,
                  ),
                );
              }),
              if (attended.isNotEmpty) const SizedBox(height: AppSpacing.md),
            ],

            // ── Attended Group ────────────────────────────────────────────
            if (attended.isNotEmpty) ...[
              _SectionHeader(
                title: 'ATTENDED TODAY',
                count: attended.length,
                color: Colors.green.shade700,
              ),
              const SizedBox(height: AppSpacing.sm),
              ...attended.map((entry) {
                return Padding(
                  padding: const EdgeInsets.only(bottom: AppSpacing.md),
                  child: _PatientAttendanceCard(
                    patient: entry.patient,
                    appointments: entry.todayAppointments,
                    staffId: staffId,
                    currentStaffFullName: staffFullName,
                  ),
                );
              }),
            ],
          ],
        );
      },
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

// ── Dedicated search result card (CHANGE 3) ──────────────────────────────────

class _StaffPatientSearchResultCard extends StatelessWidget {
  const _StaffPatientSearchResultCard({
    required this.patient,
  });

  final PatientModel patient;

  static String _initials(String name) {
    final parts = name.trim().split(RegExp(r'\s+'));
    if (parts.isEmpty || parts.first.isEmpty) return '?';
    if (parts.length == 1) return parts.first[0].toUpperCase();
    return '${parts.first[0]}${parts.last[0]}'.toUpperCase();
  }

  @override
  Widget build(BuildContext context) {
    final deptLabel = patient.department == 'eye'
        ? 'Eye'
        : patient.department == 'dental'
            ? 'Dental'
            : (patient.department?.toUpperCase() ?? 'GENERAL');

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
      child: Material(
        color: Colors.transparent,
        borderRadius: BorderRadius.circular(AppSpacing.radiusLg),
        child: InkWell(
          key: Key('staff_patient_search_result_${patient.id}'),
          borderRadius: BorderRadius.circular(AppSpacing.radiusLg),
          onTap: () {
            Navigator.of(context).push(
              MaterialPageRoute(
                builder: (_) => PatientDetailsScreen(patientId: patient.id),
              ),
            );
          },
          child: Padding(
            padding: const EdgeInsets.all(AppSpacing.md),
            child: Row(
              crossAxisAlignment: CrossAxisAlignment.center,
              children: [
                // ── Avatar ───────────────────────────────────────────
                CircleAvatar(
                  backgroundColor: AppColors.primaryContainer.withValues(alpha: 0.2),
                  radius: 26,
                  child: Text(
                    _initials(patient.name),
                    style: AppTypography.labelCaps.copyWith(
                      color: AppColors.primary,
                      fontWeight: FontWeight.bold,
                    ),
                  ),
                ),
                const SizedBox(width: AppSpacing.md),

                // ── Patient Info ─────────────────────────────────────
                Expanded(
                  child: Column(
                    crossAxisAlignment: CrossAxisAlignment.start,
                    children: [
                      Wrap(
                        crossAxisAlignment: WrapCrossAlignment.center,
                        spacing: 6,
                        children: [
                          Text(
                            patient.name,
                            style: AppTypography.headlineMd.copyWith(fontSize: 17),
                          ),
                          Container(
                            padding: const EdgeInsets.symmetric(
                              horizontal: 6,
                              vertical: 2,
                            ),
                            decoration: BoxDecoration(
                              color: AppColors.surfaceContainerLow,
                              borderRadius: BorderRadius.circular(4),
                            ),
                            child: Text(
                              patient.patientNumber,
                              style: AppTypography.dataMono.copyWith(
                                fontSize: 12,
                                color: AppColors.primary,
                              ),
                            ),
                          ),
                        ],
                      ),
                      const SizedBox(height: AppSpacing.base),
                      Row(
                        children: [
                          Container(
                            padding: const EdgeInsets.symmetric(
                              horizontal: 6,
                              vertical: 2,
                            ),
                            decoration: BoxDecoration(
                              color: AppColors.secondaryContainer.withValues(alpha: 0.2),
                              borderRadius: BorderRadius.circular(4),
                            ),
                            child: Text(
                              deptLabel,
                              style: AppTypography.labelCaps.copyWith(
                                color: AppColors.secondary,
                                fontSize: 10,
                              ),
                            ),
                          ),
                          if (patient.dob != null) ...[
                            const SizedBox(width: AppSpacing.xs),
                            Text(
                              '${DateTime.now().year - patient.dob!.year}y',
                              style: AppTypography.bodySm.copyWith(
                                color: AppColors.onSurfaceVariant,
                              ),
                            ),
                          ],
                          if (patient.mobile != null && patient.mobile!.isNotEmpty) ...[
                            const SizedBox(width: AppSpacing.xs),
                            const Icon(Icons.phone_outlined,
                                size: 13, color: AppColors.outline),
                            const SizedBox(width: 3),
                            Flexible(
                              child: Text(
                                patient.mobile!,
                                style: AppTypography.bodySm.copyWith(
                                  color: AppColors.onSurfaceVariant,
                                ),
                                overflow: TextOverflow.ellipsis,
                              ),
                            ),
                          ],
                        ],
                      ),
                    ],
                  ),
                ),

                const SizedBox(width: AppSpacing.sm),

                // ── Chevron / View Details Hint ────────────────────────
                const Icon(
                  Icons.arrow_forward_ios_rounded,
                  size: 16,
                  color: AppColors.outline,
                ),
              ],
            ),
          ),
        ),
      ),
    );
  }
}

// ── Per-patient attendance card ───────────────────────────────────────────────

class _PatientAttendanceCard extends ConsumerWidget {
  const _PatientAttendanceCard({
    required this.patient,
    this.appointments,
    required this.staffId,
    this.currentStaffFullName,
  });

  final PatientModel patient;
  final List<AppointmentModel>? appointments;
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
        child: Column(
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            Row(
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
                            ],
                          ),
                        ),
                      ],
                    ),
                  ),
                ),

                const SizedBox(width: AppSpacing.sm),

                // ── "I Attended" button ──────────────────────────────────────
                _AttendanceActionButton(
                  hasAttended: hasAttended,
                  isLoading: isLoading,
                  isAttendedByMe: isAttendedByMe,
                  attendingStaffName: staffFullName,
                  patientId: patient.id,
                  staffId: staffId,
                ),
              ],
            ),

            // ── Today's Appointment Chips (Requirement 2 & 9) ─────────────
            if (appointments != null && appointments!.isNotEmpty) ...[
              const SizedBox(height: AppSpacing.sm),
              Wrap(
                spacing: 6,
                runSpacing: 4,
                children: appointments!.map((appt) {
                  final time = appt.appointmentTime.isNotEmpty
                      ? appt.appointmentTime.substring(0, 5)
                      : 'Scheduled';
                  return Container(
                    padding: const EdgeInsets.symmetric(horizontal: 8, vertical: 3),
                    decoration: BoxDecoration(
                      color: AppColors.primaryContainer.withValues(alpha: 0.1),
                      borderRadius: BorderRadius.circular(4),
                      border: Border.all(
                          color: AppColors.primaryContainer.withValues(alpha: 0.3)),
                    ),
                    child: Row(
                      mainAxisSize: MainAxisSize.min,
                      children: [
                        const Icon(Icons.schedule, size: 12, color: AppColors.primary),
                        const SizedBox(width: 4),
                        Text(
                          '$time · ${appt.department.toUpperCase()}',
                          style: AppTypography.dataMono.copyWith(
                            fontSize: 11,
                            fontWeight: FontWeight.w600,
                            color: AppColors.primary,
                          ),
                        ),
                      ],
                    ),
                  );
                }).toList(),
              ),
            ],

            // ── Attendance timestamp banner if attended ───────────────────
            if (hasAttended) ...[
              const SizedBox(height: AppSpacing.xs),
              Container(
                padding: const EdgeInsets.symmetric(horizontal: 8, vertical: 4),
                decoration: BoxDecoration(
                  color: Colors.green.withValues(alpha: 0.08),
                  borderRadius: BorderRadius.circular(6),
                  border: Border.all(color: Colors.green.withValues(alpha: 0.2)),
                ),
                child: Row(
                  children: [
                    Icon(Icons.check_circle_outline,
                        size: 14, color: Colors.green.shade700),
                    const SizedBox(width: 6),
                    Expanded(
                      child: Text(
                        isAttendedByMe
                            ? 'Attended by you on $attendedAtFormatted'
                            : 'Attended by $staffFullName on $attendedAtFormatted',
                        style: AppTypography.bodySm.copyWith(
                          color: Colors.green.shade800,
                          fontSize: 11,
                          fontWeight: FontWeight.w500,
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
    );
  }

  String _initials(String name) {
    final parts = name.trim().split(RegExp(r'\s+'));
    if (parts.isEmpty || parts.first.isEmpty) return '?';
    if (parts.length == 1) return parts.first[0].toUpperCase();
    return '${parts.first[0]}${parts.last[0]}'.toUpperCase();
  }
}

// ── Attendance action button ──────────────────────────────────────────────────

class _AttendanceActionButton extends ConsumerWidget {
  const _AttendanceActionButton({
    required this.hasAttended,
    required this.isLoading,
    required this.isAttendedByMe,
    required this.attendingStaffName,
    required this.patientId,
    required this.staffId,
  });

  final bool hasAttended;
  final bool isLoading;
  final bool isAttendedByMe;
  final String attendingStaffName;
  final String patientId;
  final String staffId;

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    if (hasAttended) {
      return Container(
        padding: const EdgeInsets.symmetric(horizontal: 10, vertical: 6),
        decoration: BoxDecoration(
          color: Colors.green.withValues(alpha: 0.12),
          borderRadius: BorderRadius.circular(AppSpacing.radiusMd),
          border: Border.all(color: Colors.green.shade600),
        ),
        child: Row(
          mainAxisSize: MainAxisSize.min,
          children: [
            Icon(Icons.check_circle, size: 15, color: Colors.green.shade700),
            const SizedBox(width: 4),
            Text(
              'Attended',
              style: AppTypography.labelCaps.copyWith(
                color: Colors.green.shade800,
                fontWeight: FontWeight.bold,
                fontSize: 11,
              ),
            ),
          ],
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

// ── Empty State ───────────────────────────────────────────────────────────────

class _EmptyState extends StatelessWidget {
  const _EmptyState();

  @override
  Widget build(BuildContext context) {
    return Center(
      child: Padding(
        padding: const EdgeInsets.symmetric(vertical: AppSpacing.xl),
        child: Column(
          mainAxisSize: MainAxisSize.min,
          children: [
            Icon(
              Icons.event_available_outlined,
              size: 56,
              color: AppColors.outline.withValues(alpha: 0.5),
            ),
            const SizedBox(height: AppSpacing.md),
            Text(
              'No patients scheduled for today.',
              style: AppTypography.headlineMd
                  .copyWith(color: AppColors.onSurfaceVariant),
            ),
            const SizedBox(height: AppSpacing.xs),
            Text(
              'Patients with appointments today will appear here.\nUse the search bar above to look up any patient.',
              textAlign: TextAlign.center,
              style: AppTypography.bodyMd
                  .copyWith(color: AppColors.onSurfaceVariant),
            ),
          ],
        ),
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
