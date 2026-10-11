import 'package:flutter/material.dart';

import '../../../core/theme/app_colors.dart';
import '../../../core/theme/app_spacing.dart';
import '../../../core/theme/app_typography.dart';

class StaffAttendanceSummaryCard extends StatelessWidget {
  const StaffAttendanceSummaryCard({super.key});

  static const _secondaryFixed = Color(0xFFFFD8EB);

  @override
  Widget build(BuildContext context) {
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
              department: 'Morning Shift (07:00 - 15:00)',
              staffed: '14/14',
              status: 'Optimal',
              dotColor: AppColors.primaryContainer,
              statusColor: AppColors.primaryContainer,
            ),
            _DepartmentRow(
              department: 'Evening Shift (15:00 - 23:00)',
              staffed: '10/12',
              status: 'Short - 2',
              dotColor: AppColors.secondary,
              statusColor: AppColors.secondary,
              highlighted: true,
              highlightColor: _secondaryFixed.withValues(alpha: 0.3),
            ),
            _DepartmentRow(
              department: 'Night Shift (23:00 - 07:00)',
              staffed: '4/4',
              status: 'Optimal',
              dotColor: AppColors.primaryContainer,
              statusColor: AppColors.primaryContainer,
            ),
            _DepartmentRow(
              department: 'On-Call Emergency Triage',
              staffed: '2/3',
              status: 'On Standby',
              dotColor: AppColors.tertiary,
              statusColor: AppColors.tertiary,
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
