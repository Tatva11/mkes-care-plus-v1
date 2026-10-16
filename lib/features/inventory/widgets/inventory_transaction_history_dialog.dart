import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:intl/intl.dart';

import '../../../core/theme/app_colors.dart';
import '../../../core/theme/app_spacing.dart';
import '../../../core/theme/app_typography.dart';
import '../models/inventory_item.dart';
import '../models/inventory_transaction.dart';
import '../providers/inventory_provider.dart';

/// Modal dialog displaying the complete audit history of stock operations for an inventory item.
class InventoryTransactionHistoryDialog extends ConsumerStatefulWidget {
  const InventoryTransactionHistoryDialog({
    super.key,
    required this.item,
  });

  final InventoryItem item;

  @override
  ConsumerState<InventoryTransactionHistoryDialog> createState() =>
      _InventoryTransactionHistoryDialogState();
}

class _InventoryTransactionHistoryDialogState
    extends ConsumerState<InventoryTransactionHistoryDialog> {
  String _selectedFilter = 'All'; // 'All' | 'stock_in' | 'stock_out'

  @override
  Widget build(BuildContext context) {
    final transactionsAsync = ref.watch(itemTransactionsProvider(widget.item.id));
    final isDesktop = MediaQuery.sizeOf(context).width > 700;
    final dateFormat = DateFormat('MMM d, yyyy, h:mm a');

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
          maxWidth: isDesktop ? 680 : 440,
          maxHeight: MediaQuery.sizeOf(context).height * 0.85,
        ),
        child: Column(
          mainAxisSize: MainAxisSize.min,
          crossAxisAlignment: CrossAxisAlignment.stretch,
          children: [
            // Header
            Padding(
              padding: const EdgeInsets.symmetric(
                horizontal: AppSpacing.lg,
                vertical: AppSpacing.md,
              ),
              child: Row(
                children: [
                  Container(
                    padding: const EdgeInsets.all(AppSpacing.xs),
                    decoration: BoxDecoration(
                      color: AppColors.primaryContainer.withValues(alpha: 0.15),
                      borderRadius: BorderRadius.circular(AppSpacing.radiusMd),
                    ),
                    child: const Icon(
                      Icons.history_rounded,
                      color: AppColors.primary,
                      size: 24,
                    ),
                  ),
                  const SizedBox(width: AppSpacing.sm),
                  Expanded(
                    child: Column(
                      crossAxisAlignment: CrossAxisAlignment.start,
                      children: [
                        Text(
                          'Stock Transaction History',
                          style: AppTypography.headlineMd.copyWith(
                            fontWeight: FontWeight.w700,
                          ),
                        ),
                        Text(
                          '${widget.item.name} (${widget.item.formattedStock})',
                          style: AppTypography.bodySm.copyWith(
                            color: AppColors.onSurfaceVariant,
                          ),
                          overflow: TextOverflow.ellipsis,
                        ),
                      ],
                    ),
                  ),
                  IconButton(
                    tooltip: 'Refresh History',
                    icon: const Icon(Icons.refresh, size: 20),
                    onPressed: () {
                      ref.invalidate(itemTransactionsProvider(widget.item.id));
                    },
                  ),
                  IconButton(
                    icon: const Icon(Icons.close),
                    onPressed: () => Navigator.of(context).pop(),
                  ),
                ],
              ),
            ),
            const Divider(height: 1, color: AppColors.outlineVariant),

            // Filter Bar
            Padding(
              padding: const EdgeInsets.symmetric(
                horizontal: AppSpacing.lg,
                vertical: AppSpacing.xs,
              ),
              child: Row(
                children: [
                  Text(
                    'Filter:',
                    style: AppTypography.labelCaps.copyWith(
                      color: AppColors.onSurfaceVariant,
                      fontSize: 11,
                    ),
                  ),
                  const SizedBox(width: AppSpacing.sm),
                  _buildFilterChip('All', 'All'),
                  const SizedBox(width: 6),
                  _buildFilterChip('Stock In', 'stock_in'),
                  const SizedBox(width: 6),
                  _buildFilterChip('Stock Out', 'stock_out'),
                ],
              ),
            ),
            const Divider(height: 1, color: AppColors.outlineVariant),

            // Content List
            Expanded(
              child: transactionsAsync.when(
                loading: () => const Center(
                  child: Padding(
                    padding: EdgeInsets.all(AppSpacing.xl),
                    child: CircularProgressIndicator(),
                  ),
                ),
                error: (error, _) => Center(
                  child: Padding(
                    padding: const EdgeInsets.all(AppSpacing.lg),
                    child: Column(
                      mainAxisSize: MainAxisSize.min,
                      children: [
                        const Icon(Icons.error_outline, color: AppColors.error, size: 40),
                        const SizedBox(height: AppSpacing.sm),
                        Text(
                          'Failed to load transactions: $error',
                          style: AppTypography.bodySm.copyWith(color: AppColors.error),
                          textAlign: TextAlign.center,
                        ),
                        const SizedBox(height: AppSpacing.md),
                        OutlinedButton(
                          onPressed: () {
                            ref.invalidate(itemTransactionsProvider(widget.item.id));
                          },
                          child: const Text('Retry'),
                        ),
                      ],
                    ),
                  ),
                ),
                data: (allTransactions) {
                  final filtered = allTransactions.where((tx) {
                    if (_selectedFilter == 'All') return true;
                    return tx.transactionType == _selectedFilter;
                  }).toList();

                  if (filtered.isEmpty) {
                    return _buildEmptyState();
                  }

                  return ListView.separated(
                    padding: const EdgeInsets.all(AppSpacing.md),
                    itemCount: filtered.length,
                    separatorBuilder: (_, __) => const SizedBox(height: AppSpacing.sm),
                    itemBuilder: (context, index) {
                      final tx = filtered[index];
                      return _buildTransactionCard(tx, dateFormat);
                    },
                  );
                },
              ),
            ),
            const Divider(height: 1, color: AppColors.outlineVariant),

            // Footer
            Padding(
              padding: const EdgeInsets.all(AppSpacing.md),
              child: Row(
                mainAxisAlignment: MainAxisAlignment.end,
                children: [
                  FilledButton(
                    onPressed: () => Navigator.of(context).pop(),
                    style: FilledButton.styleFrom(
                      backgroundColor: AppColors.surfaceContainerHigh,
                      foregroundColor: AppColors.onSurface,
                    ),
                    child: const Text('Close'),
                  ),
                ],
              ),
            ),
          ],
        ),
      ),
    );
  }

  Widget _buildFilterChip(String label, String value) {
    final isSelected = _selectedFilter == value;
    return FilterChip(
      label: Text(label),
      selected: isSelected,
      onSelected: (_) {
        setState(() => _selectedFilter = value);
      },
      selectedColor: AppColors.primaryContainer.withValues(alpha: 0.25),
      checkmarkColor: AppColors.primary,
      labelStyle: TextStyle(
        fontSize: 11,
        fontWeight: isSelected ? FontWeight.w700 : FontWeight.normal,
        color: isSelected ? AppColors.primary : AppColors.onSurfaceVariant,
      ),
      backgroundColor: AppColors.surfaceContainerLow,
      visualDensity: VisualDensity.compact,
      padding: const EdgeInsets.symmetric(horizontal: 4),
    );
  }

  Widget _buildEmptyState() {
    return SingleChildScrollView(
      padding: const EdgeInsets.all(AppSpacing.md),
      child: Center(
        child: Column(
          mainAxisSize: MainAxisSize.min,
          children: [
            Container(
              padding: const EdgeInsets.all(AppSpacing.sm),
              decoration: BoxDecoration(
                color: AppColors.surfaceContainerLow,
                shape: BoxShape.circle,
              ),
              child: const Icon(
                Icons.receipt_long_outlined,
                size: 32,
                color: AppColors.onSurfaceVariant,
              ),
            ),
            const SizedBox(height: AppSpacing.sm),
            Text(
              'No stock transactions yet.',
              style: AppTypography.headlineMd.copyWith(
                fontWeight: FontWeight.w600,
                fontSize: 16,
              ),
            ),
            const SizedBox(height: AppSpacing.xs),
            Text(
              'Operations performed for this item will be logged here with complete audit details.',
              style: AppTypography.bodySm.copyWith(
                color: AppColors.onSurfaceVariant,
              ),
              textAlign: TextAlign.center,
            ),
          ],
        ),
      ),
    );
  }

  Widget _buildTransactionCard(
    InventoryTransaction tx,
    DateFormat dateFormat,
  ) {
    return Container(
      padding: const EdgeInsets.all(AppSpacing.md),
      decoration: BoxDecoration(
        color: AppColors.surfaceContainerLow,
        borderRadius: BorderRadius.circular(AppSpacing.radiusMd),
        border: Border.all(color: AppColors.outlineVariant),
      ),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          // Row 1: Type badge, progression, quantity
          Row(
            crossAxisAlignment: CrossAxisAlignment.center,
            children: [
              // Badge
              Container(
                padding: const EdgeInsets.symmetric(horizontal: 8, vertical: 3),
                decoration: BoxDecoration(
                  color: tx.typeColor.withValues(alpha: 0.15),
                  borderRadius: BorderRadius.circular(4),
                  border: Border.all(color: tx.typeColor),
                ),
                child: Row(
                  mainAxisSize: MainAxisSize.min,
                  children: [
                    Icon(tx.typeIcon, size: 14, color: tx.typeColor),
                    const SizedBox(width: 4),
                    Text(
                      tx.typeLabel.toUpperCase(),
                      style: TextStyle(
                        color: tx.typeColor,
                        fontSize: 10,
                        fontWeight: FontWeight.w700,
                      ),
                    ),
                  ],
                ),
              ),
              const SizedBox(width: AppSpacing.sm),

              // Stock progression (e.g. 20 -> 25)
              if (tx.formattedStockProgression != null) ...[
                Text(
                  tx.formattedStockProgression!,
                  style: AppTypography.bodySm.copyWith(
                    fontWeight: FontWeight.w600,
                    color: AppColors.onSurfaceVariant,
                  ),
                ),
              ],
              const Spacer(),

              // Quantity
              Text(
                '${tx.formattedQuantity} ${widget.item.unit}',
                style: AppTypography.bodyMd.copyWith(
                  fontWeight: FontWeight.w800,
                  color: tx.typeColor,
                ),
              ),
            ],
          ),
          const SizedBox(height: AppSpacing.xs),

          // Row 2: Reason
          if (tx.reason != null && tx.reason!.isNotEmpty) ...[
            Row(
              children: [
                Text(
                  'Reason: ',
                  style: AppTypography.bodySm.copyWith(
                    color: AppColors.onSurfaceVariant,
                    fontWeight: FontWeight.w500,
                  ),
                ),
                Expanded(
                  child: Text(
                    tx.reason!,
                    style: AppTypography.bodySm.copyWith(
                      fontWeight: FontWeight.w600,
                    ),
                    overflow: TextOverflow.ellipsis,
                  ),
                ),
              ],
            ),
          ],

          // Row 3: Remarks
          if (tx.remarks != null && tx.remarks!.isNotEmpty) ...[
            const SizedBox(height: 2),
            Text(
              'Remarks: ${tx.remarks!}',
              style: AppTypography.bodySm.copyWith(
                color: AppColors.onSurfaceVariant,
                fontStyle: FontStyle.italic,
              ),
            ),
          ],

          // Row 4: Patient details (shown when Dispensed to Patient, else Patient: —)
          if (tx.reason == 'Dispensed to Patient') ...[
            const SizedBox(height: 2),
            Row(
              children: [
                const Icon(
                  Icons.person,
                  size: 13,
                  color: AppColors.primary,
                ),
                const SizedBox(width: 4),
                Text(
                  'Patient: ',
                  style: AppTypography.bodySm.copyWith(
                    fontWeight: FontWeight.w600,
                    fontSize: 12,
                    color: AppColors.onSurface,
                  ),
                ),
                Expanded(
                  child: Text(
                    tx.patientDisplay ?? '—',
                    style: AppTypography.bodySm.copyWith(
                      fontWeight: FontWeight.w600,
                      fontSize: 12,
                      color: AppColors.primary,
                    ),
                    overflow: TextOverflow.ellipsis,
                  ),
                ),
              ],
            ),
          ] else ...[
            const SizedBox(height: 2),
            Text(
              'Patient: —',
              style: AppTypography.bodySm.copyWith(
                fontSize: 11,
                color: AppColors.onSurfaceVariant,
              ),
            ),
          ],
          if (tx.departmentName != null && tx.departmentName!.isNotEmpty) ...[
            const SizedBox(height: 2),
            Row(
              children: [
                const Icon(
                  Icons.business_outlined,
                  size: 13,
                  color: AppColors.secondary,
                ),
                const SizedBox(width: 4),
                Text(
                  'Department: ',
                  style: AppTypography.bodySm.copyWith(
                    fontWeight: FontWeight.w600,
                    fontSize: 12,
                    color: AppColors.onSurface,
                  ),
                ),
                Expanded(
                  child: Text(
                    tx.departmentName!,
                    style: AppTypography.bodySm.copyWith(
                      fontWeight: FontWeight.w600,
                      fontSize: 12,
                      color: AppColors.secondary,
                    ),
                    overflow: TextOverflow.ellipsis,
                  ),
                ),
              ],
            ),
          ],
          const SizedBox(height: 6),

          // Row 4: Performed by & Date
          Row(
            mainAxisAlignment: MainAxisAlignment.spaceBetween,
            children: [
              Row(
                children: [
                  const Icon(
                    Icons.person_outline,
                    size: 14,
                    color: AppColors.onSurfaceVariant,
                  ),
                  const SizedBox(width: 4),
                  Text(
                    tx.performedByName ?? 'Staff Member',
                    style: AppTypography.bodySm.copyWith(
                      fontSize: 11,
                      color: AppColors.onSurfaceVariant,
                    ),
                  ),
                ],
              ),
              Text(
                dateFormat.format(tx.createdAt.toLocal()),
                style: AppTypography.bodySm.copyWith(
                  fontSize: 11,
                  color: AppColors.onSurfaceVariant,
                ),
              ),
            ],
          ),
        ],
      ),
    );
  }
}
