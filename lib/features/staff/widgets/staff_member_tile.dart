import 'package:flutter/material.dart';

import '../../../core/theme/app_colors.dart';
import '../../../core/theme/app_spacing.dart';
import '../../../core/theme/app_typography.dart';

import '../models/attendance_record.dart';
import '../../admin/models/user_profile.dart';
import '../screens/staff_profile_detail_screen.dart';

enum StaffStatus { present, late, checkedOut, onLeave, absent, notCheckedIn, offDuty }

class StaffMemberTile extends StatelessWidget {
  const StaffMemberTile({
    super.key,
    required this.user,
    this.todayAttendance,
    this.showDivider = true,
  });

  final UserProfile user;
  final AttendanceRecord? todayAttendance;
  final bool showDivider;

  static const _errorContainer = Color(0xFFFFDAD6);
  static const _secondaryFixed = Color(0xFFFFD8EB);

  StaffStatus get _status {
    if (!user.isActive) {
      return StaffStatus.offDuty;
    }
    final att = todayAttendance;
    if (att == null) {
      return StaffStatus.notCheckedIn;
    }
    final st = att.status.toLowerCase();
    if (st == 'leave') {
      return StaffStatus.onLeave;
    }
    if (st == 'absent') {
      return StaffStatus.absent;
    }
    if (att.checkOutTime != null) {
      return StaffStatus.checkedOut;
    }
    if (att.checkInTime != null) {
      if (att.isLate || st == 'late') {
        return StaffStatus.late;
      }
      return StaffStatus.present;
    }
    return StaffStatus.notCheckedIn;
  }

  Color get _statusBg {
    switch (_status) {
      case StaffStatus.present:
        return AppColors.surfaceContainerLow;
      case StaffStatus.late:
        return _secondaryFixed.withValues(alpha: 0.35);
      case StaffStatus.checkedOut:
        return AppColors.surfaceContainerHigh;
      case StaffStatus.onLeave:
        return _errorContainer.withValues(alpha: 0.25);
      case StaffStatus.absent:
        return _errorContainer.withValues(alpha: 0.35);
      case StaffStatus.notCheckedIn:
      case StaffStatus.offDuty:
        return AppColors.surfaceContainerHigh;
    }
  }

  Color get _statusTextColor {
    switch (_status) {
      case StaffStatus.present:
        return AppColors.primaryContainer;
      case StaffStatus.late:
        return AppColors.secondary;
      case StaffStatus.checkedOut:
        return AppColors.onSurfaceVariant;
      case StaffStatus.onLeave:
        return AppColors.secondary;
      case StaffStatus.absent:
        return AppColors.error;
      case StaffStatus.notCheckedIn:
        return AppColors.onSurfaceVariant;
      case StaffStatus.offDuty:
        return AppColors.onSurfaceVariant;
    }
  }

  Color get _statusDotColor {
    switch (_status) {
      case StaffStatus.present:
        return AppColors.primaryContainer;
      case StaffStatus.late:
        return AppColors.secondary;
      case StaffStatus.checkedOut:
        return AppColors.outline;
      case StaffStatus.onLeave:
        return AppColors.secondary;
      case StaffStatus.absent:
        return AppColors.error;
      case StaffStatus.notCheckedIn:
        return AppColors.outlineVariant;
      case StaffStatus.offDuty:
        return AppColors.onSurfaceVariant;
    }
  }

  String get _statusLabel {
    switch (_status) {
      case StaffStatus.present:
        return 'Present';
      case StaffStatus.late:
        return 'Late';
      case StaffStatus.checkedOut:
        return 'Checked Out';
      case StaffStatus.onLeave:
        return 'On Leave';
      case StaffStatus.absent:
        return 'Absent';
      case StaffStatus.notCheckedIn:
        return 'Not Checked In';
      case StaffStatus.offDuty:
        return 'Inactive';
    }
  }

  Color get _avatarBg {
    switch (user.departmentName ?? user.department) {
      case 'Dental':
        return _secondaryFixed.withValues(alpha: 0.5);
      case 'OPD':
        return AppColors.primaryContainer.withValues(alpha: 0.15);
      default:
        return const Color(0xFFE5E2E1);
    }
  }

  Color get _avatarTextColor {
    switch (user.departmentName ?? user.department) {
      case 'Dental':
        return AppColors.secondary;
      case 'OPD':
        return AppColors.primaryContainer;
      default:
        return AppColors.onSurfaceVariant;
    }
  }

  @override
  Widget build(BuildContext context) {
    final initials = user.fullName
        .split(' ')
        .map((w) => w.isNotEmpty ? w[0] : '')
        .take(2)
        .join()
        .toUpperCase();

    return Column(
      children: [
        InkWell(
          borderRadius: BorderRadius.circular(AppSpacing.radiusMd),
          onTap: () {
            Navigator.of(context).push(
              MaterialPageRoute(
                builder: (_) => StaffProfileDetailScreen(user: user),
              ),
            );
          },
          child: Padding(
            padding: const EdgeInsets.symmetric(
              vertical: AppSpacing.sm,
              horizontal: AppSpacing.xs,
            ),
            child: Row(
              children: [
                // Avatar
                Container(
                  width: 40,
                  height: 40,
                  decoration: BoxDecoration(
                    color: _avatarBg,
                    shape: BoxShape.circle,
                    border: Border.all(
                      color: AppColors.outlineVariant.withValues(alpha: 0.5),
                    ),
                  ),
                  child: Center(
                    child: Text(
                      initials,
                      style: AppTypography.labelCaps.copyWith(
                        color: _avatarTextColor,
                        fontWeight: FontWeight.w700,
                      ),
                    ),
                  ),
                ),
                const SizedBox(width: AppSpacing.sm),
                // Name + role
                Expanded(
                  child: Column(
                    crossAxisAlignment: CrossAxisAlignment.start,
                    children: [
                      Text(
                        user.fullName,
                        style: AppTypography.bodyMd.copyWith(
                          fontWeight: FontWeight.w600,
                        ),
                        overflow: TextOverflow.ellipsis,
                        maxLines: 1,
                      ),
                      Text(
                        '${user.designation ?? user.role.toUpperCase()} • ${user.departmentName ?? user.department ?? '-'}',
                        style: AppTypography.bodySm,
                        overflow: TextOverflow.ellipsis,
                        maxLines: 1,
                      ),
                    ],
                  ),
                ),
                const SizedBox(width: AppSpacing.xs),
                // Shift & Contact & Salary
                Column(
                  crossAxisAlignment: CrossAxisAlignment.end,
                  children: [
                    // Status badge
                    Container(
                      padding: const EdgeInsets.symmetric(
                        horizontal: AppSpacing.xs,
                        vertical: AppSpacing.base,
                      ),
                      decoration: BoxDecoration(
                        color: _statusBg,
                        borderRadius: BorderRadius.circular(AppSpacing.radiusSm),
                      ),
                      child: Row(
                        mainAxisSize: MainAxisSize.min,
                        children: [
                          Container(
                            width: 6,
                            height: 6,
                            decoration: BoxDecoration(
                              color: _statusDotColor,
                              shape: BoxShape.circle,
                            ),
                          ),
                          const SizedBox(width: AppSpacing.base),
                          Text(
                            _statusLabel,
                            style: AppTypography.labelCaps.copyWith(
                              color: _statusTextColor,
                            ),
                          ),
                        ],
                      ),
                    ),
                    const SizedBox(height: AppSpacing.base),
                    Text(
                      '${user.email} • ${user.phoneNumber ?? 'No phone'}',
                      style: AppTypography.bodySm.copyWith(
                        fontSize: 12,
                      ),
                    ),
                    Text(
                      'Joined: ${user.joiningDate?.toIso8601String().split('T').first ?? '—'} • Salary: ${user.salary != null ? '₹${user.salary!.toStringAsFixed(0)}' : '—'}',
                      style: AppTypography.bodySm.copyWith(fontSize: 11),
                    ),
                  ],
                ),
                const SizedBox(width: AppSpacing.xs),
                const Icon(
                  Icons.chevron_right,
                  size: 20,
                  color: AppColors.outline,
                ),
              ],
            ),
          ),
        ),
        if (showDivider)
          Divider(
            height: 1,
            thickness: 1,
            color: AppColors.outlineVariant.withValues(alpha: 0.4),
            indent: AppSpacing.xs,
            endIndent: AppSpacing.xs,
          ),
      ],
    );
  }
}
