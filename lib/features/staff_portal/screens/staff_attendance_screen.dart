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

              profileShift: profileAsync.valueOrNull?.activeShift,

              assignedShiftAsync: assignedShiftAsync,

              configsAsync: configsAsync,

              activeAttendanceAsync: activeAttendanceAsync,

              profile: profileAsync.valueOrNull,

            ),

            const SizedBox(height: AppSpacing.lg),



            // ── Monthly Shift Log with Shift Badges ────────────────────────

            Wrap(

              alignment: WrapAlignment.spaceBetween,

              crossAxisAlignment: WrapCrossAlignment.center,

              spacing: AppSpacing.sm,

              runSpacing: AppSpacing.xs,

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

          Expanded(child: title),

          const SizedBox(width: AppSpacing.md),

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

    // Resolve assigned shift for today according to schedule and effective date

    final effectiveShift = (assignedShiftAsync.valueOrNull ??

            profile?.getShiftForDate(DateTime.now()) ??

            profileShift ??

            'morning')

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
          (c) => c.shift.toLowerCase().contains('morning'),
          orElse: () => ShiftConfiguration.defaultMorning,
        );
        final afternoonConfig = configs.firstWhere(
          (c) =>
              c.shift.toLowerCase().contains('afternoon') ||
              c.shift.toLowerCase().contains('evening') ||
              c.shift.toLowerCase().contains('night'),
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

            if (profile != null && profile.isUpcomingShiftChange())

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

              _buildCombinedBothShiftsDutyCard(

                isDesktop: isDesktop,

                staffId: staffId,

                morningConfig: morningConfig,

                afternoonConfig: afternoonConfig,

                leaveRequests: leaveRequests,

              )

            else

              _buildShiftDutySection(

                isDesktop: isDesktop,

                staffId: staffId,

                config: shiftsToDisplay.first,

                activeRecord: activeRecord,

                leaveRequests: leaveRequests,

              ),

          ],

        );

      },

    );

  }





  Widget _buildCombinedBothShiftsDutyCard({

    required bool isDesktop,

    required String staffId,

    required ShiftConfiguration morningConfig,

    required ShiftConfiguration afternoonConfig,

    required List<LeaveRequest> leaveRequests,

  }) {

    final now = DateTime.now();



    // 1. Check approved leave for both morning and afternoon shifts

    final morningLeave = leaveRequests.where((req) {

      if (req.status.toLowerCase() != 'approved') return false;

      final check = DateTime(now.year, now.month, now.day);

      final start = DateTime(req.startDate.year, req.startDate.month, req.startDate.day);

      final end = DateTime(req.endDate.year, req.endDate.month, req.endDate.day);

      if (check.isBefore(start) || check.isAfter(end)) return false;

      return req.coversShift(morningConfig.shift);

    }).firstOrNull;



    final eveningLeave = leaveRequests.where((req) {

      if (req.status.toLowerCase() != 'approved') return false;

      final check = DateTime(now.year, now.month, now.day);

      final start = DateTime(req.startDate.year, req.startDate.month, req.startDate.day);

      final end = DateTime(req.endDate.year, req.endDate.month, req.endDate.day);

      if (check.isBefore(start) || check.isAfter(end)) return false;

      return req.coversShift(afternoonConfig.shift);

    }).firstOrNull;



    // 2. Watch today's attendance for morning and evening

    final todayMorningAsync = ref.watch(

      todayShiftAttendanceProvider((

        staffId: staffId,

        shift: morningConfig.shift,

        config: morningConfig,

      )),

    );

    final todayEveningAsync = ref.watch(

      todayShiftAttendanceProvider((

        staffId: staffId,

        shift: afternoonConfig.shift,

        config: afternoonConfig,

      )),

    );



    final morningRecord = todayMorningAsync.valueOrNull;

    final eveningRecord = todayEveningAsync.valueOrNull;



    final isMorningActive = morningRecord != null &&

        morningRecord.checkInTime != null &&

        morningRecord.checkOutTime == null &&

        morningRecord.status != 'leave' &&

        morningRecord.status != 'holiday' &&

        morningRecord.status != 'absent';



    final isEveningActive = eveningRecord != null &&

        eveningRecord.checkInTime != null &&

        eveningRecord.checkOutTime == null &&

        eveningRecord.status != 'leave' &&

        eveningRecord.status != 'holiday' &&

        eveningRecord.status != 'absent';



    final isMorningCompleted = morningRecord != null && morningRecord.checkOutTime != null;

    final isEveningCompleted = eveningRecord != null && eveningRecord.checkOutTime != null;



    // Calculate working hours strictly excluding break time

    double morningHours = 0.0;

    if (morningRecord != null) {

      if (morningRecord.workingHours != null && morningRecord.workingHours! > 0) {

        morningHours = morningRecord.workingHours!;

      } else if (morningRecord.checkInTime != null) {

        final effectiveEnd = morningRecord.checkOutTime ??

            (morningConfig.isTimePastShiftEnd(now)

                ? morningConfig.getShiftEndDateTime(morningRecord.checkInTime!.toLocal())

                : now);

        morningHours = (effectiveEnd.difference(morningRecord.checkInTime!.toLocal()).inMinutes / 60.0).clamp(0.0, 24.0);

      }

    }



    double eveningHours = 0.0;

    if (eveningRecord != null) {

      if (eveningRecord.workingHours != null && eveningRecord.workingHours! > 0) {

        eveningHours = eveningRecord.workingHours!;

      } else if (eveningRecord.checkInTime != null) {

        final effectiveEnd = eveningRecord.checkOutTime ??

            (afternoonConfig.isTimePastShiftEnd(now)

                ? afternoonConfig.getShiftEndDateTime(eveningRecord.checkInTime!.toLocal())

                : now);

        eveningHours = (effectiveEnd.difference(eveningRecord.checkInTime!.toLocal()).inMinutes / 60.0).clamp(0.0, 24.0);

      }

    }



    final totalWorkingHours = morningHours + eveningHours;



    final isMorningEligible = morningConfig.isEligibleForCheckIn(now);

    final isMorningInShift = morningConfig.isTimeWithinShift(now);



    final isEveningEligible = afternoonConfig.isEligibleForCheckIn(now);

    final isEveningInShift = afternoonConfig.isTimeWithinShift(now);



    final isPastMorningEnd = morningConfig.isTimePastShiftEnd(now);

    final isBeforeEveningShift = !isEveningInShift && !isEveningEligible && !afternoonConfig.isTimePastShiftEnd(now);

    final isCurrentlyOnBreak = isPastMorningEnd && isBeforeEveningShift;



    // Determine action button

    Widget? actionButton;

    if (isMorningActive) {

      actionButton = _buildActionButton(

        isClockedIn: true,

        staffId: staffId,

        shift: morningConfig.shift,

        config: morningConfig,

      );

    } else if (isEveningActive) {

      actionButton = _buildActionButton(

        isClockedIn: true,

        staffId: staffId,

        shift: afternoonConfig.shift,

        config: afternoonConfig,

      );

    } else if (!isMorningCompleted && morningLeave == null && (isMorningEligible || isMorningInShift)) {

      actionButton = _buildActionButton(

        isClockedIn: false,

        staffId: staffId,

        shift: morningConfig.shift,

        config: morningConfig,

      );

    } else if (!isEveningCompleted && eveningLeave == null && (isEveningEligible || isEveningInShift)) {

      actionButton = _buildActionButton(

        isClockedIn: false,

        staffId: staffId,

        shift: afternoonConfig.shift,

        config: afternoonConfig,

      );

    }



    return Container(

      width: double.infinity,

      padding: const EdgeInsets.all(AppSpacing.lg),

      decoration: BoxDecoration(

        color: AppColors.surfaceContainerLowest,

        borderRadius: BorderRadius.circular(AppSpacing.radiusLg),

        border: Border.all(

          color: (isMorningActive || isEveningActive)

              ? Colors.green.withValues(alpha: 0.5)

              : AppColors.primary.withValues(alpha: 0.3),

        ),

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

          // Header: Both Shifts & Timings

          Row(

            crossAxisAlignment: CrossAxisAlignment.start,

            children: [

              Container(

                padding: const EdgeInsets.all(10),

                decoration: BoxDecoration(

                  color: AppColors.primary.withValues(alpha: 0.12),

                  shape: BoxShape.circle,

                ),

                child: const Icon(

                  Icons.all_inclusive,

                  color: AppColors.primary,

                  size: 24,

                ),

              ),

              const SizedBox(width: AppSpacing.md),

              Expanded(

                child: Column(

                  crossAxisAlignment: CrossAxisAlignment.start,

                  children: [

                    Wrap(
                      alignment: WrapAlignment.spaceBetween,
                      crossAxisAlignment: WrapCrossAlignment.center,
                      spacing: AppSpacing.xs,
                      runSpacing: 4,
                      children: [
                        Text(
                          'BOTH SHIFTS',
                          style: AppTypography.labelCaps.copyWith(
                            color: AppColors.primary,
                            fontWeight: FontWeight.bold,
                            letterSpacing: 1.1,
                          ),
                        ),
                        if (totalWorkingHours > 0)
                          Container(
                            padding: const EdgeInsets.symmetric(horizontal: 8, vertical: 2),
                            decoration: BoxDecoration(
                              color: Colors.green.withValues(alpha: 0.15),
                              borderRadius: BorderRadius.circular(4),
                            ),
                            child: Text(
                              'Total: ${totalWorkingHours.toStringAsFixed(1)} hrs',
                              style: AppTypography.dataMono.copyWith(
                                color: Colors.green.shade800,
                                fontWeight: FontWeight.bold,
                                fontSize: 12,
                              ),
                            ),
                          ),
                      ],
                    ),
                    const SizedBox(height: 2),
                    Text(
                      '${morningConfig.formattedTiming} · ${afternoonConfig.formattedTiming}',
                      style: AppTypography.headlineMd.copyWith(
                        fontSize: 15,
                        fontWeight: FontWeight.w700,
                        color: AppColors.onSurface,
                      ),
                      softWrap: true,
                    ),
                  ],
                ),
              ),
            ],
          ),
          const SizedBox(height: AppSpacing.md),

          const Divider(height: 1),

          const SizedBox(height: AppSpacing.md),



          // Session 1: Morning Session

          _buildSessionRow(

            title: 'Morning Session',

            timing: morningConfig.formattedTiming,

            icon: Icons.wb_sunny_outlined,

            iconColor: AppColors.primary,

            isActive: isMorningActive,

            isCompleted: isMorningCompleted,

            leave: morningLeave,

            record: morningRecord,

            hours: morningHours,

            isNextOrCurrent: !isMorningCompleted && morningLeave == null && (isMorningEligible || isMorningInShift),

          ),



          const SizedBox(height: AppSpacing.sm),



          // Inter-Shift Break Indicator

          Container(

            padding: const EdgeInsets.symmetric(horizontal: 12, vertical: 8),

            decoration: BoxDecoration(

              color: isCurrentlyOnBreak

                  ? Colors.amber.withValues(alpha: 0.15)

                  : AppColors.surfaceContainerLow,

              borderRadius: BorderRadius.circular(AppSpacing.radiusSm),

              border: Border.all(

                color: isCurrentlyOnBreak

                    ? Colors.amber.shade700.withValues(alpha: 0.5)

                    : AppColors.outlineVariant,

              ),

            ),

            child: Row(

              children: [

                Icon(

                  Icons.free_breakfast_outlined,

                  size: 16,

                  color: isCurrentlyOnBreak ? Colors.amber.shade900 : AppColors.onSurfaceVariant,

                ),

                const SizedBox(width: 8),

                Expanded(

                  child: Text(

                    'Inter-Shift Break: ${morningConfig.endTime} – ${afternoonConfig.startTime} · No duty active (break excluded from working hours)',

                    style: AppTypography.bodySm.copyWith(

                      color: isCurrentlyOnBreak ? Colors.amber.shade900 : AppColors.onSurfaceVariant,

                      fontWeight: isCurrentlyOnBreak ? FontWeight.bold : FontWeight.normal,

                    ),

                  ),

                ),

              ],

            ),

          ),



          const SizedBox(height: AppSpacing.sm),



          // Session 2: Evening Session

          _buildSessionRow(

            title: 'Evening Session',

            timing: afternoonConfig.formattedTiming,

            icon: Icons.nightlight_round_outlined,

            iconColor: AppColors.secondary,

            isActive: isEveningActive,

            isCompleted: isEveningCompleted,

            leave: eveningLeave,

            record: eveningRecord,

            hours: eveningHours,

            isNextOrCurrent: !isEveningCompleted && eveningLeave == null && (isEveningEligible || isEveningInShift),

          ),



          // Action button / status message

          if (actionButton != null) ...[

            const SizedBox(height: AppSpacing.md),

            if (isDesktop)

              Row(

                mainAxisAlignment: MainAxisAlignment.end,

                children: [actionButton],

              )

            else

              SizedBox(

                width: double.infinity,

                child: actionButton,

              ),

          ] else if (isCurrentlyOnBreak) ...[

            const SizedBox(height: AppSpacing.md),

            Text(

              'Morning session completed. Break in progress until evening session starts at ${afternoonConfig.formattedTiming}.',

              style: AppTypography.bodySm.copyWith(

                color: Colors.amber.shade900,

                fontStyle: FontStyle.italic,

              ),

            ),

          ] else if (isMorningCompleted && isEveningCompleted) ...[

            const SizedBox(height: AppSpacing.md),

            Text(

              'Both daily duty sessions are completed for today. Total ${totalWorkingHours.toStringAsFixed(1)} hours logged.',

              style: AppTypography.bodySm.copyWith(

                color: Colors.green.shade800,

                fontWeight: FontWeight.bold,

              ),

            ),

          ] else if (!isMorningInShift && !isMorningEligible && !isEveningInShift && !isEveningEligible) ...[

            const SizedBox(height: AppSpacing.md),

            Text(

              'Outside Shift Hours: Clock-in is only available during assigned shift hours (${morningConfig.formattedTiming} · ${afternoonConfig.formattedTiming}).',

              style: AppTypography.bodySm.copyWith(

                color: AppColors.onSurfaceVariant,

              ),

            ),

          ],

        ],

      ),

    );

  }



  Widget _buildSessionRow({

    required String title,

    required String timing,

    required IconData icon,

    required Color iconColor,

    required bool isActive,

    required bool isCompleted,

    required LeaveRequest? leave,

    required AttendanceRecord? record,

    required double hours,

    required bool isNextOrCurrent,

  }) {

    String statusText;

    Color statusColor;



    if (leave != null) {

      statusText = 'On Approved Leave';

      statusColor = Colors.green.shade800;

    } else if (isActive) {

      final checkIn = record?.checkInTime;

      final checkInStr = checkIn != null ? DateFormat('hh:mm a').format(checkIn.toLocal()) : '';

      statusText = 'On Duty · Clocked in at $checkInStr';

      statusColor = Colors.green.shade800;

    } else if (isCompleted) {

      statusText = 'Completed · ${hours.toStringAsFixed(1)} hrs logged';

      statusColor = Colors.green.shade800;

    } else if (isNextOrCurrent) {

      statusText = 'Ready to Clock In';

      statusColor = iconColor;

    } else {

      statusText = 'Upcoming';

      statusColor = AppColors.onSurfaceVariant;

    }



    return Container(

      padding: const EdgeInsets.symmetric(horizontal: 12, vertical: 8),

      decoration: BoxDecoration(

        color: isActive

            ? Colors.green.withValues(alpha: 0.1)

            : AppColors.surfaceContainerLowest,

        borderRadius: BorderRadius.circular(AppSpacing.radiusSm),

        border: Border.all(

          color: isActive

              ? Colors.green.withValues(alpha: 0.4)

              : AppColors.outlineVariant,

        ),

      ),

      child: Row(

        children: [

          Icon(icon, size: 18, color: iconColor),

          const SizedBox(width: 8),

          Expanded(

            child: Column(

              crossAxisAlignment: CrossAxisAlignment.start,

              children: [

                Text(

                  '$title ($timing)',

                  style: AppTypography.bodySm.copyWith(

                    fontWeight: FontWeight.bold,

                  ),

                ),

                Text(

                  statusText,

                  style: AppTypography.bodySm.copyWith(

                    color: statusColor,

                    fontSize: 12,

                    fontWeight: isActive ? FontWeight.bold : FontWeight.normal,

                  ),

                ),

              ],

            ),

          ),

          if (isActive)

            Container(

              width: 10,

              height: 10,

              decoration: const BoxDecoration(

                shape: BoxShape.circle,

                color: Colors.green,

              ),

            )

          else if (isCompleted)

            const Icon(Icons.check_circle, size: 16, color: Colors.green),

        ],

      ),

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

        ? DateFormat('hh:mm a').format(checkIn)

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

                              'Logged ${record.formattedWorkingDuration} for ${config.name} (${record.formattedCheckInTime} – ${record.formattedCheckOutTime}).',

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

      child: Wrap(

        crossAxisAlignment: WrapCrossAlignment.center,

        spacing: 6,

        runSpacing: 2,

        children: [

          Icon(

            isMorning

                ? Icons.wb_sunny_outlined

                : Icons.nightlight_round_outlined,

            size: 16,

            color: isMorning ? AppColors.primary : AppColors.secondary,

          ),

          Text(

            'Assigned Duty: $shiftTitle',

            style: AppTypography.bodySm.copyWith(

              fontWeight: FontWeight.w700,

              color: isMorning ? AppColors.primary : AppColors.secondary,

            ),

          ),

          Text(

            '· $shiftTiming',

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

            : (isClockedIn ? 'Clock Out' : 'Clock In'),

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



        final dailySummaries = filteredRecords.groupIntoDailySummaries();



        return Container(

          decoration: BoxDecoration(

            color: AppColors.surfaceContainerLowest,

            borderRadius: BorderRadius.circular(AppSpacing.radiusLg),

            border: Border.all(color: AppColors.outlineVariant),

          ),

          child: ListView.separated(

            shrinkWrap: true,

            physics: const NeverScrollableScrollPhysics(),

            itemCount: dailySummaries.length,

            separatorBuilder: (_, __) => const Divider(height: 1),

            itemBuilder: (context, index) {

              final daySummary = dailySummaries[index];

              return _buildDailyAttendanceTile(daySummary);

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



  Widget _buildDailyAttendanceTile(DailyAttendanceSummary summary) {

    final hasMultiple = summary.hasMultipleSessions;

    final isAfternoon =

        summary.sessions.any((s) => s.isAfternoonShift || s.isNightShift);

    final themeColor = hasMultiple

        ? AppColors.primary

        : isAfternoon

            ? AppColors.secondary

            : AppColors.primary;



    return Padding(

      padding: const EdgeInsets.symmetric(horizontal: 14, vertical: 12),

      child: Column(

        crossAxisAlignment: CrossAxisAlignment.start,

        children: [

          // Header row: Date, Shift Badge, Status Badge (Responsive)

          Wrap(

            alignment: WrapAlignment.spaceBetween,

            crossAxisAlignment: WrapCrossAlignment.center,

            spacing: 8,

            runSpacing: 4,

            children: [

              Container(

                width: 28,

                height: 28,

                decoration: BoxDecoration(

                  shape: BoxShape.circle,

                  color: themeColor.withValues(alpha: 0.12),

                ),

                child: Icon(

                  hasMultiple

                      ? Icons.all_inclusive

                      : isAfternoon

                          ? Icons.nightlight_round

                          : Icons.wb_sunny,

                  color: themeColor,

                  size: 15,

                ),

              ),

              Text(

                '${summary.date.day.toString().padLeft(2, '0')}/${summary.date.month.toString().padLeft(2, '0')}/${summary.date.year}',

                style: AppTypography.bodyMd.copyWith(

                  fontWeight: FontWeight.w700,

                  color: AppColors.onSurface,

                ),

              ),

              Container(

                padding:

                    const EdgeInsets.symmetric(horizontal: 6, vertical: 2),

                decoration: BoxDecoration(

                  color: themeColor.withValues(alpha: 0.1),

                  borderRadius: BorderRadius.circular(4),

                  border: Border.all(

                    color: themeColor.withValues(alpha: 0.35),

                  ),

                ),

                child: Text(

                  summary.shiftDisplayName,

                  style: AppTypography.labelCaps.copyWith(

                    fontSize: 10,

                    fontWeight: FontWeight.w600,

                    color: themeColor,

                  ),

                ),

              ),

              _buildCompactStatusBadge(summary.statusLabel, summary.dailyStatus),

            ],

          ),

          const SizedBox(height: 8),



          // Details content

          if (hasMultiple) ...[

            Container(

              padding: const EdgeInsets.symmetric(horizontal: 10, vertical: 5),

              decoration: BoxDecoration(

                color: AppColors.surfaceContainerLow,

                borderRadius: BorderRadius.circular(AppSpacing.radiusSm),

              ),

              child: Wrap(

                alignment: WrapAlignment.spaceBetween,

                crossAxisAlignment: WrapCrossAlignment.center,

                spacing: 6,

                runSpacing: 4,

                children: [

                  const Icon(Icons.timer_outlined,

                      size: 14, color: AppColors.primary),

                  Text(

                    'Total Duration: ',

                    style: AppTypography.bodySm.copyWith(

                      fontWeight: FontWeight.w600,

                      color: AppColors.onSurfaceVariant,

                    ),

                  ),

                  Text(

                    summary.formattedTotalDuration,

                    style: AppTypography.bodySm.copyWith(

                      fontWeight: FontWeight.bold,

                      color: AppColors.primary,

                    ),

                  ),

                  Text(

                    '(Excl. Break)',

                    style: AppTypography.bodySm.copyWith(

                      fontSize: 11,

                      color: AppColors.onSurfaceVariant,

                      fontStyle: FontStyle.italic,

                    ),

                  ),

                ],

              ),

            ),

            const SizedBox(height: 6),

            for (final session in summary.sessions) ...[

              Padding(

                padding: const EdgeInsets.only(left: 4, top: 4),

                child: Wrap(

                  spacing: 6,

                  runSpacing: 2,

                  crossAxisAlignment: WrapCrossAlignment.center,

                  children: [

                    Row(

                      mainAxisSize: MainAxisSize.min,

                      children: [

                        Icon(

                          session.isMorningShift

                              ? Icons.wb_sunny_outlined

                              : Icons.nightlight_round_outlined,

                          size: 13,

                          color: session.isMorningShift

                              ? AppColors.primary

                              : AppColors.secondary,

                        ),

                        const SizedBox(width: 4),

                        Text(

                          '${session.shiftDisplayName}: ',

                          style: AppTypography.bodySm.copyWith(

                            fontWeight: FontWeight.w600,

                            fontSize: 12,

                          ),

                        ),

                      ],

                    ),

                    Text(

                      'In: ${session.formattedCheckInTime} · Out: ${session.formattedCheckOutTime} (${session.formattedWorkingDuration})',

                      style: AppTypography.bodySm.copyWith(

                        fontSize: 12,

                        color: AppColors.onSurfaceVariant,

                      ),

                    ),

                  ],

                ),

              ),

            ],

          ] else ...[

            Builder(

              builder: (context) {

                final session = summary.sessions.first;

                return Wrap(

                  spacing: 12,

                  runSpacing: 4,

                  children: [

                    Text(

                      'In: ${session.formattedCheckInTime}',

                      style: AppTypography.bodySm.copyWith(

                        color: AppColors.onSurfaceVariant,

                      ),

                    ),

                    Text(

                      'Out: ${session.formattedCheckOutTime}',

                      style: AppTypography.bodySm.copyWith(

                        color: AppColors.onSurfaceVariant,

                      ),

                    ),

                    Text(

                      'Duration: ${session.formattedWorkingDuration}',

                      style: AppTypography.bodySm.copyWith(

                        fontWeight: FontWeight.w600,

                        color: AppColors.primary,

                      ),

                    ),

                  ],

                );

              },

            ),

          ],

        ],

      ),

    );

  }



  Widget _buildCompactStatusBadge(String label, String status) {

    Color bg;

    Color fg;

    switch (status.toLowerCase()) {

      case 'present':

        bg = Colors.green.withValues(alpha: 0.15);

        fg = Colors.green.shade800;

        break;

      case 'late':

        bg = Colors.orange.withValues(alpha: 0.15);

        fg = Colors.orange.shade800;

        break;

      case 'leave':

        bg = Colors.blue.withValues(alpha: 0.15);

        fg = Colors.blue.shade800;

        break;

      case 'holiday':

        bg = Colors.purple.withValues(alpha: 0.15);

        fg = Colors.purple.shade800;

        break;

      default:

        bg = AppColors.errorContainer;

        fg = AppColors.error;

    }



    return Container(

      padding: const EdgeInsets.symmetric(horizontal: 8, vertical: 3),

      decoration: BoxDecoration(

        color: bg,

        borderRadius: BorderRadius.circular(12),

      ),

      child: Text(

        label,

        style: TextStyle(

          color: fg,

          fontSize: 11,

          fontWeight: FontWeight.bold,

        ),

      ),

    );

  }
}
