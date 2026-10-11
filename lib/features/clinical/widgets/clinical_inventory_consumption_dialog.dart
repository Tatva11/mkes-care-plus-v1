import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';

import '../../../core/theme/app_colors.dart';
import '../../../core/theme/app_spacing.dart';
import '../../../core/theme/app_typography.dart';
import '../../inventory/models/inventory_item.dart';
import '../../inventory/providers/inventory_provider.dart';
import '../models/clinical_inventory_usage_model.dart';
import '../providers/clinical_inventory_provider.dart';

/// Modal dialog for recording consumed clinical inventory for an eye examination,
/// dental treatment, eye surgery, or general patient procedure.
class ClinicalInventoryConsumptionDialog extends ConsumerStatefulWidget {
  const ClinicalInventoryConsumptionDialog({
    super.key,
    required this.patientId,
    required this.patientName,
    this.patientNumber,
    required this.recordType,
    required this.recordId,
    required this.recordTitle,
  });

  final String patientId;
  final String patientName;
  final String? patientNumber;
  final String recordType; // 'eye_examination' | 'dental_treatment' | 'eye_surgery' | 'other'
  final String recordId;
  final String recordTitle;

  @override
  ConsumerState<ClinicalInventoryConsumptionDialog> createState() =>
      _ClinicalInventoryConsumptionDialogState();
}

class _ClinicalInventoryConsumptionDialogState
    extends ConsumerState<ClinicalInventoryConsumptionDialog> {
  final _formKey = GlobalKey<FormState>();

  InventoryItem? _selectedItem;
  final _quantityController = TextEditingController();
  final _remarksController = TextEditingController();

  bool _isSubmitting = false;
  String? _errorMessage;

  static const Color _successColor = Color(0xFF2E7D32);

  @override
  void dispose() {
    _quantityController.dispose();
    _remarksController.dispose();
    super.dispose();
  }

  double get _enteredQuantity =>
      double.tryParse(_quantityController.text.trim()) ?? 0.0;

  Future<void> _submit() async {
    if (_isSubmitting) return;
    if (!_formKey.currentState!.validate()) return;
    if (_selectedItem == null) {
      setState(() => _errorMessage = 'Please select an inventory item.');
      return;
    }

    final qty = _enteredQuantity;
    if (qty <= 0) {
      setState(() => _errorMessage = 'Quantity must be greater than zero.');
      return;
    }

    if (qty > _selectedItem!.currentStock) {
      setState(() => _errorMessage =
          'Insufficient stock. Available: ${_selectedItem!.currentStock} ${_selectedItem!.unit}');
      return;
    }

    setState(() {
      _isSubmitting = true;
      _errorMessage = null;
    });

    try {
      final usage = await ref
          .read(clinicalInventoryControllerProvider.notifier)
          .recordConsumption(
            patientId: widget.patientId,
            recordType: widget.recordType,
            recordId: widget.recordId,
            inventoryId: _selectedItem!.id,
            quantity: qty,
            remarks: _remarksController.text.trim().isEmpty
                ? null
                : _remarksController.text.trim(),
          );

      if (mounted) {
        ScaffoldMessenger.of(context).showSnackBar(
          SnackBar(
            content: Text(
              'Successfully consumed $qty ${_selectedItem!.unit} of ${_selectedItem!.name}.',
            ),
            backgroundColor: _successColor,
          ),
        );
        Navigator.of(context).pop<ClinicalInventoryUsageModel>(usage);
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
    final inventoryAsync = ref.watch(inventoryProvider);

    return Dialog(
      shape: RoundedRectangleBorder(
        borderRadius: BorderRadius.circular(AppSpacing.radiusLg),
      ),
      insetPadding: const EdgeInsets.symmetric(
        horizontal: AppSpacing.md,
        vertical: AppSpacing.lg,
      ),
      child: ConstrainedBox(
        constraints: const BoxConstraints(maxWidth: 540),
        child: SingleChildScrollView(
          padding: const EdgeInsets.all(AppSpacing.lg),
          child: Form(
            key: _formKey,
            child: Column(
              mainAxisSize: MainAxisSize.min,
              crossAxisAlignment: CrossAxisAlignment.stretch,
              children: [
                // Header
                Row(
                  children: [
                    Container(
                      padding: const EdgeInsets.all(AppSpacing.sm),
                      decoration: BoxDecoration(
                        color: AppColors.primaryContainer.withValues(alpha: 0.2),
                        borderRadius: BorderRadius.circular(AppSpacing.radiusMd),
                      ),
                      child: const Icon(
                        Icons.medication_outlined,
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
                            'Record Inventory Usage',
                            style: AppTypography.headlineMd.copyWith(
                              fontWeight: FontWeight.bold,
                              fontSize: 20,
                            ),
                          ),
                          const SizedBox(height: 2),
                          Text(
                            '${widget.patientName}${widget.patientNumber != null ? " (${widget.patientNumber})" : ""}',
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
                const SizedBox(height: AppSpacing.sm),

                // Record reference badge
                Container(
                  padding: const EdgeInsets.symmetric(
                    horizontal: AppSpacing.sm,
                    vertical: AppSpacing.xs,
                  ),
                  decoration: BoxDecoration(
                    color: AppColors.surfaceContainerHigh,
                    borderRadius: BorderRadius.circular(AppSpacing.radiusSm),
                  ),
                  child: Row(
                    children: [
                      const Icon(
                        Icons.link_outlined,
                        size: 16,
                        color: AppColors.primary,
                      ),
                      const SizedBox(width: AppSpacing.xs),
                      Expanded(
                        child: Text(
                          'Linked: ${widget.recordTitle}',
                          style: AppTypography.bodySm.copyWith(
                            color: AppColors.onSurface,
                            fontWeight: FontWeight.w500,
                          ),
                          overflow: TextOverflow.ellipsis,
                        ),
                      ),
                    ],
                  ),
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
                      crossAxisAlignment: CrossAxisAlignment.start,
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

                // Item selector
                Text(
                  'Select Inventory Item *',
                  style: AppTypography.bodyMd.copyWith(
                    fontWeight: FontWeight.w600,
                  ),
                ),
                const SizedBox(height: AppSpacing.xs),
                inventoryAsync.when(
                  loading: () => const LinearProgressIndicator(),
                  error: (err, _) => Text(
                    'Failed to load inventory: $err',
                    style: AppTypography.bodySm.copyWith(color: AppColors.error),
                  ),
                  data: (items) {
                    if (items.isEmpty) {
                      return const Text('No inventory items found.');
                    }
                    return DropdownButtonFormField<InventoryItem>(
                      initialValue: _selectedItem,
                      isExpanded: true,
                      decoration: const InputDecoration(
                        border: OutlineInputBorder(),
                        hintText: 'Choose medicine, consumable or supply...',
                        prefixIcon: Icon(Icons.inventory_2_outlined),
                      ),
                      items: items.map((item) {
                        final isLow = item.currentStock <= 0;
                        return DropdownMenuItem<InventoryItem>(
                          value: item,
                          child: Row(
                            children: [
                              Expanded(
                                child: Text(
                                  '${item.name} (${item.category})',
                                  overflow: TextOverflow.ellipsis,
                                  style: AppTypography.bodyMd,
                                ),
                              ),
                              const SizedBox(width: AppSpacing.xs),
                              Container(
                                padding: const EdgeInsets.symmetric(
                                  horizontal: 6,
                                  vertical: 2,
                                ),
                                decoration: BoxDecoration(
                                  color: isLow
                                      ? AppColors.errorContainer
                                      : AppColors.primaryContainer.withValues(alpha: 0.4),
                                  borderRadius: BorderRadius.circular(4),
                                ),
                                child: Text(
                                  '${item.currentStock.toStringAsFixed(item.currentStock.truncateToDouble() == item.currentStock ? 0 : 1)} ${item.unit}',
                                  style: AppTypography.bodySm.copyWith(
                                    color: isLow
                                        ? AppColors.error
                                        : AppColors.primary,
                                    fontWeight: FontWeight.bold,
                                  ),
                                ),
                              ),
                            ],
                          ),
                        );
                      }).toList(),
                      onChanged: (item) {
                        setState(() {
                          _selectedItem = item;
                          _errorMessage = null;
                        });
                      },
                      validator: (value) =>
                          value == null ? 'Please select an item' : null,
                    );
                  },
                ),
                const SizedBox(height: AppSpacing.md),

                // Selected item stock info card
                if (_selectedItem != null) ...[
                  Container(
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
                          mainAxisAlignment: MainAxisAlignment.spaceBetween,
                          children: [
                            Text(
                              'Available Stock:',
                              style: AppTypography.bodySm.copyWith(
                                color: AppColors.onSurfaceVariant,
                              ),
                            ),
                            Text(
                              '${_selectedItem!.currentStock} ${_selectedItem!.unit}',
                              style: AppTypography.bodyMd.copyWith(
                                fontWeight: FontWeight.bold,
                                color: _selectedItem!.currentStock <= 0
                                    ? AppColors.error
                                    : AppColors.onSurface,
                              ),
                            ),
                          ],
                        ),
                        if (_enteredQuantity > 0) ...[
                          const SizedBox(height: 4),
                          Row(
                            mainAxisAlignment: MainAxisAlignment.spaceBetween,
                            children: [
                              Text(
                                'Remaining after use:',
                                style: AppTypography.bodySm.copyWith(
                                  color: AppColors.onSurfaceVariant,
                                ),
                              ),
                              Text(
                                '${(_selectedItem!.currentStock - _enteredQuantity).toStringAsFixed(1)} ${_selectedItem!.unit}',
                                style: AppTypography.bodyMd.copyWith(
                                  fontWeight: FontWeight.bold,
                                  color: (_selectedItem!.currentStock - _enteredQuantity) < 0
                                      ? AppColors.error
                                      : _successColor,
                                ),
                              ),
                            ],
                          ),
                        ],
                      ],
                    ),
                  ),
                  const SizedBox(height: AppSpacing.md),
                ],

                // Quantity
                Text(
                  'Quantity to Consume *',
                  style: AppTypography.bodyMd.copyWith(
                    fontWeight: FontWeight.w600,
                  ),
                ),
                const SizedBox(height: AppSpacing.xs),
                TextFormField(
                  controller: _quantityController,
                  keyboardType:
                      const TextInputType.numberWithOptions(decimal: true),
                  decoration: InputDecoration(
                    border: const OutlineInputBorder(),
                    hintText: 'e.g. 1',
                    prefixIcon: const Icon(Icons.numbers_outlined),
                    suffixText: _selectedItem?.unit ?? 'units',
                  ),
                  onChanged: (_) => setState(() {}),
                  validator: (value) {
                    if (value == null || value.trim().isEmpty) {
                      return 'Enter quantity';
                    }
                    final parsed = double.tryParse(value.trim());
                    if (parsed == null || parsed <= 0) {
                      return 'Enter a valid positive number';
                    }
                    if (_selectedItem != null && parsed > _selectedItem!.currentStock) {
                      return 'Cannot exceed available stock (${_selectedItem!.currentStock})';
                    }
                    return null;
                  },
                ),
                const SizedBox(height: AppSpacing.md),

                // Remarks
                Text(
                  'Clinical Usage Remarks (Optional)',
                  style: AppTypography.bodyMd.copyWith(
                    fontWeight: FontWeight.w600,
                  ),
                ),
                const SizedBox(height: AppSpacing.xs),
                TextFormField(
                  controller: _remarksController,
                  maxLines: 2,
                  decoration: const InputDecoration(
                    border: OutlineInputBorder(),
                    hintText: 'e.g. Applied local anaesthetic cartridge, sterile swab...',
                  ),
                ),
                const SizedBox(height: AppSpacing.lg),

                // Action buttons
                Row(
                  mainAxisAlignment: MainAxisAlignment.end,
                  children: [
                    TextButton(
                      onPressed:
                          _isSubmitting ? null : () => Navigator.of(context).pop(),
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
                          : const Icon(Icons.check_circle_outline),
                      label: Text(
                        _isSubmitting ? 'Deducting Stock...' : 'Confirm Usage',
                      ),
                    ),
                  ],
                ),
              ],
            ),
          ),
        ),
      ),
    );
  }
}
