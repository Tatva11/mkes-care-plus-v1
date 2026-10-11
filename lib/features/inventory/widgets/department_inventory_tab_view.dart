import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';

import '../../../core/theme/app_colors.dart';
import '../../../core/theme/app_spacing.dart';
import '../../../core/theme/app_typography.dart';
import '../../auth/providers/auth_provider.dart';
import '../../department/providers/departments_provider.dart';
import '../models/department_inventory_item.dart';
import '../models/stock_request_model.dart';
import '../providers/department_inventory_provider.dart';
import 'stock_request_details_dialog.dart';
import 'stock_request_form_dialog.dart';

/// Department Inventory & Stock Requests Tab View.
/// Provides department-wise stock views and request approval/fulfillment workflows.
class DepartmentInventoryTabView extends ConsumerStatefulWidget {
  const DepartmentInventoryTabView({super.key});

  @override
  ConsumerState<DepartmentInventoryTabView> createState() =>
      _DepartmentInventoryTabViewState();
}

class _DepartmentInventoryTabViewState
    extends ConsumerState<DepartmentInventoryTabView> {
  final _searchController = TextEditingController();
  int _currentSubTab = 0; // 0 = Allocated Inventory, 1 = Stock Requests

  static const Color _successColor = Color(0xFF2E7D32);

  @override
  void dispose() {
    _searchController.dispose();
    super.dispose();
  }

  @override
  Widget build(BuildContext context) {
    final profile = ref.watch(currentProfileProvider).valueOrNull;
    final isAdmin = profile?.role == 'admin';
    final userDeptId = profile?.departmentId;
    final userDeptName =
        profile?.departmentName ?? profile?.department ?? 'My Department';

    final selectedDeptId = ref.watch(departmentInventoryFilterDeptProvider) ??
        (isAdmin ? null : userDeptId);

    final departmentsAsync = ref.watch(departmentsProvider);
    final isDesktop = MediaQuery.of(context).size.width >= 900;

    return SingleChildScrollView(
      padding: const EdgeInsets.all(AppSpacing.md),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          // Header Bar
          Row(
            crossAxisAlignment: CrossAxisAlignment.center,
            children: [
              Expanded(
                child: Column(
                  crossAxisAlignment: CrossAxisAlignment.start,
                  children: [
                    Text(
                      'Department Stock & Usage',
                      style: AppTypography.headlineMd.copyWith(
                        fontWeight: FontWeight.bold,
                        fontSize: 22,
                      ),
                    ),
                    const SizedBox(height: 2),
                    Text(
                      isAdmin
                          ? 'Unified stock tracking by department and requisition history.'
                          : 'Stock assigned to $userDeptName.',
                      style: AppTypography.bodySm.copyWith(
                        color: AppColors.onSurfaceVariant,
                      ),
                    ),
                  ],
                ),
              ),
              FilledButton.icon(
                onPressed: () async {
                  await showDialog<bool>(
                    context: context,
                    builder: (_) => StockRequestFormDialog(
                      forcedDepartmentId: isAdmin ? selectedDeptId : userDeptId,
                    ),
                  );
                },
                icon: const Icon(Icons.assignment_outlined, size: 18),
                label: const Text('Requisition Stock'),
                style: FilledButton.styleFrom(
                  backgroundColor: AppColors.primary,
                  padding: const EdgeInsets.symmetric(
                    horizontal: AppSpacing.md,
                    vertical: AppSpacing.sm,
                  ),
                ),
              ),
            ],
          ),
          const SizedBox(height: AppSpacing.md),

          // Filters & Sub-tabs Bar
          Wrap(
            spacing: AppSpacing.md,
            runSpacing: AppSpacing.sm,
            crossAxisAlignment: WrapCrossAlignment.center,
            children: [
              // Sub-tab switcher
              SegmentedButton<int>(
                segments: const [
                  ButtonSegment<int>(
                    value: 0,
                    label: Text('Department Stock'),
                    icon: Icon(Icons.inventory_2_outlined, size: 16),
                  ),
                  ButtonSegment<int>(
                    value: 1,
                    label: Text('Requisitions & Usage'),
                    icon: Icon(Icons.history_outlined, size: 16),
                  ),
                ],
                selected: {_currentSubTab},
                onSelectionChanged: (set) =>
                    setState(() => _currentSubTab = set.first),
                style: SegmentedButton.styleFrom(
                  visualDensity: VisualDensity.compact,
                ),
              ),

              // Department Selector (for Admin)
              if (isAdmin)
                departmentsAsync.when(
                  loading: () => const SizedBox(
                    width: 24,
                    height: 24,
                    child: CircularProgressIndicator(strokeWidth: 2),
                  ),
                  error: (e, _) => Text('Error: $e'),
                  data: (depts) => SizedBox(
                    width: 220,
                    child: DropdownButtonFormField<String?>(
                      initialValue: selectedDeptId,
                      isExpanded: true,
                      decoration: const InputDecoration(
                        labelText: 'Department',
                        isDense: true,
                        contentPadding: EdgeInsets.symmetric(
                            horizontal: 10, vertical: 8),
                        border: OutlineInputBorder(),
                        prefixIcon: Icon(Icons.business_outlined, size: 18),
                      ),
                      items: [
                        const DropdownMenuItem<String?>(
                          value: null,
                          child: Text('All Departments'),
                        ),
                        ...depts.map((d) => DropdownMenuItem<String?>(
                              value: d.id,
                              child: Text(d.name, overflow: TextOverflow.ellipsis),
                            )),
                      ],
                      onChanged: (val) {
                        ref
                            .read(departmentInventoryFilterDeptProvider.notifier)
                            .state = val;
                      },
                    ),
                  ),
                ),

              // Search box
              SizedBox(
                width: 260,
                child: TextField(
                  controller: _searchController,
                  decoration: InputDecoration(
                    hintText: 'Search items...',
                    prefixIcon: const Icon(Icons.search, size: 20),
                    isDense: true,
                    contentPadding: const EdgeInsets.symmetric(
                        horizontal: 10, vertical: 8),
                    border: const OutlineInputBorder(),
                    suffixIcon: _searchController.text.isNotEmpty
                        ? IconButton(
                            icon: const Icon(Icons.clear, size: 16),
                            onPressed: () {
                              _searchController.clear();
                              if (_currentSubTab == 0) {
                                ref
                                    .read(
                                        departmentInventorySearchQueryProvider
                                            .notifier)
                                    .state = '';
                              } else {
                                ref
                                    .read(stockRequestsSearchQueryProvider
                                        .notifier)
                                    .state = '';
                              }
                            },
                          )
                        : null,
                  ),
                  onChanged: (val) {
                    if (_currentSubTab == 0) {
                      ref
                          .read(departmentInventorySearchQueryProvider.notifier)
                          .state = val;
                    } else {
                      ref
                          .read(stockRequestsSearchQueryProvider.notifier)
                          .state = val;
                    }
                  },
                ),
              ),

              // Low stock toggle (only for Allocated Stock)
              if (_currentSubTab == 0)
                FilterChip(
                  label: const Text('Low Stock Only'),
                  selected:
                      ref.watch(departmentInventoryLowStockFilterProvider),
                  onSelected: (val) {
                    ref
                        .read(
                            departmentInventoryLowStockFilterProvider.notifier)
                        .state = val;
                  },
                ),

              // Status filter (only for Stock Requests)
              if (_currentSubTab == 1)
                DropdownButton<String>(
                  value: ref.watch(stockRequestsStatusFilterProvider),
                  items: const [
                    DropdownMenuItem(value: 'all', child: Text('All Statuses')),
                    DropdownMenuItem(value: 'transferred', child: Text('Transferred')),
                    DropdownMenuItem(value: 'fulfilled', child: Text('Fulfilled')),
                    DropdownMenuItem(value: 'pending', child: Text('Pending (Legacy)')),
                    DropdownMenuItem(value: 'rejected', child: Text('Rejected')),
                  ],
                  onChanged: (val) {
                    if (val != null) {
                      ref
                          .read(stockRequestsStatusFilterProvider.notifier)
                          .state = val;
                    }
                  },
                ),
            ],
          ),
          const SizedBox(height: AppSpacing.md),

          // Main Sub-tab Body
          if (_currentSubTab == 0)
            _buildAllocatedStockSection(selectedDeptId, isDesktop)
          else
            _buildStockRequestsSection(selectedDeptId, isDesktop),
        ],
      ),
    );
  }

  Widget _buildAllocatedStockSection(String? deptId, bool isDesktop) {
    final itemsAsync = ref.watch(departmentInventoryItemsProvider(deptId));

    return itemsAsync.when(
      loading: () => const Center(
        child: Padding(
          padding: EdgeInsets.all(AppSpacing.xl),
          child: CircularProgressIndicator(),
        ),
      ),
      error: (e, _) => Container(
        width: double.infinity,
        padding: const EdgeInsets.all(AppSpacing.md),
        decoration: BoxDecoration(
          color: AppColors.errorContainer.withValues(alpha: 0.2),
          borderRadius: BorderRadius.circular(AppSpacing.radiusMd),
        ),
        child: Text(
          'Unable to load department inventory: $e',
          style: AppTypography.bodySm.copyWith(color: AppColors.error),
        ),
      ),
      data: (items) {
        if (items.isEmpty) {
          return Container(
            width: double.infinity,
            padding: const EdgeInsets.all(AppSpacing.xl),
            decoration: BoxDecoration(
              color: AppColors.surfaceContainerLowest,
              borderRadius: BorderRadius.circular(AppSpacing.radiusLg),
              border: Border.all(color: AppColors.outlineVariant),
            ),
            child: Column(
              children: [
                const Icon(
                  Icons.inventory_2_outlined,
                  size: 48,
                  color: AppColors.outline,
                ),
                const SizedBox(height: AppSpacing.sm),
                Text(
                  'No allocated stock found for this department.',
                  style: AppTypography.headlineMd.copyWith(fontSize: 16),
                ),
                const SizedBox(height: AppSpacing.xs),
                Text(
                  'Submit a stock transfer to allocate items from central inventory.',
                  style: AppTypography.bodySm.copyWith(
                    color: AppColors.onSurfaceVariant,
                  ),
                ),
              ],
            ),
          );
        }

        return ListView.separated(
          shrinkWrap: true,
          physics: const NeverScrollableScrollPhysics(),
          itemCount: items.length,
          separatorBuilder: (_, __) => const SizedBox(height: AppSpacing.xs),
          itemBuilder: (context, index) {
            final item = items[index];
            return _buildDepartmentItemTile(item);
          },
        );
      },
    );
  }

  Widget _buildDepartmentItemTile(DepartmentInventoryItem item) {
    final isLow = item.isLowStock;

    return Card(
      elevation: 0,
      margin: EdgeInsets.zero,
      shape: RoundedRectangleBorder(
        borderRadius: BorderRadius.circular(AppSpacing.radiusMd),
        side: BorderSide(
          color: isLow
              ? Colors.amber.shade400
              : AppColors.outlineVariant.withValues(alpha: 0.6),
        ),
      ),
      child: Padding(
        padding: const EdgeInsets.all(AppSpacing.md),
        child: Row(
          children: [
            CircleAvatar(
              backgroundColor: isLow
                  ? Colors.amber.shade100
                  : AppColors.primaryContainer.withValues(alpha: 0.2),
              child: Icon(
                isLow ? Icons.warning_amber_rounded : Icons.inventory_2_outlined,
                color: isLow ? Colors.amber.shade900 : AppColors.primary,
                size: 20,
              ),
            ),
            const SizedBox(width: AppSpacing.md),
            Expanded(
              child: Column(
                crossAxisAlignment: CrossAxisAlignment.start,
                children: [
                  Row(
                    children: [
                      Flexible(
                        child: Text(
                          item.itemName,
                          style: AppTypography.bodyMd.copyWith(
                            fontWeight: FontWeight.bold,
                          ),
                          overflow: TextOverflow.ellipsis,
                        ),
                      ),
                      if (item.itemSku != null) ...[
                        const SizedBox(width: AppSpacing.xs),
                        Text(
                          '(${item.itemSku})',
                          style: AppTypography.bodySm.copyWith(
                            color: AppColors.onSurfaceVariant,
                          ),
                        ),
                      ],
                    ],
                  ),
                  const SizedBox(height: 2),
                  Wrap(
                    spacing: AppSpacing.sm,
                    children: [
                      Text(
                        'Dept: ${item.departmentName}',
                        style: AppTypography.bodySm.copyWith(
                          color: AppColors.onSurfaceVariant,
                        ),
                      ),
                      Text(
                        'Min: ${item.formattedMinimumStock} ${item.itemUnit}',
                        style: AppTypography.bodySm.copyWith(
                          color: AppColors.onSurfaceVariant,
                        ),
                      ),
                      if (item.itemCategory != null)
                        Text(
                          '• ${item.itemCategory}',
                          style: AppTypography.bodySm.copyWith(
                            color: AppColors.onSurfaceVariant,
                          ),
                        ),
                    ],
                  ),
                ],
              ),
            ),
            Column(
              crossAxisAlignment: CrossAxisAlignment.end,
              children: [
                Text(
                  '${item.formattedQuantity} ${item.itemUnit}',
                  style: AppTypography.headlineMd.copyWith(
                    fontWeight: FontWeight.bold,
                    fontSize: 18,
                    color: isLow ? Colors.amber.shade900 : AppColors.onSurface,
                  ),
                ),
                if (isLow)
                  Container(
                    padding: const EdgeInsets.symmetric(
                        horizontal: 6, vertical: 2),
                    decoration: BoxDecoration(
                      color: Colors.amber.shade100,
                      borderRadius: BorderRadius.circular(4),
                    ),
                    child: Text(
                      'LOW STOCK',
                      style: AppTypography.labelCaps.copyWith(
                        color: Colors.amber.shade900,
                        fontSize: 9,
                        fontWeight: FontWeight.bold,
                      ),
                    ),
                  ),
              ],
            ),
          ],
        ),
      ),
    );
  }

  Widget _buildStockRequestsSection(String? deptId, bool isDesktop) {
    final requestsAsync = ref.watch(stockRequestsListProvider(deptId));

    return requestsAsync.when(
      loading: () => const Center(
        child: Padding(
          padding: EdgeInsets.all(AppSpacing.xl),
          child: CircularProgressIndicator(),
        ),
      ),
      error: (e, _) => Container(
        width: double.infinity,
        padding: const EdgeInsets.all(AppSpacing.md),
        decoration: BoxDecoration(
          color: AppColors.errorContainer.withValues(alpha: 0.2),
          borderRadius: BorderRadius.circular(AppSpacing.radiusMd),
        ),
        child: Text(
          'Unable to load stock requests: $e',
          style: AppTypography.bodySm.copyWith(color: AppColors.error),
        ),
      ),
      data: (requests) {
        if (requests.isEmpty) {
          return Container(
            width: double.infinity,
            padding: const EdgeInsets.all(AppSpacing.xl),
            decoration: BoxDecoration(
              color: AppColors.surfaceContainerLowest,
              borderRadius: BorderRadius.circular(AppSpacing.radiusLg),
              border: Border.all(color: AppColors.outlineVariant),
            ),
            child: Column(
              children: [
                const Icon(
                  Icons.assignment_outlined,
                  size: 48,
                  color: AppColors.outline,
                ),
                const SizedBox(height: AppSpacing.sm),
                Text(
                  'No stock transfers found.',
                  style: AppTypography.headlineMd.copyWith(fontSize: 16),
                ),
                const SizedBox(height: AppSpacing.xs),
                Text(
                  'Click "Transfer Stock" to submit a new stock transfer.',
                  style: AppTypography.bodySm.copyWith(
                    color: AppColors.onSurfaceVariant,
                  ),
                ),
              ],
            ),
          );
        }

        return ListView.separated(
          shrinkWrap: true,
          physics: const NeverScrollableScrollPhysics(),
          itemCount: requests.length,
          separatorBuilder: (_, __) => const SizedBox(height: AppSpacing.xs),
          itemBuilder: (context, index) {
            final req = requests[index];
            return _buildStockRequestTile(req);
          },
        );
      },
    );
  }

  Widget _buildStockRequestTile(StockRequestModel req) {
    return Card(
      elevation: 0,
      margin: EdgeInsets.zero,
      shape: RoundedRectangleBorder(
        borderRadius: BorderRadius.circular(AppSpacing.radiusMd),
        side: const BorderSide(color: AppColors.outlineVariant),
      ),
      child: ListTile(
        contentPadding: const EdgeInsets.symmetric(
          horizontal: AppSpacing.md,
          vertical: AppSpacing.xs,
        ),
        leading: CircleAvatar(
          backgroundColor: AppColors.primaryContainer.withValues(alpha: 0.2),
          child: const Icon(
            Icons.assignment_outlined,
            color: AppColors.primary,
            size: 20,
          ),
        ),
        title: Row(
          children: [
            Text(
              req.requestNumber,
              style: AppTypography.dataMono.copyWith(
                fontWeight: FontWeight.bold,
                color: AppColors.primary,
              ),
            ),
            const SizedBox(width: AppSpacing.sm),
            Flexible(
              child: Text(
                '${req.itemName} (${req.formattedRequestedQuantity} ${req.itemUnit})',
                style: AppTypography.bodyMd.copyWith(
                  fontWeight: FontWeight.w600,
                ),
                overflow: TextOverflow.ellipsis,
              ),
            ),
          ],
        ),
        subtitle: Column(
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            const SizedBox(height: 2),
            Text(
              'Dept: ${req.departmentName} · By: ${req.requestedByName ?? "Staff"} on ${req.formattedCreatedAt}',
              style: AppTypography.bodySm.copyWith(
                color: AppColors.onSurfaceVariant,
              ),
            ),
            if (req.rejectionReason != null && req.rejectionReason!.isNotEmpty)
              Text(
                'Rejection: ${req.rejectionReason}',
                style: AppTypography.bodySm.copyWith(
                  color: AppColors.error,
                  fontWeight: FontWeight.w500,
                ),
              ),
            if (req.isStockMoved && req.fulfilledAt != null)
              Text(
                'Transferred ${req.formattedFulfilledQuantity} ${req.itemUnit} on ${req.formattedFulfilledAt}',
                style: AppTypography.bodySm.copyWith(
                  color: _successColor,
                  fontWeight: FontWeight.w500,
                ),
              ),
          ],
        ),
        isThreeLine: true,
        trailing: Row(
          mainAxisSize: MainAxisSize.min,
          children: [
            _buildStatusChip(req.status),
            const SizedBox(width: AppSpacing.xs),
            const Icon(Icons.chevron_right, size: 20, color: AppColors.outline),
          ],
        ),
        onTap: () async {
          await showDialog<bool>(
            context: context,
            builder: (_) => StockRequestDetailsDialog(request: req),
          );
        },
      ),
    );
  }

  Widget _buildStatusChip(String status) {
    Color bg;
    Color fg;
    String label = status.toUpperCase();

    switch (status.toLowerCase()) {
      case 'pending':
        bg = Colors.amber.shade100;
        fg = Colors.amber.shade900;
        label = 'PENDING';
        break;
      case 'approved':
        bg = Colors.blue.shade100;
        fg = Colors.blue.shade900;
        label = 'APPROVED';
        break;
      case 'transferred':
        bg = Colors.green.shade100;
        fg = Colors.green.shade800;
        label = 'TRANSFERRED';
        break;
      case 'fulfilled':
        bg = Colors.green.shade100;
        fg = Colors.green.shade800;
        label = 'FULFILLED';
        break;
      case 'rejected':
        bg = Colors.red.shade100;
        fg = Colors.red.shade900;
        label = 'REJECTED';
        break;
      default:
        bg = AppColors.surfaceVariant;
        fg = AppColors.onSurfaceVariant;
    }

    return Container(
      padding: const EdgeInsets.symmetric(horizontal: 8, vertical: 3),
      decoration: BoxDecoration(
        color: bg,
        borderRadius: BorderRadius.circular(AppSpacing.radiusSm),
      ),
      child: Text(
        label,
        style: AppTypography.labelCaps.copyWith(
          color: fg,
          fontWeight: FontWeight.bold,
          fontSize: 10,
        ),
      ),
    );
  }
}
