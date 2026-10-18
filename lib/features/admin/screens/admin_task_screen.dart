import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:intl/intl.dart';

import '../../../core/theme/app_colors.dart';
import '../../../core/theme/app_spacing.dart';
import '../../../core/theme/app_typography.dart';
import '../../auth/providers/auth_provider.dart';
import '../../staff/providers/task_provider.dart';
import '../models/user_profile.dart';
import '../providers/users_provider.dart';
import '../widgets/task_form_dialog.dart';
import 'admin_task_history_screen.dart';

class AdminTaskScreen extends ConsumerWidget {
  const AdminTaskScreen({super.key});

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    final tasksAsync = ref.watch(adminTasksProvider);
    final usersAsync = ref.watch(usersProvider);
    final currentUser = ref.watch(currentUserProvider);

    return Scaffold(
      appBar: AppBar(
        title: const Text('All Tasks (Admin)'),
        actions: [
          IconButton(
            icon: const Icon(Icons.refresh),
            tooltip: 'Refresh Tasks',
            onPressed: () => ref.read(adminTasksProvider.notifier).fetchTasks(),
          ),
          OutlinedButton.icon(
            onPressed: () {
              Navigator.of(context).push(
                MaterialPageRoute(
                  builder: (_) => const AdminTaskHistoryScreen(),
                ),
              );
            },
            icon: const Icon(Icons.history, size: 18),
            label: const Text('History'),
            style: OutlinedButton.styleFrom(
              padding: const EdgeInsets.symmetric(horizontal: 12, vertical: 8),
            ),
          ),
          const SizedBox(width: AppSpacing.xs),
          IconButton(
            icon: const Icon(Icons.add),
            tooltip: 'Assign Task',
            onPressed: () {
              if (currentUser != null) {
                showDialog(
                  context: context,
                  builder: (_) => const TaskFormDialog(),
                );
              }
            },
          ),
          const SizedBox(width: AppSpacing.xs),
        ],
      ),
      body: tasksAsync.when(
        data: (tasks) {
          if (tasks.isEmpty) {
            return RefreshIndicator(
              onRefresh: () =>
                  ref.read(adminTasksProvider.notifier).fetchTasks(),
              child: ListView(
                physics: const AlwaysScrollableScrollPhysics(),
                children: [
                  SizedBox(
                    height: MediaQuery.of(context).size.height * 0.4,
                    child: Center(
                      child: Column(
                        mainAxisSize: MainAxisSize.min,
                        children: [
                          const Icon(Icons.assignment_outlined,
                              size: 48, color: AppColors.outline),
                          const SizedBox(height: AppSpacing.sm),
                          Text('No tasks found.',
                              style: AppTypography.headlineMd),
                          const SizedBox(height: AppSpacing.xs),
                          const Text(
                              'Create and assign a new task to get started.'),
                        ],
                      ),
                    ),
                  ),
                ],
              ),
            );
          }
          final users = usersAsync.valueOrNull ?? <UserProfile>[];

          return RefreshIndicator(
            onRefresh: () => ref.read(adminTasksProvider.notifier).fetchTasks(),
            child: ListView.builder(
              physics: const AlwaysScrollableScrollPhysics(),
              padding: const EdgeInsets.all(AppSpacing.md),
              itemCount: tasks.length,
              itemBuilder: (context, index) {
                final task = tasks[index];
                final assignedStaff =
                    users.where((u) => u.id == task.assignedTo).firstOrNull;
                final staffLabel = assignedStaff?.fullName ??
                    task.staffName ??
                    task.assignedTo;

                Color priorityColor;
                if (task.priority == 'critical' || task.priority == 'high') {
                  priorityColor = AppColors.error;
                } else if (task.priority == 'medium') {
                  priorityColor = AppColors.primaryContainer;
                } else {
                  priorityColor = AppColors.outline;
                }

                return Card(
                  margin: const EdgeInsets.only(bottom: AppSpacing.sm),
                  elevation: 0,
                  shape: RoundedRectangleBorder(
                    borderRadius: BorderRadius.circular(AppSpacing.radiusMd),
                    side: const BorderSide(color: AppColors.outlineVariant),
                  ),
                  child: ListTile(
                    contentPadding: const EdgeInsets.symmetric(
                      horizontal: AppSpacing.md,
                      vertical: AppSpacing.xs,
                    ),
                    title: Row(
                      children: [
                        Expanded(
                          child: Text(
                            task.title,
                            style: AppTypography.bodyLg.copyWith(
                              fontWeight: FontWeight.w600,
                              decoration: task.status == 'completed'
                                  ? TextDecoration.lineThrough
                                  : null,
                            ),
                          ),
                        ),
                        Container(
                          padding: const EdgeInsets.symmetric(
                              horizontal: 8, vertical: 2),
                          decoration: BoxDecoration(
                            color: priorityColor.withValues(alpha: 0.15),
                            borderRadius: BorderRadius.circular(12),
                          ),
                          child: Text(
                            task.priority.toUpperCase(),
                            style: AppTypography.labelCaps.copyWith(
                              color: priorityColor,
                              fontSize: 10,
                            ),
                          ),
                        ),
                      ],
                    ),
                    subtitle: Column(
                      crossAxisAlignment: CrossAxisAlignment.start,
                      children: [
                        if (task.description != null &&
                            task.description!.isNotEmpty) ...[
                          const SizedBox(height: 2),
                          Text(
                            task.description!,
                            maxLines: 2,
                            overflow: TextOverflow.ellipsis,
                            style: AppTypography.bodySm.copyWith(
                              color: AppColors.onSurfaceVariant,
                            ),
                          ),
                        ],
                        const SizedBox(height: 4),
                        Row(
                          children: [
                            const Icon(Icons.person_outline,
                                size: 14, color: AppColors.outline),
                            const SizedBox(width: 4),
                            Text(
                              staffLabel,
                              style: AppTypography.bodySm
                                  .copyWith(fontWeight: FontWeight.w600),
                            ),
                            const SizedBox(width: AppSpacing.sm),
                            Container(
                              padding: const EdgeInsets.symmetric(
                                  horizontal: 6, vertical: 1),
                              decoration: BoxDecoration(
                                color: task.status == 'completed'
                                    ? Colors.green.withValues(alpha: 0.15)
                                    : AppColors.surfaceContainerHigh,
                                borderRadius: BorderRadius.circular(8),
                              ),
                              child: Text(
                                task.statusLabel,
                                style: AppTypography.labelCaps.copyWith(
                                  fontSize: 10,
                                  color: task.status == 'completed'
                                      ? Colors.green.shade800
                                      : AppColors.onSurfaceVariant,
                                ),
                              ),
                            ),
                            if (task.dueDate != null) ...[
                              const SizedBox(width: AppSpacing.sm),
                              Icon(
                                Icons.access_time,
                                size: 13,
                                color: task.isOverdue
                                    ? AppColors.error
                                    : AppColors.outline,
                              ),
                              const SizedBox(width: 4),
                              Text(
                                DateFormat('MMM d').format(task.dueDate!),
                                style: AppTypography.bodySm.copyWith(
                                  fontSize: 11,
                                  color: task.isOverdue
                                      ? AppColors.error
                                      : AppColors.outline,
                                  fontWeight: task.isOverdue
                                      ? FontWeight.bold
                                      : FontWeight.normal,
                                ),
                              ),
                            ],
                          ],
                        ),
                      ],
                    ),
                    trailing: IconButton(
                      icon: const Icon(Icons.edit_outlined,
                          color: AppColors.primary),
                      tooltip: 'Edit Task',
                      onPressed: () {
                        showDialog(
                          context: context,
                          builder: (_) => TaskFormDialog(task: task),
                        );
                      },
                    ),
                    onTap: () {
                      showDialog(
                        context: context,
                        builder: (_) => TaskFormDialog(task: task),
                      );
                    },
                  ),
                );
              },
            ),
          );
        },
        loading: () => const Center(child: CircularProgressIndicator()),
        error: (e, st) => Center(
          child: Column(
            mainAxisSize: MainAxisSize.min,
            children: [
              const Icon(Icons.error_outline, size: 48, color: AppColors.error),
              const SizedBox(height: AppSpacing.sm),
              Text('Error loading tasks: $e', textAlign: TextAlign.center),
              const SizedBox(height: AppSpacing.md),
              FilledButton.icon(
                icon: const Icon(Icons.refresh),
                label: const Text('Retry'),
                onPressed: () =>
                    ref.read(adminTasksProvider.notifier).fetchTasks(),
              ),
            ],
          ),
        ),
      ),
    );
  }
}
