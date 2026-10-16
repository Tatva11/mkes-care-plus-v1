import 'package:flutter/material.dart';

/// Predefined standard reasons for Stock In operations.
class StockInReasons {
  static const String restock = 'Restock';
  static const String restockNewPurchase = 'Restock / New Purchase';
  static const String supplierDelivery = 'Supplier Delivery';

  static const List<String> defaults = [
    restock,
    restockNewPurchase,
    supplierDelivery,
    'Return from Department',
    'Physical Audit Adjustment (+)',
    'Donation / Free Sample',
    'Other',
  ];
}

/// Predefined standard reasons for Stock Out operations.
class StockOutReasons {
  static const String dispensedToPatient = 'Dispensed to Patient';
  static const String generalUsage = 'General Usage';
  static const String damaged = 'Damaged';
  static const String expired = 'Expired';

  static const List<String> defaults = [
    generalUsage,
    damaged,
    expired,
    dispensedToPatient,
    'Issued to Eye Department',
    'Issued to Dental Department',
    'Issued to Optical Department',
    'Routine Clinical Usage',
    'Physical Audit Adjustment (-)',
    'Other',
  ];
}

/// Domain model representing an immutable stock transaction in MKES CARE+.
@immutable
class InventoryTransaction {
  final String id;
  final String inventoryItemId;
  final String transactionType; // 'stock_in' or 'stock_out'
  final double quantity;
  final double? stockBefore;
  final double? stockAfter;
  final String? reason;
  final String? remarks;
  final String? performedBy;
  final String? performedByName;
  final String? patientId;
  final String? patientName;
  final String? patientNumber;
  final String? vendorId;
  final String? vendorName;
  final String? departmentId;
  final String? departmentName;
  final double? totalAmount;
  final double? unitPrice;
  final DateTime createdAt;

  const InventoryTransaction({
    required this.id,
    required this.inventoryItemId,
    required this.transactionType,
    required this.quantity,
    this.stockBefore,
    this.stockAfter,
    this.reason,
    this.remarks,
    this.performedBy,
    this.performedByName,
    this.patientId,
    this.patientName,
    this.patientNumber,
    this.vendorId,
    this.vendorName,
    this.departmentId,
    this.departmentName,
    this.totalAmount,
    this.unitPrice,
    required this.createdAt,
  });

  /// Formatted total payment amount string.
  String? get formattedTotalAmount {
    if (totalAmount == null) return null;
    return '₹${totalAmount!.toStringAsFixed(2)}';
  }

  /// Formatted unit price / price per piece string.
  String? get formattedUnitPrice {
    if (unitPrice == null) return null;
    return '₹${unitPrice!.toStringAsFixed(2)}';
  }

  /// True if this transaction added stock.
  bool get isStockIn => transactionType == 'stock_in';

  /// True if this transaction removed stock.
  bool get isStockOut => transactionType == 'stock_out';

  /// True if this transaction was dispensed directly to a patient.
  bool get isDispensedToPatient =>
      isStockOut && reason == StockOutReasons.dispensedToPatient;

  /// Formatted patient display label (e.g. "John Doe (P-101)").
  String? get patientDisplay {
    if (patientName != null &&
        patientNumber != null &&
        patientNumber!.isNotEmpty) {
      return '$patientName ($patientNumber)';
    }
    return patientName ?? patientNumber ?? patientId;
  }

  /// Human-readable label for transaction type.
  String get typeLabel => isStockIn ? 'Stock In' : 'Stock Out';

  /// Theme color for transaction type.
  Color get typeColor => isStockIn ? Colors.green : const Color(0xFFE65100);

  /// Visual icon for transaction type.
  IconData get typeIcon =>
      isStockIn ? Icons.add_circle_outline : Icons.remove_circle_outline;

  /// Formatted quantity display with sign (e.g. "+15" or "-4").
  String get formattedQuantity {
    final qtyStr = quantity % 1 == 0
        ? quantity.toInt().toString()
        : quantity.toStringAsFixed(2);
    return isStockIn ? '+$qtyStr' : '-$qtyStr';
  }

  /// Formatted progression string (e.g. "20 → 25").
  String? get formattedStockProgression {
    if (stockBefore == null || stockAfter == null) return null;
    final bStr = stockBefore! % 1 == 0
        ? stockBefore!.toInt().toString()
        : stockBefore!.toStringAsFixed(2);
    final aStr = stockAfter! % 1 == 0
        ? stockAfter!.toInt().toString()
        : stockAfter!.toStringAsFixed(2);
    return '$bStr → $aStr';
  }

  /// Deserializes a transaction record from Supabase.
  factory InventoryTransaction.fromJson(Map<String, dynamic> json) {
    DateTime parseDate(dynamic value) {
      if (value == null) return DateTime.now();
      if (value is DateTime) return value;
      return DateTime.tryParse(value.toString()) ?? DateTime.now();
    }

    final rawQuantity = json['quantity'];
    final qty = rawQuantity is num
        ? rawQuantity.toDouble()
        : (double.tryParse(rawQuantity?.toString() ?? '0') ?? 0.0);

    final rawBefore = json['stock_before'] ?? json['stockBefore'];
    final before = rawBefore is num
        ? rawBefore.toDouble()
        : (rawBefore != null ? double.tryParse(rawBefore.toString()) : null);

    final rawAfter = json['stock_after'] ?? json['stockAfter'];
    final after = rawAfter is num
        ? rawAfter.toDouble()
        : (rawAfter != null ? double.tryParse(rawAfter.toString()) : null);

    // Profile join resolution
    String? performerName = json['performed_by_name']?.toString();
    final rawProfile = json['profiles'] ?? json['profiles!performed_by'];
    if (performerName == null && rawProfile is Map) {
      final profile = rawProfile as Map<String, dynamic>;
      performerName = profile['full_name']?.toString() ?? profile['name']?.toString();
    }

    // Patient join resolution
    String? patName = json['patient_name']?.toString();
    String? patNumber = json['patient_number']?.toString();
    final rawPatient = json['patients'] ?? json['patients!patient_id'];
    if (rawPatient is Map) {
      final pat = rawPatient as Map<String, dynamic>;
      patName ??= pat['name']?.toString();
      patNumber ??= pat['patient_number']?.toString();
    }

    // Vendor join resolution
    String? vName = json['vendor_name']?.toString();
    final rawVendor = json['vendors'] ?? json['vendor'];
    if (rawVendor is Map) {
      vName ??= (rawVendor as Map<String, dynamic>)['name']?.toString();
    }

    // Department join resolution
    String? deptName = json['department_name']?.toString();
    final rawDept = json['departments'] ?? json['department'];
    if (deptName == null && rawDept is Map) {
      deptName = (rawDept as Map<String, dynamic>)['name']?.toString();
    }

    final rawTotal = json['total_amount'] ?? json['totalAmount'];
    final totalVal = rawTotal is num
        ? rawTotal.toDouble()
        : (rawTotal != null ? double.tryParse(rawTotal.toString()) : null);

    final rawUnit = json['unit_price'] ?? json['unitPrice'];
    final unitVal = rawUnit is num
        ? rawUnit.toDouble()
        : (rawUnit != null ? double.tryParse(rawUnit.toString()) : null);

    return InventoryTransaction(
      id: (json['id'] ?? '').toString(),
      inventoryItemId: (json['inventory_id'] ?? json['inventoryItemId'] ?? '').toString(),
      transactionType: (json['transaction_type'] ?? json['transactionType'] ?? 'stock_in').toString(),
      quantity: qty,
      stockBefore: before,
      stockAfter: after,
      reason: json['reason'] as String?,
      remarks: json['remarks'] as String?,
      performedBy: (json['performed_by'] ?? json['created_by'])?.toString(),
      performedByName: performerName,
      patientId: (json['patient_id'] ?? json['patientId'])?.toString(),
      patientName: patName,
      patientNumber: patNumber,
      vendorId: (json['vendor_id'] ?? json['vendorId'])?.toString(),
      vendorName: vName,
      departmentId: (json['department_id'] ?? json['departmentId'])?.toString(),
      departmentName: deptName,
      totalAmount: totalVal,
      unitPrice: unitVal,
      createdAt: parseDate(json['created_at']),
    );
  }

  /// Serializes into database payload for Supabase.
  Map<String, dynamic> toJson({bool includeId = true}) {
    final map = <String, dynamic>{
      'inventory_id': inventoryItemId,
      'transaction_type': transactionType,
      'quantity': quantity,
      if (stockBefore != null) 'stock_before': stockBefore,
      if (stockAfter != null) 'stock_after': stockAfter,
      if (reason != null && reason!.trim().isNotEmpty) 'reason': reason!.trim(),
      if (remarks != null && remarks!.trim().isNotEmpty) 'remarks': remarks!.trim(),
      if (performedBy != null) 'performed_by': performedBy,
      if (performedBy != null) 'created_by': performedBy,
      if (patientId != null && patientId!.trim().isNotEmpty) 'patient_id': patientId!.trim(),
      if (vendorId != null && vendorId!.trim().isNotEmpty) 'vendor_id': vendorId!.trim(),
      if (departmentId != null && departmentId!.trim().isNotEmpty) 'department_id': departmentId!.trim(),
      if (totalAmount != null) 'total_amount': totalAmount,
      if (unitPrice != null) 'unit_price': unitPrice,
      'created_at': createdAt.toIso8601String(),
    };

    if (includeId && id.isNotEmpty) {
      map['id'] = id;
    }

    return map;
  }

  /// Immutability copy helper.
  InventoryTransaction copyWith({
    String? id,
    String? inventoryItemId,
    String? transactionType,
    double? quantity,
    double? stockBefore,
    double? stockAfter,
    String? reason,
    String? remarks,
    String? performedBy,
    String? performedByName,
    String? patientId,
    String? patientName,
    String? patientNumber,
    String? vendorId,
    String? vendorName,
    String? departmentId,
    String? departmentName,
    double? totalAmount,
    double? unitPrice,
    DateTime? createdAt,
  }) {
    return InventoryTransaction(
      id: id ?? this.id,
      inventoryItemId: inventoryItemId ?? this.inventoryItemId,
      transactionType: transactionType ?? this.transactionType,
      quantity: quantity ?? this.quantity,
      stockBefore: stockBefore ?? this.stockBefore,
      stockAfter: stockAfter ?? this.stockAfter,
      reason: reason ?? this.reason,
      remarks: remarks ?? this.remarks,
      performedBy: performedBy ?? this.performedBy,
      performedByName: performedByName ?? this.performedByName,
      patientId: patientId ?? this.patientId,
      patientName: patientName ?? this.patientName,
      patientNumber: patientNumber ?? this.patientNumber,
      vendorId: vendorId ?? this.vendorId,
      vendorName: vendorName ?? this.vendorName,
      departmentId: departmentId ?? this.departmentId,
      departmentName: departmentName ?? this.departmentName,
      totalAmount: totalAmount ?? this.totalAmount,
      unitPrice: unitPrice ?? this.unitPrice,
      createdAt: createdAt ?? this.createdAt,
    );
  }

  @override
  bool operator ==(Object other) {
    if (identical(this, other)) return true;
    return other is InventoryTransaction && other.id == id;
  }

  @override
  int get hashCode => id.hashCode;
}
