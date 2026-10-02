import 'package:flutter/material.dart';
import 'package:flutter/services.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';

import '../../../core/theme/app_colors.dart';
import '../../../core/theme/app_spacing.dart';
import '../../../core/theme/app_typography.dart';
import '../models/billing_item_model.dart';
import '../models/billing_service_model.dart';
import '../providers/billing_provider.dart';

class InvoiceLineItemsEditor extends ConsumerWidget {
  final String department;
  final List<BillingItemModel> items;
  final ValueChanged<List<BillingItemModel>> onChanged;

  const InvoiceLineItemsEditor({
    super.key,
    required this.department,
    required this.items,
    required this.onChanged,
  });

  void _addItem() {
    final updated = List<BillingItemModel>.from(items);
    updated.add(
      const BillingItemModel(
        serviceName: '',
        isCustom: false,
        quantity: 1,
        unitPrice: 0.0,
      ),
    );
    onChanged(updated);
  }

  void _removeItem(int index) {
    if (items.length <= 1) return;
    final updated = List<BillingItemModel>.from(items);
    updated.removeAt(index);
    onChanged(updated);
  }

  void _updateItem(int index, BillingItemModel item) {
    final updated = List<BillingItemModel>.from(items);
    updated[index] = item;
    onChanged(updated);
  }

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    final servicesAsync = ref.watch(departmentBillingServicesProvider(department));

    return Column(
      crossAxisAlignment: CrossAxisAlignment.start,
      children: [
        Row(
          mainAxisAlignment: MainAxisAlignment.spaceBetween,
          children: [
            Text(
              'Services & Line Items',
              style: AppTypography.bodyMd.copyWith(
                color: AppColors.onSurface,
                fontWeight: FontWeight.w700,
              ),
            ),
            OutlinedButton.icon(
              onPressed: _addItem,
              icon: const Icon(Icons.add, size: 16),
              label: const Text('Add Service'),
              style: OutlinedButton.styleFrom(
                foregroundColor: AppColors.primary,
                side: const BorderSide(color: AppColors.primary),
                padding: const EdgeInsets.symmetric(horizontal: 14, vertical: 8),
              ),
            ),
          ],
        ),
        const SizedBox(height: AppSpacing.sm),
        servicesAsync.when(
          loading: () => const Center(
            child: Padding(
              padding: EdgeInsets.all(AppSpacing.md),
              child: CircularProgressIndicator(),
            ),
          ),
          error: (error, _) => Container(
            padding: const EdgeInsets.all(AppSpacing.sm),
            decoration: BoxDecoration(
              color: AppColors.errorContainer,
              borderRadius: BorderRadius.circular(AppSpacing.radiusSm),
            ),
            child: Text(
              'Error loading ${department.toUpperCase()} services: $error',
              style: AppTypography.bodySm.copyWith(color: AppColors.onErrorContainer),
            ),
          ),
          data: (services) {
            return Column(
              children: [
                for (int i = 0; i < items.length; i++)
                  _LineItemCard(
                    key: ValueKey('item_${i}_${items[i].serviceId}_${items[i].isCustom}'),
                    index: i,
                    item: items[i],
                    services: services,
                    canDelete: items.length > 1,
                    onUpdate: (updated) => _updateItem(i, updated),
                    onDelete: () => _removeItem(i),
                  ),
              ],
            );
          },
        ),
      ],
    );
  }
}

class _LineItemCard extends StatefulWidget {
  final int index;
  final BillingItemModel item;
  final List<BillingServiceModel> services;
  final bool canDelete;
  final ValueChanged<BillingItemModel> onUpdate;
  final VoidCallback onDelete;

  const _LineItemCard({
    super.key,
    required this.index,
    required this.item,
    required this.services,
    required this.canDelete,
    required this.onUpdate,
    required this.onDelete,
  });

  @override
  State<_LineItemCard> createState() => _LineItemCardState();
}

class _LineItemCardState extends State<_LineItemCard> {
  late TextEditingController _customNameController;
  late TextEditingController _qtyController;
  late TextEditingController _priceController;

  static const String _customServiceKey = '__custom__';

  @override
  void initState() {
    super.initState();
    _customNameController = TextEditingController(
      text: widget.item.isCustom ? widget.item.serviceName : '',
    );
    _qtyController = TextEditingController(text: widget.item.quantity.toString());
    _priceController = TextEditingController(
      text: widget.item.unitPrice > 0 ? widget.item.unitPrice.toStringAsFixed(0) : '',
    );
  }

  @override
  void didUpdateWidget(covariant _LineItemCard oldWidget) {
    super.didUpdateWidget(oldWidget);
    if (widget.item.isCustom &&
        oldWidget.item.serviceName != widget.item.serviceName &&
        _customNameController.text != widget.item.serviceName) {
      _customNameController.text = widget.item.serviceName;
    }
    if (oldWidget.item.quantity != widget.item.quantity &&
        _qtyController.text != widget.item.quantity.toString()) {
      _qtyController.text = widget.item.quantity.toString();
    }
    if (oldWidget.item.unitPrice != widget.item.unitPrice &&
        _priceController.text != widget.item.unitPrice.toStringAsFixed(0)) {
      _priceController.text =
          widget.item.unitPrice > 0 ? widget.item.unitPrice.toStringAsFixed(0) : '';
    }
  }

  @override
  void dispose() {
    _customNameController.dispose();
    _qtyController.dispose();
    _priceController.dispose();
    super.dispose();
  }

  String? get _currentDropdownValue {
    if (widget.item.isCustom) return _customServiceKey;
    if (widget.item.serviceId != null &&
        widget.services.any((s) => s.id == widget.item.serviceId)) {
      return widget.item.serviceId;
    }
    return null;
  }

  List<DropdownMenuItem<String>> _buildDropdownItems() {
    final list = <DropdownMenuItem<String>>[];

    for (final s in widget.services) {
      list.add(
        DropdownMenuItem(
          value: s.id,
          child: Row(
            mainAxisAlignment: MainAxisAlignment.spaceBetween,
            children: [
              Flexible(
                child: Text(
                  s.name,
                  overflow: TextOverflow.ellipsis,
                ),
              ),
              const SizedBox(width: 8),
              Text(
                '₹${s.price.toStringAsFixed(0)}',
                style: TextStyle(
                  color: AppColors.primary,
                  fontWeight: FontWeight.w600,
                  fontSize: 12,
                ),
              ),
            ],
          ),
        ),
      );
    }

    // Custom Service option at the end
    list.add(
      DropdownMenuItem(
        value: _customServiceKey,
        child: Row(
          children: [
            Icon(Icons.edit_note, size: 18, color: AppColors.secondary),
            const SizedBox(width: 8),
            Text(
              'Custom Service...',
              style: TextStyle(
                color: AppColors.secondary,
                fontWeight: FontWeight.w700,
              ),
            ),
          ],
        ),
      ),
    );

    return list;
  }

  void _onDropdownChanged(String? selectedValue) {
    if (selectedValue == null) return;

    if (selectedValue == _customServiceKey) {
      // Switch to Custom Service
      widget.onUpdate(
        widget.item.copyWith(
          serviceId: null,
          serviceName: _customNameController.text.trim(),
          isCustom: true,
        ),
      );
    } else {
      // Switch to Predefined Service
      final selected = widget.services.firstWhere((s) => s.id == selectedValue);
      _priceController.text = selected.price.toStringAsFixed(0);
      widget.onUpdate(
        widget.item.copyWith(
          serviceId: selected.id,
          serviceName: selected.name,
          unitPrice: selected.price,
          isCustom: false,
        ),
      );
    }
  }

  @override
  Widget build(BuildContext context) {
    final isDesktop = MediaQuery.sizeOf(context).width >= 768;

    return Container(
      margin: const EdgeInsets.only(bottom: AppSpacing.sm),
      padding: const EdgeInsets.all(AppSpacing.sm),
      decoration: BoxDecoration(
        color: AppColors.surfaceContainerLowest,
        borderRadius: BorderRadius.circular(AppSpacing.radiusMd),
        border: Border.all(
          color: widget.item.isCustom
              ? AppColors.secondary.withValues(alpha: 0.4)
              : AppColors.outlineVariant,
        ),
      ),
      child: isDesktop ? _buildDesktopRow() : _buildMobileColumn(),
    );
  }

  Widget _buildDesktopRow() {
    return Row(
      crossAxisAlignment: CrossAxisAlignment.center,
      children: [
        // Index badge
        Container(
          width: 24,
          height: 24,
          decoration: BoxDecoration(
            color: widget.item.isCustom
                ? AppColors.secondaryContainer.withValues(alpha: 0.3)
                : AppColors.surfaceContainerHigh,
            shape: BoxShape.circle,
          ),
          child: Center(
            child: Text(
              '${widget.index + 1}',
              style: AppTypography.labelCaps.copyWith(
                fontWeight: FontWeight.bold,
                color: widget.item.isCustom
                    ? AppColors.secondary
                    : AppColors.onSurfaceVariant,
              ),
            ),
          ),
        ),
        const SizedBox(width: AppSpacing.sm),

        // Service Dropdown and Custom Name input if selected
        Expanded(
          flex: 4,
          child: Column(
            crossAxisAlignment: CrossAxisAlignment.start,
            mainAxisSize: MainAxisSize.min,
            children: [
              DropdownButtonFormField<String>(
                initialValue: _currentDropdownValue,
                isExpanded: true,
                decoration: const InputDecoration(
                  labelText: 'Select Service *',
                  isDense: true,
                ),
                items: _buildDropdownItems(),
                onChanged: _onDropdownChanged,
              ),
              if (widget.item.isCustom) ...[
                const SizedBox(height: 6),
                TextField(
                  controller: _customNameController,
                  decoration: const InputDecoration(
                    labelText: 'Custom Service Name *',
                    hintText: 'Enter procedure name...',
                    isDense: true,
                    prefixIcon: Icon(Icons.edit_outlined, size: 16),
                  ),
                  onChanged: (val) {
                    widget.onUpdate(widget.item.copyWith(serviceName: val));
                  },
                ),
              ],
            ],
          ),
        ),
        const SizedBox(width: AppSpacing.sm),

        // Quantity
        SizedBox(
          width: 85,
          child: TextField(
            controller: _qtyController,
            keyboardType: TextInputType.number,
            inputFormatters: [FilteringTextInputFormatter.digitsOnly],
            decoration: const InputDecoration(
              labelText: 'Qty',
              isDense: true,
            ),
            onChanged: (val) {
              final qty = int.tryParse(val) ?? 1;
              widget.onUpdate(widget.item.copyWith(quantity: qty.clamp(1, 9999)));
            },
          ),
        ),
        const SizedBox(width: AppSpacing.sm),

        // Unit Price
        SizedBox(
          width: 120,
          child: TextField(
            controller: _priceController,
            keyboardType: const TextInputType.numberWithOptions(decimal: true),
            inputFormatters: [
              FilteringTextInputFormatter.allow(RegExp(r'^\d*\.?\d{0,2}')),
            ],
            decoration: const InputDecoration(
              labelText: 'Price (₹)',
              isDense: true,
              prefixText: '₹ ',
            ),
            onChanged: (val) {
              final price = double.tryParse(val) ?? 0.0;
              widget.onUpdate(widget.item.copyWith(unitPrice: price.clamp(0.0, 1000000.0)));
            },
          ),
        ),
        const SizedBox(width: AppSpacing.sm),

        // Line Total
        SizedBox(
          width: 110,
          child: Column(
            crossAxisAlignment: CrossAxisAlignment.end,
            mainAxisSize: MainAxisSize.min,
            children: [
              Text(
                'Total',
                style: AppTypography.labelCaps.copyWith(color: AppColors.outline),
              ),
              Text(
                '₹${widget.item.totalAmount.toStringAsFixed(2)}',
                style: AppTypography.bodyMd.copyWith(
                  fontWeight: FontWeight.bold,
                  color: AppColors.onSurface,
                ),
              ),
            ],
          ),
        ),

        // Delete button
        if (widget.canDelete)
          IconButton(
            icon: const Icon(Icons.delete_outline, size: 20),
            color: AppColors.error,
            tooltip: 'Remove Line Item',
            onPressed: widget.onDelete,
          )
        else
          const SizedBox(width: 40),
      ],
    );
  }

  Widget _buildMobileColumn() {
    return Column(
      crossAxisAlignment: CrossAxisAlignment.start,
      children: [
        Row(
          mainAxisAlignment: MainAxisAlignment.spaceBetween,
          children: [
            Text(
              'Item #${widget.index + 1}${widget.item.isCustom ? " (Custom)" : ""}',
              style: AppTypography.labelCaps.copyWith(
                fontWeight: FontWeight.bold,
                color: widget.item.isCustom ? AppColors.secondary : AppColors.primary,
              ),
            ),
            if (widget.canDelete)
              IconButton(
                icon: const Icon(Icons.delete_outline, size: 18),
                color: AppColors.error,
                padding: EdgeInsets.zero,
                constraints: const BoxConstraints(),
                onPressed: widget.onDelete,
              ),
          ],
        ),
        const SizedBox(height: AppSpacing.xs),
        DropdownButtonFormField<String>(
          initialValue: _currentDropdownValue,
          isExpanded: true,
          decoration: const InputDecoration(
            labelText: 'Select Service *',
            isDense: true,
          ),
          items: _buildDropdownItems(),
          onChanged: _onDropdownChanged,
        ),
        if (widget.item.isCustom) ...[
          const SizedBox(height: AppSpacing.xs),
          TextField(
            controller: _customNameController,
            decoration: const InputDecoration(
              labelText: 'Custom Service Name *',
              hintText: 'Enter procedure name...',
              isDense: true,
            ),
            onChanged: (val) {
              widget.onUpdate(widget.item.copyWith(serviceName: val));
            },
          ),
        ],
        const SizedBox(height: AppSpacing.xs),
        Row(
          children: [
            Expanded(
              child: TextField(
                controller: _qtyController,
                keyboardType: TextInputType.number,
                inputFormatters: [FilteringTextInputFormatter.digitsOnly],
                decoration: const InputDecoration(
                  labelText: 'Qty',
                  isDense: true,
                ),
                onChanged: (val) {
                  final qty = int.tryParse(val) ?? 1;
                  widget.onUpdate(widget.item.copyWith(quantity: qty.clamp(1, 9999)));
                },
              ),
            ),
            const SizedBox(width: AppSpacing.sm),
            Expanded(
              flex: 2,
              child: TextField(
                controller: _priceController,
                keyboardType: const TextInputType.numberWithOptions(decimal: true),
                inputFormatters: [
                  FilteringTextInputFormatter.allow(RegExp(r'^\d*\.?\d{0,2}')),
                ],
                decoration: const InputDecoration(
                  labelText: 'Price (₹)',
                  isDense: true,
                  prefixText: '₹ ',
                ),
                onChanged: (val) {
                  final price = double.tryParse(val) ?? 0.0;
                  widget.onUpdate(widget.item.copyWith(unitPrice: price.clamp(0.0, 1000000.0)));
                },
              ),
            ),
            const SizedBox(width: AppSpacing.sm),
            Column(
              crossAxisAlignment: CrossAxisAlignment.end,
              children: [
                Text('Total', style: AppTypography.labelCaps.copyWith(color: AppColors.outline)),
                Text(
                  '₹${widget.item.totalAmount.toStringAsFixed(2)}',
                  style: AppTypography.bodyMd.copyWith(
                    fontWeight: FontWeight.bold,
                    color: AppColors.onSurface,
                  ),
                ),
              ],
            ),
          ],
        ),
      ],
    );
  }
}
