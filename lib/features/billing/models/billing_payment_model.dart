class BillingPaymentModel {
  final String? id;
  final String? billingId;
  final double amount;
  final String paymentMode;
  final String? paymentReference;
  final DateTime? paidAt;
  final String? recordedBy;
  final String? notes;
  final DateTime? createdAt;

  const BillingPaymentModel({
    this.id,
    this.billingId,
    required this.amount,
    required this.paymentMode,
    this.paymentReference,
    this.paidAt,
    this.recordedBy,
    this.notes,
    this.createdAt,
  });

  factory BillingPaymentModel.fromJson(Map<String, dynamic> json) {
    return BillingPaymentModel(
      id: json['id'] as String?,
      billingId: json['billing_id'] as String?,
      amount: (json['amount'] as num?)?.toDouble() ?? 0.0,
      paymentMode: (json['payment_mode'] as String? ?? 'cash').toLowerCase(),
      paymentReference: json['payment_reference'] as String?,
      paidAt: json['paid_at'] != null
          ? DateTime.tryParse(json['paid_at'] as String)
          : null,
      recordedBy: json['recorded_by'] as String?,
      notes: json['notes'] as String?,
      createdAt: json['created_at'] != null
          ? DateTime.tryParse(json['created_at'] as String)
          : null,
    );
  }

  Map<String, dynamic> toJson() {
    return {
      if (id != null) 'id': id,
      if (billingId != null) 'billing_id': billingId,
      'amount': amount,
      'payment_mode': paymentMode,
      'payment_reference': paymentReference,
      'paid_at': paidAt?.toIso8601String(),
      'recorded_by': recordedBy,
      'notes': notes,
      if (createdAt != null) 'created_at': createdAt?.toIso8601String(),
    };
  }

  Map<String, dynamic> toRpcJson() {
    return {
      'amount': amount,
      'payment_mode': paymentMode.toLowerCase(),
      'payment_reference': paymentReference?.trim(),
    };
  }

  BillingPaymentModel copyWith({
    String? id,
    String? billingId,
    double? amount,
    String? paymentMode,
    String? paymentReference,
    DateTime? paidAt,
    String? recordedBy,
    String? notes,
    DateTime? createdAt,
  }) {
    return BillingPaymentModel(
      id: id ?? this.id,
      billingId: billingId ?? this.billingId,
      amount: amount ?? this.amount,
      paymentMode: paymentMode ?? this.paymentMode,
      paymentReference: paymentReference ?? this.paymentReference,
      paidAt: paidAt ?? this.paidAt,
      recordedBy: recordedBy ?? this.recordedBy,
      notes: notes ?? this.notes,
      createdAt: createdAt ?? this.createdAt,
    );
  }
}
