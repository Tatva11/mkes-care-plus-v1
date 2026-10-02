import 'package:flutter/material.dart';
import '../../../core/theme/app_colors.dart';
import '../../../core/theme/app_spacing.dart';
import '../../../core/theme/app_typography.dart';
import '../../inventory/screens/inventory_screen.dart';

class InventoryItem {
  final String name;
  final int count;
  final double levelPercent;
  final String statusText;
  final Color statusColor;
  final Color barColor;
  final bool hasWarning;
  final Color? backgroundColor;

  const InventoryItem({
    required this.name,
    required this.count,
    required this.levelPercent,
    required this.statusText,
    required this.statusColor,
    required this.barColor,
    this.hasWarning = false,
    this.backgroundColor,
  });
}

class OpticalInventoryCard extends StatelessWidget {
  const OpticalInventoryCard({super.key});

  static final _items = [
    InventoryItem(
      name: 'Designer Frames (Titanium)',
      count: 45,
      levelPercent: 0.75,
      statusText: 'Healthy',
      statusColor: AppColors.onSurfaceVariant,
      barColor: AppColors.primaryContainer,
      backgroundColor: AppColors.surface,
    ),
    InventoryItem(
      name: 'Polycarbonate Blanks',
      count: 12,
      levelPercent: 0.15,
      statusText: 'Reorder Soon',
      statusColor: AppColors.error,
      barColor: AppColors.error,
      hasWarning: true,
      backgroundColor: AppColors.errorContainer.withValues(alpha: 0.1),
    ),
    InventoryItem(
      name: 'Standard Frames (Acetate)',
      count: 120,
      levelPercent: 0.85,
      statusText: 'Well Stocked',
      statusColor: AppColors.onSurfaceVariant,
      barColor: AppColors.tertiary,
      backgroundColor: AppColors.surface,
    ),
    InventoryItem(
      name: 'High Index Lens Blanks',
      count: 28,
      levelPercent: 0.40,
      statusText: 'Adequate',
      statusColor: AppColors.onSurfaceVariant,
      barColor: AppColors.primaryContainer,
      backgroundColor: AppColors.surface,
    ),
  ];

  @override
  Widget build(BuildContext context) {
    return Container(
      padding: const EdgeInsets.all(AppSpacing.sm),
      decoration: BoxDecoration(
        color: const Color(0xFFFEFEFD),
        borderRadius: BorderRadius.circular(AppSpacing.radiusXl),
        border: Border.all(color: const Color(0xFFE8E4E2)),
        boxShadow: const [
          BoxShadow(
            color: Color(0x0A000000),
            blurRadius: 20,
            offset: Offset(0, 4),
          ),
        ],
      ),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.stretch,
        children: [
          Row(
            mainAxisAlignment: MainAxisAlignment.spaceBetween,
            children: [
              Expanded(
                child: Row(
                  children: [
                    Container(
                      padding: const EdgeInsets.all(6),
                      decoration: BoxDecoration(
                        color:
                            AppColors.secondaryContainer.withValues(alpha: 0.3),
                        borderRadius:
                            BorderRadius.circular(AppSpacing.radiusMd),
                      ),
                      child: Icon(
                        Icons.inventory_2,
                        color: AppColors.tertiary,
                        size: 20,
                      ),
                    ),
                    const SizedBox(width: AppSpacing.xs),
                    Flexible(
                      child: Text(
                        'Optical Inventory',
                        style: AppTypography.headlineMd.copyWith(fontSize: 18),
                        overflow: TextOverflow.ellipsis,
                      ),
                    ),
                  ],
                ),
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
                  foregroundColor: AppColors.secondary,
                  textStyle: AppTypography.labelCaps,
                ),
                child: const Text('View All'),
              ),
            ],
          ),
          const SizedBox(height: AppSpacing.xs),
          ListView.separated(
            shrinkWrap: true,
            physics: const NeverScrollableScrollPhysics(),
            itemCount: _items.length,
            separatorBuilder: (_, __) => const SizedBox(height: AppSpacing.xs),
            itemBuilder: (context, index) {
              final item = _items[index];
              return Container(
                padding: const EdgeInsets.all(8),
                decoration: BoxDecoration(
                  color: item.backgroundColor,
                  borderRadius: BorderRadius.circular(AppSpacing.radiusMd),
                  border: Border.all(
                    color: item.hasWarning
                        ? AppColors.error.withValues(alpha: 0.2)
                        : AppColors.surfaceVariant,
                  ),
                ),
                child: Column(
                  crossAxisAlignment: CrossAxisAlignment.stretch,
                  children: [
                    Row(
                      mainAxisAlignment: MainAxisAlignment.spaceBetween,
                      children: [
                        Flexible(
                          child: Row(
                            children: [
                              Flexible(
                                child: Text(
                                  item.name,
                                  style: AppTypography.bodySm.copyWith(
                                    fontWeight: FontWeight.w500,
                                  ),
                                  overflow: TextOverflow.ellipsis,
                                ),
                              ),
                              if (item.hasWarning) ...[
                                const SizedBox(width: 4),
                                Icon(Icons.warning,
                                    size: 12, color: AppColors.error),
                              ],
                            ],
                          ),
                        ),
                        const SizedBox(width: 4),
                        Text(
                          item.count.toString(),
                          style: AppTypography.dataMono.copyWith(
                            color: item.hasWarning
                                ? AppColors.error
                                : AppColors.onSurface,
                          ),
                        ),
                      ],
                    ),
                    const SizedBox(height: 6),
                    Container(
                      height: 4,
                      decoration: BoxDecoration(
                        color: AppColors.surfaceVariant,
                        borderRadius: BorderRadius.circular(2),
                      ),
                      child: FractionallySizedBox(
                        alignment: Alignment.centerLeft,
                        widthFactor: item.levelPercent,
                        child: Container(
                          decoration: BoxDecoration(
                            color: item.barColor,
                            borderRadius: BorderRadius.circular(2),
                          ),
                        ),
                      ),
                    ),
                    const SizedBox(height: 4),
                    Text(
                      item.statusText,
                      textAlign: TextAlign.right,
                      style: TextStyle(
                        fontSize: 9,
                        fontWeight: FontWeight.w700,
                        letterSpacing: 0.5,
                        color: item.statusColor,
                      ),
                    ),
                  ],
                ),
              );
            },
          ),
          const SizedBox(height: AppSpacing.sm),
          FilledButton.icon(
            onPressed: () {},
            icon: const Icon(Icons.add_shopping_cart, size: 18),
            label: const Text('Quick Reorder'),
            style: FilledButton.styleFrom(
              backgroundColor: AppColors.primaryContainer,
              foregroundColor: Colors.white,
              padding: const EdgeInsets.symmetric(vertical: AppSpacing.sm),
              textStyle: AppTypography.bodySm,
              shape: RoundedRectangleBorder(
                borderRadius: BorderRadius.circular(AppSpacing.radiusMd),
              ),
            ),
          ),
        ],
      ),
    );
  }
}

class DepartmentCopilotActionCard extends StatelessWidget {
  const DepartmentCopilotActionCard({super.key});

  @override
  Widget build(BuildContext context) {
    return Container(
      padding: const EdgeInsets.all(AppSpacing.sm),
      decoration: BoxDecoration(
        color: AppColors.surfaceContainerLowest,
        borderRadius: BorderRadius.circular(AppSpacing.radiusXl),
        border: Border.all(color: AppColors.outlineVariant),
        boxShadow: const [
          BoxShadow(
            color: Color(0x0A000000),
            blurRadius: 20,
            offset: Offset(0, 4),
          ),
        ],
      ),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Row(
            mainAxisAlignment: MainAxisAlignment.spaceBetween,
            children: [
              Container(
                padding: const EdgeInsets.all(8),
                decoration: BoxDecoration(
                  color: AppColors.primaryContainer.withValues(alpha: 0.1),
                  borderRadius: BorderRadius.circular(AppSpacing.radiusMd),
                  border: Border.all(
                      color: AppColors.primaryContainer.withValues(alpha: 0.2)),
                ),
                child: const Icon(Icons.psychology, color: AppColors.primary),
              ),
              Container(
                padding: const EdgeInsets.symmetric(horizontal: 8, vertical: 2),
                decoration: BoxDecoration(
                  color: AppColors.primaryFixed.withValues(alpha: 0.5),
                  borderRadius: BorderRadius.circular(16),
                ),
                child: Text(
                  'Copilot',
                  style: AppTypography.labelCaps
                      .copyWith(color: AppColors.primary),
                ),
              ),
            ],
          ),
          const SizedBox(height: AppSpacing.sm),
          Column(
            crossAxisAlignment: CrossAxisAlignment.start,
            children: [
              Text(
                'Optimize Production Schedule',
                style: AppTypography.headlineMd.copyWith(fontSize: 18),
              ),
              const SizedBox(height: 4),
              Text(
                'AI suggests re-ordering queue based on rush requests and current blank availability to improve output by 14%.',
                style: AppTypography.bodySm
                    .copyWith(color: AppColors.onSurfaceVariant),
                maxLines: 2,
                overflow: TextOverflow.ellipsis,
              ),
            ],
          ),
        ],
      ),
    );
  }
}
