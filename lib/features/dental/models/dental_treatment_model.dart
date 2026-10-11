import 'package:intl/intl.dart';

/// Represents a Dental Clinical Treatment record in `public.dental_treatments`.
class DentalTreatmentModel {
  static const List<String> validStatuses = [
    'planned',
    'in_progress',
    'completed',
    'cancelled',
  ];

  const DentalTreatmentModel({
    required this.id,
    required this.patientId,
    this.appointmentId,
    this.dentalLabCaseId,
    required this.treatmentDate,
    this.treatmentTime,
    this.toothNumber,
    required this.procedurePerformed,
    this.treatmentNotes,
    this.diagnosis,
    this.procedureStatus = 'completed',
    this.createdBy,
    required this.createdAt,
    required this.updatedAt,
    this.patientName,
    this.patientNumber,
    this.appointmentDate,
    this.appointmentTime,
    this.appointmentStatus,
    this.dentalLabCaseNumber,
    this.dentalLabCaseType,
    this.createdByName,
  });

  final String id;
  final String patientId;
  final String? appointmentId;
  final String? dentalLabCaseId;
  final DateTime treatmentDate;
  final String? treatmentTime;
  final String? toothNumber;
  final String procedurePerformed;
  final String? treatmentNotes;
  final String? diagnosis;
  final String procedureStatus; // 'planned' | 'in_progress' | 'completed' | 'cancelled'
  final String? createdBy;
  final DateTime createdAt;
  final DateTime updatedAt;

  // Joined presentation data
  final String? patientName;
  final String? patientNumber;
  final DateTime? appointmentDate;
  final String? appointmentTime;
  final String? appointmentStatus;
  final String? dentalLabCaseNumber;
  final String? dentalLabCaseType;
  final String? createdByName;

  String get formattedDate =>
      DateFormat('dd MMM yyyy').format(treatmentDate);

  String? get formattedTime {
    if (treatmentTime == null || treatmentTime!.trim().isEmpty) return null;
    final parts = treatmentTime!.trim().split(':');
    if (parts.length >= 2) {
      final hour = int.tryParse(parts[0]);
      final minute = int.tryParse(parts[1]);
      if (hour != null && minute != null) {
        final period = hour >= 12 ? 'PM' : 'AM';
        final displayHour = hour == 0 ? 12 : (hour > 12 ? hour - 12 : hour);
        return '${displayHour.toString().padLeft(2, '0')}:${minute.toString().padLeft(2, '0')} $period';
      }
    }
    return treatmentTime;
  }

  String get statusDisplay {
    switch (procedureStatus.toLowerCase()) {
      case 'planned':
        return 'Planned';
      case 'in_progress':
        return 'In Progress';
      case 'completed':
        return 'Completed';
      case 'cancelled':
        return 'Cancelled';
      default:
        return procedureStatus;
    }
  }

  bool get isCompleted => procedureStatus.toLowerCase() == 'completed';
  bool get isInProgress => procedureStatus.toLowerCase() == 'in_progress';
  bool get isPlanned => procedureStatus.toLowerCase() == 'planned';
  bool get isCancelled => procedureStatus.toLowerCase() == 'cancelled';

  factory DentalTreatmentModel.fromJson(Map<String, dynamic> json) {
    final patientMap = _asStringMap(json['patients']);
    final appointmentMap = _asStringMap(json['appointments']);
    final labMap = _asStringMap(json['dental_lab']);
    final profileMap = _asStringMap(json['profiles']);

    final rawStatus = _stringValue(json['procedure_status'])?.toLowerCase() ?? 'completed';
    final safeStatus = validStatuses.contains(rawStatus) ? rawStatus : 'completed';

    return DentalTreatmentModel(
      id: _stringValue(json['id']) ?? '',
      patientId: _stringValue(json['patient_id']) ?? '',
      appointmentId: _stringValue(json['appointment_id']),
      dentalLabCaseId: _stringValue(json['dental_lab_case_id']),
      treatmentDate: _parseDate(json['treatment_date']),
      treatmentTime: _stringValue(json['treatment_time']),
      toothNumber: _stringValue(json['tooth_number']),
      procedurePerformed: _stringValue(json['procedure_performed']) ?? 'Procedure',
      treatmentNotes: _stringValue(json['treatment_notes']),
      diagnosis: _stringValue(json['diagnosis']),
      procedureStatus: safeStatus,
      createdBy: _stringValue(json['created_by']),
      createdAt: _parseTimestamp(json['created_at']) ?? DateTime.now(),
      updatedAt: _parseTimestamp(json['updated_at']) ?? DateTime.now(),
      patientName: _stringValue(patientMap?['name']) ??
          _stringValue(json['patient_name']),
      patientNumber: _stringValue(patientMap?['patient_number']) ??
          _stringValue(json['patient_number']),
      appointmentDate: _parseOptionalDate(appointmentMap?['appointment_date']),
      appointmentTime: _stringValue(appointmentMap?['appointment_time']),
      appointmentStatus: _stringValue(appointmentMap?['status']) ??
          _stringValue(json['appointment_status']),
      dentalLabCaseNumber: _stringValue(labMap?['case_number']) ??
          _stringValue(json['dental_lab_case_number']),
      dentalLabCaseType: _stringValue(labMap?['case_type']) ??
          _stringValue(json['dental_lab_case_type']),
      createdByName: _stringValue(profileMap?['full_name']) ??
          _stringValue(json['created_by_name']),
    );
  }

  factory DentalTreatmentModel.fromMap(Map<String, dynamic> map) =>
      DentalTreatmentModel.fromJson(map);

  Map<String, dynamic> toJson() => {
        'id': id,
        'patient_id': patientId,
        'appointment_id': appointmentId,
        'dental_lab_case_id': dentalLabCaseId,
        'treatment_date': _dateOnly(treatmentDate),
        'treatment_time': treatmentTime,
        'tooth_number': toothNumber,
        'procedure_performed': procedurePerformed,
        'treatment_notes': treatmentNotes,
        'diagnosis': diagnosis,
        'procedure_status': procedureStatus,
        'created_by': createdBy,
        'created_at': createdAt.toIso8601String(),
        'updated_at': updatedAt.toIso8601String(),
      };

  Map<String, dynamic> toInsertJson() {
    final map = toJson()
      ..remove('id')
      ..remove('created_at')
      ..remove('updated_at');
    return map;
  }

  DentalTreatmentModel copyWith({
    String? id,
    String? patientId,
    String? appointmentId,
    bool clearAppointmentId = false,
    String? dentalLabCaseId,
    bool clearDentalLabCaseId = false,
    DateTime? treatmentDate,
    String? treatmentTime,
    String? toothNumber,
    String? procedurePerformed,
    String? treatmentNotes,
    String? diagnosis,
    String? procedureStatus,
    String? createdBy,
    DateTime? createdAt,
    DateTime? updatedAt,
    String? patientName,
    String? patientNumber,
    DateTime? appointmentDate,
    String? appointmentTime,
    String? appointmentStatus,
    String? dentalLabCaseNumber,
    String? dentalLabCaseType,
    String? createdByName,
  }) {
    return DentalTreatmentModel(
      id: id ?? this.id,
      patientId: patientId ?? this.patientId,
      appointmentId: clearAppointmentId
          ? null
          : (appointmentId ?? this.appointmentId),
      dentalLabCaseId: clearDentalLabCaseId
          ? null
          : (dentalLabCaseId ?? this.dentalLabCaseId),
      treatmentDate: treatmentDate ?? this.treatmentDate,
      treatmentTime: treatmentTime ?? this.treatmentTime,
      toothNumber: toothNumber ?? this.toothNumber,
      procedurePerformed: procedurePerformed ?? this.procedurePerformed,
      treatmentNotes: treatmentNotes ?? this.treatmentNotes,
      diagnosis: diagnosis ?? this.diagnosis,
      procedureStatus: procedureStatus ?? this.procedureStatus,
      createdBy: createdBy ?? this.createdBy,
      createdAt: createdAt ?? this.createdAt,
      updatedAt: updatedAt ?? this.updatedAt,
      patientName: patientName ?? this.patientName,
      patientNumber: patientNumber ?? this.patientNumber,
      appointmentDate: clearAppointmentId
          ? null
          : (appointmentDate ?? this.appointmentDate),
      appointmentTime: clearAppointmentId
          ? null
          : (appointmentTime ?? this.appointmentTime),
      appointmentStatus: clearAppointmentId
          ? null
          : (appointmentStatus ?? this.appointmentStatus),
      dentalLabCaseNumber: clearDentalLabCaseId
          ? null
          : (dentalLabCaseNumber ?? this.dentalLabCaseNumber),
      dentalLabCaseType: clearDentalLabCaseId
          ? null
          : (dentalLabCaseType ?? this.dentalLabCaseType),
      createdByName: createdByName ?? this.createdByName,
    );
  }

  static String _dateOnly(DateTime date) =>
      '${date.year.toString().padLeft(4, '0')}-'
      '${date.month.toString().padLeft(2, '0')}-'
      '${date.day.toString().padLeft(2, '0')}';

  static String? _stringValue(Object? value) {
    if (value is! String) return null;
    final trimmed = value.trim();
    return trimmed.isEmpty ? null : trimmed;
  }

  static DateTime _parseDate(Object? value) {
    final parsed = _parseOptionalDate(value);
    if (parsed == null) {
      return DateTime.now();
    }
    return parsed;
  }

  static DateTime? _parseOptionalDate(Object? value) {
    if (value is DateTime) return value;
    if (value is String) return DateTime.tryParse(value);
    return null;
  }

  static DateTime? _parseTimestamp(Object? value) => _parseOptionalDate(value);

  static Map<String, dynamic>? _asStringMap(Object? value) {
    if (value is! Map) return null;
    return {
      for (final entry in value.entries)
        if (entry.key is String) entry.key as String: entry.value,
    };
  }
}
