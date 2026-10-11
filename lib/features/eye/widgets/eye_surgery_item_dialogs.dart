import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';

import '../../../core/theme/app_colors.dart';
import '../../../core/theme/app_spacing.dart';
import '../../../core/theme/app_typography.dart';
import '../../../features/inventory/models/inventory_item.dart';
import '../../../features/inventory/providers/inventory_provider.dart';
import '../../../features/inventory/repositories/inventory_repository.dart';
import '../../../features/inventory/screens/purchase_order_list_screen.dart';
import '../models/eye_surgery_model.dart';
import '../models/eye_surgery_item_model.dart';
import '../providers/eye_surgery_provider.dart';

bool isEyeSurgeryInventoryItemSelectable(InventoryItem item) =>
    item.isActive && item.currentStock > 0;

Future<InventoryItem?> fetchSelectableEyeSurgeryInventoryItem({
  required InventoryRepository repository,
  required String itemId,
}) async {
  final freshItems = await repository.getInventoryItems(activeOnly: true);
  final item = freshItems.where((entry) => entry.id == itemId).firstOrNull;
  return item != null && isEyeSurgeryInventoryItemSelectable(item)
      ? item
      : null;
}

DropdownMenuItem<String> eyeSurgeryInventoryMenuItem(InventoryItem item) =>
    DropdownMenuItem<String>(
      value: item.id,
      enabled: isEyeSurgeryInventoryItemSelectable(item),
      child: Text(
        item.currentStock > 0
            ? '${item.name} · Stock ${item.formattedStock}'
            : '${item.name} - Out of Stock',
        overflow: TextOverflow.ellipsis,
      ),
    );

void openEyeSurgeryPurchaseOrders(BuildContext context) {
  final navigator = Navigator.of(context);
  final route = navigator.widget.onGenerateRoute?.call(
    const RouteSettings(name: '/purchase-orders'),
  );
  if (route != null) {
    navigator.push(route);
  } else {
    navigator.push(
      MaterialPageRoute<void>(
        settings: const RouteSettings(name: '/purchase-orders'),
        builder: (_) => const PurchaseOrderManagementScreen(),
      ),
    );
  }
}

/// Standalone, reliable Inventory Item Picker dialog.
/// Opens when "Add Inventory Item" is pressed.
class EyeSurgeryInventoryPickerDialog extends ConsumerStatefulWidget {
  const EyeSurgeryInventoryPickerDialog({
    super.key,
    this.excludedItemIds = const <String>{},
  });

  final Set<String> excludedItemIds;

  static Future<List<({InventoryItem item, double quantity})>?> show(
    BuildContext context, {
    Set<String> excludedItemIds = const <String>{},
  }) {
    return showDialog<List<({InventoryItem item, double quantity})>>(
      context: context,
      barrierDismissible: true,
      builder: (_) => EyeSurgeryInventoryPickerDialog(
        excludedItemIds: excludedItemIds,
      ),
    );
  }

  @override
  ConsumerState<EyeSurgeryInventoryPickerDialog> createState() =>
      _EyeSurgeryInventoryPickerDialogState();
}

class _EyeSurgeryInventoryPickerDialogState
    extends ConsumerState<EyeSurgeryInventoryPickerDialog> {
  final _searchController = TextEditingController();
  final Map<String, ({InventoryItem item, double quantity})> _selectedItems = {};
  bool _validating = false;
  String? _errorMessage;

  @override
  void dispose() {
    _searchController.dispose();
    super.dispose();
  }

  Future<void> _confirmSelection() async {
    if (_selectedItems.isEmpty) return;

    setState(() {
      _validating = true;
      _errorMessage = null;
    });

    try {
      final repo = ref.read(inventoryRepositoryProvider);
      final validatedList = <({InventoryItem item, double quantity})>[];

      // Revalidate EVERY selected item before adding
      for (final entry in _selectedItems.values) {
        final freshItem = await fetchSelectableEyeSurgeryInventoryItem(
          repository: repo,
          itemId: entry.item.id,
        );

        if (freshItem == null || freshItem.currentStock <= 0) {
          if (mounted) {
            setState(() {
              _validating = false;
              _errorMessage =
                  '${entry.item.name} is Out of Stock. Cannot add batch with unavailable items.';
            });
          }
          return; // Do NOT partially add!
        }

        if (freshItem.currentStock < entry.quantity) {
          if (mounted) {
            setState(() {
              _validating = false;
              _errorMessage =
                  '${entry.item.name} only has ${freshItem.formattedStock} available (requested ${entry.quantity}).';
            });
          }
          return; // Do NOT partially add!
        }

        validatedList.add((item: freshItem, quantity: entry.quantity));
      }

      if (mounted) {
        Navigator.of(context).pop(validatedList);
      }
    } catch (e) {
      if (mounted) {
        setState(() {
          _validating = false;
          _errorMessage = 'Unable to validate stock: $e';
        });
      }
    }
  }

  void _toggleItem(InventoryItem item) {
    setState(() {
      _errorMessage = null;
      if (_selectedItems.containsKey(item.id)) {
        _selectedItems.remove(item.id);
      } else {
        _selectedItems[item.id] = (item: item, quantity: 1.0);
      }
    });
  }

  @override
  Widget build(BuildContext context) {
    final inventoryAsync = ref.watch(inventoryProvider);
    final size = MediaQuery.sizeOf(context);
    final searchQuery = _searchController.text.trim().toLowerCase();

    return Dialog(
      insetPadding: const EdgeInsets.symmetric(horizontal: 16, vertical: 24),
      child: ConstrainedBox(
        constraints: BoxConstraints(
          maxWidth: (size.width - 32).clamp(320.0, 640.0),
          maxHeight: (size.height - 48).clamp(400.0, 720.0),
        ),
        child: Column(
          children: [
            ListTile(
              title: const Text('Add Inventory Item'),
              subtitle: const Text('Select a product to add to surgery'),
              trailing: IconButton(
                tooltip: 'Close',
                icon: const Icon(Icons.close),
                onPressed: () => Navigator.of(context).pop(),
              ),
            ),
            const Divider(height: 1),
            Padding(
              padding: const EdgeInsets.all(AppSpacing.md),
              child: TextField(
                controller: _searchController,
                onChanged: (_) => setState(() {}),
                decoration: InputDecoration(
                  hintText: 'Search product name, category, or SKU...',
                  prefixIcon: const Icon(Icons.search),
                  suffixIcon: _searchController.text.isNotEmpty
                      ? IconButton(
                          icon: const Icon(Icons.clear),
                          onPressed: () => setState(() => _searchController.clear()),
                        )
                      : null,
                  border: const OutlineInputBorder(),
                  isDense: true,
                ),
              ),
            ),
            if (_errorMessage != null)
              Container(
                margin: const EdgeInsets.symmetric(
                    horizontal: AppSpacing.md, vertical: AppSpacing.xs),
                padding: const EdgeInsets.all(AppSpacing.sm),
                decoration: BoxDecoration(
                  color: AppColors.error.withValues(alpha: 0.1),
                  borderRadius: BorderRadius.circular(AppSpacing.radiusSm),
                ),
                child: Row(
                  children: [
                    const Icon(Icons.error_outline, color: AppColors.error, size: 20),
                    const SizedBox(width: AppSpacing.sm),
                    Expanded(
                      child: Text(
                        _errorMessage!,
                        style: const TextStyle(color: AppColors.error, fontSize: 13),
                      ),
                    ),
                    TextButton(
                      onPressed: () => openEyeSurgeryPurchaseOrders(context),
                      child: const Text('Go to Purchase Orders'),
                    ),
                  ],
                ),
              ),
            Expanded(
              child: inventoryAsync.when(
                loading: () => const Center(child: CircularProgressIndicator()),
                error: (err, _) => Center(
                  child: Column(
                    mainAxisSize: MainAxisSize.min,
                    children: [
                      Text('Unable to load inventory: $err'),
                      TextButton.icon(
                        onPressed: () => ref.read(inventoryProvider.notifier).refresh(),
                        icon: const Icon(Icons.refresh),
                        label: const Text('Retry'),
                      ),
                    ],
                  ),
                ),
                data: (items) {
                  final activeItems = items.where((i) => i.isActive).toList();
                  final filtered = activeItems.where((i) {
                    if (searchQuery.isEmpty) return true;
                    return i.name.toLowerCase().contains(searchQuery) ||
                        i.category.toLowerCase().contains(searchQuery) ||
                        (i.sku != null && i.sku!.toLowerCase().contains(searchQuery));
                  }).toList()
                    ..sort((a, b) {
                      final aInStock = a.currentStock > 0 ? 0 : 1;
                      final bInStock = b.currentStock > 0 ? 0 : 1;
                      if (aInStock != bInStock) return aInStock.compareTo(bInStock);
                      return a.name.compareTo(b.name);
                    });

                  if (filtered.isEmpty) {
                    return Center(
                      child: Text(
                        searchQuery.isEmpty
                            ? 'No active inventory items found.'
                            : 'No items match "$searchQuery".',
                        style: const TextStyle(color: AppColors.onSurfaceVariant),
                      ),
                    );
                  }

                  return ListView.separated(
                    padding: const EdgeInsets.symmetric(horizontal: AppSpacing.md),
                    itemCount: filtered.length,
                    separatorBuilder: (_, __) => const Divider(height: 1),
                    itemBuilder: (context, index) {
                      final item = filtered[index];
                      final isOutOfStock = item.currentStock <= 0;
                      final isAlreadyInSurgery = widget.excludedItemIds.contains(item.id);
                      final isSelected = _selectedItems.containsKey(item.id);

                      return ListTile(
                        dense: true,
                        contentPadding: const EdgeInsets.symmetric(horizontal: 8, vertical: 4),
                        leading: isOutOfStock || isAlreadyInSurgery
                            ? const Checkbox(value: false, onChanged: null)
                            : Checkbox(
                                value: isSelected,
                                activeColor: AppColors.primary,
                                onChanged: (_) => _toggleItem(item),
                              ),
                        title: Text(
                          item.name,
                          style: TextStyle(
                            fontWeight: isSelected ? FontWeight.bold : FontWeight.w600,
                            color: (isOutOfStock || isAlreadyInSurgery) ? AppColors.onSurfaceVariant : null,
                          ),
                        ),
                        subtitle: Wrap(
                          spacing: 6,
                          runSpacing: 4,
                          crossAxisAlignment: WrapCrossAlignment.center,
                          children: [
                            if (isAlreadyInSurgery)
                              Container(
                                padding: const EdgeInsets.symmetric(horizontal: 6, vertical: 2),
                                decoration: BoxDecoration(
                                  color: Colors.grey.withValues(alpha: 0.2),
                                  borderRadius: BorderRadius.circular(4),
                                ),
                                child: const Text(
                                  'Already in Surgery',
                                  style: TextStyle(fontSize: 11, fontWeight: FontWeight.w600),
                                ),
                              )
                            else if (isOutOfStock) ...[
                              Container(
                                padding: const EdgeInsets.symmetric(horizontal: 6, vertical: 2),
                                decoration: BoxDecoration(
                                  color: AppColors.error.withValues(alpha: 0.15),
                                  borderRadius: BorderRadius.circular(4),
                                ),
                                child: const Text(
                                  'Out of Stock',
                                  style: TextStyle(
                                    color: AppColors.error,
                                    fontSize: 11,
                                    fontWeight: FontWeight.bold,
                                  ),
                                ),
                              ),
                              TextButton.icon(
                                style: TextButton.styleFrom(
                                  visualDensity: VisualDensity.compact,
                                  padding: const EdgeInsets.symmetric(horizontal: 6),
                                ),
                                onPressed: () => openEyeSurgeryPurchaseOrders(context),
                                icon: const Icon(Icons.receipt_long_outlined, size: 14),
                                label: const Text('Go to Purchase Orders', style: TextStyle(fontSize: 11)),
                              ),
                            ] else
                              Text(
                                'Stock: ${item.formattedStock} ${item.unit}',
                                style: const TextStyle(fontSize: 12),
                              ),
                            if (item.sku != null && item.sku!.isNotEmpty)
                              Text('· SKU: ${item.sku}',
                                  style: const TextStyle(
                                      fontSize: 12,
                                      color: AppColors.onSurfaceVariant)),
                          ],
                        ),
                        onTap: isOutOfStock || isAlreadyInSurgery
                            ? null
                            : () => _toggleItem(item),
                      );
                    },
                  );
                },
              ),
            ),
            const Divider(height: 1),
            Padding(
              padding: const EdgeInsets.all(AppSpacing.md),
              child: Wrap(
                alignment: WrapAlignment.spaceBetween,
                crossAxisAlignment: WrapCrossAlignment.center,
                spacing: AppSpacing.sm,
                runSpacing: AppSpacing.xs,
                children: [
                  if (_selectedItems.isNotEmpty)
                    Text(
                      '${_selectedItems.length} selected',
                      style: const TextStyle(fontWeight: FontWeight.bold),
                    )
                  else
                    const SizedBox.shrink(),
                  Row(
                    mainAxisSize: MainAxisSize.min,
                    children: [
                      TextButton(
                        onPressed: () => Navigator.of(context).pop(),
                        child: const Text('Cancel'),
                      ),
                      const SizedBox(width: AppSpacing.sm),
                      FilledButton.icon(
                        onPressed: _selectedItems.isEmpty || _validating ? null : _confirmSelection,
                        icon: _validating
                            ? const SizedBox.square(
                                dimension: 16,
                                child: CircularProgressIndicator(strokeWidth: 2, color: Colors.white))
                            : const Icon(Icons.add),
                        label: Text(
                          _selectedItems.isEmpty
                              ? 'Add Selected Items'
                              : 'Add Selected Items (${_selectedItems.length})',
                        ),
                      ),
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
}

class EyeSurgeryItemsDialog extends ConsumerStatefulWidget {
  const EyeSurgeryItemsDialog({super.key, required this.surgery});

  final EyeSurgeryModel surgery;

  @override
  ConsumerState<EyeSurgeryItemsDialog> createState() =>
      _EyeSurgeryItemsDialogState();
}

class _EyeSurgeryItemsDialogState extends ConsumerState<EyeSurgeryItemsDialog> {
  String? _selectedInventoryId;
  final _quantityController = TextEditingController(text: '1');
  bool _saving = false;
  bool _showPurchaseOrdersAction = false;

  bool get _locked => widget.surgery.inventoryConsumedAt != null;

  @override
  void dispose() {
    _quantityController.dispose();
    super.dispose();
  }

  Future<void> _openInventoryPicker() async {
    final existingItems =
        ref.read(eyeSurgeryItemsProvider(widget.surgery.id)).valueOrNull ?? [];
    final excluded = existingItems.map((i) => i.inventoryItemId).toSet();
    final result = await EyeSurgeryInventoryPickerDialog.show(
      context,
      excludedItemIds: excluded,
    );
    if (result == null || result.isEmpty) return;
    setState(() => _saving = true);
    try {
      await ref
          .read(eyeSurgeryItemsProvider(widget.surgery.id).notifier)
          .addItems(
            result
                .map((r) => (
                      inventoryItemId: r.item.id,
                      plannedQuantity: r.quantity,
                      source: 'manual',
                    ))
                .toList(),
          );
    } catch (error) {
      _showError('Unable to add items: $error');
    } finally {
      if (mounted) setState(() => _saving = false);
    }
  }

  Future<void> _addItem() async {
    final inventoryId = _selectedInventoryId;
    final quantity = double.tryParse(_quantityController.text.trim());
    if (inventoryId == null || quantity == null || quantity <= 0) return;
    setState(() => _saving = true);
    try {
      final freshItem = await fetchSelectableEyeSurgeryInventoryItem(
        repository: ref.read(inventoryRepositoryProvider),
        itemId: inventoryId,
      );
      if (freshItem == null) {
        if (mounted) {
          setState(() => _showPurchaseOrdersAction = true);
          _showOutOfStockError();
        }
        return;
      }
      await ref
          .read(eyeSurgeryItemsProvider(widget.surgery.id).notifier)
          .addItem(
            inventoryItemId: inventoryId,
            plannedQuantity: quantity,
          );
      _quantityController.text = '1';
    } catch (error) {
      _showError('Unable to add item: $error');
    } finally {
      if (mounted) setState(() => _saving = false);
    }
  }

  Future<void> _editItem(EyeSurgeryItemModel item) async {
    final result = await showDialog<({double planned, double actual})>(
      context: context,
      builder: (_) => _EditSurgeryItemDialog(item: item),
    );
    if (result == null) return;
    setState(() => _saving = true);
    try {
      await ref
          .read(eyeSurgeryItemsProvider(widget.surgery.id).notifier)
          .updateItem(
            itemId: item.id,
            plannedQuantity: result.planned,
            actualQuantity: result.actual,
          );
    } catch (error) {
      _showError('Unable to update item: $error');
    } finally {
      if (mounted) setState(() => _saving = false);
    }
  }

  Future<void> _removeItem(EyeSurgeryItemModel item) async {
    setState(() => _saving = true);
    try {
      await ref
          .read(eyeSurgeryItemsProvider(widget.surgery.id).notifier)
          .removeItem(item.id);
    } catch (error) {
      _showError('Unable to remove item: $error');
    } finally {
      if (mounted) setState(() => _saving = false);
    }
  }

  void _showError(String message) {
    if (!mounted) return;
    ScaffoldMessenger.of(context)
        .showSnackBar(SnackBar(content: Text(message)));
  }

  void _showOutOfStockError() {
    ScaffoldMessenger.of(context).showSnackBar(
      SnackBar(
        content: const Text('This inventory item is Out of Stock.'),
        action: SnackBarAction(
          label: 'Go to Purchase Orders',
          onPressed: () => openEyeSurgeryPurchaseOrders(context),
        ),
      ),
    );
  }

  @override
  Widget build(BuildContext context) {
    final size = MediaQuery.sizeOf(context);
    final itemsAsync = ref.watch(eyeSurgeryItemsProvider(widget.surgery.id));
    final inventoryAsync = ref.watch(inventoryProvider);
    final inventoryItems =
        inventoryAsync.valueOrNull ?? const <InventoryItem>[];
    final availableInventory = inventoryItems
        .where((item) => item.isActive)
        .toList()
      ..sort((a, b) => a.name.compareTo(b.name));
    final selectedItem = availableInventory
        .where((item) => item.id == _selectedInventoryId)
        .firstOrNull;
    final validInventoryId = selectedItem != null &&
            isEyeSurgeryInventoryItemSelectable(selectedItem)
        ? _selectedInventoryId
        : null;
    final hasOutOfStockItems =
        availableInventory.any((item) => item.currentStock <= 0);
    if (_selectedInventoryId != null && validInventoryId == null) {
      WidgetsBinding.instance.addPostFrameCallback((_) {
        if (mounted && _selectedInventoryId != null) {
          setState(() {
            _selectedInventoryId = null;
            _showPurchaseOrdersAction = true;
          });
        }
      });
    }
    final purchaseOrdersButton = OutlinedButton.icon(
      onPressed: () => openEyeSurgeryPurchaseOrders(context),
      icon: const Icon(Icons.receipt_long_outlined),
      label: const Text('Go to Purchase Orders'),
    );

    return Dialog(
      insetPadding: const EdgeInsets.all(12),
      child: ConstrainedBox(
        constraints: BoxConstraints(
          maxWidth: (size.width - 24).clamp(280.0, 680.0),
          maxHeight: (size.height - 24).clamp(320.0, 760.0),
        ),
        child: Column(
          children: [
            ListTile(
              title: const Text('Customize Surgery Items & Supplies'),
              subtitle: Text(
                '${widget.surgery.patientName ?? "Patient"} · ${widget.surgery.displaySurgeryType}',
              ),
              trailing: IconButton(
                tooltip: 'Close',
                onPressed: () => Navigator.pop(context),
                icon: const Icon(Icons.close),
              ),
            ),
            const Divider(height: 1),
            if (_locked)
              const ListTile(
                dense: true,
                leading: Icon(Icons.lock_outline),
                title: Text('Inventory has been consumed; items are locked.'),
              ),
            Expanded(
              child: itemsAsync.when(
                loading: () => const Center(child: CircularProgressIndicator()),
                error: (error, _) => Center(
                  child: TextButton.icon(
                    onPressed: () => ref
                        .invalidate(eyeSurgeryItemsProvider(widget.surgery.id)),
                    icon: const Icon(Icons.refresh),
                    label: Text('Unable to load items: $error'),
                  ),
                ),
                data: (items) => items.isEmpty
                    ? const Center(child: Text('No inventory items selected.'))
                    : ListView.separated(
                        padding: const EdgeInsets.all(AppSpacing.md),
                        itemCount: items.length,
                        separatorBuilder: (_, __) =>
                            const SizedBox(height: AppSpacing.xs),
                        itemBuilder: (context, index) => _SurgeryItemTile(
                          item: items[index],
                          locked: _locked || _saving,
                          onEdit: () => _editItem(items[index]),
                          onRemove: () => _removeItem(items[index]),
                        ),
                      ),
              ),
            ),
            if (!_locked) ...[
              const Divider(height: 1),
              Padding(
                padding: const EdgeInsets.all(AppSpacing.md),
                child: Column(
                  crossAxisAlignment: CrossAxisAlignment.stretch,
                  children: [
                    FilledButton.icon(
                      onPressed: _saving ? null : _openInventoryPicker,
                      icon: const Icon(Icons.add),
                      label: const Text('Add Inventory Item'),
                    ),
                    const SizedBox(height: AppSpacing.sm),
                    LayoutBuilder(
                      builder: (context, constraints) {
                        final itemPicker = DropdownButtonFormField<String>(
                          key: ValueKey(validInventoryId),
                          initialValue: validInventoryId,
                          isExpanded: true,
                          decoration: const InputDecoration(
                            labelText: 'Quick select inventory item',
                            border: OutlineInputBorder(),
                            isDense: true,
                          ),
                          items: availableInventory
                              .map(eyeSurgeryInventoryMenuItem)
                              .toList(),
                          onChanged: _saving
                              ? null
                              : (value) => setState(
                                    () => _selectedInventoryId = value,
                                  ),
                        );
                        final quantity = TextField(
                          controller: _quantityController,
                          keyboardType:
                              const TextInputType.numberWithOptions(decimal: true),
                          decoration: const InputDecoration(
                            labelText: 'Quantity',
                            border: OutlineInputBorder(),
                            isDense: true,
                          ),
                        );
                        final add = OutlinedButton.icon(
                          onPressed: _saving ? null : _addItem,
                          icon: _saving
                              ? const SizedBox.square(
                                  dimension: 16,
                                  child: CircularProgressIndicator(strokeWidth: 2),
                                )
                              : const Icon(Icons.add_shopping_cart, size: 18),
                          label: const Text('Add Quick Item'),
                        );
                        if (constraints.maxWidth < 440) {
                          return Column(
                            crossAxisAlignment: CrossAxisAlignment.stretch,
                            children: [
                              itemPicker,
                              if (hasOutOfStockItems ||
                                  _showPurchaseOrdersAction) ...[
                                const SizedBox(height: AppSpacing.xs),
                                purchaseOrdersButton,
                              ],
                              const SizedBox(height: AppSpacing.xs),
                              quantity,
                              const SizedBox(height: AppSpacing.xs),
                              add,
                            ],
                          );
                        }
                        return Column(
                          crossAxisAlignment: CrossAxisAlignment.stretch,
                          children: [
                            itemPicker,
                            if (hasOutOfStockItems ||
                                _showPurchaseOrdersAction) ...[
                              const SizedBox(height: AppSpacing.xs),
                              Align(
                                alignment: Alignment.centerLeft,
                                child: purchaseOrdersButton,
                              ),
                            ],
                            const SizedBox(height: AppSpacing.xs),
                            Row(
                              children: [
                                SizedBox(width: 120, child: quantity),
                                const SizedBox(width: AppSpacing.sm),
                                Expanded(child: add),
                              ],
                            ),
                          ],
                        );
                      },
                    ),
                  ],
                ),
              ),
            ],
          ],
        ),
      ),
    );
  }
}

class _SurgeryItemTile extends StatelessWidget {
  const _SurgeryItemTile({
    required this.item,
    required this.locked,
    required this.onEdit,
    required this.onRemove,
  });

  final EyeSurgeryItemModel item;
  final bool locked;
  final VoidCallback onEdit;
  final VoidCallback onRemove;

  @override
  Widget build(BuildContext context) {
    final isOutOfStock = item.currentStock <= 0;

    return Card(
      margin: EdgeInsets.zero,
      child: ListTile(
        title: Text(item.inventoryItemName, overflow: TextOverflow.ellipsis),
        subtitle: Column(
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            Text(
              'Required: ${item.requiredQuantity} ${item.unit} · Current stock ${item.currentStock} ${item.unit} · ${item.source == 'template' ? 'Preset' : 'Manual'}',
            ),
            if (isOutOfStock) ...[
              const SizedBox(height: 4),
              Row(
                children: [
                  Container(
                    padding: const EdgeInsets.symmetric(horizontal: 6, vertical: 2),
                    decoration: BoxDecoration(
                      color: AppColors.error.withValues(alpha: 0.15),
                      borderRadius: BorderRadius.circular(4),
                    ),
                    child: const Text(
                      'Out of Stock',
                      style: TextStyle(
                        color: AppColors.error,
                        fontSize: 11,
                        fontWeight: FontWeight.bold,
                      ),
                    ),
                  ),
                  const SizedBox(width: 8),
                  TextButton.icon(
                    style: TextButton.styleFrom(visualDensity: VisualDensity.compact),
                    onPressed: () => openEyeSurgeryPurchaseOrders(context),
                    icon: const Icon(Icons.receipt_long_outlined, size: 14),
                    label: const Text('Go to Purchase Orders', style: TextStyle(fontSize: 11)),
                  ),
                ],
              ),
            ],
          ],
        ),
        isThreeLine: isOutOfStock,
        trailing: locked
            ? const Icon(Icons.lock_outline)
            : PopupMenuButton<String>(
                tooltip: 'Surgery item actions',
                onSelected: (action) {
                  if (action == 'edit') onEdit();
                  if (action == 'remove') onRemove();
                },
                itemBuilder: (_) => const [
                  PopupMenuItem(
                      value: 'edit', child: Text('Edit required quantity')),
                  PopupMenuItem(value: 'remove', child: Text('Remove item')),
                ],
              ),
      ),
    );
  }
}

class _EditSurgeryItemDialog extends StatefulWidget {
  const _EditSurgeryItemDialog({required this.item});

  final EyeSurgeryItemModel item;

  @override
  State<_EditSurgeryItemDialog> createState() => _EditSurgeryItemDialogState();
}

class _EditSurgeryItemDialogState extends State<_EditSurgeryItemDialog> {
  late final _quantityController =
      TextEditingController(text: '${widget.item.requiredQuantity}');

  @override
  void dispose() {
    _quantityController.dispose();
    super.dispose();
  }

  @override
  Widget build(BuildContext context) => AlertDialog(
        title: Text(widget.item.inventoryItemName),
        content: Column(
          mainAxisSize: MainAxisSize.min,
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            Text(
              'Current Central Stock: ${widget.item.currentStock} ${widget.item.unit}',
              style: AppTypography.bodySm.copyWith(color: AppColors.onSurfaceVariant),
            ),
            const SizedBox(height: AppSpacing.sm),
            TextField(
              controller: _quantityController,
              keyboardType:
                  const TextInputType.numberWithOptions(decimal: true),
              decoration: InputDecoration(
                labelText: 'Required quantity (${widget.item.unit})',
                border: const OutlineInputBorder(),
              ),
              autofocus: true,
            ),
          ],
        ),
        actions: [
          TextButton(
              onPressed: () => Navigator.pop(context),
              child: const Text('Cancel')),
          FilledButton(
            onPressed: () {
              final qty = double.tryParse(_quantityController.text.trim());
              if (qty == null || qty <= 0) {
                return;
              }
              Navigator.pop(context, (planned: qty, actual: qty));
            },
            child: const Text('Save'),
          ),
        ],
      );
}

/// Responsive, Admin-controlled preset manager for default Eye Surgery inventory items.
///
/// Supports all 6 surgery types (Cataract, LASIK/Refractive, Glaucoma, Retinal, Corneal, Other).
/// Admin can configure default inventory items and required quantities per surgery type.
/// Viewing or modifying presets never deducts central inventory stock.
class SurgeryInventoryPresetsDialog extends ConsumerStatefulWidget {
  const SurgeryInventoryPresetsDialog({
    super.key,
    this.initialSurgeryType,
  });

  final String? initialSurgeryType;

  @override
  ConsumerState<SurgeryInventoryPresetsDialog> createState() =>
      _SurgeryInventoryPresetsDialogState();
}

class _SurgeryInventoryPresetsDialogState
    extends ConsumerState<SurgeryInventoryPresetsDialog> {
  late String _selectedSurgeryType;
  String? _selectedInventoryId;
  final _quantityController = TextEditingController(text: '1');
  bool _saving = false;

  @override
  void initState() {
    super.initState();
    _selectedSurgeryType = widget.initialSurgeryType ??
        EyeSurgeryModel.surgeryTypeOptions.first;
  }

  @override
  void dispose() {
    _quantityController.dispose();
    super.dispose();
  }

  Future<void> _savePresetItem() async {
    final inventoryId = _selectedInventoryId;
    final quantity = double.tryParse(_quantityController.text.trim());
    if (inventoryId == null || quantity == null || quantity <= 0) {
      _showError('Please select an item and enter a valid quantity greater than zero.');
      return;
    }
    setState(() => _saving = true);
    try {
      await ref.read(eyeSurgeryRepositoryProvider).saveItemTemplate(
            surgeryType: _selectedSurgeryType,
            inventoryItemId: inventoryId,
            defaultQuantity: quantity,
          );
      ref.invalidate(allEyeSurgeryItemTemplatesProvider);
      ref.invalidate(eyeSurgeryItemTemplatesProvider(_selectedSurgeryType));
      setState(() {
        _selectedInventoryId = null;
        _quantityController.text = '1';
      });
      if (mounted) {
        ScaffoldMessenger.of(context).showSnackBar(
          const SnackBar(
            content: Text('Preset item saved successfully.'),
            duration: Duration(seconds: 2),
          ),
        );
      }
    } catch (error) {
      _showError('Unable to save preset item: $error');
    } finally {
      if (mounted) setState(() => _saving = false);
    }
  }

  Future<void> _editQuantity(EyeSurgeryItemTemplateModel item) async {
    final controller = TextEditingController(text: '${item.defaultQuantity}');
    final newQty = await showDialog<double>(
      context: context,
      builder: (ctx) => AlertDialog(
        title: Text('Edit Default Quantity: ${item.inventoryItemName}'),
        content: TextField(
          controller: controller,
          keyboardType: const TextInputType.numberWithOptions(decimal: true),
          decoration: InputDecoration(
            labelText: 'Required Quantity (${item.unit})',
            border: const OutlineInputBorder(),
          ),
          autofocus: true,
        ),
        actions: [
          TextButton(
            onPressed: () => Navigator.pop(ctx),
            child: const Text('Cancel'),
          ),
          FilledButton(
            onPressed: () {
              final val = double.tryParse(controller.text.trim());
              if (val != null && val > 0) Navigator.pop(ctx, val);
            },
            child: const Text('Save'),
          ),
        ],
      ),
    );

    if (newQty != null && newQty > 0) {
      setState(() => _saving = true);
      try {
        await ref.read(eyeSurgeryRepositoryProvider).saveItemTemplate(
              surgeryType: item.surgeryType,
              inventoryItemId: item.inventoryItemId,
              defaultQuantity: newQty,
            );
        ref.invalidate(allEyeSurgeryItemTemplatesProvider);
        ref.invalidate(eyeSurgeryItemTemplatesProvider(item.surgeryType));
      } catch (e) {
        _showError('Unable to update quantity: $e');
      } finally {
        if (mounted) setState(() => _saving = false);
      }
    }
  }

  Future<void> _removeItem(EyeSurgeryItemTemplateModel item) async {
    setState(() => _saving = true);
    try {
      await ref.read(eyeSurgeryRepositoryProvider).deleteItemTemplate(item.id);
      ref.invalidate(allEyeSurgeryItemTemplatesProvider);
      ref.invalidate(eyeSurgeryItemTemplatesProvider(item.surgeryType));
    } catch (error) {
      _showError('Unable to remove preset item: $error');
    } finally {
      if (mounted) setState(() => _saving = false);
    }
  }

  void _showError(String message) {
    if (!mounted) return;
    ScaffoldMessenger.of(context).showSnackBar(
      SnackBar(content: Text(message), backgroundColor: AppColors.error),
    );
  }

  @override
  Widget build(BuildContext context) {
    final inventory =
        ref.watch(inventoryProvider).valueOrNull ?? const <InventoryItem>[];
    final templatesAsync = ref.watch(allEyeSurgeryItemTemplatesProvider);
    final size = MediaQuery.sizeOf(context);
    final insets = MediaQuery.viewInsetsOf(context);
    final isCompact = size.width < 600;

    return Dialog(
      insetPadding: EdgeInsets.all(isCompact ? 8 : 16),
      shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(AppSpacing.radiusLg)),
      child: ConstrainedBox(
        constraints: BoxConstraints(
          maxWidth: (size.width - 24).clamp(320.0, 780.0),
          maxHeight: (size.height - insets.bottom - 24).clamp(320.0, 820.0),
        ),
        child: Column(
          crossAxisAlignment: CrossAxisAlignment.stretch,
          children: [
            // ── Dialog Header ──────────────────────────────────────────
            Padding(
              padding: const EdgeInsets.fromLTRB(AppSpacing.lg, AppSpacing.md, AppSpacing.sm, AppSpacing.sm),
              child: Row(
                children: [
                  const Icon(Icons.inventory_2_outlined, color: AppColors.primary, size: 24),
                  const SizedBox(width: AppSpacing.sm),
                  Expanded(
                    child: Column(
                      crossAxisAlignment: CrossAxisAlignment.start,
                      children: [
                        Text(
                          'Surgery Inventory Presets',
                          style: AppTypography.headlineMd.copyWith(fontSize: 18),
                        ),
                        Text(
                          'Configure default items per surgery type',
                          style: AppTypography.bodySm.copyWith(color: AppColors.onSurfaceVariant),
                        ),
                      ],
                    ),
                  ),
                  IconButton(
                    tooltip: 'Close',
                    onPressed: () => Navigator.pop(context),
                    icon: const Icon(Icons.close),
                  ),
                ],
              ),
            ),
            const Divider(height: 1),

            // ── Surgery Type Filter Chips Bar ──────────────────────────
            templatesAsync.when(
              loading: () => const LinearProgressIndicator(minHeight: 2),
              error: (_, __) => const SizedBox.shrink(),
              data: (allTemplates) {
                return Container(
                  color: AppColors.surfaceContainerLowest,
                  padding: const EdgeInsets.symmetric(horizontal: AppSpacing.md, vertical: AppSpacing.sm),
                  child: SingleChildScrollView(
                    scrollDirection: Axis.horizontal,
                    child: Row(
                      children: EyeSurgeryModel.surgeryTypeOptions.map((type) {
                        final count = allTemplates.where((t) => t.surgeryType == type).length;
                        final isSelected = type == _selectedSurgeryType;
                        return Padding(
                          padding: const EdgeInsets.only(right: 8),
                          child: ChoiceChip(
                            label: Text('$type ($count)'),
                            selected: isSelected,
                            onSelected: _saving
                                ? null
                                : (selected) {
                                    if (selected) {
                                      setState(() {
                                        _selectedSurgeryType = type;
                                        _selectedInventoryId = null;
                                      });
                                    }
                                  },
                            selectedColor: AppColors.primaryContainer,
                            labelStyle: TextStyle(
                              color: isSelected ? AppColors.primary : AppColors.onSurface,
                              fontWeight: isSelected ? FontWeight.bold : FontWeight.normal,
                              fontSize: 13,
                            ),
                          ),
                        );
                      }).toList(),
                    ),
                  ),
                );
              },
            ),
            const Divider(height: 1),

            // ── Preset Items & Add Form (Unified Scrollable Body) ─────
            Expanded(
              child: templatesAsync.when(
                loading: () => const Center(
                  child: Padding(
                    padding: EdgeInsets.all(AppSpacing.xl),
                    child: CircularProgressIndicator(),
                  ),
                ),
                error: (error, _) => Center(
                  child: Padding(
                    padding: const EdgeInsets.all(AppSpacing.md),
                    child: Column(
                      mainAxisSize: MainAxisSize.min,
                      children: [
                        Text('Unable to load presets: $error'),
                        const SizedBox(height: AppSpacing.sm),
                        TextButton.icon(
                          onPressed: () => ref.invalidate(allEyeSurgeryItemTemplatesProvider),
                          icon: const Icon(Icons.refresh),
                          label: const Text('Retry'),
                        ),
                      ],
                    ),
                  ),
                ),
                data: (allTemplates) {
                  final typeTemplates = allTemplates
                      .where((t) => t.surgeryType == _selectedSurgeryType)
                      .toList();

                  final currentItemIds = typeTemplates
                      .map((t) => t.inventoryItemId)
                      .toSet();

                  final availableItems = inventory
                      .where((item) => item.isActive && !currentItemIds.contains(item.id))
                      .toList();

                  return SingleChildScrollView(
                    padding: const EdgeInsets.all(AppSpacing.md),
                    child: Column(
                      crossAxisAlignment: CrossAxisAlignment.stretch,
                      children: [
                        // Preset Items List or Empty State
                        if (typeTemplates.isEmpty)
                          Container(
                            padding: const EdgeInsets.all(AppSpacing.lg),
                            decoration: BoxDecoration(
                              color: AppColors.surfaceContainerLowest,
                              borderRadius: BorderRadius.circular(AppSpacing.radiusMd),
                              border: Border.all(color: AppColors.outlineVariant),
                            ),
                            child: Column(
                              mainAxisSize: MainAxisSize.min,
                              children: [
                                const Icon(Icons.playlist_add, size: 40, color: AppColors.outline),
                                const SizedBox(height: AppSpacing.xs),
                                Text(
                                  'No preset items for $_selectedSurgeryType',
                                  style: AppTypography.headlineMd.copyWith(fontSize: 15),
                                  textAlign: TextAlign.center,
                                ),
                                const SizedBox(height: 4),
                                Text(
                                  'Add default supplies below to create this surgery preset.',
                                  textAlign: TextAlign.center,
                                  style: AppTypography.bodySm.copyWith(color: AppColors.onSurfaceVariant),
                                ),
                              ],
                            ),
                          )
                        else
                          for (final item in typeTemplates)
                            Container(
                              margin: const EdgeInsets.only(bottom: 8),
                              decoration: BoxDecoration(
                                color: AppColors.surfaceContainerLowest,
                                borderRadius: BorderRadius.circular(AppSpacing.radiusMd),
                                border: Border.all(color: AppColors.outlineVariant),
                              ),
                              child: ListTile(
                                dense: true,
                                leading: const CircleAvatar(
                                  radius: 18,
                                  backgroundColor: AppColors.primaryContainer,
                                  child: Icon(Icons.medication_outlined, size: 18, color: AppColors.primary),
                                ),
                                title: Text(
                                  item.inventoryItemName,
                                  style: AppTypography.bodyMd.copyWith(fontWeight: FontWeight.w600),
                                  overflow: TextOverflow.ellipsis,
                                ),
                                subtitle: Text(
                                  'Default Qty: ${item.defaultQuantity} ${item.unit}  •  Stock: ${item.currentStock} ${item.unit}',
                                  style: AppTypography.bodySm.copyWith(color: AppColors.onSurfaceVariant),
                                  overflow: TextOverflow.ellipsis,
                                ),
                                trailing: Row(
                                  mainAxisSize: MainAxisSize.min,
                                  children: [
                                    IconButton(
                                      icon: const Icon(Icons.edit_outlined, size: 18),
                                      tooltip: 'Edit quantity',
                                      onPressed: _saving ? null : () => _editQuantity(item),
                                    ),
                                    IconButton(
                                      icon: const Icon(Icons.delete_outline, size: 18),
                                      color: AppColors.error,
                                      tooltip: 'Remove from preset',
                                      onPressed: _saving ? null : () => _removeItem(item),
                                    ),
                                  ],
                                ),
                              ),
                            ),

                        const SizedBox(height: AppSpacing.md),
                        const Divider(height: 1),
                        const SizedBox(height: AppSpacing.md),

                        // Add Item to Preset Section
                        Container(
                          padding: const EdgeInsets.all(AppSpacing.md),
                          decoration: BoxDecoration(
                            color: AppColors.surfaceContainerLowest,
                            borderRadius: BorderRadius.circular(AppSpacing.radiusMd),
                            border: Border.all(color: AppColors.outlineVariant),
                          ),
                          child: Column(
                            crossAxisAlignment: CrossAxisAlignment.stretch,
                            children: [
                              Text(
                                'ADD ITEM TO $_selectedSurgeryType PRESET',
                                style: AppTypography.labelCaps.copyWith(color: AppColors.primary),
                              ),
                              const SizedBox(height: AppSpacing.sm),
                              if (availableItems.isEmpty)
                                const Padding(
                                  padding: EdgeInsets.symmetric(vertical: 4),
                                  child: Text(
                                    'All active inventory items are already in this preset.',
                                    style: TextStyle(color: AppColors.onSurfaceVariant, fontSize: 13),
                                  ),
                                )
                              else ...[
                                DropdownButtonFormField<String>(
                                  key: ValueKey('preset_inventory_picker_${_selectedSurgeryType}_$_selectedInventoryId'),
                                  initialValue: _selectedInventoryId,
                                  isExpanded: true,
                                  decoration: const InputDecoration(
                                    labelText: 'Select inventory item',
                                    border: OutlineInputBorder(),
                                    isDense: true,
                                  ),
                                  items: availableItems
                                      .map((item) => DropdownMenuItem(
                                            value: item.id,
                                            child: Text(
                                              '${item.name} (${item.formattedStock} ${item.unit})',
                                              overflow: TextOverflow.ellipsis,
                                            ),
                                          ))
                                      .toList(),
                                  onChanged: _saving
                                      ? null
                                      : (value) => setState(() => _selectedInventoryId = value),
                                ),
                                const SizedBox(height: AppSpacing.sm),
                                LayoutBuilder(
                                  builder: (context, addConstraints) {
                                    final isNarrow = addConstraints.maxWidth < 360;
                                    if (isNarrow) {
                                      return Column(
                                        crossAxisAlignment: CrossAxisAlignment.stretch,
                                        children: [
                                          TextField(
                                            controller: _quantityController,
                                            keyboardType: const TextInputType.numberWithOptions(decimal: true),
                                            decoration: const InputDecoration(
                                              labelText: 'Required qty',
                                              border: OutlineInputBorder(),
                                              isDense: true,
                                            ),
                                          ),
                                          const SizedBox(height: AppSpacing.sm),
                                          FilledButton.icon(
                                            onPressed: _saving || _selectedInventoryId == null
                                                ? null
                                                : _savePresetItem,
                                            icon: _saving
                                                ? const SizedBox(
                                                    width: 16,
                                                    height: 16,
                                                    child: CircularProgressIndicator(strokeWidth: 2, color: Colors.white),
                                                  )
                                                : const Icon(Icons.add, size: 18),
                                            label: const Text('Add to Preset'),
                                          ),
                                        ],
                                      );
                                    }
                                    return Row(
                                      children: [
                                        SizedBox(
                                          width: 130,
                                          child: TextField(
                                            controller: _quantityController,
                                            keyboardType: const TextInputType.numberWithOptions(decimal: true),
                                            decoration: const InputDecoration(
                                              labelText: 'Required qty',
                                              border: OutlineInputBorder(),
                                              isDense: true,
                                            ),
                                          ),
                                        ),
                                        const SizedBox(width: AppSpacing.sm),
                                        Expanded(
                                          child: FilledButton.icon(
                                            onPressed: _saving || _selectedInventoryId == null
                                                ? null
                                                : _savePresetItem,
                                            icon: _saving
                                                ? const SizedBox(
                                                    width: 16,
                                                    height: 16,
                                                    child: CircularProgressIndicator(strokeWidth: 2, color: Colors.white),
                                                  )
                                                : const Icon(Icons.add, size: 18),
                                            label: const Text('Add to Preset'),
                                          ),
                                        ),
                                      ],
                                    );
                                  },
                                ),
                              ],
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
        ),
      ),
    );
  }
}

/// Backward compatibility alias
typedef EyeSurgeryTemplateManagerDialog = SurgeryInventoryPresetsDialog;
