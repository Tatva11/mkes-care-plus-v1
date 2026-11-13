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

/// Admin Dashboard Card showing revenue collections for a selected date,
/// growth vs the preceding day, payment modes breakdown,
/// and an hourly time-slot chart spanning clinic operating hours.
class RevenueGrowthCard extends ConsumerWidget {
  const RevenueGrowthCard({super.key});

  static const _surfaceContainerHigh = Color(0xFFEAE7E7);

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    final selectedDate = ref.watch(selectedRevenueDateProvider);
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
          Wrap(
            alignment: WrapAlignment.spaceBetween,
            crossAxisAlignment: WrapCrossAlignment.center,
            spacing: AppSpacing.xs,
            runSpacing: 4,
            children: [
              Row(
                mainAxisSize: MainAxisSize.min,
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
                    ),
                  ),
                ],
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
          const SizedBox(height: AppSpacing.xs),
          _buildDateSelector(context, ref, selectedDate),
          const SizedBox(height: AppSpacing.sm),
          revenueAsync.when(
            loading: () => _buildLoadingState(),
            error: (err, _) => _buildErrorState(ref, err.toString()),
            data: (metrics) =>
                _buildDataContent(context, ref, metrics, currency, selectedDate),
          ),
        ],
      ),
    );
  }

  /// Compact, interactive date navigation bar with previous, next, calendar picker, and quick 'Today'.
  Widget _buildDateSelector(
    BuildContext context,
    WidgetRef ref,
    DateTime selectedDate,
  ) {
    final isToday = DateBoundaries.isToday(selectedDate);
    final formattedDate = isToday
        ? 'Today'
        : DateFormat('d MMM').format(selectedDate);

    return Container(
      padding: const EdgeInsets.symmetric(horizontal: 2, vertical: 2),
      decoration: BoxDecoration(
        color: AppColors.surfaceContainerLow,
        borderRadius: BorderRadius.circular(AppSpacing.radiusMd),
        border: Border.all(color: const Color(0xFFE5E2E1)),
      ),
      child: Row(
        mainAxisSize: MainAxisSize.min,
        children: [
          IconButton(
            icon: const Icon(Icons.chevron_left, size: 18),
            padding: EdgeInsets.zero,
            constraints: const BoxConstraints(minWidth: 26, minHeight: 26),
            tooltip: 'Previous day',
            onPressed: () {
              final prev = selectedDate.subtract(const Duration(days: 1));
              ref.read(selectedRevenueDateProvider.notifier).state =
                  DateBoundaries.startOfDay(prev);
            },
          ),
          InkWell(
            borderRadius: BorderRadius.circular(AppSpacing.radiusSm),
            onTap: () async {
              final picked = await showDatePicker(
                context: context,
                initialDate: selectedDate,
                firstDate: DateTime(2020),
                lastDate: DateTime.now(),
              );
              if (picked != null) {
                ref.read(selectedRevenueDateProvider.notifier).state =
                    DateBoundaries.startOfDay(picked);
              }
            },
            child: Padding(
              padding: const EdgeInsets.symmetric(horizontal: 6, vertical: 2),
              child: Row(
                mainAxisSize: MainAxisSize.min,
                children: [
                  const Icon(
                    Icons.calendar_today_outlined,
                    size: 13,
                    color: AppColors.primary,
                  ),
                  const SizedBox(width: 4),
                  Text(
                    formattedDate,
                    style: AppTypography.labelCaps.copyWith(
                      fontWeight: FontWeight.w600,
                      color: AppColors.onSurface,
                      fontSize: 11,
                    ),
                  ),
                ],
              ),
            ),
          ),
          IconButton(
            icon: const Icon(Icons.chevron_right, size: 18),
            padding: EdgeInsets.zero,
            constraints: const BoxConstraints(minWidth: 26, minHeight: 26),
            tooltip: 'Next day',
            onPressed: isToday
                ? null
                : () {
                    final next = selectedDate.add(const Duration(days: 1));
                    if (!next.isAfter(DateTime.now())) {
                      ref.read(selectedRevenueDateProvider.notifier).state =
                          DateBoundaries.startOfDay(next);
                    }
                  },
          ),
          if (!isToday) ...[
            const SizedBox(width: 2),
            InkWell(
              borderRadius: BorderRadius.circular(AppSpacing.radiusSm),
              onTap: () {
                ref.read(selectedRevenueDateProvider.notifier).state =
                    DateBoundaries.startOfDay(DateTime.now());
              },
              child: Padding(
                padding: const EdgeInsets.symmetric(horizontal: 6, vertical: 2),
                child: Text(
                  'Today',
                  style: TextStyle(
                    fontSize: 10,
                    fontWeight: FontWeight.bold,
                    color: AppColors.primary,
                  ),
                ),
              ),
            ),
          ],
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
              "Loading revenue data...",
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
    WidgetRef ref,
    TodayRevenueMetrics metrics,
    NumberFormat currency,
    DateTime selectedDate,
  ) {
    final isToday = DateBoundaries.isToday(selectedDate);
    final count = metrics.todayTransactionsCount;
    final totalRev = metrics.todayRevenue;

    final String transactionSummary;
    if (isToday) {
      transactionSummary = count > 0
          ? '$count collection transaction${count == 1 ? '' : 's'} today'
          : 'No collections recorded today';
    } else {
      final formattedDay = DateFormat('EEE, d MMM yyyy').format(selectedDate);
      transactionSummary = count > 0
          ? '$count collection transaction${count == 1 ? '' : 's'} on $formattedDay'
          : 'No collections recorded on $formattedDay';
    }

    return Column(
      crossAxisAlignment: CrossAxisAlignment.start,
      children: [
        Wrap(
          crossAxisAlignment: WrapCrossAlignment.center,
          spacing: AppSpacing.xs,
          runSpacing: 4,
          children: [
            Text(
              currency.format(totalRev),
              style: AppTypography.displayLg.copyWith(
                color: AppColors.onSurface,
              ),
              maxLines: 1,
              overflow: TextOverflow.ellipsis,
            ),
            _buildGrowthBadge(metrics.growthPercentage),
          ],
        ),
        const SizedBox(height: 2),
        Text(
          transactionSummary,
          style: AppTypography.bodySm.copyWith(
            color: AppColors.onSurfaceVariant,
            fontSize: 12,
          ),
        ),
        const SizedBox(height: AppSpacing.xs),

        // Collections breakdown by payment mode
        if (totalRev > 0) ...[
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

        // Hourly Time-Slot Chart (11 operating hour slots: 9 AM to 8 PM)
        _buildHourlySlotsChart(metrics.effectiveHourlySlots, totalRev, currency),
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

  /// Renders separate bars for individual hourly time slots with exact tooltips and baseline.
  Widget _buildHourlySlotsChart(
    List<HourlyRevenueSlot> slots,
    double totalRevenue,
    NumberFormat currency,
  ) {
    double maxSlotAmount = 0.0;
    for (final s in slots) {
      if (s.amount > maxSlotAmount) {
        maxSlotAmount = s.amount;
      }
    }

    return SizedBox(
      height: 196,
      child: Stack(
        clipBehavior: Clip.none,
        children: [
          // Y-Axis reference scale
          Positioned(
            left: 0,
            top: 28,
            bottom: 24,
            width: 44,
            child: Column(
              mainAxisAlignment: MainAxisAlignment.spaceBetween,
              children: [
                _YAxisLabel(maxSlotAmount > 0 ? _formatCompact(maxSlotAmount) : '10k'),
                _YAxisLabel(maxSlotAmount > 0 ? _formatCompact(maxSlotAmount * 2 / 3) : '5k'),
                _YAxisLabel(maxSlotAmount > 0 ? _formatCompact(maxSlotAmount / 3) : '2k'),
                const _YAxisLabel('0'),
              ],
            ),
          ),
          // Chart Plot Area
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
                  2,
                  AppSpacing.sm,
                  2,
                  AppSpacing.base,
                ),
                child: Row(
                  crossAxisAlignment: CrossAxisAlignment.end,
                  children: [
                    for (int i = 0; i < slots.length; i++)
                      _HourlyChartBar(
                        slot: slots[i],
                        currency: currency,
                        heightFactor: maxSlotAmount > 0 && slots[i].amount > 0
                            ? (slots[i].amount / maxSlotAmount).clamp(0.08, 1.0)
                            : 0.02,
                        isHighlighted: (slots[i].amount == maxSlotAmount &&
                            maxSlotAmount > 0),
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
        fontSize: 9,
      ),
      textAlign: TextAlign.right,
    );
  }
}

/// Represents an individual hourly slot bar on the chart with full tooltip support.
class _HourlyChartBar extends StatelessWidget {
  const _HourlyChartBar({
    required this.slot,
    required this.currency,
    required this.heightFactor,
    required this.isHighlighted,
  });

  final HourlyRevenueSlot slot;
  final NumberFormat currency;
  final double heightFactor;
  final bool isHighlighted;

  @override
  Widget build(BuildContext context) {
    final bool hasRevenue = slot.amount > 0;
    final String tooltipMessage = hasRevenue
        ? '${slot.fullLabel}\nRevenue: ${currency.format(slot.amount)}\n${slot.transactionCount} transaction${slot.transactionCount == 1 ? '' : 's'}'
        : '${slot.fullLabel}\nRevenue: ₹0 (No collections)';

    final Color barColor = isHighlighted
        ? AppColors.primaryContainer
        : (hasRevenue
            ? AppColors.primary.withValues(alpha: 0.75)
            : const Color(0xFFEAE7E7));

    return Expanded(
      child: Tooltip(
        message: tooltipMessage,
        waitDuration: const Duration(milliseconds: 250),
        preferBelow: false,
        padding: const EdgeInsets.symmetric(horizontal: 8, vertical: 6),
        decoration: BoxDecoration(
          color: const Color(0xFF1E293B),
          borderRadius: BorderRadius.circular(6),
          boxShadow: const [
            BoxShadow(
              color: Colors.black26,
              blurRadius: 4,
              offset: Offset(0, 2),
            ),
          ],
        ),
        textStyle: const TextStyle(
          color: Colors.white,
          fontSize: 11,
          fontWeight: FontWeight.w500,
          height: 1.3,
        ),
        child: Padding(
          padding: const EdgeInsets.symmetric(horizontal: 1.5),
          child: Column(
            mainAxisAlignment: MainAxisAlignment.end,
            children: [
              // Amount pill above bar for highest or active slots
              if (hasRevenue)
                Container(
                  margin: const EdgeInsets.only(bottom: 2),
                  padding: const EdgeInsets.symmetric(
                    horizontal: 3,
                    vertical: 1,
                  ),
                  decoration: BoxDecoration(
                    color: isHighlighted
                        ? AppColors.primaryContainer
                        : AppColors.onSurface.withValues(alpha: 0.85),
                    borderRadius: BorderRadius.circular(3),
                  ),
                  child: Text(
                    RevenueGrowthCard._formatCompact(slot.amount),
                    style: const TextStyle(
                      color: Colors.white,
                      fontSize: 8,
                      fontWeight: FontWeight.w700,
                    ),
                  ),
                )
              else
                const SizedBox(height: 14),
              // Bar Column
              Expanded(
                child: Align(
                  alignment: Alignment.bottomCenter,
                  child: FractionallySizedBox(
                    heightFactor: heightFactor,
                    child: Container(
                      decoration: BoxDecoration(
                        color: barColor,
                        borderRadius: const BorderRadius.vertical(
                          top: Radius.circular(3),
                        ),
                      ),
                    ),
                  ),
                ),
              ),
              const SizedBox(height: 4),
              // Slot Label (e.g. 9-10a, 10-11a)
              Text(
                slot.label,
                style: AppTypography.labelCaps.copyWith(
                  fontSize: 8.5,
                  color: isHighlighted
                      ? AppColors.onSurface
                      : AppColors.outlineVariant,
                  fontWeight: isHighlighted ? FontWeight.w700 : FontWeight.w500,
                ),
                maxLines: 1,
                overflow: TextOverflow.clip,
                textAlign: TextAlign.center,
              ),
            ],
          ),
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
