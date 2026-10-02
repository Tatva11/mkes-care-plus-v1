/// Isolated profit and financial metrics calculation utility for Sprint 7 Phase 7.3.
///
/// NOTE FOR FUTURE SPRINT INTEGRATION:
/// Real cost data will be connected once Sprint 6 (Inventory & Vendor module)
/// is merged into main. This isolated utility encapsulates the temporary
/// estimated margin logic so it can be swapped with real inventory COGS / material
/// cost calculations without impacting any UI or repository layers.
class BillingProfitCalculator {
  /// Dummy estimated gross margin ratio (70% gross margin placeholder).
  static const double dummyEstimatedMarginPercent = 70.0;

  /// Calculates estimated profit from total sales and revenue.
  ///
  /// Currently applies the isolated placeholder margin (70%) on total sales.
  static double calculateEstimatedProfit({
    required double totalSales,
    required double totalRevenue,
  }) {
    if (totalSales <= 0) return 0.0;
    return totalSales * (dummyEstimatedMarginPercent / 100.0);
  }

  /// Calculates estimated cost placeholder (30% of sales).
  static double calculateEstimatedCost({
    required double totalSales,
  }) {
    if (totalSales <= 0) return 0.0;
    return totalSales * ((100.0 - dummyEstimatedMarginPercent) / 100.0);
  }
}
