import 'package:intl/intl.dart';

import '../utils/billing_profit_calculator.dart';
import 'billing_invoice_model.dart';

enum ReportAggregationMode {
  daily,
  monthly,
  yearly,
}

class DepartmentRevenueSummary {
  final String department;
  final int invoiceCount;
  final double totalSales;
  final double revenueCollected;
  final double outstandingBalance;
  final double estimatedProfit;
  final double sharePercentage;

  const DepartmentRevenueSummary({
    required this.department,
    required this.invoiceCount,
    required this.totalSales,
    required this.revenueCollected,
    required this.outstandingBalance,
    required this.estimatedProfit,
    required this.sharePercentage,
  });
}

class PaymentModeSummary {
  final String mode;
  final double totalAmount;
  final int transactionCount;
  final double percentage;

  const PaymentModeSummary({
    required this.mode,
    required this.totalAmount,
    required this.transactionCount,
    required this.percentage,
  });
}

class PeriodRevenueBucket {
  final String periodLabel;
  final DateTime date;
  final int invoiceCount;
  final double totalSales;
  final double revenueCollected;
  final double outstandingBalance;
  final double estimatedProfit;
  final double collectionRate;

  const PeriodRevenueBucket({
    required this.periodLabel,
    required this.date,
    required this.invoiceCount,
    required this.totalSales,
    required this.revenueCollected,
    required this.outstandingBalance,
    required this.estimatedProfit,
    required this.collectionRate,
  });
}

class ServicePerformanceSummary {
  final String serviceName;
  final String department;
  final int quantity;
  final double totalRevenue;

  const ServicePerformanceSummary({
    required this.serviceName,
    required this.department,
    required this.quantity,
    required this.totalRevenue,
  });
}

class BillingReportsData {
  final double totalSales;
  final double totalRevenue;
  final double totalOutstanding;
  final double estimatedProfit;
  final int totalInvoices;
  final int paidInvoicesCount;
  final int partiallyPaidInvoicesCount;
  final double averageOrderValue;
  final double collectionRate;

  final DepartmentRevenueSummary eyeSummary;
  final DepartmentRevenueSummary dentalSummary;
  final List<PaymentModeSummary> paymentModes;
  final List<PeriodRevenueBucket> periodicBuckets;
  final List<ServicePerformanceSummary> topServices;

  const BillingReportsData({
    required this.totalSales,
    required this.totalRevenue,
    required this.totalOutstanding,
    required this.estimatedProfit,
    required this.totalInvoices,
    required this.paidInvoicesCount,
    required this.partiallyPaidInvoicesCount,
    required this.averageOrderValue,
    required this.collectionRate,
    required this.eyeSummary,
    required this.dentalSummary,
    required this.paymentModes,
    required this.periodicBuckets,
    required this.topServices,
  });

  factory BillingReportsData.fromInvoices({
    required List<BillingInvoiceModel> invoices,
    ReportAggregationMode aggregationMode = ReportAggregationMode.daily,
  }) {
    double totalSales = 0.0;
    double totalRevenue = 0.0;
    double totalOutstanding = 0.0;
    int paidCount = 0;
    int partialCount = 0;

    // Department aggregates
    int eyeCount = 0;
    double eyeSales = 0.0;
    double eyeRevenue = 0.0;
    double eyeOutstanding = 0.0;

    int dentalCount = 0;
    double dentalSales = 0.0;
    double dentalRevenue = 0.0;
    double dentalOutstanding = 0.0;

    // Payment modes map (amount & count)
    final Map<String, double> modeAmounts = {
      'cash': 0.0,
      'upi': 0.0,
      'bank_transfer': 0.0,
      'other': 0.0,
    };
    final Map<String, int> modeCounts = {
      'cash': 0,
      'upi': 0,
      'bank_transfer': 0,
      'other': 0,
    };

    // Services map
    final Map<String, _ServiceAccumulator> servicesMap = {};

    // Periodic buckets map (key -> bucket accumulator)
    final Map<String, _BucketAccumulator> bucketMap = {};

    for (final inv in invoices) {
      if (inv.isCancelled) continue;

      totalSales += inv.totalAmount;
      totalRevenue += inv.amountPaid;
      totalOutstanding += inv.remainingAmount;

      if (inv.isPaid) {
        paidCount++;
      } else if (inv.isPartiallyPaid) {
        partialCount++;
      }

      // Department breakdown
      if (inv.department == 'eye') {
        eyeCount++;
        eyeSales += inv.totalAmount;
        eyeRevenue += inv.amountPaid;
        eyeOutstanding += inv.remainingAmount;
      } else if (inv.department == 'dental') {
        dentalCount++;
        dentalSales += inv.totalAmount;
        dentalRevenue += inv.amountPaid;
        dentalOutstanding += inv.remainingAmount;
      }

      // Payments breakdown
      for (final p in inv.payments) {
        final normMode = p.paymentMode.toLowerCase();
        final key = modeAmounts.containsKey(normMode) ? normMode : 'other';
        modeAmounts[key] = (modeAmounts[key] ?? 0.0) + p.amount;
        modeCounts[key] = (modeCounts[key] ?? 0) + 1;
      }

      // Items breakdown
      for (final item in inv.items) {
        final key = '${inv.department}_${item.serviceName}';
        if (!servicesMap.containsKey(key)) {
          servicesMap[key] = _ServiceAccumulator(
            serviceName: item.serviceName,
            department: inv.department,
          );
        }
        servicesMap[key]!.quantity += item.quantity;
        servicesMap[key]!.totalRevenue += item.totalAmount;
      }

      // Bucket key generation based on aggregation mode
      String bucketKey;
      String bucketLabel;
      DateTime bucketDate;

      if (aggregationMode == ReportAggregationMode.yearly) {
        bucketKey = '${inv.createdAt.year}';
        bucketLabel = '${inv.createdAt.year}';
        bucketDate = DateTime(inv.createdAt.year);
      } else if (aggregationMode == ReportAggregationMode.monthly) {
        bucketKey = '${inv.createdAt.year}-${inv.createdAt.month.toString().padLeft(2, '0')}';
        bucketLabel = DateFormat('MMM yyyy').format(inv.createdAt);
        bucketDate = DateTime(inv.createdAt.year, inv.createdAt.month);
      } else {
        bucketKey = DateFormat('yyyy-MM-dd').format(inv.createdAt);
        bucketLabel = DateFormat('dd MMM yyyy').format(inv.createdAt);
        bucketDate = DateTime(inv.createdAt.year, inv.createdAt.month, inv.createdAt.day);
      }

      if (!bucketMap.containsKey(bucketKey)) {
        bucketMap[bucketKey] = _BucketAccumulator(
          key: bucketKey,
          label: bucketLabel,
          date: bucketDate,
        );
      }
      final b = bucketMap[bucketKey]!;
      b.invoiceCount++;
      b.totalSales += inv.totalAmount;
      b.revenueCollected += inv.amountPaid;
      b.outstandingBalance += inv.remainingAmount;
    }

    final estimatedProfit = BillingProfitCalculator.calculateEstimatedProfit(
      totalSales: totalSales,
      totalRevenue: totalRevenue,
    );

    final aov = invoices.isNotEmpty ? (totalSales / invoices.length) : 0.0;
    final collectionRate = totalSales > 0 ? ((totalRevenue / totalSales) * 100).clamp(0.0, 100.0) : 0.0;

    // Build Department Summaries
    final eyeProfit = BillingProfitCalculator.calculateEstimatedProfit(
      totalSales: eyeSales,
      totalRevenue: eyeRevenue,
    );
    final dentalProfit = BillingProfitCalculator.calculateEstimatedProfit(
      totalSales: dentalSales,
      totalRevenue: dentalRevenue,
    );

    final eyeSummary = DepartmentRevenueSummary(
      department: 'eye',
      invoiceCount: eyeCount,
      totalSales: eyeSales,
      revenueCollected: eyeRevenue,
      outstandingBalance: eyeOutstanding,
      estimatedProfit: eyeProfit,
      sharePercentage: totalSales > 0 ? (eyeSales / totalSales * 100) : 0.0,
    );

    final dentalSummary = DepartmentRevenueSummary(
      department: 'dental',
      invoiceCount: dentalCount,
      totalSales: dentalSales,
      revenueCollected: dentalRevenue,
      outstandingBalance: dentalOutstanding,
      estimatedProfit: dentalProfit,
      sharePercentage: totalSales > 0 ? (dentalSales / totalSales * 100) : 0.0,
    );

    // Build Payment Mode Summaries
    final double allPaymentsSum = modeAmounts.values.fold(0.0, (s, v) => s + v);
    final paymentModesList = modeAmounts.entries.map((e) {
      return PaymentModeSummary(
        mode: e.key,
        totalAmount: e.value,
        transactionCount: modeCounts[e.key] ?? 0,
        percentage: allPaymentsSum > 0 ? (e.value / allPaymentsSum * 100) : 0.0,
      );
    }).toList();

    // Sort buckets chronologically (most recent first)
    final sortedBuckets = bucketMap.values.toList()
      ..sort((a, b) => b.date.compareTo(a.date));

    final periodicBucketsList = sortedBuckets.map((b) {
      final profit = BillingProfitCalculator.calculateEstimatedProfit(
        totalSales: b.totalSales,
        totalRevenue: b.revenueCollected,
      );
      final rate = b.totalSales > 0 ? ((b.revenueCollected / b.totalSales) * 100).clamp(0.0, 100.0) : 0.0;
      return PeriodRevenueBucket(
        periodLabel: b.label,
        date: b.date,
        invoiceCount: b.invoiceCount,
        totalSales: b.totalSales,
        revenueCollected: b.revenueCollected,
        outstandingBalance: b.outstandingBalance,
        estimatedProfit: profit,
        collectionRate: rate,
      );
    }).toList();

    // Sort top services by total revenue descending
    final topServicesList = servicesMap.values.map((s) {
      return ServicePerformanceSummary(
        serviceName: s.serviceName,
        department: s.department,
        quantity: s.quantity,
        totalRevenue: s.totalRevenue,
      );
    }).toList()
      ..sort((a, b) => b.totalRevenue.compareTo(a.totalRevenue));

    return BillingReportsData(
      totalSales: totalSales,
      totalRevenue: totalRevenue,
      totalOutstanding: totalOutstanding,
      estimatedProfit: estimatedProfit,
      totalInvoices: invoices.length,
      paidInvoicesCount: paidCount,
      partiallyPaidInvoicesCount: partialCount,
      averageOrderValue: aov,
      collectionRate: collectionRate,
      eyeSummary: eyeSummary,
      dentalSummary: dentalSummary,
      paymentModes: paymentModesList,
      periodicBuckets: periodicBucketsList,
      topServices: topServicesList,
    );
  }

  static const BillingReportsData empty = BillingReportsData(
    totalSales: 0.0,
    totalRevenue: 0.0,
    totalOutstanding: 0.0,
    estimatedProfit: 0.0,
    totalInvoices: 0,
    paidInvoicesCount: 0,
    partiallyPaidInvoicesCount: 0,
    averageOrderValue: 0.0,
    collectionRate: 0.0,
    eyeSummary: DepartmentRevenueSummary(
      department: 'eye',
      invoiceCount: 0,
      totalSales: 0.0,
      revenueCollected: 0.0,
      outstandingBalance: 0.0,
      estimatedProfit: 0.0,
      sharePercentage: 0.0,
    ),
    dentalSummary: DepartmentRevenueSummary(
      department: 'dental',
      invoiceCount: 0,
      totalSales: 0.0,
      revenueCollected: 0.0,
      outstandingBalance: 0.0,
      estimatedProfit: 0.0,
      sharePercentage: 0.0,
    ),
    paymentModes: [],
    periodicBuckets: [],
    topServices: [],
  );
}

class _ServiceAccumulator {
  final String serviceName;
  final String department;
  int quantity = 0;
  double totalRevenue = 0.0;

  _ServiceAccumulator({
    required this.serviceName,
    required this.department,
  });
}

class _BucketAccumulator {
  final String key;
  final String label;
  final DateTime date;
  int invoiceCount = 0;
  double totalSales = 0.0;
  double revenueCollected = 0.0;
  double outstandingBalance = 0.0;

  _BucketAccumulator({
    required this.key,
    required this.label,
    required this.date,
  });
}
