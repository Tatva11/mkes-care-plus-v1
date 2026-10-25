import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:intl/intl.dart';

import '../../../core/theme/app_breakpoints.dart';
import '../../../core/theme/app_colors.dart';
import '../../../core/theme/app_spacing.dart';
import '../../../core/theme/app_typography.dart';
import '../../../shared/widgets/adaptive_dialog_shell.dart';
import '../../auth/providers/auth_provider.dart';
import '../../staff/models/task_item.dart';
import '../../staff/providers/task_provider.dart';
import '../models/user_profile.dart';
import '../providers/users_provider.dart';

/// Reusable dialog for creating or editing tasks by administrators.
class TaskFormDialog extends ConsumerStatefulWidget {
  final TaskItem? task;
  final String? initialStaffId;

  const TaskFormDialog({
    super.key,
    this.task,
    this.initialStaffId,
  });

  bool get isEditing => task != null;

  @override
  ConsumerState<TaskFormDialog> createState() => _TaskFormDialogState();
}

class _TaskFormDialogState extends ConsumerState<TaskFormDialog> {
  final _formKey = GlobalKey<FormState>();
  late final TextEditingController _titleController;
  late final TextEditingController _descriptionController;
  late final TextEditingController _noteController;

  String? _selectedStaffId;
  late String _selectedPriority;
  late String _selectedStatus;
  DateTime? _dueDate;
  bool _isSubmitting = false;

  @override
  void initState() {
    super.initState();
    final task = widget.task;
    _titleController = TextEditingController(text: task?.title ?? '');
    _descriptionController =
        TextEditingController(text: task?.description ?? '');
    _noteController = TextEditingController();

    _selectedStaffId = task?.assignedTo ?? widget.initialStaffId;
    _selectedPriority = (task?.priority ?? 'medium').toLowerCase();
    if (!TaskItem.validPriorities.contains(_selectedPriority)) {
      _selectedPriority = 'medium';
    }

    _selectedStatus = (task?.status ?? 'pending').toLowerCase();
    if (!TaskItem.validStatuses.contains(_selectedStatus)) {
      _selectedStatus = 'pending';
    }

    _dueDate = task?.dueDate;
  }

  @override
  void dispose() {
    _titleController.dispose();
    _descriptionController.dispose();
    _noteController.dispose();
    super.dispose();
  }

  @override
  Widget build(BuildContext context) {
    final usersAsync = ref.watch(usersProvider);
    final currentUser = ref.watch(currentUserProvider);

    final staffUsers = usersAsync.valueOrNull
            ?.where((u) =>
                u.role == 'staff' && (u.isActive || u.id == _selectedStaffId))
            .toList() ??
        <UserProfile>[];

    final dialogConstraints = AdaptiveDialogConstraints.getConstraints(
      context: context,
      maxPhoneWidth: AppBreakpoints.maxDialogWidthMobile,
      maxTabletWidth: 500.0,
      maxDesktopWidth: 500.0,
    );

    return AlertDialog(
      actionsOverflowButtonSpacing: AppSpacing.xs,
      title: Row(
        children: [
          Icon(
            widget.isEditing ? Icons.edit_note : Icons.add_task,
            color: AppColors.primary,
          ),
          const SizedBox(width: AppSpacing.sm),
          Expanded(
            child: Text(
              widget.isEditing ? 'Edit Task' : 'Create & Assign Task',
              style: AppTypography.headlineMd.copyWith(fontSize: 20),
              overflow: TextOverflow.ellipsis,
            ),
          ),
        ],
      ),
      content: ConstrainedBox(
        constraints: BoxConstraints(
          maxWidth: dialogConstraints.maxWidth,
          maxHeight: dialogConstraints.maxHeight,
        ),
        child: Form(
          key: _formKey,
          child: SingleChildScrollView(
            child: Column(
              mainAxisSize: MainAxisSize.min,
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                // Title Field
                TextFormField(
                  controller: _titleController,
                  decoration: const InputDecoration(
                    labelText: 'Task Title *',
                    hintText: 'e.g., Calibrate slit lamp in Room 3',
                  ),
                  validator: (value) {
                    if (value == null || value.trim().isEmpty) {
                      return 'Please enter a task title';
                    }
                    return null;
                  },
                ),
                const SizedBox(height: AppSpacing.md),

                // Description Field
                TextFormField(
                  controller: _descriptionController,
                  maxLines: 3,
                  decoration: const InputDecoration(
                    labelText: 'Description (optional)',
                    hintText: 'Additional details or instructions for staff',
                  ),
                ),
                const SizedBox(height: AppSpacing.md),

                // Staff Assignment Dropdown
                DropdownButtonFormField<String>(
                  initialValue: staffUsers.any((u) => u.id == _selectedStaffId)
                      ? _selectedStaffId
                      : null,
                  decoration: const InputDecoration(
                    labelText: 'Assigned Staff Member *',
                  ),
                  items: staffUsers.map((u) {
                    return DropdownMenuItem<String>(
                      value: u.id,
                      child: Text(
                        u.fullName +
                            (u.department != null ? ' (${u.department})' : ''),
                        overflow: TextOverflow.ellipsis,
                      ),
                    );
                  }).toList(),
                  onChanged: (val) {
                    setState(() => _selectedStaffId = val);
                  },
                  validator: (value) {
                    if (value == null || value.isEmpty) {
                      return 'Please select a staff member';
                    }
                    return null;
                  },
                ),
                const SizedBox(height: AppSpacing.md),

                // Priority and Status (Adaptive: Column on narrow screens, Row on wide screens)
                if (widget.isEditing)
                  if (dialogConstraints.maxWidth < 420)
                    Column(
                      crossAxisAlignment: CrossAxisAlignment.stretch,
                      mainAxisSize: MainAxisSize.min,
                      children: [
                        _buildPriorityDropdown(),
                        const SizedBox(height: AppSpacing.sm),
                        _buildStatusDropdown(),
                      ],
                    )
                  else
                    Row(
                      crossAxisAlignment: CrossAxisAlignment.start,
                      children: [
                        Expanded(child: _buildPriorityDropdown()),
                        const SizedBox(width: AppSpacing.md),
                        Expanded(child: _buildStatusDropdown()),
                      ],
                    )
                else
                  _buildPriorityDropdown(),
                const SizedBox(height: AppSpacing.md),

                // Due Date Picker
                Row(
                  children: [
                    Expanded(
                      child: OutlinedButton.icon(
                        onPressed: () async {
                          final now = DateTime.now();
                          final picked = await showDatePicker(
                            context: context,
                            initialDate: _dueDate ?? now,
                            firstDate: now.subtract(const Duration(days: 365)),
                            lastDate: now.add(const Duration(days: 3650)),
                          );
                          if (picked != null) {
                            setState(() => _dueDate = picked);
                          }
                        },
                        icon: const Icon(Icons.calendar_today, size: 18),
                        label: Text(
                          _dueDate != null
                              ? 'Due: ${DateFormat('MMM d, yyyy').format(_dueDate!)}'
                              : 'Set Due Date (optional)',
                          overflow: TextOverflow.ellipsis,
                        ),
                      ),
                    ),
                    if (_dueDate != null) ...[
                      const SizedBox(width: AppSpacing.xs),
                      IconButton(
                        tooltip: 'Clear due date',
                        icon: const Icon(Icons.clear, size: 20),
                        onPressed: () => setState(() => _dueDate = null),
                      ),
                    ],
                  ],
                ),

                // Admin Note (for edits)
                if (widget.isEditing) ...[
                  const SizedBox(height: AppSpacing.md),
                  TextFormField(
                    controller: _noteController,
                    decoration: const InputDecoration(
                      labelText: 'Change Note (optional)',
                      hintText: 'Brief explanation of changes for history log',
                    ),
                  ),
                ],
              ],
            ),
          ),
        ),
      ),
      actions: [
        TextButton(
          onPressed: _isSubmitting ? null : () => Navigator.of(context).pop(),
          child: const Text('Cancel'),
        ),
        FilledButton(
          onPressed: _isSubmitting ? null : () => _handleSave(currentUser?.id),
          child: _isSubmitting
              ? const SizedBox(
                  width: 18,
                  height: 18,
                  child: CircularProgressIndicator(
                      strokeWidth: 2, color: Colors.white),
                )
              : Text(widget.isEditing ? 'Save Changes' : 'Assign Task'),
        ),
      ],
    );
  }

  Future<void> _handleSave(String? adminId) async {
    if (!_formKey.currentState!.validate()) return;
    if (_selectedStaffId == null || _selectedStaffId!.isEmpty) return;

    if (adminId == null) {
      ScaffoldMessenger.of(context).showSnackBar(
        const SnackBar(
            content: Text('Error: No active administrator session found.')),
      );
      return;
    }

    setState(() => _isSubmitting = true);

    try {
      final oldStaffId = widget.task?.assignedTo;
      final newStaffId = _selectedStaffId!;

      if (widget.isEditing) {
        await ref.read(adminTasksProvider.notifier).updateTask(
              taskId: widget.task!.id,
              adminId: adminId,
              title: _titleController.text.trim(),
              description: _descriptionController.text.trim().isEmpty
                  ? null
                  : _descriptionController.text.trim(),
              assignedTo: newStaffId,
              dueDate: _dueDate,
              priority: _selectedPriority,
              status: _selectedStatus,
              note: _noteController.text.trim().isEmpty
                  ? null
                  : _noteController.text.trim(),
            );

        // Cross-refresh staff providers
        ref.read(staffTasksProvider(newStaffId).notifier).fetchTasks();
        if (oldStaffId != null && oldStaffId != newStaffId) {
          ref.read(staffTasksProvider(oldStaffId).notifier).fetchTasks();
        }

        if (mounted) {
          ScaffoldMessenger.of(context).showSnackBar(
            const SnackBar(content: Text('Task updated successfully!')),
          );
          Navigator.of(context).pop(true);
        }
      } else {
        await ref.read(adminTasksProvider.notifier).createTask(
              title: _titleController.text.trim(),
              description: _descriptionController.text.trim().isEmpty
                  ? null
                  : _descriptionController.text.trim(),
              assignedTo: newStaffId,
              adminId: adminId,
              dueDate: _dueDate,
              priority: _selectedPriority,
            );

        // Cross-refresh staff provider
        ref.read(staffTasksProvider(newStaffId).notifier).fetchTasks();

        if (mounted) {
          ScaffoldMessenger.of(context).showSnackBar(
            const SnackBar(
                content: Text('Task created and assigned successfully!')),
          );
          Navigator.of(context).pop(true);
        }
      }
    } catch (e) {
      if (mounted) {
        ScaffoldMessenger.of(context).showSnackBar(
          SnackBar(content: Text('Failed to save task: $e')),
        );
      }
    } finally {
      if (mounted) {
        setState(() => _isSubmitting = false);
      }
    }
  }

  Widget _buildPriorityDropdown() {
    return DropdownButtonFormField<String>(
      initialValue: _selectedPriority,
      isExpanded: true,
      decoration: const InputDecoration(
        labelText: 'Priority',
      ),
      items: const [
        DropdownMenuItem(value: 'low', child: Text('Low')),
        DropdownMenuItem(value: 'medium', child: Text('Medium')),
        DropdownMenuItem(value: 'high', child: Text('High')),
        DropdownMenuItem(value: 'critical', child: Text('Critical')),
      ],
      onChanged: (val) {
        if (val != null) {
          setState(() => _selectedPriority = val);
        }
      },
    );
  }

  Widget _buildStatusDropdown() {
    return DropdownButtonFormField<String>(
      initialValue: _selectedStatus,
      isExpanded: true,
      decoration: const InputDecoration(
        labelText: 'Status',
      ),
      items: const [
        DropdownMenuItem(value: 'pending', child: Text('Pending')),
        DropdownMenuItem(value: 'in_progress', child: Text('In Progress')),
        DropdownMenuItem(value: 'completed', child: Text('Completed')),
        DropdownMenuItem(value: 'overdue', child: Text('Overdue')),
        DropdownMenuItem(value: 'cancelled', child: Text('Cancelled')),
      ],
      onChanged: (val) {
        if (val != null) {
          setState(() => _selectedStatus = val);
        }
      },
    );
  }
}
