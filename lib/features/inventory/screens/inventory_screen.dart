import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:intl/intl.dart';

import '../../../core/theme/app_colors.dart';
import '../../../core/theme/app_spacing.dart';
import '../../../core/theme/app_typography.dart';
import '../../../shared/widgets/app_footer.dart';
import '../../admin/screens/administration_screen.dart';
import '../../admin/widgets/admin_shell.dart';
import '../../auth/providers/auth_provider.dart';
import '../../department/screens/department_management_screen.dart';
import '../../patients/screens/patient_list_screen.dart';
import '../../staff/screens/staff_management_screen.dart';
import '../models/inventory_item.dart';
import '../providers/inventory_provider.dart';
import '../widgets/inventory_details_dialog.dart';
import '../widgets/inventory_form_dialog.dart';
import '../widgets/inventory_transaction_history_dialog.dart';
import '../widgets/stock_operation_dialog.dart';

/// Full screen for Inventory Management with role-aware shell and navigation.
class InventoryManagementScreen extends ConsumerWidget {
  const InventoryManagementScreen({super.key});

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    final role = ref.watch(currentUserRoleProvider).valueOrNull;

    if (role == 'admin') {
      return AdminShell(
        selectedItem: AdminNavItem.operations,
        onNavItemSelected: (item) {
          if (item == AdminNavItem.dashboard) {
            Navigator.of(context).popUntil((route) => route.isFirst);
            return;
          }
          if (item == AdminNavItem.staff) {
            Navigator.of(context).pushReplacement(
              MaterialPageRoute(builder: (_) => const StaffManagementScreen()),
            );
            return;
          }
          if (item == AdminNavItem.patients) {
            Navigator.of(context).pushReplacement(
              MaterialPageRoute(builder: (_) => const PatientListScreen()),
            );
            return;
          }
          if (item == AdminNavItem.administration) {
            Navigator.of(context).pushReplacement(
              MaterialPageRoute(builder: (_) => const AdministrationScreen()),
            );
            return;
          }
        },
        body: const InventoryManagementContent(),
      );
    }

    return Scaffold(
      backgroundColor: AppColors.surfaceContainerLowest,
      appBar: AppBar(
        title: const Text('Inventory Management'),
        backgroundColor: AppColors.surface,
        foregroundColor: AppColors.onSurface,
        elevation: 0,
        leading: Navigator.of(context).canPop()
            ? BackButton(onPressed: () => Navigator.of(context).pop())
            : null,
      ),
      body: const InventoryManagementContent(),
    );
  }
}

/// The inner content of the Inventory Management view.
/// Can be rendered inside [InventoryManagementScreen] or embedded inside tabbed operations.
class InventoryManagementContent extends ConsumerStatefulWidget {
  const InventoryManagementContent({super.key});

  @override
  ConsumerState<InventoryManagementContent> createState() =>
      _InventoryManagementContentState();
}

class _InventoryManagementContentState
    extends ConsumerState<InventoryManagementContent> {
  final _searchController = TextEditingController();

  @override
  void dispose() {
    _searchController.dispose();
    super.dispose();
  }

  Future<void> _openItemDialog({InventoryItem? item}) async {
    await showDialog<InventoryItem>(
      context: context,
      builder: (_) => InventoryFormDialog(item: item),
    );
  }

  Future<void> _openDetailsDialog(InventoryItem item) async {
    await showDialog<void>(
      context: context,
      builder: (_) => InventoryDetailsDialog(item: item),
    );
  }

  Future<void> _openStockInDialog(InventoryItem item) async {
    await showDialog<void>(
      context: context,
      builder: (_) => StockOperationDialog.stockIn(item: item),
    );
  }

  Future<void> _openStockOutDialog(InventoryItem item) async {
    await showDialog<void>(
      context: context,
      builder: (_) => StockOperationDialog.stockOut(item: item),
    );
  }

  Future<void> _openHistoryDialog(InventoryItem item) async {
    await showDialog<void>(
      context: context,
      builder: (_) => InventoryTransactionHistoryDialog(item: item),
    );
  }

  Future<void> _confirmDelete(InventoryItem item) async {
    final confirmed = await showDialog<bool>(
      context: context,
      builder: (dialogContext) => AlertDialog(
        title: const Row(
          children: [
            Icon(Icons.warning_amber_rounded, color: AppColors.error, size: 24),
            SizedBox(width: AppSpacing.xs),
            Text('Delete Inventory Item'),
          ],
        ),
        content: Text(
          'Are you sure you want to delete "${item.name}"?\n'
          'Current stock: ${item.formattedStock}\n\n'
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
            child: const Text('Delete'),
          ),
        ],
      ),
    );

    if (confirmed == true && mounted) {
      try {
        await ref.read(inventoryProvider.notifier).deleteItem(item.id);
        if (mounted) {
          ScaffoldMessenger.of(context).showSnackBar(
            SnackBar(
              backgroundColor: AppColors.primaryContainer,
              content: Row(
                children: [
                  const Icon(Icons.check_circle, color: Colors.white),
                  const SizedBox(width: AppSpacing.xs),
                  Expanded(
                    child: Text(
                      'Item "${item.name}" deleted successfully.',
                      style: const TextStyle(color: Colors.white),
                    ),
                  ),
                ],
              ),
            ),
          );
        }
      } catch (e) {
        if (mounted) {
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

  @override
  Widget build(BuildContext context) {
    final inventoryState = ref.watch(inventoryProvider);
    final filteredItems = ref.watch(filteredInventoryProvider);
    final availableCategories = ref.watch(availableCategoriesProvider);
    final selectedCategory = ref.watch(inventoryCategoryFilterProvider);
    final selectedDepartment = ref.watch(inventoryDepartmentFilterProvider);
    final selectedStatus = ref.watch(inventoryStatusFilterProvider);
    final searchQuery = ref.watch(inventorySearchQueryProvider);

    final lowStockCount = ref.watch(lowStockCountProvider);
    final expiringSoonCount = ref.watch(expiringSoonCountProvider);
    final expiredCount = ref.watch(expiredCountProvider);

    final role = ref.watch(currentUserRoleProvider).valueOrNull;
    final isAdmin = role == 'admin';
    final canManageInventory = isAdmin || role == 'staff';

    final isDesktop = MediaQuery.sizeOf(context).width > 768;

    return RefreshIndicator(
      onRefresh: () async {
        await ref.read(inventoryProvider.notifier).refresh();
      },
      child: SingleChildScrollView(
        physics: const AlwaysScrollableScrollPhysics(),
        padding: EdgeInsets.all(
          isDesktop ? AppSpacing.marginDesktop : AppSpacing.marginMobile,
        ),
        child: Column(
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            _buildHeader(isDesktop, canManageInventory),
            const SizedBox(height: AppSpacing.lg),
            _buildSearchAndFilterBar(
              isDesktop,
              availableCategories,
              selectedCategory,
              selectedDepartment,
              selectedStatus,
              searchQuery,
              lowStockCount,
              expiringSoonCount,
              expiredCount,
            ),
            const SizedBox(height: AppSpacing.md),
            inventoryState.when(
              loading: () => const Center(
                child: Padding(
                  padding: EdgeInsets.all(AppSpacing.xl),
                  child: CircularProgressIndicator(),
                ),
              ),
              error: (error, _) => _buildErrorCard(error),
              data: (allItems) {
                if (allItems.isEmpty) {
                  return _buildEmptyInventoryState(canManageInventory);
                }
                if (filteredItems.isEmpty) {
                  return _buildNoSearchResultsState(searchQuery, selectedCategory, selectedStatus);
                }
                return isDesktop
                    ? _buildDesktopTable(filteredItems, canManageInventory)
                    : _buildMobileCards(filteredItems, canManageInventory);
              },
            ),
            const SizedBox(height: AppSpacing.xl),
            const AppFooter(),
          ],
        ),
      ),
    );
  }

  Widget _buildHeader(bool isDesktop, bool canManageInventory) {
    final actions = Wrap(
      spacing: AppSpacing.sm,
      runSpacing: AppSpacing.sm,
      children: [
        IconButton.outlined(
          tooltip: 'Refresh Inventory',
          onPressed: () => ref.read(inventoryProvider.notifier).refresh(),
          icon: const Icon(Icons.refresh, size: 20),
        ),
        if (canManageInventory)
          OutlinedButton.icon(
            onPressed: () {
              Navigator.of(context).push(
                MaterialPageRoute(
                  builder: (_) => const DepartmentManagementScreen(),
                ),
              );
            },
            icon: const Icon(Icons.business_outlined, size: 18),
            label: const Text('Departments'),
          ),
        if (canManageInventory)
          FilledButton.icon(
            onPressed: () => _openItemDialog(),
            icon: const Icon(Icons.add, size: 18),
            label: const Text('Add Item'),
            style: FilledButton.styleFrom(
              backgroundColor: AppColors.primary,
              foregroundColor: AppColors.onPrimary,
              padding: const EdgeInsets.symmetric(
                horizontal: AppSpacing.md,
                vertical: AppSpacing.sm,
              ),
              shape: RoundedRectangleBorder(
                borderRadius: BorderRadius.circular(AppSpacing.radiusMd),
              ),
            ),
          ),
      ],
    );

    if (isDesktop) {
      return Row(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Expanded(
            child: Column(
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                Text(
                  'Inventory Management',
                  style: AppTypography.displayLg.copyWith(
                    color: AppColors.onBackground,
                    fontWeight: FontWeight.w700,
                  ),
                ),
                const SizedBox(height: AppSpacing.xs),
                Text(
                  'Track clinic stock, supplies, medications, and equipment across departments.',
                  style: AppTypography.bodyLg.copyWith(
                    color: AppColors.onSurfaceVariant,
                  ),
                ),
              ],
            ),
          ),
          const SizedBox(width: AppSpacing.md),
          actions,
        ],
      );
    }

    return Column(
      crossAxisAlignment: CrossAxisAlignment.start,
      children: [
        Text(
          'Inventory Management',
          style: AppTypography.displayLg.copyWith(
            fontSize: 26,
            color: AppColors.onBackground,
            fontWeight: FontWeight.w700,
          ),
        ),
        const SizedBox(height: AppSpacing.xs),
        Text(
          'Track clinic stock, supplies, medications, and equipment across departments.',
          style: AppTypography.bodyLg.copyWith(
            color: AppColors.onSurfaceVariant,
          ),
        ),
        const SizedBox(height: AppSpacing.sm),
        actions,
      ],
    );
  }

  Widget _buildSearchAndFilterBar(
    bool isDesktop,
    List<String> categories,
    String selectedCategory,
    String selectedDepartment,
    String selectedStatus,
    String searchQuery,
    int lowStockCount,
    int expiringSoonCount,
    int expiredCount,
  ) {
    return Container(
      padding: const EdgeInsets.all(AppSpacing.md),
      decoration: BoxDecoration(
        color: AppColors.surfaceContainerLowest,
        borderRadius: BorderRadius.circular(AppSpacing.radiusLg),
        border: Border.all(color: AppColors.outlineVariant),
      ),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          // Search Field + Department Filter
          Row(
            children: [
              Expanded(
                child: TextField(
                  controller: _searchController,
                  decoration: InputDecoration(
                    hintText: 'Search by item name, category, SKU, brand...',
                    prefixIcon: const Icon(Icons.search, size: 20),
                    suffixIcon: searchQuery.isNotEmpty
                        ? IconButton(
                            icon: const Icon(Icons.clear, size: 18),
                            onPressed: () {
                              _searchController.clear();
                              ref.read(inventorySearchQueryProvider.notifier).state = '';
                            },
                          )
                        : null,
                    isDense: true,
                    contentPadding: const EdgeInsets.symmetric(
                      horizontal: 12,
                      vertical: 10,
                    ),
                    border: OutlineInputBorder(
                      borderRadius: BorderRadius.circular(AppSpacing.radiusMd),
                      borderSide: const BorderSide(color: AppColors.outlineVariant),
                    ),
                    fillColor: AppColors.surfaceContainerLow,
                  ),
                  onChanged: (val) {
                    ref.read(inventorySearchQueryProvider.notifier).state = val;
                  },
                ),
              ),
              if (isDesktop) ...[
                const SizedBox(width: AppSpacing.md),
                SizedBox(
                  width: 170,
                  child: DropdownButtonFormField<String>(
                    isExpanded: true,
                    initialValue: selectedDepartment,
                    decoration: InputDecoration(
                      isDense: true,
                      contentPadding: const EdgeInsets.symmetric(
                        horizontal: 10,
                        vertical: 9,
                      ),
                      prefixIcon: const Icon(
                        Icons.business_outlined,
                        size: 18,
                        color: AppColors.onSurfaceVariant,
                      ),
                      border: OutlineInputBorder(
                        borderRadius: BorderRadius.circular(AppSpacing.radiusMd),
                      ),
                      fillColor: AppColors.surfaceContainerLow,
                    ),
                    items: const [
                      DropdownMenuItem(value: 'All', child: Text('All Depts')),
                      DropdownMenuItem(value: 'eye', child: Text('Eye Care')),
                      DropdownMenuItem(value: 'dental', child: Text('Dental')),
                      DropdownMenuItem(value: 'optical', child: Text('Optical')),
                      DropdownMenuItem(value: 'general', child: Text('General')),
                    ],
                    onChanged: (val) {
                      if (val != null) {
                        ref.read(inventoryDepartmentFilterProvider.notifier).state = val;
                      }
                    },
                  ),
                ),
              ],
            ],
          ),
          const SizedBox(height: AppSpacing.sm),

          // Status Filter Chips (Quick Toggles for Low Stock & Expiry)
          Row(
            crossAxisAlignment: CrossAxisAlignment.center,
            children: [
              Text(
                'Status:',
                style: AppTypography.labelCaps.copyWith(
                  color: AppColors.onSurfaceVariant,
                ),
              ),
              const SizedBox(width: AppSpacing.sm),
              Expanded(
                child: SingleChildScrollView(
                  scrollDirection: Axis.horizontal,
                  child: Row(
                    children: [
                      _buildStatusFilterChip('All', 'All', selectedStatus),
                      _buildStatusFilterChip(
                        'Low Stock',
                        'Low Stock',
                        selectedStatus,
                        count: lowStockCount,
                        badgeColor: AppColors.error,
                      ),
                      _buildStatusFilterChip(
                        'Expiring Soon',
                        'Expiring Soon',
                        selectedStatus,
                        count: expiringSoonCount,
                        badgeColor: const Color(0xFFE65100),
                      ),
                      _buildStatusFilterChip(
                        'Expired',
                        'Expired',
                        selectedStatus,
                        count: expiredCount,
                        badgeColor: AppColors.error,
                      ),
                    ],
                  ),
                ),
              ),
            ],
          ),
          const SizedBox(height: AppSpacing.xs),

          // Category Chips
          Row(
            crossAxisAlignment: CrossAxisAlignment.center,
            children: [
              Text(
                'Category:',
                style: AppTypography.labelCaps.copyWith(
                  color: AppColors.onSurfaceVariant,
                ),
              ),
              const SizedBox(width: AppSpacing.sm),
              Expanded(
                child: SingleChildScrollView(
                  scrollDirection: Axis.horizontal,
                  child: Row(
                    children: categories.map((cat) {
                      final isSelected = selectedCategory == cat;
                      return Padding(
                        padding: const EdgeInsets.only(right: 6),
                        child: FilterChip(
                          label: Text(cat),
                          selected: isSelected,
                          onSelected: (_) {
                            ref.read(inventoryCategoryFilterProvider.notifier).state = cat;
                          },
                          selectedColor:
                              AppColors.primaryContainer.withValues(alpha: 0.25),
                          checkmarkColor: AppColors.primary,
                          labelStyle: TextStyle(
                            fontSize: 12,
                            fontWeight:
                                isSelected ? FontWeight.w700 : FontWeight.normal,
                            color: isSelected
                                ? AppColors.primary
                                : AppColors.onSurfaceVariant,
                          ),
                          backgroundColor: AppColors.surfaceContainerLow,
                          visualDensity: VisualDensity.compact,
                          padding: const EdgeInsets.symmetric(horizontal: 4),
                        ),
                      );
                    }).toList(),
                  ),
                ),
              ),
            ],
          ),
        ],
      ),
    );
  }

  Widget _buildStatusFilterChip(
    String label,
    String value,
    String selectedStatus, {
    int? count,
    Color? badgeColor,
  }) {
    final isSelected = selectedStatus == value;
    final color = badgeColor ?? AppColors.primary;

    return Padding(
      padding: const EdgeInsets.only(right: 6),
      child: FilterChip(
        label: Row(
          mainAxisSize: MainAxisSize.min,
          children: [
            Text(label),
            if (count != null && count > 0) ...[
              const SizedBox(width: 4),
              Container(
                padding: const EdgeInsets.symmetric(horizontal: 5, vertical: 1),
                decoration: BoxDecoration(
                  color: isSelected ? color : color.withValues(alpha: 0.15),
                  borderRadius: BorderRadius.circular(10),
                ),
                child: Text(
                  count.toString(),
                  style: TextStyle(
                    fontSize: 10,
                    fontWeight: FontWeight.w700,
                    color: isSelected ? Colors.white : color,
                  ),
                ),
              ),
            ],
          ],
        ),
        selected: isSelected,
        onSelected: (_) {
          ref.read(inventoryStatusFilterProvider.notifier).state = value;
        },
        selectedColor: color.withValues(alpha: 0.2),
        checkmarkColor: color,
        labelStyle: TextStyle(
          fontSize: 11,
          fontWeight: isSelected ? FontWeight.w700 : FontWeight.normal,
          color: isSelected ? color : AppColors.onSurfaceVariant,
        ),
        backgroundColor: AppColors.surfaceContainerLow,
        visualDensity: VisualDensity.compact,
        padding: const EdgeInsets.symmetric(horizontal: 4),
      ),
    );
  }

  Widget _buildDesktopTable(List<InventoryItem> items, bool canManageInventory) {
    final dateFormat = DateFormat('MMM d, yyyy');

    return Container(
      decoration: BoxDecoration(
        color: AppColors.surfaceContainerLowest,
        borderRadius: BorderRadius.circular(AppSpacing.radiusLg),
        border: Border.all(color: AppColors.outlineVariant),
        boxShadow: const [
          BoxShadow(
            color: Color(0x0A000000),
            blurRadius: 8,
            offset: Offset(0, 1),
          ),
        ],
      ),
      child: SingleChildScrollView(
        scrollDirection: Axis.horizontal,
        child: ConstrainedBox(
          constraints: const BoxConstraints(minWidth: 1120),
          child: Column(
            children: [
              // Table Header
              Container(
                width: 1120,
                padding: const EdgeInsets.symmetric(
                  horizontal: AppSpacing.md,
                  vertical: AppSpacing.sm,
                ),
                decoration: const BoxDecoration(
                  border: Border(
                    bottom: BorderSide(color: AppColors.outlineVariant),
                  ),
                ),
                child: Row(
                  children: [
                    Expanded(
                      flex: 4,
                      child: Text('ITEM NAME', style: AppTypography.labelCaps),
                    ),
                    Expanded(
                      flex: 2,
                      child: Text('CATEGORY', style: AppTypography.labelCaps),
                    ),
                    Expanded(
                      flex: 2,
                      child: Text('STOCK & HEALTH', style: AppTypography.labelCaps),
                    ),
                    Expanded(
                      flex: 2,
                      child: Text('EXPIRY STATUS', style: AppTypography.labelCaps),
                    ),
                    Expanded(
                      flex: 1,
                      child: Text('DEPT', style: AppTypography.labelCaps),
                    ),
                    Expanded(
                      flex: 1,
                      child: Text('STATUS', style: AppTypography.labelCaps),
                    ),
                    SizedBox(
                      width: canManageInventory ? 260 : 160,
                      child: const Text(
                        'ACTIONS',
                        style: TextStyle(fontSize: 11, fontWeight: FontWeight.w700),
                        textAlign: TextAlign.end,
                      ),
                    ),
                  ],
                ),
              ),

              // Rows
              Column(
                children: items.map((item) {
                  return Container(
                    width: 1120,
                    padding: const EdgeInsets.symmetric(
                      horizontal: AppSpacing.md,
                      vertical: AppSpacing.sm,
                    ),
                    decoration: const BoxDecoration(
                      border: Border(
                        bottom: BorderSide(
                          color: AppColors.outlineVariant,
                          width: 0.5,
                        ),
                      ),
                    ),
                    child: Row(
                      children: [
                        // Item Name + SKU
                        Expanded(
                          flex: 4,
                          child: InkWell(
                            onTap: () => _openDetailsDialog(item),
                            child: Row(
                              children: [
                                Container(
                                  padding: const EdgeInsets.all(6),
                                  decoration: BoxDecoration(
                                    color: item.isLowStock
                                        ? AppColors.errorContainer.withValues(alpha: 0.2)
                                        : AppColors.primaryContainer.withValues(alpha: 0.15),
                                    borderRadius: BorderRadius.circular(AppSpacing.radiusMd),
                                  ),
                                  child: Icon(
                                    item.isLowStock
                                        ? Icons.warning_amber_rounded
                                        : Icons.medication_outlined,
                                    size: 18,
                                    color: item.isLowStock
                                        ? AppColors.error
                                        : AppColors.primary,
                                  ),
                                ),
                                const SizedBox(width: AppSpacing.sm),
                                Expanded(
                                  child: Column(
                                    crossAxisAlignment: CrossAxisAlignment.start,
                                    children: [
                                      Text(
                                        item.name,
                                        style: AppTypography.bodyMd.copyWith(
                                          fontWeight: FontWeight.w600,
                                        ),
                                        overflow: TextOverflow.ellipsis,
                                      ),
                                      if (item.sku != null && item.sku!.isNotEmpty)
                                        Text(
                                          'SKU: ${item.sku}',
                                          style: AppTypography.labelCaps.copyWith(
                                            color: AppColors.onSurfaceVariant,
                                            fontSize: 10,
                                          ),
                                        ),
                                    ],
                                  ),
                                ),
                              ],
                            ),
                          ),
                        ),

                        // Category Badge
                        Expanded(
                          flex: 2,
                          child: Align(
                            alignment: Alignment.centerLeft,
                            child: Container(
                              padding: const EdgeInsets.symmetric(
                                horizontal: 8,
                                vertical: 3,
                              ),
                              decoration: BoxDecoration(
                                color: AppColors.surfaceContainerLow,
                                borderRadius: BorderRadius.circular(4),
                                border: Border.all(color: AppColors.outlineVariant),
                              ),
                              child: Text(
                                item.category,
                                style: AppTypography.bodySm.copyWith(
                                  fontWeight: FontWeight.w500,
                                  fontSize: 12,
                                ),
                                overflow: TextOverflow.ellipsis,
                              ),
                            ),
                          ),
                        ),

                        // Current Stock & Health
                        Expanded(
                          flex: 2,
                          child: Column(
                            crossAxisAlignment: CrossAxisAlignment.start,
                            mainAxisSize: MainAxisSize.min,
                            children: [
                              Row(
                                children: [
                                  Flexible(
                                    child: Text(
                                      item.formattedStock,
                                      style: AppTypography.bodyMd.copyWith(
                                        fontWeight: FontWeight.w700,
                                        color: item.isLowStock
                                            ? AppColors.error
                                            : AppColors.onSurface,
                                      ),
                                      overflow: TextOverflow.ellipsis,
                                    ),
                                  ),
                                  if (item.isLowStock) ...[
                                    const SizedBox(width: 4),
                                    const Icon(
                                      Icons.arrow_downward,
                                      color: AppColors.error,
                                      size: 14,
                                    ),
                                  ],
                                ],
                              ),
                              if (item.isLowStock) ...[
                                const SizedBox(height: 2),
                                Container(
                                  padding: const EdgeInsets.symmetric(
                                    horizontal: 4,
                                    vertical: 1,
                                  ),
                                  decoration: BoxDecoration(
                                    color: AppColors.error.withValues(alpha: 0.15),
                                    borderRadius: BorderRadius.circular(2),
                                  ),
                                  child: const Text(
                                    'LOW STOCK',
                                    style: TextStyle(
                                      color: AppColors.error,
                                      fontSize: 9,
                                      fontWeight: FontWeight.w700,
                                    ),
                                  ),
                                ),
                              ],
                            ],
                          ),
                        ),

                        // Expiry Status
                        Expanded(
                          flex: 2,
                          child: item.expiryDate != null
                              ? Column(
                                  crossAxisAlignment: CrossAxisAlignment.start,
                                  mainAxisSize: MainAxisSize.min,
                                  children: [
                                    Text(
                                      dateFormat.format(item.expiryDate!),
                                      style: AppTypography.bodySm.copyWith(
                                        fontSize: 12,
                                      ),
                                    ),
                                    const SizedBox(height: 2),
                                    Container(
                                      padding: const EdgeInsets.symmetric(
                                        horizontal: 5,
                                        vertical: 1,
                                      ),
                                      decoration: BoxDecoration(
                                        color: item.expiryStatusColor
                                            .withValues(alpha: 0.15),
                                        borderRadius: BorderRadius.circular(3),
                                        border: Border.all(
                                          color: item.expiryStatusColor
                                              .withValues(alpha: 0.4),
                                          width: 0.8,
                                        ),
                                      ),
                                      child: Row(
                                        mainAxisSize: MainAxisSize.min,
                                        children: [
                                          Icon(
                                            item.expiryStatusIcon,
                                            size: 10,
                                            color: item.expiryStatusColor,
                                          ),
                                          const SizedBox(width: 3),
                                          Text(
                                            item.expiryStatusLabel,
                                            style: TextStyle(
                                              color: item.expiryStatusColor,
                                              fontSize: 9,
                                              fontWeight: FontWeight.w700,
                                            ),
                                          ),
                                        ],
                                      ),
                                    ),
                                  ],
                                )
                              : Text(
                                  '—',
                                  style: AppTypography.bodySm.copyWith(
                                    color: AppColors.onSurfaceVariant,
                                  ),
                                ),
                        ),

                        // Department
                        Expanded(
                          flex: 1,
                          child: Text(
                            item.department != null && item.department!.isNotEmpty
                                ? item.department!.toUpperCase()
                                : 'General',
                            style: AppTypography.bodySm.copyWith(
                              color: AppColors.onSurfaceVariant,
                              fontSize: 11,
                            ),
                          ),
                        ),

                        // Status Badge
                        Expanded(
                          flex: 1,
                          child: Align(
                            alignment: Alignment.centerLeft,
                            child: Container(
                              padding: const EdgeInsets.symmetric(
                                horizontal: 6,
                                vertical: 2,
                              ),
                              decoration: BoxDecoration(
                                color: item.isActive
                                    ? Colors.green.withValues(alpha: 0.1)
                                    : Colors.grey.withValues(alpha: 0.1),
                                borderRadius: BorderRadius.circular(4),
                              ),
                              child: Text(
                                item.isActive ? 'Active' : 'Inactive',
                                style: TextStyle(
                                  fontSize: 10,
                                  fontWeight: FontWeight.w600,
                                  color: item.isActive ? Colors.green : Colors.grey,
                                ),
                              ),
                            ),
                          ),
                        ),

                        // Actions
                        SizedBox(
                          width: canManageInventory ? 260 : 160,
                          child: Row(
                            mainAxisAlignment: MainAxisAlignment.end,
                            children: [
                              IconButton(
                                visualDensity: VisualDensity.compact,
                                padding: EdgeInsets.zero,
                                constraints: const BoxConstraints(minWidth: 32, minHeight: 32),
                                icon: const Icon(Icons.visibility_outlined, size: 18),
                                tooltip: 'View Details',
                                onPressed: () => _openDetailsDialog(item),
                              ),
                              IconButton(
                                visualDensity: VisualDensity.compact,
                                padding: EdgeInsets.zero,
                                constraints: const BoxConstraints(minWidth: 32, minHeight: 32),
                                icon: Icon(
                                  Icons.add_circle_outline,
                                  size: 18,
                                  color: Colors.green.shade700,
                                ),
                                tooltip: 'Stock In',
                                onPressed: () => _openStockInDialog(item),
                              ),
                              IconButton(
                                visualDensity: VisualDensity.compact,
                                padding: EdgeInsets.zero,
                                constraints: const BoxConstraints(minWidth: 32, minHeight: 32),
                                icon: const Icon(
                                  Icons.remove_circle_outline,
                                  size: 18,
                                  color: Color(0xFFE65100),
                                ),
                                tooltip: 'Stock Out',
                                onPressed: () => _openStockOutDialog(item),
                              ),
                              IconButton(
                                visualDensity: VisualDensity.compact,
                                padding: EdgeInsets.zero,
                                constraints: const BoxConstraints(minWidth: 32, minHeight: 32),
                                icon: const Icon(Icons.history, size: 18),
                                tooltip: 'History',
                                onPressed: () => _openHistoryDialog(item),
                              ),
                              if (canManageInventory) ...[
                                IconButton(
                                  visualDensity: VisualDensity.compact,
                                  padding: EdgeInsets.zero,
                                  constraints: const BoxConstraints(minWidth: 32, minHeight: 32),
                                  icon: const Icon(Icons.edit_outlined, size: 18),
                                  tooltip: 'Edit Item',
                                  onPressed: () => _openItemDialog(item: item),
                                ),
                                IconButton(
                                  visualDensity: VisualDensity.compact,
                                  padding: EdgeInsets.zero,
                                  constraints: const BoxConstraints(minWidth: 32, minHeight: 32),
                                  icon: const Icon(
                                    Icons.delete_outline,
                                    size: 18,
                                    color: AppColors.error,
                                  ),
                                  tooltip: 'Delete Item',
                                  onPressed: () => _confirmDelete(item),
                                ),
                              ],
                            ],
                          ),
                        ),
                      ],
                    ),
                  );
                }).toList(),
              ),
            ],
          ),
        ),
      ),
    );
  }

  Widget _buildMobileCards(List<InventoryItem> items, bool canManageInventory) {
    final dateFormat = DateFormat('MMM d, yyyy');

    return Column(
      children: items.map((item) {
        return Container(
          margin: const EdgeInsets.only(bottom: AppSpacing.sm),
          padding: const EdgeInsets.all(AppSpacing.md),
          decoration: BoxDecoration(
            color: AppColors.surfaceContainerLowest,
            borderRadius: BorderRadius.circular(AppSpacing.radiusLg),
            border: Border.all(
              color: item.isLowStock
                  ? AppColors.error.withValues(alpha: 0.4)
                  : AppColors.outlineVariant,
            ),
          ),
          child: Column(
            crossAxisAlignment: CrossAxisAlignment.start,
            children: [
              Row(
                crossAxisAlignment: CrossAxisAlignment.start,
                children: [
                  Container(
                    padding: const EdgeInsets.all(AppSpacing.xs),
                    decoration: BoxDecoration(
                      color: item.isLowStock
                          ? AppColors.errorContainer.withValues(alpha: 0.2)
                          : AppColors.primaryContainer.withValues(alpha: 0.15),
                      borderRadius: BorderRadius.circular(AppSpacing.radiusMd),
                    ),
                    child: Icon(
                      item.isLowStock
                          ? Icons.warning_amber_rounded
                          : Icons.medication_outlined,
                      color: item.isLowStock ? AppColors.error : AppColors.primary,
                      size: 20,
                    ),
                  ),
                  const SizedBox(width: AppSpacing.sm),
                  Expanded(
                    child: Column(
                      crossAxisAlignment: CrossAxisAlignment.start,
                      children: [
                        Text(
                          item.name,
                          style: AppTypography.headlineMd.copyWith(fontSize: 16),
                        ),
                        if (item.sku != null && item.sku!.isNotEmpty)
                          Text(
                            'SKU: ${item.sku}',
                            style: AppTypography.bodySm.copyWith(
                              color: AppColors.onSurfaceVariant,
                              fontSize: 11,
                            ),
                          ),
                      ],
                    ),
                  ),
                  Column(
                    crossAxisAlignment: CrossAxisAlignment.end,
                    children: [
                      Text(
                        item.formattedStock,
                        style: AppTypography.headlineMd.copyWith(
                          color: item.isLowStock ? AppColors.error : AppColors.primary,
                          fontSize: 18,
                        ),
                      ),
                      if (item.isLowStock)
                        Container(
                          padding: const EdgeInsets.symmetric(horizontal: 5, vertical: 1),
                          decoration: BoxDecoration(
                            color: AppColors.error,
                            borderRadius: BorderRadius.circular(3),
                          ),
                          child: const Text(
                            'LOW STOCK',
                            style: TextStyle(
                              color: Colors.white,
                              fontSize: 9,
                              fontWeight: FontWeight.w700,
                            ),
                          ),
                        ),
                    ],
                  ),
                ],
              ),
              const SizedBox(height: AppSpacing.xs),
              Wrap(
                spacing: 6,
                runSpacing: 4,
                crossAxisAlignment: WrapCrossAlignment.center,
                children: [
                  Container(
                    padding: const EdgeInsets.symmetric(horizontal: 6, vertical: 2),
                    decoration: BoxDecoration(
                      color: AppColors.surfaceContainerLow,
                      borderRadius: BorderRadius.circular(4),
                    ),
                    child: Text(
                      item.category,
                      style: const TextStyle(fontSize: 11, fontWeight: FontWeight.w500),
                    ),
                  ),
                  if (item.department != null)
                    Text(
                      '• ${item.department!.toUpperCase()}',
                      style: AppTypography.bodySm.copyWith(
                        color: AppColors.onSurfaceVariant,
                        fontSize: 11,
                      ),
                    ),
                  if (item.expiryDate != null)
                    Container(
                      padding: const EdgeInsets.symmetric(horizontal: 6, vertical: 2),
                      decoration: BoxDecoration(
                        color: item.expiryStatusColor.withValues(alpha: 0.15),
                        borderRadius: BorderRadius.circular(4),
                      ),
                      child: Row(
                        mainAxisSize: MainAxisSize.min,
                        children: [
                          Icon(item.expiryStatusIcon, size: 10, color: item.expiryStatusColor),
                          const SizedBox(width: 3),
                          Text(
                            'Exp: ${dateFormat.format(item.expiryDate!)} (${item.expiryStatusLabel})',
                            style: TextStyle(
                              fontSize: 10,
                              fontWeight: FontWeight.w600,
                              color: item.expiryStatusColor,
                            ),
                          ),
                        ],
                      ),
                    ),
                ],
              ),
              if (item.description != null && item.description!.isNotEmpty) ...[
                const SizedBox(height: AppSpacing.xs),
                Text(
                  item.description!,
                  maxLines: 2,
                  overflow: TextOverflow.ellipsis,
                  style: AppTypography.bodySm.copyWith(
                    color: AppColors.onSurfaceVariant,
                  ),
                ),
              ],
              const Divider(height: AppSpacing.lg),
              Wrap(
                spacing: AppSpacing.xs,
                runSpacing: AppSpacing.xs,
                alignment: WrapAlignment.end,
                children: [
                  TextButton.icon(
                    onPressed: () => _openDetailsDialog(item),
                    icon: const Icon(Icons.visibility_outlined, size: 16),
                    label: const Text('Details'),
                  ),
                  OutlinedButton.icon(
                    onPressed: () => _openStockInDialog(item),
                    icon: Icon(Icons.add_circle_outline, size: 16, color: Colors.green.shade700),
                    label: Text(
                      'Stock In',
                      style: TextStyle(color: Colors.green.shade700, fontSize: 12),
                    ),
                    style: OutlinedButton.styleFrom(
                      padding: const EdgeInsets.symmetric(horizontal: 8),
                      visualDensity: VisualDensity.compact,
                    ),
                  ),
                  OutlinedButton.icon(
                    onPressed: () => _openStockOutDialog(item),
                    icon: const Icon(Icons.remove_circle_outline, size: 16, color: Color(0xFFE65100)),
                    label: const Text(
                      'Stock Out',
                      style: TextStyle(color: Color(0xFFE65100), fontSize: 12),
                    ),
                    style: OutlinedButton.styleFrom(
                      padding: const EdgeInsets.symmetric(horizontal: 8),
                      visualDensity: VisualDensity.compact,
                    ),
                  ),
                  IconButton(
                    icon: const Icon(Icons.history, size: 18),
                    tooltip: 'History',
                    onPressed: () => _openHistoryDialog(item),
                  ),
                  if (canManageInventory) ...[
                    IconButton(
                      icon: const Icon(Icons.edit_outlined, size: 18),
                      tooltip: 'Edit',
                      onPressed: () => _openItemDialog(item: item),
                    ),
                    IconButton(
                      icon: const Icon(Icons.delete_outline,
                          size: 18, color: AppColors.error),
                      tooltip: 'Delete',
                      onPressed: () => _confirmDelete(item),
                    ),
                  ],
                ],
              ),
            ],
          ),
        );
      }).toList(),
    );
  }

  Widget _buildEmptyInventoryState(bool canAdd) {
    return Container(
      width: double.infinity,
      padding: const EdgeInsets.all(AppSpacing.xl),
      decoration: BoxDecoration(
        color: AppColors.surfaceContainerLowest,
        borderRadius: BorderRadius.circular(AppSpacing.radiusLg),
        border: Border.all(color: AppColors.outlineVariant),
      ),
      child: Column(
        mainAxisSize: MainAxisSize.min,
        children: [
          Container(
            padding: const EdgeInsets.all(AppSpacing.md),
            decoration: BoxDecoration(
              color: AppColors.surfaceContainerLow,
              shape: BoxShape.circle,
            ),
            child: const Icon(
              Icons.inventory_2_outlined,
              size: 48,
              color: AppColors.onSurfaceVariant,
            ),
          ),
          const SizedBox(height: AppSpacing.md),
          Text(
            'No Inventory Items Yet',
            style: AppTypography.headlineMd.copyWith(
              fontWeight: FontWeight.w700,
            ),
          ),
          const SizedBox(height: AppSpacing.xs),
          Text(
            'Get started by adding clinical supplies, medications, or equipment to your inventory.',
            textAlign: TextAlign.center,
            style: AppTypography.bodyMd.copyWith(
              color: AppColors.onSurfaceVariant,
            ),
          ),
          if (canAdd) ...[
            const SizedBox(height: AppSpacing.lg),
            FilledButton.icon(
              onPressed: () => _openItemDialog(),
              icon: const Icon(Icons.add),
              label: const Text('Add First Item'),
              style: FilledButton.styleFrom(
                backgroundColor: AppColors.primary,
                foregroundColor: AppColors.onPrimary,
              ),
            ),
          ],
        ],
      ),
    );
  }

  Widget _buildNoSearchResultsState(String query, String category, String status) {
    return Container(
      width: double.infinity,
      padding: const EdgeInsets.all(AppSpacing.xl),
      decoration: BoxDecoration(
        color: AppColors.surfaceContainerLowest,
        borderRadius: BorderRadius.circular(AppSpacing.radiusLg),
        border: Border.all(color: AppColors.outlineVariant),
      ),
      child: Column(
        mainAxisSize: MainAxisSize.min,
        children: [
          const Icon(
            Icons.search_off_outlined,
            size: 40,
            color: AppColors.onSurfaceVariant,
          ),
          const SizedBox(height: AppSpacing.sm),
          Text(
            query.isNotEmpty
                ? 'No items found matching "$query"'
                : status != 'All'
                    ? 'No items matching status "$status"'
                    : 'No items in category "$category"',
            style: AppTypography.headlineMd,
          ),
          const SizedBox(height: AppSpacing.xs),
          Text(
            'Try adjusting your search query, status, or category filter.',
            style: AppTypography.bodySm.copyWith(
              color: AppColors.onSurfaceVariant,
            ),
          ),
          const SizedBox(height: AppSpacing.md),
          OutlinedButton.icon(
            onPressed: () {
              _searchController.clear();
              ref.read(inventorySearchQueryProvider.notifier).state = '';
              ref.read(inventoryCategoryFilterProvider.notifier).state = 'All';
              ref.read(inventoryDepartmentFilterProvider.notifier).state = 'All';
              ref.read(inventoryStatusFilterProvider.notifier).state = 'All';
            },
            icon: const Icon(Icons.filter_alt_off_outlined, size: 16),
            label: const Text('Clear Filters'),
          ),
        ],
      ),
    );
  }

  Widget _buildErrorCard(Object error) {
    return Container(
      width: double.infinity,
      padding: const EdgeInsets.all(AppSpacing.xl),
      decoration: BoxDecoration(
        color: AppColors.surfaceContainerLowest,
        borderRadius: BorderRadius.circular(AppSpacing.radiusLg),
        border: Border.all(color: AppColors.error.withValues(alpha: 0.3)),
      ),
      child: Column(
        mainAxisSize: MainAxisSize.min,
        children: [
          const Icon(Icons.error_outline, size: 44, color: AppColors.error),
          const SizedBox(height: AppSpacing.sm),
          Text(
            'Unable to load inventory',
            style: AppTypography.headlineMd.copyWith(color: AppColors.error),
          ),
          const SizedBox(height: AppSpacing.xs),
          Text(
            '$error',
            textAlign: TextAlign.center,
            style: AppTypography.bodySm.copyWith(
              color: AppColors.onSurfaceVariant,
            ),
          ),
          const SizedBox(height: AppSpacing.md),
          FilledButton.icon(
            onPressed: () => ref.read(inventoryProvider.notifier).fetchInventory(),
            icon: const Icon(Icons.refresh, size: 18),
            label: const Text('Retry'),
            style: FilledButton.styleFrom(
              backgroundColor: AppColors.primary,
              foregroundColor: AppColors.onPrimary,
            ),
          ),
        ],
      ),
    );
  }
}

