import 'billing_item_model.dart';
import 'billing_payment_model.dart';

class BillingInvoiceModel {
  final String id;
  final String invoiceNumber;
  final String patientId;
  final String department;
  final double subtotal;
  final double discount;
  final double totalAmount;
  final String paymentStatus;
  final String? paymentMode;
  final double amountPaid;
  final String? billedBy;
  final String? notes;
  final DateTime createdAt;
  final DateTime updatedAt;

  // Joined/enriched fields
  final String? patientName;
  final String? patientNumber;
  final String? patientMobile;
  final List<BillingItemModel> items;
  final List<BillingPaymentModel> payments;

  const BillingInvoiceModel({
    required this.id,
    required this.invoiceNumber,
    required this.patientId,
    required this.department,
    required this.subtotal,
    this.discount = 0.0,
    required this.totalAmount,
    this.paymentStatus = 'pending',
    this.paymentMode,
    this.amountPaid = 0.0,
    this.billedBy,
    this.notes,
    required this.createdAt,
    required this.updatedAt,
    this.patientName,
    this.patientNumber,
    this.patientMobile,
    this.items = const [],
    this.payments = const [],
  });

  double get remainingAmount => (totalAmount - amountPaid).clamp(0.0, double.infinity);
  bool get isPaid => paymentStatus == 'paid' || (amountPaid >= totalAmount && totalAmount > 0);
  bool get isPartiallyPaid => paymentStatus == 'partially_paid';
  bool get isPending => paymentStatus == 'pending';
  bool get isCancelled => paymentStatus == 'cancelled';

  factory BillingInvoiceModel.fromJson(Map<String, dynamic> json) {
    final patientJson = json['patients'] as Map<String, dynamic>?;
    final itemsList = (json['billing_items'] as List?)
            ?.map((e) => BillingItemModel.fromJson(e as Map<String, dynamic>))
            .toList() ??
        const [];
    final paymentsList = (json['billing_payments'] as List?)
            ?.map((e) => BillingPaymentModel.fromJson(e as Map<String, dynamic>))
            .toList() ??
        const [];

    return BillingInvoiceModel(
      id: json['id'] as String,
      invoiceNumber: json['invoice_number'] as String? ?? '',
      patientId: json['patient_id'] as String? ?? '',
      department: (json['department'] as String? ?? 'eye').toLowerCase(),
      subtotal: (json['subtotal'] as num?)?.toDouble() ?? 0.0,
      discount: (json['discount'] as num?)?.toDouble() ?? 0.0,
      totalAmount: (json['total_amount'] as num?)?.toDouble() ?? 0.0,
      paymentStatus: (json['payment_status'] as String? ?? 'pending').toLowerCase(),
      paymentMode: json['payment_mode'] as String?,
      amountPaid: (json['amount_paid'] as num?)?.toDouble() ?? 0.0,
      billedBy: json['billed_by'] as String?,
      notes: json['notes'] as String?,
      createdAt: json['created_at'] != null
          ? DateTime.parse(json['created_at'] as String)
          : DateTime.now(),
      updatedAt: json['updated_at'] != null
          ? DateTime.parse(json['updated_at'] as String)
          : DateTime.now(),
      patientName: patientJson != null ? patientJson['name'] as String? : json['patient_name'] as String?,
      patientNumber: patientJson != null ? patientJson['patient_number'] as String? : json['patient_number'] as String?,
      patientMobile: patientJson != null ? patientJson['mobile'] as String? : json['patient_mobile'] as String?,
      items: itemsList,
      payments: paymentsList,
    );
  }

  Map<String, dynamic> toJson() {
    return {
      'id': id,
      'invoice_number': invoiceNumber,
      'patient_id': patientId,
      'department': department,
      'subtotal': subtotal,
      'discount': discount,
      'total_amount': totalAmount,
      'payment_status': paymentStatus,
      'payment_mode': paymentMode,
      'amount_paid': amountPaid,
      'billed_by': billedBy,
      'notes': notes,
      'created_at': createdAt.toIso8601String(),
      'updated_at': updatedAt.toIso8601String(),
      if (patientName != null) 'patient_name': patientName,
      if (patientNumber != null) 'patient_number': patientNumber,
      if (patientMobile != null) 'patient_mobile': patientMobile,
    };
  }

  BillingInvoiceModel copyWith({
    String? id,
    String? invoiceNumber,
    String? patientId,
    String? department,
    double? subtotal,
    double? discount,
    double? totalAmount,
    String? paymentStatus,
    String? paymentMode,
    double? amountPaid,
    String? billedBy,
    String? notes,
    DateTime? createdAt,
    DateTime? updatedAt,
    String? patientName,
    String? patientNumber,
    String? patientMobile,
    List<BillingItemModel>? items,
    List<BillingPaymentModel>? payments,
  }) {
    return BillingInvoiceModel(
      id: id ?? this.id,
      invoiceNumber: invoiceNumber ?? this.invoiceNumber,
      patientId: patientId ?? this.patientId,
      department: department ?? this.department,
      subtotal: subtotal ?? this.subtotal,
      discount: discount ?? this.discount,
      totalAmount: totalAmount ?? this.totalAmount,
      paymentStatus: paymentStatus ?? this.paymentStatus,
      paymentMode: paymentMode ?? this.paymentMode,
      amountPaid: amountPaid ?? this.amountPaid,
      billedBy: billedBy ?? this.billedBy,
      notes: notes ?? this.notes,
      createdAt: createdAt ?? this.createdAt,
      updatedAt: updatedAt ?? this.updatedAt,
      patientName: patientName ?? this.patientName,
      patientNumber: patientNumber ?? this.patientNumber,
      patientMobile: patientMobile ?? this.patientMobile,
      items: items ?? this.items,
      payments: payments ?? this.payments,
    );
  }
}
