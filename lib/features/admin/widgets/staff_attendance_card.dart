import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';

import '../../../core/theme/app_colors.dart';
import '../../../core/theme/app_spacing.dart';
import '../../../core/theme/app_typography.dart';
import '../../../core/utils/date_boundaries.dart';
import '../../staff/models/attendance_record.dart';
import '../../staff/models/leave_request.dart';
import '../../staff/providers/attendance_provider.dart';
import '../../staff/providers/leave_provider.dart';
import '../../staff/screens/staff_management_screen.dart';
import '../models/user_profile.dart';
import '../providers/users_provider.dart';

/// Admin Dashboard Card displaying real, dynamic staff attendance and department breakdowns
/// for today's local calendar day. Eliminates all hardcoded department rows and targets.
class StaffAttendanceCard extends ConsumerWidget {
  const StaffAttendanceCard({
    super.key,
    this.onNavigateToStaff,
  });

  final VoidCallback? onNavigateToStaff;

  static const _errorContainer = Color(0xFFFFDAD6);

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    final now = DateTime.now();
    final today = DateBoundaries.startOfDay(now);

    final usersAsync = ref.watch(usersProvider);
    final attendanceAsync = ref.watch(adminAttendanceForDateProvider(today));
    final leaveAsync = ref.watch(adminAllLeaveRequestsProvider);

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
            // Card Header
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
                          Icons.badge_outlined,
                          color: AppColors.onSurfaceVariant,
                          size: 22,
                        ),
                        const SizedBox(width: AppSpacing.xs),
                        Flexible(
                          child: Text(
                            'Staff Attendance',
                            style: AppTypography.headlineMd,
                          ),
                        ),
                      ],
                    ),
                    TextButton(
                      onPressed: () {
                        if (onNavigateToStaff != null) {
                          onNavigateToStaff!();
                        } else {
                          Navigator.of(context).push(
                            MaterialPageRoute(
                              builder: (_) => const StaffManagementScreen(),
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
                            'Manage Staff',
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

            // Async data aggregation
            if (usersAsync.isLoading || attendanceAsync.isLoading)
              _buildLoadingState()
            else if (usersAsync.hasError || attendanceAsync.hasError)
              _buildErrorState(
                ref,
                usersAsync.error?.toString() ??
                    attendanceAsync.error?.toString() ??
                    'Failed to load attendance',
                today,
              )
            else
              _buildDataContent(
                context,
                users: usersAsync.valueOrNull ?? [],
                attendanceRecords: attendanceAsync.valueOrNull ?? [],
                leaveRequests: leaveAsync.valueOrNull ?? [],
                today: today,
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
              "Loading today's attendance...",
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

  Widget _buildErrorState(WidgetRef ref, String error, DateTime today) {
    return SizedBox(
      height: 180,
      child: Center(
        child: Column(
          mainAxisAlignment: MainAxisAlignment.center,
          children: [
            const Icon(Icons.error_outline, color: AppColors.error, size: 28),
            const SizedBox(height: AppSpacing.xs),
            Text(
              'Unable to load attendance data',
              style: AppTypography.labelCaps.copyWith(
                color: AppColors.error,
                fontWeight: FontWeight.w600,
              ),
            ),
            const SizedBox(height: AppSpacing.xs),
            OutlinedButton.icon(
              onPressed: () {
                ref.invalidate(usersProvider);
                ref.invalidate(adminAttendanceForDateProvider(today));
                ref.invalidate(adminAllLeaveRequestsProvider);
              },
              icon: const Icon(Icons.refresh, size: 14),
              label: const Text('Retry'),
            ),
          ],
        ),
      ),
    );
  }

  Widget _buildDataContent(
    BuildContext context, {
    required List<UserProfile> users,
    required List<AttendanceRecord> attendanceRecords,
    required List<LeaveRequest> leaveRequests,
    required DateTime today,
  }) {
    // 1. Identify active staff (excluding admin roles)
    final activeStaff = users.where((u) {
      return u.isActive && u.role.toLowerCase() != 'admin';
    }).toList();

    // 2. Identify present staff today (from attendance records with valid check-in or present/late status)
    final presentStaffIds = <String>{};
    for (final a in attendanceRecords) {
      final s = a.status.toLowerCase();
      if (s == 'present' || s == 'late' || a.checkInTime != null) {
        presentStaffIds.add(a.staffId);
      }
    }

    // 3. Identify staff on approved leave today (avoiding double-counting with present staff)
    final onLeaveStaffIds = <String>{};
    for (final l in leaveRequests) {
      if (l.status.toLowerCase() == 'approved') {
        final start =
            DateTime(l.startDate.year, l.startDate.month, l.startDate.day);
        final end = DateTime(l.endDate.year, l.endDate.month, l.endDate.day);
        if (!today.isBefore(start) && !today.isAfter(end)) {
          if (!presentStaffIds.contains(l.staffId)) {
            onLeaveStaffIds.add(l.staffId);
          }
        }
      }
    }
    for (final a in attendanceRecords) {
      if (a.status.toLowerCase() == 'leave' &&
          !presentStaffIds.contains(a.staffId)) {
        onLeaveStaffIds.add(a.staffId);
      }
    }

    final totalPresent =
        activeStaff.where((u) => presentStaffIds.contains(u.id)).length;
    final totalOnLeave =
        activeStaff.where((u) => onLeaveStaffIds.contains(u.id)).length;

    // 4. Group active staff by real department
    final Map<String, List<UserProfile>> deptMap = {};
    for (final u in activeStaff) {
      var d = u.departmentName ?? u.department ?? 'General';
      if (d.trim().isEmpty) d = 'General';
      deptMap.putIfAbsent(d, () => []).add(u);
    }

    final sortedDepts = deptMap.keys.toList()..sort();

    return Column(
      crossAxisAlignment: CrossAxisAlignment.stretch,
      children: [
        // Top KPI Stat Tiles
        Row(
          children: [
            Expanded(
              child: _StatTile(
                value: '$totalPresent',
                label: 'Present Today',
                valueColor: AppColors.primary,
              ),
            ),
            const SizedBox(width: AppSpacing.sm),
            Expanded(
              child: _StatTile(
                value: '$totalOnLeave',
                label: 'On Approved Leave',
                valueColor: AppColors.secondary,
                backgroundColor: _errorContainer.withValues(alpha: 0.2),
                borderColor: _errorContainer,
              ),
            ),
          ],
        ),
        const SizedBox(height: AppSpacing.md),

        // Real Department Breakdown Table
        _TableHeader(),
        if (sortedDepts.isEmpty)
          Padding(
            padding: const EdgeInsets.symmetric(vertical: AppSpacing.md),
            child: Center(
              child: Text(
                'No active staff assigned to departments',
                style: AppTypography.bodySm.copyWith(
                  color: AppColors.onSurfaceVariant,
                ),
              ),
            ),
          )
        else
          for (int i = 0; i < sortedDepts.length; i++) ...[
            Builder(
              builder: (context) {
                final deptName = sortedDepts[i];
                final deptStaff = deptMap[deptName]!;
                final assigned = deptStaff.length;
                final present = deptStaff
                    .where((u) => presentStaffIds.contains(u.id))
                    .length;
                final leave = deptStaff
                    .where((u) => onLeaveStaffIds.contains(u.id))
                    .length;

                final String statusText;
                final Color statusColor;
                if (leave > 0) {
                  statusText = '$leave on leave';
                  statusColor = AppColors.secondary;
                } else if (present > 0) {
                  statusText = '$present present';
                  statusColor = const Color(0xFF2E7D32);
                } else {
                  statusText = 'No check-ins';
                  statusColor = AppColors.outline;
                }

                return _DepartmentRow(
                  department: deptName,
                  staffed: '$present/$assigned',
                  status: statusText,
                  dotColor: present > 0
                      ? AppColors.primaryContainer
                      : AppColors.outlineVariant,
                  statusColor: statusColor,
                  showBottomBorder: i < sortedDepts.length - 1,
                );
              },
            ),
          ],
      ],
    );
  }
}

class _StatTile extends StatelessWidget {
  const _StatTile({
    required this.value,
    required this.label,
    required this.valueColor,
    this.backgroundColor,
    this.borderColor,
  });

  final String value;
  final String label;
  final Color valueColor;
  final Color? backgroundColor;
  final Color? borderColor;

  @override
  Widget build(BuildContext context) {
    return Container(
      padding: const EdgeInsets.all(AppSpacing.sm),
      decoration: BoxDecoration(
        color: backgroundColor ?? AppColors.surfaceContainerLow,
        borderRadius: BorderRadius.circular(AppSpacing.radiusMd),
        border: Border.all(
          color: borderColor ?? Colors.transparent,
        ),
      ),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Text(
            value,
            style: AppTypography.headlineMd.copyWith(
              color: valueColor,
              fontWeight: FontWeight.bold,
            ),
          ),
          const SizedBox(height: 2),
          Text(
            label,
            style: AppTypography.labelCaps.copyWith(
              color: AppColors.onSurfaceVariant,
              fontSize: 10,
            ),
          ),
        ],
      ),
    );
  }
}

class _TableHeader extends StatelessWidget {
  @override
  Widget build(BuildContext context) {
    return Padding(
      padding: const EdgeInsets.symmetric(
        horizontal: AppSpacing.xs,
        vertical: AppSpacing.base,
      ),
      child: Row(
        children: [
          Expanded(
            flex: 4,
            child: Text(
              'DEPARTMENT',
              style: AppTypography.labelCaps.copyWith(
                color: AppColors.onSurfaceVariant,
              ),
            ),
          ),
          Expanded(
            flex: 3,
            child: Text(
              'STAFFED',
              style: AppTypography.labelCaps.copyWith(
                color: AppColors.onSurfaceVariant,
              ),
              textAlign: TextAlign.center,
            ),
          ),
          Expanded(
            flex: 3,
            child: Text(
              'STATUS',
              style: AppTypography.labelCaps.copyWith(
                color: AppColors.onSurfaceVariant,
              ),
              textAlign: TextAlign.right,
            ),
          ),
        ],
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
    this.showBottomBorder = true,
  });

  final String department;
  final String staffed;
  final String status;
  final Color dotColor;
  final Color statusColor;
  final bool showBottomBorder;

  @override
  Widget build(BuildContext context) {
    return Container(
      decoration: BoxDecoration(
        border: showBottomBorder
            ? const Border(
                bottom: BorderSide(
                  color: Color(0xFFF0ECEB),
                  width: 1,
                ),
              )
            : null,
      ),
      padding: const EdgeInsets.symmetric(
        horizontal: AppSpacing.xs,
        vertical: AppSpacing.sm,
      ),
      child: Row(
        children: [
          Expanded(
            flex: 4,
            child: Row(
              children: [
                Container(
                  width: 6,
                  height: 6,
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
                      fontWeight: FontWeight.w600,
                    ),
                    overflow: TextOverflow.ellipsis,
                  ),
                ),
              ],
            ),
          ),
          Expanded(
            flex: 3,
            child: Text(
              staffed,
              style: AppTypography.bodySm,
              textAlign: TextAlign.center,
            ),
          ),
          Expanded(
            flex: 3,
            child: Text(
              status,
              style: AppTypography.labelCaps.copyWith(
                color: statusColor,
                fontWeight: FontWeight.w600,
                fontSize: 10,
              ),
              textAlign: TextAlign.right,
              overflow: TextOverflow.ellipsis,
            ),
          ),
        ],
      ),
    );
  }
}
