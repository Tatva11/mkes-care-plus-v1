import 'package:intl/intl.dart';

/// Represents a Clinical Eye Examination record in `public.eye_examinations`.
class EyeExaminationModel {
  const EyeExaminationModel({
    required this.id,
    required this.patientId,
    this.appointmentId,
    this.eyeSurgeryId,
    required this.examinationDate,
    this.examinationTime,
    this.visualAcuityOd,
    this.visualAcuityOs,
    this.visualAcuity,
    this.intraocularPressureOd,
    this.intraocularPressureOs,
    this.intraocularPressure,
    this.slitLampExamination,
    this.diagnosis,
    this.clinicalNotes,
    this.createdBy,
    required this.createdAt,
    required this.updatedAt,
    this.patientName,
    this.patientNumber,
    this.appointmentDate,
    this.appointmentTime,
    this.createdByName,
  });

  final String id;
  final String patientId;
  final String? appointmentId;
  final String? eyeSurgeryId;
  final DateTime examinationDate;
  final String? examinationTime;
  final String? visualAcuityOd;
  final String? visualAcuityOs;
  final String? visualAcuity;
  final String? intraocularPressureOd;
  final String? intraocularPressureOs;
  final String? intraocularPressure;
  final String? slitLampExamination;
  final String? diagnosis;
  final String? clinicalNotes;
  final String? createdBy;
  final DateTime createdAt;
  final DateTime updatedAt;

  // Joined presentation data
  final String? patientName;
  final String? patientNumber;
  final DateTime? appointmentDate;
  final String? appointmentTime;
  final String? createdByName;

  String get formattedDate =>
      DateFormat('dd MMM yyyy').format(examinationDate);

  String? get formattedTime {
    if (examinationTime == null || examinationTime!.trim().isEmpty) return null;
    final parts = examinationTime!.trim().split(':');
    if (parts.length >= 2) {
      final hour = int.tryParse(parts[0]);
      final minute = int.tryParse(parts[1]);
      if (hour != null && minute != null) {
        final period = hour >= 12 ? 'PM' : 'AM';
        final displayHour = hour == 0 ? 12 : (hour > 12 ? hour - 12 : hour);
        return '${displayHour.toString().padLeft(2, '0')}:${minute.toString().padLeft(2, '0')} $period';
      }
    }
    return examinationTime;
  }

  bool get hasVisualAcuity =>
      (visualAcuityOd != null && visualAcuityOd!.trim().isNotEmpty) ||
      (visualAcuityOs != null && visualAcuityOs!.trim().isNotEmpty) ||
      (visualAcuity != null && visualAcuity!.trim().isNotEmpty);

  bool get hasIop =>
      (intraocularPressureOd != null &&
          intraocularPressureOd!.trim().isNotEmpty) ||
      (intraocularPressureOs != null &&
          intraocularPressureOs!.trim().isNotEmpty) ||
      (intraocularPressure != null &&
          intraocularPressure!.trim().isNotEmpty);

  bool get hasSlitLamp =>
      slitLampExamination != null && slitLampExamination!.trim().isNotEmpty;

  factory EyeExaminationModel.fromJson(Map<String, dynamic> json) {
    final patientMap = _asStringMap(json['patients']);
    final appointmentMap = _asStringMap(json['appointments']);
    final profileMap = _asStringMap(json['profiles']);

    return EyeExaminationModel(
      id: _stringValue(json['id']) ?? '',
      patientId: _stringValue(json['patient_id']) ?? '',
      appointmentId: _stringValue(json['appointment_id']),
      eyeSurgeryId: _stringValue(json['eye_surgery_id']),
      examinationDate: _parseDate(json['examination_date']),
      examinationTime: _stringValue(json['examination_time']),
      visualAcuityOd: _stringValue(json['visual_acuity_od']),
      visualAcuityOs: _stringValue(json['visual_acuity_os']),
      visualAcuity: _stringValue(json['visual_acuity']),
      intraocularPressureOd: _stringValue(json['intraocular_pressure_od']),
      intraocularPressureOs: _stringValue(json['intraocular_pressure_os']),
      intraocularPressure: _stringValue(json['intraocular_pressure']),
      slitLampExamination: _stringValue(json['slit_lamp_examination']),
      diagnosis: _stringValue(json['diagnosis']),
      clinicalNotes: _stringValue(json['clinical_notes']),
      createdBy: _stringValue(json['created_by']),
      createdAt: _parseTimestamp(json['created_at']) ?? DateTime.now(),
      updatedAt: _parseTimestamp(json['updated_at']) ?? DateTime.now(),
      patientName: _stringValue(patientMap?['name']) ??
          _stringValue(json['patient_name']),
      patientNumber: _stringValue(patientMap?['patient_number']) ??
          _stringValue(json['patient_number']),
      appointmentDate: _parseOptionalDate(appointmentMap?['appointment_date']),
      appointmentTime: _stringValue(appointmentMap?['appointment_time']),
      createdByName: _stringValue(profileMap?['full_name']) ??
          _stringValue(json['created_by_name']),
    );
  }

  factory EyeExaminationModel.fromMap(Map<String, dynamic> map) =>
      EyeExaminationModel.fromJson(map);

  Map<String, dynamic> toJson() => {
        'id': id,
        'patient_id': patientId,
        'appointment_id': appointmentId,
        'eye_surgery_id': eyeSurgeryId,
        'examination_date': _dateOnly(examinationDate),
        'examination_time': examinationTime,
        'visual_acuity_od': visualAcuityOd,
        'visual_acuity_os': visualAcuityOs,
        'visual_acuity': visualAcuity,
        'intraocular_pressure_od': intraocularPressureOd,
        'intraocular_pressure_os': intraocularPressureOs,
        'intraocular_pressure': intraocularPressure,
        'slit_lamp_examination': slitLampExamination,
        'diagnosis': diagnosis,
        'clinical_notes': clinicalNotes,
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

  EyeExaminationModel copyWith({
    String? id,
    String? patientId,
    String? appointmentId,
    String? eyeSurgeryId,
    DateTime? examinationDate,
    String? examinationTime,
    String? visualAcuityOd,
    String? visualAcuityOs,
    String? visualAcuity,
    String? intraocularPressureOd,
    String? intraocularPressureOs,
    String? intraocularPressure,
    String? slitLampExamination,
    String? diagnosis,
    String? clinicalNotes,
    String? createdBy,
    DateTime? createdAt,
    DateTime? updatedAt,
    String? patientName,
    String? patientNumber,
    DateTime? appointmentDate,
    String? appointmentTime,
    String? createdByName,
  }) {
    return EyeExaminationModel(
      id: id ?? this.id,
      patientId: patientId ?? this.patientId,
      appointmentId: appointmentId ?? this.appointmentId,
      eyeSurgeryId: eyeSurgeryId ?? this.eyeSurgeryId,
      examinationDate: examinationDate ?? this.examinationDate,
      examinationTime: examinationTime ?? this.examinationTime,
      visualAcuityOd: visualAcuityOd ?? this.visualAcuityOd,
      visualAcuityOs: visualAcuityOs ?? this.visualAcuityOs,
      visualAcuity: visualAcuity ?? this.visualAcuity,
      intraocularPressureOd:
          intraocularPressureOd ?? this.intraocularPressureOd,
      intraocularPressureOs:
          intraocularPressureOs ?? this.intraocularPressureOs,
      intraocularPressure: intraocularPressure ?? this.intraocularPressure,
      slitLampExamination: slitLampExamination ?? this.slitLampExamination,
      diagnosis: diagnosis ?? this.diagnosis,
      clinicalNotes: clinicalNotes ?? this.clinicalNotes,
      createdBy: createdBy ?? this.createdBy,
      createdAt: createdAt ?? this.createdAt,
      updatedAt: updatedAt ?? this.updatedAt,
      patientName: patientName ?? this.patientName,
      patientNumber: patientNumber ?? this.patientNumber,
      appointmentDate: appointmentDate ?? this.appointmentDate,
      appointmentTime: appointmentTime ?? this.appointmentTime,
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
