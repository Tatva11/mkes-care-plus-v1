import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';

import '../../../core/theme/app_colors.dart';
import '../../../core/theme/app_spacing.dart';
import '../../../core/theme/app_typography.dart';
import '../../auth/providers/auth_provider.dart';
import '../../department/providers/departments_provider.dart';
import '../models/inventory_item.dart';
import '../providers/department_inventory_provider.dart';
import '../providers/inventory_provider.dart';

/// Modal dialog allowing users to request and directly transfer inventory stock to a department.
/// Staff selects a target department and an item; stock is transferred atomically.
class StockRequestFormDialog extends ConsumerStatefulWidget {
  const StockRequestFormDialog({
    super.key,
    this.preselectedInventoryItem,
    this.forcedDepartmentId,
  });

  final InventoryItem? preselectedInventoryItem;
  final String? forcedDepartmentId;

  @override
  ConsumerState<StockRequestFormDialog> createState() =>
      _StockRequestFormDialogState();
}

class _StockRequestFormDialogState
    extends ConsumerState<StockRequestFormDialog> {
  final _formKey = GlobalKey<FormState>();

  InventoryItem? _selectedItem;
  String? _targetDepartmentId;
  final _quantityController = TextEditingController();
  final _notesController = TextEditingController();

  bool _isSubmitting = false;
  String? _errorMessage;

  static const Color _successColor = Color(0xFF2E7D32);

  @override
  void initState() {
    super.initState();
    _selectedItem = widget.preselectedInventoryItem;
    _targetDepartmentId = widget.forcedDepartmentId;
  }

  @override
  void dispose() {
    _quantityController.dispose();
    _notesController.dispose();
    super.dispose();
  }

  double get _enteredQuantity =>
      double.tryParse(_quantityController.text.trim()) ?? 0.0;

  Future<void> _submit() async {
    if (_isSubmitting) return;
    if (!_formKey.currentState!.validate()) return;

    if (_targetDepartmentId == null || _targetDepartmentId!.trim().isEmpty) {
      setState(() => _errorMessage = 'Please select a target department.');
      return;
    }

    if (_selectedItem == null) {
      setState(() => _errorMessage = 'Please select an inventory item.');
      return;
    }

    // Block zero-stock items at UI level
    if (_selectedItem!.currentStock <= 0) {
      setState(() => _errorMessage = 'This item is currently out of stock.');
      return;
    }

    final qty = _enteredQuantity;
    if (qty <= 0) {
      setState(() => _errorMessage = 'Quantity must be greater than zero.');
      return;
    }

    // Client-side check: quantity vs available stock
    if (qty > _selectedItem!.currentStock) {
      setState(() => _errorMessage =
          'Requested quantity exceeds available inventory stock (${_selectedItem!.currentStock} ${_selectedItem!.unit}).');
      return;
    }

    setState(() {
      _isSubmitting = true;
      _errorMessage = null;
    });

    try {
      await ref
          .read(departmentInventoryControllerProvider.notifier)
          .submitAndTransfer(
            inventoryId: _selectedItem!.id,
            requestedQuantity: qty,
            targetDeptId: _targetDepartmentId!,
            notes: _notesController.text.trim().isEmpty
                ? null
                : _notesController.text.trim(),
          );

      if (mounted) {
        ScaffoldMessenger.of(context).showSnackBar(
          const SnackBar(
            content: Text('Stock transferred to department successfully.'),
            backgroundColor: _successColor,
          ),
        );
        Navigator.of(context).pop(true);
      }
    } catch (e) {
      if (mounted) {
        setState(() {
          _isSubmitting = false;
          _errorMessage = e.toString().replaceAll('Exception:', '').trim();
        });
      }
    }
  }

  @override
  Widget build(BuildContext context) {
    final profile = ref.watch(currentProfileProvider).valueOrNull;
    final isAdmin = profile?.role == 'admin';
    final userDeptId = profile?.departmentId;
    final itemsAsync = ref.watch(inventoryProvider);
    final departmentsAsync = ref.watch(departmentsProvider);

    // Default target dept for staff
    _targetDepartmentId ??= userDeptId;

    return Dialog(
      shape: RoundedRectangleBorder(
        borderRadius: BorderRadius.circular(AppSpacing.radiusLg),
      ),
      child: ConstrainedBox(
        constraints: const BoxConstraints(maxWidth: 540),
        child: Padding(
          padding: const EdgeInsets.all(AppSpacing.lg),
          child: Form(
            key: _formKey,
            child: SingleChildScrollView(
              child: Column(
                mainAxisSize: MainAxisSize.min,
                crossAxisAlignment: CrossAxisAlignment.start,
                children: [
                  // Header
                  Row(
                    children: [
                      Container(
                        padding: const EdgeInsets.all(AppSpacing.xs),
                        decoration: BoxDecoration(
                          color: AppColors.primaryContainer.withValues(alpha: 0.2),
                          borderRadius: BorderRadius.circular(AppSpacing.radiusSm),
                        ),
                        child: const Icon(
                          Icons.swap_horiz_outlined,
                          color: AppColors.primary,
                          size: 24,
                        ),
                      ),
                      const SizedBox(width: AppSpacing.md),
                      Expanded(
                        child: Column(
                          crossAxisAlignment: CrossAxisAlignment.start,
                          children: [
                            Text(
                              'Transfer Stock to Department',
                              style: AppTypography.headlineMd.copyWith(
                                fontWeight: FontWeight.bold,
                                fontSize: 20,
                              ),
                            ),
                            const SizedBox(height: 2),
                            Text(
                              'Stock will be transferred immediately from central inventory.',
                              style: AppTypography.bodySm.copyWith(
                                color: AppColors.onSurfaceVariant,
                              ),
                            ),
                          ],
                        ),
                      ),
                      IconButton(
                        icon: const Icon(Icons.close),
                        tooltip: 'Close',
                        onPressed: () => Navigator.of(context).pop(),
                      ),
                    ],
                  ),
                  const SizedBox(height: AppSpacing.md),

                  if (_errorMessage != null) ...[
                    Container(
                      padding: const EdgeInsets.all(AppSpacing.sm),
                      decoration: BoxDecoration(
                        color: AppColors.errorContainer.withValues(alpha: 0.3),
                        borderRadius: BorderRadius.circular(AppSpacing.radiusSm),
                        border: Border.all(color: AppColors.error.withValues(alpha: 0.5)),
                      ),
                      child: Row(
                        children: [
                          const Icon(Icons.error_outline,
                              color: AppColors.error, size: 20),
                          const SizedBox(width: AppSpacing.xs),
                          Expanded(
                            child: Text(
                              _errorMessage!,
                              style: AppTypography.bodySm.copyWith(
                                color: AppColors.error,
                              ),
                            ),
                          ),
                        ],
                      ),
                    ),
                    const SizedBox(height: AppSpacing.md),
                  ],

                  // Department Selector — always shown
                  departmentsAsync.when(
                    loading: () => const LinearProgressIndicator(),
                    error: (e, _) => Text('Error loading departments: $e'),
                    data: (depts) {
                      final activeDepts = depts.where((d) => d.isActive).toList();
                      // For staff, only show their assigned department
                      final availableDepts = isAdmin
                          ? activeDepts
                          : activeDepts.where((d) => d.id == userDeptId).toList();

                      return DropdownButtonFormField<String>(
                        initialValue: _targetDepartmentId,
                        decoration: const InputDecoration(
                          labelText: 'Target Department *',
                          border: OutlineInputBorder(),
                          prefixIcon: Icon(Icons.business_outlined),
                        ),
                        items: availableDepts
                            .map((d) => DropdownMenuItem(
                                  value: d.id,
                                  child: Text(d.name),
                                ))
                            .toList(),
                        onChanged: (val) => setState(() => _targetDepartmentId = val),
                        validator: (val) =>
                            val == null ? 'Select target department' : null,
                      );
                    },
                  ),
                  const SizedBox(height: AppSpacing.md),

                  // Inventory Item Picker — filters out zero-stock items
                  itemsAsync.when(
                    loading: () => const Padding(
                      padding: EdgeInsets.symmetric(vertical: AppSpacing.sm),
                      child: LinearProgressIndicator(),
                    ),
                    error: (e, _) => Text('Error loading inventory: $e'),
                    data: (items) {
                      final activeItems =
                          items.where((i) => i.isActive).toList();
                      return DropdownButtonFormField<String>(
                        initialValue: _selectedItem?.id,
                        isExpanded: true,
                        decoration: const InputDecoration(
                          labelText: 'Select Inventory Item *',
                          border: OutlineInputBorder(),
                          prefixIcon: Icon(Icons.inventory_2_outlined),
                        ),
                        items: activeItems.map((item) {
                          final isOutOfStock = item.currentStock <= 0;
                          final stockDisplay = item.currentStock % 1 == 0
                              ? item.currentStock.toInt().toString()
                              : item.currentStock.toString();
                          return DropdownMenuItem(
                            value: item.id,
                            enabled: !isOutOfStock,
                            child: Row(
                              children: [
                                Expanded(
                                  child: Text(
                                    '${item.name} (${item.unit}) · Stock: $stockDisplay',
                                    overflow: TextOverflow.ellipsis,
                                    style: TextStyle(
                                      color: isOutOfStock
                                          ? AppColors.onSurfaceVariant
                                          : null,
                                    ),
                                  ),
                                ),
                                if (isOutOfStock) ...[
                                  const SizedBox(width: 4),
                                  Container(
                                    padding: const EdgeInsets.symmetric(
                                        horizontal: 6, vertical: 2),
                                    decoration: BoxDecoration(
                                      color: AppColors.errorContainer,
                                      borderRadius: BorderRadius.circular(4),
                                    ),
                                    child: Text(
                                      'OUT OF STOCK',
                                      style: AppTypography.labelCaps.copyWith(
                                        color: AppColors.error,
                                        fontSize: 8,
                                        fontWeight: FontWeight.bold,
                                      ),
                                    ),
                                  ),
                                ],
                              ],
                            ),
                          );
                        }).toList(),
                        onChanged: (itemId) {
                          if (itemId == null) return;
                          final item = activeItems
                              .firstWhere((i) => i.id == itemId);
                          setState(() {
                            _selectedItem = item;
                            _errorMessage = null;
                          });
                        },
                        validator: (val) =>
                            val == null ? 'Select an inventory item' : null,
                      );
                    },
                  ),
                  const SizedBox(height: AppSpacing.md),

                  // Requested Quantity
                  TextFormField(
                    controller: _quantityController,
                    keyboardType: const TextInputType.numberWithOptions(
                        decimal: true),
                    decoration: InputDecoration(
                      labelText: 'Quantity to Transfer *',
                      border: const OutlineInputBorder(),
                      prefixIcon: const Icon(Icons.numbers_outlined),
                      suffixText: _selectedItem?.unit ?? 'units',
                      helperText: _selectedItem != null
                          ? 'Central available: ${_selectedItem!.currentStock} ${_selectedItem!.unit}'
                          : null,
                    ),
                    validator: (val) {
                      if (val == null || val.trim().isEmpty) {
                        return 'Enter quantity';
                      }
                      final n = double.tryParse(val.trim());
                      if (n == null || n <= 0) {
                        return 'Quantity must be greater than zero';
                      }
                      if (_selectedItem != null && n > _selectedItem!.currentStock) {
                        return 'Exceeds available stock (${_selectedItem!.currentStock} ${_selectedItem!.unit})';
                      }
                      return null;
                    },
                  ),
                  const SizedBox(height: AppSpacing.md),

                  // Optional Notes / Reason
                  TextFormField(
                    controller: _notesController,
                    maxLines: 2,
                    decoration: const InputDecoration(
                      labelText: 'Notes / Reason (Optional)',
                      border: OutlineInputBorder(),
                      hintText: 'e.g. Routine clinic restock, high procedure demand',
                      prefixIcon: Icon(Icons.note_alt_outlined),
                    ),
                  ),
                  const SizedBox(height: AppSpacing.lg),

                  // Info banner
                  Container(
                    width: double.infinity,
                    padding: const EdgeInsets.all(AppSpacing.sm),
                    decoration: BoxDecoration(
                      color: Colors.blue.shade50,
                      borderRadius: BorderRadius.circular(AppSpacing.radiusSm),
                      border: Border.all(color: Colors.blue.shade200),
                    ),
                    child: Row(
                      children: [
                        Icon(Icons.info_outline, size: 16, color: Colors.blue.shade700),
                        const SizedBox(width: AppSpacing.xs),
                        Expanded(
                          child: Text(
                            'Stock will be deducted from central inventory and added to the department immediately.',
                            style: AppTypography.bodySm.copyWith(
                              color: Colors.blue.shade700,
                            ),
                          ),
                        ),
                      ],
                    ),
                  ),
                  const SizedBox(height: AppSpacing.md),

                  // Actions
                  Row(
                    mainAxisAlignment: MainAxisAlignment.end,
                    children: [
                      TextButton(
                        onPressed: _isSubmitting
                            ? null
                            : () => Navigator.of(context).pop(),
                        child: const Text('Cancel'),
                      ),
                      const SizedBox(width: AppSpacing.sm),
                      FilledButton.icon(
                        onPressed: _isSubmitting ? null : _submit,
                        icon: _isSubmitting
                            ? const SizedBox(
                                width: 16,
                                height: 16,
                                child: CircularProgressIndicator(
                                  strokeWidth: 2,
                                  color: Colors.white,
                                ),
                              )
                            : const Icon(Icons.swap_horiz, size: 18),
                        label: Text(_isSubmitting
                            ? 'Transferring...'
                            : 'Transfer Stock'),
                      ),
                    ],
                  ),
                ],
              ),
            ),
          ),
        ),
      ),
    );
  }
}
