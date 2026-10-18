import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:intl/intl.dart';

import '../../../core/theme/app_colors.dart';
import '../../../core/theme/app_spacing.dart';
import '../../../core/theme/app_typography.dart';
import '../../../core/utils/date_boundaries.dart';
import '../../inventory/models/purchase_order.dart';
import '../../inventory/providers/purchase_order_provider.dart';
import '../../inventory/screens/purchase_order_list_screen.dart';
import '../../inventory/widgets/purchase_order_details_dialog.dart';
import '../../vendors/models/vendor.dart';
import '../../vendors/providers/vendor_provider.dart';
import '../../vendors/screens/vendor_management_screen.dart';

/// Live dashboard card displaying strictly today's procurement activity.
/// Omits all historical vendor counts and all-time PO totals.
class VendorPurchaseOrderSummaryCard extends ConsumerWidget {
  const VendorPurchaseOrderSummaryCard({
    super.key,
    this.onNavigateToVendors,
    this.onNavigateToOrders,
  });

  /// Optional navigation callback for Vendor Management.
  /// Defaults to navigating to [VendorManagementScreen].
  final VoidCallback? onNavigateToVendors;

  /// Optional navigation callback for Purchase Order Management.
  /// Defaults to navigating to [PurchaseOrderManagementScreen].
  final VoidCallback? onNavigateToOrders;

  static const _surfaceBorder = Color(0xFFE5E2E1);

  void _openVendors(BuildContext context) {
    if (onNavigateToVendors != null) {
      onNavigateToVendors!();
    } else {
      Navigator.of(context).push(
        MaterialPageRoute(
          builder: (_) => const VendorManagementScreen(),
        ),
      );
    }
  }

  void _openOrders(BuildContext context) {
    if (onNavigateToOrders != null) {
      onNavigateToOrders!();
    } else {
      Navigator.of(context).push(
        MaterialPageRoute(
          builder: (_) => const PurchaseOrderManagementScreen(),
        ),
      );
    }
  }

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    final vendorsAsync = ref.watch(vendorsProvider);
    final ordersAsync = ref.watch(purchaseOrdersProvider);

    return DecoratedBox(
      decoration: BoxDecoration(
        color: AppColors.surfaceContainerLowest,
        borderRadius: BorderRadius.circular(AppSpacing.radiusLg),
        border: Border.all(color: _surfaceBorder),
        boxShadow: const [
          BoxShadow(
            color: Color(0x0A000000),
            blurRadius: 8,
            offset: Offset(0, 1),
          ),
        ],
      ),
      child: Padding(
        padding: const EdgeInsets.all(AppSpacing.md),
        child: Column(
          crossAxisAlignment: CrossAxisAlignment.stretch,
          children: [
            // Card Header: Icon, Title, and Actions
            DecoratedBox(
              decoration: const BoxDecoration(
                border: Border(
                  bottom: BorderSide(color: AppColors.outlineVariant),
                ),
              ),
              child: Padding(
                padding: const EdgeInsets.only(bottom: AppSpacing.xs),
                child: Row(
                  mainAxisAlignment: MainAxisAlignment.spaceBetween,
                  children: [
                    Expanded(
                      child: Row(
                        children: [
                          Container(
                            padding: const EdgeInsets.all(AppSpacing.xs),
                            decoration: BoxDecoration(
                              color: AppColors.primaryContainer
                                  .withValues(alpha: 0.15),
                              borderRadius:
                                  BorderRadius.circular(AppSpacing.radiusSm),
                            ),
                            child: const Icon(
                              Icons.storefront_outlined,
                              color: AppColors.primary,
                              size: 20,
                            ),
                          ),
                          const SizedBox(width: AppSpacing.sm),
                          Expanded(
                            child: Text(
                              'Vendors & Procurement',
                              style: AppTypography.headlineMd,
                              maxLines: 1,
                              overflow: TextOverflow.ellipsis,
                            ),
                          ),
                        ],
                      ),
                    ),
                    const SizedBox(width: AppSpacing.xs),
                    Row(
                      mainAxisSize: MainAxisSize.min,
                      children: [
                        TextButton(
                          onPressed: () => _openVendors(context),
                          style: TextButton.styleFrom(
                            padding: const EdgeInsets.symmetric(horizontal: 6),
                            minimumSize: Size.zero,
                            tapTargetSize: MaterialTapTargetSize.shrinkWrap,
                          ),
                          child: Text(
                            'Vendors',
                            style: AppTypography.labelCaps.copyWith(
                              color: AppColors.primary,
                            ),
                          ),
                        ),
                        TextButton(
                          onPressed: () => _openOrders(context),
                          style: TextButton.styleFrom(
                            padding: const EdgeInsets.symmetric(horizontal: 6),
                            minimumSize: Size.zero,
                            tapTargetSize: MaterialTapTargetSize.shrinkWrap,
                          ),
                          child: Row(
                            mainAxisSize: MainAxisSize.min,
                            children: [
                              Text(
                                'All POs',
                                style: AppTypography.labelCaps.copyWith(
                                  color: AppColors.secondary,
                                ),
                              ),
                              const SizedBox(width: 2),
                              const Icon(
                                Icons.chevron_right,
                                size: 16,
                                color: AppColors.secondary,
                              ),
                            ],
                          ),
                        ),
                      ],
                    ),
                  ],
                ),
              ),
            ),
            const SizedBox(height: AppSpacing.md),

            // Async data loading & states
            ordersAsync.when(
              loading: () => _buildLoadingState(),
              error: (err, _) => _buildErrorState(
                ref,
                err.toString(),
                onRetry: () =>
                    ref.read(purchaseOrdersProvider.notifier).fetchOrders(),
              ),
              data: (orders) {
                final vendors = vendorsAsync.valueOrNull ?? [];
                return _buildDataContent(
                  context,
                  ref,
                  vendors,
                  orders,
                );
              },
            ),
          ],
        ),
      ),
    );
  }

  Widget _buildLoadingState() {
    return const Padding(
      padding: EdgeInsets.symmetric(vertical: AppSpacing.lg),
      child: Center(
        child: Column(
          mainAxisSize: MainAxisSize.min,
          mainAxisAlignment: MainAxisAlignment.center,
          children: [
            SizedBox(
              width: 24,
              height: 24,
              child: CircularProgressIndicator(
                strokeWidth: 2.5,
                color: AppColors.primary,
              ),
            ),
            SizedBox(height: AppSpacing.sm),
            Text(
              'Loading procurement metrics...',
              style: TextStyle(
                color: AppColors.outline,
                fontSize: 12,
              ),
            ),
          ],
        ),
      ),
    );
  }

  Widget _buildErrorState(
    WidgetRef ref,
    String error, {
    required VoidCallback onRetry,
  }) {
    return Padding(
      padding: const EdgeInsets.symmetric(
        horizontal: AppSpacing.md,
        vertical: AppSpacing.md,
      ),
      child: Center(
        child: Column(
          mainAxisSize: MainAxisSize.min,
          mainAxisAlignment: MainAxisAlignment.center,
          children: [
            const Icon(
              Icons.error_outline,
              color: AppColors.error,
              size: 28,
            ),
            const SizedBox(height: AppSpacing.xs),
            Text(
              'Unable to load procurement data',
              style: AppTypography.labelCaps.copyWith(
                color: AppColors.error,
                fontWeight: FontWeight.w600,
              ),
            ),
            const SizedBox(height: 2),
            Text(
              error,
              style: AppTypography.bodySm.copyWith(
                color: AppColors.onSurfaceVariant,
                fontSize: 11,
              ),
              maxLines: 2,
              overflow: TextOverflow.ellipsis,
              textAlign: TextAlign.center,
            ),
            const SizedBox(height: AppSpacing.xs),
            OutlinedButton.icon(
              onPressed: onRetry,
              icon: const Icon(Icons.refresh, size: 14),
              label: const Text('Retry'),
              style: OutlinedButton.styleFrom(
                padding: const EdgeInsets.symmetric(
                  horizontal: AppSpacing.sm,
                  vertical: AppSpacing.base,
                ),
              ),
            ),
          ],
        ),
      ),
    );
  }

  Widget _buildEmptyState(BuildContext context) {
    return Padding(
      padding: const EdgeInsets.symmetric(vertical: AppSpacing.md),
      child: Center(
        child: Column(
          mainAxisSize: MainAxisSize.min,
          mainAxisAlignment: MainAxisAlignment.center,
          children: [
            const Icon(
              Icons.storefront_outlined,
              size: 36,
              color: AppColors.outlineVariant,
            ),
            const SizedBox(height: AppSpacing.xs),
            Text(
              'No procurement activity scheduled for today',
              style: AppTypography.bodySm.copyWith(
                color: AppColors.onSurfaceVariant,
                fontWeight: FontWeight.w600,
              ),
            ),
            const SizedBox(height: 2),
            Text(
              'No orders placed or deliveries expected today.',
              style: AppTypography.bodySm.copyWith(
                color: AppColors.outline,
                fontSize: 11,
              ),
            ),
            const SizedBox(height: AppSpacing.sm),
            Wrap(
              spacing: AppSpacing.sm,
              runSpacing: AppSpacing.xs,
              alignment: WrapAlignment.center,
              children: [
                OutlinedButton.icon(
                  onPressed: () => _openVendors(context),
                  icon: const Icon(Icons.store_outlined, size: 14),
                  label: const Text('Manage Vendors'),
                  style: OutlinedButton.styleFrom(
                    padding: const EdgeInsets.symmetric(
                      horizontal: AppSpacing.sm,
                      vertical: AppSpacing.base,
                    ),
                  ),
                ),
                FilledButton.icon(
                  onPressed: () => _openOrders(context),
                  icon: const Icon(Icons.add, size: 14),
                  label: const Text('New Purchase Order'),
                  style: FilledButton.styleFrom(
                    backgroundColor: AppColors.primary,
                    padding: const EdgeInsets.symmetric(
                      horizontal: AppSpacing.sm,
                      vertical: AppSpacing.base,
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

  Widget _buildDataContent(
    BuildContext context,
    WidgetRef ref,
    List<Vendor> vendors,
    List<PurchaseOrder> orders,
  ) {
    // 1. Genuinely daily metrics:
    // Orders created/placed today
    final ordersPlacedToday = orders.where((po) {
      return DateBoundaries.isToday(po.orderDate);
    }).toList();

    // Purchase orders with delivery due today
    final deliveriesDueToday = orders.where((po) {
      if (po.expectedDeliveryDate == null) return false;
      return DateBoundaries.isToday(po.expectedDeliveryDate!);
    }).toList();

    if (ordersPlacedToday.isEmpty && deliveriesDueToday.isEmpty) {
      return _buildEmptyState(context);
    }

    final currency = NumberFormat.currency(
      locale: 'en_IN',
      symbol: '₹',
      decimalDigits: 0,
    );

    final double totalAmountPlacedToday = ordersPlacedToday.fold(
      0.0,
      (sum, po) => sum + po.totalAmount,
    );

    final receivedDeliveriesCount =
        deliveriesDueToday.where((po) => po.isReceived).length;

    // Combined unique list of today's active orders
    final Set<String> seenIds = {};
    final List<PurchaseOrder> todayActivityOrders = [];
    for (final po in [...ordersPlacedToday, ...deliveriesDueToday]) {
      if (seenIds.add(po.id)) {
        todayActivityOrders.add(po);
      }
    }

    final displayOrders = todayActivityOrders.take(3).toList();

    return Column(
      crossAxisAlignment: CrossAxisAlignment.stretch,
      children: [
        // Two main KPI summary tiles for today's procurement
        Row(
          children: [
            Expanded(
              child: _MetricTile(
                title: 'Orders Placed Today',
                value: '${ordersPlacedToday.length}',
                subtitle: ordersPlacedToday.isNotEmpty
                    ? (totalAmountPlacedToday > 0
                        ? '${currency.format(totalAmountPlacedToday)} total'
                        : '${ordersPlacedToday.length} placed today')
                    : 'No orders placed today',
                icon: Icons.receipt_long_outlined,
                iconColor: AppColors.primary,
                bgColor: AppColors.primaryContainer.withValues(alpha: 0.12),
                onTap: () => _openOrders(context),
              ),
            ),
            const SizedBox(width: AppSpacing.sm),
            Expanded(
              child: _MetricTile(
                title: 'Deliveries Due Today',
                value: '${deliveriesDueToday.length}',
                subtitle: deliveriesDueToday.isNotEmpty
                    ? (receivedDeliveriesCount > 0
                        ? '$receivedDeliveriesCount received'
                        : 'Awaiting delivery')
                    : 'No deliveries due today',
                icon: Icons.local_shipping_outlined,
                iconColor: AppColors.secondary,
                bgColor: AppColors.secondary.withValues(alpha: 0.12),
                onTap: () => _openOrders(context),
              ),
            ),
          ],
        ),
        const SizedBox(height: AppSpacing.md),

        // Activity breakdown header
        Padding(
          padding: const EdgeInsets.symmetric(horizontal: 2),
          child: Row(
            mainAxisAlignment: MainAxisAlignment.spaceBetween,
            children: [
              Expanded(
                child: Text(
                  "Today's Procurement Activity",
                  style: AppTypography.labelCaps.copyWith(
                    color: AppColors.onSurfaceVariant,
                    fontWeight: FontWeight.w600,
                    fontSize: 11,
                  ),
                  overflow: TextOverflow.ellipsis,
                ),
              ),
              const SizedBox(width: AppSpacing.xs),
              Text(
                '${todayActivityOrders.length} active',
                style: AppTypography.labelCaps.copyWith(
                  color: AppColors.outline,
                  fontSize: 10,
                ),
              ),
            ],
          ),
        ),
        const SizedBox(height: AppSpacing.xs),

        // Orders list
        for (int i = 0; i < displayOrders.length; i++) ...[
          if (i > 0) const SizedBox(height: AppSpacing.xs),
          _OrderListTile(
            order: displayOrders[i],
            currency: currency,
            onTap: () {
              showDialog(
                context: context,
                builder: (_) => PurchaseOrderDetailsDialog(
                  order: displayOrders[i],
                ),
              );
            },
          ),
        ],

        const SizedBox(height: AppSpacing.xs),
        Padding(
          padding: const EdgeInsets.symmetric(horizontal: 2),
          child: Wrap(
            alignment: WrapAlignment.spaceBetween,
            children: [
              Text(
                'Scope: Orders and deliveries today',
                style: AppTypography.bodySm.copyWith(
                  color: AppColors.onSurfaceVariant,
                  fontSize: 11,
                ),
              ),
              Text(
                'Historical POs in All POs',
                style: AppTypography.labelCaps.copyWith(
                  color: AppColors.outline,
                  fontSize: 10,
                ),
              ),
            ],
          ),
        ),
      ],
    );
  }
}

class _MetricTile extends StatelessWidget {
  const _MetricTile({
    required this.title,
    required this.value,
    required this.subtitle,
    required this.icon,
    required this.iconColor,
    required this.bgColor,
    this.onTap,
  });

  final String title;
  final String value;
  final String subtitle;
  final IconData icon;
  final Color iconColor;
  final Color bgColor;
  final VoidCallback? onTap;

  @override
  Widget build(BuildContext context) {
    return Material(
      color: Colors.transparent,
      child: InkWell(
        onTap: onTap,
        borderRadius: BorderRadius.circular(AppSpacing.radiusMd),
        child: Container(
          padding: const EdgeInsets.all(AppSpacing.sm),
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
                  Flexible(
                    child: Text(
                      title,
                      style: AppTypography.labelCaps.copyWith(
                        color: AppColors.onSurfaceVariant,
                        fontSize: 10,
                        fontWeight: FontWeight.w600,
                      ),
                      overflow: TextOverflow.ellipsis,
                    ),
                  ),
                  Container(
                    padding: const EdgeInsets.all(4),
                    decoration: BoxDecoration(
                      color: bgColor,
                      borderRadius: BorderRadius.circular(AppSpacing.radiusSm),
                    ),
                    child: Icon(icon, size: 14, color: iconColor),
                  ),
                ],
              ),
              const SizedBox(height: AppSpacing.xs),
              Text(
                value,
                style: AppTypography.headlineMd.copyWith(
                  color: AppColors.onSurface,
                  fontWeight: FontWeight.bold,
                  fontSize: 22,
                ),
                maxLines: 1,
                overflow: TextOverflow.ellipsis,
              ),
              const SizedBox(height: 2),
              Text(
                subtitle,
                style: AppTypography.bodySm.copyWith(
                  color: AppColors.onSurfaceVariant,
                  fontSize: 10,
                ),
                maxLines: 1,
                overflow: TextOverflow.ellipsis,
              ),
            ],
          ),
        ),
      ),
    );
  }
}

class _OrderListTile extends StatelessWidget {
  const _OrderListTile({
    required this.order,
    required this.currency,
    required this.onTap,
  });

  final PurchaseOrder order;
  final NumberFormat currency;
  final VoidCallback onTap;

  @override
  Widget build(BuildContext context) {
    final bool placedToday = DateBoundaries.isToday(order.orderDate);
    final bool dueToday = order.expectedDeliveryDate != null &&
        DateBoundaries.isToday(order.expectedDeliveryDate!);

    final String activityLabel = placedToday && dueToday
        ? 'Ordered & Due Today'
        : placedToday
            ? 'Placed Today'
            : 'Delivery Due Today';

    return Material(
      color: AppColors.surfaceContainerLow,
      borderRadius: BorderRadius.circular(AppSpacing.radiusMd),
      child: InkWell(
        onTap: onTap,
        borderRadius: BorderRadius.circular(AppSpacing.radiusMd),
        child: Padding(
          padding: const EdgeInsets.symmetric(
            horizontal: AppSpacing.sm,
            vertical: AppSpacing.xs,
          ),
          child: Row(
            children: [
              Container(
                padding: const EdgeInsets.all(6),
                decoration: BoxDecoration(
                  color: order.status.color.withValues(alpha: 0.12),
                  borderRadius: BorderRadius.circular(AppSpacing.radiusSm),
                ),
                child: Icon(
                  order.status.icon,
                  size: 16,
                  color: order.status.color,
                ),
              ),
              const SizedBox(width: AppSpacing.sm),
              Expanded(
                child: Column(
                  crossAxisAlignment: CrossAxisAlignment.start,
                  children: [
                    Text(
                      order.purchaseOrderNumber,
                      style: AppTypography.bodySm.copyWith(
                        fontWeight: FontWeight.w600,
                      ),
                      overflow: TextOverflow.ellipsis,
                      maxLines: 1,
                    ),
                    Text(
                      '${order.vendorName ?? 'Unknown Vendor'} • $activityLabel',
                      style: AppTypography.bodySm.copyWith(
                        color: AppColors.onSurfaceVariant,
                        fontSize: 11,
                      ),
                      overflow: TextOverflow.ellipsis,
                      maxLines: 1,
                    ),
                  ],
                ),
              ),
              const SizedBox(width: AppSpacing.xs),
              Column(
                crossAxisAlignment: CrossAxisAlignment.end,
                children: [
                  Text(
                    currency.format(order.totalAmount),
                    style: AppTypography.bodySm.copyWith(
                      fontWeight: FontWeight.w700,
                      color: AppColors.onSurface,
                    ),
                  ),
                  Container(
                    padding:
                        const EdgeInsets.symmetric(horizontal: 4, vertical: 1),
                    decoration: BoxDecoration(
                      color: order.status.color.withValues(alpha: 0.1),
                      borderRadius: BorderRadius.circular(2),
                    ),
                    child: Text(
                      order.status.label,
                      style: TextStyle(
                        fontSize: 9,
                        color: order.status.color,
                        fontWeight: FontWeight.w600,
                      ),
                    ),
                  ),
                ],
              ),
            ],
          ),
        ),
      ),
    );
  }
}
