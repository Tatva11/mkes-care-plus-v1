import 'dart:math';
import 'package:flutter/material.dart';
import 'package:flutter/services.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:intl/intl.dart';

import '../../../core/theme/app_colors.dart';
import '../../../core/theme/app_spacing.dart';
import '../../../core/theme/app_typography.dart';
import '../../vendors/providers/vendor_provider.dart';
import '../models/inventory_item.dart';
import '../models/purchase_order.dart';
import '../providers/inventory_provider.dart';
import '../providers/purchase_order_provider.dart';

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
  });

  final PurchaseOrder? order;

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

    final autoNumber =
        'PO-${DateFormat('yyyyMMdd').format(DateTime.now())}-${(100 + Random().nextInt(900))}';

    _poNumberController = TextEditingController(
      text: po?.purchaseOrderNumber ?? autoNumber,
    );
    _notesController = TextEditingController(text: po?.notes ?? '');

    _selectedVendorId = po?.vendorId;
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

      final poOrder = PurchaseOrder(
        id: widget.order?.id ?? '',
        purchaseOrderNumber: _poNumberController.text.trim(),
        vendorId: _selectedVendorId!,
        orderDate: _orderDate,
        expectedDeliveryDate: _expectedDeliveryDate,
        status: targetStatus,
        subtotal: _grandTotal,
        totalAmount: _grandTotal,
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
    final isDesktop = MediaQuery.sizeOf(context).width > 768;
    final allVendors = (ref.watch(vendorsProvider).value ?? [])
        .where((v) => v.isActive)
        .toList();
    final allInventory = ref.watch(inventoryProvider).value ?? [];

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
                      Row(
                        crossAxisAlignment: CrossAxisAlignment.start,
                        children: [
                          Expanded(
                            flex: 2,
                            child: Column(
                              crossAxisAlignment: CrossAxisAlignment.start,
                              children: [
                                Text(
                                  'PO NUMBER *',
                                  style: AppTypography.labelCaps.copyWith(
                                    color: AppColors.onSurfaceVariant,
                                  ),
                                ),
                                const SizedBox(height: AppSpacing.xs),
                                TextFormField(
                                  controller: _poNumberController,
                                  decoration: InputDecoration(
                                    prefixIcon: const Icon(
                                      Icons.tag,
                                      size: 20,
                                      color: AppColors.onSurfaceVariant,
                                    ),
                                    fillColor: AppColors.surfaceContainerLow,
                                  ),
                                  validator: (v) => (v == null || v.trim().isEmpty)
                                      ? 'PO number is required'
                                      : null,
                                ),
                              ],
                            ),
                          ),
                          const SizedBox(width: AppSpacing.md),
                          Expanded(
                            flex: 3,
                            child: Column(
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
                                  isExpanded: true,
                                  initialValue: _selectedVendorId,
                                  decoration: InputDecoration(
                                    prefixIcon: const Icon(
                                      Icons.local_shipping_outlined,
                                      size: 20,
                                      color: AppColors.onSurfaceVariant,
                                    ),
                                    fillColor: AppColors.surfaceContainerLow,
                                    hintText: 'Select supplier / vendor',
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
                                  onChanged: (val) =>
                                      setState(() => _selectedVendorId = val),
                                  validator: (v) => (v == null || v.isEmpty)
                                      ? 'Vendor is required'
                                      : null,
                                ),
                              ],
                            ),
                          ),
                        ],
                      ),
                      const SizedBox(height: AppSpacing.md),

                      // Row 2: Dates (Order Date & Expected Delivery)
                      Row(
                        children: [
                          Expanded(
                            child: Column(
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
                          ),
                          const SizedBox(width: AppSpacing.md),
                          Expanded(
                            child: Column(
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
                            onPressed: _addItem,
                            icon: const Icon(Icons.add_circle_outline, size: 18),
                            label: const Text('Add Product'),
                          ),
                        ],
                      ),
                      const SizedBox(height: AppSpacing.xs),

                      // List of Line Items
                      ListView.separated(
                        shrinkWrap: true,
                        physics: const NeverScrollableScrollPhysics(),
                        itemCount: _items.length,
                        separatorBuilder: (_, __) => const SizedBox(height: AppSpacing.sm),
                        itemBuilder: (context, index) {
                          return _buildLineItemRow(index, allInventory);
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

  Widget _buildLineItemRow(int index, List<InventoryItem> allInventory) {
    final line = _items[index];

    return Container(
      padding: const EdgeInsets.all(AppSpacing.sm),
      decoration: BoxDecoration(
        color: AppColors.surfaceContainerLow,
        borderRadius: BorderRadius.circular(AppSpacing.radiusMd),
        border: Border.all(color: AppColors.outlineVariant),
      ),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Row(
            crossAxisAlignment: CrossAxisAlignment.start,
            children: [
              // Product dropdown
              Expanded(
                flex: 4,
                child: DropdownButtonFormField<String>(
                  isExpanded: true,
                  initialValue: line.inventoryId.isNotEmpty ? line.inventoryId : null,
                  decoration: InputDecoration(
                    labelText: 'Product ${index + 1}',
                    contentPadding: const EdgeInsets.symmetric(horizontal: 10, vertical: 8),
                  ),
                  items: allInventory.map((item) {
                    final skuSuffix = item.sku != null ? ' (${item.sku})' : '';
                    return DropdownMenuItem<String>(
                      value: item.id,
                      child: Text(
                        '${item.name}$skuSuffix',
                        overflow: TextOverflow.ellipsis,
                      ),
                    );
                  }).toList(),
                  onChanged: (val) {
                    if (val == null) return;
                    final selected = allInventory.firstWhere((i) => i.id == val);
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
                ),
              ),
              const SizedBox(width: AppSpacing.sm),

              // Quantity
              Expanded(
                flex: 2,
                child: TextFormField(
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
                ),
              ),
              const SizedBox(width: AppSpacing.sm),

              // Unit price
              Expanded(
                flex: 2,
                child: TextFormField(
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
                ),
              ),
              const SizedBox(width: AppSpacing.sm),

              // Subtotal
              SizedBox(
                width: 90,
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
              ),

              // Delete row
              IconButton(
                icon: const Icon(Icons.delete_outline, size: 20, color: AppColors.error),
                tooltip: 'Remove product',
                onPressed: () => _removeItem(index),
              ),
            ],
          ),
        ],
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
          Row(
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
              Text(
                _isEditing ? 'Edit Purchase Order' : 'New Purchase Order',
                style: AppTypography.headlineMd.copyWith(
                  fontWeight: FontWeight.w700,
                  fontSize: 18,
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

  Widget _buildDialogActions() {
    return Padding(
      padding: const EdgeInsets.all(AppSpacing.md),
      child: Row(
        mainAxisAlignment: MainAxisAlignment.end,
        children: [
          TextButton(
            onPressed: _isLoading ? null : () => Navigator.of(context).pop(),
            child: const Text('Cancel'),
          ),
          const SizedBox(width: AppSpacing.sm),
          OutlinedButton(
            onPressed: _isLoading ? null : () => _submit(PurchaseOrderStatus.draft),
            child: const Text('Save as Draft'),
          ),
          const SizedBox(width: AppSpacing.sm),
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
