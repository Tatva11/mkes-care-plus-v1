import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';

import '../../../core/theme/app_colors.dart';
import '../../../core/theme/app_spacing.dart';
import '../../../core/theme/app_typography.dart';
import '../providers/billing_provider.dart';

class BillingSummaryCards extends ConsumerWidget {
  const BillingSummaryCards({super.key});

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    final metrics = ref.watch(adminBillingMetricsProvider);
    final isDesktop = MediaQuery.sizeOf(context).width >= 900;
    final isTablet = MediaQuery.sizeOf(context).width >= 600 && !isDesktop;

    final cards = [
      _MetricCard(
        title: 'Total Sales',
        value: '₹${metrics.totalSales.toStringAsFixed(2)}',
        subtitle: '${metrics.totalInvoices} Invoices Generated',
        icon: Icons.receipt_long_outlined,
        color: AppColors.primary,
        bgColor: AppColors.primaryContainer.withValues(alpha: 0.12),
      ),
      _MetricCard(
        title: 'Revenue Collected',
        value: '₹${metrics.totalRevenue.toStringAsFixed(2)}',
        subtitle: '${metrics.paidInvoicesCount} Settled Invoices',
        icon: Icons.account_balance_wallet_outlined,
        color: Colors.green[700]!,
        bgColor: Colors.green.withValues(alpha: 0.10),
      ),
      _MetricCard(
        title: 'Outstanding Balance',
        value: '₹${metrics.totalOutstanding.toStringAsFixed(2)}',
        subtitle: '${metrics.partiallyPaidInvoicesCount} Partially Paid',
        icon: Icons.pending_actions_outlined,
        color: Colors.orange[800]!,
        bgColor: Colors.orange.withValues(alpha: 0.10),
      ),
      _MetricCard(
        title: 'Estimated Profit',
        value: '₹${metrics.estimatedProfit.toStringAsFixed(2)}',
        subtitle: 'Estimated Gross Margin (70%)',
        icon: Icons.auto_graph_outlined,
        color: Colors.teal[700]!,
        bgColor: Colors.teal.withValues(alpha: 0.10),
        tooltip:
            'Temporary isolated calculation (70% margin placeholder). Real inventory & COGS data will connect once Sprint 6 is merged.',
      ),
    ];

    if (isDesktop) {
      return Row(
        children: [
          for (int i = 0; i < cards.length; i++) ...[
            Expanded(child: cards[i]),
            if (i < cards.length - 1) const SizedBox(width: AppSpacing.md),
          ],
        ],
      );
    }

    if (isTablet) {
      return Column(
        children: [
          Row(
            children: [
              Expanded(child: cards[0]),
              const SizedBox(width: AppSpacing.md),
              Expanded(child: cards[1]),
            ],
          ),
          const SizedBox(height: AppSpacing.md),
          Row(
            children: [
              Expanded(child: cards[2]),
              const SizedBox(width: AppSpacing.md),
              Expanded(child: cards[3]),
            ],
          ),
        ],
      );
    }

    // Mobile layout: 2x2 grid or stacked
    return Column(
      children: [
        for (int i = 0; i < cards.length; i++) ...[
          cards[i],
          if (i < cards.length - 1) const SizedBox(height: AppSpacing.sm),
        ],
      ],
    );
  }
}

class _MetricCard extends StatelessWidget {
  final String title;
  final String value;
  final String subtitle;
  final IconData icon;
  final Color color;
  final Color bgColor;
  final String? tooltip;

  const _MetricCard({
    required this.title,
    required this.value,
    required this.subtitle,
    required this.icon,
    required this.color,
    required this.bgColor,
    this.tooltip,
  });

  @override
  Widget build(BuildContext context) {
    return Container(
      padding: const EdgeInsets.all(AppSpacing.md),
      decoration: BoxDecoration(
        color: AppColors.surfaceContainerLowest,
        borderRadius: BorderRadius.circular(AppSpacing.radiusMd),
        border: Border.all(color: AppColors.outlineVariant),
        boxShadow: [
          BoxShadow(
            color: Colors.black.withValues(alpha: 0.02),
            blurRadius: 4,
            offset: const Offset(0, 2),
          ),
        ],
      ),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Row(
            mainAxisAlignment: MainAxisAlignment.spaceBetween,
            children: [
              Expanded(
                child: Row(
                  children: [
                    Flexible(
                      child: Text(
                        title,
                        style: AppTypography.labelCaps.copyWith(
                          color: AppColors.onSurfaceVariant,
                          fontWeight: FontWeight.w600,
                        ),
                        overflow: TextOverflow.ellipsis,
                      ),
                    ),
                    if (tooltip != null) ...[
                      const SizedBox(width: 4),
                      Tooltip(
                        message: tooltip!,
                        child: const Icon(
                          Icons.info_outline,
                          size: 14,
                          color: AppColors.outline,
                        ),
                      ),
                    ],
                  ],
                ),
              ),
              const SizedBox(width: AppSpacing.xs),
              Container(
                padding: const EdgeInsets.all(6),
                decoration: BoxDecoration(
                  color: bgColor,
                  borderRadius: BorderRadius.circular(AppSpacing.radiusSm),
                ),
                child: Icon(icon, size: 18, color: color),
              ),
            ],
          ),
          const SizedBox(height: AppSpacing.xs),
          FittedBox(
            fit: BoxFit.scaleDown,
            alignment: Alignment.centerLeft,
            child: Text(
              value,
              style: AppTypography.headlineMd.copyWith(
                fontWeight: FontWeight.bold,
                color: AppColors.onSurface,
              ),
            ),
          ),
          const SizedBox(height: 2),
          Text(
            subtitle,
            style: AppTypography.bodySm.copyWith(
              color: AppColors.onSurfaceVariant,
              fontSize: 11,
            ),
            overflow: TextOverflow.ellipsis,
            maxLines: 1,
          ),
        ],
      ),
    );
  }
}
