import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';

import '../../../core/theme/app_colors.dart';
import '../../../core/theme/app_spacing.dart';
import '../../../core/theme/app_typography.dart';
import '../../inventory/models/inventory_item.dart';
import '../../inventory/providers/inventory_provider.dart';
import '../../inventory/screens/inventory_screen.dart';
import '../../inventory/widgets/inventory_details_dialog.dart';

/// Dashboard card displaying real-time critical stock alerts (low stock, expiring soon, expired).
class InventoryAlertsCard extends ConsumerWidget {
  const InventoryAlertsCard({super.key});

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    final inventoryAsync = ref.watch(inventoryProvider);

    return DecoratedBox(
      decoration: BoxDecoration(
        color: AppColors.surfaceContainerLowest,
        borderRadius: BorderRadius.circular(AppSpacing.radiusLg),
        border: Border.all(color: const Color(0xFFE5E2E1)),
        boxShadow: const [
          BoxShadow(
            color: Color(0x0A000000),
            blurRadius: 8,
            offset: Offset(0, 1),
          ),
        ],
      ),
      child: Padding(
        padding: const EdgeInsets.all(AppSpacing.md),
        child: Column(
          crossAxisAlignment: CrossAxisAlignment.stretch,
          children: [
            // Header
            DecoratedBox(
              decoration: const BoxDecoration(
                border: Border(
                  bottom: BorderSide(color: AppColors.outlineVariant),
                ),
              ),
              child: Padding(
                padding: const EdgeInsets.only(bottom: AppSpacing.xs),
                child: Wrap(
                  alignment: WrapAlignment.spaceBetween,
                  crossAxisAlignment: WrapCrossAlignment.center,
                  spacing: AppSpacing.xs,
                  runSpacing: 4,
                  children: [
                    Row(
                      mainAxisSize: MainAxisSize.min,
                      children: [
                        const Icon(
                          Icons.inventory_2_outlined,
                          color: AppColors.secondary,
                          size: 22,
                        ),
                        const SizedBox(width: AppSpacing.xs),
                        Flexible(
                          child: Text(
                            'Critical Inventory',
                            style: AppTypography.headlineMd,
                          ),
                        ),
                      ],
                    ),
                    TextButton(
                      onPressed: () {
                        Navigator.of(context).push(
                          MaterialPageRoute(
                            builder: (_) => const InventoryManagementScreen(),
                          ),
                        );
                      },
                      style: TextButton.styleFrom(
                        padding: EdgeInsets.zero,
                        minimumSize: Size.zero,
                        tapTargetSize: MaterialTapTargetSize.shrinkWrap,
                      ),
                      child: Text(
                        'Manage Inventory',
                        style: AppTypography.labelCaps.copyWith(
                          color: AppColors.primary,
                        ),
                      ),
                    ),
                  ],
                ),
              ),
            ),
            const SizedBox(height: AppSpacing.md),

            // Realtime Critical Items
            inventoryAsync.when(
              loading: () => const Padding(
                padding: EdgeInsets.all(AppSpacing.lg),
                child: Center(
                  child: SizedBox(
                    width: 20,
                    height: 20,
                    child: CircularProgressIndicator(strokeWidth: 2),
                  ),
                ),
              ),
              error: (err, _) => _buildErrorState(ref, err.toString()),
              data: (items) {
                final criticalItems = items.where((item) {
                  return item.isLowStock ||
                      item.expiryStatus == ExpiryStatus.expiringSoon ||
                      item.expiryStatus == ExpiryStatus.expired;
                }).toList();

                if (criticalItems.isEmpty) {
                  return _buildAllHealthyState();
                }

                // Show top 3 critical items
                final displayItems = criticalItems.take(3).toList();
                return Column(
                  children: [
                    for (int i = 0; i < displayItems.length; i++) ...[
                      if (i > 0) const SizedBox(height: AppSpacing.sm),
                      _buildAlertTile(context, displayItems[i]),
                    ],
                  ],
                );
              },
            ),
          ],
        ),
      ),
    );
  }

  Widget _buildAlertTile(BuildContext context, InventoryItem item) {
    final bool isLow = item.isLowStock;
    final bool isExpired = item.expiryStatus == ExpiryStatus.expired;
    final bool isExpiringSoon = item.expiryStatus == ExpiryStatus.expiringSoon;

    final IconData icon;
    final Color iconBackground;
    final Color iconColor;
    final String subtitle;
    final Color subtitleColor;

    if (isExpired) {
      icon = Icons.event_busy_outlined;
      iconBackground = const Color(0x33B3261E);
      iconColor = AppColors.error;
      subtitle = 'Expired (${item.formattedStock} remaining)';
      subtitleColor = AppColors.error;
    } else if (isLow) {
      icon = Icons.warning_amber_rounded;
      iconBackground = const Color(0x33B3261E);
      iconColor = AppColors.error;
      subtitle = item.minimumStock != null
          ? 'Stock: ${item.formattedStock} (Min: ${item.formattedMinStock})'
          : 'Low Stock: ${item.formattedStock}';
      subtitleColor = AppColors.error;
    } else if (isExpiringSoon) {
      icon = Icons.schedule_outlined;
      iconBackground = const Color(0x33E65100);
      iconColor = const Color(0xFFE65100);
      subtitle =
          'Expiring in ${item.daysUntilExpiry} days (${item.formattedStock})';
      subtitleColor = const Color(0xFFE65100);
    } else {
      icon = Icons.inventory_2_outlined;
      iconBackground = const Color(0x80FFD8EB);
      iconColor = AppColors.secondary;
      subtitle = item.formattedStock;
      subtitleColor = AppColors.onSurfaceVariant;
    }

    return _InventoryAlertItem(
      icon: icon,
      iconBackground: iconBackground,
      iconColor: iconColor,
      title: item.name,
      subtitle: subtitle,
      subtitleColor: subtitleColor,
      actionLabel: 'View',
      actionBorderColor: iconColor,
      actionTextColor: iconColor,
      onTap: () {
        showDialog(
          context: context,
          builder: (_) => InventoryDetailsDialog(item: item),
        );
      },
    );
  }

  Widget _buildAllHealthyState() {
    return Container(
      padding: const EdgeInsets.all(AppSpacing.md),
      decoration: BoxDecoration(
        color: AppColors.surfaceContainerLow,
        borderRadius: BorderRadius.circular(AppSpacing.radiusMd),
      ),
      child: Row(
        children: [
          Container(
            padding: const EdgeInsets.all(AppSpacing.xs),
            decoration: BoxDecoration(
              color: Colors.green.withValues(alpha: 0.15),
              shape: BoxShape.circle,
            ),
            child: const Icon(
              Icons.check_circle_outline,
              color: Colors.green,
              size: 20,
            ),
          ),
          const SizedBox(width: AppSpacing.sm),
          Expanded(
            child: Column(
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                Text(
                  'All Stock Levels Healthy',
                  style: AppTypography.bodyMd.copyWith(
                    fontWeight: FontWeight.w600,
                  ),
                ),
                Text(
                  'No critical low-stock or expiring items.',
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
    );
  }

  Widget _buildErrorState(WidgetRef ref, String error) {
    return Container(
      padding: const EdgeInsets.all(AppSpacing.md),
      alignment: Alignment.center,
      child: Column(
        mainAxisAlignment: MainAxisAlignment.center,
        children: [
          const Icon(Icons.error_outline, color: AppColors.error, size: 28),
          const SizedBox(height: AppSpacing.xs),
          Text(
            'Unable to load inventory alerts',
            style: AppTypography.labelCaps.copyWith(
              color: AppColors.error,
              fontWeight: FontWeight.w600,
            ),
          ),
          const SizedBox(height: AppSpacing.xs),
          OutlinedButton.icon(
            onPressed: () => ref.invalidate(inventoryProvider),
            icon: const Icon(Icons.refresh, size: 14),
            label: const Text('Retry'),
            style: OutlinedButton.styleFrom(
              padding: const EdgeInsets.symmetric(
                horizontal: AppSpacing.sm,
                vertical: AppSpacing.base,
              ),
            ),
          ),
        ],
      ),
    );
  }
}

class _InventoryAlertItem extends StatelessWidget {
  const _InventoryAlertItem({
    required this.icon,
    required this.iconBackground,
    required this.iconColor,
    required this.title,
    required this.subtitle,
    this.subtitleColor,
    this.actionLabel,
    this.actionBorderColor,
    this.actionTextColor,
    this.onTap,
  });

  final IconData icon;
  final Color iconBackground;
  final Color iconColor;
  final String title;
  final String subtitle;
  final Color? subtitleColor;
  final String? actionLabel;
  final Color? actionBorderColor;
  final Color? actionTextColor;
  final VoidCallback? onTap;

  @override
  Widget build(BuildContext context) {
    return Material(
      color: AppColors.surfaceContainerLow,
      borderRadius: BorderRadius.circular(AppSpacing.radiusMd),
      child: InkWell(
        onTap: onTap,
        borderRadius: BorderRadius.circular(AppSpacing.radiusMd),
        hoverColor: AppColors.surfaceContainerLow,
        child: Container(
          padding: const EdgeInsets.all(AppSpacing.sm),
          decoration: BoxDecoration(
            borderRadius: BorderRadius.circular(AppSpacing.radiusMd),
            border: Border.all(color: Colors.transparent),
          ),
          child: Row(
            children: [
              Container(
                width: 40,
                height: 40,
                decoration: BoxDecoration(
                  color: iconBackground,
                  borderRadius: BorderRadius.circular(AppSpacing.radiusSm),
                ),
                child: Icon(icon, color: iconColor, size: 22),
              ),
              const SizedBox(width: AppSpacing.sm),
              Expanded(
                child: Column(
                  crossAxisAlignment: CrossAxisAlignment.start,
                  children: [
                    Text(
                      title,
                      style: AppTypography.bodyMd.copyWith(
                        fontWeight: FontWeight.w600,
                      ),
                      overflow: TextOverflow.ellipsis,
                      maxLines: 1,
                    ),
                    Text(
                      subtitle,
                      style: AppTypography.bodySm.copyWith(
                        color: subtitleColor ?? AppColors.onSurfaceVariant,
                      ),
                      overflow: TextOverflow.ellipsis,
                      maxLines: 1,
                    ),
                  ],
                ),
              ),
              if (actionLabel != null)
                OutlinedButton(
                  onPressed: onTap,
                  style: OutlinedButton.styleFrom(
                    backgroundColor: AppColors.surface,
                    foregroundColor: actionTextColor,
                    side: BorderSide(
                        color: actionBorderColor ?? AppColors.outlineVariant),
                    padding: const EdgeInsets.symmetric(
                      horizontal: 12,
                      vertical: AppSpacing.base,
                    ),
                    minimumSize: Size.zero,
                    tapTargetSize: MaterialTapTargetSize.shrinkWrap,
                    shape: RoundedRectangleBorder(
                      borderRadius: BorderRadius.circular(AppSpacing.radiusSm),
                    ),
                  ),
                  child: Text(
                    actionLabel!,
                    style: AppTypography.labelCaps.copyWith(
                      color: actionTextColor,
                    ),
                  ),
                ),
            ],
          ),
        ),
      ),
    );
  }
}
