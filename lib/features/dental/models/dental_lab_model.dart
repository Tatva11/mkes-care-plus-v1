import 'package:intl/intl.dart';
import '../../patients/models/patient_model.dart';

/// Represents a Dental Lab Case record in the `public.dental_lab` table.
class DentalLabModel {
  static const List<String> validStatuses = ['processing', 'ready', 'delivered'];

  final String id;
  final String? patientId;
  final String caseNumber;
  final String caseType;
  final String status; // 'processing' | 'ready' | 'delivered'
  final DateTime sentDate;
  final DateTime? readyDate;
  final DateTime? deliveredDate;
  final String? remarks;
  final DateTime createdAt;
  final DateTime updatedAt;

  // Joined patient fields
  final PatientModel? patient;
  final String? patientName;
  final String? patientNumber;
  final String? patientMobile;

  const DentalLabModel({
    required this.id,
    this.patientId,
    required this.caseNumber,
    required this.caseType,
    this.status = 'processing',
    required this.sentDate,
    this.readyDate,
    this.deliveredDate,
    this.remarks,
    required this.createdAt,
    required this.updatedAt,
    this.patient,
    this.patientName,
    this.patientNumber,
    this.patientMobile,
  });

  bool get isProcessing => status.toLowerCase() == 'processing';
  bool get isReady => status.toLowerCase() == 'ready';
  bool get isDelivered => status.toLowerCase() == 'delivered';

  String get statusLabel {
    switch (status.toLowerCase()) {
      case 'processing':
        return 'Processing';
      case 'ready':
        return 'Ready';
      case 'delivered':
        return 'Delivered';
      default:
        return status;
    }
  }

  /// Validates date consistency. Returns null if valid, or an error message if invalid.
  static String? validateDates({
    required DateTime sentDate,
    DateTime? readyDate,
    DateTime? deliveredDate,
  }) {
    final sentDay = DateTime(sentDate.year, sentDate.month, sentDate.day);

    if (readyDate != null) {
      final readyDay = DateTime(readyDate.year, readyDate.month, readyDate.day);
      if (readyDay.isBefore(sentDay)) {
        return 'Ready date cannot be before sent date.';
      }
    }

    if (deliveredDate != null) {
      final deliveredDay = DateTime(deliveredDate.year, deliveredDate.month, deliveredDate.day);
      if (deliveredDay.isBefore(sentDay)) {
        return 'Delivered date cannot be before sent date.';
      }
      if (readyDate != null) {
        final readyDay = DateTime(readyDate.year, readyDate.month, readyDate.day);
        if (deliveredDay.isBefore(readyDay)) {
          return 'Delivered date cannot be before ready date.';
        }
      }
    }

    return null;
  }

  factory DentalLabModel.fromJson(Map<String, dynamic> json) {
    final patientJson = json['patients'] is Map<String, dynamic>
        ? json['patients'] as Map<String, dynamic>
        : null;

    final patientObj = patientJson != null ? PatientModel.fromJson(patientJson) : null;

    final parsedSentDate = json['sent_date'] != null
        ? DateTime.tryParse(json['sent_date'] as String) ?? DateTime.now()
        : DateTime.now();

    final parsedReadyDate = json['ready_date'] != null
        ? DateTime.tryParse(json['ready_date'] as String)
        : null;

    final parsedDeliveredDate = json['delivered_date'] != null
        ? DateTime.tryParse(json['delivered_date'] as String)
        : null;

    return DentalLabModel(
      id: json['id'] as String? ?? '',
      patientId: json['patient_id'] as String?,
      caseNumber: json['case_number'] as String? ?? '',
      caseType: json['case_type'] as String? ?? '',
      status: json['status'] as String? ?? 'processing',
      sentDate: parsedSentDate,
      readyDate: parsedReadyDate,
      deliveredDate: parsedDeliveredDate,
      remarks: json['remarks'] as String?,
      createdAt: json['created_at'] != null
          ? DateTime.tryParse(json['created_at'] as String) ?? DateTime.now()
          : DateTime.now(),
      updatedAt: json['updated_at'] != null
          ? DateTime.tryParse(json['updated_at'] as String) ?? DateTime.now()
          : DateTime.now(),
      patient: patientObj,
      patientName: patientObj?.name ?? (json['patient_name'] as String?),
      patientNumber: patientObj?.patientNumber ?? (json['patient_number'] as String?),
      patientMobile: patientObj?.mobile ?? (json['patient_mobile'] as String?),
    );
  }

  Map<String, dynamic> toJson() {
    final formatter = DateFormat('yyyy-MM-dd');
    return {
      if (id.isNotEmpty) 'id': id,
      if (patientId != null) 'patient_id': patientId,
      'case_number': caseNumber,
      'case_type': caseType,
      'status': status,
      'sent_date': formatter.format(sentDate),
      if (readyDate != null) 'ready_date': formatter.format(readyDate!),
      if (deliveredDate != null) 'delivered_date': formatter.format(deliveredDate!),
      'remarks': remarks,
    };
  }

  DentalLabModel copyWith({
    String? id,
    String? patientId,
    String? caseNumber,
    String? caseType,
    String? status,
    DateTime? sentDate,
    DateTime? readyDate,
    DateTime? deliveredDate,
    String? remarks,
    DateTime? createdAt,
    DateTime? updatedAt,
    PatientModel? patient,
    String? patientName,
    String? patientNumber,
    String? patientMobile,
  }) {
    return DentalLabModel(
      id: id ?? this.id,
      patientId: patientId ?? this.patientId,
      caseNumber: caseNumber ?? this.caseNumber,
      caseType: caseType ?? this.caseType,
      status: status ?? this.status,
      sentDate: sentDate ?? this.sentDate,
      readyDate: readyDate ?? this.readyDate,
      deliveredDate: deliveredDate ?? this.deliveredDate,
      remarks: remarks ?? this.remarks,
      createdAt: createdAt ?? this.createdAt,
      updatedAt: updatedAt ?? this.updatedAt,
      patient: patient ?? this.patient,
      patientName: patientName ?? this.patientName,
      patientNumber: patientNumber ?? this.patientNumber,
      patientMobile: patientMobile ?? this.patientMobile,
    );
  }
}
