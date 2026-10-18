import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:intl/intl.dart';

import '../../../core/theme/app_colors.dart';
import '../../../core/theme/app_spacing.dart';
import '../../../core/theme/app_typography.dart';
import '../../auth/models/profile_model.dart';
import '../../auth/providers/auth_provider.dart';
import '../../staff/models/attendance_record.dart';
import '../../staff/models/leave_request.dart';
import '../../staff/models/shift_configuration.dart';
import '../../staff/providers/attendance_provider.dart';
import '../../staff/providers/leave_provider.dart';
import 'staff_leave_screen.dart';

class StaffAttendanceScreen extends ConsumerStatefulWidget {
  const StaffAttendanceScreen({super.key});

  @override
  ConsumerState<StaffAttendanceScreen> createState() =>
      _StaffAttendanceScreenState();
}

class _StaffAttendanceScreenState extends ConsumerState<StaffAttendanceScreen> {
  String _logShiftFilter = 'all'; // 'all' | 'morning' | 'afternoon'
  String? _actionInProgressShift;

  @override
  Widget build(BuildContext context) {
    final isDesktop = MediaQuery.sizeOf(context).width >= 768.0;
    final currentUser = ref.watch(currentUserProvider);
    if (currentUser == null) {
      return const Center(child: CircularProgressIndicator());
    }

    final profileAsync = ref.watch(currentProfileProvider);
    final assignedShiftAsync =
        ref.watch(staffAssignedShiftProvider(currentUser.id));
    final configsAsync = ref.watch(shiftConfigurationsProvider);
    final activeAttendanceAsync =
        ref.watch(staffActiveAttendanceProvider(currentUser.id));
    final attendanceAsync = ref.watch(attendanceProvider(currentUser.id));

    return RefreshIndicator(
      onRefresh: () async {
        ref.invalidate(currentProfileProvider);
        ref.invalidate(staffAssignedShiftProvider(currentUser.id));
        ref.invalidate(shiftConfigurationsProvider);
        ref.invalidate(staffActiveAttendanceProvider(currentUser.id));
        ref.invalidate(todayShiftAttendanceProvider);
        ref.invalidate(staffLeaveRequestsProvider(currentUser.id));
        await ref
            .read(attendanceProvider(currentUser.id).notifier)
            .fetchCurrentMonth();
      },
      child: SingleChildScrollView(
        physics: const AlwaysScrollableScrollPhysics(),
        padding: EdgeInsets.all(
            isDesktop ? AppSpacing.marginDesktop : AppSpacing.marginMobile),
        child: Column(
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            _buildHeader(isDesktop, context),
            const SizedBox(height: AppSpacing.md),

            // ── Shift Timing & Clock In/Out Section ────────────────────────
            _buildShiftAttendanceBody(
              isDesktop: isDesktop,
              staffId: currentUser.id,
              profileShift: profileAsync.valueOrNull?.assignedShift,
              assignedShiftAsync: assignedShiftAsync,
              configsAsync: configsAsync,
              activeAttendanceAsync: activeAttendanceAsync,
              profile: profileAsync.valueOrNull,
            ),
            const SizedBox(height: AppSpacing.lg),

            // ── Monthly Shift Log with Shift Badges ────────────────────────
            Row(
              mainAxisAlignment: MainAxisAlignment.spaceBetween,
              children: [
                Text('Monthly Shift Log', style: AppTypography.headlineMd),
                _buildLogShiftFilter(),
              ],
            ),
            const SizedBox(height: AppSpacing.md),
            _buildLogTable(attendanceAsync),
          ],
        ),
      ),
    );
  }

  Widget _buildHeader(bool isDesktop, BuildContext context) {
    final title = Column(
      crossAxisAlignment: CrossAxisAlignment.start,
      children: [
        Text(
          'Attendance & Shift Logs',
          style: AppTypography.displayLg.copyWith(
            color: AppColors.onBackground,
            fontSize: isDesktop ? null : 24,
          ),
        ),
        const SizedBox(height: AppSpacing.xs),
        Text(
          'Track shifts, clock-in history, and PTO requests according to your assigned shift',
          style:
              AppTypography.bodyLg.copyWith(color: AppColors.onSurfaceVariant),
        ),
      ],
    );

    final leaveButton = FilledButton.icon(
      onPressed: () {
        Navigator.of(context)
            .push(MaterialPageRoute(builder: (_) => const StaffLeaveScreen()));
      },
      icon: const Icon(Icons.event_note, size: 18),
      label: const Text('Leave Management'),
      style: FilledButton.styleFrom(
        backgroundColor: AppColors.secondary,
        foregroundColor: Colors.white,
      ),
    );

    if (isDesktop) {
      return Row(
        mainAxisAlignment: MainAxisAlignment.spaceBetween,
        children: [
          title,
          leaveButton,
        ],
      );
    } else {
      return Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          title,
          const SizedBox(height: AppSpacing.sm),
          leaveButton,
        ],
      );
    }
  }

  Widget _buildShiftAttendanceBody({
    required bool isDesktop,
    required String staffId,
    required String? profileShift,
    required AsyncValue<String?> assignedShiftAsync,
    required AsyncValue<List<ShiftConfiguration>> configsAsync,
    required AsyncValue<AttendanceRecord?> activeAttendanceAsync,
    ProfileModel? profile,
  }) {
    // Resolve assigned shift
    final effectiveShift =
        (assignedShiftAsync.valueOrNull ?? profileShift ?? 'morning')
            .toLowerCase();
    final leaveRequestsAsync = ref.watch(staffLeaveRequestsProvider(staffId));
    final leaveRequests =
        leaveRequestsAsync.valueOrNull ?? const <LeaveRequest>[];

    return configsAsync.when(
      loading: () => const Center(
        child: Padding(
          padding: EdgeInsets.all(AppSpacing.lg),
          child: CircularProgressIndicator(),
        ),
      ),
      error: (e, _) => Container(
        padding: const EdgeInsets.all(AppSpacing.md),
        decoration: BoxDecoration(
          color: AppColors.errorContainer,
          borderRadius: BorderRadius.circular(AppSpacing.radiusMd),
        ),
        child: Text('Error loading shift configuration: $e'),
      ),
      data: (configs) {
        final morningConfig = configs.firstWhere(
          (c) => c.shift.toLowerCase() == 'morning',
          orElse: () => ShiftConfiguration.defaultMorning,
        );
        final afternoonConfig = configs.firstWhere(
          (c) =>
              c.shift.toLowerCase() == 'afternoon' ||
              c.shift.toLowerCase() == 'night',
          orElse: () => ShiftConfiguration.defaultAfternoon,
        );

        final shiftsToDisplay = effectiveShift == 'both'
            ? [morningConfig, afternoonConfig]
            : [
                (effectiveShift == 'afternoon' ||
                        effectiveShift == 'evening' ||
                        effectiveShift == 'night')
                    ? afternoonConfig
                    : morningConfig
              ];

        final activeRecord = activeAttendanceAsync.valueOrNull;

        return Column(
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            if (profile != null && profile.hasScheduledShift)
              Padding(
                padding: const EdgeInsets.only(bottom: AppSpacing.sm),
                child: Container(
                  padding:
                      const EdgeInsets.symmetric(horizontal: 12, vertical: 8),
                  decoration: BoxDecoration(
                    color: AppColors.secondary.withValues(alpha: 0.1),
                    borderRadius: BorderRadius.circular(AppSpacing.radiusSm),
                    border: Border.all(
                        color: AppColors.secondary.withValues(alpha: 0.4)),
                  ),
                  child: Row(
                    children: [
                      const Icon(Icons.schedule_send_outlined,
                          size: 18, color: AppColors.secondary),
                      const SizedBox(width: 8),
                      Expanded(
                        child: Text(
                          'Upcoming Shift Change: Your duty will change to ${profile.scheduledShiftDisplayName} starting on ${DateFormat('d MMMM yyyy').format(profile.shiftEffectiveDate!)}.',
                          style: AppTypography.bodySm.copyWith(
                            color: AppColors.secondary,
                            fontWeight: FontWeight.w600,
                          ),
                        ),
                      ),
                    ],
                  ),
                ),
              ),
            if (effectiveShift == 'both')
              Padding(
                padding: const EdgeInsets.only(bottom: AppSpacing.sm),
                child: Container(
                  padding:
                      const EdgeInsets.symmetric(horizontal: 10, vertical: 6),
                  decoration: BoxDecoration(
                    color: AppColors.primaryContainer.withValues(alpha: 0.15),
                    borderRadius: BorderRadius.circular(AppSpacing.radiusSm),
                    border: Border.all(
                        color: AppColors.primary.withValues(alpha: 0.3)),
                  ),
                  child: Row(
                    mainAxisSize: MainAxisSize.min,
                    children: [
                      const Icon(Icons.all_inclusive,
                          size: 16, color: AppColors.primary),
                      const SizedBox(width: 6),
                      Text(
                        'Assigned Duty: Morning & Evening Sessions (Both)',
                        style: AppTypography.bodySm.copyWith(
                          fontWeight: FontWeight.bold,
                          color: AppColors.primary,
                        ),
                      ),
                    ],
                  ),
                ),
              ),
            for (int i = 0; i < shiftsToDisplay.length; i++) ...[
              if (i > 0) const SizedBox(height: AppSpacing.md),
              _buildShiftDutySection(
                isDesktop: isDesktop,
                staffId: staffId,
                config: shiftsToDisplay[i],
                activeRecord: activeRecord,
                leaveRequests: leaveRequests,
              ),
            ],
          ],
        );
      },
    );
  }

  Widget _buildShiftDutySection({
    required bool isDesktop,
    required String staffId,
    required ShiftConfiguration config,
    required AttendanceRecord? activeRecord,
    required List<LeaveRequest> leaveRequests,
  }) {
    final now = DateTime.now();

    // 1. Check if there is an approved leave request covering today and this shift
    final approvedLeave = leaveRequests.where((req) {
      if (req.status.toLowerCase() != 'approved') return false;
      final check = DateTime(now.year, now.month, now.day);
      final start =
          DateTime(req.startDate.year, req.startDate.month, req.startDate.day);
      final end =
          DateTime(req.endDate.year, req.endDate.month, req.endDate.day);
      if (check.isBefore(start) || check.isAfter(end)) return false;
      return req.coversShift(config.shift);
    }).firstOrNull;

    if (approvedLeave != null) {
      return _buildOnApprovedLeaveCard(config: config, leave: approvedLeave);
    }

    // 2. Check today's record for this shift (isolated per shift session)
    final todayAsync = ref.watch(
      todayShiftAttendanceProvider((
        staffId: staffId,
        shift: config.shift,
        config: config,
      )),
    );

    final todayRecord = todayAsync.valueOrNull;

    // Show Clock Out only when a valid active session exists for that staff member and shift today
    // Must have checkInTime != null, checkOutTime == null, and not be marked leave/holiday/absent
    final hasActiveOpenSession = todayRecord != null &&
        todayRecord.checkInTime != null &&
        todayRecord.checkOutTime == null &&
        todayRecord.status != 'leave' &&
        todayRecord.status != 'holiday' &&
        todayRecord.status != 'absent';

    if (hasActiveOpenSession) {
      return _buildActiveClockInCard(
        isDesktop: isDesktop,
        staffId: staffId,
        activeRecord: todayRecord,
        config: config,
      );
    }

    // If today's attendance is completed, display completion card
    if (todayRecord != null && todayRecord.checkOutTime != null) {
      return _buildShiftClockCard(
        isDesktop: isDesktop,
        staffId: staffId,
        config: config,
        todayAsync: todayAsync,
      );
    }

    final isInShift = config.isTimeWithinShift(now);
    final isEligible = config.isEligibleForCheckIn(now);

    if (!isEligible && !isInShift) {
      return _buildOutsideShiftHoursCard(
        assignedConfig: config,
        todayAsync: todayAsync,
      );
    }

    return _buildShiftClockCard(
      isDesktop: isDesktop,
      staffId: staffId,
      config: config,
      todayAsync: todayAsync,
    );
  }

  Widget _buildOnApprovedLeaveCard({
    required ShiftConfiguration config,
    required LeaveRequest leave,
  }) {
    return Container(
      width: double.infinity,
      padding: const EdgeInsets.all(AppSpacing.lg),
      decoration: BoxDecoration(
        color: AppColors.surfaceContainerLowest,
        borderRadius: BorderRadius.circular(AppSpacing.radiusLg),
        border: Border.all(color: Colors.green.withValues(alpha: 0.4)),
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
          Row(
            children: [
              Container(
                padding: const EdgeInsets.all(10),
                decoration: BoxDecoration(
                  color: Colors.green.withValues(alpha: 0.12),
                  shape: BoxShape.circle,
                ),
                child: const Icon(
                  Icons.beach_access,
                  color: Colors.green,
                  size: 24,
                ),
              ),
              const SizedBox(width: AppSpacing.md),
              Expanded(
                child: Column(
                  crossAxisAlignment: CrossAxisAlignment.start,
                  children: [
                    Text(
                      'ON APPROVED LEAVE — ${config.name.toUpperCase()}',
                      style: AppTypography.labelCaps.copyWith(
                        color: Colors.green.shade800,
                        fontWeight: FontWeight.bold,
                      ),
                    ),
                    Text(
                      config.formattedTiming,
                      style: AppTypography.headlineMd.copyWith(
                        fontSize: 16,
                        fontWeight: FontWeight.w600,
                      ),
                    ),
                  ],
                ),
              ),
            ],
          ),
          const SizedBox(height: AppSpacing.md),
          const Divider(),
          const SizedBox(height: AppSpacing.sm),
          Row(
            children: [
              const Icon(Icons.check_circle_outline,
                  color: Colors.green, size: 20),
              const SizedBox(width: AppSpacing.xs),
              Expanded(
                child: Text(
                  'Approved ${leave.dutyPeriodDisplayName} Leave: ${leave.reason.isNotEmpty ? leave.reason : "Authorized leave approved by administration."} Attendance is not required for this shift session.',
                  style: AppTypography.bodyMd
                      .copyWith(color: AppColors.onSurfaceVariant),
                ),
              ),
            ],
          ),
        ],
      ),
    );
  }

  Widget _buildOutsideShiftHoursCard({
    required ShiftConfiguration assignedConfig,
    required AsyncValue<AttendanceRecord?> todayAsync,
  }) {
    final isMorning = assignedConfig.shift == 'morning';
    final themeColor = isMorning ? AppColors.primary : AppColors.secondary;

    return Container(
      width: double.infinity,
      padding: const EdgeInsets.all(AppSpacing.lg),
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
          Row(
            children: [
              Container(
                padding: const EdgeInsets.all(10),
                decoration: BoxDecoration(
                  color: themeColor.withValues(alpha: 0.12),
                  shape: BoxShape.circle,
                ),
                child: Icon(
                  isMorning
                      ? Icons.wb_sunny_outlined
                      : Icons.nightlight_round_outlined,
                  color: themeColor,
                  size: 24,
                ),
              ),
              const SizedBox(width: AppSpacing.md),
              Expanded(
                child: Column(
                  crossAxisAlignment: CrossAxisAlignment.start,
                  children: [
                    Text(
                      'ASSIGNED: ${assignedConfig.name.toUpperCase()}',
                      style: AppTypography.labelCaps.copyWith(
                        color: themeColor,
                        fontWeight: FontWeight.bold,
                      ),
                    ),
                    Text(
                      assignedConfig.formattedTiming,
                      style: AppTypography.headlineMd
                          .copyWith(fontSize: 16, fontWeight: FontWeight.w600),
                    ),
                  ],
                ),
              ),
            ],
          ),
          const SizedBox(height: AppSpacing.md),
          const Divider(),
          const SizedBox(height: AppSpacing.sm),
          Row(
            children: [
              Icon(Icons.schedule, color: AppColors.onSurfaceVariant, size: 20),
              const SizedBox(width: AppSpacing.xs),
              Expanded(
                child: Text(
                  'Outside Shift Hours: Clock-in is only available during your assigned shift hours (${assignedConfig.formattedTiming}).',
                  style: AppTypography.bodyMd
                      .copyWith(color: AppColors.onSurfaceVariant),
                ),
              ),
            ],
          ),
          // If already completed today, show note
          todayAsync.whenData((record) {
                if (record != null && record.checkOutTime != null) {
                  return Padding(
                    padding: const EdgeInsets.only(top: AppSpacing.sm),
                    child: Text(
                      'You have already completed attendance for today with ${record.workingHours?.toStringAsFixed(1) ?? "0"} hours logged.',
                      style: AppTypography.bodySm
                          .copyWith(color: Colors.green.shade700),
                    ),
                  );
                }
                return const SizedBox.shrink();
              }).valueOrNull ??
              const SizedBox.shrink(),
        ],
      ),
    );
  }

  Widget _buildActiveClockInCard({
    required bool isDesktop,
    required String staffId,
    required AttendanceRecord activeRecord,
    required ShiftConfiguration config,
  }) {
    final isMorning = config.shift == 'morning';
    final themeColor = isMorning ? AppColors.primary : AppColors.secondary;

    final checkIn = activeRecord.checkInTime;
    final checkInStr = checkIn != null
        ? '${checkIn.hour.toString().padLeft(2, '0')}:${checkIn.minute.toString().padLeft(2, '0')}'
        : 'Active';

    final statusContent = Column(
      crossAxisAlignment: CrossAxisAlignment.start,
      children: [
        _buildShiftTimingHeader(config.name, config.formattedTiming, isMorning),
        const SizedBox(height: AppSpacing.sm),
        Row(
          children: [
            Container(
              width: 10,
              height: 10,
              decoration: const BoxDecoration(
                shape: BoxShape.circle,
                color: Colors.green,
              ),
            ),
            const SizedBox(width: 8),
            Flexible(
              child: Text(
                'CLOCKED IN — ON DUTY',
                style: AppTypography.labelCaps.copyWith(
                  color: Colors.green.shade800,
                  fontWeight: FontWeight.bold,
                ),
                overflow: TextOverflow.ellipsis,
              ),
            ),
          ],
        ),
        const SizedBox(height: 6),
        Text(
          'Shift In Progress',
          style: AppTypography.headlineMd.copyWith(
            fontSize: isDesktop ? 24 : 20,
            color: AppColors.onSurface,
          ),
        ),
        Text(
          'Checked in at $checkInStr. Tap Clock Out when completing your shift.',
          style:
              AppTypography.bodySm.copyWith(color: AppColors.onSurfaceVariant),
        ),
      ],
    );

    return Container(
      padding: const EdgeInsets.all(AppSpacing.md),
      decoration: BoxDecoration(
        color: AppColors.surfaceContainerLowest,
        borderRadius: BorderRadius.circular(AppSpacing.radiusLg),
        border: Border.all(color: themeColor.withValues(alpha: 0.4)),
        boxShadow: const [
          BoxShadow(
            color: Color(0x0A000000),
            blurRadius: 8,
            offset: Offset(0, 1),
          ),
        ],
      ),
      child: isDesktop
          ? Row(
              mainAxisAlignment: MainAxisAlignment.spaceBetween,
              children: [
                Expanded(child: statusContent),
                const SizedBox(width: AppSpacing.md),
                _buildActionButton(
                  isClockedIn: true,
                  staffId: staffId,
                  shift: config.shift,
                  config: config,
                ),
              ],
            )
          : Column(
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                statusContent,
                const SizedBox(height: AppSpacing.md),
                SizedBox(
                  width: double.infinity,
                  child: _buildActionButton(
                    isClockedIn: true,
                    staffId: staffId,
                    shift: config.shift,
                    config: config,
                  ),
                ),
              ],
            ),
    );
  }

  Widget _buildShiftClockCard({
    required bool isDesktop,
    required String staffId,
    required ShiftConfiguration config,
    required AsyncValue<AttendanceRecord?> todayAsync,
  }) {
    final isMorning = config.shift == 'morning';
    final themeColor = isMorning ? AppColors.primary : AppColors.secondary;

    return Container(
      padding: const EdgeInsets.all(AppSpacing.md),
      decoration: BoxDecoration(
        color: AppColors.surfaceContainerLowest,
        borderRadius: BorderRadius.circular(AppSpacing.radiusLg),
        border: Border.all(color: themeColor.withValues(alpha: 0.3)),
        boxShadow: const [
          BoxShadow(
            color: Color(0x0A000000),
            blurRadius: 8,
            offset: Offset(0, 1),
          ),
        ],
      ),
      child: todayAsync.when(
        data: (record) {
          final isClockedIn = record != null && record.checkOutTime == null;
          final hasCompletedShift =
              record != null && record.checkOutTime != null;
          final isLeave = record != null && record.status == 'leave';
          final isHoliday = record != null && record.status == 'holiday';

          if (isLeave || isHoliday) {
            return Center(
              child: Padding(
                padding: const EdgeInsets.all(AppSpacing.md),
                child: Text(
                  isLeave
                      ? 'YOU ARE ON LEAVE FOR THIS SHIFT'
                      : 'TODAY IS A HOLIDAY',
                  style: AppTypography.headlineMd
                      .copyWith(color: AppColors.primary),
                ),
              ),
            );
          }

          if (hasCompletedShift) {
            return Column(
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                _buildShiftTimingHeader(
                    config.name, config.formattedTiming, isMorning),
                const SizedBox(height: AppSpacing.sm),
                Container(
                  padding: const EdgeInsets.all(AppSpacing.md),
                  decoration: BoxDecoration(
                    color: Colors.green.withValues(alpha: 0.08),
                    borderRadius: BorderRadius.circular(AppSpacing.radiusMd),
                    border:
                        Border.all(color: Colors.green.withValues(alpha: 0.3)),
                  ),
                  child: Row(
                    children: [
                      Icon(Icons.check_circle,
                          color: Colors.green.shade700, size: 28),
                      const SizedBox(width: AppSpacing.md),
                      Expanded(
                        child: Column(
                          crossAxisAlignment: CrossAxisAlignment.start,
                          children: [
                            Text(
                              'SHIFT COMPLETED',
                              style: AppTypography.labelCaps.copyWith(
                                color: Colors.green.shade800,
                                fontWeight: FontWeight.bold,
                              ),
                            ),
                            Text(
                              'Logged ${record.workingHours?.toStringAsFixed(1) ?? "0"} hours for ${config.name}.',
                              style: AppTypography.bodyMd,
                            ),
                          ],
                        ),
                      ),
                    ],
                  ),
                ),
              ],
            );
          }

          final statusContent = Column(
            crossAxisAlignment: CrossAxisAlignment.start,
            children: [
              _buildShiftTimingHeader(
                  config.name, config.formattedTiming, isMorning),
              const SizedBox(height: AppSpacing.sm),
              Row(
                children: [
                  Container(
                    width: 10,
                    height: 10,
                    decoration: BoxDecoration(
                      shape: BoxShape.circle,
                      color: isClockedIn ? Colors.green : AppColors.error,
                    ),
                  ),
                  const SizedBox(width: 8),
                  Flexible(
                    child: Text(
                      isClockedIn
                          ? 'CLOCKED IN — ON DUTY'
                          : 'CLOCKED OUT — OFF DUTY',
                      style: AppTypography.labelCaps.copyWith(
                        color: isClockedIn
                            ? Colors.green.shade800
                            : AppColors.error,
                        fontWeight: FontWeight.bold,
                      ),
                      overflow: TextOverflow.ellipsis,
                    ),
                  ),
                ],
              ),
              const SizedBox(height: 6),
              Text(
                isClockedIn ? 'Shift In Progress' : 'Ready to Start Shift',
                style: AppTypography.headlineMd.copyWith(
                  fontSize: isDesktop ? 24 : 20,
                  color: AppColors.onSurface,
                ),
              ),
              Text(
                isClockedIn
                    ? 'Check-in: ${record.checkInTime?.hour.toString().padLeft(2, '0')}:${record.checkInTime?.minute.toString().padLeft(2, '0')}'
                    : 'Tap Clock In below to record your ${config.name} attendance.',
                style: AppTypography.bodySm
                    .copyWith(color: AppColors.onSurfaceVariant),
              ),
            ],
          );

          if (isDesktop) {
            return Row(
              mainAxisAlignment: MainAxisAlignment.spaceBetween,
              children: [
                Expanded(child: statusContent),
                const SizedBox(width: AppSpacing.md),
                _buildActionButton(
                  isClockedIn: isClockedIn,
                  staffId: staffId,
                  shift: config.shift,
                  config: config,
                ),
              ],
            );
          } else {
            return Column(
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                statusContent,
                const SizedBox(height: AppSpacing.md),
                SizedBox(
                  width: double.infinity,
                  child: _buildActionButton(
                    isClockedIn: isClockedIn,
                    staffId: staffId,
                    shift: config.shift,
                    config: config,
                  ),
                ),
              ],
            );
          }
        },
        loading: () => const Center(
          child: Padding(
            padding: EdgeInsets.all(AppSpacing.md),
            child: CircularProgressIndicator(),
          ),
        ),
        error: (e, _) => Center(child: Text('Error loading status: $e')),
      ),
    );
  }

  Widget _buildShiftTimingHeader(
      String shiftTitle, String shiftTiming, bool isMorning) {
    return Container(
      padding: const EdgeInsets.symmetric(horizontal: 10, vertical: 6),
      decoration: BoxDecoration(
        color: isMorning
            ? AppColors.primaryContainer.withValues(alpha: 0.12)
            : AppColors.secondaryContainer.withValues(alpha: 0.2),
        borderRadius: BorderRadius.circular(AppSpacing.radiusSm),
      ),
      child: Row(
        mainAxisSize: MainAxisSize.min,
        children: [
          Icon(
            isMorning
                ? Icons.wb_sunny_outlined
                : Icons.nightlight_round_outlined,
            size: 16,
            color: isMorning ? AppColors.primary : AppColors.secondary,
          ),
          const SizedBox(width: 6),
          Text(
            '$shiftTitle · Assigned Timing: $shiftTiming',
            style: AppTypography.bodySm.copyWith(
              fontWeight: FontWeight.w600,
              color: isMorning ? AppColors.primary : AppColors.secondary,
            ),
          ),
        ],
      ),
    );
  }

  Widget _buildActionButton({
    required bool isClockedIn,
    required String staffId,
    required String shift,
    required ShiftConfiguration config,
  }) {
    final isLoading = _actionInProgressShift == shift;

    return FilledButton.icon(
      onPressed: isLoading
          ? null
          : () async {
              setState(() => _actionInProgressShift = shift);
              try {
                if (isClockedIn) {
                  await ref
                      .read(attendanceProvider(staffId).notifier)
                      .checkOut(shift: shift, config: config);
                } else {
                  await ref
                      .read(attendanceProvider(staffId).notifier)
                      .checkIn(shift: shift, config: config);
                }
                ref.invalidate(todayShiftAttendanceProvider);
                ref.invalidate(staffActiveAttendanceProvider(staffId));
                ref.invalidate(attendanceProvider(staffId));
                await ref
                    .read(attendanceProvider(staffId).notifier)
                    .fetchCurrentMonth();
              } catch (e) {
                if (mounted) {
                  ScaffoldMessenger.of(context).showSnackBar(
                    SnackBar(
                      content: Text(
                          'Error: ${e.toString().replaceAll("Exception: ", "")}'),
                      backgroundColor: AppColors.error,
                    ),
                  );
                }
              } finally {
                if (mounted) {
                  setState(() => _actionInProgressShift = null);
                }
              }
            },
      icon: isLoading
          ? const SizedBox(
              width: 18,
              height: 18,
              child: CircularProgressIndicator(
                strokeWidth: 2,
                color: Colors.white,
              ),
            )
          : Icon(isClockedIn ? Icons.logout : Icons.login),
      label: Text(
        isLoading
            ? (isClockedIn ? 'Clocking Out...' : 'Clocking In...')
            : (isClockedIn
                ? 'Clock Out (${config.name})'
                : 'Clock In (${config.name})'),
      ),
      style: FilledButton.styleFrom(
        backgroundColor: isClockedIn
            ? AppColors.error
            : (config.shift == 'night'
                ? AppColors.secondary
                : AppColors.primary),
        foregroundColor: Colors.white,
        padding: const EdgeInsets.symmetric(
            horizontal: AppSpacing.lg, vertical: AppSpacing.md),
      ),
    );
  }

  Widget _buildLogShiftFilter() {
    return DropdownButton<String>(
      value: _logShiftFilter,
      items: const [
        DropdownMenuItem(value: 'all', child: Text('All Shifts')),
        DropdownMenuItem(value: 'morning', child: Text('Morning Shift')),
        DropdownMenuItem(value: 'afternoon', child: Text('Evening Shift')),
      ],
      onChanged: (val) {
        if (val != null) {
          setState(() => _logShiftFilter = val);
        }
      },
    );
  }

  Widget _buildLogTable(AsyncValue<List<AttendanceRecord>> attendanceAsync) {
    return attendanceAsync.when(
      data: (records) {
        final filteredRecords = _logShiftFilter == 'all'
            ? records
            : records.where((r) {
                final s = r.shift.toLowerCase();
                if (_logShiftFilter == 'afternoon') {
                  return s == 'afternoon' || s == 'evening' || s == 'night';
                }
                return s == _logShiftFilter;
              }).toList();

        if (filteredRecords.isEmpty) {
          return Center(
            child: Padding(
              padding: const EdgeInsets.all(AppSpacing.xl),
              child: Text(
                'No attendance logs recorded for this period.',
                style: AppTypography.bodyLg
                    .copyWith(color: AppColors.onSurfaceVariant),
              ),
            ),
          );
        }

        return Container(
          decoration: BoxDecoration(
            color: AppColors.surfaceContainerLowest,
            borderRadius: BorderRadius.circular(AppSpacing.radiusLg),
            border: Border.all(color: AppColors.outlineVariant),
          ),
          child: ListView.separated(
            shrinkWrap: true,
            physics: const NeverScrollableScrollPhysics(),
            itemCount: filteredRecords.length,
            separatorBuilder: (_, __) => const Divider(height: 1),
            itemBuilder: (context, index) {
              final r = filteredRecords[index];
              final isAfternoon = r.isAfternoonShift || r.isNightShift;

              return ListTile(
                leading: CircleAvatar(
                  backgroundColor: isAfternoon
                      ? AppColors.secondary.withValues(alpha: 0.15)
                      : AppColors.primary.withValues(alpha: 0.15),
                  child: Icon(
                    isAfternoon ? Icons.nightlight_round : Icons.wb_sunny,
                    color:
                        isAfternoon ? AppColors.secondary : AppColors.primary,
                    size: 18,
                  ),
                ),
                title: Row(
                  children: [
                    Text(
                      '${r.date.day.toString().padLeft(2, '0')}/${r.date.month.toString().padLeft(2, '0')}/${r.date.year}',
                      style: AppTypography.bodyMd
                          .copyWith(fontWeight: FontWeight.w600),
                    ),
                    const SizedBox(width: AppSpacing.sm),
                    Container(
                      padding: const EdgeInsets.symmetric(
                          horizontal: 6, vertical: 2),
                      decoration: BoxDecoration(
                        color: isAfternoon
                            ? AppColors.secondary.withValues(alpha: 0.1)
                            : AppColors.primary.withValues(alpha: 0.1),
                        borderRadius: BorderRadius.circular(4),
                        border: Border.all(
                          color: isAfternoon
                              ? AppColors.secondary.withValues(alpha: 0.4)
                              : AppColors.primary.withValues(alpha: 0.4),
                        ),
                      ),
                      child: Text(
                        r.shiftDisplayName,
                        style: AppTypography.labelCaps.copyWith(
                          fontSize: 10,
                          color: isAfternoon
                              ? AppColors.secondary
                              : AppColors.primary,
                        ),
                      ),
                    ),
                  ],
                ),
                subtitle: Text(
                  'In: ${r.checkInTime != null ? "${r.checkInTime!.hour.toString().padLeft(2, '0')}:${r.checkInTime!.minute.toString().padLeft(2, '0')}" : "—"} · '
                  'Out: ${r.checkOutTime != null ? "${r.checkOutTime!.hour.toString().padLeft(2, '0')}:${r.checkOutTime!.minute.toString().padLeft(2, '0')}" : "—"} · '
                  'Hours: ${r.workingHours != null ? r.workingHours!.toStringAsFixed(1) : "—"}',
                  style: AppTypography.bodySm,
                ),
                trailing: Chip(
                  label: Text(r.statusLabel),
                  backgroundColor: r.status.toLowerCase() == 'present'
                      ? Colors.green.withValues(alpha: 0.15)
                      : r.status.toLowerCase() == 'late'
                          ? Colors.orange.withValues(alpha: 0.15)
                          : AppColors.errorContainer,
                  labelStyle: TextStyle(
                    color: r.status.toLowerCase() == 'present'
                        ? Colors.green.shade800
                        : r.status.toLowerCase() == 'late'
                            ? Colors.orange.shade800
                            : AppColors.error,
                    fontSize: 12,
                    fontWeight: FontWeight.bold,
                  ),
                ),
              );
            },
          ),
        );
      },
      loading: () => const Center(
        child: Padding(
          padding: EdgeInsets.all(AppSpacing.xl),
          child: CircularProgressIndicator(),
        ),
      ),
      error: (e, _) => Center(child: Text('Error loading shift logs: $e')),
    );
  }
}
