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
import '../../staff/providers/task_provider.dart';
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
  int _filterIndex = 0; // 0: All, 1: Pending, 2: Completed
  DateTime _selectedShiftDate = DateTime.now();

  static bool _isSameDay(DateTime a, DateTime b) =>
      a.year == b.year && a.month == b.month && a.day == b.day;

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
                                .read(staffTasksProvider(currentUser.id).notifier)
                                .fetchTasks(),
                          ),
                          const SizedBox(width: AppSpacing.xs),
                          OutlinedButton.icon(
                            onPressed: () => setState(
                                () => _selectedTab = StaffTaskTab.inventory),
                            icon: const Icon(Icons.inventory_2_outlined, size: 18),
                            label: const Text('Inventory'),
                            style: OutlinedButton.styleFrom(
                              padding: const EdgeInsets.symmetric(
                                  horizontal: 14, vertical: 8),
                            ),
                          ),
                          const SizedBox(width: AppSpacing.xs),
                          OutlinedButton.icon(
                            onPressed: () =>
                                setState(() => _selectedTab = StaffTaskTab.vendors),
                            icon:
                                const Icon(Icons.local_shipping_outlined, size: 18),
                            label: const Text('Vendors'),
                            style: OutlinedButton.styleFrom(
                              padding: const EdgeInsets.symmetric(
                                  horizontal: 14, vertical: 8),
                            ),
                          ),
                          const SizedBox(width: AppSpacing.xs),
                          OutlinedButton.icon(
                            onPressed: () => setState(
                                () => _selectedTab = StaffTaskTab.purchaseOrders),
                            icon: const Icon(Icons.receipt_long_outlined, size: 18),
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
            tasksAsync.when(
              data: (tasks) {
                final shiftTasks = tasks.where((t) {
                  if (t.dueDate != null) {
                    return _isSameDay(t.dueDate!, _selectedShiftDate);
                  }
                  return _isSameDay(_selectedShiftDate, DateTime.now());
                }).toList();

                final pendingCount = shiftTasks
                    .where((t) =>
                        t.status != 'completed' && t.status != 'cancelled')
                    .length;
                final completedCount =
                    shiftTasks.where((t) => t.status == 'completed').length;

                final filtered = shiftTasks.where((t) {
                  final isCompleted = t.status == 'completed';
                  if (_filterIndex == 1) {
                    return !isCompleted && t.status != 'cancelled';
                  }
                  if (_filterIndex == 2) {
                    return isCompleted;
                  }
                  return t.status != 'cancelled';
                }).toList();

                return Column(
                  crossAxisAlignment: CrossAxisAlignment.start,
                  children: [
                    // Dynamic Shift Date Selector
                    Container(
                      margin: const EdgeInsets.only(bottom: AppSpacing.md),
                      padding: const EdgeInsets.symmetric(
                          horizontal: AppSpacing.sm, vertical: 4),
                      decoration: BoxDecoration(
                        color: AppColors.surfaceContainerLowest,
                        borderRadius:
                            BorderRadius.circular(AppSpacing.radiusMd),
                        border: Border.all(color: AppColors.outlineVariant),
                      ),
                      child: Row(
                        mainAxisAlignment: MainAxisAlignment.spaceBetween,
                        children: [
                          IconButton(
                            icon: const Icon(Icons.chevron_left),
                            tooltip: 'Previous Day',
                            onPressed: () {
                              setState(() {
                                _selectedShiftDate = _selectedShiftDate
                                    .subtract(const Duration(days: 1));
                              });
                            },
                          ),
                          InkWell(
                            onTap: () async {
                              final picked = await showDatePicker(
                                context: context,
                                initialDate: _selectedShiftDate,
                                firstDate: DateTime(2020),
                                lastDate: DateTime(2035),
                              );
                              if (picked != null) {
                                setState(() => _selectedShiftDate = picked);
                              }
                            },
                            child: Padding(
                              padding: const EdgeInsets.symmetric(
                                  horizontal: 8, vertical: 4),
                              child: Row(
                                mainAxisSize: MainAxisSize.min,
                                children: [
                                  const Icon(Icons.calendar_today,
                                      size: 16, color: AppColors.primary),
                                  const SizedBox(width: AppSpacing.xs),
                                  Text(
                                    _isSameDay(
                                            _selectedShiftDate, DateTime.now())
                                        ? 'Today (${DateFormat('d MMM').format(_selectedShiftDate)})'
                                        : DateFormat('EEE, d MMM yyyy')
                                            .format(_selectedShiftDate),
                                    style: AppTypography.bodyMd.copyWith(
                                        fontWeight: FontWeight.w600),
                                  ),
                                ],
                              ),
                            ),
                          ),
                          Row(
                            mainAxisSize: MainAxisSize.min,
                            children: [
                              if (!_isSameDay(
                                  _selectedShiftDate, DateTime.now()))
                                TextButton(
                                  onPressed: () {
                                    setState(
                                        () => _selectedShiftDate = DateTime.now());
                                  },
                                  child: const Text('Today'),
                                ),
                              IconButton(
                                icon: const Icon(Icons.chevron_right),
                                tooltip: 'Next Day',
                                onPressed: () {
                                  setState(() {
                                    _selectedShiftDate = _selectedShiftDate
                                        .add(const Duration(days: 1));
                                  });
                                },
                              ),
                            ],
                          ),
                        ],
                      ),
                    ),
                    SingleChildScrollView(
                      scrollDirection: Axis.horizontal,
                      child: Row(
                        children: [
                          _buildFilterChip(
                              'All (${pendingCount + completedCount})', 0),
                          const SizedBox(width: AppSpacing.sm),
                          _buildFilterChip('Pending ($pendingCount)', 1),
                          const SizedBox(width: AppSpacing.sm),
                          _buildFilterChip('Completed ($completedCount)', 2),
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
                                    ? 'No pending shift tasks for this date.'
                                    : _filterIndex == 2
                                        ? 'No completed tasks yet for this date.'
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
                                      : AppColors.primary.withValues(alpha: 0.3),
                                ),
                              ),
                              child: ListTile(
                                leading: Icon(
                                  isCompleted
                                      ? Icons.check_circle
                                      : Icons.pending_actions_outlined,
                                  color: isCompleted
                                      ? AppColors.primary
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
                                            const Icon(Icons.access_time,
                                                size: 12,
                                                color: AppColors.outline),
                                            const SizedBox(width: 4),
                                            Text(
                                              DateFormat('MMM d, h:mm a')
                                                  .format(item.dueDate!),
                                              style: AppTypography.dataMono
                                                  .copyWith(
                                                fontSize: 11,
                                                color: item.isOverdue
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
                                                overflow:
                                                    TextOverflow.ellipsis,
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
                                    Container(
                                      padding: const EdgeInsets.symmetric(
                                          horizontal: 8, vertical: 2),
                                      decoration: BoxDecoration(
                                        color: AppColors.primary
                                            .withValues(alpha: 0.12),
                                        borderRadius:
                                            BorderRadius.circular(12),
                                      ),
                                      child: Text(
                                        isCompleted
                                            ? 'SURGERY DISCHARGED'
                                            : 'EYE SURGERY',
                                        style: AppTypography.labelCaps
                                            .copyWith(
                                                color: AppColors.primary,
                                                fontSize: 10),
                                      ),
                                    ),
                                    IconButton(
                                      icon: const Icon(
                                          Icons.arrow_forward_ios,
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
                                  setState(() => _selectedTab =
                                      StaffTaskTab.eyeSurgery);
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
                              side:
                                  const BorderSide(color: AppColors.outlineVariant),
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
                                      const Icon(Icons.access_time,
                                          size: 12, color: AppColors.outline),
                                      const SizedBox(width: 4),
                                      Text(
                                        DateFormat('MMM d, h:mm a')
                                            .format(item.dueDate!),
                                        style: AppTypography.dataMono.copyWith(
                                          fontSize: 11,
                                          color: item.isOverdue
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
                              secondary: Container(
                                padding: const EdgeInsets.symmetric(
                                    horizontal: 8, vertical: 2),
                                decoration: BoxDecoration(
                                  color: priorityColor.withValues(alpha: 0.15),
                                  borderRadius: BorderRadius.circular(12),
                                ),
                                child: Text(
                                  item.priority.toUpperCase(),
                                  style: AppTypography.labelCaps.copyWith(
                                      color: priorityColor, fontSize: 10),
                                ),
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
}
