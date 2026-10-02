import '../utils/billing_profit_calculator.dart';
import 'billing_invoice_model.dart';

class BillingMetricsModel {
  final double totalSales;
  final double totalRevenue;
  final double totalOutstanding;
  final double estimatedProfit;
  final int totalInvoices;
  final int paidInvoicesCount;
  final int partiallyPaidInvoicesCount;

  const BillingMetricsModel({
    required this.totalSales,
    required this.totalRevenue,
    required this.totalOutstanding,
    required this.estimatedProfit,
    required this.totalInvoices,
    required this.paidInvoicesCount,
    required this.partiallyPaidInvoicesCount,
  });

  factory BillingMetricsModel.fromInvoices(List<BillingInvoiceModel> invoices) {
    double sales = 0.0;
    double revenue = 0.0;
    double outstanding = 0.0;
    int paidCount = 0;
    int partialCount = 0;

    for (final inv in invoices) {
      if (inv.isCancelled) continue;
      sales += inv.totalAmount;
      revenue += inv.amountPaid;
      outstanding += inv.remainingAmount;
      if (inv.isPaid) {
        paidCount++;
      } else if (inv.isPartiallyPaid) {
        partialCount++;
      }
    }

    final profit = BillingProfitCalculator.calculateEstimatedProfit(
      totalSales: sales,
      totalRevenue: revenue,
    );

    return BillingMetricsModel(
      totalSales: sales,
      totalRevenue: revenue,
      totalOutstanding: outstanding,
      estimatedProfit: profit,
      totalInvoices: invoices.length,
      paidInvoicesCount: paidCount,
      partiallyPaidInvoicesCount: partialCount,
    );
  }

  static const BillingMetricsModel zero = BillingMetricsModel(
    totalSales: 0.0,
    totalRevenue: 0.0,
    totalOutstanding: 0.0,
    estimatedProfit: 0.0,
    totalInvoices: 0,
    paidInvoicesCount: 0,
    partiallyPaidInvoicesCount: 0,
  );
}
