import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:intl/intl.dart';

import '../../../core/theme/app_colors.dart';
import '../../../core/theme/app_spacing.dart';
import '../../../core/theme/app_typography.dart';
import '../models/billing_reports_model.dart';
import '../providers/billing_provider.dart';

class BillingReportsScreen extends ConsumerStatefulWidget {
  const BillingReportsScreen({super.key});

  @override
  ConsumerState<BillingReportsScreen> createState() => _BillingReportsScreenState();
}

class _BillingReportsScreenState extends ConsumerState<BillingReportsScreen> {
  Future<void> _pickCustomDateRange(ReportsFilter filter) async {
    final now = DateTime.now();
    final picked = await showDateRangePicker(
      context: context,
      initialDateRange: filter.customStartDate != null && filter.customEndDate != null
          ? DateTimeRange(start: filter.customStartDate!, end: filter.customEndDate!)
          : DateTimeRange(
              start: now.subtract(const Duration(days: 30)),
              end: now,
            ),
      firstDate: DateTime(2020),
      lastDate: now.add(const Duration(days: 365)),
    );

    if (picked != null) {
      ref.read(reportsFilterProvider.notifier).state = filter.copyWith(
        datePreset: BillingDatePreset.custom,
        customStartDate: picked.start,
        customEndDate: picked.end,
      );
    }
  }

  @override
  Widget build(BuildContext context) {
    final filter = ref.watch(reportsFilterProvider);
    final reportsAsync = ref.watch(billingReportsDataProvider);
    final isDesktop = MediaQuery.sizeOf(context).width >= 900;

    return Scaffold(
      backgroundColor: AppColors.background,
      appBar: AppBar(
        title: const Text('Reports & Analytics'),
        actions: [
          IconButton(
            icon: const Icon(Icons.refresh),
            tooltip: 'Refresh Reports',
            onPressed: () => ref.invalidate(billingReportsDataProvider),
          ),
        ],
      ),
      body: RefreshIndicator(
        onRefresh: () async {
          ref.invalidate(billingReportsDataProvider);
        },
        child: SingleChildScrollView(
          physics: const AlwaysScrollableScrollPhysics(),
          padding: EdgeInsets.all(
            isDesktop ? AppSpacing.marginDesktop : AppSpacing.marginMobile,
          ),
          child: Column(
            crossAxisAlignment: CrossAxisAlignment.start,
            children: [
              // Header description
              Column(
                crossAxisAlignment: CrossAxisAlignment.start,
                children: [
                  Text(
                    'Financial & Operational Intelligence',
                    style: AppTypography.headlineMd.copyWith(
                      fontWeight: FontWeight.bold,
                    ),
                  ),
                  const SizedBox(height: 2),
                  Text(
                    'Comprehensive sales, revenue collection, department performance, and margin analytics',
                    style: AppTypography.bodySm.copyWith(
                      color: AppColors.onSurfaceVariant,
                    ),
                  ),
                ],
              ),
              const SizedBox(height: AppSpacing.lg),

              // Filter Toolbar
              _buildFilterToolbar(filter, isDesktop),
              const SizedBox(height: AppSpacing.lg),

              // Reports Data Content
              reportsAsync.when(
                loading: () => const Center(
                  child: Padding(
                    padding: EdgeInsets.all(64.0),
                    child: CircularProgressIndicator(),
                  ),
                ),
                error: (err, _) => Container(
                  padding: const EdgeInsets.all(AppSpacing.xl),
                  decoration: BoxDecoration(
                    color: AppColors.errorContainer,
                    borderRadius: BorderRadius.circular(AppSpacing.radiusMd),
                  ),
                  child: Center(
                    child: Column(
                      mainAxisSize: MainAxisSize.min,
                      children: [
                        const Icon(Icons.error_outline, color: AppColors.error, size: 36),
                        const SizedBox(height: AppSpacing.sm),
                        Text(
                          'Failed to load analytics: $err',
                          style: AppTypography.bodyMd.copyWith(
                            color: AppColors.onErrorContainer,
                          ),
                          textAlign: TextAlign.center,
                        ),
                        const SizedBox(height: AppSpacing.md),
                        FilledButton.icon(
                          onPressed: () => ref.invalidate(billingReportsDataProvider),
                          icon: const Icon(Icons.refresh, size: 16),
                          label: const Text('Retry'),
                        ),
                      ],
                    ),
                  ),
                ),
                data: (data) {
                  if (data.totalInvoices == 0) {
                    return Container(
                      padding: const EdgeInsets.all(AppSpacing.xl * 1.5),
                      decoration: BoxDecoration(
                        color: AppColors.surfaceContainerLowest,
                        borderRadius: BorderRadius.circular(AppSpacing.radiusMd),
                        border: Border.all(color: AppColors.outlineVariant),
                      ),
                      child: Center(
                        child: Column(
                          mainAxisSize: MainAxisSize.min,
                          children: [
                            const Icon(
                              Icons.analytics_outlined,
                              size: 56,
                              color: AppColors.outline,
                            ),
                            const SizedBox(height: AppSpacing.md),
                            Text(
                              'No billing data available for this period.',
                              style: AppTypography.headlineMd.copyWith(
                                fontSize: 18,
                                color: AppColors.onSurface,
                                fontWeight: FontWeight.w600,
                              ),
                            ),
                            const SizedBox(height: AppSpacing.xs),
                            Text(
                              'Try selecting a broader date range or changing department filters.',
                              style: AppTypography.bodySm.copyWith(
                                color: AppColors.onSurfaceVariant,
                              ),
                            ),
                          ],
                        ),
                      ),
                    );
                  }

                  return Column(
                    crossAxisAlignment: CrossAxisAlignment.start,
                    children: [
                      // 1. Executive KPI Summary Cards
                      _buildKpiGrid(data, isDesktop),
                      const SizedBox(height: AppSpacing.xl),

                      // 2. Department Breakdown & Payment Modes (2 Columns on Desktop)
                      if (isDesktop)
                        Row(
                          crossAxisAlignment: CrossAxisAlignment.start,
                          children: [
                            Expanded(flex: 5, child: _buildDepartmentComparisonCard(data)),
                            const SizedBox(width: AppSpacing.lg),
                            Expanded(flex: 4, child: _buildPaymentModesCard(data)),
                          ],
                        )
                      else ...[
                        _buildDepartmentComparisonCard(data),
                        const SizedBox(height: AppSpacing.lg),
                        _buildPaymentModesCard(data),
                      ],
                      const SizedBox(height: AppSpacing.xl),

                      // 3. Periodic Trend & Summary Table
                      _buildPeriodicSummaryTable(data, filter, isDesktop),
                      const SizedBox(height: AppSpacing.xl),

                      // 4. Top Performing Clinical Services
                      _buildTopServicesSection(data),
                    ],
                  );
                },
              ),
            ],
          ),
        ),
      ),
    );
  }

  Widget _buildFilterToolbar(ReportsFilter filter, bool isDesktop) {
    return Container(
      padding: const EdgeInsets.all(AppSpacing.md),
      decoration: BoxDecoration(
        color: AppColors.surfaceContainerLowest,
        borderRadius: BorderRadius.circular(AppSpacing.radiusMd),
        border: Border.all(color: AppColors.outlineVariant),
      ),
      child: Wrap(
        spacing: AppSpacing.md,
        runSpacing: AppSpacing.sm,
        crossAxisAlignment: WrapCrossAlignment.center,
        children: [
          // Department filter
          SegmentedButton<String>(
            segments: const [
              ButtonSegment(value: 'all', label: Text('All Depts')),
              ButtonSegment(value: 'eye', label: Text('Eye')),
              ButtonSegment(value: 'dental', label: Text('Dental')),
            ],
            selected: {filter.department},
            onSelectionChanged: (s) {
              ref.read(reportsFilterProvider.notifier).state =
                  filter.copyWith(department: s.first);
            },
          ),

          // Date range preset dropdown
          DropdownButton<BillingDatePreset>(
            value: filter.datePreset,
            underline: const SizedBox.shrink(),
            borderRadius: BorderRadius.circular(AppSpacing.radiusSm),
            items: const [
              DropdownMenuItem(value: BillingDatePreset.today, child: Text('Today')),
              DropdownMenuItem(value: BillingDatePreset.thisWeek, child: Text('This Week')),
              DropdownMenuItem(value: BillingDatePreset.thisMonth, child: Text('This Month')),
              DropdownMenuItem(value: BillingDatePreset.thisYear, child: Text('This Year')),
              DropdownMenuItem(value: BillingDatePreset.allTime, child: Text('All Time')),
              DropdownMenuItem(value: BillingDatePreset.custom, child: Text('Custom Date Range...')),
            ],
            onChanged: (val) {
              if (val != null) {
                if (val == BillingDatePreset.custom) {
                  _pickCustomDateRange(filter);
                } else {
                  ref.read(reportsFilterProvider.notifier).state = filter.copyWith(
                    datePreset: val,
                    clearCustomDates: true,
                  );
                }
              }
            },
          ),

          // Custom Date Range badge if active
          if (filter.datePreset == BillingDatePreset.custom &&
              filter.customStartDate != null &&
              filter.customEndDate != null)
            InputChip(
              avatar: const Icon(Icons.date_range, size: 16),
              label: Text(
                '${DateFormat('dd MMM').format(filter.customStartDate!)} - ${DateFormat('dd MMM yyyy').format(filter.customEndDate!)}',
                style: AppTypography.bodySm.copyWith(fontSize: 12),
              ),
              onPressed: () => _pickCustomDateRange(filter),
              onDeleted: () {
                ref.read(reportsFilterProvider.notifier).state = filter.copyWith(
                  datePreset: BillingDatePreset.thisMonth,
                  clearCustomDates: true,
                );
              },
            ),

          // Summary Aggregation Mode (Daily, Monthly, Yearly)
          Row(
            mainAxisSize: MainAxisSize.min,
            children: [
              Text(
                'Group by: ',
                style: AppTypography.labelCaps.copyWith(
                  color: AppColors.onSurfaceVariant,
                ),
              ),
              const SizedBox(width: 4),
              SegmentedButton<ReportAggregationMode>(
                segments: const [
                  ButtonSegment(
                    value: ReportAggregationMode.daily,
                    label: Text('Daily'),
                  ),
                  ButtonSegment(
                    value: ReportAggregationMode.monthly,
                    label: Text('Monthly'),
                  ),
                  ButtonSegment(
                    value: ReportAggregationMode.yearly,
                    label: Text('Yearly'),
                  ),
                ],
                selected: {filter.aggregationMode},
                onSelectionChanged: (s) {
                  ref.read(reportsFilterProvider.notifier).state =
                      filter.copyWith(aggregationMode: s.first);
                },
              ),
            ],
          ),
        ],
      ),
    );
  }

  Widget _buildKpiGrid(BillingReportsData data, bool isDesktop) {
    final kpis = [
      _ReportKpiCard(
        title: 'Gross Invoiced Sales',
        value: '₹${data.totalSales.toStringAsFixed(2)}',
        subtitle: '${data.totalInvoices} Invoices Generated',
        icon: Icons.receipt_long_outlined,
        color: AppColors.primary,
        bgColor: AppColors.primaryContainer.withValues(alpha: 0.15),
      ),
      _ReportKpiCard(
        title: 'Revenue Collected',
        value: '₹${data.totalRevenue.toStringAsFixed(2)}',
        subtitle: '${data.paidInvoicesCount} Fully Settled',
        icon: Icons.account_balance_wallet_outlined,
        color: Colors.green[700]!,
        bgColor: Colors.green.withValues(alpha: 0.12),
      ),
      _ReportKpiCard(
        title: 'Outstanding Receivables',
        value: '₹${data.totalOutstanding.toStringAsFixed(2)}',
        subtitle: '${data.partiallyPaidInvoicesCount} Partially Paid',
        icon: Icons.pending_actions_outlined,
        color: Colors.orange[800]!,
        bgColor: Colors.orange.withValues(alpha: 0.12),
      ),
      _ReportKpiCard(
        title: 'Estimated Gross Profit',
        value: '₹${data.estimatedProfit.toStringAsFixed(2)}',
        subtitle: '70% Estimated Margin',
        icon: Icons.auto_graph_outlined,
        color: Colors.teal[700]!,
        bgColor: Colors.teal.withValues(alpha: 0.12),
        tooltip:
            'Temporary 70% gross margin estimate. Real inventory & procedure cost tracking will connect once Sprint 6 is merged.',
      ),
      _ReportKpiCard(
        title: 'Average Order Value (AOV)',
        value: '₹${data.averageOrderValue.toStringAsFixed(2)}',
        subtitle: 'Average per Invoice',
        icon: Icons.pie_chart_outline,
        color: Colors.indigo[700]!,
        bgColor: Colors.indigo.withValues(alpha: 0.12),
      ),
      _ReportKpiCard(
        title: 'Collection Efficiency',
        value: '${data.collectionRate.toStringAsFixed(1)}%',
        subtitle: 'Collected / Invoiced',
        icon: Icons.task_alt_outlined,
        color: data.collectionRate >= 80 ? Colors.green[700]! : Colors.orange[800]!,
        bgColor: (data.collectionRate >= 80 ? Colors.green : Colors.orange).withValues(alpha: 0.12),
      ),
    ];

    if (isDesktop) {
      return Column(
        children: [
          Row(
            children: [
              Expanded(child: kpis[0]),
              const SizedBox(width: AppSpacing.md),
              Expanded(child: kpis[1]),
              const SizedBox(width: AppSpacing.md),
              Expanded(child: kpis[2]),
            ],
          ),
          const SizedBox(height: AppSpacing.md),
          Row(
            children: [
              Expanded(child: kpis[3]),
              const SizedBox(width: AppSpacing.md),
              Expanded(child: kpis[4]),
              const SizedBox(width: AppSpacing.md),
              Expanded(child: kpis[5]),
            ],
          ),
        ],
      );
    }

    // Tablet / Mobile: 2-column or stacked
    return Wrap(
      spacing: AppSpacing.md,
      runSpacing: AppSpacing.md,
      children: kpis.map((k) => SizedBox(width: 320, child: k)).toList(),
    );
  }

  Widget _buildDepartmentComparisonCard(BillingReportsData data) {
    final eye = data.eyeSummary;
    final dental = data.dentalSummary;

    return Container(
      padding: const EdgeInsets.all(AppSpacing.lg),
      decoration: BoxDecoration(
        color: AppColors.surfaceContainerLowest,
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
                'Department Comparison',
                style: AppTypography.headlineMd.copyWith(
                  fontSize: 16,
                  fontWeight: FontWeight.bold,
                ),
              ),
              const Icon(Icons.compare_arrows, size: 20, color: AppColors.primary),
            ],
          ),
          const SizedBox(height: AppSpacing.md),

          // Side-by-side department statistics
          Row(
            children: [
              // Eye Department
              Expanded(
                child: Container(
                  padding: const EdgeInsets.all(AppSpacing.md),
                  decoration: BoxDecoration(
                    color: AppColors.primaryContainer.withValues(alpha: 0.08),
                    borderRadius: BorderRadius.circular(AppSpacing.radiusSm),
                    border: Border.all(color: AppColors.primary.withValues(alpha: 0.2)),
                  ),
                  child: Column(
                    crossAxisAlignment: CrossAxisAlignment.start,
                    children: [
                      Row(
                        mainAxisAlignment: MainAxisAlignment.spaceBetween,
                        children: [
                          Text(
                            'EYE CLINIC',
                            style: AppTypography.labelCaps.copyWith(
                              color: AppColors.primary,
                              fontWeight: FontWeight.bold,
                            ),
                          ),
                          Text(
                            '${eye.sharePercentage.toStringAsFixed(1)}% Share',
                            style: AppTypography.bodySm.copyWith(
                              fontSize: 11,
                              fontWeight: FontWeight.bold,
                              color: AppColors.primary,
                            ),
                          ),
                        ],
                      ),
                      const SizedBox(height: 6),
                      Text(
                        '₹${eye.totalSales.toStringAsFixed(2)}',
                        style: AppTypography.headlineMd.copyWith(
                          fontSize: 18,
                          fontWeight: FontWeight.bold,
                        ),
                      ),
                      const SizedBox(height: 4),
                      Text(
                        'Collected: ₹${eye.revenueCollected.toStringAsFixed(2)}',
                        style: AppTypography.bodySm.copyWith(fontSize: 12),
                      ),
                      Text(
                        'Outstanding: ₹${eye.outstandingBalance.toStringAsFixed(2)}',
                        style: AppTypography.bodySm.copyWith(
                          fontSize: 12,
                          color: eye.outstandingBalance > 0 ? AppColors.error : Colors.green,
                        ),
                      ),
                      Text(
                        'Invoices: ${eye.invoiceCount}',
                        style: AppTypography.bodySm.copyWith(
                          fontSize: 11,
                          color: AppColors.onSurfaceVariant,
                        ),
                      ),
                    ],
                  ),
                ),
              ),
              const SizedBox(width: AppSpacing.md),

              // Dental Department
              Expanded(
                child: Container(
                  padding: const EdgeInsets.all(AppSpacing.md),
                  decoration: BoxDecoration(
                    color: AppColors.secondaryContainer.withValues(alpha: 0.08),
                    borderRadius: BorderRadius.circular(AppSpacing.radiusSm),
                    border: Border.all(color: AppColors.secondary.withValues(alpha: 0.2)),
                  ),
                  child: Column(
                    crossAxisAlignment: CrossAxisAlignment.start,
                    children: [
                      Row(
                        mainAxisAlignment: MainAxisAlignment.spaceBetween,
                        children: [
                          Text(
                            'DENTAL CLINIC',
                            style: AppTypography.labelCaps.copyWith(
                              color: AppColors.secondary,
                              fontWeight: FontWeight.bold,
                            ),
                          ),
                          Text(
                            '${dental.sharePercentage.toStringAsFixed(1)}% Share',
                            style: AppTypography.bodySm.copyWith(
                              fontSize: 11,
                              fontWeight: FontWeight.bold,
                              color: AppColors.secondary,
                            ),
                          ),
                        ],
                      ),
                      const SizedBox(height: 6),
                      Text(
                        '₹${dental.totalSales.toStringAsFixed(2)}',
                        style: AppTypography.headlineMd.copyWith(
                          fontSize: 18,
                          fontWeight: FontWeight.bold,
                        ),
                      ),
                      const SizedBox(height: 4),
                      Text(
                        'Collected: ₹${dental.revenueCollected.toStringAsFixed(2)}',
                        style: AppTypography.bodySm.copyWith(fontSize: 12),
                      ),
                      Text(
                        'Outstanding: ₹${dental.outstandingBalance.toStringAsFixed(2)}',
                        style: AppTypography.bodySm.copyWith(
                          fontSize: 12,
                          color: dental.outstandingBalance > 0 ? AppColors.error : Colors.green,
                        ),
                      ),
                      Text(
                        'Invoices: ${dental.invoiceCount}',
                        style: AppTypography.bodySm.copyWith(
                          fontSize: 11,
                          color: AppColors.onSurfaceVariant,
                        ),
                      ),
                    ],
                  ),
                ),
              ),
            ],
          ),
          const SizedBox(height: AppSpacing.md),

          // Visual proportional share bar
          ClipRRect(
            borderRadius: BorderRadius.circular(4),
            child: SizedBox(
              height: 10,
              child: Row(
                children: [
                  Expanded(
                    flex: eye.sharePercentage > 0 ? (eye.sharePercentage * 10).round() : 1,
                    child: Container(color: AppColors.primary),
                  ),
                  Expanded(
                    flex: dental.sharePercentage > 0 ? (dental.sharePercentage * 10).round() : 1,
                    child: Container(color: AppColors.secondary),
                  ),
                ],
              ),
            ),
          ),
        ],
      ),
    );
  }

  Widget _buildPaymentModesCard(BillingReportsData data) {
    return Container(
      padding: const EdgeInsets.all(AppSpacing.lg),
      decoration: BoxDecoration(
        color: AppColors.surfaceContainerLowest,
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
                'Payment Channels',
                style: AppTypography.headlineMd.copyWith(
                  fontSize: 16,
                  fontWeight: FontWeight.bold,
                ),
              ),
              const Icon(Icons.payments_outlined, size: 20, color: AppColors.primary),
            ],
          ),
          const SizedBox(height: AppSpacing.md),
          for (final mode in data.paymentModes) ...[
            Row(
              mainAxisAlignment: MainAxisAlignment.spaceBetween,
              children: [
                Row(
                  children: [
                    Icon(
                      _modeIcon(mode.mode),
                      size: 16,
                      color: AppColors.primary,
                    ),
                    const SizedBox(width: 8),
                    Text(
                      _formatModeName(mode.mode),
                      style: AppTypography.bodySm.copyWith(
                        fontWeight: FontWeight.w600,
                      ),
                    ),
                  ],
                ),
                Column(
                  crossAxisAlignment: CrossAxisAlignment.end,
                  children: [
                    Text(
                      '₹${mode.totalAmount.toStringAsFixed(2)}',
                      style: AppTypography.bodySm.copyWith(
                        fontWeight: FontWeight.bold,
                      ),
                    ),
                    Text(
                      '${mode.percentage.toStringAsFixed(1)}% (${mode.transactionCount} txns)',
                      style: AppTypography.bodySm.copyWith(
                        fontSize: 10,
                        color: AppColors.onSurfaceVariant,
                      ),
                    ),
                  ],
                ),
              ],
            ),
            const SizedBox(height: 6),
            ClipRRect(
              borderRadius: BorderRadius.circular(2),
              child: LinearProgressIndicator(
                value: (mode.percentage / 100).clamp(0.0, 1.0),
                minHeight: 4,
                backgroundColor: AppColors.surfaceContainerLow,
                color: _modeColor(mode.mode),
              ),
            ),
            const SizedBox(height: AppSpacing.sm),
          ],
        ],
      ),
    );
  }

  Widget _buildPeriodicSummaryTable(
    BillingReportsData data,
    ReportsFilter filter,
    bool isDesktop,
  ) {
    return Container(
      decoration: BoxDecoration(
        color: AppColors.surfaceContainerLowest,
        borderRadius: BorderRadius.circular(AppSpacing.radiusMd),
        border: Border.all(color: AppColors.outlineVariant),
      ),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Padding(
            padding: const EdgeInsets.all(AppSpacing.md),
            child: Row(
              mainAxisAlignment: MainAxisAlignment.spaceBetween,
              children: [
                Text(
                  '${_aggregationTitle(filter.aggregationMode)} Breakdown',
                  style: AppTypography.headlineMd.copyWith(
                    fontSize: 16,
                    fontWeight: FontWeight.bold,
                  ),
                ),
                Text(
                  '${data.periodicBuckets.length} Periods Recorded',
                  style: AppTypography.bodySm.copyWith(
                    color: AppColors.onSurfaceVariant,
                  ),
                ),
              ],
            ),
          ),
          const Divider(height: 1),
          Table(
            columnWidths: const {
              0: FlexColumnWidth(2), // Period
              1: FlexColumnWidth(1), // Invoices
              2: FlexColumnWidth(1.5), // Total Sales
              3: FlexColumnWidth(1.5), // Collected
              4: FlexColumnWidth(1.5), // Outstanding
              5: FlexColumnWidth(1.5), // Est Profit
              6: FlexColumnWidth(1.2), // Rate %
            },
            children: [
              TableRow(
                decoration: const BoxDecoration(
                  color: AppColors.surfaceContainerLow,
                ),
                children: [
                  _headerCell('Period'),
                  _headerCell('Invoices'),
                  _headerCell('Invoiced (₹)'),
                  _headerCell('Collected (₹)'),
                  _headerCell('Outstanding (₹)'),
                  _headerCell('Est. Profit (₹)'),
                  _headerCell('Collection %'),
                ],
              ),
              for (final b in data.periodicBuckets)
                TableRow(
                  decoration: const BoxDecoration(
                    border: Border(bottom: BorderSide(color: AppColors.outlineVariant, width: 0.5)),
                  ),
                  children: [
                    _bodyCell(Text(b.periodLabel, style: AppTypography.bodySm.copyWith(fontWeight: FontWeight.w600))),
                    _bodyCell(Text('${b.invoiceCount}', style: AppTypography.bodySm)),
                    _bodyCell(Text('₹${b.totalSales.toStringAsFixed(2)}', style: AppTypography.bodySm.copyWith(fontWeight: FontWeight.w600))),
                    _bodyCell(Text('₹${b.revenueCollected.toStringAsFixed(2)}', style: AppTypography.bodySm.copyWith(color: Colors.green[800], fontWeight: FontWeight.w600))),
                    _bodyCell(Text('₹${b.outstandingBalance.toStringAsFixed(2)}', style: AppTypography.bodySm.copyWith(color: b.outstandingBalance > 0 ? AppColors.error : Colors.green[800]))),
                    _bodyCell(Text('₹${b.estimatedProfit.toStringAsFixed(2)}', style: AppTypography.bodySm.copyWith(color: Colors.teal[800], fontWeight: FontWeight.w600))),
                    _bodyCell(Text('${b.collectionRate.toStringAsFixed(1)}%', style: AppTypography.bodySm.copyWith(fontWeight: FontWeight.bold))),
                  ],
                ),
            ],
          ),
        ],
      ),
    );
  }

  Widget _buildTopServicesSection(BillingReportsData data) {
    if (data.topServices.isEmpty) return const SizedBox.shrink();

    return Container(
      padding: const EdgeInsets.all(AppSpacing.lg),
      decoration: BoxDecoration(
        color: AppColors.surfaceContainerLowest,
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
                'Top Performing Services & Procedures',
                style: AppTypography.headlineMd.copyWith(
                  fontSize: 16,
                  fontWeight: FontWeight.bold,
                ),
              ),
              const Icon(Icons.star_outline, size: 20, color: AppColors.primary),
            ],
          ),
          const SizedBox(height: AppSpacing.md),
          ListView.separated(
            shrinkWrap: true,
            physics: const NeverScrollableScrollPhysics(),
            itemCount: data.topServices.length.clamp(0, 10),
            separatorBuilder: (_, __) => const Divider(height: 1),
            itemBuilder: (context, index) {
              final s = data.topServices[index];
              return ListTile(
                dense: true,
                contentPadding: EdgeInsets.zero,
                leading: CircleAvatar(
                  radius: 14,
                  backgroundColor: s.department == 'eye'
                      ? AppColors.primaryContainer.withValues(alpha: 0.2)
                      : AppColors.secondaryContainer.withValues(alpha: 0.2),
                  child: Text(
                    '${index + 1}',
                    style: TextStyle(
                      fontSize: 11,
                      fontWeight: FontWeight.bold,
                      color: s.department == 'eye' ? AppColors.primary : AppColors.secondary,
                    ),
                  ),
                ),
                title: Text(
                  s.serviceName,
                  style: AppTypography.bodySm.copyWith(fontWeight: FontWeight.w600),
                ),
                subtitle: Text(
                  '${s.department.toUpperCase()} • ${s.quantity} Procedures Performed',
                  style: AppTypography.bodySm.copyWith(fontSize: 11, color: AppColors.onSurfaceVariant),
                ),
                trailing: Text(
                  '₹${s.totalRevenue.toStringAsFixed(2)}',
                  style: AppTypography.bodySm.copyWith(
                    fontWeight: FontWeight.bold,
                    color: AppColors.onSurface,
                  ),
                ),
              );
            },
          ),
        ],
      ),
    );
  }

  Widget _headerCell(String title) {
    return Padding(
      padding: const EdgeInsets.symmetric(horizontal: 10, vertical: 8),
      child: Text(
        title,
        style: AppTypography.labelCaps.copyWith(
          fontSize: 10,
          fontWeight: FontWeight.bold,
        ),
      ),
    );
  }

  Widget _bodyCell(Widget child) {
    return Padding(
      padding: const EdgeInsets.symmetric(horizontal: 10, vertical: 10),
      child: child,
    );
  }

  String _aggregationTitle(ReportAggregationMode mode) {
    switch (mode) {
      case ReportAggregationMode.daily:
        return 'Daily Financial';
      case ReportAggregationMode.monthly:
        return 'Monthly Financial';
      case ReportAggregationMode.yearly:
        return 'Yearly Financial';
    }
  }

  String _formatModeName(String mode) {
    switch (mode) {
      case 'cash':
        return 'Cash';
      case 'upi':
        return 'UPI / QR Code';
      case 'bank_transfer':
        return 'Bank Transfer';
      case 'other':
        return 'Other Channels';
      default:
        return mode.toUpperCase();
    }
  }

  IconData _modeIcon(String mode) {
    switch (mode) {
      case 'cash':
        return Icons.payments_outlined;
      case 'upi':
        return Icons.qr_code_2_outlined;
      case 'bank_transfer':
        return Icons.account_balance_outlined;
      default:
        return Icons.credit_card_outlined;
    }
  }

  Color _modeColor(String mode) {
    switch (mode) {
      case 'cash':
        return Colors.green;
      case 'upi':
        return Colors.purple;
      case 'bank_transfer':
        return Colors.blue;
      default:
        return Colors.orange;
    }
  }
}

class _ReportKpiCard extends StatelessWidget {
  final String title;
  final String value;
  final String subtitle;
  final IconData icon;
  final Color color;
  final Color bgColor;
  final String? tooltip;

  const _ReportKpiCard({
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
      ),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Row(
            mainAxisAlignment: MainAxisAlignment.spaceBetween,
            children: [
              Row(
                children: [
                  Text(
                    title,
                    style: AppTypography.labelCaps.copyWith(
                      color: AppColors.onSurfaceVariant,
                      fontWeight: FontWeight.w600,
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
          Text(
            value,
            style: AppTypography.headlineMd.copyWith(
              fontWeight: FontWeight.bold,
              fontSize: 20,
              color: AppColors.onSurface,
            ),
          ),
          const SizedBox(height: 2),
          Text(
            subtitle,
            style: AppTypography.bodySm.copyWith(
              color: AppColors.onSurfaceVariant,
              fontSize: 11,
            ),
          ),
        ],
      ),
    );
  }
}
