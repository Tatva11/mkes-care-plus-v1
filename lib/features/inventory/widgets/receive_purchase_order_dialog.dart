import 'package:flutter/material.dart';
import 'package:flutter/services.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';

import '../../../core/theme/app_colors.dart';
import '../../../core/theme/app_spacing.dart';
import '../../../core/theme/app_typography.dart';
import '../models/purchase_order.dart';
import '../providers/purchase_order_provider.dart';

/// Line item state for the Receive Purchase Order dialog.
class _ReceiveLineState {
  _ReceiveLineState({
    required this.item,
  }) {
    // Default to receiving all remaining items for quick full receiving
    controller = TextEditingController(
      text: item.remainingQuantity % 1 == 0
          ? item.remainingQuantity.toInt().toString()
          : item.remainingQuantity.toString(),
    );
  }

  final PurchaseOrderItem item;
  late TextEditingController controller;

  double get receiveQuantity => double.tryParse(controller.text.trim()) ?? 0.0;
  double get batchAmount => receiveQuantity * item.unitPrice;

  void dispose() {
    controller.dispose();
  }
}

/// Dialog allowing Admin and Staff to receive full or partial quantities of a [PurchaseOrder].
class ReceivePurchaseOrderDialog extends ConsumerStatefulWidget {
  const ReceivePurchaseOrderDialog({
    super.key,
    required this.order,
  });

  final PurchaseOrder order;

  @override
  ConsumerState<ReceivePurchaseOrderDialog> createState() =>
      _ReceivePurchaseOrderDialogState();
}

class _ReceivePurchaseOrderDialogState
    extends ConsumerState<ReceivePurchaseOrderDialog> {
  final _formKey = GlobalKey<FormState>();
  late List<_ReceiveLineState> _lines;

  bool _isLoading = false;
  String? _errorMessage;

  @override
  void initState() {
    super.initState();
    _lines = widget.order.items
        .where((i) => i.remainingQuantity > 0)
        .map((i) => _ReceiveLineState(item: i))
        .toList();
  }

  @override
  void dispose() {
    for (final line in _lines) {
      line.dispose();
    }
    super.dispose();
  }

  void _receiveAllRemaining() {
    setState(() {
      for (final line in _lines) {
        line.controller.text = line.item.remainingQuantity % 1 == 0
            ? line.item.remainingQuantity.toInt().toString()
            : line.item.remainingQuantity.toString();
      }
    });
  }

  void _clearAllQuantities() {
    setState(() {
      for (final line in _lines) {
        line.controller.text = '0';
      }
    });
  }

  double get _totalBatchQuantity =>
      _lines.fold(0.0, (sum, l) => sum + l.receiveQuantity);

  double get _totalBatchAmount =>
      _lines.fold(0.0, (sum, l) => sum + l.batchAmount);

  Future<void> _submitReceiving() async {
    setState(() => _errorMessage = null);

    if (!_formKey.currentState!.validate()) return;

    if (_totalBatchQuantity <= 0) {
      setState(() => _errorMessage = 'Please enter at least one item quantity to receive.');
      return;
    }

    for (final line in _lines) {
      final qty = line.receiveQuantity;
      if (qty < 0) {
        setState(() => _errorMessage = 'Receive quantity cannot be negative.');
        return;
      }
      if (qty > line.item.remainingQuantity) {
        setState(() => _errorMessage =
            'Cannot receive more than remaining quantity (${line.item.formattedRemainingQuantity}) for "${line.item.inventoryName}".');
        return;
      }
    }

    setState(() => _isLoading = true);

    try {
      final itemsToReceive = _lines
          .where((l) => l.receiveQuantity > 0)
          .map((l) => {
                'item_id': l.item.id,
                'receive_quantity': l.receiveQuantity,
              })
          .toList();

      final result = await ref
          .read(purchaseOrdersProvider.notifier)
          .receiveOrder(
            purchaseOrderId: widget.order.id,
            items: itemsToReceive,
          );

      if (mounted) {
        Navigator.of(context).pop(true);

        final newStatus = result['status'] as String? ?? 'received';
        final isFullyReceived = newStatus == 'received';

        ScaffoldMessenger.of(context).showSnackBar(
          SnackBar(
            backgroundColor: Colors.green.shade700,
            content: Row(
              children: [
                const Icon(Icons.check_circle, color: Colors.white),
                const SizedBox(width: AppSpacing.xs),
                Expanded(
                  child: Text(
                    isFullyReceived
                        ? 'PO #${widget.order.purchaseOrderNumber} received in full! Inventory stock updated.'
                        : 'Partial shipment received for PO #${widget.order.purchaseOrderNumber}. Inventory stock updated.',
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
          _isLoading = false;
          _errorMessage = e.toString().replaceFirst('Exception: ', '');
        });
      }
    }
  }

  @override
  Widget build(BuildContext context) {
    final isDesktop = MediaQuery.sizeOf(context).width > 700;

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
          maxWidth: isDesktop ? 720 : 500,
          maxHeight: MediaQuery.sizeOf(context).height * 0.9,
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

                      // PO Info Header Card
                      Container(
                        padding: const EdgeInsets.all(AppSpacing.md),
                        decoration: BoxDecoration(
                          color: AppColors.surfaceContainerLow,
                          borderRadius: BorderRadius.circular(AppSpacing.radiusLg),
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
                                    'PO NUMBER',
                                    style: AppTypography.labelCaps.copyWith(
                                      color: AppColors.onSurfaceVariant,
                                    ),
                                  ),
                                  const SizedBox(height: 2),
                                  Text(
                                    widget.order.purchaseOrderNumber,
                                    style: AppTypography.headlineMd.copyWith(
                                      fontWeight: FontWeight.w700,
                                    ),
                                    maxLines: 1,
                                    overflow: TextOverflow.ellipsis,
                                  ),
                                ],
                              ),
                            ),
                            const SizedBox(width: AppSpacing.sm),
                            Expanded(
                              child: Column(
                                crossAxisAlignment: CrossAxisAlignment.end,
                                children: [
                                  Text(
                                    'SUPPLIER / VENDOR',
                                    style: AppTypography.labelCaps.copyWith(
                                      color: AppColors.onSurfaceVariant,
                                    ),
                                  ),
                                  const SizedBox(height: 2),
                                  Text(
                                    widget.order.vendorName ?? 'Vendor',
                                    style: AppTypography.headlineMd.copyWith(
                                      fontWeight: FontWeight.w600,
                                      color: AppColors.primary,
                                    ),
                                    maxLines: 1,
                                    overflow: TextOverflow.ellipsis,
                                    textAlign: TextAlign.end,
                                  ),
                                ],
                              ),
                            ),
                          ],
                        ),
                      ),
                      const SizedBox(height: AppSpacing.md),

                      // Section Title & Convenience buttons
                      Wrap(
                        alignment: WrapAlignment.spaceBetween,
                        crossAxisAlignment: WrapCrossAlignment.center,
                        spacing: AppSpacing.sm,
                        runSpacing: 4,
                        children: [
                          Text(
                            'ENTER QUANTITIES TO RECEIVE',
                            style: AppTypography.labelCaps.copyWith(
                              color: AppColors.primary,
                              fontWeight: FontWeight.w700,
                            ),
                          ),
                          Row(
                            mainAxisSize: MainAxisSize.min,
                            children: [
                              TextButton(
                                onPressed: _receiveAllRemaining,
                                child: const Text('Receive All'),
                              ),
                              TextButton(
                                onPressed: _clearAllQuantities,
                                child: const Text('Clear All'),
                              ),
                            ],
                          ),
                        ],
                      ),
                      const SizedBox(height: AppSpacing.xs),

                      // Line items list
                      if (_lines.isEmpty)
                        const Padding(
                          padding: EdgeInsets.all(AppSpacing.lg),
                          child: Center(
                            child: Text('All items have already been fully received.'),
                          ),
                        )
                      else
                        ListView.separated(
                          shrinkWrap: true,
                          physics: const NeverScrollableScrollPhysics(),
                          itemCount: _lines.length,
                          separatorBuilder: (_, __) =>
                              const SizedBox(height: AppSpacing.sm),
                          itemBuilder: (context, index) {
                            return _buildReceiveLineCard(_lines[index]);
                          },
                        ),
                      const SizedBox(height: AppSpacing.lg),

                      // Batch summary card
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
                            Expanded(
                              child: Column(
                                crossAxisAlignment: CrossAxisAlignment.start,
                                children: [
                                  Text(
                                    'BATCH RECEIVE QUANTITY:',
                                    style: AppTypography.labelCaps.copyWith(
                                      color: AppColors.primary,
                                    ),
                                  ),
                                  const SizedBox(height: 2),
                                  Text(
                                    '${_totalBatchQuantity % 1 == 0 ? _totalBatchQuantity.toInt() : _totalBatchQuantity} units',
                                    style: AppTypography.headlineMd.copyWith(
                                      fontWeight: FontWeight.w700,
                                      color: AppColors.primary,
                                    ),
                                    maxLines: 1,
                                    overflow: TextOverflow.ellipsis,
                                  ),
                                ],
                              ),
                            ),
                            const SizedBox(width: AppSpacing.sm),
                            Expanded(
                              child: Column(
                                crossAxisAlignment: CrossAxisAlignment.end,
                                children: [
                                  Text(
                                    'BATCH VALUE:',
                                    style: AppTypography.labelCaps.copyWith(
                                      color: AppColors.primary,
                                    ),
                                  ),
                                  const SizedBox(height: 2),
                                  Text(
                                    '₹${_totalBatchAmount.toStringAsFixed(2)}',
                                    style: AppTypography.displayLg.copyWith(
                                      fontWeight: FontWeight.w800,
                                      color: AppColors.primary,
                                      fontSize: 18,
                                    ),
                                    maxLines: 1,
                                    overflow: TextOverflow.ellipsis,
                                    textAlign: TextAlign.end,
                                  ),
                                ],
                              ),
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
            _buildDialogActions(),
          ],
        ),
      ),
    );
  }

  Widget _buildReceiveLineCard(_ReceiveLineState line) {
    final item = line.item;

    return Container(
      padding: const EdgeInsets.all(AppSpacing.sm),
      decoration: BoxDecoration(
        color: AppColors.surfaceContainerLow,
        borderRadius: BorderRadius.circular(AppSpacing.radiusMd),
        border: Border.all(color: AppColors.outlineVariant),
      ),
      child: Row(
        crossAxisAlignment: CrossAxisAlignment.center,
        children: [
          // Product name and quantities overview
          Expanded(
            child: Column(
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                Text(
                  item.inventoryName,
                  style: AppTypography.bodyMd.copyWith(
                    fontWeight: FontWeight.w700,
                  ),
                ),
                const SizedBox(height: 4),
                Wrap(
                  spacing: AppSpacing.sm,
                  runSpacing: 2,
                  children: [
                    Text(
                      'Ordered: ${item.formattedQuantity}',
                      style: AppTypography.bodySm.copyWith(
                        color: AppColors.onSurfaceVariant,
                      ),
                    ),
                    Text(
                      'Received: ${item.formattedReceivedQuantity}',
                      style: AppTypography.bodySm.copyWith(
                        color: Colors.green.shade700,
                      ),
                    ),
                    Text(
                      'Remaining: ${item.formattedRemainingQuantity}',
                      style: AppTypography.bodySm.copyWith(
                        fontWeight: FontWeight.w600,
                        color: const Color(0xFFE65100),
                      ),
                    ),
                  ],
                ),
              ],
            ),
          ),
          const SizedBox(width: AppSpacing.md),

          // Input for receive quantity
          SizedBox(
            width: 130,
            child: TextFormField(
              controller: line.controller,
              keyboardType: const TextInputType.numberWithOptions(decimal: true),
              inputFormatters: [
                FilteringTextInputFormatter.allow(RegExp(r'^\d+\.?\d{0,2}')),
              ],
              decoration: InputDecoration(
                labelText: 'Receive (${item.inventoryUnit})',
                contentPadding: const EdgeInsets.symmetric(horizontal: 10, vertical: 8),
              ),
              onChanged: (_) => setState(() {}),
            ),
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
                  color: Colors.green.withValues(alpha: 0.15),
                  borderRadius: BorderRadius.circular(AppSpacing.radiusMd),
                ),
                child: const Icon(
                  Icons.inventory,
                  color: Colors.green,
                  size: 20,
                ),
              ),
              const SizedBox(width: AppSpacing.sm),
              Text(
                'Receive Purchase Order',
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
          FilledButton.icon(
            onPressed: _isLoading ? null : _submitReceiving,
            icon: _isLoading
                ? const SizedBox(
                    width: 18,
                    height: 18,
                    child: CircularProgressIndicator(strokeWidth: 2, color: Colors.white),
                  )
                : const Icon(Icons.check_circle_outline, size: 18),
            label: const Text('Confirm Receiving'),
            style: FilledButton.styleFrom(
              backgroundColor: Colors.green.shade700,
              foregroundColor: Colors.white,
            ),
          ),
        ],
      ),
    );
  }
}
