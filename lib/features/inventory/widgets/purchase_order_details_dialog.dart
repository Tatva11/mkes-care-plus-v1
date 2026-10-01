import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:intl/intl.dart';
import 'package:url_launcher/url_launcher.dart';

import '../../../core/theme/app_colors.dart';
import '../../../core/theme/app_spacing.dart';
import '../../../core/theme/app_typography.dart';
import '../models/purchase_order.dart';
import '../providers/inventory_provider.dart';
import '../providers/purchase_order_provider.dart';
import 'purchase_order_form_dialog.dart';
import 'receive_purchase_order_dialog.dart';

/// Modal dialog displaying comprehensive details of a [PurchaseOrder].
/// Admin and Staff have IDENTICAL capabilities: View, Edit, Cancel, and Receive items.
class PurchaseOrderDetailsDialog extends ConsumerWidget {
  const PurchaseOrderDetailsDialog({
    super.key,
    required this.order,
  });

  final PurchaseOrder order;

  Future<void> _handleCallVendor(BuildContext context, String? phone) async {
    if (phone == null || phone.trim().isEmpty) {
      ScaffoldMessenger.of(context).showSnackBar(
        const SnackBar(content: Text('No phone number available for this vendor.')),
      );
      return;
    }

    final cleanedPhone = phone.replaceAll(RegExp(r'[^0-9+]'), '');
    final uri = Uri(scheme: 'tel', path: cleanedPhone);

    try {
      final canLaunch = await canLaunchUrl(uri);
      if (canLaunch) {
        await launchUrl(uri);
      } else {
        if (context.mounted) {
          ScaffoldMessenger.of(context).showSnackBar(
            SnackBar(content: Text('Cannot launch dialer for number: $cleanedPhone')),
          );
        }
      }
    } catch (e) {
      if (context.mounted) {
        ScaffoldMessenger.of(context).showSnackBar(
          SnackBar(content: Text('Error opening dialer: $e')),
        );
      }
    }
  }

  Future<void> _handleCancel(BuildContext context, WidgetRef ref, PurchaseOrder po) async {
    final confirmed = await showDialog<bool>(
      context: context,
      builder: (dialogCtx) => AlertDialog(
        title: const Row(
          children: [
            Icon(Icons.warning_amber_rounded, color: AppColors.error, size: 24),
            SizedBox(width: AppSpacing.xs),
            Text('Cancel Purchase Order'),
          ],
        ),
        content: Text(
          'Are you sure you want to cancel Purchase Order #${po.purchaseOrderNumber}?\n\n'
          'Total: ${po.formattedTotal}\n'
          'Vendor: ${po.vendorName ?? 'Vendor'}\n\n'
          'This action cannot be undone.',
          style: AppTypography.bodyMd,
        ),
        actions: [
          TextButton(
            onPressed: () => Navigator.of(dialogCtx).pop(false),
            child: const Text('Keep PO'),
          ),
          FilledButton(
            style: FilledButton.styleFrom(
              backgroundColor: AppColors.error,
              foregroundColor: Colors.white,
            ),
            onPressed: () => Navigator.of(dialogCtx).pop(true),
            child: const Text('Cancel PO'),
          ),
        ],
      ),
    );

    if (confirmed == true && context.mounted) {
      try {
        await ref.read(purchaseOrdersProvider.notifier).cancelOrder(po.id);
        if (context.mounted) {
          Navigator.of(context).pop();
          ScaffoldMessenger.of(context).showSnackBar(
            SnackBar(
              backgroundColor: AppColors.error,
              content: Text('Purchase Order #${po.purchaseOrderNumber} has been cancelled.'),
            ),
          );
        }
      } catch (e) {
        if (context.mounted) {
          ScaffoldMessenger.of(context).showSnackBar(
            SnackBar(
              backgroundColor: AppColors.error,
              content: Text('Failed to cancel purchase order: $e'),
            ),
          );
        }
      }
    }
  }

  Future<void> _handleMarkOrdered(BuildContext context, WidgetRef ref, PurchaseOrder po) async {
    try {
      await ref
          .read(purchaseOrdersProvider.notifier)
          .updateStatus(po.id, PurchaseOrderStatus.ordered);
      if (context.mounted) {
        ScaffoldMessenger.of(context).showSnackBar(
          SnackBar(
            backgroundColor: Colors.green.shade700,
            content: Text('Purchase Order #${po.purchaseOrderNumber} marked as Ordered.'),
          ),
        );
      }
    } catch (e) {
      if (context.mounted) {
        ScaffoldMessenger.of(context).showSnackBar(
          SnackBar(
            backgroundColor: AppColors.error,
            content: Text('Failed to update status: $e'),
          ),
        );
      }
    }
  }

  Future<void> _handleEdit(BuildContext context, PurchaseOrder po) async {
    Navigator.of(context).pop();
    await showDialog(
      context: context,
      builder: (_) => PurchaseOrderFormDialog(order: po),
    );
  }

  Future<void> _handleReceive(BuildContext context, PurchaseOrder po) async {
    await showDialog(
      context: context,
      builder: (_) => ReceivePurchaseOrderDialog(order: po),
    );
  }

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    // Keep active PO reactive to status changes
    final allOrders = ref.watch(purchaseOrdersProvider).value ?? [];
    final activeOrder = allOrders.firstWhere(
      (o) => o.id == order.id,
      orElse: () => order,
    );

    final isDesktop = MediaQuery.sizeOf(context).width > 768;
    final dateFormat = DateFormat('MMM d, yyyy');

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
          maxWidth: isDesktop ? 800 : 540,
          maxHeight: MediaQuery.sizeOf(context).height * 0.92,
        ),
        child: Column(
          mainAxisSize: MainAxisSize.min,
          crossAxisAlignment: CrossAxisAlignment.stretch,
          children: [
            _buildDialogHeader(context, activeOrder),
            const Divider(height: 1, color: AppColors.outlineVariant),
            Flexible(
              child: SingleChildScrollView(
                padding: const EdgeInsets.all(AppSpacing.lg),
                child: Column(
                  crossAxisAlignment: CrossAxisAlignment.start,
                  children: [
                    // Top Overview Card
                    _buildOverviewCard(context, activeOrder, dateFormat),
                    const SizedBox(height: AppSpacing.md),

                    // Products Line Items Table
                    _buildLineItemsSection(activeOrder),
                    const SizedBox(height: AppSpacing.md),

                    // Received Batches & Expiry Dates Section
                    _buildReceivedBatchesSection(context, ref, activeOrder, dateFormat),
                    const SizedBox(height: AppSpacing.md),

                    // Notes / Audit info
                    if (activeOrder.notes != null && activeOrder.notes!.isNotEmpty) ...[
                      _buildNotesCard(activeOrder.notes!),
                      const SizedBox(height: AppSpacing.md),
                    ],

                    _buildAuditTrailCard(activeOrder, dateFormat),
                  ],
                ),
              ),
            ),
            const Divider(height: 1, color: AppColors.outlineVariant),
            _buildDialogFooter(context, ref, activeOrder),
          ],
        ),
      ),
    );
  }

  Widget _buildOverviewCard(
    BuildContext context,
    PurchaseOrder po,
    DateFormat dateFormat,
  ) {
    final hasPhone = po.vendorPhone != null && po.vendorPhone!.trim().isNotEmpty;

    return Container(
      padding: const EdgeInsets.all(AppSpacing.md),
      decoration: BoxDecoration(
        color: AppColors.surfaceContainerLow,
        borderRadius: BorderRadius.circular(AppSpacing.radiusLg),
        border: Border.all(color: AppColors.outlineVariant),
      ),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Row(
            mainAxisAlignment: MainAxisAlignment.spaceBetween,
            children: [
              // Vendor info
              Expanded(
                child: Column(
                  crossAxisAlignment: CrossAxisAlignment.start,
                  children: [
                    Text(
                      'SUPPLIER / VENDOR',
                      style: AppTypography.labelCaps.copyWith(
                        color: AppColors.onSurfaceVariant,
                        fontSize: 10,
                      ),
                    ),
                    const SizedBox(height: 2),
                    Text(
                      po.vendorName ?? 'Vendor',
                      style: AppTypography.headlineMd.copyWith(
                        fontWeight: FontWeight.w700,
                      ),
                    ),
                    if (hasPhone) ...[
                      const SizedBox(height: 4),
                      Row(
                        children: [
                          Icon(Icons.phone_outlined, size: 14, color: Colors.blue.shade700),
                          const SizedBox(width: 4),
                          Text(
                            po.vendorPhone!,
                            style: AppTypography.bodySm.copyWith(
                              color: AppColors.onSurfaceVariant,
                            ),
                          ),
                          const SizedBox(width: AppSpacing.sm),
                          InkWell(
                            onTap: () => _handleCallVendor(context, po.vendorPhone),
                            borderRadius: BorderRadius.circular(4),
                            child: Padding(
                              padding: const EdgeInsets.symmetric(horizontal: 6, vertical: 2),
                              child: Row(
                                mainAxisSize: MainAxisSize.min,
                                children: [
                                  Icon(Icons.call, size: 13, color: Colors.green.shade700),
                                  const SizedBox(width: 3),
                                  Text(
                                    'Call Vendor',
                                    style: TextStyle(
                                      fontSize: 11,
                                      fontWeight: FontWeight.w600,
                                      color: Colors.green.shade700,
                                    ),
                                  ),
                                ],
                              ),
                            ),
                          ),
                        ],
                      ),
                    ],
                  ],
                ),
              ),

              // Total Order Amount
              Column(
                crossAxisAlignment: CrossAxisAlignment.end,
                children: [
                  Text(
                    'TOTAL AMOUNT',
                    style: AppTypography.labelCaps.copyWith(
                      color: AppColors.onSurfaceVariant,
                      fontSize: 10,
                    ),
                  ),
                  const SizedBox(height: 2),
                  Text(
                    po.formattedTotal,
                    style: AppTypography.displayLg.copyWith(
                      color: AppColors.primary,
                      fontWeight: FontWeight.w800,
                      fontSize: 22,
                    ),
                  ),
                ],
              ),
            ],
          ),
          const Divider(height: 20),

          // Dates & Progress
          Row(
            children: [
              Expanded(
                child: _buildInfoItem(
                  'Order Date',
                  dateFormat.format(po.orderDate),
                  Icons.calendar_today_outlined,
                ),
              ),
              Expanded(
                child: _buildInfoItem(
                  'Expected Delivery',
                  po.expectedDeliveryDate != null
                      ? dateFormat.format(po.expectedDeliveryDate!)
                      : '—',
                  Icons.event_available_outlined,
                ),
              ),
              Expanded(
                child: _buildInfoItem(
                  'Actual Delivery',
                  po.actualDeliveryDate != null
                      ? dateFormat.format(po.actualDeliveryDate!)
                      : 'Pending',
                  Icons.check_circle_outline,
                ),
              ),
            ],
          ),
        ],
      ),
    );
  }

  Widget _buildInfoItem(String label, String value, IconData icon) {
    return Row(
      children: [
        Icon(icon, size: 16, color: AppColors.onSurfaceVariant),
        const SizedBox(width: 6),
        Column(
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            Text(
              label,
              style: AppTypography.labelCaps.copyWith(
                color: AppColors.onSurfaceVariant,
                fontSize: 10,
              ),
            ),
            Text(
              value,
              style: AppTypography.bodySm.copyWith(
                fontWeight: FontWeight.w600,
              ),
            ),
          ],
        ),
      ],
    );
  }

  Widget _buildLineItemsSection(PurchaseOrder po) {
    return Column(
      crossAxisAlignment: CrossAxisAlignment.start,
      children: [
        Row(
          mainAxisAlignment: MainAxisAlignment.spaceBetween,
          children: [
            Text(
              'ORDERED PRODUCTS (${po.items.length})',
              style: AppTypography.labelCaps.copyWith(
                color: AppColors.primary,
                fontWeight: FontWeight.w700,
              ),
            ),
            Text(
              'Received: ${po.totalReceivedQuantity % 1 == 0 ? po.totalReceivedQuantity.toInt() : po.totalReceivedQuantity} / ${po.totalOrderedQuantity % 1 == 0 ? po.totalOrderedQuantity.toInt() : po.totalOrderedQuantity}',
              style: AppTypography.bodySm.copyWith(
                fontWeight: FontWeight.w600,
                color: po.isReceived ? Colors.green.shade700 : AppColors.onSurfaceVariant,
              ),
            ),
          ],
        ),
        const SizedBox(height: AppSpacing.xs),
        Container(
          decoration: BoxDecoration(
            color: AppColors.surfaceContainerLow,
            borderRadius: BorderRadius.circular(AppSpacing.radiusLg),
            border: Border.all(color: AppColors.outlineVariant),
          ),
          child: ListView.separated(
            shrinkWrap: true,
            physics: const NeverScrollableScrollPhysics(),
            itemCount: po.items.length,
            separatorBuilder: (_, __) =>
                const Divider(height: 1, color: AppColors.outlineVariant),
            itemBuilder: (context, index) {
              final item = po.items[index];
              return Padding(
                padding: const EdgeInsets.all(AppSpacing.sm),
                child: Row(
                  children: [
                    // Item name & SKU
                    Expanded(
                      flex: 4,
                      child: Column(
                        crossAxisAlignment: CrossAxisAlignment.start,
                        children: [
                          Text(
                            item.inventoryName,
                            style: AppTypography.bodyMd.copyWith(
                              fontWeight: FontWeight.w700,
                            ),
                          ),
                          if (item.inventorySku != null)
                            Text(
                              'SKU: ${item.inventorySku}',
                              style: AppTypography.bodySm.copyWith(
                                color: AppColors.onSurfaceVariant,
                                fontSize: 11,
                              ),
                            ),
                        ],
                      ),
                    ),

                    // Ordered Qty
                    Expanded(
                      flex: 2,
                      child: Column(
                        crossAxisAlignment: CrossAxisAlignment.center,
                        children: [
                          Text(
                            'ORDERED',
                            style: AppTypography.labelCaps.copyWith(
                              fontSize: 9,
                              color: AppColors.onSurfaceVariant,
                            ),
                          ),
                          Text(
                            item.formattedQuantity,
                            style: AppTypography.bodySm.copyWith(
                              fontWeight: FontWeight.w600,
                            ),
                          ),
                        ],
                      ),
                    ),

                    // Received Qty
                    Expanded(
                      flex: 2,
                      child: Column(
                        crossAxisAlignment: CrossAxisAlignment.center,
                        children: [
                          Text(
                            'RECEIVED',
                            style: AppTypography.labelCaps.copyWith(
                              fontSize: 9,
                              color: Colors.green.shade700,
                            ),
                          ),
                          Text(
                            item.formattedReceivedQuantity,
                            style: AppTypography.bodySm.copyWith(
                              fontWeight: FontWeight.w700,
                              color: Colors.green.shade700,
                            ),
                          ),
                        ],
                      ),
                    ),

                    // Unit Price
                    Expanded(
                      flex: 2,
                      child: Column(
                        crossAxisAlignment: CrossAxisAlignment.center,
                        children: [
                          Text(
                            'UNIT PRICE',
                            style: AppTypography.labelCaps.copyWith(
                              fontSize: 9,
                              color: AppColors.onSurfaceVariant,
                            ),
                          ),
                          Text(
                            item.formattedUnitPrice,
                            style: AppTypography.bodySm.copyWith(
                              fontWeight: FontWeight.w600,
                            ),
                          ),
                        ],
                      ),
                    ),

                    // Line Total
                    SizedBox(
                      width: 80,
                      child: Column(
                        crossAxisAlignment: CrossAxisAlignment.end,
                        children: [
                          Text(
                            'TOTAL',
                            style: AppTypography.labelCaps.copyWith(
                              fontSize: 9,
                              color: AppColors.onSurfaceVariant,
                            ),
                          ),
                          Text(
                            item.formattedTotalAmount,
                            style: AppTypography.bodySm.copyWith(
                              fontWeight: FontWeight.w700,
                              color: AppColors.onSurface,
                            ),
                          ),
                        ],
                      ),
                    ),
                  ],
                ),
              );
            },
          ),
        ),
      ],
    );
  }

  Widget _buildReceivedBatchesSection(
    BuildContext context,
    WidgetRef ref,
    PurchaseOrder po,
    DateFormat dateFormat,
  ) {
    if (po.totalReceivedQuantity <= 0) {
      return const SizedBox.shrink();
    }

    final batchesAsync = ref.watch(poBatchesProvider(po.id));

    return Column(
      crossAxisAlignment: CrossAxisAlignment.start,
      children: [
        Row(
          mainAxisAlignment: MainAxisAlignment.spaceBetween,
          children: [
            Text(
              'RECEIVED BATCHES & EXPIRY DATES',
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
          padding: const EdgeInsets.all(AppSpacing.sm),
          decoration: BoxDecoration(
            color: AppColors.surfaceContainerLow,
            borderRadius: BorderRadius.circular(AppSpacing.radiusLg),
            border: Border.all(color: AppColors.outlineVariant),
          ),
          child: batchesAsync.when(
            loading: () => const Padding(
              padding: EdgeInsets.all(AppSpacing.sm),
              child: Center(
                child: SizedBox(width: 20, height: 20, child: CircularProgressIndicator(strokeWidth: 2)),
              ),
            ),
            error: (e, _) => Padding(
              padding: const EdgeInsets.all(AppSpacing.sm),
              child: Text('Unable to load batches: $e', style: AppTypography.bodySm.copyWith(color: AppColors.error)),
            ),
            data: (batches) {
              if (batches.isEmpty) {
                return Padding(
                  padding: const EdgeInsets.all(AppSpacing.sm),
                  child: Text(
                    'No individual batch records logged yet.',
                    style: AppTypography.bodySm.copyWith(
                      color: AppColors.onSurfaceVariant,
                      fontStyle: FontStyle.italic,
                    ),
                  ),
                );
              }

              return ListView.separated(
                shrinkWrap: true,
                physics: const NeverScrollableScrollPhysics(),
                itemCount: batches.length,
                separatorBuilder: (_, __) => const Divider(height: 12, color: AppColors.outlineVariant),
                itemBuilder: (context, index) {
                  final b = batches[index];
                  return Padding(
                    padding: const EdgeInsets.symmetric(vertical: 4, horizontal: 4),
                    child: Row(
                      crossAxisAlignment: CrossAxisAlignment.start,
                      children: [
                        Container(
                          padding: const EdgeInsets.all(6),
                          decoration: BoxDecoration(
                            color: AppColors.primary.withValues(alpha: 0.1),
                            borderRadius: BorderRadius.circular(AppSpacing.radiusSm),
                          ),
                          child: const Icon(Icons.qr_code_2_outlined, size: 20, color: AppColors.primary),
                        ),
                        const SizedBox(width: AppSpacing.sm),
                        Expanded(
                          child: Column(
                            crossAxisAlignment: CrossAxisAlignment.start,
                            children: [
                              Row(
                                children: [
                                  Text(
                                    b.batchNumber,
                                    style: AppTypography.bodyMd.copyWith(
                                      fontWeight: FontWeight.w700,
                                      color: AppColors.onSurface,
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
                                '${b.inventoryName ?? 'Product'} • Received: ${b.formattedReceivedQuantity} • Left: ${b.formattedRemainingQuantity}',
                                style: AppTypography.bodySm.copyWith(
                                  color: AppColors.onSurfaceVariant,
                                  fontSize: 12,
                                ),
                              ),
                              Text(
                                'Received: ${b.formattedReceivedDate} • Expiry: ${b.formattedExpiryDate}',
                                style: AppTypography.bodySm.copyWith(
                                  color: AppColors.onSurfaceVariant,
                                  fontSize: 11,
                                ),
                              ),
                            ],
                          ),
                        ),
                        Text(
                          b.formattedUnitPrice,
                          style: AppTypography.bodySm.copyWith(
                            fontWeight: FontWeight.w700,
                            color: AppColors.primary,
                          ),
                        ),
                      ],
                    ),
                  );
                },
              );
            },
          ),
        ),
      ],
    );
  }

  Widget _buildNotesCard(String notes) {
    return Column(
      crossAxisAlignment: CrossAxisAlignment.start,
      children: [
        Text(
          'NOTES & SPECIAL INSTRUCTIONS',
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
            notes,
            style: AppTypography.bodyMd.copyWith(
              fontStyle: FontStyle.italic,
            ),
          ),
        ),
      ],
    );
  }

  Widget _buildAuditTrailCard(PurchaseOrder po, DateFormat dateFormat) {
    return Container(
      padding: const EdgeInsets.all(AppSpacing.sm),
      decoration: BoxDecoration(
        color: AppColors.surfaceContainerLow.withValues(alpha: 0.5),
        borderRadius: BorderRadius.circular(AppSpacing.radiusMd),
      ),
      child: Row(
        mainAxisAlignment: MainAxisAlignment.spaceBetween,
        children: [
          Text(
            'Created By: ${po.createdByName ?? 'Staff/Admin'}',
            style: AppTypography.bodySm.copyWith(
              color: AppColors.onSurfaceVariant,
              fontSize: 11,
            ),
          ),
          if (po.createdAt != null)
            Text(
              'Created: ${dateFormat.format(po.createdAt!)}',
              style: AppTypography.bodySm.copyWith(
                color: AppColors.onSurfaceVariant,
                fontSize: 11,
              ),
            ),
        ],
      ),
    );
  }

  Widget _buildDialogHeader(BuildContext context, PurchaseOrder po) {
    return Padding(
      padding: const EdgeInsets.symmetric(
        horizontal: AppSpacing.lg,
        vertical: AppSpacing.md,
      ),
      child: Row(
        mainAxisAlignment: MainAxisAlignment.spaceBetween,
        children: [
          Row(
            children: [
              Container(
                padding: const EdgeInsets.all(AppSpacing.xs),
                decoration: BoxDecoration(
                  color: po.status.color.withValues(alpha: 0.15),
                  borderRadius: BorderRadius.circular(AppSpacing.radiusMd),
                ),
                child: Icon(
                  po.status.icon,
                  color: po.status.color,
                  size: 20,
                ),
              ),
              const SizedBox(width: AppSpacing.sm),
              Text(
                'PO #${po.purchaseOrderNumber}',
                style: AppTypography.headlineMd.copyWith(
                  fontWeight: FontWeight.w700,
                  fontSize: 18,
                ),
              ),
              const SizedBox(width: AppSpacing.sm),
              Container(
                padding: const EdgeInsets.symmetric(horizontal: 8, vertical: 3),
                decoration: BoxDecoration(
                  color: po.status.color.withValues(alpha: 0.15),
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
          IconButton(
            icon: const Icon(Icons.close),
            onPressed: () => Navigator.of(context).pop(),
          ),
        ],
      ),
    );
  }

  Widget _buildDialogFooter(BuildContext context, WidgetRef ref, PurchaseOrder po) {
    return Padding(
      padding: const EdgeInsets.all(AppSpacing.md),
      child: Row(
        mainAxisAlignment: MainAxisAlignment.spaceBetween,
        children: [
          // Cancel PO button (if draft or ordered)
          if (po.canCancel)
            OutlinedButton.icon(
              onPressed: () => _handleCancel(context, ref, po),
              icon: const Icon(Icons.cancel_outlined, size: 18),
              label: const Text('Cancel PO'),
              style: OutlinedButton.styleFrom(
                foregroundColor: AppColors.error,
                side: const BorderSide(color: AppColors.error),
              ),
            )
          else
            const SizedBox.shrink(),

          Row(
            children: [
              TextButton(
                onPressed: () => Navigator.of(context).pop(),
                child: const Text('Close'),
              ),
              if (po.canEdit) ...[
                const SizedBox(width: AppSpacing.sm),
                OutlinedButton.icon(
                  onPressed: () => _handleEdit(context, po),
                  icon: const Icon(Icons.edit_outlined, size: 18),
                  label: const Text('Edit PO'),
                ),
              ],
              if (po.isDraft) ...[
                const SizedBox(width: AppSpacing.sm),
                FilledButton.icon(
                  onPressed: () => _handleMarkOrdered(context, ref, po),
                  icon: const Icon(Icons.send_outlined, size: 18),
                  label: const Text('Mark as Ordered'),
                  style: FilledButton.styleFrom(
                    backgroundColor: const Color(0xFF1976D2),
                    foregroundColor: Colors.white,
                  ),
                ),
              ],
              if (po.canReceive) ...[
                const SizedBox(width: AppSpacing.sm),
                FilledButton.icon(
                  onPressed: () => _handleReceive(context, po),
                  icon: const Icon(Icons.inventory, size: 18),
                  label: const Text('Receive Items'),
                  style: FilledButton.styleFrom(
                    backgroundColor: Colors.green.shade700,
                    foregroundColor: Colors.white,
                  ),
                ),
              ],
            ],
          ),
        ],
      ),
    );
  }
}
