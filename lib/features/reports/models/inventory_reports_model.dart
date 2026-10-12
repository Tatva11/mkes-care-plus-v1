import 'package:flutter/material.dart';

/// Represents stock valuation and item count for an inventory category.
class CategoryValuationStat {
  final String category;
  final int itemCount;
  final double totalUnits;
  final double totalValuation;
  final double percentage;

  const CategoryValuationStat({
    required this.category,
    required this.itemCount,
    required this.totalUnits,
    required this.totalValuation,
    required this.percentage,
  });
}

/// Represents a low-stock or out-of-stock item requiring reordering.
class LowStockItemStat {
  final String itemId;
  final String itemName;
  final String? sku;
  final String unit;
  final String location; // 'Central Store', 'Eye Clinic', 'Dental Clinic'
  final double currentStock;
  final double minimumStock;
  final double shortfall;
  final String? vendorName;
  final String? vendorPhone;
  final double? lastPrice;
  final bool isStockOut;

  const LowStockItemStat({
    required this.itemId,
    required this.itemName,
    this.sku,
    required this.unit,
    required this.location,
    required this.currentStock,
    required this.minimumStock,
    required this.shortfall,
    this.vendorName,
    this.vendorPhone,
    this.lastPrice,
    required this.isStockOut,
  });
}

/// Domain model for batch-level expiry tracking.
class BatchExpiryStat {
  final String batchId;
  final String batchNumber;
  final String itemId;
  final String itemName;
  final String category;
  final DateTime? expiryDate;
  final int? daysRemaining; // negative if already expired
  final double remainingQuantity;
  final double unitPrice;
  final double totalAmount;
  final String urgencyStatus; // 'expired', '30days', '60days', '90days', 'safe'

  const BatchExpiryStat({
    required this.batchId,
    required this.batchNumber,
    required this.itemId,
    required this.itemName,
    required this.category,
    this.expiryDate,
    this.daysRemaining,
    required this.remainingQuantity,
    required this.unitPrice,
    required this.totalAmount,
    required this.urgencyStatus,
  });

  bool get isExpired =>
      (daysRemaining != null && daysRemaining! < 0) ||
      urgencyStatus == 'expired';
}

/// Periodic data point for stock movement trends.
class StockMovementTrendPoint {
  final String label;
  final DateTime date;
  final double stockInUnits;
  final double stockOutUnits;
  final double stockInValue;
  final double stockOutValue;

  const StockMovementTrendPoint({
    required this.label,
    required this.date,
    required this.stockInUnits,
    required this.stockOutUnits,
    required this.stockInValue,
    required this.stockOutValue,
  });
}

/// Breakdown of stock movements by declared operational reason.
class MovementReasonStat {
  final String reason;
  final int transactionCount;
  final double totalUnits;
  final double totalValue;
  final bool isStockIn;

  const MovementReasonStat({
    required this.reason,
    required this.transactionCount,
    required this.totalUnits,
    required this.totalValue,
    required this.isStockIn,
  });
}

/// Most frequently or highly consumed items in the period.
class FastMovingItemStat {
  final String itemId;
  final String itemName;
  final String category;
  final double totalConsumedUnits;
  final double totalConsumedValue;
  final int transactionCount;

  const FastMovingItemStat({
    required this.itemId,
    required this.itemName,
    required this.category,
    required this.totalConsumedUnits,
    required this.totalConsumedValue,
    required this.transactionCount,
  });
}

/// Domain model for an immutable stock transaction audit log.
class InventoryAuditEntry {
  final String id;
  final DateTime date;
  final String itemName;
  final String transactionType; // 'stock_in' or 'stock_out'
  final double quantity;
  final double? stockBefore;
  final double? stockAfter;
  final String? reason;
  final String? performedByName;
  final String? recipientInfo;
  final String? remarks;
  final double? totalAmount;

  const InventoryAuditEntry({
    required this.id,
    required this.date,
    required this.itemName,
    required this.transactionType,
    required this.quantity,
    this.stockBefore,
    this.stockAfter,
    this.reason,
    this.performedByName,
    this.recipientInfo,
    this.remarks,
    this.totalAmount,
  });
}

/// Aggregated root data object for Sprint 8 Phase 8.2 Inventory Analytics.
@immutable
class InventoryReportsData {
  // 1. Overview & Valuation
  final int totalCatalogItems;
  final int activeItemsCount;
  final double centralValuation;
  final double eyeValuation;
  final double dentalValuation;
  final double totalValuation;
  final double centralUnits;
  final double eyeUnits;
  final double dentalUnits;
  final double totalUnits;
  final List<CategoryValuationStat> categoryValuations;

  // 2. Low-Stock & Reorder Analytics
  final int centralLowStockCount;
  final int departmentLowStockCount;
  final int stockOutCount;
  final List<LowStockItemStat> lowStockItems;

  // 3. Expiry Analytics
  final int expiredBatchesCount;
  final double expiredValueLost;
  final int expiring30DaysCount;
  final double expiring30DaysValue;
  final int expiring60DaysCount;
  final double expiring60DaysValue;
  final int expiring90DaysCount;
  final double expiring90DaysValue;
  final double totalAtRiskValue;
  final List<BatchExpiryStat> batchExpiryDetails;

  // 4. Stock Movement & Ledger
  final double totalStockInUnits;
  final double totalStockInValue;
  final double totalStockOutUnits;
  final double totalStockOutValue;
  final List<StockMovementTrendPoint> movementTrends;
  final List<MovementReasonStat> movementReasons;
  final List<FastMovingItemStat> fastMovingItems;
  final List<InventoryAuditEntry> auditLedger;

  const InventoryReportsData({
    required this.totalCatalogItems,
    required this.activeItemsCount,
    required this.centralValuation,
    required this.eyeValuation,
    required this.dentalValuation,
    required this.totalValuation,
    required this.centralUnits,
    required this.eyeUnits,
    required this.dentalUnits,
    required this.totalUnits,
    required this.categoryValuations,
    required this.centralLowStockCount,
    required this.departmentLowStockCount,
    required this.stockOutCount,
    required this.lowStockItems,
    required this.expiredBatchesCount,
    required this.expiredValueLost,
    required this.expiring30DaysCount,
    required this.expiring30DaysValue,
    required this.expiring60DaysCount,
    required this.expiring60DaysValue,
    required this.expiring90DaysCount,
    required this.expiring90DaysValue,
    required this.totalAtRiskValue,
    required this.batchExpiryDetails,
    required this.totalStockInUnits,
    required this.totalStockInValue,
    required this.totalStockOutUnits,
    required this.totalStockOutValue,
    required this.movementTrends,
    required this.movementReasons,
    required this.fastMovingItems,
    required this.auditLedger,
  });

  /// Central allocation share percentage.
  double get centralSharePercentage =>
      totalUnits > 0 ? (centralUnits / totalUnits * 100) : 0.0;

  /// Eye allocation share percentage.
  double get eyeSharePercentage =>
      totalUnits > 0 ? (eyeUnits / totalUnits * 100) : 0.0;

  /// Dental allocation share percentage.
  double get dentalSharePercentage =>
      totalUnits > 0 ? (dentalUnits / totalUnits * 100) : 0.0;

  /// Total alerts needing operational attention.
  int get totalUrgentAlerts =>
      centralLowStockCount +
      departmentLowStockCount +
      stockOutCount +
      expiredBatchesCount +
      expiring30DaysCount;

  static const InventoryReportsData empty = InventoryReportsData(
    totalCatalogItems: 0,
    activeItemsCount: 0,
    centralValuation: 0.0,
    eyeValuation: 0.0,
    dentalValuation: 0.0,
    totalValuation: 0.0,
    centralUnits: 0.0,
    eyeUnits: 0.0,
    dentalUnits: 0.0,
    totalUnits: 0.0,
    categoryValuations: [],
    centralLowStockCount: 0,
    departmentLowStockCount: 0,
    stockOutCount: 0,
    lowStockItems: [],
    expiredBatchesCount: 0,
    expiredValueLost: 0.0,
    expiring30DaysCount: 0,
    expiring30DaysValue: 0.0,
    expiring60DaysCount: 0,
    expiring60DaysValue: 0.0,
    expiring90DaysCount: 0,
    expiring90DaysValue: 0.0,
    totalAtRiskValue: 0.0,
    batchExpiryDetails: [],
    totalStockInUnits: 0.0,
    totalStockInValue: 0.0,
    totalStockOutUnits: 0.0,
    totalStockOutValue: 0.0,
    movementTrends: [],
    movementReasons: [],
    fastMovingItems: [],
    auditLedger: [],
  );
}
