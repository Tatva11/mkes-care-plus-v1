import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:intl/intl.dart';

import '../../../core/theme/app_colors.dart';
import '../../../core/theme/app_spacing.dart';
import '../../../core/theme/app_typography.dart';
import '../../../shared/widgets/app_footer.dart';
import '../../admin/widgets/admin_shell.dart';
import '../../auth/providers/auth_provider.dart';
import '../../vendors/providers/vendor_provider.dart';
import '../models/purchase_order.dart';
import '../providers/purchase_order_provider.dart';
import '../widgets/purchase_order_details_dialog.dart';
import '../widgets/purchase_order_form_dialog.dart';
import '../widgets/receive_purchase_order_dialog.dart';

/// Full screen wrapper for Purchase Orders management.
class PurchaseOrderManagementScreen extends ConsumerWidget {
  const PurchaseOrderManagementScreen({super.key});

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    final role = ref.watch(currentUserRoleProvider).valueOrNull;

    if (role == 'admin') {
      return AdminShell(
        selectedItem: AdminNavItem.operations,
        onNavItemSelected: (item) {
          if (item == AdminNavItem.dashboard) {
            Navigator.of(context).popUntil((route) => route.isFirst);
          }
        },
        body: const PurchaseOrderManagementContent(),
      );
    }

    return Scaffold(
      backgroundColor: AppColors.surfaceContainerLowest,
      appBar: AppBar(
        title: const Text('Purchase Orders'),
        backgroundColor: AppColors.surface,
        foregroundColor: AppColors.onSurface,
        elevation: 0,
        leading: Navigator.of(context).canPop()
            ? BackButton(onPressed: () => Navigator.of(context).pop())
            : null,
      ),
      body: const PurchaseOrderManagementContent(),
    );
  }
}

/// Responsive content widget for managing Purchase Orders.
/// Reusable in Admin Operations, Staff Tasks, or standalone screen.
class PurchaseOrderManagementContent extends ConsumerStatefulWidget {
  const PurchaseOrderManagementContent({super.key});

  @override
  ConsumerState<PurchaseOrderManagementContent> createState() =>
      _PurchaseOrderManagementContentState();
}

class _PurchaseOrderManagementContentState
    extends ConsumerState<PurchaseOrderManagementContent> {
  final _searchController = TextEditingController();

  @override
  void dispose() {
    _searchController.dispose();
    super.dispose();
  }

  void _openCreateDialog() {
    showDialog(
      context: context,
      builder: (_) => const PurchaseOrderFormDialog(),
    );
  }

  void _openDetailsDialog(PurchaseOrder po) {
    showDialog(
      context: context,
      builder: (_) => PurchaseOrderDetailsDialog(order: po),
    );
  }

  void _openReceiveDialog(PurchaseOrder po) {
    showDialog(
      context: context,
      builder: (_) => ReceivePurchaseOrderDialog(order: po),
    );
  }

  void _openEditDialog(PurchaseOrder po) {
    showDialog(
      context: context,
      builder: (_) => PurchaseOrderFormDialog(order: po),
    );
  }

  Future<void> _cancelOrder(PurchaseOrder po) async {
    final confirmed = await showDialog<bool>(
      context: context,
      builder: (dialogCtx) => AlertDialog(
        title: const Text('Cancel Purchase Order'),
        content: Text('Are you sure you want to cancel PO #${po.purchaseOrderNumber}?'),
        actions: [
          TextButton(
            onPressed: () => Navigator.of(dialogCtx).pop(false),
            child: const Text('Keep PO'),
          ),
          FilledButton(
            style: FilledButton.styleFrom(backgroundColor: AppColors.error),
            onPressed: () => Navigator.of(dialogCtx).pop(true),
            child: const Text('Cancel PO'),
          ),
        ],
      ),
    );

    if (confirmed == true && mounted) {
      try {
        await ref.read(purchaseOrdersProvider.notifier).cancelOrder(po.id);
        if (mounted) {
          ScaffoldMessenger.of(context).showSnackBar(
            SnackBar(
              backgroundColor: AppColors.error,
              content: Text('PO #${po.purchaseOrderNumber} cancelled.'),
            ),
          );
        }
      } catch (e) {
        if (mounted) {
          ScaffoldMessenger.of(context).showSnackBar(
            SnackBar(
              backgroundColor: AppColors.error,
              content: Text('Failed to cancel PO: $e'),
            ),
          );
        }
      }
    }
  }

  @override
  Widget build(BuildContext context) {
    final ordersAsync = ref.watch(purchaseOrdersProvider);
    final filteredOrders = ref.watch(filteredPurchaseOrdersProvider);
    final isDesktop = MediaQuery.sizeOf(context).width > 768;

    return RefreshIndicator(
      onRefresh: () => ref.read(purchaseOrdersProvider.notifier).fetchOrders(),
      child: SingleChildScrollView(
        physics: const AlwaysScrollableScrollPhysics(),
        padding: EdgeInsets.all(
          isDesktop ? AppSpacing.marginDesktop : AppSpacing.marginMobile,
        ),
        child: Column(
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            _buildHeader(isDesktop),
            const SizedBox(height: AppSpacing.md),
            _buildKpiSummaryCards(),
            const SizedBox(height: AppSpacing.lg),
            _buildSearchAndFilters(isDesktop),
            const SizedBox(height: AppSpacing.md),
            ordersAsync.when(
              loading: () => const Center(
                child: Padding(
                  padding: EdgeInsets.all(AppSpacing.xl),
                  child: CircularProgressIndicator(),
                ),
              ),
              error: (err, _) => _buildErrorCard(err),
              data: (allOrders) {
                if (allOrders.isEmpty) {
                  return _buildEmptyState();
                }
                if (filteredOrders.isEmpty) {
                  return _buildNoResultsState();
                }
                return isDesktop
                    ? _buildDesktopTable(filteredOrders)
                    : _buildMobileCards(filteredOrders);
              },
            ),
            const SizedBox(height: AppSpacing.xl),
            const AppFooter(),
          ],
        ),
      ),
    );
  }

  Widget _buildHeader(bool isDesktop) {
    if (!isDesktop) {
      return Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Row(
            crossAxisAlignment: CrossAxisAlignment.center,
            children: [
              if (Navigator.of(context).canPop()) ...[
                IconButton.filledTonal(
                  tooltip: 'Back to previous screen',
                  onPressed: () => Navigator.of(context).maybePop(),
                  icon: const Icon(Icons.arrow_back),
                ),
                const SizedBox(width: AppSpacing.sm),
              ],
              Expanded(
                child: Text(
                  'Purchase Orders',
                  style: AppTypography.headlineMd.copyWith(
                    color: AppColors.onBackground,
                    fontWeight: FontWeight.bold,
                  ),
                  overflow: TextOverflow.ellipsis,
                ),
              ),
              IconButton.outlined(
                tooltip: 'Refresh Purchase Orders',
                onPressed: () =>
                    ref.read(purchaseOrdersProvider.notifier).fetchOrders(),
                icon: const Icon(Icons.refresh, size: 20),
              ),
            ],
          ),
          const SizedBox(height: AppSpacing.xs),
          Text(
            'Manage supplier orders, delivery tracking, and atomic inventory stock receiving',
            style: AppTypography.bodySm.copyWith(
              color: AppColors.onSurfaceVariant,
            ),
          ),
          const SizedBox(height: AppSpacing.sm),
          SizedBox(
            width: double.infinity,
            child: FilledButton.icon(
              onPressed: _openCreateDialog,
              icon: const Icon(Icons.add, size: 18),
              label: const Text('New Purchase Order'),
              style: FilledButton.styleFrom(
                backgroundColor: AppColors.primary,
                foregroundColor: AppColors.onPrimary,
                padding: const EdgeInsets.symmetric(
                  horizontal: AppSpacing.md,
                  vertical: 12,
                ),
              ),
            ),
          ),
        ],
      );
    }

    return Row(
      crossAxisAlignment: CrossAxisAlignment.start,
      children: [
        if (Navigator.of(context).canPop()) ...[
          IconButton.filledTonal(
            tooltip: 'Back to previous screen',
            onPressed: () => Navigator.of(context).maybePop(),
            icon: const Icon(Icons.arrow_back),
          ),
          const SizedBox(width: AppSpacing.sm),
        ],
        Expanded(
          child: Column(
            crossAxisAlignment: CrossAxisAlignment.start,
            children: [
              Text(
                'Purchase Orders',
                style: AppTypography.displayLg.copyWith(
                  color: AppColors.onBackground,
                ),
              ),
              const SizedBox(height: AppSpacing.xs),
              Text(
                'Manage supplier orders, delivery tracking, and atomic inventory stock receiving',
                style: AppTypography.bodyLg.copyWith(
                  color: AppColors.onSurfaceVariant,
                ),
              ),
            ],
          ),
        ),
        Row(
          children: [
            IconButton.outlined(
              tooltip: 'Refresh Purchase Orders',
              onPressed: () =>
                  ref.read(purchaseOrdersProvider.notifier).fetchOrders(),
              icon: const Icon(Icons.refresh, size: 20),
            ),
            const SizedBox(width: AppSpacing.sm),
            FilledButton.icon(
              onPressed: _openCreateDialog,
              icon: const Icon(Icons.add, size: 18),
              label: const Text('New Purchase Order'),
              style: FilledButton.styleFrom(
                backgroundColor: AppColors.primary,
                foregroundColor: AppColors.onPrimary,
                padding: const EdgeInsets.symmetric(
                  horizontal: AppSpacing.md,
                  vertical: AppSpacing.sm,
                ),
              ),
            ),
          ],
        ),
      ],
    );
  }

  Widget _buildKpiSummaryCards() {
    final allOrders = ref.watch(purchaseOrdersProvider).valueOrNull ?? [];
    final draftCount = ref.watch(draftPOCountProvider);
    final orderedCount = ref.watch(orderedPOCountProvider);
    final partialCount = ref.watch(partiallyReceivedPOCountProvider);
    final receivedCount = ref.watch(receivedPOCountProvider);

    return LayoutBuilder(
      builder: (context, constraints) {
        final cardWidth = constraints.maxWidth > 700
            ? (constraints.maxWidth - (AppSpacing.sm * 4)) / 5
            : (constraints.maxWidth - AppSpacing.sm) / 2;

        return Wrap(
          spacing: AppSpacing.sm,
          runSpacing: AppSpacing.sm,
          children: [
            _buildStatCard('Total POs', allOrders.length.toString(), Icons.receipt_long, Colors.blueGrey, cardWidth),
            _buildStatCard('Drafts', draftCount.toString(), Icons.edit_note, Colors.grey, cardWidth),
            _buildStatCard('Ordered', orderedCount.toString(), Icons.send, const Color(0xFF1976D2), cardWidth),
            _buildStatCard('Partially Received', partialCount.toString(), Icons.hourglass_top, const Color(0xFFE65100), cardWidth),
            _buildStatCard('Received in Full', receivedCount.toString(), Icons.check_circle, const Color(0xFF2E7D32), cardWidth),
          ],
        );
      },
    );
  }

  Widget _buildStatCard(
    String label,
    String count,
    IconData icon,
    Color color,
    double width,
  ) {
    return Container(
      width: width,
      padding: const EdgeInsets.symmetric(
        horizontal: AppSpacing.md,
        vertical: AppSpacing.sm,
      ),
      decoration: BoxDecoration(
        color: AppColors.surfaceContainerLow,
        borderRadius: BorderRadius.circular(AppSpacing.radiusMd),
        border: Border.all(color: AppColors.outlineVariant),
      ),
      child: Row(
        children: [
          Container(
            padding: const EdgeInsets.all(8),
            decoration: BoxDecoration(
              color: color.withValues(alpha: 0.12),
              borderRadius: BorderRadius.circular(8),
            ),
            child: Icon(icon, color: color, size: 18),
          ),
          const SizedBox(width: AppSpacing.sm),
          Expanded(
            child: Column(
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                Text(
                  count,
                  style: AppTypography.headlineMd.copyWith(
                    fontWeight: FontWeight.w700,
                  ),
                ),
                Text(
                  label,
                  style: AppTypography.labelCaps.copyWith(
                    color: AppColors.onSurfaceVariant,
                    fontSize: 10,
                  ),
                  overflow: TextOverflow.ellipsis,
                ),
              ],
            ),
          ),
        ],
      ),
    );
  }

  Widget _buildSearchAndFilters(bool isDesktop) {
    final selectedStatus = ref.watch(purchaseOrderStatusFilterProvider);
    final selectedVendorId = ref.watch(purchaseOrderVendorFilterProvider);
    final allVendors = ref.watch(vendorsProvider).value ?? [];

    return Column(
      crossAxisAlignment: CrossAxisAlignment.start,
      children: [
        // Search bar & Vendor Dropdown
        if (!isDesktop) ...[
          TextField(
            controller: _searchController,
            decoration: InputDecoration(
              hintText: 'Search by PO number, vendor, notes, product...',
              prefixIcon: const Icon(Icons.search, size: 20),
              suffixIcon: _searchController.text.isNotEmpty
                  ? IconButton(
                      icon: const Icon(Icons.clear, size: 18),
                      onPressed: () {
                        _searchController.clear();
                        ref
                            .read(purchaseOrderSearchQueryProvider.notifier)
                            .state = '';
                      },
                    )
                  : null,
              fillColor: AppColors.surfaceContainerLow,
            ),
            onChanged: (val) {
              ref.read(purchaseOrderSearchQueryProvider.notifier).state = val;
            },
          ),
          const SizedBox(height: AppSpacing.sm),
          DropdownButtonFormField<String?>(
            isExpanded: true,
            initialValue: selectedVendorId,
            decoration: const InputDecoration(
              prefixIcon: Icon(Icons.local_shipping_outlined, size: 20),
              fillColor: AppColors.surfaceContainerLow,
              contentPadding: EdgeInsets.symmetric(horizontal: 10, vertical: 8),
            ),
            hint: const Text('All Vendors'),
            items: [
              const DropdownMenuItem<String?>(
                value: null,
                child: Text('All Vendors'),
              ),
              ...allVendors.map((v) {
                return DropdownMenuItem<String?>(
                  value: v.id,
                  child: Text(v.name, overflow: TextOverflow.ellipsis),
                );
              }),
            ],
            onChanged: (val) {
              ref.read(purchaseOrderVendorFilterProvider.notifier).state = val;
            },
          ),
        ] else ...[
          Row(
            children: [
              Expanded(
                flex: 3,
                child: TextField(
                  controller: _searchController,
                  decoration: InputDecoration(
                    hintText: 'Search by PO number, vendor, notes, product...',
                    prefixIcon: const Icon(Icons.search, size: 20),
                    suffixIcon: _searchController.text.isNotEmpty
                        ? IconButton(
                            icon: const Icon(Icons.clear, size: 18),
                            onPressed: () {
                              _searchController.clear();
                              ref
                                  .read(purchaseOrderSearchQueryProvider.notifier)
                                  .state = '';
                            },
                          )
                        : null,
                    fillColor: AppColors.surfaceContainerLow,
                  ),
                  onChanged: (val) {
                    ref.read(purchaseOrderSearchQueryProvider.notifier).state = val;
                  },
                ),
              ),
              const SizedBox(width: AppSpacing.sm),
              Expanded(
                flex: 2,
                child: DropdownButtonFormField<String?>(
                  isExpanded: true,
                  initialValue: selectedVendorId,
                  decoration: InputDecoration(
                    prefixIcon: const Icon(Icons.local_shipping_outlined, size: 20),
                    fillColor: AppColors.surfaceContainerLow,
                    contentPadding: const EdgeInsets.symmetric(horizontal: 10, vertical: 8),
                  ),
                  hint: const Text('All Vendors'),
                  items: [
                    const DropdownMenuItem<String?>(
                      value: null,
                      child: Text('All Vendors'),
                    ),
                    ...allVendors.map((v) {
                      return DropdownMenuItem<String?>(
                        value: v.id,
                        child: Text(v.name, overflow: TextOverflow.ellipsis),
                      );
                    }),
                  ],
                  onChanged: (val) {
                    ref.read(purchaseOrderVendorFilterProvider.notifier).state = val;
                  },
                ),
              ),
            ],
          ),
        ],
        const SizedBox(height: AppSpacing.sm),

        // Status Chips Filter
        SingleChildScrollView(
          scrollDirection: Axis.horizontal,
          child: Row(
            children: [
              _buildStatusFilterChip('All', selectedStatus),
              _buildStatusFilterChip('Draft', selectedStatus),
              _buildStatusFilterChip('Ordered', selectedStatus),
              _buildStatusFilterChip('Partially Received', selectedStatus),
              _buildStatusFilterChip('Received', selectedStatus),
              _buildStatusFilterChip('Cancelled', selectedStatus),
            ],
          ),
        ),
      ],
    );
  }

  Widget _buildStatusFilterChip(String label, String currentSelection) {
    final isSelected = currentSelection.toLowerCase() == label.toLowerCase();

    return Padding(
      padding: const EdgeInsets.only(right: AppSpacing.xs),
      child: FilterChip(
        label: Text(label),
        selected: isSelected,
        onSelected: (_) {
          ref.read(purchaseOrderStatusFilterProvider.notifier).state = label;
        },
        selectedColor: AppColors.primaryContainer.withValues(alpha: 0.25),
        checkmarkColor: AppColors.primary,
        labelStyle: TextStyle(
          fontSize: 12,
          fontWeight: isSelected ? FontWeight.w700 : FontWeight.w500,
          color: isSelected ? AppColors.primary : AppColors.onSurface,
        ),
        visualDensity: VisualDensity.compact,
      ),
    );
  }

  Widget _buildDesktopTable(List<PurchaseOrder> orders) {
    final dateFormat = DateFormat('MMM d, yyyy');

    return Container(
      decoration: BoxDecoration(
        color: AppColors.surfaceContainerLowest,
        borderRadius: BorderRadius.circular(AppSpacing.radiusLg),
        border: Border.all(color: AppColors.outlineVariant),
      ),
      child: ClipRRect(
        borderRadius: BorderRadius.circular(AppSpacing.radiusLg),
        child: Table(
          columnWidths: const {
            0: FlexColumnWidth(2.2), // PO Number
            1: FlexColumnWidth(2.5), // Vendor
            2: FlexColumnWidth(1.6), // Order Date
            3: FlexColumnWidth(1.6), // Expected Delivery
            4: FlexColumnWidth(1.6), // Total
            5: FlexColumnWidth(1.8), // Status
            6: FixedColumnWidth(220), // Actions
          },
          defaultVerticalAlignment: TableCellVerticalAlignment.middle,
          children: [
            // Table Header
            TableRow(
              decoration: const BoxDecoration(
                color: AppColors.surfaceContainerLow,
                border: Border(
                  bottom: BorderSide(color: AppColors.outlineVariant),
                ),
              ),
              children: [
                _buildTableHeaderCell('PO NUMBER'),
                _buildTableHeaderCell('VENDOR'),
                _buildTableHeaderCell('ORDER DATE'),
                _buildTableHeaderCell('DELIVERY'),
                _buildTableHeaderCell('TOTAL'),
                _buildTableHeaderCell('STATUS'),
                _buildTableHeaderCell('ACTIONS', alignRight: true),
              ],
            ),

            // Table Rows
            ...orders.map((po) {
              return TableRow(
                decoration: const BoxDecoration(
                  border: Border(
                    bottom: BorderSide(color: AppColors.outlineVariant),
                  ),
                ),
                children: [
                  // PO Number
                  Padding(
                    padding: const EdgeInsets.symmetric(horizontal: 16, vertical: 12),
                    child: Column(
                      crossAxisAlignment: CrossAxisAlignment.start,
                      children: [
                        Text(
                          po.purchaseOrderNumber,
                          style: AppTypography.bodyMd.copyWith(
                            fontWeight: FontWeight.w700,
                          ),
                        ),
                        Text(
                          '${po.items.length} items',
                          style: AppTypography.bodySm.copyWith(
                            color: AppColors.onSurfaceVariant,
                            fontSize: 11,
                          ),
                        ),
                      ],
                    ),
                  ),

                  // Vendor
                  Padding(
                    padding: const EdgeInsets.symmetric(horizontal: 16, vertical: 12),
                    child: Text(
                      po.vendorName ?? '—',
                      style: AppTypography.bodyMd.copyWith(
                        fontWeight: FontWeight.w600,
                      ),
                    ),
                  ),

                  // Order Date
                  Padding(
                    padding: const EdgeInsets.symmetric(horizontal: 16, vertical: 12),
                    child: Text(
                      dateFormat.format(po.orderDate),
                      style: AppTypography.bodySm,
                    ),
                  ),

                  // Expected Delivery
                  Padding(
                    padding: const EdgeInsets.symmetric(horizontal: 16, vertical: 12),
                    child: Text(
                      po.expectedDeliveryDate != null
                          ? dateFormat.format(po.expectedDeliveryDate!)
                          : '—',
                      style: AppTypography.bodySm.copyWith(
                        color: AppColors.onSurfaceVariant,
                      ),
                    ),
                  ),

                  // Total Amount
                  Padding(
                    padding: const EdgeInsets.symmetric(horizontal: 16, vertical: 12),
                    child: Text(
                      po.formattedTotal,
                      style: AppTypography.bodyMd.copyWith(
                        fontWeight: FontWeight.w700,
                        color: AppColors.primary,
                      ),
                    ),
                  ),

                  // Status Badge
                  Padding(
                    padding: const EdgeInsets.symmetric(horizontal: 16, vertical: 12),
                    child: Align(
                      alignment: Alignment.centerLeft,
                      child: Container(
                        padding: const EdgeInsets.symmetric(horizontal: 8, vertical: 4),
                        decoration: BoxDecoration(
                          color: po.status.color.withValues(alpha: 0.12),
                          borderRadius: BorderRadius.circular(4),
                          border: Border.all(color: po.status.color),
                        ),
                        child: Text(
                          po.status.label,
                          style: TextStyle(
                            color: po.status.color,
                            fontWeight: FontWeight.w700,
                            fontSize: 11,
                          ),
                        ),
                      ),
                    ),
                  ),

                  // Actions
                  Padding(
                    padding: const EdgeInsets.symmetric(horizontal: 8, vertical: 8),
                    child: Row(
                      mainAxisAlignment: MainAxisAlignment.end,
                      children: [
                        // View Details
                        IconButton(
                          tooltip: 'View Details',
                          icon: const Icon(Icons.visibility_outlined, size: 20),
                          onPressed: () => _openDetailsDialog(po),
                        ),

                        // Receive Items
                        if (po.canReceive)
                          IconButton(
                            tooltip: 'Receive Items',
                            icon: const Icon(Icons.inventory, size: 20, color: Colors.green),
                            onPressed: () => _openReceiveDialog(po),
                          ),

                        // Edit PO
                        if (po.canEdit)
                          IconButton(
                            tooltip: 'Edit PO',
                            icon: const Icon(Icons.edit_outlined, size: 20),
                            onPressed: () => _openEditDialog(po),
                          ),

                        // Cancel PO
                        if (po.canCancel)
                          IconButton(
                            tooltip: 'Cancel PO',
                            icon: const Icon(Icons.cancel_outlined, size: 20, color: AppColors.error),
                            onPressed: () => _cancelOrder(po),
                          ),
                      ],
                    ),
                  ),
                ],
              );
            }),
          ],
        ),
      ),
    );
  }

  Widget _buildMobileCards(List<PurchaseOrder> orders) {
    final dateFormat = DateFormat('MMM d, yyyy');

    return ListView.separated(
      shrinkWrap: true,
      physics: const NeverScrollableScrollPhysics(),
      itemCount: orders.length,
      separatorBuilder: (_, __) => const SizedBox(height: AppSpacing.sm),
      itemBuilder: (context, index) {
        final po = orders[index];
        return Card(
          margin: EdgeInsets.zero,
          elevation: 0,
          shape: RoundedRectangleBorder(
            borderRadius: BorderRadius.circular(AppSpacing.radiusLg),
            side: const BorderSide(color: AppColors.outlineVariant),
          ),
          child: Padding(
            padding: const EdgeInsets.all(AppSpacing.md),
            child: Column(
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                Row(
                  mainAxisAlignment: MainAxisAlignment.spaceBetween,
                  children: [
                    Text(
                      po.purchaseOrderNumber,
                      style: AppTypography.headlineMd.copyWith(
                        fontWeight: FontWeight.w700,
                      ),
                    ),
                    Container(
                      padding: const EdgeInsets.symmetric(horizontal: 8, vertical: 3),
                      decoration: BoxDecoration(
                        color: po.status.color.withValues(alpha: 0.12),
                        borderRadius: BorderRadius.circular(4),
                        border: Border.all(color: po.status.color),
                      ),
                      child: Text(
                        po.status.label,
                        style: TextStyle(
                          color: po.status.color,
                          fontWeight: FontWeight.w700,
                          fontSize: 11,
                        ),
                      ),
                    ),
                  ],
                ),
                const SizedBox(height: 4),
                Text(
                  po.vendorName ?? 'Vendor',
                  style: AppTypography.bodyMd.copyWith(fontWeight: FontWeight.w600),
                ),
                const SizedBox(height: AppSpacing.xs),
                Row(
                  mainAxisAlignment: MainAxisAlignment.spaceBetween,
                  children: [
                    Text(
                      'Order: ${dateFormat.format(po.orderDate)}',
                      style: AppTypography.bodySm.copyWith(color: AppColors.onSurfaceVariant),
                    ),
                    Text(
                      po.formattedTotal,
                      style: AppTypography.headlineMd.copyWith(
                        color: AppColors.primary,
                        fontWeight: FontWeight.w800,
                      ),
                    ),
                  ],
                ),
                const Divider(height: 16),
                Wrap(
                  alignment: WrapAlignment.end,
                  spacing: AppSpacing.xs,
                  runSpacing: AppSpacing.xs,
                  crossAxisAlignment: WrapCrossAlignment.center,
                  children: [
                    TextButton.icon(
                      onPressed: () => _openDetailsDialog(po),
                      icon: const Icon(Icons.visibility_outlined, size: 16),
                      label: const Text('Details'),
                    ),
                    if (po.canReceive)
                      FilledButton.icon(
                        onPressed: () => _openReceiveDialog(po),
                        icon: const Icon(Icons.inventory, size: 16),
                        label: const Text('Receive'),
                        style: FilledButton.styleFrom(
                          backgroundColor: Colors.green.shade700,
                        ),
                      ),
                    if (po.canEdit)
                      IconButton(
                        icon: const Icon(Icons.edit_outlined, size: 18),
                        onPressed: () => _openEditDialog(po),
                      ),
                    if (po.canCancel)
                      IconButton(
                        icon: const Icon(Icons.cancel_outlined, size: 18, color: AppColors.error),
                        onPressed: () => _cancelOrder(po),
                      ),
                  ],
                ),
              ],
            ),
          ),
        );
      },
    );
  }

  Widget _buildTableHeaderCell(String text, {bool alignRight = false}) {
    return Padding(
      padding: const EdgeInsets.symmetric(horizontal: 16, vertical: 12),
      child: Text(
        text,
        textAlign: alignRight ? TextAlign.end : TextAlign.start,
        style: AppTypography.labelCaps.copyWith(
          color: AppColors.onSurfaceVariant,
          fontWeight: FontWeight.w700,
          fontSize: 11,
        ),
      ),
    );
  }

  Widget _buildEmptyState() {
    return Center(
      child: Padding(
        padding: const EdgeInsets.all(AppSpacing.xl),
        child: Column(
          children: [
            const Icon(Icons.receipt_long_outlined, size: 56, color: AppColors.outline),
            const SizedBox(height: AppSpacing.md),
            Text(
              'No Purchase Orders Yet',
              style: AppTypography.headlineMd.copyWith(fontWeight: FontWeight.w700),
            ),
            const SizedBox(height: AppSpacing.xs),
            Text(
              'Create a purchase order to request products from your suppliers and track delivery.',
              style: AppTypography.bodyMd.copyWith(color: AppColors.onSurfaceVariant),
              textAlign: TextAlign.center,
            ),
            const SizedBox(height: AppSpacing.lg),
            FilledButton.icon(
              onPressed: _openCreateDialog,
              icon: const Icon(Icons.add),
              label: const Text('Create Purchase Order'),
            ),
          ],
        ),
      ),
    );
  }

  Widget _buildNoResultsState() {
    return Center(
      child: Padding(
        padding: const EdgeInsets.all(AppSpacing.xl),
        child: Column(
          children: [
            const Icon(Icons.search_off_outlined, size: 48, color: AppColors.outline),
            const SizedBox(height: AppSpacing.md),
            Text(
              'No Purchase Orders Found',
              style: AppTypography.headlineMd,
            ),
            const SizedBox(height: AppSpacing.xs),
            Text(
              'No purchase orders match your search and filter criteria.',
              style: AppTypography.bodySm.copyWith(color: AppColors.onSurfaceVariant),
            ),
          ],
        ),
      ),
    );
  }

  Widget _buildErrorCard(Object error) {
    return Container(
      padding: const EdgeInsets.all(AppSpacing.lg),
      decoration: BoxDecoration(
        color: AppColors.error.withValues(alpha: 0.1),
        borderRadius: BorderRadius.circular(AppSpacing.radiusLg),
        border: Border.all(color: AppColors.error),
      ),
      child: Row(
        children: [
          const Icon(Icons.error_outline, color: AppColors.error),
          const SizedBox(width: AppSpacing.md),
          Expanded(
            child: Text(
              'Unable to load purchase orders: $error',
              style: const TextStyle(color: AppColors.error),
            ),
          ),
          TextButton(
            onPressed: () =>
                ref.read(purchaseOrdersProvider.notifier).fetchOrders(),
            child: const Text('Retry'),
          ),
        ],
      ),
    );
  }
}
