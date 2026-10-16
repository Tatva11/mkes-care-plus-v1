import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';

import '../../../core/theme/app_colors.dart';
import '../../../core/theme/app_spacing.dart';
import '../../../core/theme/app_typography.dart';
import '../../staff/providers/attendance_provider.dart';

class StaffAttendanceCard extends ConsumerWidget {
  const StaffAttendanceCard({super.key});

  static const _errorContainer = Color(0xFFFFDAD6);
  static const _secondaryFixed = Color(0xFFFFD8EB);

  @override
  Widget build(BuildContext context, WidgetRef ref) {
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
                          Icon(
                            Icons.badge_outlined,
                            color: AppColors.onSurfaceVariant,
                            size: 22,
                          ),
                          const SizedBox(width: AppSpacing.xs),
                          Flexible(
                            child: Text(
                              'Staff Attendance',
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
            Builder(
              builder: (context) {
                final now = DateTime.now();
                final today = DateTime(now.year, now.month, now.day);
                final summaryAsync = ref.watch(adminAttendanceSummaryProvider(today));
                final presentCount = summaryAsync.when(
                  data: (s) => '${(s['present'] ?? 0) + (s['late'] ?? 0)}',
                  loading: () => '...',
                  error: (_, __) => '0',
                );
                final leaveCount = summaryAsync.when(
                  data: (s) => '${s['leave'] ?? 0}',
                  loading: () => '...',
                  error: (_, __) => '0',
                );

                return Row(
                  children: [
                    Expanded(
                      child: _StatTile(
                        value: presentCount,
                        label: 'Present',
                        valueColor: AppColors.primary,
                      ),
                    ),
                    const SizedBox(width: AppSpacing.sm),
                    Expanded(
                      child: _StatTile(
                        value: leaveCount,
                        label: 'On Leave',
                        valueColor: AppColors.secondary,
                        backgroundColor: _errorContainer.withValues(alpha: 0.2),
                        borderColor: _errorContainer,
                      ),
                    ),
                  ],
                );
              },
            ),
            const SizedBox(height: AppSpacing.md),
            _TableHeader(),
            const _DepartmentRow(
              department: 'OPD',
              staffed: '12/12',
              status: 'Optimal',
              dotColor: AppColors.primaryContainer,
              statusColor: AppColors.primaryContainer,
            ),
            _DepartmentRow(
              department: 'Dental',
              staffed: '4/6',
              status: 'Short',
              dotColor: AppColors.secondary,
              statusColor: AppColors.secondary,
              highlighted: true,
              highlightColor: _secondaryFixed.withValues(alpha: 0.3),
            ),
            const _DepartmentRow(
              department: 'Pharmacy',
              staffed: '5/5',
              status: 'Optimal',
              dotColor: AppColors.primaryContainer,
              statusColor: AppColors.primaryContainer,
              showBottomBorder: false,
            ),
          ],
        ),
      ),
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
        border: borderColor != null ? Border.all(color: borderColor!) : null,
      ),
      child: Column(
        children: [
          Text(
            value,
            style: AppTypography.displayLg.copyWith(color: valueColor),
            maxLines: 1,
            overflow: TextOverflow.ellipsis,
          ),
          const SizedBox(height: AppSpacing.base),
          Text(
            label,
            style: AppTypography.labelCaps.copyWith(
              color: AppColors.onSurfaceVariant,
            ),
            maxLines: 1,
            overflow: TextOverflow.ellipsis,
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
                  'Department',
                  style: AppTypography.labelCaps.copyWith(
                    color: AppColors.outlineVariant,
                    fontWeight: FontWeight.w500,
                  ),
                ),
              ),
              Expanded(
                child: Text(
                  'Staffed',
                  textAlign: TextAlign.right,
                  style: AppTypography.labelCaps.copyWith(
                    color: AppColors.outlineVariant,
                    fontWeight: FontWeight.w500,
                  ),
                ),
              ),
              Expanded(
                child: Text(
                  'Status',
                  textAlign: TextAlign.right,
                  style: AppTypography.labelCaps.copyWith(
                    color: AppColors.outlineVariant,
                    fontWeight: FontWeight.w500,
                  ),
                ),
              ),
            ],
          ),
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
                  child: Text(department, style: AppTypography.bodySm.copyWith(
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
              textAlign: TextAlign.right,
              style: AppTypography.dataMono.copyWith(
                color: AppColors.onSurface,
              ),
            ),
          ),
          Expanded(
            child: Text(
              status,
              textAlign: TextAlign.right,
              style: AppTypography.bodySm.copyWith(
                color: statusColor,
              ),
            ),
          ),
        ],
      ),
    );
  }
}
