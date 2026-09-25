import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:intl/intl.dart';

import '../../../core/theme/app_spacing.dart';
import '../../../core/theme/app_typography.dart';
import '../../admin/models/user_profile.dart';
import '../../admin/providers/users_provider.dart';
import '../../auth/providers/auth_provider.dart';
import '../../staff/providers/task_provider.dart';
import 'admin_task_history_screen.dart';

class AdminTaskScreen extends ConsumerWidget {
  const AdminTaskScreen({super.key});

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    final tasksAsync = ref.watch(adminTasksProvider);
    final currentUser = ref.watch(currentUserProvider);
    final usersAsync = ref.watch(usersProvider);

    return Scaffold(
      appBar: AppBar(
        title: const Text('All Tasks (Admin)'),
        actions: [
          IconButton(
            tooltip: 'Task history and performance',
            icon: const Icon(Icons.analytics_outlined),
            onPressed: () {
              Navigator.of(context).push(
                MaterialPageRoute(builder: (_) => const AdminTaskHistoryScreen()),
              );
            },
          ),
          IconButton(
            icon: const Icon(Icons.add),
            onPressed: currentUser == null
                ? null
                : () => _showCreateTaskDialog(context, ref, currentUser.id, usersAsync),
          )
        ],
      ),
      body: tasksAsync.when(
        data: (tasks) {
          if (tasks.isEmpty) {
            return const Center(child: Text('No tasks assigned yet.'));
          }

          return ListView.builder(
            padding: const EdgeInsets.all(AppSpacing.md),
            itemCount: tasks.length,
            itemBuilder: (context, index) {
              final task = tasks[index];
              final statusColor = task.status == 'completed'
                  ? Colors.green
                  : task.status == 'pending'
                      ? Colors.orange
                      : task.status == 'in_progress'
                          ? Colors.blue
                          : Colors.red;

              return Card(
                margin: const EdgeInsets.only(bottom: AppSpacing.sm),
                child: Padding(
                  padding: const EdgeInsets.all(AppSpacing.md),
                  child: Column(
                    crossAxisAlignment: CrossAxisAlignment.start,
                    children: [
                      Row(
                        crossAxisAlignment: CrossAxisAlignment.start,
                        children: [
                          Expanded(
                            child: Text(task.title, style: AppTypography.bodyLg.copyWith(fontWeight: FontWeight.w600)),
                          ),
                          Container(
                            padding: const EdgeInsets.symmetric(horizontal: AppSpacing.sm, vertical: AppSpacing.xs),
                            decoration: BoxDecoration(
                              color: statusColor.withValues(alpha: 0.12),
                              borderRadius: BorderRadius.circular(AppSpacing.radiusSm),
                            ),
                            child: Text(
                              task.statusLabel,
                              style: AppTypography.labelCaps.copyWith(color: statusColor),
                            ),
                          ),
                        ],
                      ),
                      const SizedBox(height: AppSpacing.sm),
                      Text('Staff: ${task.staffName ?? 'Unknown staff'}'),
                      if (task.description != null && task.description!.trim().isNotEmpty) ...[
                        const SizedBox(height: AppSpacing.xs),
                        Text(task.description!),
                      ],
                      const SizedBox(height: AppSpacing.xs),
                      Text(
                        'Priority: ${task.priority.toUpperCase()} • Due: ${task.dueDate != null ? DateFormat('MMM d, yyyy').format(task.dueDate!) : 'No due date'}',
                      ),
                    ],
                  ),
                ),
              );
            },
          );
        },
        loading: () => const Center(child: CircularProgressIndicator()),
        error: (e, st) => Center(child: Text('Error: $e')),
      ),
    );
  }

  void _showCreateTaskDialog(BuildContext context, WidgetRef ref, String adminId, AsyncValue<List<UserProfile>> usersAsync) {
    final titleController = TextEditingController();
    final descriptionController = TextEditingController();
    String? selectedStaffId;
    String selectedPriority = 'medium';
    DateTime? dueDate;

    showDialog(
      context: context,
      builder: (dialogContext) {
        final staffUsers = usersAsync.valueOrNull
            ?.where((user) => user.role == 'staff' && user.isActive)
            .toList() ?? <UserProfile>[];

        return StatefulBuilder(
          builder: (context, setState) {
            return AlertDialog(
              title: const Text('Create Task'),
              content: SingleChildScrollView(
                child: Column(
                  mainAxisSize: MainAxisSize.min,
                  crossAxisAlignment: CrossAxisAlignment.start,
                  children: [
                    TextField(
                      controller: titleController,
                      decoration: const InputDecoration(labelText: 'Task title'),
                    ),
                    const SizedBox(height: AppSpacing.md),
                    TextField(
                      controller: descriptionController,
                      minLines: 2,
                      maxLines: 4,
                      decoration: const InputDecoration(labelText: 'Details'),
                    ),
                    const SizedBox(height: AppSpacing.md),
                    DropdownButtonFormField<String>(
                      initialValue: staffUsers.any((user) => user.id == selectedStaffId) ? selectedStaffId : null,
                      decoration: const InputDecoration(labelText: 'Assign to staff'),
                      items: staffUsers
                          .map((user) => DropdownMenuItem(
                                value: user.id,
                                child: Text(user.fullName),
                              ))
                          .toList(),
                      onChanged: (value) => setState(() => selectedStaffId = value),
                      hint: const Text('Select staff member'),
                    ),
                    const SizedBox(height: AppSpacing.md),
                    DropdownButtonFormField<String>(
                      initialValue: selectedPriority,
                      decoration: const InputDecoration(labelText: 'Priority'),
                      items: const [
                        DropdownMenuItem(value: 'low', child: Text('Low')),
                        DropdownMenuItem(value: 'medium', child: Text('Medium')),
                        DropdownMenuItem(value: 'high', child: Text('High')),
                        DropdownMenuItem(value: 'critical', child: Text('Critical')),
                      ],
                      onChanged: (value) => setState(() => selectedPriority = value ?? 'medium'),
                    ),
                    const SizedBox(height: AppSpacing.md),
                    Row(
                      children: [
                        Expanded(
                          child: OutlinedButton.icon(
                            onPressed: () async {
                              final date = await showDatePicker(
                                context: dialogContext,
                                initialDate: DateTime.now(),
                                firstDate: DateTime.now(),
                                lastDate: DateTime.now().add(const Duration(days: 3650)),
                              );
                              if (date != null) setState(() => dueDate = date);
                            },
                            icon: const Icon(Icons.calendar_today),
                            label: Text(dueDate != null ? DateFormat('MMM d, yyyy').format(dueDate!) : 'Due date'),
                          ),
                        ),
                      ],
                    ),
                  ],
                ),
              ),
              actions: [
                TextButton(onPressed: () => Navigator.pop(dialogContext), child: const Text('Cancel')),
                FilledButton(
                  onPressed: () async {
                    final trimmedTitle = titleController.text.trim();
                    if (trimmedTitle.isEmpty || selectedStaffId == null || selectedStaffId!.isEmpty) {
                      ScaffoldMessenger.of(dialogContext).showSnackBar(
                        const SnackBar(content: Text('Task title and assigned staff are required.')),
                      );
                      return;
                    }

                    try {
                      await ref.read(adminTasksProvider.notifier).createTask(
                        title: trimmedTitle,
                        description: descriptionController.text.trim(),
                        assignedTo: selectedStaffId!,
                        adminId: adminId,
                        dueDate: dueDate,
                        priority: selectedPriority,
                      );
                      if (dialogContext.mounted) Navigator.pop(dialogContext);
                    } catch (e) {
                      if (dialogContext.mounted) {
                        ScaffoldMessenger.of(dialogContext).showSnackBar(
                          SnackBar(content: Text('Error creating task: $e')),
                        );
                      }
                    }
                  },
                  child: const Text('Create'),
                ),
              ],
            );
          },
        );
      },
    );
  }
}
