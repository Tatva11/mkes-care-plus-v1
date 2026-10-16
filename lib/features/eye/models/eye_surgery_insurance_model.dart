import 'package:flutter/foundation.dart';

/// Supported insurance arrangements exclusively for Eye Surgery
enum EyeSurgeryInsuranceArrangement {
  cashless,
  reimbursement;

  String get value => name;

  String get label {
    switch (this) {
      case EyeSurgeryInsuranceArrangement.cashless:
        return 'Cashless';
      case EyeSurgeryInsuranceArrangement.reimbursement:
        return 'Reimbursement';
    }
  }

  static EyeSurgeryInsuranceArrangement fromString(String? val) {
    if (val?.toLowerCase().trim() == 'reimbursement') {
      return EyeSurgeryInsuranceArrangement.reimbursement;
    }
    return EyeSurgeryInsuranceArrangement.cashless;
  }
}

/// Supported insurance claim statuses
enum EyeSurgeryClaimStatus {
  notSubmitted('not_submitted', 'Not Submitted'),
  submitted('submitted', 'Submitted'),
  underReview('under_review', 'Under Review'),
  approved('approved', 'Approved'),
  partiallyApproved('partially_approved', 'Partially Approved'),
  rejected('rejected', 'Rejected'),
  settled('settled', 'Settled');

  final String value;
  final String label;

  const EyeSurgeryClaimStatus(this.value, this.label);

  static EyeSurgeryClaimStatus fromString(String? val) {
    final clean = val?.toLowerCase().trim() ?? '';
    for (final s in EyeSurgeryClaimStatus.values) {
      if (s.value == clean) return s;
    }
    return EyeSurgeryClaimStatus.notSubmitted;
  }
}

/// Model representing Eye Surgery Insurance configuration & claim tracking
@immutable
class EyeSurgeryInsuranceModel {
  final String id;
  final String eyeSurgeryId;
  final String patientId;
  final String insuranceProvider;
  final EyeSurgeryInsuranceArrangement arrangement;
  final String? policyNumber;
  final String? memberId;
  final String? claimNumber;
  final String? coverageDetails;
  final double estimatedAmount;
  final double approvedAmount;
  final double amountReceived;
  final DateTime? claimSubmissionDate;
  final EyeSurgeryClaimStatus claimStatus;
  final String? notes;
  final String? rejectionReason;
  final DateTime createdAt;
  final DateTime updatedAt;
  final List<EyeSurgeryInsurancePaymentModel> payments;

  const EyeSurgeryInsuranceModel({
    required this.id,
    required this.eyeSurgeryId,
    required this.patientId,
    required this.insuranceProvider,
    required this.arrangement,
    this.policyNumber,
    this.memberId,
    this.claimNumber,
    this.coverageDetails,
    this.estimatedAmount = 0.0,
    this.approvedAmount = 0.0,
    this.amountReceived = 0.0,
    this.claimSubmissionDate,
    this.claimStatus = EyeSurgeryClaimStatus.notSubmitted,
    this.notes,
    this.rejectionReason,
    required this.createdAt,
    required this.updatedAt,
    this.payments = const [],
  });

  bool get isCashless => arrangement == EyeSurgeryInsuranceArrangement.cashless;
  bool get isReimbursement => arrangement == EyeSurgeryInsuranceArrangement.reimbursement;

  bool get isApproved =>
      claimStatus == EyeSurgeryClaimStatus.approved ||
      claimStatus == EyeSurgeryClaimStatus.partiallyApproved;

  bool get isPartiallyApproved => claimStatus == EyeSurgeryClaimStatus.partiallyApproved;
  bool get isRejected => claimStatus == EyeSurgeryClaimStatus.rejected;
  bool get isSettled => claimStatus == EyeSurgeryClaimStatus.settled;

  /// Sum of all payments received by the clinic from insurer
  double get totalClinicPaymentsReceived => payments
      .where((p) => p.paymentDestination == 'clinic')
      .fold<double>(0.0, (acc, p) => acc + p.amount);

  /// Sum of all reimbursements paid directly to the patient
  double get totalPatientReimbursementsReceived => payments
      .where((p) => p.paymentDestination == 'patient')
      .fold<double>(0.0, (acc, p) => acc + p.amount);

  factory EyeSurgeryInsuranceModel.fromJson(Map<String, dynamic> json) {
    final paymentsJson = json['eye_surgery_insurance_payments'] as List?;
    final paymentsList = paymentsJson != null
        ? paymentsJson
            .map((e) => EyeSurgeryInsurancePaymentModel.fromJson(e as Map<String, dynamic>))
            .toList()
        : const <EyeSurgeryInsurancePaymentModel>[];

    return EyeSurgeryInsuranceModel(
      id: json['id'] as String? ?? '',
      eyeSurgeryId: json['eye_surgery_id'] as String? ?? '',
      patientId: json['patient_id'] as String? ?? '',
      insuranceProvider: json['insurance_provider'] as String? ?? '',
      arrangement: EyeSurgeryInsuranceArrangement.fromString(json['arrangement'] as String?),
      policyNumber: json['policy_number'] as String?,
      memberId: json['member_id'] as String?,
      claimNumber: json['claim_number'] as String?,
      coverageDetails: json['coverage_details'] as String?,
      estimatedAmount: (json['estimated_amount'] as num?)?.toDouble() ?? 0.0,
      approvedAmount: (json['approved_amount'] as num?)?.toDouble() ?? 0.0,
      amountReceived: (json['amount_received'] as num?)?.toDouble() ?? 0.0,
      claimSubmissionDate: json['claim_submission_date'] != null
          ? DateTime.tryParse(json['claim_submission_date'] as String)
          : null,
      claimStatus: EyeSurgeryClaimStatus.fromString(json['claim_status'] as String?),
      notes: json['notes'] as String?,
      rejectionReason: json['rejection_reason'] as String?,
      createdAt: json['created_at'] != null
          ? DateTime.tryParse(json['created_at'] as String) ?? DateTime.now()
          : DateTime.now(),
      updatedAt: json['updated_at'] != null
          ? DateTime.tryParse(json['updated_at'] as String) ?? DateTime.now()
          : DateTime.now(),
      payments: paymentsList,
    );
  }

  Map<String, dynamic> toJson() {
    return {
      'id': id,
      'eye_surgery_id': eyeSurgeryId,
      'patient_id': patientId,
      'insurance_provider': insuranceProvider,
      'arrangement': arrangement.value,
      'policy_number': policyNumber,
      'member_id': memberId,
      'claim_number': claimNumber,
      'coverage_details': coverageDetails,
      'estimated_amount': estimatedAmount,
      'approved_amount': approvedAmount,
      'amount_received': amountReceived,
      'claim_submission_date': claimSubmissionDate != null
          ? '${claimSubmissionDate!.year.toString().padLeft(4, '0')}-${claimSubmissionDate!.month.toString().padLeft(2, '0')}-${claimSubmissionDate!.day.toString().padLeft(2, '0')}'
          : null,
      'claim_status': claimStatus.value,
      'notes': notes,
      'rejection_reason': rejectionReason,
      'created_at': createdAt.toIso8601String(),
      'updated_at': updatedAt.toIso8601String(),
    };
  }

  Map<String, dynamic> toInsertJson() {
    final map = toJson()
      ..remove('id')
      ..remove('created_at')
      ..remove('updated_at');
    return map;
  }

  EyeSurgeryInsuranceModel copyWith({
    String? id,
    String? eyeSurgeryId,
    String? patientId,
    String? insuranceProvider,
    EyeSurgeryInsuranceArrangement? arrangement,
    String? policyNumber,
    String? memberId,
    String? claimNumber,
    String? coverageDetails,
    double? estimatedAmount,
    double? approvedAmount,
    double? amountReceived,
    DateTime? claimSubmissionDate,
    EyeSurgeryClaimStatus? claimStatus,
    String? notes,
    String? rejectionReason,
    DateTime? createdAt,
    DateTime? updatedAt,
    List<EyeSurgeryInsurancePaymentModel>? payments,
  }) {
    return EyeSurgeryInsuranceModel(
      id: id ?? this.id,
      eyeSurgeryId: eyeSurgeryId ?? this.eyeSurgeryId,
      patientId: patientId ?? this.patientId,
      insuranceProvider: insuranceProvider ?? this.insuranceProvider,
      arrangement: arrangement ?? this.arrangement,
      policyNumber: policyNumber ?? this.policyNumber,
      memberId: memberId ?? this.memberId,
      claimNumber: claimNumber ?? this.claimNumber,
      coverageDetails: coverageDetails ?? this.coverageDetails,
      estimatedAmount: estimatedAmount ?? this.estimatedAmount,
      approvedAmount: approvedAmount ?? this.approvedAmount,
      amountReceived: amountReceived ?? this.amountReceived,
      claimSubmissionDate: claimSubmissionDate ?? this.claimSubmissionDate,
      claimStatus: claimStatus ?? this.claimStatus,
      notes: notes ?? this.notes,
      rejectionReason: rejectionReason ?? this.rejectionReason,
      createdAt: createdAt ?? this.createdAt,
      updatedAt: updatedAt ?? this.updatedAt,
      payments: payments ?? this.payments,
    );
  }
}

/// Model representing an individual payment from insurer (or patient reimbursement receipt)
@immutable
class EyeSurgeryInsurancePaymentModel {
  final String? id;
  final String insuranceId;
  final String eyeSurgeryId;
  final double amount;
  final DateTime paymentDate;
  final String? paymentReference;
  final String paymentDestination; // 'clinic' | 'patient'
  final String paymentMode; // 'bank_transfer' | 'upi' | 'cheque' | 'other'
  final String? notes;
  final String? recordedBy;
  final DateTime? createdAt;

  const EyeSurgeryInsurancePaymentModel({
    this.id,
    required this.insuranceId,
    required this.eyeSurgeryId,
    required this.amount,
    required this.paymentDate,
    this.paymentReference,
    this.paymentDestination = 'clinic',
    this.paymentMode = 'bank_transfer',
    this.notes,
    this.recordedBy,
    this.createdAt,
  });

  bool get isClinicDestination => paymentDestination == 'clinic';
  bool get isPatientDestination => paymentDestination == 'patient';

  factory EyeSurgeryInsurancePaymentModel.fromJson(Map<String, dynamic> json) {
    return EyeSurgeryInsurancePaymentModel(
      id: json['id'] as String?,
      insuranceId: json['insurance_id'] as String? ?? '',
      eyeSurgeryId: json['eye_surgery_id'] as String? ?? '',
      amount: (json['amount'] as num?)?.toDouble() ?? 0.0,
      paymentDate: json['payment_date'] != null
          ? DateTime.tryParse(json['payment_date'] as String) ?? DateTime.now()
          : DateTime.now(),
      paymentReference: json['payment_reference'] as String?,
      paymentDestination: json['payment_destination'] as String? ?? 'clinic',
      paymentMode: json['payment_mode'] as String? ?? 'bank_transfer',
      notes: json['notes'] as String?,
      recordedBy: json['recorded_by'] as String?,
      createdAt: json['created_at'] != null
          ? DateTime.tryParse(json['created_at'] as String)
          : null,
    );
  }

  Map<String, dynamic> toJson() {
    return {
      if (id != null) 'id': id,
      'insurance_id': insuranceId,
      'eye_surgery_id': eyeSurgeryId,
      'amount': amount,
      'payment_date':
          '${paymentDate.year.toString().padLeft(4, '0')}-${paymentDate.month.toString().padLeft(2, '0')}-${paymentDate.day.toString().padLeft(2, '0')}',
      'payment_reference': paymentReference,
      'payment_destination': paymentDestination,
      'payment_mode': paymentMode,
      'notes': notes,
      if (recordedBy != null) 'recorded_by': recordedBy,
      if (createdAt != null) 'created_at': createdAt!.toIso8601String(),
    };
  }

  EyeSurgeryInsurancePaymentModel copyWith({
    String? id,
    String? insuranceId,
    String? eyeSurgeryId,
    double? amount,
    DateTime? paymentDate,
    String? paymentReference,
    String? paymentDestination,
    String? paymentMode,
    String? notes,
    String? recordedBy,
    DateTime? createdAt,
  }) {
    return EyeSurgeryInsurancePaymentModel(
      id: id ?? this.id,
      insuranceId: insuranceId ?? this.insuranceId,
      eyeSurgeryId: eyeSurgeryId ?? this.eyeSurgeryId,
      amount: amount ?? this.amount,
      paymentDate: paymentDate ?? this.paymentDate,
      paymentReference: paymentReference ?? this.paymentReference,
      paymentDestination: paymentDestination ?? this.paymentDestination,
      paymentMode: paymentMode ?? this.paymentMode,
      notes: notes ?? this.notes,
      recordedBy: recordedBy ?? this.recordedBy,
      createdAt: createdAt ?? this.createdAt,
    );
  }
}

/// Authoritative financial breakdown for Eye Surgery adhering to Section 4 rules:
/// 1. Total surgery bill
/// 2. Estimated insurance coverage
/// 3. Approved insurance coverage
/// 4. Insurance amount actually received by the clinic
/// 5. Insurance amount still pending (where applicable)
/// 6. Patient's payable share
/// 7. Patient payments received
/// 8. Remaining patient balance
@immutable
class EyeSurgeryFinancialSummary {
  final double totalSurgeryBill;
  final double estimatedInsuranceCoverage;
  final double approvedInsuranceCoverage;
  final double insuranceAmountReceivedByClinic;
  final double insuranceAmountPending;
  final double patientPayableShare;
  final double patientPaymentsReceived;
  final double remainingPatientBalance;
  final double patientReimbursementReceived;
  final EyeSurgeryInsuranceArrangement? arrangement;
  final EyeSurgeryClaimStatus claimStatus;

  const EyeSurgeryFinancialSummary({
    required this.totalSurgeryBill,
    required this.estimatedInsuranceCoverage,
    required this.approvedInsuranceCoverage,
    required this.insuranceAmountReceivedByClinic,
    required this.insuranceAmountPending,
    required this.patientPayableShare,
    required this.patientPaymentsReceived,
    required this.remainingPatientBalance,
    this.patientReimbursementReceived = 0.0,
    this.arrangement,
    this.claimStatus = EyeSurgeryClaimStatus.notSubmitted,
  });

  bool get hasInsurance => arrangement != null;
  bool get isCashless => arrangement == EyeSurgeryInsuranceArrangement.cashless;
  bool get isReimbursement => arrangement == EyeSurgeryInsuranceArrangement.reimbursement;

  /// Pure functional calculation adhering strictly to Section 4 financial rules
  factory EyeSurgeryFinancialSummary.calculate({
    required double surgeryBill,
    EyeSurgeryInsuranceModel? insurance,
    double patientPayments = 0.0,
  }) {
    final bill = (surgeryBill < 0 ? 0.0 : surgeryBill);
    final patientPaid = (patientPayments < 0 ? 0.0 : patientPayments);

    if (insurance == null) {
      final rem = (bill - patientPaid).clamp(0.0, double.infinity);
      return EyeSurgeryFinancialSummary(
        totalSurgeryBill: bill,
        estimatedInsuranceCoverage: 0.0,
        approvedInsuranceCoverage: 0.0,
        insuranceAmountReceivedByClinic: 0.0,
        insuranceAmountPending: 0.0,
        patientPayableShare: bill,
        patientPaymentsReceived: patientPaid,
        remainingPatientBalance: rem,
        claimStatus: EyeSurgeryClaimStatus.notSubmitted,
      );
    }

    final estimated = insurance.estimatedAmount;
    final approved = insurance.isApproved ? insurance.approvedAmount : 0.0;
    final clinicReceived = insurance.amountReceived > 0
        ? insurance.amountReceived
        : insurance.totalClinicPaymentsReceived;

    if (insurance.isCashless) {
      // In Cashless:
      // Insurer covers approved amount.
      // Insurer pending amount = Approved insurance - Insurance received by clinic.
      final insurerPending = (approved - clinicReceived).clamp(0.0, double.infinity);

      // Patient payable share:
      // If approved, patient pays the remainder: Total bill - approved
      // If rejected or not approved, patient share is the full bill.
      final patientShare = insurance.isApproved
          ? (bill - approved).clamp(0.0, bill)
          : bill;

      // Remaining patient balance = patient's share - patient payments received.
      // Critical: Pending insurer amount is NOT added to patient balance!
      final remPatient = (patientShare - patientPaid).clamp(0.0, double.infinity);

      return EyeSurgeryFinancialSummary(
        totalSurgeryBill: bill,
        estimatedInsuranceCoverage: estimated,
        approvedInsuranceCoverage: approved,
        insuranceAmountReceivedByClinic: clinicReceived,
        insuranceAmountPending: insurerPending,
        patientPayableShare: patientShare,
        patientPaymentsReceived: patientPaid,
        remainingPatientBalance: remPatient,
        patientReimbursementReceived: 0.0,
        arrangement: EyeSurgeryInsuranceArrangement.cashless,
        claimStatus: insurance.claimStatus,
      );
    } else {
      // In Reimbursement:
      // The patient pays the clinic directly.
      // Patient payable share = Total surgery bill.
      // Insurer does NOT pay clinic directly, so clinic insurer pending is 0.
      final remPatient = (bill - patientPaid).clamp(0.0, double.infinity);
      final patientReimbursed = insurance.totalPatientReimbursementsReceived;

      return EyeSurgeryFinancialSummary(
        totalSurgeryBill: bill,
        estimatedInsuranceCoverage: estimated,
        approvedInsuranceCoverage: insurance.approvedAmount,
        insuranceAmountReceivedByClinic: clinicReceived,
        insuranceAmountPending: 0.0,
        patientPayableShare: bill,
        patientPaymentsReceived: patientPaid,
        remainingPatientBalance: remPatient,
        patientReimbursementReceived: patientReimbursed,
        arrangement: EyeSurgeryInsuranceArrangement.reimbursement,
        claimStatus: insurance.claimStatus,
      );
    }
  }
}
