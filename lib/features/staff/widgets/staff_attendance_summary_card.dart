import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';

import '../../../core/theme/app_colors.dart';
import '../../../core/theme/app_spacing.dart';
import '../../../core/theme/app_typography.dart';
import '../../admin/providers/users_provider.dart';
import '../models/shift_configuration.dart';
import '../providers/attendance_provider.dart';

class StaffAttendanceSummaryCard extends ConsumerWidget {
  const StaffAttendanceSummaryCard({super.key, this.targetDate});

  final DateTime? targetDate;

  static const _secondaryFixed = Color(0xFFFFD8EB);

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    final today = targetDate ?? DateTime.now();
    final todayDate = DateTime(today.year, today.month, today.day);

    final usersState = ref.watch(usersProvider);
    final users = (usersState.valueOrNull ?? const [])
        .where((u) => u.role == 'staff' && u.isActive)
        .toList();

    final attendanceRecords =
        ref.watch(adminAttendanceForDateProvider(todayDate)).valueOrNull ??
            const [];

    final shiftConfigs = ref.watch(shiftConfigurationsProvider).valueOrNull ??
        const [
          ShiftConfiguration.defaultMorning,
          ShiftConfiguration.defaultAfternoon,
        ];

    final morningConfig = shiftConfigs.firstWhere(
      (c) => c.name.toLowerCase() == 'morning',
      orElse: () => ShiftConfiguration.defaultMorning,
    );
    final eveningConfig = shiftConfigs.firstWhere(
      (c) =>
          c.name.toLowerCase() == 'afternoon' ||
          c.name.toLowerCase() == 'evening' ||
          c.name.toLowerCase() == 'night',
      orElse: () => ShiftConfiguration.defaultAfternoon,
    );

    // Count staff assigned to each shift category respecting effective dates
    final morningAssigned = users.where((u) {
      final s = u.getShiftForDate(todayDate).toLowerCase().trim();
      return s == 'morning' || s == 'both';
    }).length;

    final eveningAssigned = users.where((u) {
      final s = u.getShiftForDate(todayDate).toLowerCase().trim();
      return s == 'afternoon' || s == 'evening' || s == 'both';
    }).length;

    final nightAssigned = users.where((u) {
      final s = u.getShiftForDate(todayDate).toLowerCase().trim();
      return s == 'night';
    }).length;

    final onCallAssigned = users.where((u) {
      final s = u.getShiftForDate(todayDate).toLowerCase().trim();
      return s == 'on_call' || s == 'oncall' || s == 'emergency';
    }).length;

    // Distinct checked-in staff count to avoid duplicate staff counts
    final morningPresent = attendanceRecords
        .where((r) =>
            r.shift.toLowerCase().trim() == 'morning' && r.checkInTime != null)
        .map((r) => r.staffId)
        .toSet()
        .length;

    final eveningPresent = attendanceRecords
        .where((r) =>
            (r.shift.toLowerCase().trim() == 'afternoon' ||
                r.shift.toLowerCase().trim() == 'evening') &&
            r.checkInTime != null)
        .map((r) => r.staffId)
        .toSet()
        .length;

    final nightPresent = attendanceRecords
        .where((r) =>
            r.shift.toLowerCase().trim() == 'night' && r.checkInTime != null)
        .map((r) => r.staffId)
        .toSet()
        .length;

    final onCallPresent = attendanceRecords
        .where((r) =>
            (r.shift.toLowerCase().trim() == 'on_call' ||
                r.shift.toLowerCase().trim() == 'emergency') &&
            r.checkInTime != null)
        .map((r) => r.staffId)
        .toSet()
        .length;

    // Shift 1: Morning
    final morningShort =
        morningAssigned > morningPresent ? morningAssigned - morningPresent : 0;
    final morningStatus =
        morningShort > 0 ? 'Short - $morningShort' : 'Optimal';
    final morningDotColor =
        morningShort > 0 ? AppColors.secondary : AppColors.primaryContainer;
    final morningStatusColor =
        morningShort > 0 ? AppColors.secondary : AppColors.primaryContainer;

    // Shift 2: Evening
    final eveningShort =
        eveningAssigned > eveningPresent ? eveningAssigned - eveningPresent : 0;
    final eveningStatus =
        eveningShort > 0 ? 'Short - $eveningShort' : 'Optimal';
    final eveningDotColor =
        eveningShort > 0 ? AppColors.secondary : AppColors.primaryContainer;
    final eveningStatusColor =
        eveningShort > 0 ? AppColors.secondary : AppColors.primaryContainer;

    // Shift 3: Night
    final nightShort =
        nightAssigned > nightPresent ? nightAssigned - nightPresent : 0;
    final nightStatus = nightShort > 0 ? 'Short - $nightShort' : 'Optimal';
    final nightDotColor =
        nightShort > 0 ? AppColors.secondary : AppColors.primaryContainer;
    final nightStatusColor =
        nightShort > 0 ? AppColors.secondary : AppColors.primaryContainer;

    // Shift 4: On-Call
    final onCallShort =
        onCallAssigned > onCallPresent ? onCallAssigned - onCallPresent : 0;
    final onCallStatus = onCallAssigned > 0
        ? (onCallShort > 0 ? 'Short - $onCallShort' : 'Optimal')
        : 'On Standby';
    final onCallDotColor =
        onCallShort > 0 ? AppColors.secondary : AppColors.tertiary;
    final onCallStatusColor =
        onCallShort > 0 ? AppColors.secondary : AppColors.tertiary;

    return DecoratedBox(
      decoration: BoxDecoration(
        color: AppColors.surfaceContainerLowest,
        borderRadius: BorderRadius.circular(AppSpacing.radiusLg),
        border: Border.all(color: const Color(0xFFE5E2E1)),
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
            // Header
            DecoratedBox(
              decoration: const BoxDecoration(
                border: Border(
                  bottom: BorderSide(color: AppColors.outlineVariant),
                ),
              ),
              child: Padding(
                padding: const EdgeInsets.only(bottom: AppSpacing.xs),
                child: Row(
                  mainAxisAlignment: MainAxisAlignment.spaceBetween,
                  children: [
                    Flexible(
                      child: Row(
                        children: [
                          const Icon(
                            Icons.groups_outlined,
                            color: AppColors.onSurfaceVariant,
                            size: 22,
                          ),
                          const SizedBox(width: AppSpacing.xs),
                          Flexible(
                            child: Text(
                              'Shift & Attendance Summary',
                              style: AppTypography.headlineMd,
                              overflow: TextOverflow.ellipsis,
                            ),
                          ),
                        ],
                      ),
                    ),
                    Container(
                      padding: const EdgeInsets.symmetric(
                        horizontal: AppSpacing.xs,
                        vertical: AppSpacing.base,
                      ),
                      decoration: BoxDecoration(
                        color: AppColors.surfaceContainerHigh,
                        borderRadius:
                            BorderRadius.circular(AppSpacing.radiusSm),
                      ),
                      child: Text(
                        'Today',
                        style: AppTypography.labelCaps.copyWith(
                          color: AppColors.onSurface,
                        ),
                      ),
                    ),
                  ],
                ),
              ),
            ),
            const SizedBox(height: AppSpacing.md),
            // Table header
            Padding(
              padding: const EdgeInsets.only(bottom: AppSpacing.xs),
              child: DecoratedBox(
                decoration: const BoxDecoration(
                  border: Border(
                    bottom: BorderSide(color: Color(0xFFF0EDEC)),
                  ),
                ),
                child: Padding(
                  padding: const EdgeInsets.only(bottom: AppSpacing.xs),
                  child: Row(
                    children: [
                      Expanded(
                        flex: 2,
                        child: Text(
                          'Shift Category',
                          style: AppTypography.labelCaps.copyWith(
                            color: AppColors.onSurfaceVariant,
                            fontWeight: FontWeight.w500,
                          ),
                          overflow: TextOverflow.ellipsis,
                        ),
                      ),
                      Expanded(
                        child: Text(
                          'Staffed',
                          textAlign: TextAlign.center,
                          style: AppTypography.labelCaps.copyWith(
                            color: AppColors.onSurfaceVariant,
                            fontWeight: FontWeight.w500,
                          ),
                          overflow: TextOverflow.ellipsis,
                        ),
                      ),
                      Expanded(
                        child: Text(
                          'Status',
                          textAlign: TextAlign.right,
                          style: AppTypography.labelCaps.copyWith(
                            color: AppColors.onSurfaceVariant,
                            fontWeight: FontWeight.w500,
                          ),
                          overflow: TextOverflow.ellipsis,
                        ),
                      ),
                    ],
                  ),
                ),
              ),
            ),
            _DepartmentRow(
              department:
                  'Morning Shift (${morningConfig.startTime} - ${morningConfig.endTime})',
              staffed: '$morningPresent/$morningAssigned',
              status: morningStatus,
              dotColor: morningDotColor,
              statusColor: morningStatusColor,
              highlighted: morningShort > 0,
              highlightColor: _secondaryFixed.withValues(alpha: 0.3),
            ),
            _DepartmentRow(
              department:
                  'Evening Shift (${eveningConfig.startTime} - ${eveningConfig.endTime})',
              staffed: '$eveningPresent/$eveningAssigned',
              status: eveningStatus,
              dotColor: eveningDotColor,
              statusColor: eveningStatusColor,
              highlighted: eveningShort > 0,
              highlightColor: _secondaryFixed.withValues(alpha: 0.3),
            ),
            _DepartmentRow(
              department: 'Night Shift (23:00 - 07:00)',
              staffed: '$nightPresent/$nightAssigned',
              status: nightStatus,
              dotColor: nightDotColor,
              statusColor: nightStatusColor,
              highlighted: nightShort > 0,
              highlightColor: _secondaryFixed.withValues(alpha: 0.3),
            ),
            _DepartmentRow(
              department: 'On-Call Emergency Triage',
              staffed: '$onCallPresent/$onCallAssigned',
              status: onCallStatus,
              dotColor: onCallDotColor,
              statusColor: onCallStatusColor,
              highlighted: onCallShort > 0,
              highlightColor: _secondaryFixed.withValues(alpha: 0.3),
              showBottomBorder: false,
            ),
          ],
        ),
      ),
    );
  }
}

class _DepartmentRow extends StatelessWidget {
  const _DepartmentRow({
    required this.department,
    required this.staffed,
    required this.status,
    required this.dotColor,
    required this.statusColor,
    this.highlighted = false,
    this.highlightColor,
    this.showBottomBorder = true,
  });

  final String department;
  final String staffed;
  final String status;
  final Color dotColor;
  final Color statusColor;
  final bool highlighted;
  final Color? highlightColor;
  final bool showBottomBorder;

  @override
  Widget build(BuildContext context) {
    return Container(
      padding: const EdgeInsets.symmetric(
        horizontal: AppSpacing.base,
        vertical: AppSpacing.xs,
      ),
      decoration: BoxDecoration(
        color: highlightColor,
        border: Border(
          left: highlighted
              ? const BorderSide(color: AppColors.secondary, width: 2)
              : BorderSide.none,
          bottom: showBottomBorder
              ? const BorderSide(color: AppColors.surfaceContainerLow)
              : BorderSide.none,
        ),
      ),
      child: Row(
        children: [
          Expanded(
            flex: 2,
            child: Row(
              children: [
                Container(
                  width: 8,
                  height: 8,
                  decoration: BoxDecoration(
                    color: dotColor,
                    shape: BoxShape.circle,
                  ),
                ),
                const SizedBox(width: AppSpacing.xs),
                Flexible(
                  child: Text(
                    department,
                    style: AppTypography.bodySm.copyWith(
                      color: AppColors.onSurface,
                    ),
                    overflow: TextOverflow.ellipsis,
                  ),
                ),
              ],
            ),
          ),
          Expanded(
            child: Text(
              staffed,
              textAlign: TextAlign.center,
              style: AppTypography.dataMono.copyWith(
                color: AppColors.onSurface,
              ),
              overflow: TextOverflow.ellipsis,
            ),
          ),
          Expanded(
            child: Text(
              status,
              textAlign: TextAlign.right,
              style: AppTypography.bodySm.copyWith(color: statusColor),
              overflow: TextOverflow.ellipsis,
            ),
          ),
        ],
      ),
    );
  }
}
