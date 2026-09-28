import 'package:flutter/material.dart';
import '../../../core/theme/app_colors.dart';
import '../../patients/models/patient_model.dart';

class AppointmentModel {
  final String id;
  final String? patientId;
  final String department; // 'eye' | 'dental'
  final String? doctorId;
  final DateTime appointmentDate;
  final String appointmentTime; // '09:00:00' or '09:00'
  final String appointmentType; // 'regular' | 'walk_in' | 'follow_up'
  final String
      status; // 'scheduled' | 'confirmed' | 'waiting' | 'completed' | 'missed' | 'cancelled'
  final String? notes;
  final bool aiBooked;
  final DateTime createdAt;
  final DateTime updatedAt;

  // Joined / Related Entity Data
  final PatientModel? patient;
  final String? patientName;
  final String? patientNumber;
  final String? doctorName;
  final String? specialty;
  final String? room;
  final bool isVisitingDoctor;
  final String? previousVisitSummary;
  final String? previousTreatment;
  final String? currentDiagnosis;
  final String? plannedTreatment;
  final String? doctorNotes;

  const AppointmentModel({
    required this.id,
    this.patientId,
    this.department = 'eye',
    this.doctorId,
    required this.appointmentDate,
    required this.appointmentTime,
    this.appointmentType = 'regular',
    this.status = 'scheduled',
    this.notes,
    this.aiBooked = false,
    required this.createdAt,
    required this.updatedAt,
    this.patient,
    this.patientName,
    this.patientNumber,
    this.doctorName,
    this.specialty,
    this.room,
    this.isVisitingDoctor = false,
    this.previousVisitSummary,
    this.previousTreatment,
    this.currentDiagnosis,
    this.plannedTreatment,
    this.doctorNotes,
  });

  factory AppointmentModel.fromJson(Map<String, dynamic> json) {
    final patientJson = json['patients'] is Map<String, dynamic>
        ? json['patients'] as Map<String, dynamic>
        : null;
    final doctorJson = json['profiles'] is Map<String, dynamic>
        ? json['profiles'] as Map<String, dynamic>
        : (json['doctor'] is Map<String, dynamic>
            ? json['doctor'] as Map<String, dynamic>
            : null);

    final patientObj =
        patientJson != null ? PatientModel.fromJson(patientJson) : null;
    final resolvedPatientName =
        patientObj?.name ?? (json['patient_name'] as String?);
    final resolvedPatientNumber =
        patientObj?.patientNumber ?? (json['patient_number'] as String?);

    final resolvedDoctorName =
        doctorJson?['full_name'] as String? ?? (json['doctor_name'] as String?);
    final designation =
        doctorJson?['designation'] as String? ?? (json['specialty'] as String?);
    final isVisiting =
        (designation?.toLowerCase().contains('visiting') ?? false) ||
            (json['is_visiting_doctor'] as bool? ?? false);

    // Parse date safely
    DateTime parsedDate;
    if (json['appointment_date'] != null) {
      parsedDate = DateTime.tryParse(json['appointment_date'] as String) ??
          DateTime.now();
    } else {
      parsedDate = DateTime.now();
    }

    return AppointmentModel(
      id: json['id'] as String? ?? '',
      patientId: json['patient_id'] as String?,
      department: json['department'] as String? ?? 'eye',
      doctorId: json['doctor_id'] as String?,
      appointmentDate: parsedDate,
      appointmentTime: json['appointment_time'] as String? ?? '09:00',
      appointmentType: json['appointment_type'] as String? ?? 'regular',
      status: json['status'] as String? ?? 'scheduled',
      notes: json['notes'] as String?,
      aiBooked: json['ai_booked'] as bool? ?? false,
      createdAt: json['created_at'] != null
          ? DateTime.tryParse(json['created_at'] as String) ?? DateTime.now()
          : DateTime.now(),
      updatedAt: json['updated_at'] != null
          ? DateTime.tryParse(json['updated_at'] as String) ?? DateTime.now()
          : DateTime.now(),
      patient: patientObj,
      patientName: resolvedPatientName ?? 'Unknown Patient',
      patientNumber: resolvedPatientNumber ?? 'Unknown ID',
      doctorName: resolvedDoctorName,
      specialty: designation,
      room: json['room'] as String? ??
          (json['department'] == 'dental' ? 'Dental Suite 1' : 'Room 102'),
      isVisitingDoctor: isVisiting,
      previousVisitSummary: json['previous_visit_summary'] as String?,
      previousTreatment: json['previous_treatment'] as String?,
      currentDiagnosis: json['current_diagnosis'] as String?,
      plannedTreatment: json['planned_treatment'] as String?,
      doctorNotes: json['doctor_notes'] as String? ?? json['notes'] as String?,
    );
  }

  Map<String, dynamic> toJson() {
    return {
      'id': id,
      'patient_id': patientId,
      'department': department,
      'doctor_id': doctorId,
      'appointment_date': appointmentDate.toIso8601String().split('T').first,
      'appointment_time': appointmentTime,
      'appointment_type': appointmentType,
      'status': status,
      'notes': notes,
      'ai_booked': aiBooked,
      'created_at': createdAt.toIso8601String(),
      'updated_at': updatedAt.toIso8601String(),
    };
  }

  Map<String, dynamic> toInsertJson() {
    final map = <String, dynamic>{
      'department': department,
      'appointment_date': appointmentDate.toIso8601String().split('T').first,
      'appointment_time': appointmentTime,
      'appointment_type': appointmentType,
      'status': status,
      'ai_booked': aiBooked,
    };
    if (patientId != null) map['patient_id'] = patientId;
    if (doctorId != null) map['doctor_id'] = doctorId;
    if (notes != null) map['notes'] = notes;
    return map;
  }

  AppointmentModel copyWith({
    String? id,
    String? patientId,
    String? department,
    String? doctorId,
    DateTime? appointmentDate,
    String? appointmentTime,
    String? appointmentType,
    String? status,
    String? notes,
    bool? aiBooked,
    DateTime? createdAt,
    DateTime? updatedAt,
    PatientModel? patient,
    String? patientName,
    String? patientNumber,
    String? doctorName,
    String? specialty,
    String? room,
    bool? isVisitingDoctor,
    String? previousVisitSummary,
    String? previousTreatment,
    String? currentDiagnosis,
    String? plannedTreatment,
    String? doctorNotes,
  }) {
    return AppointmentModel(
      id: id ?? this.id,
      patientId: patientId ?? this.patientId,
      department: department ?? this.department,
      doctorId: doctorId ?? this.doctorId,
      appointmentDate: appointmentDate ?? this.appointmentDate,
      appointmentTime: appointmentTime ?? this.appointmentTime,
      appointmentType: appointmentType ?? this.appointmentType,
      status: status ?? this.status,
      notes: notes ?? this.notes,
      aiBooked: aiBooked ?? this.aiBooked,
      createdAt: createdAt ?? this.createdAt,
      updatedAt: updatedAt ?? this.updatedAt,
      patient: patient ?? this.patient,
      patientName: patientName ?? this.patientName,
      patientNumber: patientNumber ?? this.patientNumber,
      doctorName: doctorName ?? this.doctorName,
      specialty: specialty ?? this.specialty,
      room: room ?? this.room,
      isVisitingDoctor: isVisitingDoctor ?? this.isVisitingDoctor,
      previousVisitSummary: previousVisitSummary ?? this.previousVisitSummary,
      previousTreatment: previousTreatment ?? this.previousTreatment,
      currentDiagnosis: currentDiagnosis ?? this.currentDiagnosis,
      plannedTreatment: plannedTreatment ?? this.plannedTreatment,
      doctorNotes: doctorNotes ?? this.doctorNotes,
    );
  }

  String get formattedTime {
    final parts = appointmentTime.split(':');
    if (parts.length >= 2) {
      final hour = int.tryParse(parts[0]) ?? 9;
      final minute = int.tryParse(parts[1]) ?? 0;
      final period = hour >= 12 ? 'PM' : 'AM';
      final displayHour = hour > 12 ? hour - 12 : (hour == 0 ? 12 : hour);
      final displayMinute = minute.toString().padLeft(2, '0');
      return '$displayHour:$displayMinute $period';
    }
    return appointmentTime;
  }

  String get statusLabel {
    switch (status.toLowerCase()) {
      case 'scheduled':
        return 'Scheduled';
      case 'confirmed':
        return 'Confirmed';
      case 'waiting':
      case 'in_triage':
      case 'in triage':
        return 'In Triage';
      case 'completed':
        return 'Completed';
      case 'missed':
        return 'Missed';
      case 'cancelled':
        return 'Cancelled';
      default:
        return status[0].toUpperCase() + status.substring(1);
    }
  }

  Color get statusColor {
    switch (status.toLowerCase()) {
      case 'confirmed':
      case 'completed':
        return AppColors.primaryContainer;
      case 'waiting':
      case 'in_triage':
      case 'in triage':
        return AppColors.secondary;
      case 'scheduled':
        return AppColors.outline;
      case 'missed':
      case 'cancelled':
        return AppColors.error;
      default:
        return AppColors.outline;
    }
  }

  String get typeLabel {
    switch (appointmentType.toLowerCase()) {
      case 'walk_in':
        return 'Walk-In Consultation';
      case 'follow_up':
        return 'Follow-Up Visit';
      case 'regular':
      default:
        if (department.toLowerCase() == 'dental') {
          return 'Dental Checkup & Treatment';
        }
        return 'Optometry Refraction & Fitting';
    }
  }
}
