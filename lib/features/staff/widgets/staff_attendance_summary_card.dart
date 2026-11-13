import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:intl/intl.dart';

import '../../../core/theme/app_colors.dart';
import '../../../core/theme/app_spacing.dart';
import '../../../core/theme/app_typography.dart';
import '../../admin/providers/users_provider.dart';
import '../models/attendance_record.dart';
import '../providers/attendance_provider.dart';

class StaffAttendanceSummaryCard extends ConsumerWidget {
  const StaffAttendanceSummaryCard({super.key, this.targetDate});

  final DateTime? targetDate;

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

    // Distinct checked-in staff records for today matching attendance records
    final checkedInRecords = attendanceRecords
        .where((r) => r.checkInTime != null)
        .toList();

    final checkedInStaffCount = checkedInRecords
        .map((r) => r.staffId)
        .toSet()
        .length;

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
            // Header: Staff Checked In Today
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
                            Icons.how_to_reg_outlined,
                            color: AppColors.primary,
                            size: 22,
                          ),
                          const SizedBox(width: AppSpacing.xs),
                          Flexible(
                            child: Text(
                              'Staff Checked In Today',
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
                        color: checkedInStaffCount > 0
                            ? Colors.green.shade50
                            : AppColors.surfaceContainerHigh,
                        borderRadius: BorderRadius.circular(AppSpacing.radiusSm),
                        border: Border.all(
                          color: checkedInStaffCount > 0
                              ? Colors.green.shade300
                              : Colors.transparent,
                        ),
                      ),
                      child: Text(
                        checkedInStaffCount == 1
                            ? '1 Checked In'
                            : '$checkedInStaffCount Checked In',
                        style: AppTypography.labelCaps.copyWith(
                          color: checkedInStaffCount > 0
                              ? Colors.green.shade800
                              : AppColors.onSurface,
                          fontWeight: FontWeight.bold,
                        ),
                      ),
                    ),
                  ],
                ),
              ),
            ),
            const SizedBox(height: AppSpacing.md),

            if (checkedInRecords.isEmpty) ...[
              Container(
                padding: const EdgeInsets.symmetric(
                  vertical: AppSpacing.xl,
                  horizontal: AppSpacing.md,
                ),
                alignment: Alignment.center,
                child: Column(
                  mainAxisAlignment: MainAxisAlignment.center,
                  children: [
                    const Icon(
                      Icons.person_off_outlined,
                      size: 36,
                      color: AppColors.outlineVariant,
                    ),
                    const SizedBox(height: AppSpacing.xs),
                    Text(
                      'No staff members have checked in yet today.',
                      style: AppTypography.bodySm.copyWith(
                        color: AppColors.onSurfaceVariant,
                        fontWeight: FontWeight.w500,
                      ),
                      textAlign: TextAlign.center,
                    ),
                  ],
                ),
              ),
            ] else ...[
              // Table Header
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
                          flex: 3,
                          child: Text(
                            'Staff Member',
                            style: AppTypography.labelCaps.copyWith(
                              color: AppColors.onSurfaceVariant,
                              fontWeight: FontWeight.w600,
                            ),
                            overflow: TextOverflow.ellipsis,
                          ),
                        ),
                        Expanded(
                          flex: 2,
                          child: Text(
                            'Check-In',
                            textAlign: TextAlign.center,
                            style: AppTypography.labelCaps.copyWith(
                              color: AppColors.onSurfaceVariant,
                              fontWeight: FontWeight.w600,
                            ),
                            overflow: TextOverflow.ellipsis,
                          ),
                        ),
                        Expanded(
                          flex: 2,
                          child: Text(
                            'Status',
                            textAlign: TextAlign.right,
                            style: AppTypography.labelCaps.copyWith(
                              color: AppColors.onSurfaceVariant,
                              fontWeight: FontWeight.w600,
                            ),
                            overflow: TextOverflow.ellipsis,
                          ),
                        ),
                      ],
                    ),
                  ),
                ),
              ),

              // Staff List
              for (int i = 0; i < checkedInRecords.length; i++) ...[
                _StaffCheckedInRow(
                  record: checkedInRecords[i],
                  staffUser: users
                      .where((u) => u.id == checkedInRecords[i].staffId)
                      .firstOrNull,
                  showBottomBorder: i < checkedInRecords.length - 1,
                ),
              ],
            ],
          ],
        ),
      ),
    );
  }
}

class _StaffCheckedInRow extends StatelessWidget {
  const _StaffCheckedInRow({
    required this.record,
    this.staffUser,
    this.showBottomBorder = true,
  });

  final AttendanceRecord record;
  final dynamic staffUser;
  final bool showBottomBorder;

  @override
  Widget build(BuildContext context) {
    final staffName = record.staffName ?? staffUser?.fullName ?? 'Staff Member';
    final dept = staffUser?.departmentName ??
        staffUser?.department?.toString().toUpperCase() ??
        record.shift.toUpperCase();
    final timeStr = record.checkInTime != null
        ? DateFormat('h:mm a').format(record.checkInTime!.toLocal())
        : '—';
    final isLate = record.isLate;
    final statusText = isLate ? 'Late (${record.lateMinutes}m)' : 'On Time';
    final statusColor = isLate ? AppColors.secondary : Colors.green.shade700;

    return Container(
      padding: const EdgeInsets.symmetric(
        horizontal: AppSpacing.xs,
        vertical: AppSpacing.sm,
      ),
      decoration: BoxDecoration(
        border: Border(
          bottom: showBottomBorder
              ? const BorderSide(color: AppColors.surfaceContainerLow)
              : BorderSide.none,
        ),
      ),
      child: Row(
        children: [
          // Staff Member Info
          Expanded(
            flex: 3,
            child: Row(
              children: [
                CircleAvatar(
                  radius: 14,
                  backgroundColor: AppColors.primaryContainer.withValues(alpha: 0.2),
                  child: Text(
                    staffName.isNotEmpty ? staffName[0].toUpperCase() : 'S',
                    style: const TextStyle(
                      fontSize: 12,
                      fontWeight: FontWeight.bold,
                      color: AppColors.primary,
                    ),
                  ),
                ),
                const SizedBox(width: AppSpacing.xs),
                Expanded(
                  child: Column(
                    crossAxisAlignment: CrossAxisAlignment.start,
                    children: [
                      Text(
                        staffName,
                        style: AppTypography.bodySm.copyWith(
                          fontWeight: FontWeight.w600,
                        ),
                        overflow: TextOverflow.ellipsis,
                      ),
                      Text(
                        dept,
                        style: AppTypography.labelCaps.copyWith(
                          fontSize: 9,
                          color: AppColors.onSurfaceVariant,
                        ),
                        overflow: TextOverflow.ellipsis,
                      ),
                    ],
                  ),
                ),
              ],
            ),
          ),

          // Check-In Time
          Expanded(
            flex: 2,
            child: Text(
              timeStr,
              textAlign: TextAlign.center,
              style: AppTypography.bodySm.copyWith(
                fontWeight: FontWeight.w500,
              ),
              overflow: TextOverflow.ellipsis,
            ),
          ),

          // Status Badge
          Expanded(
            flex: 2,
            child: Align(
              alignment: Alignment.centerRight,
              child: Container(
                padding: const EdgeInsets.symmetric(horizontal: 6, vertical: 2),
                decoration: BoxDecoration(
                  color: statusColor.withValues(alpha: 0.12),
                  borderRadius: BorderRadius.circular(4),
                  border: Border.all(color: statusColor.withValues(alpha: 0.4)),
                ),
                child: Text(
                  statusText,
                  style: TextStyle(
                    fontSize: 10,
                    fontWeight: FontWeight.w600,
                    color: statusColor,
                  ),
                  overflow: TextOverflow.ellipsis,
                ),
              ),
            ),
          ),
        ],
      ),
    );
  }
}
