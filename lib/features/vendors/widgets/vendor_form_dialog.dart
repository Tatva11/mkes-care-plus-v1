import 'package:flutter/material.dart';
import 'package:flutter/services.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';

import '../../../core/theme/app_colors.dart';
import '../../../core/theme/app_spacing.dart';
import '../../../core/theme/app_typography.dart';
import '../models/vendor.dart';
import '../providers/vendor_provider.dart';

/// Dialog for creating or editing a [Vendor].
class VendorFormDialog extends ConsumerStatefulWidget {
  const VendorFormDialog({
    super.key,
    this.vendor,
  });

  final Vendor? vendor;

  @override
  ConsumerState<VendorFormDialog> createState() => _VendorFormDialogState();
}

class _VendorFormDialogState extends ConsumerState<VendorFormDialog> {
  final _formKey = GlobalKey<FormState>();

  late final TextEditingController _nameController;
  late final TextEditingController _contactPersonController;
  late final TextEditingController _phoneController;
  late final TextEditingController _emailController;
  late final TextEditingController _addressController;
  late final TextEditingController _productsController;
  late final TextEditingController _quantityController;
  late final TextEditingController _totalAmountController;
  late final TextEditingController _remarksController;

  DateTime? _lastOrderDate;
  DateTime? _lastDeliveryDate;
  bool _isActive = true;
  bool _isSubmitting = false;
  String? _errorMessage;

  bool get _isEditing => widget.vendor != null;

  @override
  void initState() {
    super.initState();
    final v = widget.vendor;

    _nameController = TextEditingController(text: v?.name ?? '');
    _contactPersonController =
        TextEditingController(text: v?.contactPerson ?? '');
    _phoneController = TextEditingController(text: v?.phone ?? '');
    _emailController = TextEditingController(text: v?.email ?? '');
    _addressController = TextEditingController(text: v?.address ?? '');
    _productsController =
        TextEditingController(text: v?.productsSupplied.join(', ') ?? '');
    _quantityController = TextEditingController(
      text: v?.lastQuantity != null
          ? (v!.lastQuantity! % 1 == 0
              ? v.lastQuantity!.toInt().toString()
              : v.lastQuantity!.toString())
          : '',
    );
    _totalAmountController = TextEditingController(
      text: v?.lastTotalAmount != null
          ? (v!.lastTotalAmount! % 1 == 0
              ? v.lastTotalAmount!.toInt().toString()
              : v.lastTotalAmount!.toString())
          : '',
    );
    _remarksController = TextEditingController(text: v?.remarks ?? '');

    _quantityController.addListener(_onPriceRelatedChange);
    _totalAmountController.addListener(_onPriceRelatedChange);

    _lastOrderDate = v?.lastOrderDate;
    _lastDeliveryDate = v?.lastDeliveryDate;
    _isActive = v?.isActive ?? true;
  }

  void _onPriceRelatedChange() {
    setState(() {});
  }

  @override
  void dispose() {
    _quantityController.removeListener(_onPriceRelatedChange);
    _totalAmountController.removeListener(_onPriceRelatedChange);
    _nameController.dispose();
    _contactPersonController.dispose();
    _phoneController.dispose();
    _emailController.dispose();
    _addressController.dispose();
    _productsController.dispose();
    _quantityController.dispose();
    _totalAmountController.dispose();
    _remarksController.dispose();
    super.dispose();
  }

  Future<void> _pickDate({
    required bool isOrderDate,
  }) async {
    final initialDate = isOrderDate
        ? (_lastOrderDate ?? DateTime.now())
        : (_lastDeliveryDate ?? DateTime.now());

    final picked = await showDatePicker(
      context: context,
      initialDate: initialDate,
      firstDate: DateTime(2020),
      lastDate: DateTime.now().add(const Duration(days: 365)),
      helpText: isOrderDate ? 'SELECT LAST ORDER DATE' : 'SELECT LAST DELIVERY DATE',
    );

    if (picked != null) {
      setState(() {
        if (isOrderDate) {
          _lastOrderDate = picked;
        } else {
          _lastDeliveryDate = picked;
        }
      });
    }
  }

  Future<void> _submit() async {
    setState(() => _errorMessage = null);

    if (!_formKey.currentState!.validate()) {
      return;
    }

    final rawQty = _quantityController.text.trim();
    double? parsedQty;
    if (rawQty.isNotEmpty) {
      parsedQty = double.tryParse(rawQty);
      if (parsedQty == null || parsedQty < 0) {
        setState(() => _errorMessage = 'Last quantity must be a non-negative number.');
        return;
      }
    }

    final rawTotal = _totalAmountController.text.trim();
    double? parsedTotal;
    if (rawTotal.isNotEmpty) {
      parsedTotal = double.tryParse(rawTotal);
      if (parsedTotal == null || parsedTotal < 0) {
        setState(() => _errorMessage = 'Total payment amount must be a non-negative number.');
        return;
      }
    }

    final rawProducts = _productsController.text.trim();
    final productsList = rawProducts.isEmpty
        ? <String>[]
        : rawProducts
            .split(',')
            .map((p) => p.trim())
            .where((p) => p.isNotEmpty)
            .toList();

    setState(() => _isSubmitting = true);

    try {
      final vendorToSave = Vendor(
        id: widget.vendor?.id ?? '',
        name: _nameController.text.trim(),
        contactPerson: _contactPersonController.text.trim().isNotEmpty
            ? _contactPersonController.text.trim()
            : null,
        phone: _phoneController.text.trim().isNotEmpty
            ? _phoneController.text.trim()
            : null,
        email: _emailController.text.trim().isNotEmpty
            ? _emailController.text.trim()
            : null,
        address: _addressController.text.trim().isNotEmpty
            ? _addressController.text.trim()
            : null,
        productsSupplied: productsList,
        lastOrderDate: _lastOrderDate,
        lastDeliveryDate: _lastDeliveryDate,
        lastQuantity: parsedQty,
        lastTotalAmount: parsedTotal,
        remarks: _remarksController.text.trim().isNotEmpty
            ? _remarksController.text.trim()
            : null,
        isActive: _isActive,
      );

      final notifier = ref.read(vendorsProvider.notifier);
      final Vendor result;

      if (_isEditing) {
        result = await notifier.updateVendor(vendorToSave);
      } else {
        result = await notifier.createVendor(vendorToSave);
      }

      if (mounted) {
        Navigator.of(context).pop(result);
        ScaffoldMessenger.of(context).showSnackBar(
          SnackBar(
            backgroundColor: Colors.green.shade700,
            content: Text(
              _isEditing
                  ? 'Vendor "${result.name}" updated successfully.'
                  : 'Vendor "${result.name}" added successfully.',
            ),
          ),
        );
      }
    } catch (e) {
      if (mounted) {
        setState(() {
          _isSubmitting = false;
          _errorMessage = e.toString().replaceFirst('Exception: ', '');
        });
      }
    }
  }

  String _formatDate(DateTime? date) {
    if (date == null) return 'Not set';
    return '${date.year}-${date.month.toString().padLeft(2, '0')}-${date.day.toString().padLeft(2, '0')}';
  }

  @override
  Widget build(BuildContext context) {
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
                      size: 22,
                    ),
                  ),
                  const SizedBox(width: AppSpacing.sm),
                  Expanded(
                    child: Text(
                      _isEditing ? 'Edit Vendor' : 'Add New Vendor',
                      style: AppTypography.headlineMd.copyWith(
                        fontWeight: FontWeight.w700,
                        color: AppColors.primary,
                      ),
                    ),
                  ),
                  IconButton(
                    icon: const Icon(Icons.close),
                    onPressed: _isSubmitting ? null : () => Navigator.of(context).pop(),
                  ),
                ],
              ),
            ),

            // Form Content
            Flexible(
              child: SingleChildScrollView(
                padding: const EdgeInsets.all(AppSpacing.lg),
                child: Form(
                  key: _formKey,
                  child: Column(
                    crossAxisAlignment: CrossAxisAlignment.start,
                    children: [
                      // Error banner if any
                      if (_errorMessage != null) ...[
                        Container(
                          padding: const EdgeInsets.all(AppSpacing.sm),
                          decoration: BoxDecoration(
                            color: AppColors.errorContainer,
                            borderRadius: BorderRadius.circular(AppSpacing.radiusMd),
                            border: Border.all(color: AppColors.error),
                          ),
                          child: Row(
                            children: [
                              const Icon(Icons.error_outline, color: AppColors.error, size: 20),
                              const SizedBox(width: AppSpacing.sm),
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

                      // 1. Vendor Name (Required)
                      Text(
                        'VENDOR NAME *',
                        style: AppTypography.labelCaps.copyWith(
                          color: AppColors.onSurfaceVariant,
                        ),
                      ),
                      const SizedBox(height: AppSpacing.xs),
                      TextFormField(
                        controller: _nameController,
                        autofocus: !_isEditing,
                        decoration: InputDecoration(
                          hintText: 'E.g. Apollo Pharma Distributors',
                          prefixIcon: const Icon(Icons.business),
                          border: OutlineInputBorder(
                            borderRadius: BorderRadius.circular(AppSpacing.radiusMd),
                          ),
                          filled: true,
                          fillColor: AppColors.surfaceContainerLow,
                        ),
                        validator: (value) {
                          if (value == null || value.trim().isEmpty) {
                            return 'Vendor name is required.';
                          }
                          if (value.trim().length < 2) {
                            return 'Vendor name must be at least 2 characters.';
                          }
                          return null;
                        },
                      ),
                      const SizedBox(height: AppSpacing.md),

                      // 2. Contact Person & Phone Row
                      Row(
                        children: [
                          Expanded(
                            child: Column(
                              crossAxisAlignment: CrossAxisAlignment.start,
                              children: [
                                Text(
                                  'CONTACT PERSON',
                                  style: AppTypography.labelCaps.copyWith(
                                    color: AppColors.onSurfaceVariant,
                                  ),
                                ),
                                const SizedBox(height: AppSpacing.xs),
                                TextFormField(
                                  controller: _contactPersonController,
                                  decoration: InputDecoration(
                                    hintText: 'E.g. John Doe',
                                    prefixIcon: const Icon(Icons.person_outline),
                                    border: OutlineInputBorder(
                                      borderRadius: BorderRadius.circular(AppSpacing.radiusMd),
                                    ),
                                    filled: true,
                                    fillColor: AppColors.surfaceContainerLow,
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
                                  'PHONE NUMBER',
                                  style: AppTypography.labelCaps.copyWith(
                                    color: AppColors.onSurfaceVariant,
                                  ),
                                ),
                                const SizedBox(height: AppSpacing.xs),
                                TextFormField(
                                  controller: _phoneController,
                                  keyboardType: TextInputType.phone,
                                  decoration: InputDecoration(
                                    hintText: 'E.g. +91 9876543210',
                                    prefixIcon: const Icon(Icons.phone_outlined),
                                    border: OutlineInputBorder(
                                      borderRadius: BorderRadius.circular(AppSpacing.radiusMd),
                                    ),
                                    filled: true,
                                    fillColor: AppColors.surfaceContainerLow,
                                  ),
                                  validator: (value) {
                                    if (value == null || value.trim().isEmpty) {
                                      return null;
                                    }
                                    final phoneDigits =
                                        value.replaceAll(RegExp(r'[\s\-\(\)\+]'), '');
                                    if (phoneDigits.length < 7 || phoneDigits.length > 15) {
                                      return 'Enter a valid phone number.';
                                    }
                                    return null;
                                  },
                                ),
                              ],
                            ),
                          ),
                        ],
                      ),
                      const SizedBox(height: AppSpacing.md),

                      // 3. Email & Address Row
                      Row(
                        children: [
                          Expanded(
                            child: Column(
                              crossAxisAlignment: CrossAxisAlignment.start,
                              children: [
                                Text(
                                  'EMAIL ADDRESS',
                                  style: AppTypography.labelCaps.copyWith(
                                    color: AppColors.onSurfaceVariant,
                                  ),
                                ),
                                const SizedBox(height: AppSpacing.xs),
                                TextFormField(
                                  controller: _emailController,
                                  keyboardType: TextInputType.emailAddress,
                                  decoration: InputDecoration(
                                    hintText: 'vendor@domain.com',
                                    prefixIcon: const Icon(Icons.email_outlined),
                                    border: OutlineInputBorder(
                                      borderRadius: BorderRadius.circular(AppSpacing.radiusMd),
                                    ),
                                    filled: true,
                                    fillColor: AppColors.surfaceContainerLow,
                                  ),
                                  validator: (value) {
                                    if (value == null || value.trim().isEmpty) {
                                      return null;
                                    }
                                    final emailRegex =
                                        RegExp(r'^[\w-\.]+@([\w-]+\.)+[\w-]{2,4}$');
                                    if (!emailRegex.hasMatch(value.trim())) {
                                      return 'Enter a valid email address.';
                                    }
                                    return null;
                                  },
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
                                  'ADDRESS / LOCATION',
                                  style: AppTypography.labelCaps.copyWith(
                                    color: AppColors.onSurfaceVariant,
                                  ),
                                ),
                                const SizedBox(height: AppSpacing.xs),
                                TextFormField(
                                  controller: _addressController,
                                  decoration: InputDecoration(
                                    hintText: 'City, Warehouse or Address',
                                    prefixIcon: const Icon(Icons.location_on_outlined),
                                    border: OutlineInputBorder(
                                      borderRadius: BorderRadius.circular(AppSpacing.radiusMd),
                                    ),
                                    filled: true,
                                    fillColor: AppColors.surfaceContainerLow,
                                  ),
                                ),
                              ],
                            ),
                          ),
                        ],
                      ),
                      const SizedBox(height: AppSpacing.md),

                      // 4. Products Supplied
                      Text(
                        'PRODUCTS SUPPLIED (COMMA-SEPARATED)',
                        style: AppTypography.labelCaps.copyWith(
                          color: AppColors.onSurfaceVariant,
                        ),
                      ),
                      const SizedBox(height: AppSpacing.xs),
                      TextFormField(
                        controller: _productsController,
                        decoration: InputDecoration(
                          hintText: 'E.g. Amoxicillin, Gauze, Syringes, Normal Saline',
                          prefixIcon: const Icon(Icons.category_outlined),
                          border: OutlineInputBorder(
                            borderRadius: BorderRadius.circular(AppSpacing.radiusMd),
                          ),
                          filled: true,
                          fillColor: AppColors.surfaceContainerLow,
                        ),
                      ),
                      const SizedBox(height: AppSpacing.md),

                      // 5. Last Order & Last Delivery Dates
                      Row(
                        children: [
                          Expanded(
                            child: Column(
                              crossAxisAlignment: CrossAxisAlignment.start,
                              children: [
                                Text(
                                  'LAST ORDER DATE',
                                  style: AppTypography.labelCaps.copyWith(
                                    color: AppColors.onSurfaceVariant,
                                  ),
                                ),
                                const SizedBox(height: AppSpacing.xs),
                                InkWell(
                                  onTap: () => _pickDate(isOrderDate: true),
                                  borderRadius:
                                      BorderRadius.circular(AppSpacing.radiusMd),
                                  child: InputDecorator(
                                    decoration: InputDecoration(
                                      prefixIcon: const Icon(Icons.calendar_today_outlined),
                                      suffixIcon: _lastOrderDate != null
                                          ? IconButton(
                                              icon: const Icon(Icons.clear, size: 18),
                                              onPressed: () =>
                                                  setState(() => _lastOrderDate = null),
                                            )
                                          : null,
                                      border: OutlineInputBorder(
                                        borderRadius:
                                            BorderRadius.circular(AppSpacing.radiusMd),
                                      ),
                                      filled: true,
                                      fillColor: AppColors.surfaceContainerLow,
                                    ),
                                    child: Text(
                                      _formatDate(_lastOrderDate),
                                      style: TextStyle(
                                        color: _lastOrderDate != null
                                            ? AppColors.onSurface
                                            : AppColors.onSurfaceVariant,
                                      ),
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
                                  'LAST DELIVERY DATE',
                                  style: AppTypography.labelCaps.copyWith(
                                    color: AppColors.onSurfaceVariant,
                                  ),
                                ),
                                const SizedBox(height: AppSpacing.xs),
                                InkWell(
                                  onTap: () => _pickDate(isOrderDate: false),
                                  borderRadius:
                                      BorderRadius.circular(AppSpacing.radiusMd),
                                  child: InputDecorator(
                                    decoration: InputDecoration(
                                      prefixIcon: const Icon(Icons.local_shipping_outlined),
                                      suffixIcon: _lastDeliveryDate != null
                                          ? IconButton(
                                              icon: const Icon(Icons.clear, size: 18),
                                              onPressed: () =>
                                                  setState(() => _lastDeliveryDate = null),
                                            )
                                          : null,
                                      border: OutlineInputBorder(
                                        borderRadius:
                                            BorderRadius.circular(AppSpacing.radiusMd),
                                      ),
                                      filled: true,
                                      fillColor: AppColors.surfaceContainerLow,
                                    ),
                                    child: Text(
                                      _formatDate(_lastDeliveryDate),
                                      style: TextStyle(
                                        color: _lastDeliveryDate != null
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
                      const SizedBox(height: AppSpacing.md),

                      // 6. Last Quantity Supplied
                      Text(
                        'LAST QUANTITY SUPPLIED',
                        style: AppTypography.labelCaps.copyWith(
                          color: AppColors.onSurfaceVariant,
                        ),
                      ),
                      const SizedBox(height: AppSpacing.xs),
                      TextFormField(
                        controller: _quantityController,
                        keyboardType:
                            const TextInputType.numberWithOptions(decimal: true),
                        inputFormatters: [
                          FilteringTextInputFormatter.allow(RegExp(r'^\d*\.?\d*')),
                        ],
                        decoration: InputDecoration(
                          hintText: 'E.g. 500',
                          prefixIcon: const Icon(Icons.inventory_2_outlined),
                          border: OutlineInputBorder(
                            borderRadius: BorderRadius.circular(AppSpacing.radiusMd),
                          ),
                          filled: true,
                          fillColor: AppColors.surfaceContainerLow,
                        ),
                        validator: (value) {
                          if (value == null || value.trim().isEmpty) return null;
                          final parsed = double.tryParse(value.trim());
                          if (parsed == null || parsed < 0) {
                            return 'Enter a valid non-negative quantity.';
                          }
                          return null;
                        },
                      ),
                      const SizedBox(height: AppSpacing.md),

                      // 6b. Total Payment Amount
                      Text(
                        'TOTAL PAYMENT AMOUNT (₹)',
                        style: AppTypography.labelCaps.copyWith(
                          color: AppColors.onSurfaceVariant,
                        ),
                      ),
                      const SizedBox(height: AppSpacing.xs),
                      TextFormField(
                        controller: _totalAmountController,
                        keyboardType:
                            const TextInputType.numberWithOptions(decimal: true),
                        inputFormatters: [
                          FilteringTextInputFormatter.allow(RegExp(r'^\d*\.?\d*')),
                        ],
                        decoration: InputDecoration(
                          hintText: 'E.g. 5000',
                          prefixIcon: const Icon(Icons.currency_rupee, color: Colors.green),
                          border: OutlineInputBorder(
                            borderRadius: BorderRadius.circular(AppSpacing.radiusMd),
                          ),
                          filled: true,
                          fillColor: AppColors.surfaceContainerLow,
                        ),
                        validator: (value) {
                          if (value == null || value.trim().isEmpty) return null;
                          final parsed = double.tryParse(value.trim());
                          if (parsed == null || parsed < 0) {
                            return 'Enter a valid non-negative amount.';
                          }
                          return null;
                        },
                      ),
                      const SizedBox(height: AppSpacing.sm),

                      // 6c. Auto-Calculated Price Per Piece Preview Card
                      _buildPricePerPiecePreview(),
                      const SizedBox(height: AppSpacing.md),

                      // 7. Remarks
                      Text(
                        'REMARKS / NOTES (OPTIONAL)',
                        style: AppTypography.labelCaps.copyWith(
                          color: AppColors.onSurfaceVariant,
                        ),
                      ),
                      const SizedBox(height: AppSpacing.xs),
                      TextFormField(
                        controller: _remarksController,
                        maxLines: 2,
                        decoration: InputDecoration(
                          hintText: 'Payment terms, discount agreements, or notes',
                          border: OutlineInputBorder(
                            borderRadius: BorderRadius.circular(AppSpacing.radiusMd),
                          ),
                          filled: true,
                          fillColor: AppColors.surfaceContainerLow,
                        ),
                      ),
                      const SizedBox(height: AppSpacing.md),

                      // 8. Active Status Switch
                      Container(
                        padding: const EdgeInsets.symmetric(
                          horizontal: AppSpacing.md,
                          vertical: AppSpacing.sm,
                        ),
                        decoration: BoxDecoration(
                          color: AppColors.surfaceContainerLow,
                          borderRadius: BorderRadius.circular(AppSpacing.radiusMd),
                          border: Border.all(color: AppColors.outlineVariant),
                        ),
                        child: Row(
                          mainAxisAlignment: MainAxisAlignment.spaceBetween,
                          children: [
                            Expanded(
                              child: Column(
                                crossAxisAlignment: CrossAxisAlignment.start,
                                children: [
                                  Text(
                                    'Vendor Status',
                                    style: AppTypography.bodyMd.copyWith(
                                      fontWeight: FontWeight.w600,
                                    ),
                                  ),
                                  Text(
                                    _isActive
                                        ? 'Vendor is actively supplying products'
                                        : 'Vendor is marked inactive / paused',
                                    style: AppTypography.bodySm.copyWith(
                                      color: AppColors.onSurfaceVariant,
                                      fontSize: 12,
                                    ),
                                  ),
                                ],
                              ),
                            ),
                            const SizedBox(width: AppSpacing.sm),
                            Switch.adaptive(
                              value: _isActive,
                              activeTrackColor: AppColors.primary,
                              onChanged: (val) => setState(() => _isActive = val),
                            ),
                          ],
                        ),
                      ),
                    ],
                  ),
                ),
              ),
            ),
            const Divider(height: 1, color: AppColors.outlineVariant),

            // Footer Actions
            Padding(
              padding: const EdgeInsets.all(AppSpacing.md),
              child: Row(
                mainAxisAlignment: MainAxisAlignment.end,
                children: [
                  TextButton(
                    onPressed: _isSubmitting ? null : () => Navigator.of(context).pop(),
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
                        : Icon(
                            _isEditing ? Icons.check : Icons.add,
                            size: 18,
                          ),
                    label: Text(
                      _isSubmitting
                          ? 'Saving...'
                          : _isEditing
                              ? 'Update Vendor'
                              : 'Create Vendor',
                    ),
                    style: FilledButton.styleFrom(
                      backgroundColor: AppColors.primary,
                      foregroundColor: Colors.white,
                      padding: const EdgeInsets.symmetric(
                        horizontal: AppSpacing.lg,
                        vertical: AppSpacing.sm,
                      ),
                    ),
                  ),
                ],
              ),
            ),
          ],
        ),
      ),
    );
  }

  Widget _buildPricePerPiecePreview() {
    final qty = double.tryParse(_quantityController.text.trim());
    final total = double.tryParse(_totalAmountController.text.trim());
    final pricePerPiece = (qty != null && qty > 0 && total != null && total >= 0)
        ? (total / qty)
        : null;

    final priceStr = pricePerPiece != null
        ? '₹${pricePerPiece.toStringAsFixed(2)} / piece'
        : '—';

    return Container(
      width: double.infinity,
      padding: const EdgeInsets.symmetric(horizontal: AppSpacing.md, vertical: AppSpacing.sm),
      decoration: BoxDecoration(
        color: Colors.green.withValues(alpha: 0.08),
        borderRadius: BorderRadius.circular(AppSpacing.radiusMd),
        border: Border.all(color: Colors.green.withValues(alpha: 0.25)),
      ),
      child: Row(
        mainAxisAlignment: MainAxisAlignment.spaceBetween,
        children: [
          Expanded(
            child: Row(
              children: [
                const Icon(Icons.calculate_outlined, size: 18, color: Colors.green),
                const SizedBox(width: 8),
                Expanded(
                  child: Column(
                    crossAxisAlignment: CrossAxisAlignment.start,
                    children: [
                      Text(
                        'Price Per Piece',
                        style: AppTypography.labelCaps.copyWith(
                          color: Colors.green.shade800,
                          fontWeight: FontWeight.w700,
                          fontSize: 10,
                        ),
                      ),
                      Text(
                        'Auto-calculated: Total Amount / Quantity',
                        overflow: TextOverflow.ellipsis,
                        style: AppTypography.bodySm.copyWith(
                          color: AppColors.onSurfaceVariant,
                          fontSize: 11,
                        ),
                      ),
                    ],
                  ),
                ),
              ],
            ),
          ),
          const SizedBox(width: 8),
          Text(
            priceStr,
            style: AppTypography.headlineMd.copyWith(
              fontSize: 18,
              color: Colors.green.shade800,
              fontWeight: FontWeight.w800,
            ),
          ),
        ],
      ),
    );
  }
}
