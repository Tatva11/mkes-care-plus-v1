import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:intl/intl.dart';

import '../../../core/theme/app_colors.dart';
import '../../../core/theme/app_spacing.dart';
import '../../../core/theme/app_typography.dart';
import '../../admin/models/user_profile.dart';
import '../../admin/providers/users_provider.dart';
import '../../auth/providers/auth_provider.dart';
import '../../staff/models/task_item.dart';
import '../../staff/providers/attendance_provider.dart';
import '../../staff/providers/task_provider.dart';
import '../../staff/screens/staff_profile_detail_screen.dart';
import '../widgets/task_form_dialog.dart';

class AdminAttendanceScreen extends ConsumerWidget {
  const AdminAttendanceScreen({super.key});

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    return const AdminPerformanceScreen(initialTab: 1);
  }
}

class AdminPerformanceScreen extends ConsumerStatefulWidget {
  const AdminPerformanceScreen({super.key, this.initialTab = 0});

  final int initialTab;

  @override
  ConsumerState<AdminPerformanceScreen> createState() =>
      _AdminPerformanceScreenState();
}

class _AdminPerformanceScreenState extends ConsumerState<AdminPerformanceScreen>
    with SingleTickerProviderStateMixin {
  late TabController _tabController;
  DateTime _selectedDate = DateTime.now();
  String _performanceSearch = '';
  String? _selectedDepartment;

  @override
  void initState() {
    super.initState();
    _tabController = TabController(
      length: 2,
      vsync: this,
      initialIndex: widget.initialTab,
    );
  }

  @override
  void dispose() {
    _tabController.dispose();
    super.dispose();
  }

  @override
  Widget build(BuildContext context) {
    final isDesktop = MediaQuery.sizeOf(context).width >= 768.0;

    return Scaffold(
      appBar: AppBar(
        title: const Text('Performance & Attendance'),
        bottom: TabBar(
          controller: _tabController,
          indicatorColor: AppColors.primaryContainer,
          labelColor: AppColors.primaryContainer,
          unselectedLabelColor: AppColors.onSurfaceVariant,
          tabs: const [
            Tab(
              icon: Icon(Icons.speed_outlined),
              text: 'Task Performance & Workload',
            ),
            Tab(
              icon: Icon(Icons.how_to_reg_outlined),
              text: 'Attendance Management',
            ),
          ],
        ),
      ),
      body: TabBarView(
        controller: _tabController,
        children: [
          // Tab 1: Staff Performance & Workload
          _PerformanceWorkloadView(
            isDesktop: isDesktop,
            searchQuery: _performanceSearch,
            onSearchChanged: (v) => setState(() => _performanceSearch = v),
            selectedDepartment: _selectedDepartment,
            onDepartmentChanged: (v) => setState(() => _selectedDepartment = v),
          ),

          // Tab 2: Attendance Management
          _AttendanceView(
            isDesktop: isDesktop,
            selectedDate: _selectedDate,
            onDateSelected: (date) => setState(() => _selectedDate = date),
          ),
        ],
      ),
    );
  }
}

// ─────────────────────────────────────────────────────────────────────────────
// TAB 1: Task Performance & Workload
// ─────────────────────────────────────────────────────────────────────────────
class _PerformanceWorkloadView extends ConsumerWidget {
  const _PerformanceWorkloadView({
    required this.isDesktop,
    required this.searchQuery,
    required this.onSearchChanged,
    required this.selectedDepartment,
    required this.onDepartmentChanged,
  });

  final bool isDesktop;
  final String searchQuery;
  final ValueChanged<String> onSearchChanged;
  final String? selectedDepartment;
  final ValueChanged<String?> onDepartmentChanged;

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    final tasksAsync = ref.watch(adminTasksProvider);
    final usersAsync = ref.watch(usersProvider);
    final currentUser = ref.watch(currentUserProvider);

    return SingleChildScrollView(
      padding: EdgeInsets.all(
        isDesktop ? AppSpacing.marginDesktop : AppSpacing.marginMobile,
      ),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          // Header Row
          Row(
            mainAxisAlignment: MainAxisAlignment.spaceBetween,
            children: [
              Column(
                crossAxisAlignment: CrossAxisAlignment.start,
                children: [
                  Text('Staff Performance & Workload',
                      style: AppTypography.headlineMd),
                  const SizedBox(height: 2),
                  Text(
                    'Track task completion, overdue rates, and staff capacity in real-time.',
                    style: AppTypography.bodySm.copyWith(
                      color: AppColors.onSurfaceVariant,
                    ),
                  ),
                ],
              ),
              if (currentUser != null)
                FilledButton.icon(
                  icon: const Icon(Icons.add_task, size: 18),
                  label: const Text('Assign Task'),
                  style: FilledButton.styleFrom(
                    backgroundColor: AppColors.primaryContainer,
                  ),
                  onPressed: () => _openCreateTaskDialog(
                    context,
                    ref,
                    currentUser.id,
                    usersAsync.valueOrNull ?? [],
                  ),
                ),
            ],
          ),

          const SizedBox(height: AppSpacing.md),

          // High-level KPI Summary Row
          tasksAsync.when(
            loading: () => const LinearProgressIndicator(),
            error: (e, _) => Text('Error loading tasks: $e'),
            data: (tasks) {
              final total = tasks.length;
              final completed =
                  tasks.where((t) => t.status == 'completed').length;
              final overdue = tasks.where((t) => t.isOverdue).length;
              final active = tasks
                  .where((t) => t.status == 'pending' || t.status == 'in_progress')
                  .length;
              final completionRate =
                  total > 0 ? (completed / total * 100).round() : 0;

              return LayoutBuilder(
                builder: (context, constraints) {
                  final isWide = constraints.maxWidth >= 640;
                  final cards = [
                    _KpiCard(
                      label: 'Total Tasks',
                      value: '$total',
                      icon: Icons.assignment_outlined,
                    ),
                    _KpiCard(
                      label: 'Active Workload',
                      value: '$active',
                      icon: Icons.pending_actions_outlined,
                      color: AppColors.secondary,
                    ),
                    _KpiCard(
                      label: 'Completed Tasks',
                      value: '$completed',
                      subValue: '$completionRate% completed',
                      icon: Icons.check_circle_outline,
                      color: AppColors.primaryContainer,
                    ),
                    _KpiCard(
                      label: 'Overdue Tasks',
                      value: '$overdue',
                      icon: Icons.warning_amber_outlined,
                      color: overdue > 0 ? AppColors.error : AppColors.outline,
                    ),
                  ];

                  if (isWide) {
                    return Row(
                      children: cards
                          .map((c) => Expanded(
                                child: Padding(
                                  padding: const EdgeInsets.symmetric(
                                      horizontal: 4),
                                  child: c,
                                ),
                              ))
                          .toList(),
                    );
                  }
                  return Column(
                    children: cards
                        .map((c) => Padding(
                              padding: const EdgeInsets.only(
                                  bottom: AppSpacing.xs),
                              child: c,
                            ))
                        .toList(),
                  );
                },
              );
            },
          ),

          const SizedBox(height: AppSpacing.lg),

          // Filters & Search Bar
          Row(
            children: [
              Expanded(
                flex: 3,
                child: TextField(
                  decoration: InputDecoration(
                    hintText: 'Search staff by name or designation...',
                    prefixIcon: const Icon(Icons.search, size: 20),
                    isDense: true,
                    border: OutlineInputBorder(
                      borderRadius:
                          BorderRadius.circular(AppSpacing.radiusMd),
                    ),
                  ),
                  onChanged: onSearchChanged,
                ),
              ),
              const SizedBox(width: AppSpacing.md),
              usersAsync.maybeWhen(
                data: (users) {
                  final departments = users
                      .map((u) => u.departmentName ?? u.department)
                      .whereType<String>()
                      .toSet()
                      .toList();
                  return DropdownButton<String?>(
                    value: selectedDepartment,
                    hint: const Text('All Departments'),
                    underline: const SizedBox.shrink(),
                    items: [
                      const DropdownMenuItem(
                        value: null,
                        child: Text('All Departments'),
                      ),
                      ...departments.map((d) => DropdownMenuItem(
                            value: d,
                            child: Text(d),
                          )),
                    ],
                    onChanged: onDepartmentChanged,
                  );
                },
                orElse: () => const SizedBox.shrink(),
              ),
            ],
          ),

          const SizedBox(height: AppSpacing.md),

          // Staff Performance List
          usersAsync.when(
            loading: () => const Center(
              child: Padding(
                padding: EdgeInsets.all(AppSpacing.xl),
                child: CircularProgressIndicator(),
              ),
            ),
            error: (e, _) => Center(child: Text('Error loading staff: $e')),
            data: (allUsers) {
              final staffList = allUsers
                  .where((u) => u.role == 'staff')
                  .toList();

              return tasksAsync.when(
                loading: () => const SizedBox.shrink(),
                error: (e, _) => const SizedBox.shrink(),
                data: (tasks) {
                  // Filter staff list
                  var filteredStaff = staffList;
                  final q = searchQuery.trim().toLowerCase();
                  if (q.isNotEmpty) {
                    filteredStaff = filteredStaff.where((s) {
                      final nameMatch = s.fullName.toLowerCase().contains(q);
                      final desigMatch =
                          (s.designation ?? '').toLowerCase().contains(q);
                      return nameMatch || desigMatch;
                    }).toList();
                  }

                  if (selectedDepartment != null) {
                    filteredStaff = filteredStaff.where((s) {
                      final dept = s.departmentName ?? s.department;
                      return dept == selectedDepartment;
                    }).toList();
                  }

                  if (filteredStaff.isEmpty) {
                    return Center(
                      child: Padding(
                        padding: const EdgeInsets.all(AppSpacing.xl),
                        child: Text(
                          'No staff members match the selected criteria.',
                          style: AppTypography.bodyMd.copyWith(
                            color: AppColors.onSurfaceVariant,
                          ),
                        ),
                      ),
                    );
                  }

                  return ListView.separated(
                    shrinkWrap: true,
                    physics: const NeverScrollableScrollPhysics(),
                    itemCount: filteredStaff.length,
                    separatorBuilder: (_, __) =>
                        const SizedBox(height: AppSpacing.sm),
                    itemBuilder: (context, index) {
                      final staff = filteredStaff[index];
                      final staffTasks =
                          tasks.where((t) => t.assignedTo == staff.id).toList();

                      final completedCount = staffTasks
                          .where((t) => t.status == 'completed')
                          .length;
                      final overdueCount =
                          staffTasks.where((t) => t.isOverdue).length;
                      final activeCount = staffTasks
                          .where((t) =>
                              t.status == 'pending' ||
                              t.status == 'in_progress')
                          .length;
                      final totalCount = staffTasks.length;
                      final rate = totalCount > 0
                          ? (completedCount / totalCount * 100).round()
                          : 0;

                      return _StaffPerformanceCard(
                        staff: staff,
                        totalTasks: totalCount,
                        activeTasks: activeCount,
                        completedTasks: completedCount,
                        overdueTasks: overdueCount,
                        completionRate: rate,
                        onViewTasks: () => _showStaffTasksModal(
                          context,
                          staff,
                          staffTasks,
                        ),
                        onOpenProfile: () => Navigator.of(context).push(
                          MaterialPageRoute(
                            builder: (_) =>
                                StaffProfileDetailScreen(user: staff),
                          ),
                        ),
                      );
                    },
                  );
                },
              );
            },
          ),
        ],
      ),
    );
  }

  void _showStaffTasksModal(
    BuildContext context,
    UserProfile staff,
    List<TaskItem> tasks,
  ) {
    showModalBottomSheet(
      context: context,
      isScrollControlled: true,
      shape: const RoundedRectangleBorder(
        borderRadius: BorderRadius.vertical(top: Radius.circular(AppSpacing.radiusXl)),
      ),
      builder: (ctx) => DraggableScrollableSheet(
        initialChildSize: 0.65,
        maxChildSize: 0.9,
        minChildSize: 0.4,
        expand: false,
        builder: (context, scrollCtrl) => Padding(
          padding: const EdgeInsets.all(AppSpacing.lg),
          child: Column(
            crossAxisAlignment: CrossAxisAlignment.start,
            children: [
              Row(
                mainAxisAlignment: MainAxisAlignment.spaceBetween,
                children: [
                  Column(
                    crossAxisAlignment: CrossAxisAlignment.start,
                    children: [
                      Text(
                        '${staff.fullName} — Tasks',
                        style: AppTypography.headlineMd,
                      ),
                      Text(
                        '${staff.designation ?? 'Staff'} • ${tasks.length} total tasks',
                        style: AppTypography.bodySm.copyWith(
                          color: AppColors.onSurfaceVariant,
                        ),
                      ),
                    ],
                  ),
                  IconButton(
                    icon: const Icon(Icons.close),
                    onPressed: () => Navigator.of(ctx).pop(),
                  ),
                ],
              ),
              const Divider(height: AppSpacing.lg),
              Expanded(
                child: tasks.isEmpty
                    ? const Center(child: Text('No tasks assigned yet.'))
                    : ListView.separated(
                        controller: scrollCtrl,
                        itemCount: tasks.length,
                        separatorBuilder: (_, __) => const SizedBox(height: 8),
                        itemBuilder: (context, i) {
                          final task = tasks[i];
                          final isDone = task.status == 'completed';
                          return Container(
                            padding: const EdgeInsets.all(AppSpacing.md),
                            decoration: BoxDecoration(
                              color: AppColors.surfaceContainerLowest,
                              borderRadius:
                                  BorderRadius.circular(AppSpacing.radiusMd),
                              border: Border.all(
                                color: task.isOverdue
                                    ? AppColors.error.withValues(alpha: 0.4)
                                    : AppColors.outlineVariant,
                              ),
                            ),
                            child: Row(
                              children: [
                                Icon(
                                  isDone
                                      ? Icons.check_circle
                                      : Icons.radio_button_unchecked,
                                  color: isDone
                                      ? AppColors.primaryContainer
                                      : AppColors.outline,
                                  size: 20,
                                ),
                                const SizedBox(width: AppSpacing.sm),
                                Expanded(
                                  child: Column(
                                    crossAxisAlignment:
                                        CrossAxisAlignment.start,
                                    children: [
                                      Text(
                                        task.title,
                                        style: AppTypography.bodyMd.copyWith(
                                          fontWeight: FontWeight.w600,
                                        ),
                                      ),
                                      if (task.dueDate != null)
                                        Text(
                                          'Due: ${DateFormat('MMM d, yyyy').format(task.dueDate!)}${task.isOverdue ? ' (OVERDUE)' : ''}',
                                          style: AppTypography.bodySm.copyWith(
                                            color: task.isOverdue
                                                ? AppColors.error
                                                : AppColors.onSurfaceVariant,
                                            fontWeight: task.isOverdue
                                                ? FontWeight.w700
                                                : FontWeight.normal,
                                          ),
                                        ),
                                    ],
                                  ),
                                ),
                                Container(
                                  padding: const EdgeInsets.symmetric(
                                      horizontal: 8, vertical: 2),
                                  decoration: BoxDecoration(
                                    color: isDone
                                        ? AppColors.primaryContainer
                                            .withValues(alpha: 0.12)
                                        : AppColors.surfaceContainerHigh,
                                    borderRadius: BorderRadius.circular(
                                        AppSpacing.radiusSm),
                                  ),
                                  child: Text(
                                    task.statusLabel,
                                    style: AppTypography.labelCaps.copyWith(
                                      color: isDone
                                          ? AppColors.primaryContainer
                                          : AppColors.onSurfaceVariant,
                                      fontSize: 10,
                                    ),
                                  ),
                                ),
                                const SizedBox(width: AppSpacing.xs),
                                IconButton(
                                  icon: const Icon(Icons.edit_outlined, size: 18, color: AppColors.primary),
                                  tooltip: 'Edit Task',
                                  onPressed: () {
                                    Navigator.of(ctx).pop();
                                    showDialog(
                                      context: context,
                                      builder: (_) => TaskFormDialog(task: task),
                                    );
                                  },
                                ),
                              ],
                            ),
                          );
                        },
                      ),
              ),
            ],
          ),
        ),
      ),
    );
  }

  void _openCreateTaskDialog(
    BuildContext context,
    WidgetRef ref,
    String adminId,
    List<UserProfile> allUsers, {
    String? preselectedStaffId,
  }) {
    showDialog(
      context: context,
      builder: (_) => TaskFormDialog(initialStaffId: preselectedStaffId),
    );
  }
}

// ─────────────────────────────────────────────────────────────────────────────
// Staff Performance Row Card
// ─────────────────────────────────────────────────────────────────────────────
class _StaffPerformanceCard extends StatelessWidget {
  const _StaffPerformanceCard({
    required this.staff,
    required this.totalTasks,
    required this.activeTasks,
    required this.completedTasks,
    required this.overdueTasks,
    required this.completionRate,
    required this.onViewTasks,
    required this.onOpenProfile,
  });

  final UserProfile staff;
  final int totalTasks;
  final int activeTasks;
  final int completedTasks;
  final int overdueTasks;
  final int completionRate;
  final VoidCallback onViewTasks;
  final VoidCallback onOpenProfile;

  String get _ratingLabel {
    if (totalTasks == 0) return 'No Tasks';
    if (overdueTasks > 0) return 'Needs Attention';
    if (completionRate >= 80) return 'High Performer';
    return 'On Track';
  }

  Color get _ratingColor {
    if (totalTasks == 0) return AppColors.outline;
    if (overdueTasks > 0) return AppColors.error;
    if (completionRate >= 80) return AppColors.primaryContainer;
    return AppColors.secondary;
  }

  @override
  Widget build(BuildContext context) {
    final initials = staff.fullName
        .split(' ')
        .map((w) => w.isNotEmpty ? w[0] : '')
        .take(2)
        .join()
        .toUpperCase();

    return Container(
      padding: const EdgeInsets.all(AppSpacing.md),
      decoration: BoxDecoration(
        color: AppColors.surfaceContainerLowest,
        borderRadius: BorderRadius.circular(AppSpacing.radiusLg),
        border: Border.all(color: AppColors.outlineVariant),
      ),
      child: Column(
        children: [
          Row(
            children: [
              // Avatar
              CircleAvatar(
                radius: 22,
                backgroundColor: _ratingColor.withValues(alpha: 0.15),
                child: Text(
                  initials,
                  style: AppTypography.labelCaps.copyWith(
                    color: _ratingColor,
                    fontWeight: FontWeight.w700,
                  ),
                ),
              ),
              const SizedBox(width: AppSpacing.md),
              // Staff Name & Info
              Expanded(
                child: Column(
                  crossAxisAlignment: CrossAxisAlignment.start,
                  children: [
                    InkWell(
                      onTap: onOpenProfile,
                      child: Text(
                        staff.fullName,
                        style: AppTypography.bodyMd.copyWith(
                          fontWeight: FontWeight.w700,
                          decoration: TextDecoration.underline,
                        ),
                      ),
                    ),
                    Text(
                      '${staff.designation ?? 'Staff'} • ${staff.departmentName ?? staff.department ?? 'Unassigned'}',
                      style: AppTypography.bodySm.copyWith(
                        color: AppColors.onSurfaceVariant,
                      ),
                    ),
                  ],
                ),
              ),
              // Performance rating badge
              Container(
                padding:
                    const EdgeInsets.symmetric(horizontal: 10, vertical: 4),
                decoration: BoxDecoration(
                  color: _ratingColor.withValues(alpha: 0.12),
                  borderRadius: BorderRadius.circular(AppSpacing.radiusMd),
                ),
                child: Text(
                  _ratingLabel,
                  style: AppTypography.labelCaps.copyWith(
                    color: _ratingColor,
                    fontSize: 11,
                    fontWeight: FontWeight.w700,
                  ),
                ),
              ),
            ],
          ),

          const SizedBox(height: AppSpacing.sm),
          const Divider(height: 1),
          const SizedBox(height: AppSpacing.sm),

          // Metrics Row
          Row(
            mainAxisAlignment: MainAxisAlignment.spaceBetween,
            children: [
              _MiniMetric(
                label: 'Workload',
                value: '$activeTasks active',
                color: activeTasks > 5 ? AppColors.secondary : null,
              ),
              _MiniMetric(
                label: 'Completed',
                value: '$completedTasks / $totalTasks',
                color: AppColors.primaryContainer,
              ),
              _MiniMetric(
                label: 'Overdue',
                value: '$overdueTasks',
                color: overdueTasks > 0 ? AppColors.error : null,
              ),
              _MiniMetric(
                label: 'Rate',
                value: '$completionRate%',
                color: _ratingColor,
              ),
              OutlinedButton(
                onPressed: onViewTasks,
                style: OutlinedButton.styleFrom(
                  padding:
                      const EdgeInsets.symmetric(horizontal: 12, vertical: 6),
                ),
                child: const Text('View Tasks'),
              ),
            ],
          ),
        ],
      ),
    );
  }
}

class _MiniMetric extends StatelessWidget {
  const _MiniMetric({
    required this.label,
    required this.value,
    this.color,
  });

  final String label;
  final String value;
  final Color? color;

  @override
  Widget build(BuildContext context) {
    return Column(
      crossAxisAlignment: CrossAxisAlignment.start,
      children: [
        Text(
          label.toUpperCase(),
          style: AppTypography.labelCaps.copyWith(
            color: AppColors.onSurfaceVariant,
            fontSize: 9,
          ),
        ),
        const SizedBox(height: 2),
        Text(
          value,
          style: AppTypography.bodySm.copyWith(
            fontWeight: FontWeight.w700,
            color: color ?? AppColors.onSurface,
          ),
        ),
      ],
    );
  }
}

class _KpiCard extends StatelessWidget {
  const _KpiCard({
    required this.label,
    required this.value,
    required this.icon,
    this.subValue,
    this.color,
  });

  final String label;
  final String value;
  final String? subValue;
  final IconData icon;
  final Color? color;

  @override
  Widget build(BuildContext context) {
    final themeColor = color ?? AppColors.primary;
    return Container(
      padding: const EdgeInsets.all(AppSpacing.md),
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
              Text(
                label.toUpperCase(),
                style: AppTypography.labelCaps.copyWith(
                  color: AppColors.onSurfaceVariant,
                  fontSize: 10,
                ),
              ),
              Icon(icon, size: 18, color: themeColor),
            ],
          ),
          const SizedBox(height: 8),
          Text(
            value,
            style: AppTypography.headlineMd.copyWith(
              color: themeColor,
              fontWeight: FontWeight.w700,
            ),
          ),
          if (subValue != null) ...[
            const SizedBox(height: 2),
            Text(
              subValue!,
              style: AppTypography.bodySm.copyWith(
                color: AppColors.onSurfaceVariant,
                fontSize: 11,
              ),
            ),
          ],
        ],
      ),
    );
  }
}

// ─────────────────────────────────────────────────────────────────────────────
// TAB 2: Attendance Management (Preserved and Enhanced)
// ─────────────────────────────────────────────────────────────────────────────
class _AttendanceView extends ConsumerWidget {
  const _AttendanceView({
    required this.isDesktop,
    required this.selectedDate,
    required this.onDateSelected,
  });

  final bool isDesktop;
  final DateTime selectedDate;
  final ValueChanged<DateTime> onDateSelected;

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    final usersState = ref.watch(usersProvider);
    final users = (usersState.valueOrNull ?? const [])
        .where((user) => user.role == 'staff' && user.isActive)
        .toList();
    final attendanceAsync =
        ref.watch(adminAttendanceForDateProvider(selectedDate));
    final summaryAsync =
        ref.watch(adminAttendanceSummaryProvider(selectedDate));

    return Padding(
      padding: EdgeInsets.all(
        isDesktop ? AppSpacing.marginDesktop : AppSpacing.marginMobile,
      ),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Row(
            mainAxisAlignment: MainAxisAlignment.spaceBetween,
            children: [
              Expanded(
                child: Text(
                  'Staff Attendance — ${DateFormat('MMMM d, yyyy').format(selectedDate)}',
                  style: AppTypography.headlineMd,
                ),
              ),
              OutlinedButton.icon(
                icon: const Icon(Icons.calendar_today_outlined, size: 18),
                label: const Text('Change Date'),
                onPressed: () async {
                  final picked = await showDatePicker(
                    context: context,
                    initialDate: selectedDate,
                    firstDate: DateTime(2024),
                    lastDate: DateTime(2100),
                  );
                  if (picked != null) onDateSelected(picked);
                },
              ),
            ],
          ),
          const SizedBox(height: AppSpacing.md),
          summaryAsync.when(
            data: (summary) {
              final totalStaff = users.length;
              return Wrap(
                spacing: AppSpacing.sm,
                runSpacing: AppSpacing.sm,
                children: [
                  _SummaryChip(label: 'Total', value: '$totalStaff'),
                  _SummaryChip(
                    label: 'Present',
                    value: '${summary['present'] ?? 0}',
                    color: AppColors.primaryContainer,
                  ),
                  _SummaryChip(
                    label: 'Late',
                    value: '${summary['late'] ?? 0}',
                    color: AppColors.secondary,
                  ),
                  _SummaryChip(
                    label: 'Absent',
                    value: '${summary['absent'] ?? 0}',
                    color: AppColors.error,
                  ),
                  _SummaryChip(
                    label: 'Leave',
                    value: '${summary['leave'] ?? 0}',
                    color: AppColors.tertiary,
                  ),
                ],
              );
            },
            loading: () => const LinearProgressIndicator(),
            error: (e, st) => const SizedBox.shrink(),
          ),
          const SizedBox(height: AppSpacing.md),
          Expanded(
            child: attendanceAsync.when(
              data: (records) {
                if (records.isEmpty) {
                  return const Center(
                    child: Text('No attendance records found for this date.'),
                  );
                }

                final staffMap = {
                  for (final user in users) user.id: user,
                };

                final staffRecords = records
                    .where((record) => staffMap.containsKey(record.staffId))
                    .toList();

                if (staffRecords.isEmpty) {
                  return const Center(
                    child: Text('No staff attendance records found for this date.'),
                  );
                }

                final rows = staffRecords.map((record) {
                  final staff = staffMap[record.staffId]!;
                  final name = staff.fullName;
                  final statusColor = _attendanceStatusColor(record.status);
                  return Container(
                    margin: const EdgeInsets.only(bottom: AppSpacing.sm),
                    padding: const EdgeInsets.all(AppSpacing.md),
                    decoration: BoxDecoration(
                      color: AppColors.surfaceContainerLowest,
                      borderRadius: BorderRadius.circular(AppSpacing.radiusMd),
                      border: Border.all(color: AppColors.outlineVariant),
                    ),
                    child: Row(
                      children: [
                        Expanded(
                          child: Column(
                            crossAxisAlignment: CrossAxisAlignment.start,
                            children: [
                              Text(name, style: AppTypography.headlineMd),
                              const SizedBox(height: AppSpacing.xs),
                              Text(
                                staff.designation ?? 'Staff member',
                                style: AppTypography.bodySm.copyWith(
                                  color: AppColors.onSurfaceVariant,
                                ),
                              ),
                            ],
                          ),
                        ),
                        const SizedBox(width: AppSpacing.md),
                        Column(
                          crossAxisAlignment: CrossAxisAlignment.end,
                          children: [
                            Container(
                              padding: const EdgeInsets.symmetric(
                                horizontal: AppSpacing.sm,
                                vertical: AppSpacing.xs,
                              ),
                              decoration: BoxDecoration(
                                color: statusColor.withValues(alpha: 0.15),
                                borderRadius:
                                    BorderRadius.circular(AppSpacing.radiusSm),
                              ),
                              child: Text(
                                record.statusLabel,
                                style: AppTypography.labelCaps
                                    .copyWith(color: statusColor),
                              ),
                            ),
                            const SizedBox(height: AppSpacing.xs),
                            Text(
                              record.checkInTime == null
                                  ? 'No check-in'
                                  : DateFormat('hh:mm a')
                                      .format(record.checkInTime!),
                              style: AppTypography.bodySm,
                            ),
                          ],
                        ),
                      ],
                    ),
                  );
                }).toList();

                return ListView(children: rows);
              },
              loading: () =>
                  const Center(child: CircularProgressIndicator()),
              error: (e, st) => Center(
                child: Text('Unable to load attendance: $e'),
              ),
            ),
          ),
        ],
      ),
    );
  }

  Color _attendanceStatusColor(String status) {
    switch (status.toLowerCase()) {
      case 'present':
        return AppColors.primaryContainer;
      case 'late':
        return AppColors.secondary;
      case 'absent':
        return AppColors.error;
      case 'leave':
        return AppColors.tertiary;
      case 'holiday':
        return AppColors.outline;
      default:
        return AppColors.onSurfaceVariant;
    }
  }
}

class _SummaryChip extends StatelessWidget {
  const _SummaryChip({
    required this.label,
    required this.value,
    this.color,
  });

  final String label;
  final String value;
  final Color? color;

  @override
  Widget build(BuildContext context) {
    final chipColor = color ?? AppColors.surfaceContainerLow;
    return Container(
      margin: const EdgeInsets.only(right: AppSpacing.sm),
      padding: const EdgeInsets.symmetric(
        horizontal: AppSpacing.sm,
        vertical: AppSpacing.xs,
      ),
      decoration: BoxDecoration(
        color: chipColor.withValues(alpha: 0.15),
        borderRadius: BorderRadius.circular(AppSpacing.radiusMd),
      ),
      child: Row(
        mainAxisSize: MainAxisSize.min,
        children: [
          Text('$label: ', style: AppTypography.labelCaps),
          Text(
            value,
            style: AppTypography.labelCaps.copyWith(
              fontWeight: FontWeight.bold,
              color: chipColor,
            ),
          ),
        ],
      ),
    );
  }
}
