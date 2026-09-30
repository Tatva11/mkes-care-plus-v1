import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:intl/intl.dart';

import '../../../core/theme/app_colors.dart';
import '../../../core/theme/app_spacing.dart';
import '../../../core/theme/app_typography.dart';
import '../../auth/providers/auth_provider.dart';
import '../../inventory/providers/purchase_order_provider.dart';
import '../../inventory/widgets/purchase_order_details_dialog.dart';
import '../models/vendor.dart';
import '../providers/vendor_provider.dart';
import 'vendor_form_dialog.dart';

/// Modal dialog displaying comprehensive details of a [Vendor].
/// Allows Admin to edit, toggle status, and delete. Staff has read-only access.
class VendorDetailsDialog extends ConsumerWidget {
  const VendorDetailsDialog({
    super.key,
    required this.vendor,
  });

  final Vendor vendor;

  Future<void> _handleEdit(BuildContext context, Vendor activeVendor) async {
    Navigator.of(context).pop();
    await showDialog<Vendor>(
      context: context,
      builder: (_) => VendorFormDialog(vendor: activeVendor),
    );
  }

  Future<void> _handleDelete(
    BuildContext context,
    WidgetRef ref,
    Vendor activeVendor,
  ) async {
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
          'Are you sure you want to permanently delete vendor "${activeVendor.name}"?\n\n'
          'Contact: ${activeVendor.contactPerson ?? 'N/A'}\n'
          'Products: ${activeVendor.productsDisplay}\n\n'
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
            child: const Text('Delete Vendor'),
          ),
        ],
      ),
    );

    if (confirmed == true && context.mounted) {
      try {
        await ref.read(vendorsProvider.notifier).deleteVendor(activeVendor.id);
        if (context.mounted) {
          Navigator.of(context).pop();
          ScaffoldMessenger.of(context).showSnackBar(
            SnackBar(
              backgroundColor: AppColors.error,
              content: Text('Vendor "${activeVendor.name}" has been deleted.'),
            ),
          );
        }
      } catch (e) {
        if (context.mounted) {
          ScaffoldMessenger.of(context).showSnackBar(
            SnackBar(
              backgroundColor: AppColors.error,
              content: Text('Failed to delete vendor: $e'),
            ),
          );
        }
      }
    }
  }

  Future<void> _handleToggleStatus(
    BuildContext context,
    WidgetRef ref,
    Vendor activeVendor,
  ) async {
    try {
      final newStatus = !activeVendor.isActive;
      await ref
          .read(vendorsProvider.notifier)
          .toggleStatus(activeVendor.id, newStatus);
      if (context.mounted) {
        ScaffoldMessenger.of(context).showSnackBar(
          SnackBar(
            backgroundColor: newStatus ? Colors.green.shade700 : Colors.grey.shade800,
            content: Text(
              'Vendor "${activeVendor.name}" marked as ${newStatus ? 'Active' : 'Inactive'}.',
            ),
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

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    // Watch current vendor state in case it updates live
    final vendorsAsync = ref.watch(vendorsProvider);
    final activeVendor = vendorsAsync.value?.firstWhere(
          (v) => v.id == vendor.id,
          orElse: () => vendor,
        ) ??
        vendor;

    final role = ref.watch(currentUserRoleProvider).valueOrNull;
    final canManage = role == 'admin' || role == 'staff';
    final isDesktop = MediaQuery.sizeOf(context).width > 600;

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
            Container(
              padding: const EdgeInsets.symmetric(
                horizontal: AppSpacing.lg,
                vertical: AppSpacing.md,
              ),
              decoration: BoxDecoration(
                color: AppColors.primary.withValues(alpha: 0.08),
                borderRadius: const BorderRadius.only(
                  topLeft: Radius.circular(AppSpacing.radiusXl),
                  topRight: Radius.circular(AppSpacing.radiusXl),
                ),
                border: const Border(
                  bottom: BorderSide(color: AppColors.outlineVariant),
                ),
              ),
              child: Row(
                children: [
                  Container(
                    padding: const EdgeInsets.all(AppSpacing.xs),
                    decoration: BoxDecoration(
                      color: AppColors.primary.withValues(alpha: 0.15),
                      borderRadius: BorderRadius.circular(AppSpacing.radiusMd),
                    ),
                    child: const Icon(
                      Icons.local_shipping_outlined,
                      color: AppColors.primary,
                      size: 24,
                    ),
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
                                activeVendor.name,
                                style: AppTypography.headlineMd.copyWith(
                                  fontWeight: FontWeight.w700,
                                ),
                                overflow: TextOverflow.ellipsis,
                              ),
                            ),
                            const SizedBox(width: AppSpacing.xs),
                            Container(
                              padding: const EdgeInsets.symmetric(
                                horizontal: 6,
                                vertical: 2,
                              ),
                              decoration: BoxDecoration(
                                color: activeVendor.isActive
                                    ? Colors.green.withValues(alpha: 0.15)
                                    : Colors.grey.withValues(alpha: 0.2),
                                borderRadius: BorderRadius.circular(4),
                              ),
                              child: Text(
                                activeVendor.statusLabel,
                                style: TextStyle(
                                  fontSize: 10,
                                  fontWeight: FontWeight.w700,
                                  color: activeVendor.isActive
                                      ? Colors.green.shade800
                                      : Colors.grey.shade700,
                                ),
                              ),
                            ),
                          ],
                        ),
                        if (activeVendor.contactPerson != null &&
                            activeVendor.contactPerson!.isNotEmpty) ...[
                          const SizedBox(height: 2),
                          Text(
                            'Contact: ${activeVendor.contactPerson}',
                            style: AppTypography.bodySm.copyWith(
                              color: AppColors.onSurfaceVariant,
                            ),
                          ),
                        ],
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

            // Details Content
            Flexible(
              child: SingleChildScrollView(
                padding: const EdgeInsets.all(AppSpacing.lg),
                child: Column(
                  crossAxisAlignment: CrossAxisAlignment.start,
                  children: [
                    // Card 1: Contact Information
                    _buildSectionHeader('CONTACT INFORMATION', Icons.contacts_outlined),
                    const SizedBox(height: AppSpacing.xs),
                    Container(
                      padding: const EdgeInsets.all(AppSpacing.md),
                      decoration: BoxDecoration(
                        color: AppColors.surfaceContainerLow,
                        borderRadius: BorderRadius.circular(AppSpacing.radiusLg),
                        border: Border.all(color: AppColors.outlineVariant),
                      ),
                      child: Column(
                        children: [
                          _buildDetailRow(
                            icon: Icons.person_outline,
                            label: 'Contact Person',
                            value: activeVendor.contactPerson ?? '—',
                          ),
                          const Divider(height: 16),
                          _buildDetailRow(
                            icon: Icons.phone_outlined,
                            label: 'Phone Number',
                            value: activeVendor.phone ?? '—',
                          ),
                          const Divider(height: 16),
                          _buildDetailRow(
                            icon: Icons.email_outlined,
                            label: 'Email Address',
                            value: activeVendor.email ?? '—',
                          ),
                          const Divider(height: 16),
                          _buildDetailRow(
                            icon: Icons.location_on_outlined,
                            label: 'Address / Location',
                            value: activeVendor.address ?? '—',
                          ),
                        ],
                      ),
                    ),
                    const SizedBox(height: AppSpacing.lg),

                    // Card 2: Supply & Deliveries
                    _buildSectionHeader('SUPPLY & DELIVERY OPERATIONS', Icons.inventory_outlined),
                    const SizedBox(height: AppSpacing.xs),
                    Container(
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
                            children: [
                              Expanded(
                                child: _buildStatItem(
                                  label: 'Last Order Date',
                                  value: activeVendor.formattedLastOrder,
                                  icon: Icons.calendar_today_outlined,
                                ),
                              ),
                              const SizedBox(width: AppSpacing.sm),
                              Expanded(
                                child: _buildStatItem(
                                  label: 'Last Delivery Date',
                                  value: activeVendor.formattedLastDelivery,
                                  icon: Icons.local_shipping_outlined,
                                ),
                              ),
                            ],
                          ),
                          const Divider(height: 16),
                          Row(
                            children: [
                              Expanded(
                                child: _buildStatItem(
                                  label: 'Last Quantity Supplied',
                                  value: activeVendor.formattedLastQuantity,
                                  icon: Icons.inventory_2_outlined,
                                ),
                              ),
                              const SizedBox(width: AppSpacing.sm),
                              Expanded(
                                child: _buildStatItem(
                                  label: 'Total Payment',
                                  value: activeVendor.formattedLastTotalAmount,
                                  icon: Icons.currency_rupee,
                                ),
                              ),
                              const SizedBox(width: AppSpacing.sm),
                              Expanded(
                                child: _buildStatItem(
                                  label: 'Price Per Piece',
                                  value: activeVendor.formattedPricePerPiece,
                                  icon: Icons.calculate_outlined,
                                  highlight: true,
                                ),
                              ),
                            ],
                          ),
                          const Divider(height: 16),
                          Text(
                            'Products Supplied',
                            style: AppTypography.labelCaps.copyWith(
                              color: AppColors.onSurfaceVariant,
                              fontSize: 10,
                            ),
                          ),
                          const SizedBox(height: 6),
                          if (activeVendor.productsSupplied.isEmpty)
                            Text(
                              'None specified',
                              style: AppTypography.bodySm.copyWith(
                                color: AppColors.onSurfaceVariant,
                                fontStyle: FontStyle.italic,
                              ),
                            )
                          else
                            Wrap(
                              spacing: 6,
                              runSpacing: 6,
                              children: activeVendor.productsSupplied.map((product) {
                                return Container(
                                  padding: const EdgeInsets.symmetric(
                                    horizontal: 8,
                                    vertical: 3,
                                  ),
                                  decoration: BoxDecoration(
                                    color: AppColors.primaryContainer.withValues(alpha: 0.25),
                                    borderRadius: BorderRadius.circular(AppSpacing.radiusSm),
                                    border: Border.all(
                                      color: AppColors.primary.withValues(alpha: 0.3),
                                    ),
                                  ),
                                  child: Text(
                                    product,
                                    style: const TextStyle(
                                      fontSize: 11,
                                      fontWeight: FontWeight.w600,
                                      color: AppColors.primary,
                                    ),
                                  ),
                                );
                              }).toList(),
                            ),
                        ],
                      ),
                    ),

                    // Card 3: Remarks (if present)
                    if (activeVendor.remarks != null &&
                        activeVendor.remarks!.isNotEmpty) ...[
                      const SizedBox(height: AppSpacing.lg),
                      _buildSectionHeader('REMARKS & AGREEMENTS', Icons.notes_outlined),
                      const SizedBox(height: AppSpacing.xs),
                      Container(
                        width: double.infinity,
                        padding: const EdgeInsets.all(AppSpacing.md),
                        decoration: BoxDecoration(
                          color: AppColors.surfaceContainerLow,
                          borderRadius: BorderRadius.circular(AppSpacing.radiusLg),
                          border: Border.all(color: AppColors.outlineVariant),
                        ),
                        child: Text(
                          activeVendor.remarks!,
                          style: AppTypography.bodyMd.copyWith(
                            fontStyle: FontStyle.italic,
                          ),
                        ),
                      ),
                    ],

                    // Card 4: Purchase Order History
                    const SizedBox(height: AppSpacing.lg),
                    _buildPurchaseOrderHistorySection(context, ref, activeVendor),
                  ],
                ),
              ),
            ),
            const Divider(height: 1, color: AppColors.outlineVariant),

            // Footer Actions
            Padding(
              padding: const EdgeInsets.symmetric(
                horizontal: AppSpacing.md,
                vertical: AppSpacing.sm,
              ),
              child: Wrap(
                alignment: WrapAlignment.spaceBetween,
                crossAxisAlignment: WrapCrossAlignment.center,
                spacing: AppSpacing.sm,
                runSpacing: AppSpacing.xs,
                children: [
                  // Delete & Deactivate (Admin or Staff)
                  if (canManage)
                    Row(
                      mainAxisSize: MainAxisSize.min,
                      children: [
                        IconButton(
                          icon: const Icon(Icons.delete_outline, color: AppColors.error),
                          tooltip: 'Delete Vendor',
                          onPressed: () => _handleDelete(context, ref, activeVendor),
                        ),
                        TextButton.icon(
                          icon: Icon(
                            activeVendor.isActive
                                ? Icons.pause_circle_outline
                                : Icons.play_circle_outline,
                            size: 16,
                          ),
                          label: Text(activeVendor.isActive ? 'Deactivate' : 'Activate'),
                          onPressed: () => _handleToggleStatus(context, ref, activeVendor),
                        ),
                      ],
                    ),
                  Row(
                    mainAxisSize: MainAxisSize.min,
                    children: [
                      TextButton(
                        onPressed: () => Navigator.of(context).pop(),
                        child: const Text('Close'),
                      ),
                      if (canManage) ...[
                        const SizedBox(width: AppSpacing.sm),
                        FilledButton.icon(
                          icon: const Icon(Icons.edit_outlined, size: 16),
                          label: const Text('Edit Vendor'),
                          style: FilledButton.styleFrom(
                            backgroundColor: AppColors.primary,
                            foregroundColor: Colors.white,
                          ),
                          onPressed: () => _handleEdit(context, activeVendor),
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

  Widget _buildSectionHeader(String title, IconData icon) {
    return Row(
      children: [
        Icon(icon, size: 14, color: AppColors.onSurfaceVariant),
        const SizedBox(width: 4),
        Text(
          title,
          style: AppTypography.labelCaps.copyWith(
            color: AppColors.onSurfaceVariant,
            fontSize: 10,
          ),
        ),
      ],
    );
  }

  Widget _buildDetailRow({
    required IconData icon,
    required String label,
    required String value,
  }) {
    return Row(
      crossAxisAlignment: CrossAxisAlignment.start,
      children: [
        Icon(icon, size: 16, color: AppColors.onSurfaceVariant),
        const SizedBox(width: AppSpacing.sm),
        SizedBox(
          width: 110,
          child: Text(
            label,
            style: AppTypography.bodySm.copyWith(
              color: AppColors.onSurfaceVariant,
            ),
          ),
        ),
        Expanded(
          child: Text(
            value,
            style: AppTypography.bodySm.copyWith(
              fontWeight: FontWeight.w600,
            ),
          ),
        ),
      ],
    );
  }

  Widget _buildStatItem({
    required String label,
    required String value,
    required IconData icon,
    bool highlight = false,
  }) {
    return Column(
      crossAxisAlignment: CrossAxisAlignment.start,
      children: [
        Row(
          children: [
            Icon(icon, size: 12, color: highlight ? AppColors.primary : AppColors.onSurfaceVariant),
            const SizedBox(width: 4),
            Expanded(
              child: Text(
                label,
                overflow: TextOverflow.ellipsis,
                maxLines: 1,
                style: AppTypography.labelCaps.copyWith(
                  color: highlight ? AppColors.primary : AppColors.onSurfaceVariant,
                  fontSize: 9,
                ),
              ),
            ),
          ],
        ),
        const SizedBox(height: 2),
        FittedBox(
          fit: BoxFit.scaleDown,
          alignment: Alignment.centerLeft,
          child: Text(
            value,
            style: AppTypography.bodyMd.copyWith(
              fontWeight: FontWeight.w700,
              color: highlight ? AppColors.primary : AppColors.onSurface,
            ),
          ),
        ),
      ],
    );
  }

  Widget _buildPurchaseOrderHistorySection(
    BuildContext context,
    WidgetRef ref,
    Vendor activeVendor,
  ) {
    final allPOs = ref.watch(purchaseOrdersProvider).value ?? [];
    final vendorPOs =
        allPOs.where((po) => po.vendorId == activeVendor.id).toList();
    final dateFormat = DateFormat('dd MMM yyyy');

    return Column(
      crossAxisAlignment: CrossAxisAlignment.start,
      children: [
        _buildSectionHeader(
            'PURCHASE ORDER HISTORY', Icons.receipt_long_outlined),
        const SizedBox(height: AppSpacing.xs),
        Container(
          width: double.infinity,
          padding: const EdgeInsets.all(AppSpacing.md),
          decoration: BoxDecoration(
            color: AppColors.surfaceContainerLow,
            borderRadius: BorderRadius.circular(AppSpacing.radiusLg),
            border: Border.all(color: AppColors.outlineVariant),
          ),
          child: vendorPOs.isEmpty
              ? Text(
                  'No purchase orders recorded for this vendor yet.',
                  style: AppTypography.bodySm.copyWith(
                    color: AppColors.onSurfaceVariant,
                    fontStyle: FontStyle.italic,
                  ),
                )
              : ListView.separated(
                  shrinkWrap: true,
                  physics: const NeverScrollableScrollPhysics(),
                  itemCount: vendorPOs.length,
                  separatorBuilder: (_, __) => const Divider(height: 12),
                  itemBuilder: (context, index) {
                    final po = vendorPOs[index];
                    return InkWell(
                      onTap: () {
                        showDialog(
                          context: context,
                          builder: (_) =>
                              PurchaseOrderDetailsDialog(order: po),
                        );
                      },
                      borderRadius:
                          BorderRadius.circular(AppSpacing.radiusMd),
                      child: Padding(
                        padding: const EdgeInsets.symmetric(vertical: 4),
                        child: Row(
                          mainAxisAlignment:
                              MainAxisAlignment.spaceBetween,
                          children: [
                            Column(
                              crossAxisAlignment: CrossAxisAlignment.start,
                              children: [
                                Row(
                                  children: [
                                    Text(
                                      po.purchaseOrderNumber,
                                      style: AppTypography.bodyMd.copyWith(
                                        fontWeight: FontWeight.w700,
                                      ),
                                    ),
                                    const SizedBox(width: AppSpacing.xs),
                                    Container(
                                      padding: const EdgeInsets.symmetric(
                                          horizontal: 6, vertical: 2),
                                      decoration: BoxDecoration(
                                        color: po.status.color
                                            .withValues(alpha: 0.12),
                                        borderRadius:
                                            BorderRadius.circular(4),
                                        border: Border.all(
                                            color: po.status.color),
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
                                  'Ordered: ${dateFormat.format(po.orderDate)}${po.actualDeliveryDate != null ? ' • Delivered: ${dateFormat.format(po.actualDeliveryDate!)}' : ''}',
                                  style: AppTypography.bodySm.copyWith(
                                    color: AppColors.onSurfaceVariant,
                                    fontSize: 11,
                                  ),
                                ),
                              ],
                            ),
                            Row(
                              children: [
                                Text(
                                  po.formattedTotal,
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
