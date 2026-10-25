import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:intl/intl.dart';

import '../../../core/theme/app_colors.dart';
import '../../../core/theme/app_spacing.dart';
import '../../../core/theme/app_typography.dart';
import '../../auth/providers/auth_provider.dart';
import '../../dental/screens/dental_lab_screen.dart';
import '../../eye/screens/eye_surgery_screen.dart';
import '../../inventory/screens/inventory_screen.dart';
import '../../inventory/screens/purchase_order_list_screen.dart';
import '../../staff/models/task_item.dart';
import '../../staff/providers/task_provider.dart';
import '../../staff/utils/task_operational_filter.dart';
import '../../vendors/screens/vendor_management_screen.dart';
import 'staff_task_history_screen.dart';

enum StaffTaskTab {
  tasks,
  inventory,
  vendors,
  purchaseOrders,
  dentalLab,
  eyeSurgery,
}

class StaffTasksScreen extends ConsumerStatefulWidget {
  const StaffTasksScreen({
    super.key,
    this.initialTab = StaffTaskTab.tasks,
  });

  final StaffTaskTab initialTab;

  @override
  ConsumerState<StaffTasksScreen> createState() => _StaffTasksScreenState();
}

class _StaffTasksScreenState extends ConsumerState<StaffTasksScreen> {
  late StaffTaskTab _selectedTab;
  int _filterIndex =
      0; // 0: All Pending / All for Date, 1: Today / Pending, 2: Overdue
  DateTime _selectedDate = DateTime.now();

  @override
  void initState() {
    super.initState();
    _selectedTab = widget.initialTab;
  }

  @override
  Widget build(BuildContext context) {
    final isDesktop = MediaQuery.sizeOf(context).width >= 768.0;
    final currentUser = ref.watch(currentUserProvider);
    if (currentUser == null) {
      return const Center(child: CircularProgressIndicator());
    }

    return Column(
      crossAxisAlignment: CrossAxisAlignment.stretch,
      children: [
        // Sub-navigation bar under the Task section: Tasks | Inventory
        Container(
          padding: EdgeInsets.symmetric(
            horizontal:
                isDesktop ? AppSpacing.marginDesktop : AppSpacing.marginMobile,
            vertical: AppSpacing.sm,
          ),
          decoration: const BoxDecoration(
            color: AppColors.surface,
            border: Border(
              bottom: BorderSide(color: AppColors.outlineVariant),
            ),
          ),
          child: SingleChildScrollView(
            scrollDirection: Axis.horizontal,
            child: Row(
              children: [
                SegmentedButton<StaffTaskTab>(
                  segments: const [
                    ButtonSegment<StaffTaskTab>(
                      value: StaffTaskTab.tasks,
                      label: Text('Shift Tasks'),
                      icon: Icon(Icons.task_alt_outlined, size: 16),
                    ),
                    ButtonSegment<StaffTaskTab>(
                      value: StaffTaskTab.inventory,
                      label: Text('Inventory'),
                      icon: Icon(Icons.inventory_2_outlined, size: 16),
                    ),
                    ButtonSegment<StaffTaskTab>(
                      value: StaffTaskTab.vendors,
                      label: Text('Vendors'),
                      icon: Icon(Icons.local_shipping_outlined, size: 16),
                    ),
                    ButtonSegment<StaffTaskTab>(
                      value: StaffTaskTab.purchaseOrders,
                      label: Text('Purchase Orders'),
                      icon: Icon(Icons.receipt_long_outlined, size: 16),
                    ),
                    ButtonSegment<StaffTaskTab>(
                      value: StaffTaskTab.dentalLab,
                      label: Text('Dental Lab'),
                      icon: Icon(Icons.biotech_outlined, size: 16),
                    ),
                    ButtonSegment<StaffTaskTab>(
                      value: StaffTaskTab.eyeSurgery,
                      label: Text('Eye Surgery'),
                      icon: Icon(Icons.visibility_outlined, size: 16),
                    ),
                  ],
                  selected: {_selectedTab},
                  onSelectionChanged: (newSelection) {
                    setState(() => _selectedTab = newSelection.first);
                  },
                  style: SegmentedButton.styleFrom(
                    selectedBackgroundColor:
                        AppColors.primaryContainer.withValues(alpha: 0.2),
                    selectedForegroundColor: AppColors.primary,
                    textStyle: const TextStyle(
                      fontSize: 13,
                      fontWeight: FontWeight.w600,
                    ),
                    visualDensity: VisualDensity.compact,
                  ),
                ),
              ],
            ),
          ),
        ),

        // Body content based on selected tab:
        // Tasks -> Shift checklist, Inventory -> InventoryManagementContent, Vendors -> VendorManagementContent, Purchase Orders -> PurchaseOrderManagementContent, Dental Lab -> DentalLabContent
        Expanded(
          child: _selectedTab == StaffTaskTab.tasks
              ? _buildTasksView(isDesktop, currentUser)
              : _selectedTab == StaffTaskTab.inventory
                  ? const InventoryManagementContent()
                  : _selectedTab == StaffTaskTab.vendors
                      ? const VendorManagementContent()
                      : _selectedTab == StaffTaskTab.purchaseOrders
                          ? const PurchaseOrderManagementContent()
                          : _selectedTab == StaffTaskTab.dentalLab
                              ? const DentalLabContent()
                              : const EyeSurgeryScreen(),
        ),
      ],
    );
  }

  Widget _buildTasksView(bool isDesktop, dynamic currentUser) {
    final tasksAsync = ref.watch(staffTasksProvider(currentUser.id));

    return RefreshIndicator(
      onRefresh: () =>
          ref.read(staffTasksProvider(currentUser.id).notifier).fetchTasks(),
      child: SingleChildScrollView(
        physics: const AlwaysScrollableScrollPhysics(),
        padding: EdgeInsets.all(
            isDesktop ? AppSpacing.marginDesktop : AppSpacing.marginMobile),
        child: Column(
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            if (isDesktop)
              Row(
                mainAxisAlignment: MainAxisAlignment.spaceBetween,
                children: [
                  Expanded(
                    child: Column(
                      crossAxisAlignment: CrossAxisAlignment.start,
                      children: [
                        Text('My Shift Tasks',
                            style: AppTypography.displayLg
                                .copyWith(color: AppColors.onBackground)),
                        const SizedBox(height: AppSpacing.xs),
                        Text('Clinical checklist and patient care duties',
                            style: AppTypography.bodyLg
                                .copyWith(color: AppColors.onSurfaceVariant)),
                      ],
                    ),
                  ),
                  Expanded(
                    child: SingleChildScrollView(
                      scrollDirection: Axis.horizontal,
                      reverse: true,
                      child: Row(
                        mainAxisSize: MainAxisSize.min,
                        children: [
                          IconButton(
                            icon: const Icon(Icons.refresh),
                            tooltip: 'Refresh tasks',
                            onPressed: () => ref
                                .read(
                                    staffTasksProvider(currentUser.id).notifier)
                                .fetchTasks(),
                          ),
                          const SizedBox(width: AppSpacing.xs),
                          OutlinedButton.icon(
                            onPressed: () => setState(
                                () => _selectedTab = StaffTaskTab.inventory),
                            icon: const Icon(Icons.inventory_2_outlined,
                                size: 18),
                            label: const Text('Inventory'),
                            style: OutlinedButton.styleFrom(
                              padding: const EdgeInsets.symmetric(
                                  horizontal: 14, vertical: 8),
                            ),
                          ),
                          const SizedBox(width: AppSpacing.xs),
                          OutlinedButton.icon(
                            onPressed: () => setState(
                                () => _selectedTab = StaffTaskTab.vendors),
                            icon: const Icon(Icons.local_shipping_outlined,
                                size: 18),
                            label: const Text('Vendors'),
                            style: OutlinedButton.styleFrom(
                              padding: const EdgeInsets.symmetric(
                                  horizontal: 14, vertical: 8),
                            ),
                          ),
                          const SizedBox(width: AppSpacing.xs),
                          OutlinedButton.icon(
                            onPressed: () => setState(() =>
                                _selectedTab = StaffTaskTab.purchaseOrders),
                            icon: const Icon(Icons.receipt_long_outlined,
                                size: 18),
                            label: const Text('Purchase Orders'),
                            style: OutlinedButton.styleFrom(
                              padding: const EdgeInsets.symmetric(
                                  horizontal: 14, vertical: 8),
                            ),
                          ),
                          const SizedBox(width: AppSpacing.xs),
                          OutlinedButton.icon(
                            onPressed: () => Navigator.of(context).push(
                              MaterialPageRoute(
                                builder: (_) => const StaffTaskHistoryScreen(),
                              ),
                            ),
                            icon: const Icon(Icons.history, size: 18),
                            label: const Text('History'),
                            style: OutlinedButton.styleFrom(
                              padding: const EdgeInsets.symmetric(
                                  horizontal: 14, vertical: 8),
                            ),
                          ),
                        ],
                      ),
                    ),
                  ),
                ],
              )
            else ...[
              Row(
                mainAxisAlignment: MainAxisAlignment.spaceBetween,
                crossAxisAlignment: CrossAxisAlignment.start,
                children: [
                  Expanded(
                    child: Column(
                      crossAxisAlignment: CrossAxisAlignment.start,
                      children: [
                        Text('My Shift Tasks',
                            style: AppTypography.displayLg.copyWith(
                                color: AppColors.onBackground, fontSize: 26)),
                        const SizedBox(height: AppSpacing.xs),
                        Text('Clinical checklist and patient care duties',
                            style: AppTypography.bodyLg
                                .copyWith(color: AppColors.onSurfaceVariant)),
                      ],
                    ),
                  ),
                  Row(
                    mainAxisSize: MainAxisSize.min,
                    children: [
                      IconButton(
                        icon: const Icon(Icons.refresh),
                        tooltip: 'Refresh tasks',
                        onPressed: () => ref
                            .read(staffTasksProvider(currentUser.id).notifier)
                            .fetchTasks(),
                      ),
                      OutlinedButton.icon(
                        onPressed: () => setState(
                            () => _selectedTab = StaffTaskTab.inventory),
                        icon: const Icon(Icons.inventory_2_outlined, size: 16),
                        label: const Text('Inventory'),
                        style: OutlinedButton.styleFrom(
                          padding: const EdgeInsets.symmetric(
                              horizontal: 8, vertical: 6),
                        ),
                      ),
                      const SizedBox(width: AppSpacing.xs),
                      OutlinedButton.icon(
                        onPressed: () =>
                            setState(() => _selectedTab = StaffTaskTab.vendors),
                        icon:
                            const Icon(Icons.local_shipping_outlined, size: 16),
                        label: const Text('Vendors'),
                        style: OutlinedButton.styleFrom(
                          padding: const EdgeInsets.symmetric(
                              horizontal: 8, vertical: 6),
                        ),
                      ),
                      const SizedBox(width: AppSpacing.xs),
                      OutlinedButton.icon(
                        onPressed: () => setState(
                            () => _selectedTab = StaffTaskTab.purchaseOrders),
                        icon: const Icon(Icons.receipt_long_outlined, size: 16),
                        label: const Text('PO'),
                        style: OutlinedButton.styleFrom(
                          padding: const EdgeInsets.symmetric(
                              horizontal: 8, vertical: 6),
                        ),
                      ),
                      const SizedBox(width: AppSpacing.xs),
                      OutlinedButton.icon(
                        onPressed: () => Navigator.of(context).push(
                          MaterialPageRoute(
                            builder: (_) => const StaffTaskHistoryScreen(),
                          ),
                        ),
                        icon: const Icon(Icons.history, size: 16),
                        label: const Text('History'),
                        style: OutlinedButton.styleFrom(
                          padding: const EdgeInsets.symmetric(
                              horizontal: 8, vertical: 6),
                        ),
                      ),
                    ],
                  ),
                ],
              ),
            ],
            const SizedBox(height: AppSpacing.lg),

            // Date Selector Control on Staff Tasks Screen (Part 4)
            _buildDateSelector(isDesktop),

            tasksAsync.when(
              data: (tasks) {
                final isViewingToday =
                    DateUtils.isSameDay(_selectedDate, DateTime.now());

                List<TaskItem> operationalTasks;
                List<TaskItem> primaryTasks;
                List<TaskItem> overdueTasks;
                List<TaskItem> filtered;

                if (isViewingToday) {
                  operationalTasks =
                      TaskOperationalFilter.filterOperationalTasks(
                    tasks,
                    referenceDate: _selectedDate,
                  );
                  primaryTasks = operationalTasks
                      .where((t) =>
                          !TaskOperationalFilter.isOverdueCarryForward(
                              t, _selectedDate))
                      .toList();
                  overdueTasks = operationalTasks
                      .where((t) => TaskOperationalFilter.isOverdueCarryForward(
                          t, _selectedDate))
                      .toList();
                  filtered = _filterIndex == 1
                      ? primaryTasks
                      : _filterIndex == 2
                          ? overdueTasks
                          : operationalTasks;
                } else {
                  // Specific selected date tasks
                  final dateTasks = tasks
                      .where((t) =>
                          !t.isSurgeryTask &&
                          t.dueDate != null &&
                          DateUtils.isSameDay(
                              t.dueDate!.toLocal(), _selectedDate))
                      .toList();
                  primaryTasks = dateTasks
                      .where((t) =>
                          t.status != 'completed' && t.status != 'cancelled')
                      .toList();
                  // Overdue status depends on actual current time, not merely selecting a past date
                  overdueTasks = dateTasks.where((t) => t.isOverdue).toList();
                  operationalTasks = dateTasks;
                  filtered = _filterIndex == 1
                      ? primaryTasks
                      : _filterIndex == 2
                          ? overdueTasks
                          : dateTasks;
                }

                return Column(
                  crossAxisAlignment: CrossAxisAlignment.start,
                  children: [
                    // Operational / Date Header showing date and pending count
                    Container(
                      margin: const EdgeInsets.only(bottom: AppSpacing.md),
                      padding: const EdgeInsets.symmetric(
                          horizontal: AppSpacing.md, vertical: 8),
                      decoration: BoxDecoration(
                        color: AppColors.surfaceContainerLowest,
                        borderRadius:
                            BorderRadius.circular(AppSpacing.radiusMd),
                        border: Border.all(color: AppColors.outlineVariant),
                      ),
                      child: Row(
                        children: [
                          const Icon(Icons.today,
                              size: 18, color: AppColors.primary),
                          const SizedBox(width: AppSpacing.xs),
                          Text(
                            isViewingToday
                                ? 'Operational Tasks — Today (${DateFormat('d MMM yyyy').format(_selectedDate)})'
                                : 'Scheduled Tasks — ${DateFormat('EEEE, d MMM yyyy').format(_selectedDate)}',
                            style: AppTypography.bodyMd
                                .copyWith(fontWeight: FontWeight.w600),
                          ),
                          const Spacer(),
                          Container(
                            padding: const EdgeInsets.symmetric(
                                horizontal: 8, vertical: 2),
                            decoration: BoxDecoration(
                              color: AppColors.primaryContainer
                                  .withValues(alpha: 0.15),
                              borderRadius: BorderRadius.circular(10),
                            ),
                            child: Text(
                              isViewingToday
                                  ? '${operationalTasks.length} pending'
                                  : '${primaryTasks.length} pending',
                              style: AppTypography.labelCaps.copyWith(
                                color: AppColors.primary,
                                fontWeight: FontWeight.bold,
                              ),
                            ),
                          ),
                        ],
                      ),
                    ),
                    SingleChildScrollView(
                      scrollDirection: Axis.horizontal,
                      child: Row(
                        children: [
                          _buildFilterChip(
                            isViewingToday
                                ? 'All Pending (${operationalTasks.length})'
                                : 'All for Date (${operationalTasks.length})',
                            0,
                          ),
                          const SizedBox(width: AppSpacing.sm),
                          _buildFilterChip(
                            isViewingToday
                                ? "Today's Tasks (${primaryTasks.length})"
                                : 'Pending (${primaryTasks.length})',
                            1,
                          ),
                          const SizedBox(width: AppSpacing.sm),
                          _buildFilterChip(
                            'Overdue (${overdueTasks.length})',
                            2,
                          ),
                        ],
                      ),
                    ),
                    const SizedBox(height: AppSpacing.md),
                    if (filtered.isEmpty)
                      Padding(
                        padding:
                            const EdgeInsets.symmetric(vertical: AppSpacing.xl),
                        child: Center(
                          child: Column(
                            mainAxisSize: MainAxisSize.min,
                            children: [
                              const Icon(Icons.task_alt,
                                  size: 48, color: AppColors.outline),
                              const SizedBox(height: AppSpacing.sm),
                              Text(
                                _filterIndex == 1
                                    ? (isViewingToday
                                        ? 'No pending tasks scheduled for today.'
                                        : 'No pending tasks scheduled for this date.')
                                    : _filterIndex == 2
                                        ? 'No overdue carry-forward tasks.'
                                        : 'No tasks assigned for this shift date.',
                                style: AppTypography.bodyLg.copyWith(
                                    color: AppColors.onSurfaceVariant),
                              ),
                            ],
                          ),
                        ),
                      )
                    else
                      ListView.separated(
                        shrinkWrap: true,
                        physics: const NeverScrollableScrollPhysics(),
                        itemCount: filtered.length,
                        separatorBuilder: (_, __) =>
                            const SizedBox(height: AppSpacing.sm),
                        itemBuilder: (context, index) {
                          final item = filtered[index];
                          final isCompleted = item.status == 'completed';
                          final isOverdue = !item.isSurgeryTask &&
                              (TaskOperationalFilter.isOverdueCarryForward(
                                      item, DateTime.now()) ||
                                  item.isOverdue);

                          Color priorityColor;
                          if (item.priority == 'critical' ||
                              item.priority == 'high') {
                            priorityColor = AppColors.error;
                          } else if (item.priority == 'medium') {
                            priorityColor = AppColors.primaryContainer;
                          } else {
                            priorityColor = AppColors.onSurfaceVariant;
                          }

                          // Eye Surgery Shift Task: completion is driven by surgery workflow, no manual complete action
                          if (item.isSurgeryTask) {
                            return Material(
                              color: isCompleted
                                  ? AppColors.surfaceContainerLow
                                      .withValues(alpha: 0.5)
                                  : AppColors.surfaceContainerLowest,
                              shape: RoundedRectangleBorder(
                                borderRadius:
                                    BorderRadius.circular(AppSpacing.radiusLg),
                                side: BorderSide(
                                  color: isCompleted
                                      ? AppColors.outlineVariant
                                      : isOverdue
                                          ? AppColors.error
                                              .withValues(alpha: 0.5)
                                          : AppColors.primary
                                              .withValues(alpha: 0.3),
                                ),
                              ),
                              child: ListTile(
                                leading: Icon(
                                  isCompleted
                                      ? Icons.check_circle
                                      : Icons.pending_actions_outlined,
                                  color: isCompleted
                                      ? AppColors.primary
                                      : isOverdue
                                          ? AppColors.error
                                          : priorityColor,
                                ),
                                title: Text(
                                  item.title,
                                  style: AppTypography.bodyMd.copyWith(
                                    fontWeight: FontWeight.w600,
                                    decoration: isCompleted
                                        ? TextDecoration.lineThrough
                                        : null,
                                    color: isCompleted
                                        ? AppColors.outline
                                        : AppColors.onSurface,
                                  ),
                                ),
                                subtitle: Padding(
                                  padding: const EdgeInsets.only(top: 4),
                                  child: Column(
                                    crossAxisAlignment:
                                        CrossAxisAlignment.start,
                                    children: [
                                      Row(
                                        children: [
                                          if (item.dueDate != null) ...[
                                            Icon(
                                              Icons.access_time,
                                              size: 12,
                                              color: isOverdue
                                                  ? AppColors.error
                                                  : AppColors.outline,
                                            ),
                                            const SizedBox(width: 4),
                                            Text(
                                              isOverdue
                                                  ? TaskOperationalFilter
                                                      .formatDueDateMessage(
                                                          item.dueDate!)
                                                  : DateFormat('MMM d, h:mm a')
                                                      .format(item.dueDate!),
                                              style: AppTypography.dataMono
                                                  .copyWith(
                                                fontSize: 11,
                                                fontWeight: isOverdue
                                                    ? FontWeight.bold
                                                    : FontWeight.normal,
                                                color: isOverdue
                                                    ? AppColors.error
                                                    : AppColors.outline,
                                              ),
                                            ),
                                          ],
                                          if (item.description != null &&
                                              item.description!.isNotEmpty) ...[
                                            const SizedBox(width: 8),
                                            Expanded(
                                              child: Text(
                                                item.description!,
                                                maxLines: 1,
                                                overflow: TextOverflow.ellipsis,
                                                style: AppTypography.bodySm
                                                    .copyWith(
                                                  color: AppColors
                                                      .onSurfaceVariant,
                                                ),
                                              ),
                                            ),
                                          ],
                                        ],
                                      ),
                                      const SizedBox(height: 2),
                                      Text(
                                        isCompleted
                                            ? 'Completed on surgery discharge'
                                            : 'Pending — completes automatically on surgery discharge',
                                        style: AppTypography.bodySm.copyWith(
                                          color: isCompleted
                                              ? AppColors.primary
                                              : AppColors.onSurfaceVariant,
                                          fontSize: 11,
                                          fontStyle: FontStyle.italic,
                                        ),
                                      ),
                                    ],
                                  ),
                                ),
                                trailing: Wrap(
                                  crossAxisAlignment: WrapCrossAlignment.center,
                                  spacing: AppSpacing.xs,
                                  children: [
                                    if (isOverdue)
                                      Container(
                                        padding: const EdgeInsets.symmetric(
                                            horizontal: 8, vertical: 2),
                                        decoration: BoxDecoration(
                                          color: AppColors.error
                                              .withValues(alpha: 0.15),
                                          borderRadius:
                                              BorderRadius.circular(12),
                                          border: Border.all(
                                              color: AppColors.error
                                                  .withValues(alpha: 0.4)),
                                        ),
                                        child: Text(
                                          'OVERDUE',
                                          style:
                                              AppTypography.labelCaps.copyWith(
                                            color: AppColors.error,
                                            fontSize: 10,
                                            fontWeight: FontWeight.bold,
                                          ),
                                        ),
                                      ),
                                    Container(
                                      padding: const EdgeInsets.symmetric(
                                          horizontal: 8, vertical: 2),
                                      decoration: BoxDecoration(
                                        color: AppColors.primary
                                            .withValues(alpha: 0.12),
                                        borderRadius: BorderRadius.circular(12),
                                      ),
                                      child: Text(
                                        isCompleted
                                            ? 'SURGERY DISCHARGED'
                                            : 'EYE SURGERY',
                                        style: AppTypography.labelCaps.copyWith(
                                            color: AppColors.primary,
                                            fontSize: 10),
                                      ),
                                    ),
                                    IconButton(
                                      icon: const Icon(Icons.arrow_forward_ios,
                                          size: 14),
                                      tooltip: 'View Eye Surgery',
                                      onPressed: () {
                                        setState(() => _selectedTab =
                                            StaffTaskTab.eyeSurgery);
                                      },
                                    ),
                                  ],
                                ),
                                onTap: () {
                                  setState(() =>
                                      _selectedTab = StaffTaskTab.eyeSurgery);
                                },
                              ),
                            );
                          }

                          // Standard manually-created Shift Task: interactive checkbox
                          return Material(
                            color: isCompleted
                                ? AppColors.surfaceContainerLow
                                    .withValues(alpha: 0.5)
                                : AppColors.surfaceContainerLowest,
                            shape: RoundedRectangleBorder(
                              borderRadius:
                                  BorderRadius.circular(AppSpacing.radiusLg),
                              side: BorderSide(
                                color: isOverdue
                                    ? AppColors.error.withValues(alpha: 0.4)
                                    : AppColors.outlineVariant,
                              ),
                            ),
                            child: CheckboxListTile(
                              value: isCompleted,
                              onChanged: (val) async {
                                final newStatus =
                                    (val ?? false) ? 'completed' : 'pending';
                                try {
                                  await ref
                                      .read(staffTasksProvider(currentUser.id)
                                          .notifier)
                                      .updateStatus(
                                          item.id, newStatus, item.status);
                                  // Refresh admin provider in background so admin sees updated task
                                  ref
                                      .read(adminTasksProvider.notifier)
                                      .fetchTasks(silent: true);
                                } catch (e) {
                                  if (context.mounted) {
                                    ScaffoldMessenger.of(context).showSnackBar(
                                        SnackBar(
                                            content: Text(
                                                'Error updating task: $e')));
                                  }
                                }
                              },
                              activeColor: AppColors.primary,
                              controlAffinity: ListTileControlAffinity.leading,
                              title: Text(
                                item.title,
                                style: AppTypography.bodyMd.copyWith(
                                  fontWeight: FontWeight.w600,
                                  decoration: isCompleted
                                      ? TextDecoration.lineThrough
                                      : null,
                                  color: isCompleted
                                      ? AppColors.outline
                                      : AppColors.onSurface,
                                ),
                              ),
                              subtitle: Padding(
                                padding: const EdgeInsets.only(top: 4),
                                child: Row(
                                  children: [
                                    if (item.dueDate != null) ...[
                                      Icon(
                                        Icons.access_time,
                                        size: 12,
                                        color: isOverdue
                                            ? AppColors.error
                                            : AppColors.outline,
                                      ),
                                      const SizedBox(width: 4),
                                      Text(
                                        isOverdue
                                            ? TaskOperationalFilter
                                                .formatDueDateMessage(
                                                    item.dueDate!)
                                            : DateFormat('MMM d, h:mm a')
                                                .format(item.dueDate!),
                                        style: AppTypography.dataMono.copyWith(
                                          fontSize: 11,
                                          fontWeight: isOverdue
                                              ? FontWeight.bold
                                              : FontWeight.normal,
                                          color: isOverdue
                                              ? AppColors.error
                                              : AppColors.outline,
                                        ),
                                      ),
                                    ],
                                    if (item.description != null &&
                                        item.description!.isNotEmpty) ...[
                                      const SizedBox(width: 8),
                                      Expanded(
                                        child: Text(
                                          item.description!,
                                          maxLines: 1,
                                          overflow: TextOverflow.ellipsis,
                                          style: AppTypography.bodySm.copyWith(
                                              color:
                                                  AppColors.onSurfaceVariant),
                                        ),
                                      ),
                                    ],
                                  ],
                                ),
                              ),
                              secondary: Wrap(
                                crossAxisAlignment: WrapCrossAlignment.center,
                                spacing: 4,
                                children: [
                                  if (isOverdue)
                                    Container(
                                      padding: const EdgeInsets.symmetric(
                                          horizontal: 8, vertical: 2),
                                      decoration: BoxDecoration(
                                        color: AppColors.error
                                            .withValues(alpha: 0.15),
                                        borderRadius: BorderRadius.circular(12),
                                        border: Border.all(
                                            color: AppColors.error
                                                .withValues(alpha: 0.4)),
                                      ),
                                      child: Text(
                                        'OVERDUE',
                                        style: AppTypography.labelCaps.copyWith(
                                          color: AppColors.error,
                                          fontSize: 10,
                                          fontWeight: FontWeight.bold,
                                        ),
                                      ),
                                    ),
                                  Container(
                                    padding: const EdgeInsets.symmetric(
                                        horizontal: 8, vertical: 2),
                                    decoration: BoxDecoration(
                                      color:
                                          priorityColor.withValues(alpha: 0.15),
                                      borderRadius: BorderRadius.circular(12),
                                    ),
                                    child: Text(
                                      item.priority.toUpperCase(),
                                      style: AppTypography.labelCaps.copyWith(
                                          color: priorityColor, fontSize: 10),
                                    ),
                                  ),
                                ],
                              ),
                            ),
                          );
                        },
                      ),
                  ],
                );
              },
              loading: () => const Center(
                child: Padding(
                  padding: EdgeInsets.all(AppSpacing.xl),
                  child: CircularProgressIndicator(),
                ),
              ),
              error: (e, st) => Center(
                child: Padding(
                  padding: const EdgeInsets.all(AppSpacing.xl),
                  child: Column(
                    mainAxisSize: MainAxisSize.min,
                    children: [
                      const Icon(Icons.error_outline,
                          size: 48, color: AppColors.error),
                      const SizedBox(height: AppSpacing.sm),
                      Text('Error loading tasks: $e',
                          textAlign: TextAlign.center),
                      const SizedBox(height: AppSpacing.md),
                      FilledButton.icon(
                        icon: const Icon(Icons.refresh),
                        label: const Text('Retry'),
                        onPressed: () => ref
                            .read(staffTasksProvider(currentUser.id).notifier)
                            .fetchTasks(),
                      ),
                    ],
                  ),
                ),
              ),
            ),
          ],
        ),
      ),
    );
  }

  Widget _buildFilterChip(String label, int index) {
    final isSelected = _filterIndex == index;
    return ChoiceChip(
      label: Text(label),
      selected: isSelected,
      onSelected: (val) {
        if (val) setState(() => _filterIndex = index);
      },
      selectedColor: AppColors.primaryContainer.withValues(alpha: 0.2),
      backgroundColor: AppColors.surfaceContainerLowest,
      labelStyle: AppTypography.bodyMd.copyWith(
        color: isSelected ? AppColors.primary : AppColors.onSurfaceVariant,
        fontWeight: isSelected ? FontWeight.bold : FontWeight.normal,
      ),
    );
  }

  Widget _buildDateSelector(bool isDesktop) {
    final isToday = DateUtils.isSameDay(_selectedDate, DateTime.now());
    final dateLabel = isToday
        ? 'Today, ${DateFormat('d MMM yyyy').format(_selectedDate)}'
        : DateFormat('EEE, d MMM yyyy').format(_selectedDate);

    return Container(
      margin: const EdgeInsets.only(bottom: AppSpacing.md),
      padding:
          const EdgeInsets.symmetric(horizontal: AppSpacing.sm, vertical: 6),
      decoration: BoxDecoration(
        color: AppColors.surfaceContainerLowest,
        borderRadius: BorderRadius.circular(AppSpacing.radiusMd),
        border: Border.all(color: AppColors.outlineVariant),
      ),
      child: Row(
        children: [
          IconButton(
            key: const Key('staff_tasks_prev_date_button'),
            icon: const Icon(Icons.chevron_left),
            tooltip: 'Previous Day',
            visualDensity: VisualDensity.compact,
            onPressed: () {
              setState(() {
                _selectedDate = _selectedDate.subtract(const Duration(days: 1));
              });
            },
          ),
          InkWell(
            key: const Key('staff_tasks_date_picker_button'),
            borderRadius: BorderRadius.circular(AppSpacing.radiusSm),
            onTap: () async {
              final picked = await showDatePicker(
                context: context,
                initialDate: _selectedDate,
                firstDate: DateTime(2020),
                lastDate: DateTime(2035),
              );
              if (picked != null && mounted) {
                setState(() => _selectedDate = picked);
              }
            },
            child: Padding(
              padding: const EdgeInsets.symmetric(horizontal: 8, vertical: 6),
              child: Row(
                mainAxisSize: MainAxisSize.min,
                children: [
                  const Icon(Icons.calendar_month_outlined,
                      size: 18, color: AppColors.primary),
                  const SizedBox(width: 6),
                  Text(
                    dateLabel,
                    style: AppTypography.bodyMd.copyWith(
                      fontWeight: FontWeight.bold,
                      color: AppColors.onSurface,
                    ),
                  ),
                  const SizedBox(width: 4),
                  const Icon(Icons.arrow_drop_down,
                      size: 20, color: AppColors.outline),
                ],
              ),
            ),
          ),
          IconButton(
            key: const Key('staff_tasks_next_date_button'),
            icon: const Icon(Icons.chevron_right),
            tooltip: 'Next Day',
            visualDensity: VisualDensity.compact,
            onPressed: () {
              setState(() {
                _selectedDate = _selectedDate.add(const Duration(days: 1));
              });
            },
          ),
          const Spacer(),
          TextButton.icon(
            key: const Key('staff_tasks_today_button'),
            icon: const Icon(Icons.today, size: 16),
            label: const Text('Today'),
            style: TextButton.styleFrom(
              foregroundColor: isToday ? AppColors.outline : AppColors.primary,
              visualDensity: VisualDensity.compact,
            ),
            onPressed: isToday
                ? null
                : () {
                    setState(() => _selectedDate = DateTime.now());
                  },
          ),
        ],
      ),
    );
  }
}
