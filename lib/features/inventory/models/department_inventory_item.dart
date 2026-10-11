import 'package:flutter/material.dart';

/// Represents allocated inventory stock for a specific clinical department.
@immutable
class DepartmentInventoryItem {
  final String id;
  final String departmentId;
  final String departmentName;
  final String inventoryId;
  final String itemName;
  final String? itemSku;
  final String itemUnit;
  final String? itemCategory;
  final String? itemBrand;
  final bool itemIsActive;
  final double quantity;
  final double minimumStock;
  final bool isLowStock;
  final DateTime? createdAt;
  final DateTime? updatedAt;

  const DepartmentInventoryItem({
    required this.id,
    required this.departmentId,
    required this.departmentName,
    required this.inventoryId,
    required this.itemName,
    this.itemSku,
    required this.itemUnit,
    this.itemCategory,
    this.itemBrand,
    this.itemIsActive = true,
    required this.quantity,
    this.minimumStock = 5.0,
    required this.isLowStock,
    this.createdAt,
    this.updatedAt,
  });

  String get formattedQuantity =>
      quantity % 1 == 0 ? quantity.toInt().toString() : quantity.toStringAsFixed(1);

  String get formattedMinimumStock =>
      minimumStock % 1 == 0 ? minimumStock.toInt().toString() : minimumStock.toStringAsFixed(1);

  factory DepartmentInventoryItem.fromJson(Map<String, dynamic> json) {
    final qty = (json['quantity'] as num?)?.toDouble() ?? 0.0;
    final minStock = (json['minimum_stock'] as num?)?.toDouble() ?? 5.0;
    final lowStock = (json['is_low_stock'] as bool?) ?? (qty <= minStock);

    // Support both view and direct table joins
    final dept = json['departments'] as Map<String, dynamic>?;
    final inv = json['inventory'] as Map<String, dynamic>?;

    return DepartmentInventoryItem(
      id: (json['id'] ?? '').toString(),
      departmentId: (json['department_id'] ?? dept?['id'] ?? '').toString(),
      departmentName: (json['department_name'] ?? dept?['name'] ?? 'Department').toString(),
      inventoryId: (json['inventory_id'] ?? inv?['id'] ?? '').toString(),
      itemName: (json['item_name'] ?? inv?['name'] ?? 'Inventory Item').toString(),
      itemSku: (json['item_sku'] ?? inv?['sku']) as String?,
      itemUnit: (json['item_unit'] ?? inv?['unit'] ?? 'units').toString(),
      itemCategory: (json['item_category'] ?? inv?['category']) as String?,
      itemBrand: (json['item_brand'] ?? inv?['brand']) as String?,
      itemIsActive: (json['item_is_active'] ?? inv?['is_active']) as bool? ?? true,
      quantity: qty,
      minimumStock: minStock,
      isLowStock: lowStock,
      createdAt: json['created_at'] != null ? DateTime.tryParse(json['created_at'].toString()) : null,
      updatedAt: json['updated_at'] != null ? DateTime.tryParse(json['updated_at'].toString()) : null,
    );
  }

  Map<String, dynamic> toJson() => {
    'id': id,
    'department_id': departmentId,
    'department_name': departmentName,
    'inventory_id': inventoryId,
    'item_name': itemName,
    'item_sku': itemSku,
    'item_unit': itemUnit,
    'item_category': itemCategory,
    'item_brand': itemBrand,
    'item_is_active': itemIsActive,
    'quantity': quantity,
    'minimum_stock': minimumStock,
    'is_low_stock': isLowStock,
    'created_at': createdAt?.toIso8601String(),
    'updated_at': updatedAt?.toIso8601String(),
  };
}
