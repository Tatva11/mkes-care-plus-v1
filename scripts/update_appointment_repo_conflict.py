import os

file_path = "lib/features/appointments/repositories/appointment_repository.dart"
with open(file_path, "r", encoding="utf-8") as f:
    content = f.read()

# Replace header
header_old = """import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:intl/intl.dart';
import 'package:supabase_flutter/supabase_flutter.dart';

import '../../../core/providers/supabase_provider.dart';
import '../models/appointment_model.dart';

final appointmentRepositoryProvider = Provider<AppointmentRepository>((ref) {
  return AppointmentRepository(ref.watch(supabaseProvider));
});"""

header_new = """import 'package:flutter/foundation.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:intl/intl.dart';
import 'package:supabase_flutter/supabase_flutter.dart';

import '../../../core/providers/supabase_provider.dart';
import '../models/appointment_model.dart';

class AppointmentConflictException implements Exception {
  final String message;
  AppointmentConflictException(this.message);

  @override
  String toString() => message;
}

final appointmentRepositoryProvider = Provider<AppointmentRepository>((ref) {
  return AppointmentRepository(ref.watch(supabaseProvider));
});"""

fetch_by_id_old = """  /// Fetch a single appointment by ID.
  Future<AppointmentModel?> fetchAppointmentById(String id) async {
    final response = await _supabase
        .from('appointments')
        .select(
          '*, patients!appointments_patient_id_fkey(*), profiles!appointments_doctor_id_fkey(*)',
        )
        .eq('id', id)
        .maybeSingle();

    if (response == null) return null;
    return AppointmentModel.fromJson(response);
  }

  /// Create a new appointment and automatically enqueue WhatsApp confirmation.
  Future<AppointmentModel> createAppointment(
      AppointmentModel appointment) async {"""

fetch_by_id_new = """  /// Fetch a single appointment by ID.
  Future<AppointmentModel?> fetchAppointmentById(String id) async {
    final response = await _supabase
        .from('appointments')
        .select(
          '*, patients!appointments_patient_id_fkey(*), profiles!appointments_doctor_id_fkey(*)',
        )
        .eq('id', id)
        .maybeSingle();

    if (response == null) return null;
    return AppointmentModel.fromJson(response);
  }

  /// Normalizes a time string (e.g. "09:30:00", "9:30", "09:30") to "HH:mm".
  static String normalizeTimePrefix(String time) {
    final clean = time.trim();
    if (clean.isEmpty) return '';
    final parts = clean.split(':');
    if (parts.length < 2) return clean;
    final h = parts[0].padLeft(2, '0');
    final m = parts[1].padLeft(2, '0');
    return '$h:$m';
  }

  /// Checks for conflicting appointments on the same date and time.
  /// Returns a human-readable conflict description if a conflict exists, or null if clear.
  Future<String?> checkAppointmentConflict({
    required DateTime date,
    required String time,
    required String department,
    String? patientId,
    String? doctorId,
    String? doctorName,
    String? excludeAppointmentId,
  }) async {
    final normTime = normalizeTimePrefix(time);
    final dateStr = date.toIso8601String().split('T').first;

    try {
      final response = await _supabase
          .from('appointments')
          .select('id, patient_id, department, doctor_id, doctor_name, appointment_time, status, notes')
          .eq('appointment_date', dateStr)
          .neq('status', 'cancelled');

      final list = (response as List).cast<Map<String, dynamic>>();

      for (final row in list) {
        final id = row['id']?.toString() ?? '';
        if (excludeAppointmentId != null && id == excludeAppointmentId) {
          continue;
        }

        final rowTime = normalizeTimePrefix(row['appointment_time']?.toString() ?? '');
        if (rowTime != normTime) {
          continue;
        }

        // 1. Patient Conflict: Same patient cannot have 2 appointments at the same time
        final rowPatientId = row['patient_id']?.toString();
        if (patientId != null && patientId.isNotEmpty && rowPatientId == patientId) {
          return 'This patient already has an active appointment scheduled on $dateStr at ${row['appointment_time'] ?? normTime}.';
        }

        // 2. Department Conflict: Same department cannot have 2 appointments at the same time
        final rowDept = (row['department']?.toString() ?? '').toLowerCase().trim();
        if (rowDept == department.toLowerCase().trim()) {
          final deptLabel = department.toUpperCase();
          return 'The $deptLabel clinic already has an appointment scheduled at ${row['appointment_time'] ?? normTime} on $dateStr. Please select another time slot.';
        }

        // 3. Doctor Conflict: Same doctor cannot have 2 appointments at the same time
        final rowDocId = row['doctor_id']?.toString();
        final rowDocName = row['doctor_name']?.toString() ??
            AppointmentModel.extractDoctorNameFromNotes(row['notes']?.toString());

        final isSameDocId = doctorId != null && doctorId.isNotEmpty && rowDocId == doctorId;
        final isSameDocName = doctorName != null &&
            doctorName.trim().isNotEmpty &&
            rowDocName != null &&
            rowDocName.trim().toLowerCase() == doctorName.trim().toLowerCase();

        if (isSameDocId || isSameDocName) {
          final docLabel = doctorName ?? rowDocName ?? 'The selected doctor';
          return '$docLabel already has an appointment scheduled at ${row['appointment_time'] ?? normTime} on $dateStr. Please select another time slot or doctor.';
        }
      }
    } catch (e) {
      debugPrint('AppointmentRepository.checkAppointmentConflict error: $e');
    }

    return null;
  }

  /// Create a new appointment and automatically enqueue WhatsApp confirmation.
  Future<AppointmentModel> createAppointment(
      AppointmentModel appointment) async {
    final conflict = await checkAppointmentConflict(
      date: appointment.appointmentDate,
      time: appointment.appointmentTime,
      department: appointment.department,
      patientId: appointment.patientId,
      doctorId: appointment.doctorId,
      doctorName: appointment.doctorName,
    );

    if (conflict != null) {
      throw AppointmentConflictException(conflict);
    }"""

# Normalize CRLF
content_norm = content.replace("\r\n", "\n")
header_old_norm = header_old.replace("\r\n", "\n")
header_new_norm = header_new.replace("\r\n", "\n")
fetch_by_id_old_norm = fetch_by_id_old.replace("\r\n", "\n")
fetch_by_id_new_norm = fetch_by_id_new.replace("\r\n", "\n")

if header_old_norm in content_norm:
    content_norm = content_norm.replace(header_old_norm, header_new_norm)
    print("Header replaced successfully.")
else:
    print("Header pattern not found!")

if fetch_by_id_old_norm in content_norm:
    content_norm = content_norm.replace(fetch_by_id_old_norm, fetch_by_id_new_norm)
    print("createAppointment pattern replaced successfully.")
else:
    print("createAppointment pattern not found!")

with open(file_path, "w", encoding="utf-8") as f:
    f.write(content_norm.replace("\n", "\r\n"))

print("Finished updating appointment_repository.dart")

