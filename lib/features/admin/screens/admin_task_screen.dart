import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:intl/intl.dart';

import '../../../core/theme/app_spacing.dart';
import '../../auth/providers/auth_provider.dart';
import '../../staff/providers/task_provider.dart';
import '../models/user_profile.dart';
import '../providers/users_provider.dart';
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
                _showCreateTaskDialog(context, ref, currentUser.id, usersAsync);
              }
            },
          ),
          const SizedBox(width: AppSpacing.xs),
        ],
      ),
      body: tasksAsync.when(
        data: (tasks) {
          if (tasks.isEmpty) {
            return const Center(child: Text('No tasks found.'));
          }
          final users = usersAsync.valueOrNull ?? <UserProfile>[];
          return ListView.builder(
            padding: const EdgeInsets.all(AppSpacing.md),
            itemCount: tasks.length,
            itemBuilder: (context, index) {
              final task = tasks[index];
              final assignedStaff = users.where((u) => u.id == task.assignedTo).firstOrNull;
              final staffLabel = assignedStaff?.fullName ?? task.assignedTo;

              return Card(
                margin: const EdgeInsets.only(bottom: AppSpacing.sm),
                child: ListTile(
                  title: Text(task.title),
                  subtitle: Text(
                    'Assigned to: $staffLabel\nStatus: ${task.status.toUpperCase()}${task.dueDate != null ? ' • Due: ${DateFormat('MMM d, yyyy').format(task.dueDate!)}' : ''}',
                  ),
                  trailing: Text(
                    task.priority.toUpperCase(),
                    style: TextStyle(
                      color: task.priority == 'critical'
                          ? Colors.red
                          : task.priority == 'high'
                              ? Colors.orange
                              : Colors.grey,
                      fontWeight: FontWeight.bold,
                    ),
                  ),
                  isThreeLine: true,
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

  void _showCreateTaskDialog(
    BuildContext context,
    WidgetRef ref,
    String adminId,
    AsyncValue<List<UserProfile>> usersAsync,
  ) {
    final titleController = TextEditingController();
    final descriptionController = TextEditingController();
    String? selectedStaffId;
    String selectedPriority = 'medium';
    DateTime? dueDate;

    final staffUsers = usersAsync.valueOrNull
            ?.where((user) => user.role == 'staff' && user.isActive)
            .toList() ??
        <UserProfile>[];

    showDialog(
      context: context,
      builder: (dialogContext) {
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
                      decoration: const InputDecoration(labelText: 'Task title *'),
                    ),
                    const SizedBox(height: AppSpacing.md),
                    TextField(
                      controller: descriptionController,
                      minLines: 2,
                      maxLines: 4,
                      decoration: const InputDecoration(labelText: 'Description (optional)'),
                    ),
                    const SizedBox(height: AppSpacing.md),
                    DropdownButtonFormField<String>(
                      initialValue: staffUsers.any((user) => user.id == selectedStaffId)
                          ? selectedStaffId
                          : null,
                      decoration: const InputDecoration(labelText: 'Assign to staff *'),
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
                            label: Text(
                              dueDate != null
                                  ? DateFormat('MMM d, yyyy').format(dueDate!)
                                  : 'Due date (optional)',
                            ),
                          ),
                        ),
                      ],
                    ),
                  ],
                ),
              ),
              actions: [
                TextButton(
                  onPressed: () => Navigator.pop(dialogContext),
                  child: const Text('Cancel'),
                ),
                FilledButton(
                  onPressed: () async {
                    final trimmedTitle = titleController.text.trim();
                    if (trimmedTitle.isEmpty ||
                        selectedStaffId == null ||
                        selectedStaffId!.isEmpty) {
                      ScaffoldMessenger.of(dialogContext).showSnackBar(
                        const SnackBar(
                          content: Text('Task title and assigned staff are required.'),
                        ),
                      );
                      return;
                    }

                    try {
                      await ref.read(adminTasksProvider.notifier).createTask(
                        title: trimmedTitle,
                        description: descriptionController.text.trim().isEmpty
                            ? null
                            : descriptionController.text.trim(),
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
