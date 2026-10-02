import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:google_fonts/google_fonts.dart';
import 'package:intl/intl.dart';

import '../../../core/theme/app_colors.dart';
import '../../../core/theme/app_spacing.dart';
import '../../../core/theme/app_typography.dart';
import '../../staff/models/task_item.dart';
import '../../staff/providers/task_provider.dart';
import '../models/user_profile.dart';
import '../providers/users_provider.dart';
import '../widgets/task_form_dialog.dart';

/// Screen displaying the complete admin task history and performance breakdown.
///
/// Features:
/// - Summary counts (total, pending, completed, overdue).
/// - Staff filter via [usersProvider].
/// - Status filter ('all', 'pending', 'in_progress', 'completed', 'cancelled').
/// - Date range filter (from/to dates).
/// - Per-staff completion breakdown.
/// - Detailed task records with assignee, priority, created, due, and completion timestamps.
class AdminTaskHistoryScreen extends ConsumerStatefulWidget {
  const AdminTaskHistoryScreen({super.key});

  @override
  ConsumerState<AdminTaskHistoryScreen> createState() =>
      _AdminTaskHistoryScreenState();
}

class _AdminTaskHistoryScreenState
    extends ConsumerState<AdminTaskHistoryScreen> {
  String? _selectedStaffId;
  String _selectedStatus = 'all';
  DateTime? _fromDate;
  DateTime? _toDate;

  @override
  Widget build(BuildContext context) {
    final tasksAsync = ref.watch(adminTasksProvider);
    final usersAsync = ref.watch(usersProvider);
    final staff = (usersAsync.valueOrNull ?? <UserProfile>[])
        .where((user) => user.role == 'staff' && user.isActive)
        .toList();

    return Scaffold(
      appBar: AppBar(
        title: const Text('Task History & Performance'),
        actions: [
          IconButton(
            icon: const Icon(Icons.refresh),
            tooltip: 'Refresh',
            onPressed: () {
              ref.read(adminTasksProvider.notifier).fetchTasks();
              ref.read(usersProvider.notifier).fetchUsers();
            },
          ),
        ],
      ),
      body: tasksAsync.when(
        loading: () => const Center(child: CircularProgressIndicator()),
        error: (error, _) => Center(
          child: Column(
            mainAxisSize: MainAxisSize.min,
            children: [
              const Icon(Icons.error_outline, size: 48, color: AppColors.error),
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
                onPressed: () =>
                    ref.read(adminTasksProvider.notifier).fetchTasks(),
                icon: const Icon(Icons.refresh),
                label: const Text('Retry'),
              ),
            ],
          ),
        ),
        data: (tasks) {
          final filteredTasks = _filterTasks(tasks);
          final total = filteredTasks.length;
          final completed = filteredTasks
              .where((task) => task.status == 'completed')
              .length;
          final pending = filteredTasks
              .where((task) =>
                  task.status == 'pending' || task.status == 'in_progress')
              .length;

          return RefreshIndicator(
            onRefresh: () async {
              await Future.wait([
                ref.read(adminTasksProvider.notifier).fetchTasks(),
                ref.read(usersProvider.notifier).fetchUsers(),
              ]);
            },
            child: ListView(
              padding: const EdgeInsets.all(AppSpacing.md),
              children: [
                _buildSummary(total, pending, completed),
                const SizedBox(height: AppSpacing.lg),
                _buildFilters(staff),
                const SizedBox(height: AppSpacing.lg),
                Text('Completed by Staff', style: AppTypography.headlineMd),
                const SizedBox(height: AppSpacing.sm),
                _buildStaffSummary(filteredTasks, staff),
                const SizedBox(height: AppSpacing.lg),
                Row(
                  children: [
                    Text('Task Records', style: AppTypography.headlineMd),
                    const SizedBox(width: AppSpacing.xs),
                    Container(
                      padding: const EdgeInsets.symmetric(
                          horizontal: 8, vertical: 2),
                      decoration: BoxDecoration(
                        color: AppColors.primaryContainer.withValues(alpha: 0.15),
                        borderRadius: BorderRadius.circular(10),
                      ),
                      child: Text(
                        '${filteredTasks.length}',
                        style: AppTypography.dataMono.copyWith(
                          color: AppColors.primary,
                          fontWeight: FontWeight.bold,
                          fontSize: 12,
                        ),
                      ),
                    ),
                  ],
                ),
                const SizedBox(height: AppSpacing.sm),
                if (filteredTasks.isEmpty)
                  Container(
                    padding: const EdgeInsets.all(AppSpacing.lg),
                    decoration: BoxDecoration(
                      color: AppColors.surfaceContainerLowest,
                      borderRadius: BorderRadius.circular(AppSpacing.radiusMd),
                      border: Border.all(color: AppColors.outlineVariant),
                    ),
                    child: Center(
                      child: Text(
                        'No task records match these filters.',
                        style: AppTypography.bodyMd
                            .copyWith(color: AppColors.onSurfaceVariant),
                      ),
                    ),
                  )
                else
                  ...filteredTasks.map((task) => _buildTaskRecord(task, staff)),
              ],
            ),
          );
        },
      ),
    );
  }

  List<TaskItem> _filterTasks(List<TaskItem> tasks) {
    return tasks.where((task) {
      if (_selectedStaffId != null && task.assignedTo != _selectedStaffId) {
        return false;
      }
      if (_selectedStatus != 'all' && task.status != _selectedStatus) {
        return false;
      }
      if (_fromDate != null && task.createdAt.isBefore(_startOfDay(_fromDate!))) {
        return false;
      }
      if (_toDate != null && task.createdAt.isAfter(_endOfDay(_toDate!))) {
        return false;
      }
      return true;
    }).toList();
  }

  Widget _buildSummary(int total, int pending, int completed) {
    return Wrap(
      spacing: AppSpacing.sm,
      runSpacing: AppSpacing.sm,
      children: [
        _SummaryCard(
          label: 'Total Tasks',
          value: '$total',
          color: AppColors.primary,
        ),
        _SummaryCard(
          label: 'Pending / In Progress',
          value: '$pending',
          color: Colors.orange.shade800,
        ),
        _SummaryCard(
          label: 'Completed',
          value: '$completed',
          color: Colors.green.shade700,
        ),
      ],
    );
  }

  Widget _buildFilters(List<UserProfile> staff) {
    return Container(
      padding: const EdgeInsets.all(AppSpacing.md),
      decoration: BoxDecoration(
        color: AppColors.surfaceContainerLowest,
        borderRadius: BorderRadius.circular(AppSpacing.radiusLg),
        border: Border.all(color: AppColors.outlineVariant),
      ),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Text('FILTERS',
              style: AppTypography.labelCaps.copyWith(color: AppColors.primary)),
          const SizedBox(height: AppSpacing.sm),
          DropdownButtonFormField<String?>(
            initialValue: staff.any((user) => user.id == _selectedStaffId)
                ? _selectedStaffId
                : null,
            decoration: InputDecoration(
              labelText: 'Staff member',
              prefixIcon: const Icon(Icons.person_outline),
              border: OutlineInputBorder(
                borderRadius: BorderRadius.circular(AppSpacing.radiusMd),
              ),
              isDense: true,
            ),
            items: [
              const DropdownMenuItem<String?>(
                value: null,
                child: Text('All staff'),
              ),
              ...staff.map(
                (user) => DropdownMenuItem<String?>(
                  value: user.id,
                  child: Text(user.fullName),
                ),
              ),
            ],
            onChanged: (value) => setState(() => _selectedStaffId = value),
          ),
          const SizedBox(height: AppSpacing.sm),
          DropdownButtonFormField<String>(
            initialValue: _selectedStatus,
            decoration: InputDecoration(
              labelText: 'Status',
              prefixIcon: const Icon(Icons.filter_list),
              border: OutlineInputBorder(
                borderRadius: BorderRadius.circular(AppSpacing.radiusMd),
              ),
              isDense: true,
            ),
            items: const [
              DropdownMenuItem(value: 'all', child: Text('All statuses')),
              DropdownMenuItem(value: 'pending', child: Text('Pending')),
              DropdownMenuItem(
                  value: 'in_progress', child: Text('In Progress')),
              DropdownMenuItem(value: 'completed', child: Text('Completed')),
              DropdownMenuItem(value: 'cancelled', child: Text('Cancelled')),
            ],
            onChanged: (value) =>
                setState(() => _selectedStatus = value ?? 'all'),
          ),
          const SizedBox(height: AppSpacing.sm),
          Wrap(
            spacing: AppSpacing.sm,
            runSpacing: AppSpacing.sm,
            children: [
              OutlinedButton.icon(
                onPressed: () => _pickDate(isFrom: true),
                icon: const Icon(Icons.calendar_today_outlined, size: 16),
                label: Text(
                  _fromDate == null
                      ? 'From date'
                      : DateFormat('MMM d, yyyy').format(_fromDate!),
                ),
              ),
              OutlinedButton.icon(
                onPressed: () => _pickDate(isFrom: false),
                icon: const Icon(Icons.calendar_today_outlined, size: 16),
                label: Text(
                  _toDate == null
                      ? 'To date'
                      : DateFormat('MMM d, yyyy').format(_toDate!),
                ),
              ),
              if (_fromDate != null || _toDate != null)
                TextButton(
                  onPressed: () => setState(() {
                    _fromDate = null;
                    _toDate = null;
                  }),
                  child: const Text('Clear dates'),
                ),
            ],
          ),
        ],
      ),
    );
  }

  Widget _buildStaffSummary(List<TaskItem> tasks, List<UserProfile> staff) {
    final completedByStaff = <String, int>{};
    for (final task in tasks.where((task) => task.status == 'completed')) {
      completedByStaff[task.assignedTo] =
          (completedByStaff[task.assignedTo] ?? 0) + 1;
    }

    if (completedByStaff.isEmpty) {
      return Container(
        padding: const EdgeInsets.all(AppSpacing.md),
        decoration: BoxDecoration(
          color: AppColors.surfaceContainerLowest,
          borderRadius: BorderRadius.circular(AppSpacing.radiusMd),
          border: Border.all(color: AppColors.outlineVariant),
        ),
        child: Text(
          'No completed tasks in this view.',
          style: AppTypography.bodyMd
              .copyWith(color: AppColors.onSurfaceVariant),
        ),
      );
    }

    return Container(
      decoration: BoxDecoration(
        color: AppColors.surfaceContainerLowest,
        borderRadius: BorderRadius.circular(AppSpacing.radiusLg),
        border: Border.all(color: AppColors.outlineVariant),
      ),
      child: Column(
        children: completedByStaff.entries.map((entry) {
          final staffUser = staff
              .where((user) => user.id == entry.key)
              .firstOrNull;
          final staffName = staffUser?.fullName ?? 'Unknown staff';

          return ListTile(
            leading: CircleAvatar(
              backgroundColor: Colors.green.withValues(alpha: 0.15),
              radius: 18,
              child: Icon(Icons.check_circle,
                  color: Colors.green.shade700, size: 20),
            ),
            title: Text(
              staffName,
              style: AppTypography.bodyMd.copyWith(fontWeight: FontWeight.w600),
            ),
            subtitle: staffUser?.email != null
                ? Text(staffUser!.email, style: AppTypography.bodySm)
                : null,
            trailing: Container(
              padding: const EdgeInsets.symmetric(horizontal: 10, vertical: 4),
              decoration: BoxDecoration(
                color: Colors.green.withValues(alpha: 0.1),
                borderRadius: BorderRadius.circular(12),
              ),
              child: Text(
                '${entry.value} completed',
                style: AppTypography.labelCaps.copyWith(
                  color: Colors.green.shade800,
                  fontWeight: FontWeight.bold,
                ),
              ),
            ),
          );
        }).toList(),
      ),
    );
  }

  Widget _buildTaskRecord(TaskItem task, List<UserProfile> staff) {
    final staffUser =
        staff.where((user) => user.id == task.assignedTo).firstOrNull;
    final staffName = staffUser?.fullName ?? task.staffName ?? 'Staff Member';

    final Color statusColor;
    switch (task.status.toLowerCase()) {
      case 'completed':
        statusColor = Colors.green.shade700;
        break;
      case 'in_progress':
        statusColor = AppColors.primary;
        break;
      case 'cancelled':
        statusColor = Colors.grey;
        break;
      default:
        statusColor = Colors.orange.shade800;
    }

    final Color priorityColor;
    switch (task.priority.toLowerCase()) {
      case 'critical':
        priorityColor = Colors.red;
        break;
      case 'high':
        priorityColor = Colors.orange;
        break;
      case 'low':
        priorityColor = Colors.grey;
        break;
      default:
        priorityColor = AppColors.secondary;
    }

    return Card(
      margin: const EdgeInsets.only(bottom: AppSpacing.sm),
      elevation: 0,
      shape: RoundedRectangleBorder(
        borderRadius: BorderRadius.circular(AppSpacing.radiusMd),
        side: const BorderSide(color: AppColors.outlineVariant),
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
                const SizedBox(width: AppSpacing.xs),
                Container(
                  padding:
                      const EdgeInsets.symmetric(horizontal: 8, vertical: 3),
                  decoration: BoxDecoration(
                    color: statusColor.withValues(alpha: 0.1),
                    borderRadius: BorderRadius.circular(AppSpacing.radiusSm),
                  ),
                  child: Text(
                    task.statusLabel.toUpperCase(),
                    style: AppTypography.labelCaps.copyWith(
                      color: statusColor,
                      fontWeight: FontWeight.bold,
                      fontSize: 10,
                    ),
                  ),
                ),
                const SizedBox(width: AppSpacing.xs),
                IconButton(
                  icon: const Icon(Icons.edit_outlined, size: 18, color: AppColors.primary),
                  tooltip: 'Edit Task',
                  padding: EdgeInsets.zero,
                  constraints: const BoxConstraints(),
                  onPressed: () {
                    showDialog(
                      context: context,
                      builder: (_) => TaskFormDialog(task: task),
                    );
                  },
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
                    const Icon(Icons.person_outline,
                        size: 14, color: AppColors.outline),
                    const SizedBox(width: 4),
                    Text(
                      'Assigned to: $staffName',
                      style: AppTypography.bodySm.copyWith(
                        fontWeight: FontWeight.w500,
                      ),
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
                      style: AppTypography.bodySm.copyWith(
                        color: priorityColor,
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
                      'Created: ${DateFormat('MMM d, yyyy').format(task.createdAt.toLocal())}',
                      style: AppTypography.bodySm.copyWith(
                        color: AppColors.onSurfaceVariant,
                      ),
                    ),
                  ],
                ),
                if (task.dueDate != null)
                  Row(
                    mainAxisSize: MainAxisSize.min,
                    children: [
                      const Icon(Icons.event_outlined,
                          size: 14, color: AppColors.outline),
                      const SizedBox(width: 4),
                      Text(
                        'Due: ${DateFormat('MMM d, yyyy').format(task.dueDate!.toLocal())}',
                        style: AppTypography.bodySm.copyWith(
                          color: task.isOverdue ? Colors.red : AppColors.onSurfaceVariant,
                          fontWeight: task.isOverdue ? FontWeight.w600 : null,
                        ),
                      ),
                    ],
                  ),
                if (task.completedAt != null)
                  Row(
                    mainAxisSize: MainAxisSize.min,
                    children: [
                      Icon(Icons.check_circle_outline,
                          size: 14, color: Colors.green.shade700),
                      const SizedBox(width: 4),
                      Text(
                        'Completed: ${DateFormat('MMM d, yyyy, h:mm a').format(task.completedAt!.toLocal())}',
                        style: AppTypography.bodySm.copyWith(
                          color: Colors.green.shade800,
                          fontWeight: FontWeight.w600,
                        ),
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

  Future<void> _pickDate({required bool isFrom}) async {
    final picked = await showDatePicker(
      context: context,
      initialDate: isFrom
          ? (_fromDate ?? DateTime.now())
          : (_toDate ?? DateTime.now()),
      firstDate: DateTime(2024),
      lastDate: DateTime(2100),
    );
    if (picked == null || !mounted) return;
    setState(() {
      if (isFrom) {
        _fromDate = picked;
      } else {
        _toDate = picked;
      }
    });
  }

  DateTime _startOfDay(DateTime date) =>
      DateTime(date.year, date.month, date.day);

  DateTime _endOfDay(DateTime date) =>
      DateTime(date.year, date.month, date.day, 23, 59, 59, 999);
}

class _SummaryCard extends StatelessWidget {
  const _SummaryCard({
    required this.label,
    required this.value,
    required this.color,
  });

  final String label;
  final String value;
  final Color color;

  @override
  Widget build(BuildContext context) {
    return Container(
      width: 145,
      padding: const EdgeInsets.all(AppSpacing.md),
      decoration: BoxDecoration(
        color: AppColors.surfaceContainerLowest,
        borderRadius: BorderRadius.circular(AppSpacing.radiusMd),
        border: Border.all(color: AppColors.outlineVariant),
      ),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Text(
            value,
            style: GoogleFonts.manrope(
              fontSize: 32,
              fontWeight: FontWeight.w700,
              color: color,
            ),
          ),
          const SizedBox(height: 4),
          Text(
            label,
            style: AppTypography.labelCaps.copyWith(
              color: AppColors.onSurfaceVariant,
            ),
          ),
        ],
      ),
    );
  }
}
