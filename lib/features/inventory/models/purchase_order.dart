import 'package:flutter/material.dart';

import '../../../core/theme/app_colors.dart';

/// Represents the workflow status of a Purchase Order.
enum PurchaseOrderStatus {
  draft,
  ordered,
  partiallyReceived,
  received,
  cancelled;

  static PurchaseOrderStatus fromString(String value) {
    switch (value.toLowerCase().replaceAll(' ', '_')) {
      case 'draft':
        return PurchaseOrderStatus.draft;
      case 'ordered':
        return PurchaseOrderStatus.ordered;
      case 'partially_received':
      case 'partiallyreceived':
      case 'partial':
        return PurchaseOrderStatus.partiallyReceived;
      case 'received':
        return PurchaseOrderStatus.received;
      case 'cancelled':
      case 'canceled':
        return PurchaseOrderStatus.cancelled;
      default:
        return PurchaseOrderStatus.draft;
    }
  }

  String get dbValue {
    switch (this) {
      case PurchaseOrderStatus.draft:
        return 'draft';
      case PurchaseOrderStatus.ordered:
        return 'ordered';
      case PurchaseOrderStatus.partiallyReceived:
        return 'partially_received';
      case PurchaseOrderStatus.received:
        return 'received';
      case PurchaseOrderStatus.cancelled:
        return 'cancelled';
    }
  }

  String get label {
    switch (this) {
      case PurchaseOrderStatus.draft:
        return 'Draft';
      case PurchaseOrderStatus.ordered:
        return 'Ordered';
      case PurchaseOrderStatus.partiallyReceived:
        return 'Partially Received';
      case PurchaseOrderStatus.received:
        return 'Received';
      case PurchaseOrderStatus.cancelled:
        return 'Cancelled';
    }
  }

  Color get color {
    switch (this) {
      case PurchaseOrderStatus.draft:
        return const Color(0xFF757575); // Neutral Grey
      case PurchaseOrderStatus.ordered:
        return const Color(0xFF1976D2); // Blue
      case PurchaseOrderStatus.partiallyReceived:
        return const Color(0xFFE65100); // Deep Orange
      case PurchaseOrderStatus.received:
        return const Color(0xFF2E7D32); // Forest Green
      case PurchaseOrderStatus.cancelled:
        return AppColors.error; // Red
    }
  }

  IconData get icon {
    switch (this) {
      case PurchaseOrderStatus.draft:
        return Icons.edit_note_outlined;
      case PurchaseOrderStatus.ordered:
        return Icons.send_outlined;
      case PurchaseOrderStatus.partiallyReceived:
        return Icons.hourglass_top_outlined;
      case PurchaseOrderStatus.received:
        return Icons.check_circle_outline;
      case PurchaseOrderStatus.cancelled:
        return Icons.cancel_outlined;
    }
  }
}

/// Represents an individual line item inside a Purchase Order.
class PurchaseOrderItem {
  const PurchaseOrderItem({
    required this.id,
    required this.purchaseOrderId,
    required this.inventoryId,
    this.inventoryName = '',
    this.inventoryUnit = 'units',
    this.inventorySku,
    required this.quantity,
    required this.unitPrice,
    required this.totalAmount,
    this.receivedQuantity = 0.0,
    this.createdAt,
    this.updatedAt,
  });

  final String id;
  final String purchaseOrderId;
  final String inventoryId;
  final String inventoryName;
  final String inventoryUnit;
  final String? inventorySku;
  final double quantity;
  final double unitPrice;
  final double totalAmount;
  final double receivedQuantity;
  final DateTime? createdAt;
  final DateTime? updatedAt;

  double get remainingQuantity {
    final remaining = quantity - receivedQuantity;
    return remaining > 0 ? remaining : 0.0;
  }

  bool get isFullyReceived => receivedQuantity >= quantity;

  String get formattedQuantity =>
      '${quantity % 1 == 0 ? quantity.toInt() : quantity} $inventoryUnit';

  String get formattedReceivedQuantity =>
      '${receivedQuantity % 1 == 0 ? receivedQuantity.toInt() : receivedQuantity} $inventoryUnit';

  String get formattedRemainingQuantity =>
      '${remainingQuantity % 1 == 0 ? remainingQuantity.toInt() : remainingQuantity} $inventoryUnit';

  String get formattedUnitPrice => '₹${unitPrice.toStringAsFixed(2)}';
  String get formattedTotalAmount => '₹${totalAmount.toStringAsFixed(2)}';

  PurchaseOrderItem copyWith({
    String? id,
    String? purchaseOrderId,
    String? inventoryId,
    String? inventoryName,
    String? inventoryUnit,
    String? inventorySku,
    double? quantity,
    double? unitPrice,
    double? totalAmount,
    double? receivedQuantity,
    DateTime? createdAt,
    DateTime? updatedAt,
  }) {
    return PurchaseOrderItem(
      id: id ?? this.id,
      purchaseOrderId: purchaseOrderId ?? this.purchaseOrderId,
      inventoryId: inventoryId ?? this.inventoryId,
      inventoryName: inventoryName ?? this.inventoryName,
      inventoryUnit: inventoryUnit ?? this.inventoryUnit,
      inventorySku: inventorySku ?? this.inventorySku,
      quantity: quantity ?? this.quantity,
      unitPrice: unitPrice ?? this.unitPrice,
      totalAmount: totalAmount ?? this.totalAmount,
      receivedQuantity: receivedQuantity ?? this.receivedQuantity,
      createdAt: createdAt ?? this.createdAt,
      updatedAt: updatedAt ?? this.updatedAt,
    );
  }

  factory PurchaseOrderItem.fromJson(Map<String, dynamic> json) {
    final inventoryData = json['inventory'] as Map<String, dynamic>?;

    return PurchaseOrderItem(
      id: json['id'] as String? ?? '',
      purchaseOrderId: json['purchase_order_id'] as String? ?? '',
      inventoryId: json['inventory_id'] as String? ?? '',
      inventoryName: inventoryData?['name'] as String? ??
          json['inventory_name'] as String? ??
          '',
      inventoryUnit: inventoryData?['unit'] as String? ??
          json['inventory_unit'] as String? ??
          'units',
      inventorySku: inventoryData?['sku'] as String? ??
          json['inventory_sku'] as String?,
      quantity: (json['quantity'] as num?)?.toDouble() ?? 0.0,
      unitPrice: (json['unit_price'] as num?)?.toDouble() ?? 0.0,
      totalAmount: (json['total_amount'] as num?)?.toDouble() ?? 0.0,
      receivedQuantity:
          (json['received_quantity'] as num?)?.toDouble() ?? 0.0,
      createdAt: json['created_at'] != null
          ? DateTime.tryParse(json['created_at'] as String)
          : null,
      updatedAt: json['updated_at'] != null
          ? DateTime.tryParse(json['updated_at'] as String)
          : null,
    );
  }

  Map<String, dynamic> toJson({bool includeId = true}) {
    final map = <String, dynamic>{
      'purchase_order_id': purchaseOrderId,
      'inventory_id': inventoryId,
      'quantity': quantity,
      'unit_price': unitPrice,
      'total_amount': totalAmount,
      'received_quantity': receivedQuantity,
    };
    if (includeId && id.isNotEmpty) {
      map['id'] = id;
    }
    return map;
  }
}

/// Represents a Purchase Order placed with a supplier/vendor.
class PurchaseOrder {
  const PurchaseOrder({
    required this.id,
    required this.purchaseOrderNumber,
    required this.vendorId,
    this.vendorName,
    this.vendorPhone,
    required this.orderDate,
    this.expectedDeliveryDate,
    this.actualDeliveryDate,
    this.status = PurchaseOrderStatus.draft,
    this.subtotal = 0.0,
    required this.totalAmount,
    this.notes,
    this.createdBy,
    this.createdByName,
    this.items = const [],
    this.createdAt,
    this.updatedAt,
  });

  final String id;
  final String purchaseOrderNumber;
  final String vendorId;
  final String? vendorName;
  final String? vendorPhone;
  final DateTime orderDate;
  final DateTime? expectedDeliveryDate;
  final DateTime? actualDeliveryDate;
  final PurchaseOrderStatus status;
  final double subtotal;
  final double totalAmount;
  final String? notes;
  final String? createdBy;
  final String? createdByName;
  final List<PurchaseOrderItem> items;
  final DateTime? createdAt;
  final DateTime? updatedAt;

  bool get canEdit =>
      status == PurchaseOrderStatus.draft || status == PurchaseOrderStatus.ordered;

  bool get canCancel =>
      status == PurchaseOrderStatus.draft || status == PurchaseOrderStatus.ordered;

  bool get canReceive =>
      status == PurchaseOrderStatus.ordered ||
      status == PurchaseOrderStatus.partiallyReceived;

  bool get isDraft => status == PurchaseOrderStatus.draft;
  bool get isOrdered => status == PurchaseOrderStatus.ordered;
  bool get isPartiallyReceived => status == PurchaseOrderStatus.partiallyReceived;
  bool get isReceived => status == PurchaseOrderStatus.received;
  bool get isCancelled => status == PurchaseOrderStatus.cancelled;

  /// Returns true if expected delivery date is null or on/after order date (date-only comparison).
  bool get hasValidDates {
    if (expectedDeliveryDate == null) return true;
    final oDate = DateTime(orderDate.year, orderDate.month, orderDate.day);
    final dDate = DateTime(
      expectedDeliveryDate!.year,
      expectedDeliveryDate!.month,
      expectedDeliveryDate!.day,
    );
    return !dDate.isBefore(oDate);
  }

  String get formattedTotal => '₹${totalAmount.toStringAsFixed(2)}';

  double get totalOrderedQuantity =>
      items.fold(0.0, (sum, item) => sum + item.quantity);

  double get totalReceivedQuantity =>
      items.fold(0.0, (sum, item) => sum + item.receivedQuantity);

  double get totalRemainingQuantity =>
      items.fold(0.0, (sum, item) => sum + item.remainingQuantity);

  PurchaseOrder copyWith({
    String? id,
    String? purchaseOrderNumber,
    String? vendorId,
    String? vendorName,
    String? vendorPhone,
    DateTime? orderDate,
    DateTime? expectedDeliveryDate,
    DateTime? actualDeliveryDate,
    PurchaseOrderStatus? status,
    double? subtotal,
    double? totalAmount,
    String? notes,
    String? createdBy,
    String? createdByName,
    List<PurchaseOrderItem>? items,
    DateTime? createdAt,
    DateTime? updatedAt,
  }) {
    return PurchaseOrder(
      id: id ?? this.id,
      purchaseOrderNumber: purchaseOrderNumber ?? this.purchaseOrderNumber,
      vendorId: vendorId ?? this.vendorId,
      vendorName: vendorName ?? this.vendorName,
      vendorPhone: vendorPhone ?? this.vendorPhone,
      orderDate: orderDate ?? this.orderDate,
      expectedDeliveryDate: expectedDeliveryDate ?? this.expectedDeliveryDate,
      actualDeliveryDate: actualDeliveryDate ?? this.actualDeliveryDate,
      status: status ?? this.status,
      subtotal: subtotal ?? this.subtotal,
      totalAmount: totalAmount ?? this.totalAmount,
      notes: notes ?? this.notes,
      createdBy: createdBy ?? this.createdBy,
      createdByName: createdByName ?? this.createdByName,
      items: items ?? this.items,
      createdAt: createdAt ?? this.createdAt,
      updatedAt: updatedAt ?? this.updatedAt,
    );
  }

  factory PurchaseOrder.fromJson(Map<String, dynamic> json) {
    final vendorData = json['vendors'] as Map<String, dynamic>?;
    final profileData = json['profiles'] as Map<String, dynamic>?;
    final itemsList = (json['purchase_order_items'] as List<dynamic>?)
            ?.map((e) => PurchaseOrderItem.fromJson(e as Map<String, dynamic>))
            .toList() ??
        const [];

    return PurchaseOrder(
      id: json['id'] as String? ?? '',
      purchaseOrderNumber: json['purchase_order_number'] as String? ?? '',
      vendorId: json['vendor_id'] as String? ?? '',
      vendorName: vendorData?['name'] as String? ??
          json['vendor_name'] as String?,
      vendorPhone: vendorData?['phone'] as String? ??
          json['vendor_phone'] as String?,
      orderDate: json['order_date'] != null
          ? DateTime.tryParse(json['order_date'] as String) ?? DateTime.now()
          : DateTime.now(),
      expectedDeliveryDate: json['expected_delivery_date'] != null
          ? DateTime.tryParse(json['expected_delivery_date'] as String)
          : null,
      actualDeliveryDate: json['actual_delivery_date'] != null
          ? DateTime.tryParse(json['actual_delivery_date'] as String)
          : null,
      status: PurchaseOrderStatus.fromString(
          json['status'] as String? ?? 'draft'),
      subtotal: (json['subtotal'] as num?)?.toDouble() ?? 0.0,
      totalAmount: (json['total_amount'] as num?)?.toDouble() ?? 0.0,
      notes: json['notes'] as String?,
      createdBy: json['created_by'] as String?,
      createdByName: profileData?['full_name'] as String? ??
          json['created_by_name'] as String?,
      items: itemsList,
      createdAt: json['created_at'] != null
          ? DateTime.tryParse(json['created_at'] as String)
          : null,
      updatedAt: json['updated_at'] != null
          ? DateTime.tryParse(json['updated_at'] as String)
          : null,
    );
  }

  Map<String, dynamic> toJson({bool includeId = true}) {
    final map = <String, dynamic>{
      'purchase_order_number': purchaseOrderNumber,
      'vendor_id': vendorId,
      'order_date': orderDate.toIso8601String().split('T').first,
      'expected_delivery_date':
          expectedDeliveryDate?.toIso8601String().split('T').first,
      'actual_delivery_date':
          actualDeliveryDate?.toIso8601String().split('T').first,
      'status': status.dbValue,
      'subtotal': subtotal,
      'total_amount': totalAmount,
      'notes': notes,
    };
    if (includeId && id.isNotEmpty) {
      map['id'] = id;
    }
    if (createdBy != null && createdBy!.isNotEmpty) {
      map['created_by'] = createdBy;
    }
    return map;
  }
}
