import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';

import '../../../core/theme/app_colors.dart';
import '../../../core/theme/app_spacing.dart';
import '../../../core/theme/app_typography.dart';
import '../models/stock_request_model.dart';

/// Modal dialog showing complete details of a stock request / transfer record.
/// In the new direct-transfer workflow, requests are immediately transferred
/// so there are no approve/reject/fulfill actions.
class StockRequestDetailsDialog extends ConsumerWidget {
  const StockRequestDetailsDialog({
    super.key,
    required this.request,
  });

  final StockRequestModel request;

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    return Dialog(
      shape: RoundedRectangleBorder(
        borderRadius: BorderRadius.circular(AppSpacing.radiusLg),
      ),
      child: ConstrainedBox(
        constraints: const BoxConstraints(maxWidth: 580),
        child: Padding(
          padding: const EdgeInsets.all(AppSpacing.lg),
          child: Column(
            mainAxisSize: MainAxisSize.min,
            crossAxisAlignment: CrossAxisAlignment.start,
            children: [
              // Header
              Row(
                crossAxisAlignment: CrossAxisAlignment.start,
                children: [
                  Container(
                    padding: const EdgeInsets.all(AppSpacing.xs),
                    decoration: BoxDecoration(
                      color: AppColors.primaryContainer.withValues(alpha: 0.2),
                      borderRadius: BorderRadius.circular(AppSpacing.radiusSm),
                    ),
                    child: Icon(
                      request.isStockMoved
                          ? Icons.swap_horiz
                          : Icons.assignment_outlined,
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
                          'Stock Transfer #${request.requestNumber}',
                          style: AppTypography.headlineMd.copyWith(
                            fontWeight: FontWeight.bold,
                            fontSize: 18,
                          ),
                        ),
                        const SizedBox(height: 2),
                        Text(
                          'Department: ${request.departmentName}',
                          style: AppTypography.bodySm.copyWith(
                            color: AppColors.onSurfaceVariant,
                          ),
                        ),
                      ],
                    ),
                  ),
                  _buildStatusChip(request.status),
                  IconButton(
                    icon: const Icon(Icons.close),
                    tooltip: 'Close',
                    onPressed: () => Navigator.of(context).pop(),
                  ),
                ],
              ),
              const SizedBox(height: AppSpacing.md),

              // Request Information Grid
              Container(
                width: double.infinity,
                padding: const EdgeInsets.all(AppSpacing.md),
                decoration: BoxDecoration(
                  color: AppColors.surfaceContainerLowest,
                  borderRadius: BorderRadius.circular(AppSpacing.radiusMd),
                  border: Border.all(color: AppColors.outlineVariant),
                ),
                child: Column(
                  children: [
                    _buildRow('Item Name', request.itemName),
                    if (request.itemSku != null)
                      _buildRow('SKU', request.itemSku!),
                    _buildRow(
                      'Requested Quantity',
                      '${request.formattedRequestedQuantity} ${request.itemUnit}',
                    ),
                    if (request.fulfilledQuantity > 0)
                      _buildRow(
                        'Transferred Quantity',
                        '${request.formattedFulfilledQuantity} ${request.itemUnit}',
                      ),
                    _buildRow('Requested By', request.requestedByName ?? 'Staff Member'),
                    _buildRow('Requested On', request.formattedCreatedAt),
                    if (request.formattedFulfilledAt != null)
                      _buildRow('Transferred On', request.formattedFulfilledAt!),
                    if (request.requestNotes != null &&
                        request.requestNotes!.isNotEmpty)
                      _buildRow('Notes', request.requestNotes!),
                    // Show legacy fields for historical records
                    if (request.approvedQuantity != null &&
                        request.status != 'transferred')
                      _buildRow(
                        'Approved Quantity',
                        '${request.formattedApprovedQuantity} ${request.itemUnit}',
                      ),
                    if (request.reviewedByName != null &&
                        request.status != 'transferred')
                      _buildRow('Reviewed By', request.reviewedByName!),
                    if (request.formattedReviewedAt != null &&
                        request.status != 'transferred')
                      _buildRow('Reviewed On', request.formattedReviewedAt!),
                    if (request.fulfilledByName != null &&
                        request.status != 'transferred')
                      _buildRow('Fulfilled By', request.fulfilledByName!),
                    if (request.rejectionReason != null &&
                        request.rejectionReason!.isNotEmpty)
                      _buildRow('Rejection Reason', request.rejectionReason!, isError: true),
                  ],
                ),
              ),
              const SizedBox(height: AppSpacing.lg),

              // Close action only (no approval/reject/fulfill buttons)
              Row(
                mainAxisAlignment: MainAxisAlignment.end,
                children: [
                  TextButton(
                    onPressed: () => Navigator.of(context).pop(),
                    child: const Text('Close'),
                  ),
                ],
              ),
            ],
          ),
        ),
      ),
    );
  }

  Widget _buildRow(String label, String value, {bool isError = false}) {
    return Padding(
      padding: const EdgeInsets.symmetric(vertical: 4),
      child: Row(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          SizedBox(
            width: 140,
            child: Text(
              label,
              style: AppTypography.bodySm.copyWith(
                color: AppColors.onSurfaceVariant,
                fontWeight: FontWeight.w500,
              ),
            ),
          ),
          Expanded(
            child: Text(
              value,
              style: AppTypography.bodyMd.copyWith(
                color: isError ? AppColors.error : AppColors.onSurface,
                fontWeight: isError ? FontWeight.bold : FontWeight.w500,
              ),
            ),
          ),
        ],
      ),
    );
  }

  Widget _buildStatusChip(String status) {
    Color bg;
    Color fg;
    String label = status.toUpperCase();

    switch (status.toLowerCase()) {
      case 'pending':
        bg = Colors.amber.shade100;
        fg = Colors.amber.shade900;
        label = 'PENDING';
        break;
      case 'approved':
        bg = Colors.blue.shade100;
        fg = Colors.blue.shade900;
        label = 'APPROVED';
        break;
      case 'fulfilled':
        bg = Colors.green.shade100;
        fg = Colors.green.shade800;
        label = 'FULFILLED';
        break;
      case 'transferred':
        bg = Colors.green.shade100;
        fg = Colors.green.shade800;
        label = 'TRANSFERRED';
        break;
      case 'rejected':
        bg = Colors.red.shade100;
        fg = Colors.red.shade900;
        label = 'REJECTED';
        break;
      default:
        bg = AppColors.surfaceVariant;
        fg = AppColors.onSurfaceVariant;
    }

    return Container(
      padding: const EdgeInsets.symmetric(horizontal: 10, vertical: 4),
      decoration: BoxDecoration(
        color: bg,
        borderRadius: BorderRadius.circular(AppSpacing.radiusSm),
      ),
      child: Text(
        label,
        style: AppTypography.labelCaps.copyWith(
          color: fg,
          fontWeight: FontWeight.bold,
          fontSize: 10,
        ),
      ),
    );
  }
}
