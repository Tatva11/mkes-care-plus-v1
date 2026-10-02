import 'package:flutter/material.dart';
import 'package:intl/intl.dart';

import '../../../core/theme/app_colors.dart';
import 'inventory_item.dart';

/// Domain model representing an inventory batch received against a Purchase Order or restock.
/// Retains its own batch number, received quantity, remaining quantity, and batch-specific expiry date.
@immutable
class InventoryBatch {
  const InventoryBatch({
    required this.id,
    required this.inventoryId,
    this.inventoryName,
    this.purchaseOrderId,
    this.purchaseOrderNumber,
    this.purchaseOrderItemId,
    this.vendorId,
    this.vendorName,
    required this.batchNumber,
    required this.receivedQuantity,
    required this.remainingQuantity,
    this.unitPrice = 0.0,
    this.totalAmount = 0.0,
    this.expiryDate,
    required this.receivedDate,
    required this.createdAt,
    this.updatedAt,
  });

  final String id;
  final String inventoryId;
  final String? inventoryName;
  final String? purchaseOrderId;
  final String? purchaseOrderNumber;
  final String? purchaseOrderItemId;
  final String? vendorId;
  final String? vendorName;
  final String batchNumber;
  final double receivedQuantity;
  final double remainingQuantity;
  final double unitPrice;
  final double totalAmount;
  final DateTime? expiryDate;
  final DateTime receivedDate;
  final DateTime createdAt;
  final DateTime? updatedAt;

  /// True if batch has 0 remaining units.
  bool get isDepleted => remainingQuantity <= 0;

  /// True if batch has available remaining units.
  bool get hasRemainingStock => remainingQuantity > 0;

  String get formattedReceivedQuantity =>
      receivedQuantity % 1 == 0 ? receivedQuantity.toInt().toString() : receivedQuantity.toString();

  String get formattedRemainingQuantity =>
      remainingQuantity % 1 == 0 ? remainingQuantity.toInt().toString() : remainingQuantity.toString();

  String get formattedUnitPrice => '₹${unitPrice.toStringAsFixed(2)}';
  String get formattedTotalAmount => '₹${totalAmount.toStringAsFixed(2)}';

  String get formattedExpiryDate {
    if (expiryDate == null) return 'No Expiry';
    return DateFormat('dd/MM/yyyy').format(expiryDate!);
  }

  String get formattedReceivedDate {
    return DateFormat('dd/MM/yyyy').format(receivedDate);
  }

  /// Calculates days until expiry relative to today.
  int? get daysUntilExpiry {
    if (expiryDate == null) return null;
    final now = DateTime.now();
    final today = DateTime(now.year, now.month, now.day);
    final exp = DateTime(expiryDate!.year, expiryDate!.month, expiryDate!.day);
    return exp.difference(today).inDays;
  }

  bool get isExpired {
    final days = daysUntilExpiry;
    return days != null && days < 0;
  }

  bool get isExpiringSoon {
    final days = daysUntilExpiry;
    return days != null && days >= 0 && days <= 30;
  }

  ExpiryStatus get expiryStatus {
    if (expiryDate == null) return ExpiryStatus.none;
    final days = daysUntilExpiry;
    if (days == null) return ExpiryStatus.none;
    if (days < 0) return ExpiryStatus.expired;
    if (days <= 30) return ExpiryStatus.expiringSoon;
    return ExpiryStatus.valid;
  }

  String get expiryStatusLabel {
    switch (expiryStatus) {
      case ExpiryStatus.none:
        return 'No Expiry Date';
      case ExpiryStatus.valid:
        return 'Valid ($daysUntilExpiry d)';
      case ExpiryStatus.expiringSoon:
        if (daysUntilExpiry == 0) return 'Expiring Soon (Today)';
        if (daysUntilExpiry == 1) return 'Expiring Soon (Tomorrow)';
        return 'Expiring Soon ($daysUntilExpiry d)';
      case ExpiryStatus.expired:
        final pastDays = daysUntilExpiry!.abs();
        return pastDays == 0 ? 'Expired Today' : 'Expired ($pastDays d ago)';
    }
  }

  Color get expiryStatusColor {
    switch (expiryStatus) {
      case ExpiryStatus.none:
        return AppColors.onSurfaceVariant;
      case ExpiryStatus.valid:
        return Colors.green;
      case ExpiryStatus.expiringSoon:
        return const Color(0xFFE65100);
      case ExpiryStatus.expired:
        return AppColors.error;
    }
  }

  InventoryBatch copyWith({
    String? id,
    String? inventoryId,
    String? inventoryName,
    String? purchaseOrderId,
    String? purchaseOrderNumber,
    String? purchaseOrderItemId,
    String? vendorId,
    String? vendorName,
    String? batchNumber,
    double? receivedQuantity,
    double? remainingQuantity,
    double? unitPrice,
    double? totalAmount,
    DateTime? expiryDate,
    DateTime? receivedDate,
    DateTime? createdAt,
    DateTime? updatedAt,
  }) {
    return InventoryBatch(
      id: id ?? this.id,
      inventoryId: inventoryId ?? this.inventoryId,
      inventoryName: inventoryName ?? this.inventoryName,
      purchaseOrderId: purchaseOrderId ?? this.purchaseOrderId,
      purchaseOrderNumber: purchaseOrderNumber ?? this.purchaseOrderNumber,
      purchaseOrderItemId: purchaseOrderItemId ?? this.purchaseOrderItemId,
      vendorId: vendorId ?? this.vendorId,
      vendorName: vendorName ?? this.vendorName,
      batchNumber: batchNumber ?? this.batchNumber,
      receivedQuantity: receivedQuantity ?? this.receivedQuantity,
      remainingQuantity: remainingQuantity ?? this.remainingQuantity,
      unitPrice: unitPrice ?? this.unitPrice,
      totalAmount: totalAmount ?? this.totalAmount,
      expiryDate: expiryDate ?? this.expiryDate,
      receivedDate: receivedDate ?? this.receivedDate,
      createdAt: createdAt ?? this.createdAt,
      updatedAt: updatedAt ?? this.updatedAt,
    );
  }

  factory InventoryBatch.fromJson(Map<String, dynamic> json) {
    final poData = json['purchase_orders'] as Map<String, dynamic>?;
    final vendorData = json['vendors'] as Map<String, dynamic>?;
    final invData = json['inventory'] as Map<String, dynamic>?;

    return InventoryBatch(
      id: json['id'] as String? ?? '',
      inventoryId: json['inventory_id'] as String? ?? '',
      inventoryName: invData?['name'] as String? ?? json['inventory_name'] as String?,
      purchaseOrderId: json['purchase_order_id'] as String?,
      purchaseOrderNumber: poData?['purchase_order_number'] as String? ??
          json['purchase_order_number'] as String?,
      purchaseOrderItemId: json['purchase_order_item_id'] as String?,
      vendorId: json['vendor_id'] as String?,
      vendorName: vendorData?['name'] as String? ?? json['vendor_name'] as String?,
      batchNumber: json['batch_number'] as String? ?? '',
      receivedQuantity: (json['received_quantity'] as num?)?.toDouble() ?? 0.0,
      remainingQuantity: (json['remaining_quantity'] as num?)?.toDouble() ?? 0.0,
      unitPrice: (json['unit_price'] as num?)?.toDouble() ?? 0.0,
      totalAmount: (json['total_amount'] as num?)?.toDouble() ?? 0.0,
      expiryDate: json['expiry_date'] != null
          ? DateTime.tryParse(json['expiry_date'] as String)
          : null,
      receivedDate: json['received_date'] != null
          ? DateTime.tryParse(json['received_date'] as String) ?? DateTime.now()
          : DateTime.now(),
      createdAt: json['created_at'] != null
          ? DateTime.tryParse(json['created_at'] as String) ?? DateTime.now()
          : DateTime.now(),
      updatedAt: json['updated_at'] != null
          ? DateTime.tryParse(json['updated_at'] as String)
          : null,
    );
  }

  Map<String, dynamic> toJson({bool includeId = true}) {
    final map = <String, dynamic>{
      'inventory_id': inventoryId,
      'batch_number': batchNumber,
      'received_quantity': receivedQuantity,
      'remaining_quantity': remainingQuantity,
      'unit_price': unitPrice,
      'total_amount': totalAmount,
      'received_date': receivedDate.toIso8601String().split('T').first,
    };
    if (includeId && id.isNotEmpty) {
      map['id'] = id;
    }
    if (purchaseOrderId != null) map['purchase_order_id'] = purchaseOrderId;
    if (purchaseOrderItemId != null) {
      map['purchase_order_item_id'] = purchaseOrderItemId;
    }
    if (vendorId != null) map['vendor_id'] = vendorId;
    if (expiryDate != null) {
      map['expiry_date'] = expiryDate!.toIso8601String().split('T').first;
    }
    return map;
  }
}
