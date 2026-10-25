import 'package:flutter/material.dart';
import 'package:flutter/services.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:intl/intl.dart';

import '../../../core/theme/app_colors.dart';
import '../../../core/theme/app_spacing.dart';
import '../../../core/theme/app_typography.dart';
import '../../../shared/widgets/adaptive_dialog_shell.dart';
import '../../../shared/widgets/responsive_form_row.dart';
import '../../auth/providers/auth_provider.dart';
import '../../vendors/models/vendor.dart';
import '../../vendors/providers/vendor_provider.dart';
import '../models/inventory_item.dart';
import '../models/purchase_order.dart';
import '../providers/inventory_provider.dart';
import '../providers/purchase_order_provider.dart';
import '../utils/vendor_product_matcher.dart';

/// Form item holding editable line-item data in the dialog.
class _EditablePOLineItem {
  _EditablePOLineItem({
    this.id = '',
    this.inventoryId = '',
    this.inventoryName = '',
    this.inventoryUnit = 'units',
    this.inventorySku,
    double initialQty = 1.0,
    double initialPrice = 0.0,
  }) {
    qtyController = TextEditingController(
      text: initialQty % 1 == 0 ? initialQty.toInt().toString() : initialQty.toString(),
    );
    priceController = TextEditingController(
      text: initialPrice.toStringAsFixed(2),
    );
  }

  String id;
  String inventoryId;
  String inventoryName;
  String inventoryUnit;
  String? inventorySku;
  late TextEditingController qtyController;
  late TextEditingController priceController;

  double get quantity => double.tryParse(qtyController.text.trim()) ?? 0.0;
  double get unitPrice => double.tryParse(priceController.text.trim()) ?? 0.0;
  double get totalAmount => quantity * unitPrice;

  void dispose() {
    qtyController.dispose();
    priceController.dispose();
  }
}

/// Dialog for creating or editing a [PurchaseOrder].
class PurchaseOrderFormDialog extends ConsumerStatefulWidget {
  const PurchaseOrderFormDialog({
    super.key,
    this.order,
    this.preselectedInventoryItem,
    this.preselectedVendorId,
  });

  final PurchaseOrder? order;
  final InventoryItem? preselectedInventoryItem;
  final String? preselectedVendorId;

  @override
  ConsumerState<PurchaseOrderFormDialog> createState() =>
      _PurchaseOrderFormDialogState();
}

class _PurchaseOrderFormDialogState
    extends ConsumerState<PurchaseOrderFormDialog> {
  final _formKey = GlobalKey<FormState>();

  late TextEditingController _poNumberController;
  late TextEditingController _notesController;

  String? _selectedVendorId;
  DateTime _orderDate = DateTime.now();
  DateTime? _expectedDeliveryDate;
  final List<_EditablePOLineItem> _items = [];

  bool _isLoading = false;
  String? _errorMessage;

  bool get _isEditing => widget.order != null;

  @override
  void initState() {
    super.initState();
    final po = widget.order;

    _poNumberController = TextEditingController(
      text: po?.purchaseOrderNumber ?? '',
    );
    _notesController = TextEditingController(text: po?.notes ?? '');

    _selectedVendorId = po?.vendorId ??
        widget.preselectedVendorId ??
        widget.preselectedInventoryItem?.vendorId;
    _orderDate = po?.orderDate ?? DateTime.now();
    _expectedDeliveryDate = po?.expectedDeliveryDate;

    if (po != null && po.items.isNotEmpty) {
      for (final item in po.items) {
        _items.add(_EditablePOLineItem(
          id: item.id,
          inventoryId: item.inventoryId,
          inventoryName: item.inventoryName,
          inventoryUnit: item.inventoryUnit,
          inventorySku: item.inventorySku,
          initialQty: item.quantity,
          initialPrice: item.unitPrice,
        ));
      }
    } else if (widget.preselectedInventoryItem != null) {
      final item = widget.preselectedInventoryItem!;
      _items.add(_EditablePOLineItem(
        inventoryId: item.id,
        inventoryName: item.name,
        inventoryUnit: item.unit,
        inventorySku: item.sku,
        initialQty: 1.0,
        initialPrice: item.price ?? 0.0,
      ));
    } else {
      // Add one blank line item by default
      _items.add(_EditablePOLineItem());
    }
  }

  @override
  void dispose() {
    _poNumberController.dispose();
    _notesController.dispose();
    for (final item in _items) {
      item.dispose();
    }
    super.dispose();
  }

  double get _grandTotal {
    return _items.fold(0.0, (sum, item) => sum + item.totalAmount);
  }

  void _addItem() {
    setState(() {
      _items.add(_EditablePOLineItem());
    });
  }

  void _removeItem(int index) {
    if (_items.length <= 1) {
      ScaffoldMessenger.of(context).showSnackBar(
        const SnackBar(content: Text('A purchase order must have at least one product.')),
      );
      return;
    }
    setState(() {
      final removed = _items.removeAt(index);
      removed.dispose();
    });
  }

  Future<void> _submit(PurchaseOrderStatus targetStatus) async {
    setState(() => _errorMessage = null);

    if (!_formKey.currentState!.validate()) return;

    if (_selectedVendorId == null || _selectedVendorId!.isEmpty) {
      setState(() => _errorMessage = 'Please select a vendor / supplier.');
      return;
    }

    if (_items.isEmpty) {
      setState(() => _errorMessage = 'Please add at least one line item.');
      return;
    }

    for (int i = 0; i < _items.length; i++) {
      final line = _items[i];
      if (line.inventoryId.isEmpty) {
        setState(() => _errorMessage = 'Please select an inventory item for line ${i + 1}.');
        return;
      }
      if (line.quantity <= 0) {
        setState(() => _errorMessage = 'Quantity for line ${i + 1} must be greater than 0.');
        return;
      }
      if (line.unitPrice < 0) {
        setState(() => _errorMessage = 'Unit price for line ${i + 1} cannot be negative.');
        return;
      }
    }

    // Explicit Date validation: Expected delivery date must be >= Order date
    if (_expectedDeliveryDate != null) {
      final orderDateOnly = DateTime(_orderDate.year, _orderDate.month, _orderDate.day);
      final deliveryDateOnly = DateTime(
        _expectedDeliveryDate!.year,
        _expectedDeliveryDate!.month,
        _expectedDeliveryDate!.day,
      );
      if (deliveryDateOnly.isBefore(orderDateOnly)) {
        setState(() => _errorMessage = 'Expected delivery date cannot be before the order date.');
        return;
      }
    }

    setState(() => _isLoading = true);

    try {
      final poItems = _items.map((line) {
        return PurchaseOrderItem(
          id: line.id,
          purchaseOrderId: widget.order?.id ?? '',
          inventoryId: line.inventoryId,
          inventoryName: line.inventoryName,
          inventoryUnit: line.inventoryUnit,
          inventorySku: line.inventorySku,
          quantity: line.quantity,
          unitPrice: line.unitPrice,
          totalAmount: line.totalAmount,
        );
      }).toList();

      final currentUserId = ref.read(currentUserProvider)?.id;
      final poOrder = PurchaseOrder(
        id: widget.order?.id ?? '',
        purchaseOrderNumber: _isEditing ? widget.order!.purchaseOrderNumber : '',
        vendorId: _selectedVendorId!,
        orderDate: _orderDate,
        expectedDeliveryDate: _expectedDeliveryDate,
        status: targetStatus,
        subtotal: _grandTotal,
        totalAmount: _grandTotal,
        createdBy: widget.order?.createdBy ?? currentUserId,
        orderedBy: targetStatus == PurchaseOrderStatus.ordered
            ? (widget.order?.orderedBy ?? currentUserId)
            : widget.order?.orderedBy,
        orderedAt: targetStatus == PurchaseOrderStatus.ordered
            ? (widget.order?.orderedAt ?? DateTime.now())
            : widget.order?.orderedAt,
        notes: _notesController.text.trim().isNotEmpty
            ? _notesController.text.trim()
            : null,
      );

      final notifier = ref.read(purchaseOrdersProvider.notifier);

      if (_isEditing) {
        await notifier.updateOrder(poOrder, poItems);
      } else {
        await notifier.createOrder(poOrder, poItems);
      }

      if (mounted) {
        Navigator.of(context).pop(true);
        ScaffoldMessenger.of(context).showSnackBar(
          SnackBar(
            backgroundColor: AppColors.primaryContainer,
            content: Text(
              _isEditing
                  ? 'Purchase Order ${poOrder.purchaseOrderNumber} updated.'
                  : 'Purchase Order ${poOrder.purchaseOrderNumber} created as ${targetStatus.label}.',
            ),
          ),
        );
      }
    } catch (e) {
      if (mounted) {
        setState(() {
          _isLoading = false;
          _errorMessage = e.toString().replaceFirst('Exception: ', '');
        });
      }
    }
  }

  @override
  Widget build(BuildContext context) {
    final rawVendors = ref.watch(vendorsProvider).value ?? [];
    final allVendors = rawVendors.where((v) => v.isActive).toList();
    final allInventory = ref.watch(inventoryProvider).value ?? [];

    final selectedVendor = rawVendors.where((v) => v.id == _selectedVendorId).firstOrNull;
    final availableProducts = selectedVendor != null
        ? allInventory.where((i) => isProductSuppliedByVendor(i, selectedVendor)).toList()
        : allInventory;

    final dialogConstraints = AdaptiveDialogShell.constraintsFor(
      context,
      maxMobileWidth: double.infinity,
      maxTabletWidth: 640.0,
      maxDesktopWidth: 800.0,
    );

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
          maxWidth: dialogConstraints.maxWidth,
          maxHeight: dialogConstraints.maxHeight,
        ),
        child: Column(
          mainAxisSize: MainAxisSize.min,
          crossAxisAlignment: CrossAxisAlignment.stretch,
          children: [
            _buildDialogHeader(),
            const Divider(height: 1, color: AppColors.outlineVariant),
            Flexible(
              child: SingleChildScrollView(
                padding: const EdgeInsets.all(AppSpacing.lg),
                child: Form(
                  key: _formKey,
                  child: Column(
                    crossAxisAlignment: CrossAxisAlignment.start,
                    children: [
                      if (_errorMessage != null) ...[
                        _buildErrorBanner(_errorMessage!),
                        const SizedBox(height: AppSpacing.md),
                      ],

                      // Row 1: PO Number & Vendor
                      ResponsiveFormRow(
                        breakpoint: 500,
                        flexes: const [2, 3],
                        children: [
                          Column(
                            crossAxisAlignment: CrossAxisAlignment.start,
                            children: [
                              Text(
                                _isEditing ? 'PO NUMBER (READ-ONLY)' : 'PO NUMBER (AUTO-GENERATED)',
                                style: AppTypography.labelCaps.copyWith(
                                  color: AppColors.onSurfaceVariant,
                                ),
                              ),
                              const SizedBox(height: AppSpacing.xs),
                              Container(
                                width: double.infinity,
                                padding: const EdgeInsets.symmetric(
                                  horizontal: AppSpacing.md,
                                  vertical: 14,
                                ),
                                decoration: BoxDecoration(
                                  color: AppColors.surfaceContainerLow,
                                  borderRadius: BorderRadius.circular(AppSpacing.radiusMd),
                                  border: Border.all(color: AppColors.outlineVariant),
                                ),
                                child: Row(
                                  children: [
                                    const Icon(
                                      Icons.tag,
                                      size: 18,
                                      color: AppColors.primary,
                                    ),
                                    const SizedBox(width: AppSpacing.xs),
                                    Expanded(
                                      child: Text(
                                        _isEditing
                                            ? widget.order!.purchaseOrderNumber
                                            : 'Auto: PO-${DateFormat('ddMMyyyy').format(DateTime.now())}-XXXX',
                                        style: AppTypography.bodyMd.copyWith(
                                          fontWeight: FontWeight.w700,
                                          color: AppColors.onSurface,
                                        ),
                                        overflow: TextOverflow.ellipsis,
                                      ),
                                    ),
                                  ],
                                ),
                              ),
                            ],
                          ),
                          Column(
                            crossAxisAlignment: CrossAxisAlignment.start,
                            children: [
                              Text(
                                'VENDOR / SUPPLIER *',
                                style: AppTypography.labelCaps.copyWith(
                                  color: AppColors.onSurfaceVariant,
                                ),
                              ),
                              const SizedBox(height: AppSpacing.xs),
                              DropdownButtonFormField<String>(
                                key: const Key('po_vendor_dropdown'),
                                isExpanded: true,
                                initialValue: _selectedVendorId,
                                hint: const Text('Select Supplier *'),
                                decoration: InputDecoration(
                                  prefixIcon: const Icon(
                                    Icons.local_shipping_outlined,
                                    size: 20,
                                    color: AppColors.onSurfaceVariant,
                                  ),
                                  fillColor: AppColors.surfaceContainerLow,
                                  hintText: 'Select Supplier *',
                                ),
                                items: allVendors.map((v) {
                                  return DropdownMenuItem<String>(
                                    value: v.id,
                                    child: Text(
                                      '${v.name} (${v.productsDisplay})',
                                      overflow: TextOverflow.ellipsis,
                                    ),
                                  );
                                }).toList(),
                                onChanged: (val) {
                                  if (val == _selectedVendorId) return;
                                  setState(() {
                                    _selectedVendorId = val;
                                    // CHANGE 1: Immediately clear/reset all previously selected PO products/items
                                    for (final item in _items) {
                                      item.dispose();
                                    }
                                    _items.clear();
                                    _items.add(_EditablePOLineItem());
                                  });
                                },
                                validator: (v) => (v == null || v.isEmpty)
                                    ? 'Vendor is required'
                                    : null,
                              ),
                            ],
                          ),
                        ],
                      ),
                      const SizedBox(height: AppSpacing.md),

                      // Row 2: Dates (Order Date & Expected Delivery)
                      ResponsiveFormRow(
                        breakpoint: 500,
                        children: [
                          Column(
                            crossAxisAlignment: CrossAxisAlignment.start,
                            children: [
                              Text(
                                'ORDER DATE *',
                                style: AppTypography.labelCaps.copyWith(
                                  color: AppColors.onSurfaceVariant,
                                ),
                              ),
                              const SizedBox(height: AppSpacing.xs),
                              InkWell(
                                onTap: () async {
                                  final picked = await showDatePicker(
                                    context: context,
                                    initialDate: _orderDate,
                                    firstDate: DateTime(2020),
                                    lastDate: DateTime(2040),
                                  );
                                  if (picked != null) {
                                    setState(() {
                                      _orderDate = picked;
                                      if (_expectedDeliveryDate != null) {
                                        final oDate = DateTime(picked.year, picked.month, picked.day);
                                        final dDate = DateTime(
                                          _expectedDeliveryDate!.year,
                                          _expectedDeliveryDate!.month,
                                          _expectedDeliveryDate!.day,
                                        );
                                        if (dDate.isBefore(oDate)) {
                                          _expectedDeliveryDate = null;
                                        }
                                      }
                                    });
                                  }
                                },
                                borderRadius: BorderRadius.circular(AppSpacing.radiusMd),
                                child: InputDecorator(
                                  decoration: InputDecoration(
                                    prefixIcon: const Icon(Icons.calendar_today_outlined, size: 20),
                                    fillColor: AppColors.surfaceContainerLow,
                                  ),
                                  child: Text(
                                    DateFormat('yyyy-MM-dd').format(_orderDate),
                                    style: AppTypography.bodyMd,
                                  ),
                                ),
                              ),
                            ],
                          ),
                          Column(
                            crossAxisAlignment: CrossAxisAlignment.start,
                            children: [
                              Text(
                                'EXPECTED DELIVERY',
                                style: AppTypography.labelCaps.copyWith(
                                  color: AppColors.onSurfaceVariant,
                                ),
                              ),
                              const SizedBox(height: AppSpacing.xs),
                              InkWell(
                                onTap: () async {
                                  final orderDateOnly = DateTime(_orderDate.year, _orderDate.month, _orderDate.day);
                                  DateTime initialTarget;
                                  if (_expectedDeliveryDate != null &&
                                      !_expectedDeliveryDate!.isBefore(orderDateOnly)) {
                                    initialTarget = _expectedDeliveryDate!;
                                  } else {
                                    initialTarget = orderDateOnly;
                                  }

                                  final picked = await showDatePicker(
                                    context: context,
                                    initialDate: initialTarget,
                                    firstDate: orderDateOnly,
                                    lastDate: DateTime(2040),
                                  );
                                  if (picked != null) {
                                    setState(() => _expectedDeliveryDate = picked);
                                  }
                                },
                                borderRadius: BorderRadius.circular(AppSpacing.radiusMd),
                                child: InputDecorator(
                                  decoration: InputDecoration(
                                    prefixIcon: const Icon(Icons.event_available_outlined, size: 20),
                                    suffixIcon: _expectedDeliveryDate != null
                                        ? IconButton(
                                            icon: const Icon(Icons.clear, size: 18),
                                            onPressed: () => setState(() => _expectedDeliveryDate = null),
                                          )
                                        : null,
                                    fillColor: AppColors.surfaceContainerLow,
                                  ),
                                  child: Text(
                                    _expectedDeliveryDate != null
                                        ? DateFormat('yyyy-MM-dd').format(_expectedDeliveryDate!)
                                        : 'Not specified',
                                    style: AppTypography.bodyMd.copyWith(
                                      color: _expectedDeliveryDate != null
                                          ? AppColors.onSurface
                                          : AppColors.onSurfaceVariant,
                                    ),
                                  ),
                                ),
                              ),
                            ],
                          ),
                        ],
                      ),
                      const SizedBox(height: AppSpacing.lg),

                      // Section Header: Products & Line Items
                      Row(
                        mainAxisAlignment: MainAxisAlignment.spaceBetween,
                        children: [
                          Text(
                            'ORDERED PRODUCTS (${_items.length})',
                            style: AppTypography.labelCaps.copyWith(
                              color: AppColors.primary,
                              fontWeight: FontWeight.w700,
                            ),
                          ),
                          TextButton.icon(
                            onPressed: (_selectedVendorId != null && availableProducts.isNotEmpty)
                                ? _addItem
                                : null,
                            icon: const Icon(Icons.add_circle_outline, size: 18),
                            label: const Text('Add Product'),
                          ),
                        ],
                      ),
                      if (_selectedVendorId == null) ...[
                        const SizedBox(height: AppSpacing.xs),
                        Container(
                          width: double.infinity,
                          padding: const EdgeInsets.all(AppSpacing.sm),
                          decoration: BoxDecoration(
                            color: AppColors.surfaceContainerLow,
                            borderRadius: BorderRadius.circular(AppSpacing.radiusMd),
                            border: Border.all(color: AppColors.outlineVariant),
                          ),
                          child: Row(
                            children: [
                              const Icon(Icons.info_outline, size: 18, color: AppColors.onSurfaceVariant),
                              const SizedBox(width: AppSpacing.xs),
                              Expanded(
                                child: Text(
                                  'Please select a vendor / supplier above to choose from their supplied products.',
                                  style: AppTypography.bodySm.copyWith(
                                    color: AppColors.onSurfaceVariant,
                                  ),
                                ),
                              ),
                            ],
                          ),
                        ),
                      ] else if (availableProducts.isEmpty) ...[
                        const SizedBox(height: AppSpacing.xs),
                        Container(
                          key: const Key('vendor_no_products_empty_state'),
                          width: double.infinity,
                          padding: const EdgeInsets.all(AppSpacing.md),
                          decoration: BoxDecoration(
                            color: Colors.amber.shade50,
                            borderRadius: BorderRadius.circular(AppSpacing.radiusMd),
                            border: Border.all(color: Colors.amber.shade300),
                          ),
                          child: Row(
                            children: [
                              Icon(Icons.warning_amber_rounded, color: Colors.amber.shade900, size: 20),
                              const SizedBox(width: AppSpacing.sm),
                              Expanded(
                                child: Text(
                                  'No products are supplied by "${selectedVendor?.name ?? 'this vendor'}". Please add products supplied to this vendor in Vendors management or select another vendor.',
                                  style: AppTypography.bodySm.copyWith(
                                    color: AppColors.onSurface,
                                    fontWeight: FontWeight.w500,
                                  ),
                                ),
                              ),
                            ],
                          ),
                        ),
                      ],
                      const SizedBox(height: AppSpacing.xs),

                      // List of Line Items
                      ListView.separated(
                        shrinkWrap: true,
                        physics: const NeverScrollableScrollPhysics(),
                        itemCount: _items.length,
                        separatorBuilder: (_, __) => const SizedBox(height: AppSpacing.sm),
                        itemBuilder: (context, index) {
                          return _buildLineItemRow(index, availableProducts, selectedVendor);
                        },
                      ),
                      const SizedBox(height: AppSpacing.md),

                      // Grand Total Card
                      Container(
                        padding: const EdgeInsets.all(AppSpacing.md),
                        decoration: BoxDecoration(
                          color: AppColors.primaryContainer.withValues(alpha: 0.15),
                          borderRadius: BorderRadius.circular(AppSpacing.radiusLg),
                          border: Border.all(
                            color: AppColors.primary.withValues(alpha: 0.3),
                          ),
                        ),
                        child: Row(
                          mainAxisAlignment: MainAxisAlignment.spaceBetween,
                          children: [
                            Text(
                              'TOTAL ORDER AMOUNT:',
                              style: AppTypography.labelCaps.copyWith(
                                color: AppColors.primary,
                                fontWeight: FontWeight.w700,
                              ),
                            ),
                            Text(
                              '₹${_grandTotal.toStringAsFixed(2)}',
                              style: AppTypography.displayLg.copyWith(
                                color: AppColors.primary,
                                fontWeight: FontWeight.w800,
                                fontSize: 20,
                              ),
                            ),
                          ],
                        ),
                      ),
                      const SizedBox(height: AppSpacing.md),

                      // Notes / Instructions
                      Text(
                        'NOTES & INSTRUCTIONS (OPTIONAL)',
                        style: AppTypography.labelCaps.copyWith(
                          color: AppColors.onSurfaceVariant,
                        ),
                      ),
                      const SizedBox(height: AppSpacing.xs),
                      TextFormField(
                        controller: _notesController,
                        maxLines: 2,
                        decoration: InputDecoration(
                          hintText: 'e.g. Expedited delivery requested, batch certificates needed...',
                          fillColor: AppColors.surfaceContainerLow,
                        ),
                      ),
                    ],
                  ),
                ),
              ),
            ),
            const Divider(height: 1, color: AppColors.outlineVariant),
            _buildDialogActions(),
          ],
        ),
      ),
    );
  }

  Widget _buildLineItemRow(
    int index,
    List<InventoryItem> availableProducts,
    Vendor? selectedVendor,
  ) {
    final line = _items[index];
    final allInventory = ref.watch(inventoryProvider).value ?? [];
    final hasCurrentItem = availableProducts.any((item) => item.id == line.inventoryId);
    if (!hasCurrentItem && line.inventoryId.isNotEmpty && selectedVendor != null && allInventory.isNotEmpty) {
      line.inventoryId = '';
      line.inventoryName = '';
      line.inventorySku = null;
      line.priceController.text = '0.00';
    }

    final dropdownProducts = List<InventoryItem>.from(availableProducts);
    if (line.inventoryId.isNotEmpty && !dropdownProducts.any((i) => i.id == line.inventoryId)) {
      final fallbackItem = allInventory.where((i) => i.id == line.inventoryId).firstOrNull ??
          (widget.preselectedInventoryItem?.id == line.inventoryId ? widget.preselectedInventoryItem : null);
      if (fallbackItem != null) {
        dropdownProducts.add(fallbackItem);
      }
    }

    return Container(
      padding: const EdgeInsets.all(AppSpacing.sm),
      decoration: BoxDecoration(
        color: AppColors.surfaceContainerLow,
        borderRadius: BorderRadius.circular(AppSpacing.radiusMd),
        border: Border.all(color: AppColors.outlineVariant),
      ),
      child: LayoutBuilder(
        builder: (context, constraints) {
          final isCompact = constraints.maxWidth < 560;

          final productField = DropdownButtonFormField<String>(
            key: ValueKey('po_item_product_${index}_${_selectedVendorId}_${line.inventoryId}'),
            isExpanded: true,
            initialValue: dropdownProducts.any((i) => i.id == line.inventoryId) ? line.inventoryId : null,
            hint: Text(
              _selectedVendorId == null
                  ? 'Select vendor first'
                  : availableProducts.isEmpty
                      ? 'No products supplied'
                      : 'Select Product *',
              overflow: TextOverflow.ellipsis,
            ),
            decoration: InputDecoration(
              labelText: 'Product ${index + 1}',
              contentPadding: const EdgeInsets.symmetric(horizontal: 10, vertical: 8),
            ),
            items: dropdownProducts.map((item) {
              final skuSuffix = item.sku != null ? ' (${item.sku})' : '';
              return DropdownMenuItem<String>(
                value: item.id,
                child: Text(
                  '${item.name}$skuSuffix',
                  overflow: TextOverflow.ellipsis,
                ),
              );
            }).toList(),
            onChanged: availableProducts.isEmpty
                ? null
                : (val) {
                    if (val == null) return;
                    final selected = dropdownProducts.firstWhere((i) => i.id == val);
                    setState(() {
                      line.inventoryId = selected.id;
                      line.inventoryName = selected.name;
                      line.inventoryUnit = selected.unit;
                      line.inventorySku = selected.sku;
                      if (selected.price != null && selected.price! > 0) {
                        line.priceController.text = selected.price!.toStringAsFixed(2);
                      }
                    });
                  },
            validator: (v) {
              if (v == null || v.isEmpty) return 'Product is required';
              return null;
            },
          );

          final qtyField = TextFormField(
            controller: line.qtyController,
            keyboardType: const TextInputType.numberWithOptions(decimal: true),
            inputFormatters: [
              FilteringTextInputFormatter.allow(RegExp(r'^\d+\.?\d{0,2}')),
            ],
            decoration: InputDecoration(
              labelText: 'Qty (${line.inventoryUnit})',
              contentPadding: const EdgeInsets.symmetric(horizontal: 10, vertical: 8),
            ),
            onChanged: (_) => setState(() {}),
          );

          final priceField = TextFormField(
            controller: line.priceController,
            keyboardType: const TextInputType.numberWithOptions(decimal: true),
            inputFormatters: [
              FilteringTextInputFormatter.allow(RegExp(r'^\d+\.?\d{0,2}')),
            ],
            decoration: const InputDecoration(
              labelText: 'Unit Price (₹)',
              contentPadding: EdgeInsets.symmetric(horizontal: 10, vertical: 8),
            ),
            onChanged: (_) => setState(() {}),
          );

          final subtotalWidget = SizedBox(
            width: 75,
            child: Padding(
              padding: const EdgeInsets.only(top: 14),
              child: Text(
                '₹${line.totalAmount.toStringAsFixed(2)}',
                style: AppTypography.bodyMd.copyWith(
                  fontWeight: FontWeight.w700,
                  color: AppColors.onSurface,
                ),
                textAlign: TextAlign.end,
              ),
            ),
          );

          final deleteButton = IconButton(
            padding: EdgeInsets.zero,
            constraints: const BoxConstraints(),
            icon: const Icon(Icons.delete_outline, size: 20, color: AppColors.error),
            tooltip: 'Remove product',
            onPressed: () => _removeItem(index),
          );

          if (isCompact) {
            return Column(
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                Row(
                  crossAxisAlignment: CrossAxisAlignment.center,
                  children: [
                    Expanded(child: productField),
                    const SizedBox(width: AppSpacing.sm),
                    deleteButton,
                  ],
                ),
                const SizedBox(height: AppSpacing.sm),
                Row(
                  crossAxisAlignment: CrossAxisAlignment.center,
                  children: [
                    Expanded(flex: 3, child: qtyField),
                    const SizedBox(width: AppSpacing.sm),
                    Expanded(flex: 3, child: priceField),
                    const SizedBox(width: AppSpacing.sm),
                    subtotalWidget,
                  ],
                ),
              ],
            );
          }

          return Row(
            crossAxisAlignment: CrossAxisAlignment.start,
            children: [
              Expanded(flex: 4, child: productField),
              const SizedBox(width: AppSpacing.sm),
              Expanded(flex: 2, child: qtyField),
              const SizedBox(width: AppSpacing.sm),
              Expanded(flex: 2, child: priceField),
              const SizedBox(width: AppSpacing.sm),
              subtotalWidget,
              deleteButton,
            ],
          );
        },
      ),
    );
  }

  Widget _buildErrorBanner(String message) {
    return Container(
      width: double.infinity,
      padding: const EdgeInsets.all(AppSpacing.sm),
      decoration: BoxDecoration(
        color: AppColors.error.withValues(alpha: 0.12),
        borderRadius: BorderRadius.circular(AppSpacing.radiusMd),
        border: Border.all(color: AppColors.error),
      ),
      child: Row(
        children: [
          const Icon(Icons.error_outline, color: AppColors.error, size: 20),
          const SizedBox(width: AppSpacing.xs),
          Expanded(
            child: Text(
              message,
              style: AppTypography.bodySm.copyWith(
                color: AppColors.error,
                fontWeight: FontWeight.w600,
              ),
            ),
          ),
        ],
      ),
    );
  }

  Widget _buildDialogHeader() {
    return Padding(
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
                    color: AppColors.primaryContainer.withValues(alpha: 0.2),
                    borderRadius: BorderRadius.circular(AppSpacing.radiusMd),
                  ),
                  child: const Icon(
                    Icons.receipt_long_outlined,
                    color: AppColors.primary,
                    size: 20,
                  ),
                ),
                const SizedBox(width: AppSpacing.sm),
                Expanded(
                  child: Text(
                    _isEditing ? 'Edit Purchase Order' : 'New Purchase Order',
                    style: AppTypography.headlineMd.copyWith(
                      fontWeight: FontWeight.w700,
                      fontSize: 18,
                    ),
                    overflow: TextOverflow.ellipsis,
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
    );
  }

  Widget _buildDialogActions() {
    return Padding(
      padding: const EdgeInsets.all(AppSpacing.md),
      child: Wrap(
        alignment: WrapAlignment.end,
        spacing: AppSpacing.sm,
        runSpacing: AppSpacing.xs,
        crossAxisAlignment: WrapCrossAlignment.center,
        children: [
          TextButton(
            onPressed: _isLoading ? null : () => Navigator.of(context).pop(),
            child: const Text('Cancel'),
          ),
          OutlinedButton(
            onPressed: _isLoading ? null : () => _submit(PurchaseOrderStatus.draft),
            child: const Text('Save as Draft'),
          ),
          FilledButton.icon(
            onPressed: _isLoading ? null : () => _submit(PurchaseOrderStatus.ordered),
            icon: _isLoading
                ? const SizedBox(
                    width: 18,
                    height: 18,
                    child: CircularProgressIndicator(strokeWidth: 2, color: Colors.white),
                  )
                : const Icon(Icons.send_outlined, size: 18),
            label: Text(_isEditing ? 'Save Changes' : 'Place Order'),
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
