import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:intl/intl.dart';

import '../../../core/theme/app_colors.dart';
import '../../../core/theme/app_spacing.dart';
import '../../../core/theme/app_typography.dart';
import '../../admin/models/user_profile.dart';
import '../../admin/providers/users_provider.dart';
import '../../staff/models/task_item.dart';
import '../../staff/providers/task_provider.dart';

class AdminTaskHistoryScreen extends ConsumerStatefulWidget {
  const AdminTaskHistoryScreen({super.key});

  @override
  ConsumerState<AdminTaskHistoryScreen> createState() => _AdminTaskHistoryScreenState();
}

class _AdminTaskHistoryScreenState extends ConsumerState<AdminTaskHistoryScreen> {
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
      appBar: AppBar(title: const Text('Task History & Performance')),
      body: tasksAsync.when(
        data: (tasks) {
          final filteredTasks = _filterTasks(tasks);
          final total = filteredTasks.length;
          final completed = filteredTasks.where((task) => task.status == 'completed').length;
          final pending = filteredTasks.where((task) => task.status == 'pending').length;

          return ListView(
            padding: const EdgeInsets.all(AppSpacing.md),
            children: [
              _buildSummary(total, pending, completed),
              const SizedBox(height: AppSpacing.lg),
              _buildFilters(staff),
              const SizedBox(height: AppSpacing.lg),
              Text('Completed by staff', style: AppTypography.headlineMd),
              const SizedBox(height: AppSpacing.sm),
              _buildStaffSummary(filteredTasks, staff),
              const SizedBox(height: AppSpacing.lg),
              Text('Task records', style: AppTypography.headlineMd),
              const SizedBox(height: AppSpacing.sm),
              if (filteredTasks.isEmpty)
                const Padding(
                  padding: EdgeInsets.all(AppSpacing.lg),
                  child: Center(child: Text('No task records match these filters.')),
                )
              else
                ...filteredTasks.map(_buildTaskRecord),
            ],
          );
        },
        loading: () => const Center(child: CircularProgressIndicator()),
        error: (error, stackTrace) => Center(child: Text('Unable to load task history: $error')),
      ),
    );
  }

  List<TaskItem> _filterTasks(List<TaskItem> tasks) {
    return tasks.where((task) {
      if (_selectedStaffId != null && task.assignedTo != _selectedStaffId) return false;
      if (_selectedStatus != 'all' && task.status != _selectedStatus) return false;
      if (_fromDate != null && task.createdAt.isBefore(_startOfDay(_fromDate!))) return false;
      if (_toDate != null && task.createdAt.isAfter(_endOfDay(_toDate!))) return false;
      return true;
    }).toList();
  }

  Widget _buildSummary(int total, int pending, int completed) {
    return Wrap(
      spacing: AppSpacing.sm,
      runSpacing: AppSpacing.sm,
      children: [
        _SummaryCard(label: 'Total Tasks', value: '$total', color: AppColors.primary),
        _SummaryCard(label: 'Pending', value: '$pending', color: Colors.orange),
        _SummaryCard(label: 'Completed', value: '$completed', color: Colors.green),
      ],
    );
  }

  Widget _buildFilters(List<UserProfile> staff) {
    return Column(
      crossAxisAlignment: CrossAxisAlignment.start,
      children: [
        DropdownButtonFormField<String>(
          initialValue: staff.any((user) => user.id == _selectedStaffId) ? _selectedStaffId : null,
          decoration: const InputDecoration(labelText: 'Staff member', border: OutlineInputBorder()),
          items: [
            const DropdownMenuItem<String>(value: null, child: Text('All staff')),
            ...staff.map((user) => DropdownMenuItem(value: user.id, child: Text(user.fullName))),
          ],
          onChanged: (value) => setState(() => _selectedStaffId = value),
        ),
        const SizedBox(height: AppSpacing.sm),
        DropdownButtonFormField<String>(
          initialValue: _selectedStatus,
          decoration: const InputDecoration(labelText: 'Status', border: OutlineInputBorder()),
          items: const [
            DropdownMenuItem(value: 'all', child: Text('All statuses')),
            DropdownMenuItem(value: 'pending', child: Text('Pending')),
            DropdownMenuItem(value: 'completed', child: Text('Completed')),
          ],
          onChanged: (value) => setState(() => _selectedStatus = value ?? 'all'),
        ),
        const SizedBox(height: AppSpacing.sm),
        Wrap(
          spacing: AppSpacing.sm,
          runSpacing: AppSpacing.sm,
          children: [
            OutlinedButton.icon(
              onPressed: () => _pickDate(isFrom: true),
              icon: const Icon(Icons.calendar_today_outlined),
              label: Text(_fromDate == null ? 'From date' : DateFormat('MMM d, yyyy').format(_fromDate!)),
            ),
            OutlinedButton.icon(
              onPressed: () => _pickDate(isFrom: false),
              icon: const Icon(Icons.calendar_today_outlined),
              label: Text(_toDate == null ? 'To date' : DateFormat('MMM d, yyyy').format(_toDate!)),
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
    );
  }

  Widget _buildStaffSummary(List<TaskItem> tasks, List<UserProfile> staff) {
    final completedByStaff = <String, int>{};
    for (final task in tasks.where((task) => task.status == 'completed')) {
      completedByStaff[task.assignedTo] = (completedByStaff[task.assignedTo] ?? 0) + 1;
    }

    if (completedByStaff.isEmpty) {
      return const Text('No completed tasks in this view.');
    }

    return Column(
      children: completedByStaff.entries.map((entry) {
        final staffName = staff.where((user) => user.id == entry.key).map((user) => user.fullName).firstOrNull ?? 'Unknown staff';
        return ListTile(
          contentPadding: EdgeInsets.zero,
          title: Text(staffName),
          trailing: Text('${entry.value}', style: AppTypography.headlineMd),
        );
      }).toList(),
    );
  }

  Widget _buildTaskRecord(TaskItem task) {
    final statusColor = task.status == 'completed' ? Colors.green : Colors.orange;
    return Card(
      margin: const EdgeInsets.only(bottom: AppSpacing.sm),
      child: Padding(
        padding: const EdgeInsets.all(AppSpacing.md),
        child: Column(
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            Row(
              children: [
                Expanded(child: Text(task.title, style: AppTypography.bodyLg.copyWith(fontWeight: FontWeight.w600))),
                Text(task.statusLabel, style: AppTypography.labelCaps.copyWith(color: statusColor)),
              ],
            ),
            if (task.description != null && task.description!.trim().isNotEmpty) ...[
              const SizedBox(height: AppSpacing.xs),
              Text(task.description!),
            ],
            const SizedBox(height: AppSpacing.xs),
            Text('Assigned: ${DateFormat('MMM d, yyyy').format(task.createdAt)}'),
            if (task.completedAt != null)
              Text('Completed: ${DateFormat('MMM d, yyyy, h:mm a').format(task.completedAt!)}'),
            Text('Priority: ${task.priority.toUpperCase()}'),
          ],
        ),
      ),
    );
  }

  Future<void> _pickDate({required bool isFrom}) async {
    final picked = await showDatePicker(
      context: context,
      initialDate: isFrom ? (_fromDate ?? DateTime.now()) : (_toDate ?? DateTime.now()),
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

  DateTime _startOfDay(DateTime date) => DateTime(date.year, date.month, date.day);

  DateTime _endOfDay(DateTime date) => DateTime(date.year, date.month, date.day, 23, 59, 59, 999);
}

class _SummaryCard extends StatelessWidget {
  const _SummaryCard({required this.label, required this.value, required this.color});

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
          Text(value, style: AppTypography.displayLg.copyWith(color: color)),
          Text(label, style: AppTypography.labelCaps),
        ],
      ),
    );
  }
}
