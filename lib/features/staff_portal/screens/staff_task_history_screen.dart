import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:intl/intl.dart';

import '../../../core/theme/app_colors.dart';
import '../../../core/theme/app_spacing.dart';
import '../../../core/theme/app_typography.dart';
import '../../auth/providers/auth_provider.dart';
import '../../staff/providers/task_provider.dart';

class StaffTaskHistoryScreen extends ConsumerWidget {
  const StaffTaskHistoryScreen({super.key});

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    final currentUser = ref.watch(currentUserProvider);
    if (currentUser == null) return const Center(child: CircularProgressIndicator());

    final tasksAsync = ref.watch(staffTasksProvider(currentUser.id));
    return Scaffold(
      appBar: AppBar(title: const Text('Task History'), backgroundColor: AppColors.surface),
      backgroundColor: AppColors.background,
      body: tasksAsync.when(
        data: (tasks) {
          final completedTasks = tasks.where((task) => task.status == 'completed').toList();
          if (completedTasks.isEmpty) {
            return const Center(child: Text('No completed tasks yet.'));
          }

          return ListView.separated(
            padding: const EdgeInsets.all(AppSpacing.md),
            itemCount: completedTasks.length,
            separatorBuilder: (_, __) => const SizedBox(height: AppSpacing.sm),
            itemBuilder: (context, index) {
              final task = completedTasks[index];
              return Card(
                child: Padding(
                  padding: const EdgeInsets.all(AppSpacing.md),
                  child: Column(
                    crossAxisAlignment: CrossAxisAlignment.start,
                    children: [
                      Row(
                        children: [
                          Expanded(
                            child: Text(task.title, style: AppTypography.bodyLg.copyWith(fontWeight: FontWeight.w600)),
                          ),
                          const Icon(Icons.check_circle, color: Colors.green),
                        ],
                      ),
                      if (task.description != null && task.description!.trim().isNotEmpty) ...[
                        const SizedBox(height: AppSpacing.xs),
                        Text(task.description!),
                      ],
                      const SizedBox(height: AppSpacing.sm),
                      Text('Status: Completed', style: AppTypography.bodySm.copyWith(color: Colors.green, fontWeight: FontWeight.w600)),
                      if (task.completedAt != null)
                        Text('Completed: ${DateFormat('MMM d, yyyy, h:mm a').format(task.completedAt!)}'),
                      Text('Assigned: ${DateFormat('MMM d, yyyy').format(task.createdAt)}'),
                    ],
                  ),
                ),
              );
            },
          );
        },
        loading: () => const Center(child: CircularProgressIndicator()),
        error: (error, stackTrace) => Center(child: Text('Unable to load task history: $error')),
      ),
    );
  }
}
