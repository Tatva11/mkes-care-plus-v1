import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:intl/intl.dart';

import '../../../core/theme/app_colors.dart';
import '../../../core/theme/app_spacing.dart';
import '../../../core/theme/app_typography.dart';
import '../../auth/providers/auth_provider.dart';
import '../models/inventory_item.dart';
import '../models/inventory_transaction.dart';
import '../providers/inventory_provider.dart';
import '../providers/purchase_order_provider.dart';
import 'inventory_form_dialog.dart';
import 'inventory_transaction_history_dialog.dart';
import 'purchase_order_details_dialog.dart';
import 'purchase_order_form_dialog.dart';
import 'stock_operation_dialog.dart';
import '../../vendors/providers/vendor_provider.dart';
import '../utils/phone_dialer_util.dart';

/// Modal dialog displaying comprehensive details of an [InventoryItem].
/// Supports atomic Stock In / Stock Out, Recent Transactions, and role-based actions.
class InventoryDetailsDialog extends ConsumerWidget {
  const InventoryDetailsDialog({
    super.key,
    required this.item,
  });

  final InventoryItem item;

  Future<void> _handleEdit(BuildContext context, InventoryItem activeItem) async {
    Navigator.of(context).pop();
    await showDialog<InventoryItem>(
      context: context,
      builder: (_) => InventoryFormDialog(item: activeItem),
    );
  }

  Future<void> _handleDelete(BuildContext context, WidgetRef ref, InventoryItem activeItem) async {
    final confirmed = await showDialog<bool>(
      context: context,
      builder: (dialogContext) => AlertDialog(
        title: const Row(
          children: [
            Icon(Icons.warning_amber_rounded, color: AppColors.error, size: 24),
            SizedBox(width: AppSpacing.xs),
            Text('Confirm Deletion'),
          ],
        ),
        content: Text(
          'Are you sure you want to permanently delete "${activeItem.name}"?\n'
          'Category: ${activeItem.category}\n'
          'Current stock: ${activeItem.formattedStock}\n\n'
          'This action cannot be undone.',
          style: AppTypography.bodyMd,
        ),
        actions: [
          TextButton(
            onPressed: () => Navigator.of(dialogContext).pop(false),
            child: const Text('Cancel'),
          ),
          FilledButton(
            style: FilledButton.styleFrom(
              backgroundColor: AppColors.error,
              foregroundColor: Colors.white,
            ),
            onPressed: () => Navigator.of(dialogContext).pop(true),
            child: const Text('Delete Item'),
          ),
        ],
      ),
    );

    if (confirmed == true && context.mounted) {
      try {
        await ref.read(inventoryProvider.notifier).deleteItem(activeItem.id);
        if (context.mounted) {
          Navigator.of(context).pop();
          ScaffoldMessenger.of(context).showSnackBar(
            SnackBar(
              backgroundColor: AppColors.primaryContainer,
              content: Row(
                children: [
                  const Icon(Icons.check_circle, color: Colors.white),
                  const SizedBox(width: AppSpacing.xs),
                  Expanded(
                    child: Text(
                      'Item "${activeItem.name}" deleted successfully.',
                      style: const TextStyle(color: Colors.white),
                    ),
                  ),
                ],
              ),
            ),
          );
        }
      } catch (e) {
        if (context.mounted) {
          ScaffoldMessenger.of(context).showSnackBar(
            SnackBar(
              backgroundColor: AppColors.error,
              content: Text('Failed to delete item: $e'),
            ),
          );
        }
      }
    }
  }

  Future<void> _handleStockIn(BuildContext context, InventoryItem activeItem) async {
    await showDialog(
      context: context,
      builder: (_) => StockOperationDialog.stockIn(item: activeItem),
    );
  }

  Future<void> _handleStockOut(BuildContext context, InventoryItem activeItem) async {
    await showDialog(
      context: context,
      builder: (_) => StockOperationDialog.stockOut(item: activeItem),
    );
  }

  Future<void> _handleViewHistory(BuildContext context, InventoryItem activeItem) async {
    await showDialog(
      context: context,
      builder: (_) => InventoryTransactionHistoryDialog(item: activeItem),
    );
  }

  Future<void> _handleCreatePO(BuildContext context, InventoryItem activeItem) async {
    await showDialog(
      context: context,
      builder: (_) => PurchaseOrderFormDialog(
        preselectedInventoryItem: activeItem,
        preselectedVendorId: activeItem.vendorId,
      ),
    );
  }

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    // Keep active item reactive to stock updates
    final allItems = ref.watch(inventoryProvider).value ?? [];
    final activeItem = allItems.firstWhere(
      (i) => i.id == item.id,
      orElse: () => item,
    );

    // Watch transactions for this item
    final transactionsAsync = ref.watch(itemTransactionsProvider(activeItem.id));

    // Role-based permissions
    final role = ref.watch(currentUserRoleProvider).valueOrNull;
    final canManageInventory = role == 'admin' || role == 'staff';

    final dateFormat = DateFormat('MMM d, yyyy, h:mm a');
    final isDesktop = MediaQuery.sizeOf(context).width > 700;

    return Dialog(
      shape: RoundedRectangleBorder(
        borderRadius: BorderRadius.circular(AppSpacing.radiusXl),
      ),
      backgroundColor: AppColors.surfaceContainerLowest,
      insetPadding: const EdgeInsets.symmetric(
        horizontal: AppSpacing.md,
        vertical: AppSpacing.lg,
      ),
      child: ConstrainedBox(
        constraints: BoxConstraints(
          maxWidth: isDesktop ? 620 : 440,
          maxHeight: MediaQuery.sizeOf(context).height * 0.9,
        ),
        child: Column(
          mainAxisSize: MainAxisSize.min,
          crossAxisAlignment: CrossAxisAlignment.stretch,
          children: [
            // Header
            Padding(
              padding: const EdgeInsets.symmetric(
                horizontal: AppSpacing.lg,
                vertical: AppSpacing.md,
              ),
              child: Row(
                mainAxisAlignment: MainAxisAlignment.spaceBetween,
                children: [
                  Expanded(
                    child: Row(
                      children: [
                        Container(
                          padding: const EdgeInsets.all(AppSpacing.xs),
                          decoration: BoxDecoration(
                            color: AppColors.primaryContainer.withValues(alpha: 0.15),
                            borderRadius: BorderRadius.circular(AppSpacing.radiusMd),
                          ),
                          child: const Icon(
                            Icons.inventory_2_outlined,
                            color: AppColors.primary,
                            size: 24,
                          ),
                        ),
                        const SizedBox(width: AppSpacing.sm),
                        Expanded(
                          child: Column(
                            crossAxisAlignment: CrossAxisAlignment.start,
                            children: [
                              Text(
                                activeItem.name,
                                style: AppTypography.headlineMd.copyWith(
                                  fontWeight: FontWeight.w700,
                                ),
                                overflow: TextOverflow.ellipsis,
                              ),
                              Text(
                                activeItem.category,
                                style: AppTypography.bodySm.copyWith(
                                  color: AppColors.onSurfaceVariant,
                                ),
                              ),
                            ],
                          ),
                        ),
                      ],
                    ),
                  ),
                  IconButton(
                    icon: const Icon(Icons.close),
                    onPressed: () => Navigator.of(context).pop(),
                  ),
                ],
              ),
            ),
            const Divider(height: 1, color: AppColors.outlineVariant),

            // Scrollable Content
            Flexible(
              child: SingleChildScrollView(
                padding: const EdgeInsets.all(AppSpacing.lg),
                child: Column(
                  crossAxisAlignment: CrossAxisAlignment.start,
                  children: [
                    // Stock Summary Card
                    _buildStockSummaryCard(activeItem),
                    const SizedBox(height: AppSpacing.md),

                    // Quick Action Buttons (Stock In, Stock Out, History, Create Purchase Order)
                    _buildQuickActionButtons(context, activeItem),
                    const SizedBox(height: AppSpacing.lg),

                    // Suppliers / Vendors Supplying This Product (unified)
                    _buildSuppliersSection(context, ref, activeItem, dateFormat),
                    const SizedBox(height: AppSpacing.lg),

                    // Inventory Batches
                    _buildInventoryBatchesSection(context, ref, activeItem, dateFormat),
                    const SizedBox(height: AppSpacing.lg),

                    // Product Purchase & Supply History
                    _buildProductPurchaseHistorySection(context, ref, activeItem, dateFormat),
                    const SizedBox(height: AppSpacing.lg),

                    // Recent Transactions Section
                    _buildRecentTransactionsSection(
                      context,
                      ref,
                      activeItem,
                      transactionsAsync,
                      dateFormat,
                    ),
                    const SizedBox(height: AppSpacing.lg),

                    // Details & Specifications Grid
                    _buildInfoSection('DETAILS & SPECS', [
                      _buildInfoRow('Category', activeItem.category),
                      _buildInfoRow('Measurement Unit', activeItem.unit),
                      if (activeItem.sku != null && activeItem.sku!.isNotEmpty)
                        _buildInfoRow('SKU / Code', activeItem.sku!),
                      if (activeItem.department != null && activeItem.department!.isNotEmpty)
                        _buildInfoRow('Department', activeItem.department!.toUpperCase()),
                      if (activeItem.brand != null && activeItem.brand!.isNotEmpty)
                        _buildInfoRow('Brand / Manufacturer', activeItem.brand!),
                      if (activeItem.vendorName != null && activeItem.vendorName!.isNotEmpty)
                        _buildInfoRow('Last Supplier', activeItem.vendorName!),
                      if (activeItem.price != null)
                        _buildInfoRow('Unit Price', '₹${activeItem.price!.toStringAsFixed(2)}'),
                      _buildInfoRow(
                        'Item Status',
                        activeItem.isActive ? 'Active' : 'Inactive',
                        badgeColor: activeItem.isActive ? Colors.green : Colors.grey,
                      ),
                      _buildInfoRow(
                        'Stock Health',
                        activeItem.stockStatusLabel,
                        badgeColor: activeItem.stockStatusColor,
                      ),
                      if (activeItem.expiryDate != null)
                        _buildInfoRow(
                          'Expiry Status',
                          activeItem.expiryStatusLabel,
                          badgeColor: activeItem.expiryStatusColor,
                        ),
                    ]),
                    const SizedBox(height: AppSpacing.md),

                    // Description / Remarks
                    if (activeItem.description != null &&
                        activeItem.description!.isNotEmpty) ...[
                      Text(
                        'DESCRIPTION / REMARKS',
                        style: AppTypography.labelCaps.copyWith(
                          color: AppColors.onSurfaceVariant,
                        ),
                      ),
                      const SizedBox(height: AppSpacing.xs),
                      Container(
                        width: double.infinity,
                        padding: const EdgeInsets.all(AppSpacing.md),
                        decoration: BoxDecoration(
                          color: AppColors.surfaceContainerLow,
                          borderRadius: BorderRadius.circular(AppSpacing.radiusMd),
                          border: Border.all(color: AppColors.outlineVariant),
                        ),
                        child: Text(
                          activeItem.description!,
                          style: AppTypography.bodyMd,
                        ),
                      ),
                      const SizedBox(height: AppSpacing.md),
                    ],

                    // Audit Trail Timestamps
                    _buildInfoSection('AUDIT TRAIL', [
                      _buildInfoRow(
                        'Created At',
                        activeItem.createdAt != null
                            ? dateFormat.format(activeItem.createdAt!.toLocal())
                            : '—',
                      ),
                      _buildInfoRow(
                        'Last Updated',
                        activeItem.updatedAt != null
                            ? dateFormat.format(activeItem.updatedAt!.toLocal())
                            : '—',
                      ),
                      _buildInfoRow('Item ID', activeItem.id),
                    ]),
                  ],
                ),
              ),
            ),
            const Divider(height: 1, color: AppColors.outlineVariant),

            // Footer Actions (Role-Enforced)
            Padding(
              padding: const EdgeInsets.all(AppSpacing.md),
              child: Row(
                mainAxisAlignment: MainAxisAlignment.spaceBetween,
                children: [
                  if (canManageInventory) ...[
                    OutlinedButton.icon(
                      onPressed: () => _handleDelete(context, ref, activeItem),
                      icon: const Icon(Icons.delete_outline, size: 18),
                      label: const Text('Delete'),
                      style: OutlinedButton.styleFrom(
                        foregroundColor: AppColors.error,
                        side: const BorderSide(color: AppColors.error),
                      ),
                    ),
                  ] else ...[
                    const Spacer(),
                  ],
                  Row(
                    children: [
                      TextButton(
                        onPressed: () => Navigator.of(context).pop(),
                        child: const Text('Close'),
                      ),
                      if (canManageInventory) ...[
                        const SizedBox(width: AppSpacing.sm),
                        FilledButton.icon(
                          onPressed: () => _handleEdit(context, activeItem),
                          icon: const Icon(Icons.edit_outlined, size: 18),
                          label: const Text('Edit Item'),
                          style: FilledButton.styleFrom(
                            backgroundColor: AppColors.primary,
                            foregroundColor: AppColors.onPrimary,
                          ),
                        ),
                      ],
                    ],
                  ),
                ],
              ),
            ),
          ],
        ),
      ),
    );
  }

  Widget _buildStockSummaryCard(InventoryItem activeItem) {
    return Container(
      padding: const EdgeInsets.all(AppSpacing.md),
      decoration: BoxDecoration(
        color: activeItem.isLowStock
            ? AppColors.errorContainer.withValues(alpha: 0.15)
            : AppColors.surfaceContainerLow,
        borderRadius: BorderRadius.circular(AppSpacing.radiusLg),
        border: Border.all(
          color: activeItem.isLowStock
              ? AppColors.error.withValues(alpha: 0.3)
              : AppColors.outlineVariant,
        ),
      ),
      child: Column(
        children: [
          Row(
            children: [
              Expanded(
                child: Column(
                  crossAxisAlignment: CrossAxisAlignment.start,
                  children: [
                    Text(
                      'CURRENT STOCK',
                      style: AppTypography.labelCaps.copyWith(
                        color: AppColors.onSurfaceVariant,
                      ),
                    ),
                    const SizedBox(height: 4),
                    Row(
                      children: [
                        Flexible(
                          child: Text(
                            activeItem.formattedStock,
                            style: AppTypography.displayLg.copyWith(
                              fontSize: 28,
                              fontWeight: FontWeight.w700,
                              color: activeItem.isLowStock
                                  ? AppColors.error
                                  : AppColors.primary,
                            ),
                            overflow: TextOverflow.ellipsis,
                          ),
                        ),
                        if (activeItem.isLowStock) ...[
                          const SizedBox(width: AppSpacing.xs),
                          Container(
                            padding: const EdgeInsets.symmetric(
                              horizontal: 6,
                              vertical: 2,
                            ),
                            decoration: BoxDecoration(
                              color: AppColors.error,
                              borderRadius: BorderRadius.circular(4),
                            ),
                            child: const Text(
                              'LOW STOCK',
                              style: TextStyle(
                                color: Colors.white,
                                fontSize: 10,
                                fontWeight: FontWeight.w700,
                              ),
                            ),
                          ),
                        ],
                      ],
                    ),
                  ],
                ),
              ),
              if (activeItem.minimumStock != null)
                Column(
                  crossAxisAlignment: CrossAxisAlignment.end,
                  children: [
                    Text(
                      'MIN THRESHOLD',
                      style: AppTypography.labelCaps.copyWith(
                        color: AppColors.onSurfaceVariant,
                      ),
                    ),
                    const SizedBox(height: 4),
                    Text(
                      activeItem.formattedMinStock!,
                      style: AppTypography.bodyMd.copyWith(
                        fontWeight: FontWeight.w600,
                      ),
                    ),
                  ],
                ),
            ],
          ),
          if (activeItem.expiryDate != null) ...[
            const SizedBox(height: AppSpacing.sm),
            const Divider(height: 1, color: AppColors.outlineVariant),
            const SizedBox(height: AppSpacing.sm),
            Row(
              children: [
                Icon(
                  activeItem.expiryStatusIcon,
                  size: 16,
                  color: activeItem.expiryStatusColor,
                ),
                const SizedBox(width: 6),
                Text(
                  'Expiry: ',
                  style: AppTypography.bodySm.copyWith(
                    color: AppColors.onSurfaceVariant,
                  ),
                ),
                Text(
                  DateFormat('MMM d, yyyy').format(activeItem.expiryDate!),
                  style: AppTypography.bodySm.copyWith(
                    fontWeight: FontWeight.w600,
                  ),
                ),
                const Spacer(),
                Container(
                  padding: const EdgeInsets.symmetric(horizontal: 8, vertical: 2),
                  decoration: BoxDecoration(
                    color: activeItem.expiryStatusColor.withValues(alpha: 0.15),
                    borderRadius: BorderRadius.circular(4),
                    border: Border.all(color: activeItem.expiryStatusColor),
                  ),
                  child: Text(
                    activeItem.expiryStatusLabel,
                    style: TextStyle(
                      color: activeItem.expiryStatusColor,
                      fontSize: 10,
                      fontWeight: FontWeight.w700,
                    ),
                  ),
                ),
              ],
            ),
          ],
        ],
      ),
    );
  }

  Widget _buildQuickActionButtons(BuildContext context, InventoryItem activeItem) {
    return Column(
      children: [
        Row(
          children: [
            // Stock In
            Expanded(
              child: FilledButton.icon(
                onPressed: () => _handleStockIn(context, activeItem),
                icon: const Icon(Icons.add_circle_outline, size: 18),
                label: const Text('Stock In'),
                style: FilledButton.styleFrom(
                  backgroundColor: Colors.green.shade700,
                  foregroundColor: Colors.white,
                  padding: const EdgeInsets.symmetric(vertical: 10),
                ),
              ),
            ),
            const SizedBox(width: AppSpacing.sm),

            // Stock Out
            Expanded(
              child: FilledButton.icon(
                onPressed: () => _handleStockOut(context, activeItem),
                icon: const Icon(Icons.remove_circle_outline, size: 18),
                label: const Text('Stock Out'),
                style: FilledButton.styleFrom(
                  backgroundColor: const Color(0xFFE65100),
                  foregroundColor: Colors.white,
                  padding: const EdgeInsets.symmetric(vertical: 10),
                ),
              ),
            ),
            const SizedBox(width: AppSpacing.sm),

            // History
            IconButton.outlined(
              tooltip: 'Transaction History',
              onPressed: () => _handleViewHistory(context, activeItem),
              icon: const Icon(Icons.history, size: 20),
            ),
          ],
        ),
        const SizedBox(height: AppSpacing.sm),
        SizedBox(
          width: double.infinity,
          child: FilledButton.icon(
            onPressed: () => _handleCreatePO(context, activeItem),
            icon: const Icon(Icons.add_shopping_cart, size: 18),
            label: const Text('Create Purchase Order'),
            style: FilledButton.styleFrom(
              backgroundColor: AppColors.primary,
              foregroundColor: Colors.white,
              padding: const EdgeInsets.symmetric(vertical: 10),
            ),
          ),
        ),
      ],
    );
  }

  Widget _buildSuppliersSection(
    BuildContext context,
    WidgetRef ref,
    InventoryItem activeItem,
    DateFormat dateFormat,
  ) {
    final allVendors = ref.watch(vendorsProvider).value ?? [];
    final allPOs = ref.watch(purchaseOrdersProvider).value ?? [];
    final matchingPOs = allPOs
        .where((po) => po.items.any((i) => i.inventoryId == activeItem.id))
        .toList();

    // Distinct vendor IDs associated with this product
    final Set<String> supplierVendorIds = {};
    if (activeItem.vendorId != null && activeItem.vendorId!.isNotEmpty) {
      supplierVendorIds.add(activeItem.vendorId!);
    }
    for (final po in matchingPOs) {
      if (po.vendorId.isNotEmpty) {
        supplierVendorIds.add(po.vendorId);
      }
    }

    return Column(
      crossAxisAlignment: CrossAxisAlignment.start,
      children: [
        Text(
          'SUPPLIERS / VENDORS SUPPLYING THIS PRODUCT (${supplierVendorIds.length})',
          style: AppTypography.labelCaps.copyWith(
            color: AppColors.primary,
            fontWeight: FontWeight.w700,
          ),
        ),
        const SizedBox(height: AppSpacing.xs),
        Container(
          width: double.infinity,
          padding: const EdgeInsets.all(AppSpacing.md),
          decoration: BoxDecoration(
            color: AppColors.surfaceContainerLow,
            borderRadius: BorderRadius.circular(AppSpacing.radiusLg),
            border: Border.all(color: AppColors.outlineVariant),
          ),
          child: supplierVendorIds.isEmpty
              ? Row(
                  children: [
                    Expanded(
                      child: Column(
                        crossAxisAlignment: CrossAxisAlignment.start,
                        children: [
                          Text(
                            'No Vendor Associated',
                            style: AppTypography.bodyMd.copyWith(
                              fontWeight: FontWeight.w600,
                              color: AppColors.onSurfaceVariant,
                            ),
                          ),
                          const SizedBox(height: 2),
                          Text(
                            'No supplier has been recorded for this item yet.',
                            style: AppTypography.bodySm.copyWith(
                              color: AppColors.onSurfaceVariant,
                              fontSize: 12,
                            ),
                          ),
                        ],
                      ),
                    ),
                    const SizedBox(width: AppSpacing.sm),
                    Tooltip(
                      message: 'No vendor associated',
                      child: FilledButton.icon(
                        onPressed: null,
                        icon: const Icon(Icons.phone_outlined, size: 16),
                        label: const Text('Call Vendor'),
                      ),
                    ),
                  ],
                )
              : ListView.separated(
                  shrinkWrap: true,
                  physics: const NeverScrollableScrollPhysics(),
                  itemCount: supplierVendorIds.length,
                  separatorBuilder: (_, __) => const Divider(height: 24),
                  itemBuilder: (context, index) {
                    final vendorId = supplierVendorIds.elementAt(index);
                    final vendor = allVendors.where((v) => v.id == vendorId).firstOrNull;
                    final isCurrentVendor = activeItem.vendorId == vendorId;

                    final vendorName = vendor?.name ??
                        (isCurrentVendor ? (activeItem.vendorName ?? 'Vendor') : 'Vendor');
                    final contactPerson = vendor?.contactPerson;
                    final vendorPhone = vendor?.phone ??
                        (isCurrentVendor ? activeItem.vendorPhone : null);
                    final vendorEmail = vendor?.email;
                    final hasPhone = vendorPhone != null && vendorPhone.trim().isNotEmpty;

                    // Derive last supply information for this specific product & vendor
                    final vendorPOs = matchingPOs.where((po) => po.vendorId == vendorId).toList();
                    vendorPOs.sort((a, b) => b.orderDate.compareTo(a.orderDate));
                    final latestPO = vendorPOs.firstOrNull;
                    final poItem = latestPO?.items.where((i) => i.inventoryId == activeItem.id).firstOrNull;

                    final double? lastQty = (poItem != null && poItem.receivedQuantity > 0)
                        ? poItem.receivedQuantity
                        : (poItem?.quantity ??
                            (isCurrentVendor ? activeItem.lastQuantitySupplied : null));

                    final DateTime? lastDate = latestPO?.actualDeliveryDate ??
                        latestPO?.orderDate ??
                        (isCurrentVendor ? (activeItem.updatedAt ?? activeItem.createdAt) : null);

                    final double? pricePiece = (poItem != null && poItem.unitPrice > 0)
                        ? poItem.unitPrice
                        : (isCurrentVendor
                            ? (activeItem.calculatedPricePerPiece ?? activeItem.price)
                            : null);

                    final double? totalAmount = (poItem != null && poItem.totalAmount > 0)
                        ? poItem.totalAmount
                        : (isCurrentVendor ? activeItem.lastTotalAmount : null);

                    return Column(
                      crossAxisAlignment: CrossAxisAlignment.start,
                      children: [
                        if (isCurrentVendor) ...[
                          Row(
                            children: [
                              const Icon(Icons.local_shipping_outlined, size: 16, color: AppColors.primary),
                              const SizedBox(width: 6),
                              Text(
                                'LAST SUPPLIED VENDOR & PRICING',
                                style: AppTypography.labelCaps.copyWith(
                                  color: AppColors.primary,
                                  fontWeight: FontWeight.w700,
                                  fontSize: 11,
                                ),
                              ),
                            ],
                          ),
                          const SizedBox(height: AppSpacing.xs),
                        ],
                        Row(
                          children: [
                            Expanded(
                              child: Column(
                                crossAxisAlignment: CrossAxisAlignment.start,
                                children: [
                                  Text(
                                    vendorName,
                                    style: AppTypography.bodyMd.copyWith(
                                      fontWeight: FontWeight.w700,
                                    ),
                                  ),
                                  if (contactPerson != null && contactPerson.trim().isNotEmpty) ...[
                                    const SizedBox(height: 2),
                                    Text(
                                      'Contact: $contactPerson',
                                      style: AppTypography.bodySm.copyWith(
                                        color: AppColors.onSurfaceVariant,
                                        fontSize: 12,
                                      ),
                                    ),
                                  ],
                                  const SizedBox(height: 2),
                                  Row(
                                    children: [
                                      Icon(
                                        Icons.phone_outlined,
                                        size: 13,
                                        color: hasPhone ? AppColors.onSurfaceVariant : AppColors.error,
                                      ),
                                      const SizedBox(width: 4),
                                      Flexible(
                                        child: Text(
                                          hasPhone ? vendorPhone : 'Phone number unavailable',
                                          style: AppTypography.bodySm.copyWith(
                                            color: hasPhone ? AppColors.onSurfaceVariant : AppColors.error,
                                            fontSize: 12,
                                          ),
                                          overflow: TextOverflow.ellipsis,
                                        ),
                                      ),
                                    ],
                                  ),
                                  if (vendorEmail != null && vendorEmail.trim().isNotEmpty) ...[
                                    const SizedBox(height: 2),
                                    Row(
                                      children: [
                                        const Icon(
                                          Icons.email_outlined,
                                          size: 13,
                                          color: AppColors.onSurfaceVariant,
                                        ),
                                        const SizedBox(width: 4),
                                        Flexible(
                                          child: Text(
                                            vendorEmail,
                                            style: AppTypography.bodySm.copyWith(
                                              color: AppColors.onSurfaceVariant,
                                              fontSize: 12,
                                            ),
                                            overflow: TextOverflow.ellipsis,
                                          ),
                                        ),
                                      ],
                                    ),
                                  ],
                                ],
                              ),
                            ),
                            const SizedBox(width: AppSpacing.sm),
                            FilledButton.icon(
                              onPressed: hasPhone
                                  ? () => PhoneDialerUtil.launchDialer(context, vendorPhone)
                                  : null,
                              icon: const Icon(Icons.phone_outlined, size: 16),
                              label: const Text('Call Vendor'),
                              style: FilledButton.styleFrom(
                                backgroundColor: AppColors.primary,
                                foregroundColor: Colors.white,
                                disabledBackgroundColor: AppColors.surfaceContainerHigh,
                                disabledForegroundColor: AppColors.onSurfaceVariant.withValues(alpha: 0.5),
                                padding: const EdgeInsets.symmetric(horizontal: 12, vertical: 8),
                              ),
                            ),
                          ],
                        ),
                        if (lastQty != null || lastDate != null || pricePiece != null || totalAmount != null) ...[
                          const SizedBox(height: AppSpacing.xs),
                          Container(
                            padding: const EdgeInsets.symmetric(horizontal: 10, vertical: 6),
                            decoration: BoxDecoration(
                              color: AppColors.surfaceContainerLowest,
                              borderRadius: BorderRadius.circular(AppSpacing.radiusSm),
                              border: Border.all(color: AppColors.outlineVariant.withValues(alpha: 0.5)),
                            ),
                            child: Column(
                              crossAxisAlignment: CrossAxisAlignment.start,
                              children: [
                                Row(
                                  children: [
                                    Expanded(
                                      child: _buildVendorStat(
                                        label: 'Last Supply',
                                        value: lastQty != null
                                            ? '${lastQty % 1 == 0 ? lastQty.toInt() : lastQty.toStringAsFixed(2)} ${activeItem.unit}'
                                            : '—',
                                      ),
                                    ),
                                    if (totalAmount != null)
                                      Expanded(
                                        child: _buildVendorStat(
                                          label: 'Total Paid',
                                          value: '₹${totalAmount.toStringAsFixed(2)}',
                                        ),
                                      ),
                                    Expanded(
                                      child: _buildVendorStat(
                                        label: 'Price/Piece',
                                        value: pricePiece != null ? '₹${pricePiece.toStringAsFixed(2)}' : '—',
                                        highlight: true,
                                      ),
                                    ),
                                  ],
                                ),
                                if (lastDate != null) ...[
                                  const SizedBox(height: 4),
                                  Text(
                                    'Last Supply Date: ${DateFormat('dd/MM/yyyy').format(lastDate)}',
                                    style: AppTypography.bodySm.copyWith(
                                      color: AppColors.onSurfaceVariant,
                                      fontSize: 11,
                                    ),
                                  ),
                                ],
                              ],
                            ),
                          ),
                        ],
                      ],
                    );
                  },
                ),
        ),
      ],
    );
  }

  Widget _buildInventoryBatchesSection(
    BuildContext context,
    WidgetRef ref,
    InventoryItem activeItem,
    DateFormat dateFormat,
  ) {
    final batchesAsync = ref.watch(itemBatchesProvider(activeItem.id));

    return Column(
      crossAxisAlignment: CrossAxisAlignment.start,
      children: [
        Row(
          mainAxisAlignment: MainAxisAlignment.spaceBetween,
          children: [
            Text(
              'INVENTORY BATCHES',
              style: AppTypography.labelCaps.copyWith(
                color: AppColors.primary,
                fontWeight: FontWeight.w700,
              ),
            ),
          ],
        ),
        const SizedBox(height: AppSpacing.xs),
        Container(
          width: double.infinity,
          padding: const EdgeInsets.all(AppSpacing.md),
          decoration: BoxDecoration(
            color: AppColors.surfaceContainerLow,
            borderRadius: BorderRadius.circular(AppSpacing.radiusLg),
            border: Border.all(color: AppColors.outlineVariant),
          ),
          child: batchesAsync.when(
            loading: () => const Center(
              child: Padding(
                padding: EdgeInsets.all(AppSpacing.sm),
                child: SizedBox(width: 20, height: 20, child: CircularProgressIndicator(strokeWidth: 2)),
              ),
            ),
            error: (e, _) => Text(
              'Unable to load batches: $e',
              style: AppTypography.bodySm.copyWith(color: AppColors.error),
            ),
            data: (batches) {
              if (batches.isEmpty) {
                return Text(
                  'No inventory batches recorded yet.',
                  style: AppTypography.bodySm.copyWith(
                    color: AppColors.onSurfaceVariant,
                    fontStyle: FontStyle.italic,
                  ),
                );
              }

              return ListView.separated(
                shrinkWrap: true,
                physics: const NeverScrollableScrollPhysics(),
                itemCount: batches.length,
                separatorBuilder: (_, __) => const Divider(height: 16),
                itemBuilder: (context, index) {
                  final b = batches[index];
                  return Row(
                    crossAxisAlignment: CrossAxisAlignment.start,
                    children: [
                      Container(
                        padding: const EdgeInsets.all(6),
                        decoration: BoxDecoration(
                          color: AppColors.primary.withValues(alpha: 0.1),
                          borderRadius: BorderRadius.circular(AppSpacing.radiusSm),
                        ),
                        child: const Icon(Icons.inventory_outlined, size: 20, color: AppColors.primary),
                      ),
                      const SizedBox(width: AppSpacing.sm),
                      Expanded(
                        child: Column(
                          crossAxisAlignment: CrossAxisAlignment.start,
                          children: [
                            Row(
                              children: [
                                Flexible(
                                  child: Text(
                                    b.batchNumber,
                                    style: AppTypography.bodyMd.copyWith(
                                      fontWeight: FontWeight.w700,
                                    ),
                                    overflow: TextOverflow.ellipsis,
                                  ),
                                ),
                                const SizedBox(width: AppSpacing.xs),
                                Container(
                                  padding: const EdgeInsets.symmetric(horizontal: 6, vertical: 2),
                                  decoration: BoxDecoration(
                                    color: b.expiryStatusColor.withValues(alpha: 0.12),
                                    borderRadius: BorderRadius.circular(4),
                                    border: Border.all(color: b.expiryStatusColor),
                                  ),
                                  child: Text(
                                    b.expiryStatusLabel,
                                    style: TextStyle(
                                      color: b.expiryStatusColor,
                                      fontWeight: FontWeight.w700,
                                      fontSize: 10,
                                    ),
                                  ),
                                ),
                              ],
                            ),
                            const SizedBox(height: 2),
                            Text(
                              'PO: ${b.purchaseOrderNumber ?? '—'} • Vendor: ${b.vendorName ?? '—'}',
                              style: AppTypography.bodySm.copyWith(
                                color: AppColors.onSurfaceVariant,
                                fontSize: 11,
                              ),
                            ),
                            Text(
                              'Received: ${b.formattedReceivedDate} (${b.formattedReceivedQuantity} ${activeItem.unit}) • Remaining: ${b.formattedRemainingQuantity} ${activeItem.unit}',
                              style: AppTypography.bodySm.copyWith(
                                color: AppColors.onSurfaceVariant,
                                fontSize: 11,
                              ),
                            ),
                            Text(
                              'Expiry: ${b.formattedExpiryDate} • Unit Price: ${b.formattedUnitPrice}',
                              style: AppTypography.bodySm.copyWith(
                                color: AppColors.onSurfaceVariant,
                                fontSize: 11,
                              ),
                            ),
                          ],
                        ),
                      ),
                    ],
                  );
                },
              );
            },
          ),
        ),
      ],
    );
  }


  Widget _buildVendorStat({
    required String label,
    required String value,
    bool highlight = false,
  }) {
    return Column(
      crossAxisAlignment: CrossAxisAlignment.start,
      children: [
        Text(
          label,
          style: AppTypography.labelCaps.copyWith(
            color: AppColors.onSurfaceVariant,
            fontSize: 9,
          ),
        ),
        const SizedBox(height: 2),
        Text(
          value,
          style: AppTypography.bodyMd.copyWith(
            fontWeight: FontWeight.w700,
            color: highlight ? AppColors.primary : AppColors.onSurface,
          ),
        ),
      ],
    );
  }

  Widget _buildRecentTransactionsSection(
    BuildContext context,
    WidgetRef ref,
    InventoryItem activeItem,
    AsyncValue<List<InventoryTransaction>> transactionsAsync,
    DateFormat dateFormat,
  ) {
    return Column(
      crossAxisAlignment: CrossAxisAlignment.start,
      children: [
        Row(
          mainAxisAlignment: MainAxisAlignment.spaceBetween,
          children: [
            Text(
              'RECENT TRANSACTIONS',
              style: AppTypography.labelCaps.copyWith(
                color: AppColors.onSurfaceVariant,
              ),
            ),
            TextButton.icon(
              onPressed: () => _handleViewHistory(context, activeItem),
              icon: const Icon(Icons.open_in_new, size: 14),
              label: const Text('View All', style: TextStyle(fontSize: 12)),
            ),
          ],
        ),
        const SizedBox(height: AppSpacing.xs),
        transactionsAsync.when(
          loading: () => const Center(
            child: Padding(
              padding: EdgeInsets.all(AppSpacing.md),
              child: SizedBox(
                width: 24,
                height: 24,
                child: CircularProgressIndicator(strokeWidth: 2),
              ),
            ),
          ),
          error: (e, _) => Container(
            padding: const EdgeInsets.all(AppSpacing.md),
            decoration: BoxDecoration(
              color: AppColors.surfaceContainerLow,
              borderRadius: BorderRadius.circular(AppSpacing.radiusMd),
            ),
            child: Text(
              'Unable to load transactions: $e',
              style: AppTypography.bodySm.copyWith(color: AppColors.error),
            ),
          ),
          data: (transactions) {
            if (transactions.isEmpty) {
              return Container(
                width: double.infinity,
                padding: const EdgeInsets.all(AppSpacing.md),
                decoration: BoxDecoration(
                  color: AppColors.surfaceContainerLow,
                  borderRadius: BorderRadius.circular(AppSpacing.radiusMd),
                  border: Border.all(color: AppColors.outlineVariant),
                ),
                child: Column(
                  children: [
                    const Icon(
                      Icons.history,
                      size: 28,
                      color: AppColors.onSurfaceVariant,
                    ),
                    const SizedBox(height: 4),
                    Text(
                      'No stock transactions yet.',
                      style: AppTypography.bodySm.copyWith(
                        fontWeight: FontWeight.w600,
                      ),
                    ),
                  ],
                ),
              );
            }

            final recent = transactions.take(3).toList();
            return Column(
              children: recent.map((tx) {
                return Container(
                  margin: const EdgeInsets.only(bottom: 6),
                  padding: const EdgeInsets.all(10),
                  decoration: BoxDecoration(
                    color: AppColors.surfaceContainerLow,
                    borderRadius: BorderRadius.circular(AppSpacing.radiusMd),
                    border: Border.all(color: AppColors.outlineVariant),
                  ),
                  child: Row(
                    children: [
                      Container(
                        padding: const EdgeInsets.all(4),
                        decoration: BoxDecoration(
                          color: tx.typeColor.withValues(alpha: 0.15),
                          shape: BoxShape.circle,
                        ),
                        child: Icon(tx.typeIcon, size: 16, color: tx.typeColor),
                      ),
                      const SizedBox(width: AppSpacing.sm),
                      Expanded(
                        child: Column(
                          crossAxisAlignment: CrossAxisAlignment.start,
                          children: [
                            Row(
                              children: [
                                Text(
                                  tx.typeLabel,
                                  style: AppTypography.bodySm.copyWith(
                                    fontWeight: FontWeight.w700,
                                    color: tx.typeColor,
                                  ),
                                ),
                                if (tx.formattedStockProgression != null) ...[
                                  const SizedBox(width: 6),
                                  Text(
                                    '(${tx.formattedStockProgression})',
                                    style: AppTypography.bodySm.copyWith(
                                      fontSize: 11,
                                      color: AppColors.onSurfaceVariant,
                                    ),
                                  ),
                                ],
                              ],
                            ),
                            if (tx.reason != null && tx.reason!.isNotEmpty)
                              Text(
                                tx.reason!,
                                style: AppTypography.bodySm.copyWith(
                                  fontSize: 11,
                                  color: AppColors.onSurfaceVariant,
                                ),
                                overflow: TextOverflow.ellipsis,
                              ),
                            if (tx.reason == 'Dispensed to Patient')
                              Text(
                                'Patient: ${tx.patientDisplay ?? '—'}',
                                style: AppTypography.bodySm.copyWith(
                                  fontSize: 11,
                                  fontWeight: FontWeight.w600,
                                  color: AppColors.primary,
                                ),
                                overflow: TextOverflow.ellipsis,
                              ),
                          ],
                        ),
                      ),
                      Column(
                        crossAxisAlignment: CrossAxisAlignment.end,
                        children: [
                          Text(
                            '${tx.formattedQuantity} ${activeItem.unit}',
                            style: AppTypography.bodySm.copyWith(
                              fontWeight: FontWeight.w800,
                              color: tx.typeColor,
                            ),
                          ),
                          Text(
                            dateFormat.format(tx.createdAt.toLocal()),
                            style: AppTypography.bodySm.copyWith(
                              fontSize: 10,
                              color: AppColors.onSurfaceVariant,
                            ),
                          ),
                        ],
                      ),
                    ],
                  ),
                );
              }).toList(),
            );
          },
        ),
      ],
    );
  }

  Widget _buildInfoSection(String title, List<Widget> children) {
    return Column(
      crossAxisAlignment: CrossAxisAlignment.start,
      children: [
        Text(
          title,
          style: AppTypography.labelCaps.copyWith(
            color: AppColors.onSurfaceVariant,
          ),
        ),
        const SizedBox(height: AppSpacing.xs),
        Container(
          padding: const EdgeInsets.symmetric(
            horizontal: AppSpacing.md,
            vertical: AppSpacing.sm,
          ),
          decoration: BoxDecoration(
            color: AppColors.surfaceContainerLowest,
            borderRadius: BorderRadius.circular(AppSpacing.radiusMd),
            border: Border.all(color: AppColors.outlineVariant),
          ),
          child: Column(children: children),
        ),
      ],
    );
  }

  Widget _buildInfoRow(String label, String value, {Color? badgeColor}) {
    return Padding(
      padding: const EdgeInsets.symmetric(vertical: 6),
      child: Row(
        mainAxisAlignment: MainAxisAlignment.spaceBetween,
        children: [
          Text(
            label,
            style: AppTypography.bodySm.copyWith(
              color: AppColors.onSurfaceVariant,
            ),
          ),
          if (badgeColor != null)
            Container(
              padding: const EdgeInsets.symmetric(horizontal: 8, vertical: 2),
              decoration: BoxDecoration(
                color: badgeColor.withValues(alpha: 0.15),
                borderRadius: BorderRadius.circular(4),
                border: Border.all(color: badgeColor),
              ),
              child: Text(
                value,
                style: TextStyle(
                  color: badgeColor,
                  fontWeight: FontWeight.w700,
                  fontSize: 11,
                ),
              ),
            )
          else
            Flexible(
              child: Text(
                value,
                style: AppTypography.bodySm.copyWith(
                  fontWeight: FontWeight.w600,
                  color: AppColors.onSurface,
                ),
                textAlign: TextAlign.end,
                overflow: TextOverflow.ellipsis,
              ),
            ),
        ],
      ),
    );
  }

  Widget _buildProductPurchaseHistorySection(
    BuildContext context,
    WidgetRef ref,
    InventoryItem activeItem,
    DateFormat dateFormat,
  ) {
    final allPOs = ref.watch(purchaseOrdersProvider).value ?? [];
    final matchingPOs = allPOs
        .where((po) => po.items.any((i) => i.inventoryId == activeItem.id))
        .toList();

    return Column(
      crossAxisAlignment: CrossAxisAlignment.start,
      children: [
        Row(
          mainAxisAlignment: MainAxisAlignment.spaceBetween,
          children: [
            Text(
              'PURCHASE & SUPPLY ORDERS (${matchingPOs.length})',
              style: AppTypography.labelCaps.copyWith(
                color: AppColors.primary,
                fontWeight: FontWeight.w700,
              ),
            ),
          ],
        ),
        const SizedBox(height: AppSpacing.xs),
        Container(
          width: double.infinity,
          padding: const EdgeInsets.all(AppSpacing.md),
          decoration: BoxDecoration(
            color: AppColors.surfaceContainerLow,
            borderRadius: BorderRadius.circular(AppSpacing.radiusLg),
            border: Border.all(color: AppColors.outlineVariant),
          ),
          child: matchingPOs.isEmpty
              ? Text(
                  'No purchase orders recorded for this product yet.',
                  style: AppTypography.bodySm.copyWith(
                    color: AppColors.onSurfaceVariant,
                    fontStyle: FontStyle.italic,
                  ),
                )
              : ListView.separated(
                  shrinkWrap: true,
                  physics: const NeverScrollableScrollPhysics(),
                  itemCount: matchingPOs.length,
                  separatorBuilder: (_, __) => const Divider(height: 12),
                  itemBuilder: (context, index) {
                    final po = matchingPOs[index];
                    final poItem = po.items
                        .firstWhere((i) => i.inventoryId == activeItem.id);

                    return InkWell(
                      onTap: () {
                        showDialog(
                          context: context,
                          builder: (_) => PurchaseOrderDetailsDialog(order: po),
                        );
                      },
                      borderRadius: BorderRadius.circular(AppSpacing.radiusMd),
                      child: Padding(
                        padding: const EdgeInsets.symmetric(vertical: 4),
                        child: Row(
                          mainAxisAlignment: MainAxisAlignment.spaceBetween,
                          children: [
                            Expanded(
                              child: Column(
                                crossAxisAlignment: CrossAxisAlignment.start,
                                children: [
                                  Row(
                                    children: [
                                      Flexible(
                                        child: Text(
                                          po.purchaseOrderNumber,
                                          style: AppTypography.bodyMd.copyWith(
                                            fontWeight: FontWeight.w700,
                                          ),
                                          overflow: TextOverflow.ellipsis,
                                        ),
                                      ),
                                      const SizedBox(width: AppSpacing.xs),
                                      Container(
                                        padding: const EdgeInsets.symmetric(
                                            horizontal: 6, vertical: 2),
                                        decoration: BoxDecoration(
                                          color: po.status.color
                                              .withValues(alpha: 0.12),
                                          borderRadius: BorderRadius.circular(4),
                                          border:
                                              Border.all(color: po.status.color),
                                        ),
                                        child: Text(
                                          po.status.label,
                                          style: TextStyle(
                                            color: po.status.color,
                                            fontWeight: FontWeight.w700,
                                            fontSize: 10,
                                          ),
                                        ),
                                      ),
                                    ],
                                  ),
                                  const SizedBox(height: 2),
                                  Text(
                                    'Supplier: ${po.vendorName ?? 'Vendor'} • Ordered: ${poItem.formattedQuantity} (Recv: ${poItem.formattedReceivedQuantity})',
                                    style: AppTypography.bodySm.copyWith(
                                      color: AppColors.onSurfaceVariant,
                                      fontSize: 11,
                                    ),
                                    overflow: TextOverflow.ellipsis,
                                  ),
                                  Text(
                                    'Date: ${dateFormat.format(po.orderDate)}${po.actualDeliveryDate != null ? ' • Delivered: ${dateFormat.format(po.actualDeliveryDate!)}' : ''}',
                                    style: AppTypography.bodySm.copyWith(
                                      color: AppColors.onSurfaceVariant,
                                      fontSize: 11,
                                    ),
                                    overflow: TextOverflow.ellipsis,
                                  ),
                                ],
                              ),
                            ),
                            Row(
                              children: [
                                Text(
                                  poItem.formattedTotalAmount,
                                  style: AppTypography.bodyMd.copyWith(
                                    fontWeight: FontWeight.w700,
                                    color: AppColors.primary,
                                  ),
                                ),
                                const SizedBox(width: 4),
                                const Icon(Icons.chevron_right,
                                    size: 18, color: AppColors.outline),
                              ],
                            ),
                          ],
                        ),
                      ),
                    );
                  },
                ),
        ),
      ],
    );
  }
}
