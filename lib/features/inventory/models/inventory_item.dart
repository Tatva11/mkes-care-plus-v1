import 'package:flutter/material.dart';

import '../../../core/theme/app_colors.dart';
import 'inventory_batch.dart';

/// Expiry status calculation based on current date.
enum ExpiryStatus {
  none,
  valid,
  expiringSoon,
  expired,
}

/// Predefined category options for inventory items.
class InventoryCategories {
  static const List<String> defaults = [
    'Pharmaceuticals',
    'Clinical Supplies',
    'Optical & Frames',
    'Dental Materials',
    'Consumables & PPE',
    'Lab & Diagnostics',
    'Surgical Equipment',
    'General',
  ];
}

/// Standard measurement units for inventory stock.
class InventoryUnits {
  static const List<String> defaults = [
    'pcs',
    'boxes',
    'bottles',
    'vials',
    'pairs',
    'packs',
    'strips',
    'units',
    'sets',
    'tubes',
  ];
}

/// Domain model representing an inventory item in the MKES CARE+ clinic.
@immutable
class InventoryItem {
  final String id;
  final String name;
  final String category;
  final String? description;
  final double currentStock;
  final String unit;
  final String? sku;
  final String? department;
  final double? minimumStock;
  final DateTime? expiryDate;
  final String? brand;
  final double? price;
  final String? vendorId;
  final String? vendorName;
  final String? vendorPhone;
  final double? lastQuantitySupplied;
  final double? lastTotalAmount;
  final List<InventoryBatch>? batches;
  final bool isActive;
  final DateTime? createdAt;
  final DateTime? updatedAt;

  const InventoryItem({
    required this.id,
    required this.name,
    required this.category,
    this.description,
    required this.currentStock,
    required this.unit,
    this.sku,
    this.department,
    this.minimumStock,
    this.expiryDate,
    this.brand,
    this.price,
    this.vendorId,
    this.vendorName,
    this.vendorPhone,
    this.lastQuantitySupplied,
    this.lastTotalAmount,
    this.batches,
    this.isActive = true,
    this.createdAt,
    this.updatedAt,
  });

  /// Automatically calculated price per piece for the latest restock: total payment / quantity.
  /// Returns null if quantity is missing, non-positive, or total amount is missing.
  double? get calculatedPricePerPiece {
    if (lastQuantitySupplied == null || lastQuantitySupplied! <= 0) return null;
    if (lastTotalAmount == null || lastTotalAmount! < 0) return null;
    return lastTotalAmount! / lastQuantitySupplied!;
  }

  /// Formatted last quantity supplied string.
  String get formattedLastQuantitySupplied {
    if (lastQuantitySupplied == null) return '—';
    if (lastQuantitySupplied! % 1 == 0) return lastQuantitySupplied!.toInt().toString();
    return lastQuantitySupplied!.toStringAsFixed(2);
  }

  /// Formatted total payment amount string (e.g. "₹5,000.00" or "—").
  String get formattedLastTotalAmount {
    if (lastTotalAmount == null) return '—';
    return '₹${lastTotalAmount!.toStringAsFixed(2)}';
  }

  /// Formatted price per piece string (e.g. "₹50.00" or "—").
  String get formattedCalculatedPricePerPiece {
    final p = calculatedPricePerPiece;
    if (p == null) return '—';
    return '₹${p.toStringAsFixed(2)}';
  }

  /// True if current stock is at or below the defined minimum stock threshold.
  bool get isLowStock {
    if (minimumStock == null || minimumStock! <= 0) {
      return currentStock <= 0;
    }
    return currentStock <= minimumStock!;
  }

  /// Formatted stock display, e.g. "25 pcs" or "12.5 kg".
  String get formattedStock {
    final stockStr = currentStock % 1 == 0
        ? currentStock.toInt().toString()
        : currentStock.toStringAsFixed(2);
    return '$stockStr $unit';
  }

  /// Formatted minimum stock threshold if specified.
  String? get formattedMinStock {
    if (minimumStock == null) return null;
    final minStr = minimumStock! % 1 == 0
        ? minimumStock!.toInt().toString()
        : minimumStock!.toStringAsFixed(2);
    return '$minStr $unit';
  }

  /// Returns the effective earliest expiry date among active batches,
  /// falling back to [expiryDate] if no active batches with expiry exist.
  DateTime? get effectiveExpiryDate {
    if (batches != null && batches!.isNotEmpty) {
      final activeWithExpiry = batches!
          .where((b) => b.remainingQuantity > 0 && b.expiryDate != null)
          .toList();
      if (activeWithExpiry.isNotEmpty) {
        activeWithExpiry.sort((a, b) => a.expiryDate!.compareTo(b.expiryDate!));
        return activeWithExpiry.first.expiryDate;
      }
    }
    return expiryDate;
  }

  /// Calculates expiry status relative to today based on batches (or expiryDate).
  ExpiryStatus get expiryStatus {
    final expDate = effectiveExpiryDate;
    if (expDate == null) return ExpiryStatus.none;
    final now = DateTime.now();
    final today = DateTime(now.year, now.month, now.day);
    final exp = DateTime(expDate.year, expDate.month, expDate.day);
    final diffInDays = exp.difference(today).inDays;
    if (diffInDays < 0) return ExpiryStatus.expired;
    if (diffInDays <= 30) return ExpiryStatus.expiringSoon;
    return ExpiryStatus.valid;
  }

  /// Number of days remaining until expiry (negative if already expired).
  int? get daysUntilExpiry {
    final expDate = effectiveExpiryDate;
    if (expDate == null) return null;
    final now = DateTime.now();
    final today = DateTime(now.year, now.month, now.day);
    final exp = DateTime(expDate.year, expDate.month, expDate.day);
    return exp.difference(today).inDays;
  }

  /// True if the item is expiring within 30 days.
  bool get isExpiringSoon => expiryStatus == ExpiryStatus.expiringSoon;

  /// True if the item has already expired.
  bool get isExpired => expiryStatus == ExpiryStatus.expired;

  /// Human-readable expiry status label.
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

  /// Color representing the urgency of the expiry status.
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

  /// Icon representing the expiry status.
  IconData get expiryStatusIcon {
    switch (expiryStatus) {
      case ExpiryStatus.none:
        return Icons.calendar_today_outlined;
      case ExpiryStatus.valid:
        return Icons.verified_outlined;
      case ExpiryStatus.expiringSoon:
        return Icons.warning_amber_rounded;
      case ExpiryStatus.expired:
        return Icons.event_busy_outlined;
    }
  }

  /// Human-readable stock status label.
  String get stockStatusLabel {
    if (currentStock <= 0) return 'Out of Stock';
    if (isLowStock) return 'Low Stock';
    return 'In Stock';
  }

  /// Color representing stock health.
  Color get stockStatusColor {
    if (currentStock <= 0 || isLowStock) return AppColors.error;
    return Colors.green;
  }

  /// Deserializes a database row from Supabase.
  factory InventoryItem.fromJson(Map<String, dynamic> json) {
    DateTime? parseDate(dynamic value) {
      if (value == null) return null;
      if (value is DateTime) return value;
      return DateTime.tryParse(value.toString());
    }

    final rawQuantity = json['quantity'] ?? json['current_stock'];
    final stockVal = rawQuantity is num
        ? rawQuantity.toDouble()
        : (double.tryParse(rawQuantity?.toString() ?? '0') ?? 0.0);

    final rawMinStock = json['minimum_stock'];
    final minStockVal = rawMinStock is num
        ? rawMinStock.toDouble()
        : (rawMinStock != null ? double.tryParse(rawMinStock.toString()) : null);

    final rawPrice = json['price'];
    final priceVal = rawPrice is num
        ? rawPrice.toDouble()
        : (rawPrice != null ? double.tryParse(rawPrice.toString()) : null);

    final rawLastQuantity = json['last_quantity_supplied'] ?? json['lastQuantitySupplied'];
    final lastQtyVal = rawLastQuantity is num
        ? rawLastQuantity.toDouble()
        : (rawLastQuantity != null ? double.tryParse(rawLastQuantity.toString()) : null);

    final rawLastTotal = json['last_total_amount'] ?? json['lastTotalAmount'];
    final lastTotalVal = rawLastTotal is num
        ? rawLastTotal.toDouble()
        : (rawLastTotal != null ? double.tryParse(rawLastTotal.toString()) : null);

    // Vendor join resolution
    String? vName = json['vendor_name']?.toString();
    String? vPhone = json['vendor_phone']?.toString();
    final rawVendor = json['vendors'] ?? json['vendor'];
    if (rawVendor is Map) {
      final vMap = rawVendor as Map<String, dynamic>;
      vName ??= vMap['name']?.toString();
      vPhone ??= vMap['phone']?.toString();
    }

    // Inventory batches deserialization if joined or provided
    final rawBatches = json['inventory_batches'] ?? json['batches'];
    List<InventoryBatch>? parsedBatches;
    if (rawBatches is List) {
      parsedBatches = rawBatches
          .map((b) => InventoryBatch.fromJson(b as Map<String, dynamic>))
          .toList();
    }

    return InventoryItem(
      id: (json['id'] ?? '').toString(),
      name: (json['name'] ?? '').toString(),
      category: (json['category'] ?? 'General').toString(),
      description: json['description'] as String? ?? json['remarks'] as String?,
      currentStock: stockVal,
      unit: (json['unit'] as String?)?.isNotEmpty == true
          ? json['unit'] as String
          : 'units',
      sku: json['sku'] as String?,
      department: json['department'] as String?,
      minimumStock: minStockVal,
      expiryDate: parseDate(json['expiry_date']),
      brand: json['brand'] as String?,
      price: priceVal,
      vendorId: (json['vendor_id'] ?? json['vendorId'])?.toString(),
      vendorName: vName,
      vendorPhone: vPhone,
      lastQuantitySupplied: lastQtyVal,
      lastTotalAmount: lastTotalVal,
      batches: parsedBatches,
      isActive: json['is_active'] as bool? ?? true,
      createdAt: parseDate(json['created_at']),
      updatedAt: parseDate(json['updated_at']),
    );
  }

  /// Serializes into a Supabase record payload.
  Map<String, dynamic> toJson({bool includeId = true}) {
    final map = <String, dynamic>{
      'name': name.trim(),
      'category': category.trim(),
      'description': (description?.trim().isNotEmpty ?? false)
          ? description!.trim()
          : null,
      'quantity': currentStock,
      'unit': unit.trim(),
      'is_active': isActive,
    };

    if (includeId && id.isNotEmpty) {
      map['id'] = id;
    }
    if (sku != null && sku!.trim().isNotEmpty) {
      map['sku'] = sku!.trim();
    }
    if (department != null && department!.trim().isNotEmpty) {
      map['department'] = department!.trim().toLowerCase();
    }
    if (minimumStock != null) {
      map['minimum_stock'] = minimumStock;
    }
    if (expiryDate != null) {
      map['expiry_date'] = expiryDate!.toIso8601String().split('T').first;
    }
    if (brand != null && brand!.trim().isNotEmpty) {
      map['brand'] = brand!.trim();
    }
    if (price != null) {
      map['price'] = price;
    }
    if (vendorId != null && vendorId!.trim().isNotEmpty) {
      map['vendor_id'] = vendorId!.trim();
    }
    if (lastQuantitySupplied != null) {
      map['last_quantity_supplied'] = lastQuantitySupplied;
    }
    if (lastTotalAmount != null) {
      map['last_total_amount'] = lastTotalAmount;
    }

    return map;
  }

  /// Immutability helper for editing or updating fields.
  InventoryItem copyWith({
    String? id,
    String? name,
    String? category,
    String? description,
    double? currentStock,
    String? unit,
    String? sku,
    String? department,
    double? minimumStock,
    DateTime? expiryDate,
    String? brand,
    double? price,
    String? vendorId,
    String? vendorName,
    String? vendorPhone,
    double? lastQuantitySupplied,
    double? lastTotalAmount,
    List<InventoryBatch>? batches,
    bool? isActive,
    DateTime? createdAt,
    DateTime? updatedAt,
  }) {
    return InventoryItem(
      id: id ?? this.id,
      name: name ?? this.name,
      category: category ?? this.category,
      description: description ?? this.description,
      currentStock: currentStock ?? this.currentStock,
      unit: unit ?? this.unit,
      sku: sku ?? this.sku,
      department: department ?? this.department,
      minimumStock: minimumStock ?? this.minimumStock,
      expiryDate: expiryDate ?? this.expiryDate,
      brand: brand ?? this.brand,
      price: price ?? this.price,
      vendorId: vendorId ?? this.vendorId,
      vendorName: vendorName ?? this.vendorName,
      vendorPhone: vendorPhone ?? this.vendorPhone,
      lastQuantitySupplied: lastQuantitySupplied ?? this.lastQuantitySupplied,
      lastTotalAmount: lastTotalAmount ?? this.lastTotalAmount,
      batches: batches ?? this.batches,
      isActive: isActive ?? this.isActive,
      createdAt: createdAt ?? this.createdAt,
      updatedAt: updatedAt ?? this.updatedAt,
    );
  }

  @override
  bool operator ==(Object other) {
    if (identical(this, other)) return true;
    return other is InventoryItem && other.id == id;
  }

  @override
  int get hashCode => id.hashCode;
}
