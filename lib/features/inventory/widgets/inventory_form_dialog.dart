import 'package:flutter/material.dart';
import 'package:flutter/services.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';

import '../../../core/theme/app_colors.dart';
import '../../../core/theme/app_spacing.dart';
import '../../../core/theme/app_typography.dart';
import '../../../shared/widgets/adaptive_dialog_shell.dart';
import '../../../shared/widgets/responsive_form_row.dart';
import '../../../shared/widgets/mkes_text_field.dart';
import '../models/inventory_item.dart';
import '../providers/inventory_provider.dart';
import '../../vendors/providers/vendor_provider.dart';

/// Dialog for creating or editing an [InventoryItem].
class InventoryFormDialog extends ConsumerStatefulWidget {
  const InventoryFormDialog({
    super.key,
    this.item,
  });

  final InventoryItem? item;

  @override
  ConsumerState<InventoryFormDialog> createState() => _InventoryFormDialogState();
}

class _InventoryFormDialogState extends ConsumerState<InventoryFormDialog> {
  final _formKey = GlobalKey<FormState>();

  late final TextEditingController _nameController;
  late final TextEditingController _categoryController;
  late final TextEditingController _descriptionController;
  late final TextEditingController _stockController;
  late final TextEditingController _unitController;
  late final TextEditingController _skuController;
  late final TextEditingController _minStockController;
  late final TextEditingController _priceController;
  late final TextEditingController _brandController;

  DateTime? _expiryDate;
  String? _selectedDepartment;
  String? _selectedVendorId;
  bool _isActive = true;
  bool _isLoading = false;
  String? _errorMessage;

  bool get _isEditing => widget.item != null;

  @override
  void initState() {
    super.initState();
    final item = widget.item;

    _nameController = TextEditingController(text: item?.name ?? '');
    _categoryController = TextEditingController(
      text: item?.category ?? InventoryCategories.defaults.first,
    );
    _descriptionController = TextEditingController(text: item?.description ?? '');
    _stockController = TextEditingController(
      text: item != null
          ? (item.currentStock % 1 == 0
              ? item.currentStock.toInt().toString()
              : item.currentStock.toString())
          : '0',
    );
    _unitController = TextEditingController(text: item?.unit ?? 'pcs');
    _skuController = TextEditingController(text: item?.sku ?? '');
    _minStockController = TextEditingController(
      text: item?.minimumStock != null
          ? (item!.minimumStock! % 1 == 0
              ? item.minimumStock!.toInt().toString()
              : item.minimumStock!.toString())
          : '',
    );
    _priceController = TextEditingController(
      text: item?.price != null ? item!.price!.toString() : '',
    );
    _brandController = TextEditingController(text: item?.brand ?? '');

    _expiryDate = item?.expiryDate;
    _selectedDepartment = item?.department;
    _selectedVendorId = item?.vendorId;
    _isActive = item?.isActive ?? true;
  }

  @override
  void dispose() {
    _nameController.dispose();
    _categoryController.dispose();
    _descriptionController.dispose();
    _stockController.dispose();
    _unitController.dispose();
    _skuController.dispose();
    _minStockController.dispose();
    _priceController.dispose();
    _brandController.dispose();
    super.dispose();
  }

  Future<void> _pickExpiryDate() async {
    final picked = await showDatePicker(
      context: context,
      initialDate: _expiryDate ?? DateTime.now().add(const Duration(days: 365)),
      firstDate: DateTime(2000),
      lastDate: DateTime.now().add(const Duration(days: 365 * 15)),
      helpText: 'SELECT EXPIRY DATE',
    );
    if (picked != null) {
      setState(() => _expiryDate = picked);
    }
  }

  Future<void> _submit() async {
    setState(() => _errorMessage = null);

    if (!_formKey.currentState!.validate()) {
      return;
    }

    final stockVal = double.tryParse(_stockController.text.trim());
    if (stockVal == null) {
      setState(() => _errorMessage = 'Stock must be a valid number.');
      return;
    }
    if (stockVal < 0) {
      setState(() => _errorMessage = 'Stock cannot be negative.');
      return;
    }

    final minStockText = _minStockController.text.trim();
    final minStockVal = minStockText.isNotEmpty ? double.tryParse(minStockText) : null;
    if (minStockText.isNotEmpty && (minStockVal == null || minStockVal < 0)) {
      setState(() => _errorMessage = 'Minimum stock must be a non-negative number.');
      return;
    }

    final priceText = _priceController.text.trim();
    final priceVal = priceText.isNotEmpty ? double.tryParse(priceText) : null;
    if (priceText.isNotEmpty && (priceVal == null || priceVal < 0)) {
      setState(() => _errorMessage = 'Unit price must be a non-negative number.');
      return;
    }

    setState(() => _isLoading = true);

    try {
      final name = _nameController.text.trim();
      final category = _categoryController.text.trim();
      final unit = _unitController.text.trim();
      final desc = _descriptionController.text.trim();
      final sku = _skuController.text.trim();
      final brand = _brandController.text.trim();

      final itemToSave = InventoryItem(
        id: widget.item?.id ?? '',
        name: name,
        category: category,
        description: desc.isNotEmpty ? desc : null,
        currentStock: stockVal,
        unit: unit,
        sku: sku.isNotEmpty ? sku : null,
        department: _selectedDepartment?.isNotEmpty == true ? _selectedDepartment : null,
        minimumStock: minStockVal,
        expiryDate: _expiryDate,
        brand: brand.isNotEmpty ? brand : null,
        price: priceVal,
        vendorId: _selectedVendorId,
        lastQuantitySupplied: widget.item?.lastQuantitySupplied,
        lastTotalAmount: widget.item?.lastTotalAmount,
        isActive: _isActive,
      );

      final notifier = ref.read(inventoryProvider.notifier);
      final InventoryItem saved;

      if (_isEditing) {
        saved = await notifier.updateItem(itemToSave);
      } else {
        saved = await notifier.createItem(itemToSave);
      }

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
                    _isEditing
                        ? 'Inventory item "${saved.name}" updated successfully!'
                        : 'Inventory item "${saved.name}" added successfully!',
                    style: const TextStyle(color: Colors.white),
                  ),
                ),
              ],
            ),
          ),
        );
        Navigator.of(context).pop(saved);
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
    final dialogConstraints = AdaptiveDialogShell.constraintsFor(
      context,
      maxMobileWidth: double.infinity,
      maxTabletWidth: 540.0,
      maxDesktopWidth: 640.0,
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
                    crossAxisAlignment: CrossAxisAlignment.stretch,
                    children: [
                      if (_errorMessage != null) ...[
                        Container(
                          padding: const EdgeInsets.all(AppSpacing.sm),
                          decoration: BoxDecoration(
                            color: AppColors.errorContainer.withValues(alpha: 0.15),
                            borderRadius: BorderRadius.circular(AppSpacing.radiusMd),
                            border: Border.all(color: AppColors.error),
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
                                    fontWeight: FontWeight.w600,
                                  ),
                                ),
                              ),
                            ],
                          ),
                        ),
                        const SizedBox(height: AppSpacing.md),
                      ],

                      // 1. Item Name (Required)
                      MkesTextField(
                        controller: _nameController,
                        label: 'ITEM NAME *',
                        hintText: 'e.g. Amoxicillin 500mg, Titanium Frame, Latex Gloves',
                        prefixIcon: Icons.medication_outlined,
                        validator: (value) {
                          if (value == null || value.trim().isEmpty) {
                            return 'Item name is required';
                          }
                          return null;
                        },
                      ),
                      const SizedBox(height: AppSpacing.md),

                      // 2. Category selection with presets (Required)
                      Text(
                        'CATEGORY *',
                        style: AppTypography.labelCaps.copyWith(
                          color: AppColors.onSurfaceVariant,
                        ),
                      ),
                      const SizedBox(height: AppSpacing.xs),
                      TextFormField(
                        controller: _categoryController,
                        decoration: InputDecoration(
                          hintText: 'e.g. Pharmaceuticals, Optical & Frames',
                          prefixIcon: const Icon(
                            Icons.category_outlined,
                            color: AppColors.onSurfaceVariant,
                            size: 20,
                          ),
                          fillColor: AppColors.surfaceContainerLow,
                        ),
                        style: AppTypography.bodyMd,
                        validator: (value) {
                          if (value == null || value.trim().isEmpty) {
                            return 'Category is required';
                          }
                          return null;
                        },
                      ),
                      const SizedBox(height: AppSpacing.xs),
                      Wrap(
                        spacing: 6,
                        runSpacing: 4,
                        children: InventoryCategories.defaults.take(6).map((cat) {
                          final isSelected =
                              _categoryController.text.trim().toLowerCase() ==
                                  cat.toLowerCase();
                          return ActionChip(
                            label: Text(
                              cat,
                              style: TextStyle(
                                fontSize: 11,
                                color: isSelected
                                    ? AppColors.primary
                                    : AppColors.onSurfaceVariant,
                                fontWeight: isSelected
                                    ? FontWeight.w700
                                    : FontWeight.normal,
                              ),
                            ),
                            backgroundColor: isSelected
                                ? AppColors.primaryContainer.withValues(alpha: 0.2)
                                : AppColors.surfaceContainerLow,
                            padding: const EdgeInsets.symmetric(horizontal: 4),
                            visualDensity: VisualDensity.compact,
                            onPressed: () {
                              setState(() {
                                _categoryController.text = cat;
                              });
                            },
                          );
                        }).toList(),
                      ),
                      const SizedBox(height: AppSpacing.md),

                      // 3. Stock & Unit row (Both Required)
                      ResponsiveFormRow(
                        breakpoint: 480,
                        flexes: const [3, 2],
                        children: [
                          MkesTextField(
                            controller: _stockController,
                            label: 'CURRENT STOCK *',
                            hintText: '0',
                            prefixIcon: Icons.inventory_2_outlined,
                            keyboardType: const TextInputType.numberWithOptions(
                              decimal: true,
                            ),
                            inputFormatters: [
                              FilteringTextInputFormatter.allow(
                                RegExp(r'^\d*\.?\d*'),
                              ),
                            ],
                            validator: (value) {
                              if (value == null || value.trim().isEmpty) {
                                return 'Stock quantity is required';
                              }
                              final numVal = double.tryParse(value.trim());
                              if (numVal == null) {
                                return 'Must be numeric';
                              }
                              if (numVal < 0) {
                                return 'Cannot be negative';
                              }
                              return null;
                            },
                          ),
                          Column(
                            crossAxisAlignment: CrossAxisAlignment.start,
                            children: [
                              Text(
                                'UNIT *',
                                style: AppTypography.labelCaps.copyWith(
                                  color: AppColors.onSurfaceVariant,
                                ),
                              ),
                              const SizedBox(height: AppSpacing.xs),
                              TextFormField(
                                controller: _unitController,
                                decoration: const InputDecoration(
                                  hintText: 'e.g. pcs',
                                  fillColor: AppColors.surfaceContainerLow,
                                ),
                                style: AppTypography.bodyMd,
                                validator: (value) {
                                  if (value == null || value.trim().isEmpty) {
                                    return 'Unit required';
                                  }
                                  return null;
                                },
                              ),
                            ],
                          ),
                        ],
                      ),
                      const SizedBox(height: AppSpacing.xs),
                      Wrap(
                        spacing: 4,
                        children: ['pcs', 'boxes', 'bottles', 'vials', 'pairs', 'packs', 'units']
                            .map((unit) => ActionChip(
                                  label: Text(unit, style: const TextStyle(fontSize: 10)),
                                  visualDensity: VisualDensity.compact,
                                  padding: const EdgeInsets.symmetric(horizontal: 2),
                                  onPressed: () {
                                    setState(() {
                                      _unitController.text = unit;
                                    });
                                  },
                                ))
                            .toList(),
                      ),
                      const SizedBox(height: AppSpacing.md),

                      // 4. Department & SKU Row (Optional)
                      ResponsiveFormRow(
                        breakpoint: 480,
                        children: [
                          Column(
                            crossAxisAlignment: CrossAxisAlignment.start,
                            children: [
                              Text(
                                'DEPARTMENT',
                                style: AppTypography.labelCaps.copyWith(
                                  color: AppColors.onSurfaceVariant,
                                ),
                              ),
                              const SizedBox(height: AppSpacing.xs),
                              DropdownButtonFormField<String?>(
                                isExpanded: true,
                                initialValue: _selectedDepartment,
                                decoration: InputDecoration(
                                  prefixIcon: const Icon(
                                    Icons.business_outlined,
                                    size: 20,
                                    color: AppColors.onSurfaceVariant,
                                  ),
                                  fillColor: AppColors.surfaceContainerLow,
                                ),
                                items: const [
                                  DropdownMenuItem(
                                    value: null,
                                    child: Text('All / General'),
                                  ),
                                  DropdownMenuItem(
                                    value: 'eye',
                                    child: Text('Eye Care'),
                                  ),
                                  DropdownMenuItem(
                                    value: 'dental',
                                    child: Text('Dental Clinic'),
                                  ),
                                  DropdownMenuItem(
                                    value: 'optical',
                                    child: Text('Optical Store'),
                                  ),
                                  DropdownMenuItem(
                                    value: 'general',
                                    child: Text('General'),
                                  ),
                                ],
                                onChanged: (val) {
                                  setState(() => _selectedDepartment = val);
                                },
                              ),
                            ],
                          ),
                          MkesTextField(
                            controller: _skuController,
                            label: 'SKU / CODE',
                            hintText: 'e.g. MED-AMX-500',
                            prefixIcon: Icons.qr_code_outlined,
                          ),
                        ],
                      ),
                      const SizedBox(height: AppSpacing.md),

                      // 5. Minimum Stock Threshold & Unit Price Row (Optional)
                      ResponsiveFormRow(
                        breakpoint: 480,
                        children: [
                          MkesTextField(
                            controller: _minStockController,
                            label: 'MIN. STOCK THRESHOLD',
                            hintText: 'e.g. 10',
                            prefixIcon: Icons.warning_amber_outlined,
                            keyboardType: const TextInputType.numberWithOptions(
                              decimal: true,
                            ),
                            inputFormatters: [
                              FilteringTextInputFormatter.allow(
                                RegExp(r'^\d*\.?\d*'),
                              ),
                            ],
                            validator: (value) {
                              if (value == null || value.trim().isEmpty) {
                                return null;
                              }
                              final val = double.tryParse(value.trim());
                              if (val == null || val < 0) {
                                return 'Must be >= 0';
                              }
                              return null;
                            },
                          ),
                          MkesTextField(
                            controller: _priceController,
                            label: 'UNIT PRICE (₹)',
                            hintText: 'e.g. 150.00',
                            prefixIcon: Icons.currency_rupee_outlined,
                            keyboardType: const TextInputType.numberWithOptions(
                              decimal: true,
                            ),
                            inputFormatters: [
                              FilteringTextInputFormatter.allow(
                                RegExp(r'^\d*\.?\d*'),
                              ),
                            ],
                            validator: (value) {
                              if (value == null || value.trim().isEmpty) {
                                return null;
                              }
                              final val = double.tryParse(value.trim());
                              if (val == null || val < 0) {
                                return 'Must be >= 0';
                              }
                              return null;
                            },
                          ),
                        ],
                      ),
                      const SizedBox(height: AppSpacing.md),

                      // Brand & Expiry Date Row (Optional)
                      ResponsiveFormRow(
                        breakpoint: 480,
                        children: [
                          MkesTextField(
                            controller: _brandController,
                            label: 'BRAND / MANUFACTURER',
                            hintText: 'e.g. Cipla, Ray-Ban, 3M',
                            prefixIcon: Icons.branding_watermark_outlined,
                          ),
                          Column(
                            crossAxisAlignment: CrossAxisAlignment.start,
                            children: [
                              Text(
                                'EXPIRY DATE',
                                style: AppTypography.labelCaps.copyWith(
                                  color: AppColors.onSurfaceVariant,
                                ),
                              ),
                              const SizedBox(height: AppSpacing.xs),
                              InkWell(
                                borderRadius: BorderRadius.circular(AppSpacing.radiusMd),
                                onTap: _pickExpiryDate,
                                child: InputDecorator(
                                  decoration: InputDecoration(
                                    hintText: 'Select date...',
                                    prefixIcon: const Icon(
                                      Icons.calendar_today_outlined,
                                      size: 20,
                                      color: AppColors.onSurfaceVariant,
                                    ),
                                    suffixIcon: _expiryDate != null
                                        ? IconButton(
                                            icon: const Icon(Icons.clear, size: 18),
                                            tooltip: 'Clear expiry date',
                                            onPressed: () => setState(() => _expiryDate = null),
                                          )
                                        : null,
                                    fillColor: AppColors.surfaceContainerLow,
                                  ),
                                  child: Text(
                                    _expiryDate != null
                                        ? '${_expiryDate!.year}-${_expiryDate!.month.toString().padLeft(2, '0')}-${_expiryDate!.day.toString().padLeft(2, '0')}'
                                        : 'No expiry date set',
                                    style: AppTypography.bodyMd.copyWith(
                                      color: _expiryDate != null
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
                      const SizedBox(height: AppSpacing.md),

                      // Supplier / Vendor Selection (Optional)
                      Consumer(
                        builder: (context, ref, _) {
                          final vendors = (ref.watch(vendorsProvider).value ?? [])
                              .where((v) => v.isActive)
                              .toList();
                          return Column(
                            crossAxisAlignment: CrossAxisAlignment.start,
                            children: [
                              Text(
                                'SUPPLIER / VENDOR (OPTIONAL)',
                                style: AppTypography.labelCaps.copyWith(
                                  color: AppColors.onSurfaceVariant,
                                ),
                              ),
                              const SizedBox(height: AppSpacing.xs),
                              DropdownButtonFormField<String?>(
                                isExpanded: true,
                                initialValue: _selectedVendorId,
                                decoration: InputDecoration(
                                  hintText: 'Select supplier / vendor...',
                                  prefixIcon: const Icon(
                                    Icons.storefront_outlined,
                                    size: 20,
                                    color: AppColors.onSurfaceVariant,
                                  ),
                                  fillColor: AppColors.surfaceContainerLow,
                                ),
                                items: [
                                  const DropdownMenuItem<String?>(
                                    value: null,
                                    child: Text('None / Unassigned'),
                                  ),
                                  ...vendors.map((v) {
                                    return DropdownMenuItem<String?>(
                                      value: v.id,
                                      child: Text(
                                        v.contactPerson != null
                                            ? '${v.name} (${v.contactPerson})'
                                            : v.name,
                                        overflow: TextOverflow.ellipsis,
                                      ),
                                    );
                                  }),
                                ],
                                onChanged: (val) {
                                  setState(() => _selectedVendorId = val);
                                },
                              ),
                            ],
                          );
                        },
                      ),
                      const SizedBox(height: AppSpacing.md),

                      // 6. Description / Remarks (Optional)
                      MkesTextField(
                        controller: _descriptionController,
                        label: 'DESCRIPTION / REMARKS',
                        hintText: 'Storage instructions, batch details, usage notes...',
                        maxLines: 3,
                        prefixIcon: Icons.notes_outlined,
                      ),
                      const SizedBox(height: AppSpacing.sm),

                      // 7. Active Status Switch
                      SwitchListTile(
                        contentPadding: EdgeInsets.zero,
                        title: Text(
                          'Item Active Status',
                          style: AppTypography.bodyMd.copyWith(
                            fontWeight: FontWeight.w600,
                          ),
                        ),
                        subtitle: Text(
                          _isActive
                              ? 'Item is actively available in clinic workflow'
                              : 'Item is archived / inactive',
                          style: AppTypography.bodySm.copyWith(
                            color: AppColors.onSurfaceVariant,
                          ),
                        ),
                        value: _isActive,
                        activeTrackColor: AppColors.primary,
                        onChanged: (val) => setState(() => _isActive = val),
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
                    Icons.inventory_2_outlined,
                    color: AppColors.primary,
                    size: 20,
                  ),
                ),
                const SizedBox(width: AppSpacing.sm),
                Expanded(
                  child: Text(
                    _isEditing ? 'Edit Inventory Item' : 'New Inventory Item',
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
        crossAxisAlignment: WrapCrossAlignment.center,
        spacing: AppSpacing.sm,
        runSpacing: AppSpacing.xs,
        children: [
          TextButton(
            onPressed: _isLoading ? null : () => Navigator.of(context).pop(),
            child: const Text('Cancel'),
          ),
          FilledButton.icon(
            onPressed: _isLoading ? null : _submit,
            icon: _isLoading
                ? const SizedBox(
                    width: 18,
                    height: 18,
                    child: CircularProgressIndicator(
                      strokeWidth: 2,
                      color: Colors.white,
                    ),
                  )
                : const Icon(Icons.check, size: 18),
            label: Text(_isEditing ? 'Save Changes' : 'Create Item'),
            style: FilledButton.styleFrom(
              backgroundColor: AppColors.primary,
              foregroundColor: AppColors.onPrimary,
              padding: const EdgeInsets.symmetric(
                horizontal: AppSpacing.lg,
                vertical: AppSpacing.sm,
              ),
            ),
          ),
        ],
      ),
    );
  }
}
