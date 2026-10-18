import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:intl/intl.dart';

import '../../../core/theme/app_colors.dart';
import '../../../core/theme/app_spacing.dart';
import '../../../core/theme/app_typography.dart';
import '../../../core/utils/date_boundaries.dart';
import '../../billing/providers/billing_provider.dart';
import '../../reports/models/reports_filter_model.dart';
import '../../reports/providers/reports_provider.dart';
import '../../reports/screens/admin_reports_screen.dart';

/// Admin Dashboard Card showing today-only revenue collections, growth vs yesterday,
/// payment modes, and an intraday timeline chart.
class RevenueGrowthCard extends ConsumerWidget {
  const RevenueGrowthCard({super.key});

  static const _surfaceContainerHigh = Color(0xFFEAE7E7);

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    final revenueAsync = ref.watch(todayRevenueMetricsProvider);
    final currency = NumberFormat.currency(
      locale: 'en_IN',
      symbol: '₹',
      decimalDigits: 0,
    );

    return _DashboardCard(
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Row(
            mainAxisAlignment: MainAxisAlignment.spaceBetween,
            children: [
              Expanded(
                child: Row(
                  children: [
                    const Icon(
                      Icons.trending_up,
                      color: AppColors.primaryContainer,
                      size: 22,
                    ),
                    const SizedBox(width: AppSpacing.xs),
                    Flexible(
                      child: Text(
                        'Revenue Growth',
                        style: AppTypography.headlineMd,
                        overflow: TextOverflow.ellipsis,
                      ),
                    ),
                  ],
                ),
              ),
              TextButton(
                onPressed: () {
                  ref.read(adminReportsSectionProvider.notifier).state =
                      ReportsSection.financial;
                  Navigator.of(context).push(
                    MaterialPageRoute(
                      builder: (_) => const AdminReportsScreen(),
                    ),
                  );
                },
                style: TextButton.styleFrom(
                  padding: EdgeInsets.zero,
                  minimumSize: Size.zero,
                  tapTargetSize: MaterialTapTargetSize.shrinkWrap,
                ),
                child: Row(
                  mainAxisSize: MainAxisSize.min,
                  children: [
                    Text(
                      'View Reports',
                      style: AppTypography.labelCaps.copyWith(
                        color: AppColors.primary,
                      ),
                    ),
                    const SizedBox(width: 2),
                    const Icon(
                      Icons.chevron_right,
                      size: 16,
                      color: AppColors.primary,
                    ),
                  ],
                ),
              ),
            ],
          ),
          const SizedBox(height: AppSpacing.sm),
          revenueAsync.when(
            loading: () => _buildLoadingState(),
            error: (err, _) => _buildErrorState(ref, err.toString()),
            data: (metrics) => _buildDataContent(context, metrics, currency),
          ),
        ],
      ),
    );
  }

  Widget _buildLoadingState() {
    return const SizedBox(
      height: 250,
      child: Center(
        child: Column(
          mainAxisAlignment: MainAxisAlignment.center,
          children: [
            SizedBox(
              width: 28,
              height: 28,
              child: CircularProgressIndicator(
                strokeWidth: 2.5,
                color: AppColors.primary,
              ),
            ),
            SizedBox(height: AppSpacing.sm),
            Text(
              "Loading today's revenue...",
              style: TextStyle(
                color: AppColors.onSurfaceVariant,
                fontSize: 12,
              ),
            ),
          ],
        ),
      ),
    );
  }

  Widget _buildErrorState(WidgetRef ref, String error) {
    return SizedBox(
      height: 250,
      child: Center(
        child: Padding(
          padding: const EdgeInsets.symmetric(horizontal: AppSpacing.md),
          child: Column(
            mainAxisAlignment: MainAxisAlignment.center,
            children: [
              const Icon(
                Icons.error_outline,
                color: AppColors.error,
                size: 32,
              ),
              const SizedBox(height: AppSpacing.xs),
              Text(
                'Unable to load revenue data',
                style: AppTypography.labelCaps.copyWith(
                  color: AppColors.error,
                  fontWeight: FontWeight.w600,
                ),
              ),
              const SizedBox(height: AppSpacing.xs),
              Text(
                error,
                style: AppTypography.bodySm.copyWith(
                  color: AppColors.onSurfaceVariant,
                  fontSize: 12,
                ),
                maxLines: 2,
                overflow: TextOverflow.ellipsis,
                textAlign: TextAlign.center,
              ),
              const SizedBox(height: AppSpacing.sm),
              OutlinedButton.icon(
                onPressed: () => ref.invalidate(todayRevenueMetricsProvider),
                icon: const Icon(Icons.refresh, size: 16),
                label: const Text('Retry'),
                style: OutlinedButton.styleFrom(
                  padding: const EdgeInsets.symmetric(
                    horizontal: AppSpacing.md,
                    vertical: AppSpacing.xs,
                  ),
                ),
              ),
            ],
          ),
        ),
      ),
    );
  }

  Widget _buildDataContent(
    BuildContext context,
    TodayRevenueMetrics metrics,
    NumberFormat currency,
  ) {
    return Column(
      crossAxisAlignment: CrossAxisAlignment.start,
      children: [
        Row(
          crossAxisAlignment: CrossAxisAlignment.baseline,
          textBaseline: TextBaseline.alphabetic,
          children: [
            Flexible(
              child: Text(
                currency.format(metrics.todayRevenue),
                style: AppTypography.displayLg.copyWith(
                  color: AppColors.onSurface,
                ),
                maxLines: 1,
                overflow: TextOverflow.ellipsis,
              ),
            ),
            const SizedBox(width: AppSpacing.xs),
            _buildGrowthBadge(metrics.growthPercentage),
          ],
        ),
        const SizedBox(height: 2),
        Text(
          metrics.todayTransactionsCount > 0
              ? '${metrics.todayTransactionsCount} collection transaction${metrics.todayTransactionsCount == 1 ? '' : 's'} today'
              : 'No collections recorded today',
          style: AppTypography.bodySm.copyWith(
            color: AppColors.onSurfaceVariant,
            fontSize: 12,
          ),
        ),
        const SizedBox(height: AppSpacing.xs),

        // Today's collections breakdown by payment mode
        if (metrics.todayRevenue > 0) ...[
          Padding(
            padding: const EdgeInsets.symmetric(vertical: 2),
            child: Wrap(
              spacing: AppSpacing.sm,
              runSpacing: 4,
              children: [
                if ((metrics.paymentModeAmounts['cash'] ?? 0) > 0)
                  _PaymentModeChip(
                    label:
                        'Cash: ${currency.format(metrics.paymentModeAmounts['cash'])}',
                    color: AppColors.primary,
                  ),
                if ((metrics.paymentModeAmounts['upi'] ?? 0) > 0)
                  _PaymentModeChip(
                    label:
                        'UPI: ${currency.format(metrics.paymentModeAmounts['upi'])}',
                    color: AppColors.secondary,
                  ),
                if ((metrics.paymentModeAmounts['bank_transfer'] ?? 0) > 0)
                  _PaymentModeChip(
                    label:
                        'Bank: ${currency.format(metrics.paymentModeAmounts['bank_transfer'])}',
                    color: const Color(0xFF2E7D32),
                  ),
                if ((metrics.paymentModeAmounts['other'] ?? 0) > 0)
                  _PaymentModeChip(
                    label:
                        'Other: ${currency.format(metrics.paymentModeAmounts['other'])}',
                    color: AppColors.outline,
                  ),
              ],
            ),
          ),
        ],

        const SizedBox(height: AppSpacing.md),

        // Intraday Chart over today's time buckets
        _buildIntradayChart(
            metrics.intradayHourlyBuckets, metrics.todayRevenue),
      ],
    );
  }

  Widget _buildGrowthBadge(double? growth) {
    final String label;
    final Color textColor;
    final Color bgColor;

    if (growth == null) {
      label = 'Growth unavailable';
      textColor = AppColors.onSurfaceVariant;
      bgColor = _surfaceContainerHigh;
    } else if (growth > 0) {
      label = '+${growth.toStringAsFixed(1)}% vs yesterday';
      textColor = const Color(0xFF2E7D32);
      bgColor = const Color(0xFFE8F5E9);
    } else if (growth < 0) {
      label = '${growth.toStringAsFixed(1)}% vs yesterday';
      textColor = AppColors.error;
      bgColor = const Color(0xFFFFEBEE);
    } else {
      label = '0.0% vs yesterday';
      textColor = AppColors.onSurfaceVariant;
      bgColor = _surfaceContainerHigh;
    }

    return Container(
      padding: const EdgeInsets.symmetric(
        horizontal: AppSpacing.xs,
        vertical: AppSpacing.base,
      ),
      decoration: BoxDecoration(
        color: bgColor,
        borderRadius: BorderRadius.circular(AppSpacing.radiusSm),
      ),
      child: Text(
        label,
        style: AppTypography.labelCaps.copyWith(
          color: textColor,
          fontWeight: FontWeight.w600,
        ),
      ),
    );
  }

  Widget _buildIntradayChart(List<double> buckets, double totalRevenue) {
    if (totalRevenue <= 0) {
      return Container(
        height: 192,
        alignment: Alignment.center,
        decoration: const BoxDecoration(
          border: Border(
            left: BorderSide(color: _surfaceContainerHigh),
            bottom: BorderSide(color: _surfaceContainerHigh),
          ),
        ),
        child: Column(
          mainAxisAlignment: MainAxisAlignment.center,
          children: [
            const Icon(
              Icons.bar_chart_outlined,
              size: 36,
              color: AppColors.outlineVariant,
            ),
            const SizedBox(height: AppSpacing.xs),
            Text(
              'No collections recorded today',
              style: AppTypography.bodySm.copyWith(
                color: AppColors.onSurfaceVariant,
              ),
            ),
          ],
        ),
      );
    }

    double maxBucketAmount = 0.0;
    for (final b in buckets) {
      if (b > maxBucketAmount) {
        maxBucketAmount = b;
      }
    }

    return SizedBox(
      height: 192,
      child: Stack(
        clipBehavior: Clip.none,
        children: [
          Positioned(
            left: 0,
            top: 32,
            bottom: 24,
            width: 44,
            child: Column(
              mainAxisAlignment: MainAxisAlignment.spaceBetween,
              children: [
                _YAxisLabel(_formatCompact(maxBucketAmount)),
                _YAxisLabel(_formatCompact(maxBucketAmount * 2 / 3)),
                _YAxisLabel(_formatCompact(maxBucketAmount / 3)),
                const _YAxisLabel('0'),
              ],
            ),
          ),
          Positioned(
            left: 48,
            right: 0,
            top: 0,
            bottom: 0,
            child: DecoratedBox(
              decoration: const BoxDecoration(
                border: Border(
                  left: BorderSide(color: _surfaceContainerHigh),
                  bottom: BorderSide(color: _surfaceContainerHigh),
                ),
              ),
              child: Padding(
                padding: const EdgeInsets.fromLTRB(
                  AppSpacing.xs,
                  AppSpacing.lg,
                  AppSpacing.xs,
                  AppSpacing.base,
                ),
                child: Row(
                  crossAxisAlignment: CrossAxisAlignment.end,
                  children: [
                    for (int i = 0; i < buckets.length; i++)
                      _ChartBar(
                        label: DateBoundaries.intradayBucketLabels[i],
                        heightFactor: maxBucketAmount > 0
                            ? (buckets[i] / maxBucketAmount).clamp(0.06, 1.0)
                            : 0.06,
                        color: (buckets[i] == maxBucketAmount &&
                                maxBucketAmount > 0)
                            ? AppColors.primaryContainer
                            : _surfaceContainerHigh,
                        highlighted: (buckets[i] == maxBucketAmount &&
                            maxBucketAmount > 0),
                        tooltip:
                            buckets[i] > 0 ? _formatCompact(buckets[i]) : null,
                      ),
                  ],
                ),
              ),
            ),
          ),
        ],
      ),
    );
  }

  static String _formatCompact(double value) {
    if (value <= 0) return '0';
    if (value >= 10000000) {
      return '${(value / 10000000).toStringAsFixed(1)}Cr';
    } else if (value >= 100000) {
      return '${(value / 100000).toStringAsFixed(1)}L';
    } else if (value >= 1000) {
      return '${(value / 1000).toStringAsFixed(0)}k';
    }
    return value.toStringAsFixed(0);
  }
}

class _PaymentModeChip extends StatelessWidget {
  const _PaymentModeChip({
    required this.label,
    required this.color,
  });

  final String label;
  final Color color;

  @override
  Widget build(BuildContext context) {
    return Container(
      padding: const EdgeInsets.symmetric(horizontal: 6, vertical: 2),
      decoration: BoxDecoration(
        color: color.withValues(alpha: 0.08),
        borderRadius: BorderRadius.circular(4),
        border: Border.all(color: color.withValues(alpha: 0.2)),
      ),
      child: Text(
        label,
        style: TextStyle(
          fontSize: 10,
          fontWeight: FontWeight.w600,
          color: color,
        ),
      ),
    );
  }
}

class _YAxisLabel extends StatelessWidget {
  const _YAxisLabel(this.text);

  final String text;

  @override
  Widget build(BuildContext context) {
    return Text(
      text,
      style: AppTypography.labelCaps.copyWith(
        color: AppColors.outlineVariant,
        fontSize: 10,
      ),
      textAlign: TextAlign.right,
    );
  }
}

class _ChartBar extends StatelessWidget {
  const _ChartBar({
    required this.label,
    required this.heightFactor,
    required this.color,
    this.highlighted = false,
    this.tooltip,
  });

  final String label;
  final double heightFactor;
  final Color color;
  final bool highlighted;
  final String? tooltip;

  @override
  Widget build(BuildContext context) {
    return Expanded(
      child: Padding(
        padding: const EdgeInsets.symmetric(horizontal: 2),
        child: Column(
          mainAxisAlignment: MainAxisAlignment.end,
          children: [
            if (tooltip != null)
              Container(
                margin: const EdgeInsets.only(bottom: 2),
                padding: const EdgeInsets.symmetric(
                  horizontal: 4,
                  vertical: 1,
                ),
                decoration: BoxDecoration(
                  color: AppColors.onSurface,
                  borderRadius: BorderRadius.circular(AppSpacing.radiusSm),
                ),
                child: Text(
                  tooltip!,
                  style: const TextStyle(
                    color: AppColors.surfaceContainerLowest,
                    fontSize: 9,
                    fontWeight: FontWeight.w700,
                  ),
                ),
              )
            else
              const SizedBox(height: 15),
            Expanded(
              child: Align(
                alignment: Alignment.bottomCenter,
                child: FractionallySizedBox(
                  heightFactor: heightFactor,
                  child: Container(
                    decoration: BoxDecoration(
                      color: color,
                      borderRadius: const BorderRadius.vertical(
                        top: Radius.circular(AppSpacing.radiusSm),
                      ),
                    ),
                  ),
                ),
              ),
            ),
            const SizedBox(height: AppSpacing.xs),
            Text(
              label,
              style: AppTypography.labelCaps.copyWith(
                fontSize: 10,
                color: highlighted
                    ? AppColors.onSurface
                    : AppColors.outlineVariant,
                fontWeight: highlighted ? FontWeight.w700 : FontWeight.w500,
              ),
            ),
          ],
        ),
      ),
    );
  }
}

class _DashboardCard extends StatelessWidget {
  const _DashboardCard({required this.child});

  final Widget child;

  @override
  Widget build(BuildContext context) {
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
        child: child,
      ),
    );
  }
}
