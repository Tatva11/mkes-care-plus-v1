import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:intl/intl.dart';

import '../../../core/theme/app_colors.dart';
import '../../../core/theme/app_spacing.dart';
import '../../../core/theme/app_typography.dart';
import '../../auth/providers/auth_provider.dart';
import '../../staff/models/task_item.dart';
import '../../staff/providers/task_provider.dart';

/// Screen displaying the current staff member's completed task history and timestamps.
class StaffTaskHistoryScreen extends ConsumerWidget {
  const StaffTaskHistoryScreen({super.key});

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    final currentUser = ref.watch(currentUserProvider);
    if (currentUser == null) {
      return const Center(child: CircularProgressIndicator());
    }

    final isDesktop = MediaQuery.sizeOf(context).width >= 768.0;
    final tasksAsync = ref.watch(staffTasksProvider(currentUser.id));

    return Scaffold(
      appBar: AppBar(
        title: const Text('My Task History'),
        backgroundColor: AppColors.surface,
        actions: [
          IconButton(
            icon: const Icon(Icons.refresh),
            tooltip: 'Refresh',
            onPressed: () => ref
                .read(staffTasksProvider(currentUser.id).notifier)
                .fetchTasks(),
          ),
        ],
      ),
      backgroundColor: AppColors.background,
      body: RefreshIndicator(
        onRefresh: () =>
            ref.read(staffTasksProvider(currentUser.id).notifier).fetchTasks(),
        child: SingleChildScrollView(
          physics: const AlwaysScrollableScrollPhysics(),
          padding: EdgeInsets.all(
            isDesktop ? AppSpacing.marginDesktop : AppSpacing.marginMobile,
          ),
          child: Column(
            crossAxisAlignment: CrossAxisAlignment.start,
            children: [
              Text(
                'Completed Task History',
                style: AppTypography.displayLg.copyWith(
                  color: AppColors.onBackground,
                  fontSize: isDesktop ? null : 26,
                ),
              ),
              const SizedBox(height: AppSpacing.xs),
              Text(
                'Record of clinical and administrative tasks completed during your shifts.',
                style: AppTypography.bodyLg
                    .copyWith(color: AppColors.onSurfaceVariant),
              ),
              const SizedBox(height: AppSpacing.lg),
              tasksAsync.when(
                loading: () => const Center(
                  child: Padding(
                    padding: EdgeInsets.all(AppSpacing.xl),
                    child: CircularProgressIndicator(),
                  ),
                ),
                error: (error, _) => Center(
                  child: Column(
                    mainAxisSize: MainAxisSize.min,
                    children: [
                      const Icon(Icons.error_outline,
                          size: 48, color: AppColors.error),
                      const SizedBox(height: AppSpacing.sm),
                      Text(
                        'Unable to load task history.',
                        style: AppTypography.headlineMd,
                      ),
                      const SizedBox(height: AppSpacing.xs),
                      Text(
                        '$error',
                        textAlign: TextAlign.center,
                        style: AppTypography.bodySm
                            .copyWith(color: AppColors.onSurfaceVariant),
                      ),
                      const SizedBox(height: AppSpacing.md),
                      FilledButton.icon(
                        onPressed: () => ref
                            .read(staffTasksProvider(currentUser.id).notifier)
                            .fetchTasks(),
                        icon: const Icon(Icons.refresh),
                        label: const Text('Retry'),
                      ),
                    ],
                  ),
                ),
                data: (tasks) {
                  final completedTasks = tasks
                      .where((task) => task.status == 'completed')
                      .toList()
                    ..sort((a, b) {
                      final aTime = a.completedAt ?? a.updatedAt;
                      final bTime = b.completedAt ?? b.updatedAt;
                      return bTime.compareTo(aTime);
                    });

                  if (completedTasks.isEmpty) {
                    return Container(
                      width: double.infinity,
                      padding: const EdgeInsets.all(AppSpacing.xl),
                      decoration: BoxDecoration(
                        color: AppColors.surfaceContainerLowest,
                        borderRadius:
                            BorderRadius.circular(AppSpacing.radiusLg),
                        border: Border.all(color: AppColors.outlineVariant),
                      ),
                      child: Center(
                        child: Column(
                          children: [
                            Icon(
                              Icons.task_alt,
                              size: 48,
                              color: AppColors.outline.withValues(alpha: 0.5),
                            ),
                            const SizedBox(height: AppSpacing.sm),
                            Text(
                              'No completed tasks yet.',
                              style: AppTypography.headlineMd.copyWith(
                                color: AppColors.onSurfaceVariant,
                              ),
                            ),
                            const SizedBox(height: AppSpacing.xs),
                            Text(
                              'Tasks you mark as completed on your shift will appear here.',
                              style: AppTypography.bodyMd.copyWith(
                                color: AppColors.onSurfaceVariant,
                              ),
                            ),
                          ],
                        ),
                      ),
                    );
                  }

                  return Column(
                    crossAxisAlignment: CrossAxisAlignment.start,
                    children: [
                      Row(
                        children: [
                          Text('COMPLETED TASKS',
                              style: AppTypography.labelCaps.copyWith(
                                  color: Colors.green.shade800,
                                  fontWeight: FontWeight.bold)),
                          const SizedBox(width: AppSpacing.xs),
                          Container(
                            padding: const EdgeInsets.symmetric(
                                horizontal: 8, vertical: 2),
                            decoration: BoxDecoration(
                              color: Colors.green.withValues(alpha: 0.15),
                              borderRadius: BorderRadius.circular(10),
                            ),
                            child: Text(
                              '${completedTasks.length}',
                              style: AppTypography.dataMono.copyWith(
                                color: Colors.green.shade800,
                                fontWeight: FontWeight.bold,
                                fontSize: 11,
                              ),
                            ),
                          ),
                        ],
                      ),
                      const SizedBox(height: AppSpacing.sm),
                      ListView.separated(
                        shrinkWrap: true,
                        physics: const NeverScrollableScrollPhysics(),
                        itemCount: completedTasks.length,
                        separatorBuilder: (_, __) =>
                            const SizedBox(height: AppSpacing.sm),
                        itemBuilder: (context, index) {
                          final task = completedTasks[index];
                          return _buildTaskCard(task);
                        },
                      ),
                    ],
                  );
                },
              ),
            ],
          ),
        ),
      ),
    );
  }

  Widget _buildTaskCard(TaskItem task) {
    final completedFormatted = task.completedAt != null
        ? DateFormat('d MMM yyyy, h:mm a').format(task.completedAt!.toLocal())
        : DateFormat('d MMM yyyy, h:mm a').format(task.updatedAt.toLocal());

    final createdFormatted =
        DateFormat('d MMM yyyy').format(task.createdAt.toLocal());

    return Container(
      decoration: BoxDecoration(
        color: AppColors.surfaceContainerLowest,
        borderRadius: BorderRadius.circular(AppSpacing.radiusMd),
        border: Border.all(
          color: Colors.green.withValues(alpha: 0.3),
        ),
        boxShadow: const [
          BoxShadow(
            color: Color(0x08000000),
            blurRadius: 6,
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
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                Expanded(
                  child: Text(
                    task.title,
                    style: AppTypography.bodyLg
                        .copyWith(fontWeight: FontWeight.w600),
                  ),
                ),
                Container(
                  padding:
                      const EdgeInsets.symmetric(horizontal: 8, vertical: 3),
                  decoration: BoxDecoration(
                    color: Colors.green.withValues(alpha: 0.12),
                    borderRadius: BorderRadius.circular(AppSpacing.radiusSm),
                  ),
                  child: Row(
                    mainAxisSize: MainAxisSize.min,
                    children: [
                      Icon(Icons.check_circle,
                          size: 14, color: Colors.green.shade700),
                      const SizedBox(width: 4),
                      Text(
                        'COMPLETED',
                        style: AppTypography.labelCaps.copyWith(
                          color: Colors.green.shade800,
                          fontWeight: FontWeight.bold,
                          fontSize: 10,
                        ),
                      ),
                    ],
                  ),
                ),
              ],
            ),
            if (task.description != null &&
                task.description!.trim().isNotEmpty) ...[
              const SizedBox(height: AppSpacing.xs),
              Text(
                task.description!,
                style: AppTypography.bodyMd
                    .copyWith(color: AppColors.onSurfaceVariant),
              ),
            ],
            const SizedBox(height: AppSpacing.sm),
            const Divider(height: 1, color: AppColors.outlineVariant),
            const SizedBox(height: AppSpacing.sm),
            Wrap(
              spacing: AppSpacing.md,
              runSpacing: 4,
              children: [
                Row(
                  mainAxisSize: MainAxisSize.min,
                  children: [
                    Icon(Icons.check_circle_outline,
                        size: 14, color: Colors.green.shade700),
                    const SizedBox(width: 4),
                    Text(
                      'Completed: $completedFormatted',
                      style: AppTypography.bodySm.copyWith(
                        color: Colors.green.shade800,
                        fontWeight: FontWeight.w600,
                      ),
                    ),
                  ],
                ),
                Row(
                  mainAxisSize: MainAxisSize.min,
                  children: [
                    const Icon(Icons.calendar_today_outlined,
                        size: 14, color: AppColors.outline),
                    const SizedBox(width: 4),
                    Text(
                      'Assigned: $createdFormatted',
                      style: AppTypography.bodySm
                          .copyWith(color: AppColors.onSurfaceVariant),
                    ),
                  ],
                ),
                Row(
                  mainAxisSize: MainAxisSize.min,
                  children: [
                    const Icon(Icons.flag_outlined,
                        size: 14, color: AppColors.outline),
                    const SizedBox(width: 4),
                    Text(
                      'Priority: ${task.priority.toUpperCase()}',
                      style: AppTypography.bodySm
                          .copyWith(color: AppColors.onSurfaceVariant),
                    ),
                  ],
                ),
              ],
            ),
          ],
        ),
      ),
    );
  }
}
