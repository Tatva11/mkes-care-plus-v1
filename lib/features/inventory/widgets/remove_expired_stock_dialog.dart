import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';

import '../../../core/theme/app_colors.dart';
import '../../../core/theme/app_spacing.dart';
import '../../../core/theme/app_typography.dart';
import '../models/expired_stock_entry.dart';
import '../providers/inventory_provider.dart';

/// Interactive modal allowing authorized personnel to inspect, select, and remove expired inventory stock.
/// Atomically writes off expired quantities with transaction reason 'Expired'.
class RemoveExpiredStockDialog extends ConsumerStatefulWidget {
  const RemoveExpiredStockDialog({super.key});

  static Future<bool?> show(BuildContext context) {
    return showDialog<bool>(
      context: context,
      barrierDismissible: false,
      builder: (_) => const RemoveExpiredStockDialog(),
    );
  }

  @override
  ConsumerState<RemoveExpiredStockDialog> createState() =>
      _RemoveExpiredStockDialogState();
}

class _RemoveExpiredStockDialogState
    extends ConsumerState<RemoveExpiredStockDialog> {
  final Map<int, bool> _selectedIndices = {};
  final Map<int, TextEditingController> _quantityControllers = {};
  bool _isSubmitting = false;
  bool _confirming = false;
  String? _errorMessage;

  @override
  void dispose() {
    for (final controller in _quantityControllers.values) {
      controller.dispose();
    }
    super.dispose();
  }

  void _initSelection(List<ExpiredStockEntry> entries) {
    if (_selectedIndices.isNotEmpty) return;
    for (var i = 0; i < entries.length; i++) {
      _selectedIndices[i] = true;
      _quantityControllers[i] = TextEditingController(
        text: entries[i].expiredQuantity % 1 == 0
            ? entries[i].expiredQuantity.toInt().toString()
            : entries[i].expiredQuantity.toString(),
      );
    }
  }

  double? _parseQuantity(int index, ExpiredStockEntry entry) {
    final text = _quantityControllers[index]?.text.trim() ?? '';
    final qty = double.tryParse(text);
    if (qty == null || qty <= 0) return null;
    if (qty > entry.expiredQuantity || qty > entry.totalAvailableStock) {
      return null;
    }
    return qty;
  }

  bool _validateSelections(List<ExpiredStockEntry> entries) {
    var hasValidSelection = false;
    for (var i = 0; i < entries.length; i++) {
      if (_selectedIndices[i] == true) {
        final qty = _parseQuantity(i, entries[i]);
        if (qty == null) {
          setState(() {
            _errorMessage =
                'Please enter a valid removal quantity for "${entries[i].itemName}" (up to ${entries[i].formattedExpiredQuantity} ${entries[i].unit}).';
          });
          return false;
        }
        hasValidSelection = true;
      }
    }
    if (!hasValidSelection) {
      setState(() {
        _errorMessage = 'Please select at least one expired item to remove.';
      });
      return false;
    }
    setState(() => _errorMessage = null);
    return true;
  }

  Future<void> _submitRemoval(List<ExpiredStockEntry> entries) async {
    if (_isSubmitting) return;

    if (!_validateSelections(entries)) return;

    setState(() {
      _isSubmitting = true;
      _errorMessage = null;
    });

    try {
      var removedCount = 0;
      double totalUnits = 0;

      for (var i = 0; i < entries.length; i++) {
        if (_selectedIndices[i] == true) {
          final entry = entries[i];
          final qty = _parseQuantity(i, entry)!;

          await ref.read(inventoryProvider.notifier).removeExpiredStock(
                inventoryId: entry.inventoryId,
                quantity: qty,
                batchNumber: entry.batchNumber,
                remarks: entry.batchNumber != null
                    ? 'Removed expired stock from Batch ${entry.batchNumber}'
                    : 'Removed expired stock adjustment',
              );
          removedCount++;
          totalUnits += qty;
        }
      }

      if (mounted) {
        Navigator.of(context).pop(true);
        ScaffoldMessenger.of(context).showSnackBar(
          SnackBar(
            backgroundColor: AppColors.primaryContainer,
            content: Row(
              children: [
                const Icon(Icons.check_circle, color: Colors.white),
                const SizedBox(width: AppSpacing.sm),
                Expanded(
                  child: Text(
                    'Successfully removed $removedCount expired item(s) ($totalUnits units) from available inventory.',
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
        setState(() {
          _isSubmitting = false;
          _confirming = false;
          _errorMessage = 'Failed to remove expired stock: $e';
        });
      }
    }
  }

  @override
  Widget build(BuildContext context) {
    final expiredAsync = ref.watch(expiredStockEntriesProvider);
    final size = MediaQuery.sizeOf(context);
    final insets = MediaQuery.viewInsetsOf(context);

    final maxWidth = (size.width - 32).clamp(320.0, 680.0);
    final maxHeight = (size.height - insets.bottom - 48).clamp(320.0, 780.0);

    return Dialog(
      shape: RoundedRectangleBorder(
        borderRadius: BorderRadius.circular(AppSpacing.radiusLg),
      ),
      insetPadding: const EdgeInsets.symmetric(horizontal: 16, vertical: 24),
      child: ConstrainedBox(
        constraints: BoxConstraints(
          maxWidth: maxWidth,
          maxHeight: maxHeight,
        ),
        child: expiredAsync.when(
          loading: () => const SizedBox(
            height: 240,
            child: Center(child: CircularProgressIndicator()),
          ),
          error: (err, _) => Padding(
            padding: const EdgeInsets.all(AppSpacing.lg),
            child: Column(
              mainAxisSize: MainAxisSize.min,
              children: [
                const Icon(Icons.error_outline, color: AppColors.error, size: 44),
                const SizedBox(height: AppSpacing.sm),
                Text(
                  'Unable to load expired stock',
                  style: AppTypography.headlineMd,
                ),
                const SizedBox(height: AppSpacing.xs),
                Text(
                  '$err',
                  textAlign: TextAlign.center,
                  style: AppTypography.bodySm.copyWith(color: AppColors.onSurfaceVariant),
                ),
                const SizedBox(height: AppSpacing.md),
                Row(
                  mainAxisAlignment: MainAxisAlignment.end,
                  children: [
                    TextButton(
                      onPressed: () => Navigator.of(context).pop(),
                      child: const Text('Close'),
                    ),
                    const SizedBox(width: AppSpacing.sm),
                    FilledButton(
                      onPressed: () => ref.invalidate(expiredStockEntriesProvider),
                      child: const Text('Retry'),
                    ),
                  ],
                ),
              ],
            ),
          ),
          data: (entries) {
            _initSelection(entries);

            if (entries.isEmpty) {
              return _buildEmptyState(context);
            }

            return _buildActiveDialog(context, entries);
          },
        ),
      ),
    );
  }

  Widget _buildEmptyState(BuildContext context) {
    return Padding(
      padding: const EdgeInsets.all(AppSpacing.xl),
      child: Column(
        mainAxisSize: MainAxisSize.min,
        children: [
          Container(
            padding: const EdgeInsets.all(16),
            decoration: BoxDecoration(
              color: Colors.green.withValues(alpha: 0.12),
              shape: BoxShape.circle,
            ),
            child: const Icon(
              Icons.verified_outlined,
              size: 48,
              color: Colors.green,
            ),
          ),
          const SizedBox(height: AppSpacing.md),
          Text(
            'No Expired Stock Found',
            style: AppTypography.headlineMd,
            textAlign: TextAlign.center,
          ),
          const SizedBox(height: AppSpacing.xs),
          Text(
            'All inventory batches and tracked products are currently within their valid shelf life.',
            style: AppTypography.bodyMd.copyWith(color: AppColors.onSurfaceVariant),
            textAlign: TextAlign.center,
          ),
          const SizedBox(height: AppSpacing.lg),
          FilledButton(
            onPressed: () => Navigator.of(context).pop(),
            child: const Text('Close'),
          ),
        ],
      ),
    );
  }

  Widget _buildActiveDialog(
    BuildContext context,
    List<ExpiredStockEntry> entries,
  ) {
    final selectedCount = _selectedIndices.values.where((v) => v).length;

    return Column(
      mainAxisSize: MainAxisSize.min,
      crossAxisAlignment: CrossAxisAlignment.stretch,
      children: [
        // Header
        Padding(
          padding: const EdgeInsets.fromLTRB(
            AppSpacing.lg,
            AppSpacing.md,
            AppSpacing.md,
            AppSpacing.sm,
          ),
          child: Row(
            children: [
              Container(
                padding: const EdgeInsets.all(8),
                decoration: BoxDecoration(
                  color: AppColors.errorContainer.withValues(alpha: 0.4),
                  borderRadius: BorderRadius.circular(AppSpacing.radiusSm),
                ),
                child: const Icon(
                  Icons.remove_circle_outline,
                  color: AppColors.error,
                  size: 24,
                ),
              ),
              const SizedBox(width: AppSpacing.sm),
              Expanded(
                child: Column(
                  crossAxisAlignment: CrossAxisAlignment.start,
                  children: [
                    Text(
                      'Remove Expired Stock',
                      style: AppTypography.headlineMd.copyWith(fontSize: 18),
                    ),
                    Text(
                      'Explicitly write off expired lots and update inventory ledger',
                      style: AppTypography.bodySm.copyWith(color: AppColors.onSurfaceVariant),
                    ),
                  ],
                ),
              ),
              IconButton(
                icon: const Icon(Icons.close),
                tooltip: 'Cancel',
                onPressed: _isSubmitting ? null : () => Navigator.of(context).pop(),
              ),
            ],
          ),
        ),
        const Divider(height: 1),

        // Error message banner
        if (_errorMessage != null)
          Container(
            color: AppColors.errorContainer,
            padding: const EdgeInsets.symmetric(
              horizontal: AppSpacing.md,
              vertical: AppSpacing.xs,
            ),
            child: Row(
              children: [
                const Icon(Icons.error_outline, size: 18, color: AppColors.error),
                const SizedBox(width: AppSpacing.xs),
                Expanded(
                  child: Text(
                    _errorMessage!,
                    style: AppTypography.bodySm.copyWith(color: AppColors.error),
                  ),
                ),
              ],
            ),
          ),

        // Scrollable Body
        Expanded(
          child: SingleChildScrollView(
            padding: const EdgeInsets.all(AppSpacing.md),
            child: _confirming
                ? _buildConfirmationView(entries)
                : _buildSelectionView(entries),
          ),
        ),

        const Divider(height: 1),

        // Footer Actions
        Padding(
          padding: const EdgeInsets.all(AppSpacing.md),
          child: Row(
            mainAxisAlignment: MainAxisAlignment.spaceBetween,
            children: [
              Text(
                '$selectedCount of ${entries.length} lot(s) selected',
                style: AppTypography.bodySm.copyWith(
                  color: AppColors.onSurfaceVariant,
                  fontWeight: FontWeight.w500,
                ),
              ),
              Row(
                children: [
                  TextButton(
                    onPressed: _isSubmitting
                        ? null
                        : () {
                            if (_confirming) {
                              setState(() => _confirming = false);
                            } else {
                              Navigator.of(context).pop();
                            }
                          },
                    child: Text(_confirming ? 'Back' : 'Cancel'),
                  ),
                  const SizedBox(width: AppSpacing.sm),
                  FilledButton.icon(
                    style: FilledButton.styleFrom(
                      backgroundColor: AppColors.error,
                      foregroundColor: Colors.white,
                    ),
                    onPressed: _isSubmitting || selectedCount == 0
                        ? null
                        : () {
                            if (!_confirming) {
                              if (_validateSelections(entries)) {
                                setState(() => _confirming = true);
                              }
                            } else {
                              _submitRemoval(entries);
                            }
                          },
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
                            _confirming
                                ? Icons.delete_forever
                                : Icons.arrow_forward,
                            size: 18,
                          ),
                    label: Text(
                      _confirming
                          ? 'Confirm & Remove'
                          : 'Review Removal ($selectedCount)',
                    ),
                  ),
                ],
              ),
            ],
          ),
        ),
      ],
    );
  }

  Widget _buildSelectionView(List<ExpiredStockEntry> entries) {
    return Column(
      crossAxisAlignment: CrossAxisAlignment.stretch,
      children: [
        Row(
          mainAxisAlignment: MainAxisAlignment.spaceBetween,
          children: [
            Text(
              'EXPIRED ITEMS & BATCHES',
              style: AppTypography.labelCaps.copyWith(color: AppColors.onSurfaceVariant),
            ),
            TextButton(
              onPressed: () {
                final allSelected = _selectedIndices.values.every((v) => v);
                setState(() {
                  for (var i = 0; i < entries.length; i++) {
                    _selectedIndices[i] = !allSelected;
                  }
                });
              },
              child: Text(
                _selectedIndices.values.every((v) => v)
                    ? 'Deselect All'
                    : 'Select All',
                style: const TextStyle(fontSize: 13),
              ),
            ),
          ],
        ),
        const SizedBox(height: AppSpacing.xs),
        for (var i = 0; i < entries.length; i++) ...[
          _buildItemCard(i, entries[i]),
          const SizedBox(height: 8),
        ],
      ],
    );
  }

  Widget _buildItemCard(int index, ExpiredStockEntry entry) {
    final isSelected = _selectedIndices[index] == true;
    final controller = _quantityControllers[index];
    final nonExpiredQty = (entry.totalAvailableStock - entry.expiredQuantity).clamp(0.0, double.infinity);
    final removeQty = double.tryParse(controller?.text.trim() ?? '') ?? 0.0;
    final remainingAfterRemoval = (entry.totalAvailableStock - removeQty).clamp(0.0, double.infinity);

    return Container(
      decoration: BoxDecoration(
        color: isSelected
            ? AppColors.errorContainer.withValues(alpha: 0.15)
            : AppColors.surfaceContainerLowest,
        borderRadius: BorderRadius.circular(AppSpacing.radiusMd),
        border: Border.all(
          color: isSelected ? AppColors.error : AppColors.outlineVariant,
          width: isSelected ? 1.5 : 1,
        ),
      ),
      padding: const EdgeInsets.all(AppSpacing.sm),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Row(
            crossAxisAlignment: CrossAxisAlignment.start,
            children: [
              Checkbox(
                value: isSelected,
                activeColor: AppColors.error,
                onChanged: _isSubmitting
                    ? null
                    : (val) {
                        setState(() => _selectedIndices[index] = val ?? false);
                      },
              ),
              Expanded(
                child: Column(
                  crossAxisAlignment: CrossAxisAlignment.start,
                  children: [
                    Text(
                      entry.itemName,
                      style: AppTypography.bodyMd.copyWith(fontWeight: FontWeight.bold),
                    ),
                    const SizedBox(height: 2),
                    Row(
                      children: [
                        if (entry.batchNumber != null) ...[
                          Container(
                            padding: const EdgeInsets.symmetric(horizontal: 6, vertical: 2),
                            decoration: BoxDecoration(
                              color: AppColors.surfaceContainerHigh,
                              borderRadius: BorderRadius.circular(4),
                            ),
                            child: Text(
                              'Batch: ${entry.batchNumber}',
                              style: AppTypography.bodySm.copyWith(
                                fontWeight: FontWeight.w600,
                                fontSize: 12,
                              ),
                            ),
                          ),
                          const SizedBox(width: AppSpacing.xs),
                        ],
                        Text(
                          'Expiry: ${entry.formattedExpiryDate} (${entry.expiryStatusDescription})',
                          style: AppTypography.bodySm.copyWith(
                            color: AppColors.error,
                            fontWeight: FontWeight.w500,
                          ),
                        ),
                      ],
                    ),
                    const SizedBox(height: 2),
                    Text(
                      'Total Stock: ${entry.formattedTotalStock} ${entry.unit}  •  Expired: ${entry.formattedExpiredQuantity} ${entry.unit}  •  Non-Expired: ${nonExpiredQty % 1 == 0 ? nonExpiredQty.toInt() : nonExpiredQty.toStringAsFixed(1)} ${entry.unit}',
                      style: AppTypography.bodySm.copyWith(color: AppColors.onSurfaceVariant),
                    ),
                  ],
                ),
              ),
            ],
          ),
          if (isSelected) ...[
            const Divider(height: 12),
            Padding(
              padding: const EdgeInsets.only(left: 44, right: 8, bottom: 4),
              child: Column(
                crossAxisAlignment: CrossAxisAlignment.start,
                children: [
                  Row(
                    children: [
                      Text(
                        'Remove Qty (${entry.unit}):',
                        style: AppTypography.bodySm.copyWith(fontWeight: FontWeight.w600),
                      ),
                      const SizedBox(width: AppSpacing.sm),
                      SizedBox(
                        width: 100,
                        child: TextField(
                          controller: controller,
                          enabled: !_isSubmitting,
                          keyboardType: const TextInputType.numberWithOptions(decimal: true),
                          decoration: const InputDecoration(
                            isDense: true,
                            contentPadding: EdgeInsets.symmetric(horizontal: 8, vertical: 8),
                            border: OutlineInputBorder(),
                          ),
                          onChanged: (_) => setState(() {}),
                        ),
                      ),
                      const SizedBox(width: AppSpacing.xs),
                      TextButton(
                        onPressed: _isSubmitting
                            ? null
                            : () {
                                controller?.text = entry.expiredQuantity % 1 == 0
                                    ? entry.expiredQuantity.toInt().toString()
                                    : entry.expiredQuantity.toString();
                                setState(() {});
                              },
                        child: const Text('Max', style: TextStyle(fontSize: 12)),
                      ),
                    ],
                  ),
                  const SizedBox(height: 4),
                  Text(
                    'Remaining stock after removal: ${remainingAfterRemoval % 1 == 0 ? remainingAfterRemoval.toInt() : remainingAfterRemoval.toStringAsFixed(1)} ${entry.unit} (Preserving non-expired balance)',
                    style: AppTypography.bodySm.copyWith(
                      color: AppColors.primary,
                      fontWeight: FontWeight.w500,
                      fontSize: 12,
                    ),
                  ),
                ],
              ),
            ),
          ],
        ],
      ),
    );
  }

  Widget _buildConfirmationView(List<ExpiredStockEntry> entries) {
    double totalDeduction = 0;
    final List<({ExpiredStockEntry entry, double qty})> confirmedItems = [];

    for (var i = 0; i < entries.length; i++) {
      if (_selectedIndices[i] == true) {
        final qty = _parseQuantity(i, entries[i]);
        if (qty != null) {
          totalDeduction += qty;
          confirmedItems.add((entry: entries[i], qty: qty));
        }
      }
    }

    return Column(
      crossAxisAlignment: CrossAxisAlignment.stretch,
      children: [
        Container(
          padding: const EdgeInsets.all(AppSpacing.md),
          decoration: BoxDecoration(
            color: AppColors.errorContainer.withValues(alpha: 0.3),
            borderRadius: BorderRadius.circular(AppSpacing.radiusMd),
            border: Border.all(color: AppColors.error),
          ),
          child: Column(
            crossAxisAlignment: CrossAxisAlignment.start,
            children: [
              Row(
                children: [
                  const Icon(Icons.warning_amber_rounded, color: AppColors.error),
                  const SizedBox(width: AppSpacing.xs),
                  Text(
                    'Confirm Permanent Stock Deduction',
                    style: AppTypography.headlineMd.copyWith(
                      color: AppColors.error,
                      fontSize: 16,
                    ),
                  ),
                ],
              ),
              const SizedBox(height: AppSpacing.xs),
              Text(
                'You are about to write off $totalDeduction total unit(s) across ${confirmedItems.length} lot(s). '
                'This will deduct the quantities from inventory stock and record permanent audit logs with reason "Expired". '
                'Unexpired quantities and active inventory items will remain safe.',
                style: AppTypography.bodySm,
              ),
            ],
          ),
        ),
        const SizedBox(height: AppSpacing.md),
        Text('SUMMARY OF REMOVALS', style: AppTypography.labelCaps),
        const SizedBox(height: AppSpacing.xs),
        for (final item in confirmedItems) ...[
          Builder(
            builder: (context) {
              final remaining = (item.entry.totalAvailableStock - item.qty).clamp(0.0, double.infinity);
              return Container(
                margin: const EdgeInsets.only(bottom: 6),
                padding: const EdgeInsets.symmetric(horizontal: 12, vertical: 8),
                decoration: BoxDecoration(
                  color: AppColors.surfaceContainerLowest,
                  borderRadius: BorderRadius.circular(AppSpacing.radiusSm),
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
                            item.entry.itemName,
                            style: AppTypography.bodyMd.copyWith(fontWeight: FontWeight.w600),
                          ),
                          Text(
                            '${item.entry.batchNumber != null ? "Batch ${item.entry.batchNumber}  •  " : ""}'
                            'Starting: ${item.entry.formattedTotalStock} ${item.entry.unit}  •  '
                            'Expired: ${item.entry.formattedExpiredQuantity}  •  '
                            'Remaining: ${remaining % 1 == 0 ? remaining.toInt() : remaining.toStringAsFixed(1)} ${item.entry.unit}',
                            style: AppTypography.bodySm.copyWith(color: AppColors.onSurfaceVariant),
                          ),
                        ],
                      ),
                    ),
                    Text(
                      '-${item.qty % 1 == 0 ? item.qty.toInt() : item.qty} ${item.entry.unit}',
                      style: AppTypography.bodyMd.copyWith(
                        color: AppColors.error,
                        fontWeight: FontWeight.bold,
                      ),
                    ),
                  ],
                ),
              );
            },
          ),
        ],
      ],
    );
  }
}
