import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';

import '../../../core/theme/app_colors.dart';
import '../../../core/theme/app_spacing.dart';
import '../../../core/theme/app_typography.dart';
import '../../auth/providers/auth_provider.dart';
import '../models/vendor.dart';
import '../providers/vendor_provider.dart';
import '../widgets/vendor_details_dialog.dart';
import '../widgets/vendor_form_dialog.dart';

/// Full screen for Vendor Management with clean scaffold and back navigation for Admin and Staff.
class VendorManagementScreen extends ConsumerWidget {
  const VendorManagementScreen({super.key});

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    return Scaffold(
      backgroundColor: AppColors.surfaceContainerLowest,
      appBar: AppBar(
        title: const Text('Vendor Directory'),
        backgroundColor: AppColors.surface,
        foregroundColor: AppColors.onSurface,
        elevation: 0,
        leading: Navigator.of(context).canPop()
            ? BackButton(onPressed: () => Navigator.of(context).pop())
            : null,
      ),
      body: const VendorManagementContent(),
    );
  }
}

/// The inner content of the Vendor Management view.
/// Can be rendered inside [VendorManagementScreen] or embedded inside tabbed operations.
class VendorManagementContent extends ConsumerStatefulWidget {
  const VendorManagementContent({super.key});

  @override
  ConsumerState<VendorManagementContent> createState() =>
      _VendorManagementContentState();
}

class _VendorManagementContentState
    extends ConsumerState<VendorManagementContent> {
  final _searchController = TextEditingController();

  @override
  void dispose() {
    _searchController.dispose();
    super.dispose();
  }

  Future<void> _openVendorDialog({Vendor? vendor}) async {
    await showDialog<Vendor>(
      context: context,
      builder: (_) => VendorFormDialog(vendor: vendor),
    );
  }

  Future<void> _openDetailsDialog(Vendor vendor) async {
    await showDialog(
      context: context,
      builder: (_) => VendorDetailsDialog(vendor: vendor),
    );
  }

  @override
  Widget build(BuildContext context) {
    final role = ref.watch(currentUserRoleProvider).valueOrNull;
    final canManage = role == 'admin' || role == 'staff';

    final vendorsAsync = ref.watch(vendorsProvider);
    final filteredVendors = ref.watch(filteredVendorsProvider);
    final selectedStatus = ref.watch(vendorStatusFilterProvider);
    final totalCount = ref.watch(totalVendorsCountProvider);
    final activeCount = ref.watch(activeVendorsCountProvider);

    final isDesktop = MediaQuery.sizeOf(context).width > 768;

    return RefreshIndicator(
      onRefresh: () => ref.read(vendorsProvider.notifier).refresh(),
      child: ListView(
        padding: const EdgeInsets.all(AppSpacing.md),
        children: [
          // 1. Header Toolbar
          Row(
            children: [
              Expanded(
                child: Column(
                  crossAxisAlignment: CrossAxisAlignment.start,
                  children: [
                    Text(
                      'Vendor Directory',
                      style: AppTypography.headlineMd.copyWith(
                        fontWeight: FontWeight.w700,
                      ),
                    ),
                    const SizedBox(height: 2),
                    Text(
                      '$totalCount total vendors • $activeCount active',
                      style: AppTypography.bodySm.copyWith(
                        color: AppColors.onSurfaceVariant,
                      ),
                    ),
                  ],
                ),
              ),
              if (canManage) ...[
                FilledButton.icon(
                  onPressed: () => _openVendorDialog(),
                  icon: const Icon(Icons.add, size: 18),
                  label: const Text('Add Vendor'),
                  style: FilledButton.styleFrom(
                    backgroundColor: AppColors.primary,
                    foregroundColor: Colors.white,
                    padding: const EdgeInsets.symmetric(
                      horizontal: AppSpacing.md,
                      vertical: AppSpacing.sm,
                    ),
                  ),
                ),
              ],
            ],
          ),
          const SizedBox(height: AppSpacing.md),

          // 2. Search & Filter Bar
          Card(
            elevation: 0,
            color: AppColors.surface,
            shape: RoundedRectangleBorder(
              borderRadius: BorderRadius.circular(AppSpacing.radiusLg),
              side: const BorderSide(color: AppColors.outlineVariant),
            ),
            child: Padding(
              padding: const EdgeInsets.all(AppSpacing.sm),
              child: Column(
                children: [
                  // Search Input
                  TextField(
                    controller: _searchController,
                    decoration: InputDecoration(
                      hintText: 'Search by vendor name, contact person, phone, or email...',
                      prefixIcon: const Icon(Icons.search, size: 20),
                      suffixIcon: _searchController.text.isNotEmpty
                          ? IconButton(
                              icon: const Icon(Icons.clear, size: 18),
                              onPressed: () {
                                _searchController.clear();
                                ref.read(vendorSearchQueryProvider.notifier).state = '';
                              },
                            )
                          : null,
                      border: OutlineInputBorder(
                        borderRadius: BorderRadius.circular(AppSpacing.radiusMd),
                        borderSide: BorderSide.none,
                      ),
                      filled: true,
                      fillColor: AppColors.surfaceContainerLow,
                      contentPadding: const EdgeInsets.symmetric(
                        horizontal: AppSpacing.sm,
                        vertical: AppSpacing.xs,
                      ),
                    ),
                    onChanged: (val) {
                      ref.read(vendorSearchQueryProvider.notifier).state = val;
                    },
                  ),
                  const SizedBox(height: AppSpacing.xs),

                  // Filter Chips
                  SingleChildScrollView(
                    scrollDirection: Axis.horizontal,
                    child: Row(
                      children: [
                        Text(
                          'Status: ',
                          style: AppTypography.bodySm.copyWith(
                            color: AppColors.onSurfaceVariant,
                            fontWeight: FontWeight.w600,
                          ),
                        ),
                        const SizedBox(width: AppSpacing.xs),
                        _buildFilterChip('All', 'All', selectedStatus),
                        const SizedBox(width: 6),
                        _buildFilterChip('Active', 'Active', selectedStatus),
                        const SizedBox(width: 6),
                        _buildFilterChip('Inactive', 'Inactive', selectedStatus),
                      ],
                    ),
                  ),
                ],
              ),
            ),
          ),
          const SizedBox(height: AppSpacing.md),

          // 3. Vendor Data Content
          vendorsAsync.when(
            loading: () => const Padding(
              padding: EdgeInsets.symmetric(vertical: 48),
              child: Center(
                child: CircularProgressIndicator(),
              ),
            ),
            error: (err, _) => Container(
              padding: const EdgeInsets.all(AppSpacing.lg),
              decoration: BoxDecoration(
                color: AppColors.errorContainer,
                borderRadius: BorderRadius.circular(AppSpacing.radiusLg),
                border: Border.all(color: AppColors.error),
              ),
              child: Column(
                children: [
                  const Icon(Icons.error_outline, size: 36, color: AppColors.error),
                  const SizedBox(height: AppSpacing.sm),
                  Text(
                    'Failed to load vendors',
                    style: AppTypography.headlineMd.copyWith(color: AppColors.error),
                  ),
                  const SizedBox(height: 4),
                  Text(
                    err.toString(),
                    style: AppTypography.bodySm.copyWith(color: AppColors.onErrorContainer),
                    textAlign: TextAlign.center,
                  ),
                  const SizedBox(height: AppSpacing.md),
                  OutlinedButton.icon(
                    onPressed: () => ref.read(vendorsProvider.notifier).refresh(),
                    icon: const Icon(Icons.refresh, size: 16),
                    label: const Text('Try Again'),
                  ),
                ],
              ),
            ),
            data: (allVendors) {
              if (allVendors.isEmpty) {
                return _buildEmptyState(
                  canManage: canManage,
                  hasFilters: false,
                );
              }

              if (filteredVendors.isEmpty) {
                return _buildEmptyState(
                  canManage: canManage,
                  hasFilters: true,
                );
              }

              if (isDesktop) {
                return GridView.builder(
                  shrinkWrap: true,
                  physics: const NeverScrollableScrollPhysics(),
                  gridDelegate: const SliverGridDelegateWithFixedCrossAxisCount(
                    crossAxisCount: 2,
                    mainAxisExtent: 210,
                    crossAxisSpacing: AppSpacing.md,
                    mainAxisSpacing: AppSpacing.md,
                  ),
                  itemCount: filteredVendors.length,
                  itemBuilder: (context, index) {
                    final vendor = filteredVendors[index];
                    return _buildVendorCard(vendor, canManage);
                  },
                );
              }

              return ListView.separated(
                shrinkWrap: true,
                physics: const NeverScrollableScrollPhysics(),
                itemCount: filteredVendors.length,
                separatorBuilder: (_, __) => const SizedBox(height: AppSpacing.sm),
                itemBuilder: (context, index) {
                  final vendor = filteredVendors[index];
                  return _buildVendorCard(vendor, canManage);
                },
              );
            },
          ),
        ],
      ),
    );
  }

  Widget _buildFilterChip(String label, String value, String currentSelected) {
    final isSelected = currentSelected == value;
    return FilterChip(
      label: Text(label),
      selected: isSelected,
      onSelected: (_) {
        ref.read(vendorStatusFilterProvider.notifier).state = value;
      },
      selectedColor: AppColors.primaryContainer.withValues(alpha: 0.3),
      checkmarkColor: AppColors.primary,
      labelStyle: TextStyle(
        fontSize: 12,
        fontWeight: isSelected ? FontWeight.w700 : FontWeight.normal,
        color: isSelected ? AppColors.primary : AppColors.onSurfaceVariant,
      ),
      backgroundColor: AppColors.surfaceContainerLow,
      visualDensity: VisualDensity.compact,
      padding: const EdgeInsets.symmetric(horizontal: 4),
    );
  }

  Widget _buildVendorCard(Vendor vendor, bool canManage) {
    return Card(
      elevation: 0,
      color: AppColors.surface,
      shape: RoundedRectangleBorder(
        borderRadius: BorderRadius.circular(AppSpacing.radiusLg),
        side: BorderSide(
          color: vendor.isActive
              ? AppColors.outlineVariant
              : AppColors.outlineVariant.withValues(alpha: 0.5),
        ),
      ),
      child: InkWell(
        onTap: () => _openDetailsDialog(vendor),
        borderRadius: BorderRadius.circular(AppSpacing.radiusLg),
        child: Padding(
          padding: const EdgeInsets.all(AppSpacing.md),
          child: Column(
            crossAxisAlignment: CrossAxisAlignment.start,
            children: [
              // Top Row: Vendor Name + Status Badge + Actions
              Row(
                crossAxisAlignment: CrossAxisAlignment.start,
                children: [
                  Container(
                    padding: const EdgeInsets.all(AppSpacing.xs),
                    decoration: BoxDecoration(
                      color: AppColors.primary.withValues(alpha: 0.1),
                      borderRadius: BorderRadius.circular(AppSpacing.radiusMd),
                    ),
                    child: const Icon(
                      Icons.local_shipping_outlined,
                      color: AppColors.primary,
                      size: 20,
                    ),
                  ),
                  const SizedBox(width: AppSpacing.sm),
                  Expanded(
                    child: Column(
                      crossAxisAlignment: CrossAxisAlignment.start,
                      children: [
                        Text(
                          vendor.name,
                          style: AppTypography.bodyMd.copyWith(
                            fontWeight: FontWeight.w700,
                          ),
                          maxLines: 1,
                          overflow: TextOverflow.ellipsis,
                        ),
                        if (vendor.contactPerson != null &&
                            vendor.contactPerson!.isNotEmpty) ...[
                          Text(
                            vendor.contactPerson!,
                            style: AppTypography.bodySm.copyWith(
                              color: AppColors.onSurfaceVariant,
                            ),
                            maxLines: 1,
                            overflow: TextOverflow.ellipsis,
                          ),
                        ],
                      ],
                    ),
                  ),
                  Container(
                    padding: const EdgeInsets.symmetric(horizontal: 6, vertical: 2),
                    decoration: BoxDecoration(
                      color: vendor.isActive
                          ? Colors.green.withValues(alpha: 0.15)
                          : Colors.grey.withValues(alpha: 0.2),
                      borderRadius: BorderRadius.circular(4),
                    ),
                    child: Text(
                      vendor.statusLabel,
                      style: TextStyle(
                        fontSize: 10,
                        fontWeight: FontWeight.w700,
                        color: vendor.isActive
                            ? Colors.green.shade800
                            : Colors.grey.shade700,
                      ),
                    ),
                  ),
                  if (canManage) ...[
                    PopupMenuButton<String>(
                      icon: const Icon(Icons.more_vert, size: 18),
                      padding: EdgeInsets.zero,
                      onSelected: (action) {
                        if (action == 'edit') {
                          _openVendorDialog(vendor: vendor);
                        } else if (action == 'toggle') {
                          ref
                              .read(vendorsProvider.notifier)
                              .toggleStatus(vendor.id, !vendor.isActive);
                        } else if (action == 'delete') {
                          _confirmDeleteVendor(vendor);
                        }
                      },
                      itemBuilder: (_) => [
                        const PopupMenuItem(
                          value: 'edit',
                          child: Row(
                            children: [
                              Icon(Icons.edit_outlined, size: 16),
                              SizedBox(width: 8),
                              Text('Edit Vendor'),
                            ],
                          ),
                        ),
                        PopupMenuItem(
                          value: 'toggle',
                          child: Row(
                            children: [
                              Icon(
                                vendor.isActive
                                    ? Icons.pause_circle_outline
                                    : Icons.play_circle_outline,
                                size: 16,
                              ),
                              const SizedBox(width: 8),
                              Text(vendor.isActive ? 'Deactivate' : 'Activate'),
                            ],
                          ),
                        ),
                        const PopupMenuItem(
                          value: 'delete',
                          child: Row(
                            children: [
                              Icon(Icons.delete_outline, size: 16, color: AppColors.error),
                              SizedBox(width: 8),
                              Text('Delete', style: TextStyle(color: AppColors.error)),
                            ],
                          ),
                        ),
                      ],
                    ),
                  ],
                ],
              ),
              const SizedBox(height: AppSpacing.xs),

              // Contact detail line (Phone / Email)
              if (vendor.phone != null || vendor.email != null) ...[
                Row(
                  children: [
                    if (vendor.phone != null) ...[
                      const Icon(Icons.phone_outlined, size: 13, color: AppColors.onSurfaceVariant),
                      const SizedBox(width: 4),
                      Text(
                        vendor.phone!,
                        style: AppTypography.bodySm.copyWith(fontSize: 12),
                      ),
                    ],
                    if (vendor.phone != null && vendor.email != null) ...[
                      const Text(' • ', style: TextStyle(color: AppColors.outlineVariant)),
                    ],
                    if (vendor.email != null) ...[
                      const Icon(Icons.email_outlined, size: 13, color: AppColors.onSurfaceVariant),
                      const SizedBox(width: 4),
                      Expanded(
                        child: Text(
                          vendor.email!,
                          style: AppTypography.bodySm.copyWith(fontSize: 12),
                          overflow: TextOverflow.ellipsis,
                        ),
                      ),
                    ],
                  ],
                ),
                const SizedBox(height: 6),
              ],

              // Products Supplied preview chips
              if (vendor.productsSupplied.isNotEmpty) ...[
                Wrap(
                  spacing: 4,
                  runSpacing: 4,
                  children: vendor.productsSupplied.take(3).map((p) {
                    return Container(
                      padding: const EdgeInsets.symmetric(horizontal: 6, vertical: 2),
                      decoration: BoxDecoration(
                        color: AppColors.surfaceContainerLow,
                        borderRadius: BorderRadius.circular(AppSpacing.radiusSm),
                        border: Border.all(color: AppColors.outlineVariant),
                      ),
                      child: Text(
                        p,
                        style: const TextStyle(fontSize: 10, fontWeight: FontWeight.w500),
                      ),
                    );
                  }).toList()
                    ..addAll(
                      vendor.productsSupplied.length > 3
                          ? [
                              Container(
                                padding: const EdgeInsets.symmetric(
                                  horizontal: 6,
                                  vertical: 2,
                                ),
                                decoration: BoxDecoration(
                                  color: AppColors.surfaceContainerLow,
                                  borderRadius:
                                      BorderRadius.circular(AppSpacing.radiusSm),
                                ),
                                child: Text(
                                  '+${vendor.productsSupplied.length - 3}',
                                  style: const TextStyle(
                                    fontSize: 10,
                                    fontWeight: FontWeight.w600,
                                    color: AppColors.primary,
                                  ),
                                ),
                              ),
                            ]
                          : [],
                    ),
                ),
              ],
              const SizedBox(height: AppSpacing.xs),

              // Bottom Row: Last Delivery Info
              const Divider(height: 12),
              Row(
                mainAxisAlignment: MainAxisAlignment.spaceBetween,
                children: [
                  Text(
                    'Last Delivery: ${vendor.formattedLastDelivery}',
                    style: AppTypography.bodySm.copyWith(
                      color: AppColors.onSurfaceVariant,
                      fontSize: 11,
                    ),
                  ),
                  if (vendor.lastQuantity != null)
                    Text(
                      'Qty: ${vendor.formattedLastQuantity}',
                      style: AppTypography.bodySm.copyWith(
                        fontWeight: FontWeight.w600,
                        fontSize: 11,
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

  Widget _buildEmptyState({
    required bool canManage,
    required bool hasFilters,
  }) {
    return Container(
      padding: const EdgeInsets.symmetric(vertical: 48, horizontal: 24),
      decoration: BoxDecoration(
        color: AppColors.surface,
        borderRadius: BorderRadius.circular(AppSpacing.radiusLg),
        border: Border.all(color: AppColors.outlineVariant),
      ),
      child: Column(
        children: [
          Container(
            padding: const EdgeInsets.all(AppSpacing.md),
            decoration: BoxDecoration(
              color: AppColors.primary.withValues(alpha: 0.1),
              shape: BoxShape.circle,
            ),
            child: const Icon(
              Icons.local_shipping_outlined,
              size: 40,
              color: AppColors.primary,
            ),
          ),
          const SizedBox(height: AppSpacing.md),
          Text(
            hasFilters ? 'No Matching Vendors' : 'No Vendors Registered Yet',
            style: AppTypography.headlineMd.copyWith(
              fontWeight: FontWeight.w700,
            ),
          ),
          const SizedBox(height: 6),
          Text(
            hasFilters
                ? 'Try adjusting your search query or status filter.'
                : 'Vendors supply medical, optical, and clinic inventory items.',
            style: AppTypography.bodyMd.copyWith(
              color: AppColors.onSurfaceVariant,
            ),
            textAlign: TextAlign.center,
          ),
          const SizedBox(height: AppSpacing.lg),
          if (hasFilters) ...[
            OutlinedButton(
              onPressed: () {
                _searchController.clear();
                ref.read(vendorSearchQueryProvider.notifier).state = '';
                ref.read(vendorStatusFilterProvider.notifier).state = 'All';
              },
              child: const Text('Clear Filters'),
            ),
          ] else if (canManage) ...[
            FilledButton.icon(
              onPressed: () => _openVendorDialog(),
              icon: const Icon(Icons.add, size: 18),
              label: const Text('Add First Vendor'),
            ),
          ],
        ],
      ),
    );
  }

  Future<void> _confirmDeleteVendor(Vendor vendor) async {
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
          'Are you sure you want to delete vendor "${vendor.name}"?\n\n'
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

    if (confirmed == true && mounted) {
      try {
        await ref.read(vendorsProvider.notifier).deleteVendor(vendor.id);
        if (mounted) {
          ScaffoldMessenger.of(context).showSnackBar(
            SnackBar(
              backgroundColor: AppColors.error,
              content: Text('Vendor "${vendor.name}" has been deleted.'),
            ),
          );
        }
      } catch (e) {
        if (mounted) {
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
}
