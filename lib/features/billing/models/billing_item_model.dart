class BillingItemModel {
  final String? id;
  final String? billingId;
  final String? serviceId;
  final String serviceName;
  final int quantity;
  final double unitPrice;
  final double totalAmount;
  final bool isCustom;
  final DateTime? createdAt;

  const BillingItemModel({
    this.id,
    this.billingId,
    this.serviceId,
    required this.serviceName,
    this.quantity = 1,
    this.unitPrice = 0.0,
    double? totalAmount,
    this.isCustom = false,
    this.createdAt,
  }) : totalAmount = totalAmount ?? (quantity * unitPrice);

  factory BillingItemModel.fromJson(Map<String, dynamic> json) {
    final qty = (json['quantity'] as num?)?.toInt() ?? 1;
    final price = (json['unit_price'] as num?)?.toDouble() ?? 0.0;
    return BillingItemModel(
      id: json['id'] as String?,
      billingId: json['billing_id'] as String?,
      serviceId: json['service_id'] as String?,
      serviceName: json['service_name'] as String? ?? '',
      quantity: qty,
      unitPrice: price,
      totalAmount: (json['total_amount'] as num?)?.toDouble() ?? (qty * price),
      isCustom: json['is_custom'] as bool? ?? false,
      createdAt: json['created_at'] != null
          ? DateTime.tryParse(json['created_at'] as String)
          : null,
    );
  }

  Map<String, dynamic> toJson() {
    return {
      if (id != null) 'id': id,
      if (billingId != null) 'billing_id': billingId,
      'service_id': serviceId,
      'service_name': serviceName,
      'quantity': quantity,
      'unit_price': unitPrice,
      'total_amount': totalAmount,
      'is_custom': isCustom,
      if (createdAt != null) 'created_at': createdAt?.toIso8601String(),
    };
  }

  Map<String, dynamic> toRpcJson() {
    return {
      'service_id': serviceId,
      'service_name': serviceName.trim(),
      'quantity': quantity,
      'unit_price': unitPrice,
      'is_custom': isCustom,
    };
  }

  BillingItemModel copyWith({
    String? id,
    String? billingId,
    String? serviceId,
    String? serviceName,
    int? quantity,
    double? unitPrice,
    double? totalAmount,
    bool? isCustom,
    DateTime? createdAt,
  }) {
    final newQty = quantity ?? this.quantity;
    final newPrice = unitPrice ?? this.unitPrice;
    return BillingItemModel(
      id: id ?? this.id,
      billingId: billingId ?? this.billingId,
      serviceId: serviceId ?? this.serviceId,
      serviceName: serviceName ?? this.serviceName,
      quantity: newQty,
      unitPrice: newPrice,
      totalAmount: totalAmount ?? (newQty * newPrice),
      isCustom: isCustom ?? this.isCustom,
      createdAt: createdAt ?? this.createdAt,
    );
  }
}
