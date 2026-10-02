import 'package:flutter/material.dart';

/// Domain model representing a pharmaceutical or supplies vendor in MKES CARE+.
@immutable
class Vendor {
  final String id;
  final String name;
  final String? contactPerson;
  final String? phone;
  final String? email;
  final String? address;
  final List<String> productsSupplied;
  final DateTime? lastOrderDate;
  final DateTime? lastDeliveryDate;
  final double? lastQuantity;
  final double? lastTotalAmount;
  final String? remarks;
  final bool isActive;
  final DateTime? createdAt;
  final DateTime? updatedAt;

  const Vendor({
    required this.id,
    required this.name,
    this.contactPerson,
    this.phone,
    this.email,
    this.address,
    this.productsSupplied = const [],
    this.lastOrderDate,
    this.lastDeliveryDate,
    this.lastQuantity,
    this.lastTotalAmount,
    this.remarks,
    this.isActive = true,
    this.createdAt,
    this.updatedAt,
  });

  /// Automatically calculated price per piece/unit: total payment amount / quantity.
  /// Returns null if quantity is missing, non-positive, or total amount is missing.
  double? get pricePerPiece {
    if (lastQuantity == null || lastQuantity! <= 0) return null;
    if (lastTotalAmount == null || lastTotalAmount! < 0) return null;
    return lastTotalAmount! / lastQuantity!;
  }

  /// Formatted total payment amount string (e.g. "₹5,000.00" or "—").
  String get formattedLastTotalAmount {
    if (lastTotalAmount == null) return '—';
    return '₹${lastTotalAmount!.toStringAsFixed(2)}';
  }

  /// Formatted price per piece string (e.g. "₹50.00" or "—").
  String get formattedPricePerPiece {
    final p = pricePerPiece;
    if (p == null) return '—';
    return '₹${p.toStringAsFixed(2)}';
  }

  /// Formatted comma-separated list of products supplied.
  String get productsDisplay =>
      productsSupplied.isEmpty ? 'None specified' : productsSupplied.join(', ');

  /// Formatted last order date string (YYYY-MM-DD or '—').
  String get formattedLastOrder {
    if (lastOrderDate == null) return '—';
    return '${lastOrderDate!.year}-${lastOrderDate!.month.toString().padLeft(2, '0')}-${lastOrderDate!.day.toString().padLeft(2, '0')}';
  }

  /// Formatted last delivery date string (YYYY-MM-DD or '—').
  String get formattedLastDelivery {
    if (lastDeliveryDate == null) return '—';
    return '${lastDeliveryDate!.year}-${lastDeliveryDate!.month.toString().padLeft(2, '0')}-${lastDeliveryDate!.day.toString().padLeft(2, '0')}';
  }

  /// Formatted last quantity string.
  String get formattedLastQuantity {
    if (lastQuantity == null) return '—';
    if (lastQuantity! % 1 == 0) return lastQuantity!.toInt().toString();
    return lastQuantity!.toStringAsFixed(2);
  }

  /// Status label ('Active' or 'Inactive').
  String get statusLabel => isActive ? 'Active' : 'Inactive';

  /// Deserializes a vendor record from Supabase / JSON payload.
  factory Vendor.fromJson(Map<String, dynamic> json) {
    DateTime? parseDate(dynamic value) {
      if (value == null) return null;
      if (value is DateTime) return value;
      return DateTime.tryParse(value.toString());
    }

    List<String> parseProducts(dynamic value) {
      if (value == null) return const [];
      if (value is List) {
        return value
            .map((e) => e.toString().trim())
            .where((e) => e.isNotEmpty)
            .toList();
      }
      if (value is String) {
        var str = value.trim();
        if (str.startsWith('{') && str.endsWith('}')) {
          str = str.substring(1, str.length - 1);
        }
        if (str.isEmpty) return const [];
        return str
            .split(',')
            .map((e) => e.replaceAll('"', '').trim())
            .where((e) => e.isNotEmpty)
            .toList();
      }
      return const [];
    }

    final rawQuantity = json['last_quantity'] ?? json['lastQuantity'];
    final quantity = rawQuantity is num
        ? rawQuantity.toDouble()
        : (rawQuantity != null ? double.tryParse(rawQuantity.toString()) : null);

    final rawTotalAmount = json['last_total_amount'] ?? json['lastTotalAmount'];
    final totalAmount = rawTotalAmount is num
        ? rawTotalAmount.toDouble()
        : (rawTotalAmount != null ? double.tryParse(rawTotalAmount.toString()) : null);

    return Vendor(
      id: (json['id'] ?? '').toString(),
      name: (json['name'] ?? '').toString(),
      contactPerson: (json['contact_person'] ?? json['contactPerson'])?.toString(),
      phone: json['phone']?.toString(),
      email: json['email']?.toString(),
      address: json['address']?.toString(),
      productsSupplied: parseProducts(json['products_supplied'] ?? json['productsSupplied']),
      lastOrderDate: parseDate(json['last_order_date'] ?? json['lastOrderDate']),
      lastDeliveryDate: parseDate(json['last_delivery_date'] ?? json['lastDeliveryDate']),
      lastQuantity: quantity,
      lastTotalAmount: totalAmount,
      remarks: json['remarks']?.toString(),
      isActive: (json['is_active'] ?? json['isActive'] ?? true) as bool,
      createdAt: parseDate(json['created_at'] ?? json['createdAt']),
      updatedAt: parseDate(json['updated_at'] ?? json['updatedAt']),
    );
  }

  /// Serializes into database payload for Supabase.
  Map<String, dynamic> toJson({bool includeId = true}) {
    final map = <String, dynamic>{
      'name': name.trim(),
      'contact_person': contactPerson?.trim().isNotEmpty == true ? contactPerson!.trim() : null,
      'phone': phone?.trim().isNotEmpty == true ? phone!.trim() : null,
      'email': email?.trim().isNotEmpty == true ? email!.trim() : null,
      'address': address?.trim().isNotEmpty == true ? address!.trim() : null,
      'products_supplied': productsSupplied,
      'last_order_date': lastOrderDate?.toIso8601String().split('T').first,
      'last_delivery_date': lastDeliveryDate?.toIso8601String().split('T').first,
      'last_quantity': lastQuantity,
      if (lastTotalAmount != null) 'last_total_amount': lastTotalAmount,
      'remarks': remarks?.trim().isNotEmpty == true ? remarks!.trim() : null,
      'is_active': isActive,
    };

    if (includeId && id.isNotEmpty) {
      map['id'] = id;
    }
    return map;
  }

  /// Creates a copy of this [Vendor] with updated fields.
  Vendor copyWith({
    String? id,
    String? name,
    String? contactPerson,
    String? phone,
    String? email,
    String? address,
    List<String>? productsSupplied,
    DateTime? lastOrderDate,
    DateTime? lastDeliveryDate,
    double? lastQuantity,
    double? lastTotalAmount,
    String? remarks,
    bool? isActive,
    DateTime? createdAt,
    DateTime? updatedAt,
  }) {
    return Vendor(
      id: id ?? this.id,
      name: name ?? this.name,
      contactPerson: contactPerson ?? this.contactPerson,
      phone: phone ?? this.phone,
      email: email ?? this.email,
      address: address ?? this.address,
      productsSupplied: productsSupplied ?? this.productsSupplied,
      lastOrderDate: lastOrderDate ?? this.lastOrderDate,
      lastDeliveryDate: lastDeliveryDate ?? this.lastDeliveryDate,
      lastQuantity: lastQuantity ?? this.lastQuantity,
      lastTotalAmount: lastTotalAmount ?? this.lastTotalAmount,
      remarks: remarks ?? this.remarks,
      isActive: isActive ?? this.isActive,
      createdAt: createdAt ?? this.createdAt,
      updatedAt: updatedAt ?? this.updatedAt,
    );
  }

  @override
  bool operator ==(Object other) =>
      identical(this, other) ||
      other is Vendor &&
          runtimeType == other.runtimeType &&
          id == other.id &&
          name == other.name &&
          isActive == other.isActive;

  @override
  int get hashCode => id.hashCode ^ name.hashCode ^ isActive.hashCode;
}
