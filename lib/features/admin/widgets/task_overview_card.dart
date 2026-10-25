import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';

import '../../../core/theme/app_colors.dart';
import '../../../core/theme/app_spacing.dart';
import '../../../core/theme/app_typography.dart';
import '../../staff/models/task_item.dart';
import '../../staff/providers/task_provider.dart';
import '../../staff/utils/task_operational_filter.dart';
import '../screens/admin_task_screen.dart';

/// Live dashboard card displaying strictly today's tasks and status distribution.
/// Only tasks whose authoritative [dueDate] is today are counted.
class TaskOverviewCard extends ConsumerWidget {
  const TaskOverviewCard({
    super.key,
    this.onNavigateToTasks,
  });

  /// Optional callback invoked when the user taps "View All Tasks" or status tiles.
  /// Defaults to navigating to [AdminTaskScreen].
  final VoidCallback? onNavigateToTasks;

  static const _surfaceBorder = Color(0xFFE5E2E1);

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    final tasksAsync = ref.watch(adminTasksProvider);

    return DecoratedBox(
      decoration: BoxDecoration(
        color: AppColors.surfaceContainerLowest,
        borderRadius: BorderRadius.circular(AppSpacing.radiusLg),
        border: Border.all(color: _surfaceBorder),
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
            // Header with icon, title, and "View All Tasks"
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
                        Container(
                          padding: const EdgeInsets.all(AppSpacing.xs),
                          decoration: BoxDecoration(
                            color: AppColors.primaryContainer
                                .withValues(alpha: 0.15),
                            borderRadius:
                                BorderRadius.circular(AppSpacing.radiusSm),
                          ),
                          child: const Icon(
                            Icons.assignment_outlined,
                            color: AppColors.primary,
                            size: 20,
                          ),
                        ),
                        const SizedBox(width: AppSpacing.sm),
                        Flexible(
                          child: Text(
                            'Task Overview',
                            style: AppTypography.headlineMd,
                          ),
                        ),
                      ],
                    ),
                    TextButton(
                      onPressed: () {
                        if (onNavigateToTasks != null) {
                          onNavigateToTasks!();
                        } else {
                          Navigator.of(context).push(
                            MaterialPageRoute(
                              builder: (_) => const AdminTaskScreen(),
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
                            'View All Tasks',
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

            // Async data handling
            tasksAsync.when(
              loading: () => _buildLoadingState(),
              error: (err, _) => _buildErrorState(ref, err.toString()),
              data: (tasks) => _buildDataContent(context, tasks),
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
              "Loading today's tasks...",
              style: TextStyle(
                color: AppColors.outline,
                fontSize: 12,
              ),
            ),
          ],
        ),
      ),
    );
  }

  Widget _buildErrorState(WidgetRef ref, String error) {
    return SizedBox(
      height: 180,
      child: Center(
        child: Padding(
          padding: const EdgeInsets.symmetric(horizontal: AppSpacing.md),
          child: Column(
            mainAxisAlignment: MainAxisAlignment.center,
            children: [
              const Icon(
                Icons.error_outline,
                color: AppColors.error,
                size: 28,
              ),
              const SizedBox(height: AppSpacing.xs),
              Text(
                'Unable to load task metrics',
                style: AppTypography.labelCaps.copyWith(
                  color: AppColors.error,
                  fontWeight: FontWeight.w600,
                ),
              ),
              const SizedBox(height: 2),
              Text(
                error,
                style: AppTypography.bodySm.copyWith(
                  color: AppColors.onSurfaceVariant,
                  fontSize: 11,
                ),
                maxLines: 2,
                overflow: TextOverflow.ellipsis,
                textAlign: TextAlign.center,
              ),
              const SizedBox(height: AppSpacing.xs),
              OutlinedButton.icon(
                onPressed: () =>
                    ref.read(adminTasksProvider.notifier).fetchTasks(),
                icon: const Icon(Icons.refresh, size: 14),
                label: const Text('Retry'),
                style: OutlinedButton.styleFrom(
                  padding: const EdgeInsets.symmetric(
                    horizontal: AppSpacing.sm,
                    vertical: AppSpacing.base,
                  ),
                ),
              ),
            ],
          ),
        ),
      ),
    );
  }

  Widget _buildEmptyState(BuildContext context) {
    return Container(
      height: 180,
      alignment: Alignment.center,
      child: Column(
        mainAxisAlignment: MainAxisAlignment.center,
        children: [
          const Icon(
            Icons.task_alt_outlined,
            size: 36,
            color: AppColors.outlineVariant,
          ),
          const SizedBox(height: AppSpacing.xs),
          Text(
            'No pending tasks for today',
            style: AppTypography.bodySm.copyWith(
              color: AppColors.onSurfaceVariant,
              fontWeight: FontWeight.w600,
            ),
          ),
          const SizedBox(height: 2),
          Text(
            'All staff tasks are up to date for today.',
            style: AppTypography.bodySm.copyWith(
              color: AppColors.outline,
              fontSize: 11,
            ),
          ),
        ],
      ),
    );
  }

  Widget _buildDataContent(BuildContext context, List<TaskItem> allTasks) {
    // Strictly filter to operational tasks: today's incomplete + previous dates' incomplete carry-forward
    final operationalTasks =
        TaskOperationalFilter.filterOperationalTasks(allTasks);

    if (operationalTasks.isEmpty) {
      return _buildEmptyState(context);
    }

    final totalTasks = operationalTasks.length;
    final now = DateTime.now();

    // Overdue tasks: carry forward from previous days + today's tasks whose deadline passed.
    // Surgeries are static schedule entries and must NEVER be counted as overdue.
    final overdueTasks = operationalTasks.where((t) {
      if (t.isSurgeryTask) return false;
      if (TaskOperationalFilter.isOverdueCarryForward(t, now)) return true;
      final s = t.status.toLowerCase();
      if (s == 'completed' || s == 'cancelled') return false;
      if (s == 'overdue') return true;
      return t.dueDate != null && t.dueDate!.isBefore(now);
    }).length;

    // Carry forward tasks specifically from previous dates
    final carryForwardTasks = operationalTasks
        .where((t) => TaskOperationalFilter.isOverdueCarryForward(t, now))
        .length;

    // In Progress tasks
    final inProgressTasks = operationalTasks.where((t) {
      final s = t.status.toLowerCase();
      return s == 'in_progress';
    }).length;

    // Pending tasks
    final pendingTasks = operationalTasks.where((t) {
      final s = t.status.toLowerCase();
      return s == 'pending';
    }).length;

    void handleCardTap() {
      if (onNavigateToTasks != null) {
        onNavigateToTasks!();
      } else {
        Navigator.of(context).push(
          MaterialPageRoute(
            builder: (_) => const AdminTaskScreen(),
          ),
        );
      }
    }

    return Column(
      crossAxisAlignment: CrossAxisAlignment.stretch,
      children: [
        // Top KPI summary tiles
        Row(
          children: [
            Expanded(
              child: _MetricTile(
                title: "Today's Tasks",
                value: '$totalTasks',
                subtitle: carryForwardTasks > 0
                    ? '$carryForwardTasks overdue from previous days'
                    : 'All scheduled for today',
                icon: Icons.assignment_outlined,
                iconColor: AppColors.primary,
                bgColor: AppColors.primaryContainer.withValues(alpha: 0.12),
                onTap: handleCardTap,
              ),
            ),
            const SizedBox(width: AppSpacing.sm),
            Expanded(
              child: _MetricTile(
                title: 'Pending Today',
                value: '$pendingTasks',
                subtitle: inProgressTasks > 0
                    ? '$inProgressTasks in progress'
                    : 'Awaiting start',
                icon: Icons.pending_actions_outlined,
                iconColor: AppColors.secondary,
                bgColor: AppColors.secondary.withValues(alpha: 0.12),
                onTap: handleCardTap,
              ),
            ),
          ],
        ),
        const SizedBox(height: AppSpacing.md),

        // Status breakdown container
        Container(
          padding: const EdgeInsets.symmetric(
            horizontal: AppSpacing.sm,
            vertical: AppSpacing.xs,
          ),
          decoration: BoxDecoration(
            color: AppColors.surfaceContainerLow,
            borderRadius: BorderRadius.circular(AppSpacing.radiusMd),
          ),
          child: Column(
            crossAxisAlignment: CrossAxisAlignment.stretch,
            children: [
              Wrap(
                alignment: WrapAlignment.spaceBetween,
                crossAxisAlignment: WrapCrossAlignment.center,
                spacing: AppSpacing.sm,
                runSpacing: AppSpacing.xs,
                children: [
                  _StatusPill(
                    label: 'In Progress: $inProgressTasks',
                    color: AppColors.primaryContainer,
                  ),
                  _StatusPill(
                    label: 'Pending: $pendingTasks',
                    color: AppColors.secondary,
                  ),
                  _StatusPill(
                    label: 'Overdue: $overdueTasks',
                    color:
                        overdueTasks > 0 ? AppColors.error : AppColors.outline,
                  ),
                ],
              ),
              const SizedBox(height: AppSpacing.xs),

              // Proportional status distribution bar
              ClipRRect(
                borderRadius: BorderRadius.circular(2),
                child: SizedBox(
                  height: 4,
                  child: Row(
                    children: [
                      if (totalTasks == 0)
                        Expanded(
                            child: Container(color: AppColors.outlineVariant))
                      else ...[
                        if (inProgressTasks > 0)
                          Expanded(
                            flex: inProgressTasks,
                            child: Container(color: AppColors.primaryContainer),
                          ),
                        if (pendingTasks > 0)
                          Expanded(
                            flex: pendingTasks,
                            child: Container(color: AppColors.secondary),
                          ),
                        if (overdueTasks > 0)
                          Expanded(
                            flex: overdueTasks,
                            child: Container(color: AppColors.error),
                          ),
                      ],
                    ],
                  ),
                ),
              ),
            ],
          ),
        ),
        const SizedBox(height: AppSpacing.xs),

        // Context footer
        Padding(
          padding: const EdgeInsets.symmetric(horizontal: 2),
          child: Wrap(
            alignment: WrapAlignment.spaceBetween,
            crossAxisAlignment: WrapCrossAlignment.center,
            spacing: AppSpacing.xs,
            runSpacing: 2,
            children: [
              Text(
                'Scope: Incomplete today & overdue carry-forward',
                style: AppTypography.bodySm.copyWith(
                  color: AppColors.onSurfaceVariant,
                  fontSize: 11,
                ),
              ),
              Text(
                'Full history in View All Tasks',
                style: AppTypography.labelCaps.copyWith(
                  color: AppColors.outline,
                  fontSize: 10,
                ),
              ),
            ],
          ),
        ),
      ],
    );
  }
}

class _StatusPill extends StatelessWidget {
  const _StatusPill({
    required this.label,
    required this.color,
  });

  final String label;
  final Color color;

  @override
  Widget build(BuildContext context) {
    return Row(
      mainAxisSize: MainAxisSize.min,
      children: [
        Container(
          width: 8,
          height: 8,
          decoration: BoxDecoration(
            color: color,
            shape: BoxShape.circle,
          ),
        ),
        const SizedBox(width: 4),
        Text(
          label,
          style: AppTypography.bodySm.copyWith(
            fontSize: 11,
            fontWeight: FontWeight.w600,
          ),
        ),
      ],
    );
  }
}

class _MetricTile extends StatelessWidget {
  const _MetricTile({
    required this.title,
    required this.value,
    required this.subtitle,
    required this.icon,
    required this.iconColor,
    required this.bgColor,
    this.onTap,
  });

  final String title;
  final String value;
  final String subtitle;
  final IconData icon;
  final Color iconColor;
  final Color bgColor;
  final VoidCallback? onTap;

  @override
  Widget build(BuildContext context) {
    return Material(
      color: Colors.transparent,
      child: InkWell(
        onTap: onTap,
        borderRadius: BorderRadius.circular(AppSpacing.radiusMd),
        child: Container(
          padding: const EdgeInsets.all(AppSpacing.sm),
          decoration: BoxDecoration(
            color: AppColors.surfaceContainerLowest,
            borderRadius: BorderRadius.circular(AppSpacing.radiusMd),
            border: Border.all(color: AppColors.outlineVariant),
          ),
          child: Column(
            crossAxisAlignment: CrossAxisAlignment.start,
            children: [
              Row(
                mainAxisAlignment: MainAxisAlignment.spaceBetween,
                children: [
                  Flexible(
                    child: Text(
                      title,
                      style: AppTypography.labelCaps.copyWith(
                        color: AppColors.onSurfaceVariant,
                        fontSize: 10,
                        fontWeight: FontWeight.w600,
                      ),
                      overflow: TextOverflow.ellipsis,
                    ),
                  ),
                  Container(
                    padding: const EdgeInsets.all(4),
                    decoration: BoxDecoration(
                      color: bgColor,
                      borderRadius: BorderRadius.circular(AppSpacing.radiusSm),
                    ),
                    child: Icon(icon, size: 14, color: iconColor),
                  ),
                ],
              ),
              const SizedBox(height: AppSpacing.xs),
              Text(
                value,
                style: AppTypography.headlineMd.copyWith(
                  color: AppColors.onSurface,
                  fontWeight: FontWeight.bold,
                  fontSize: 22,
                ),
                maxLines: 1,
                overflow: TextOverflow.ellipsis,
              ),
              const SizedBox(height: 2),
              Text(
                subtitle,
                style: AppTypography.bodySm.copyWith(
                  color: AppColors.onSurfaceVariant,
                  fontSize: 10,
                ),
                maxLines: 1,
                overflow: TextOverflow.ellipsis,
              ),
            ],
          ),
        ),
      ),
    );
  }
}
