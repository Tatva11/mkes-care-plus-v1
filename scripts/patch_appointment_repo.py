import re

file_path = "lib/features/appointments/repositories/appointment_repository.dart"
with open(file_path, "r", encoding="utf-8") as f:
    content = f.read()

# 1. Update imports and add AppointmentConflictException
new_header = """import 'package:flutter/foundation.dart';
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
}"""

content = re.sub(
    r"import 'package:flutter_riverpod/flutter_riverpod\.dart';\s*import 'package:intl/intl\.dart';\s*import 'package:supabase_flutter/supabase_flutter\.dart';\s*import '\.\./\.\./\.\./core/providers/supabase_provider\.dart';\s*import '\.\./models/appointment_model\.dart';",
    new_header,
    content,
    flags=re.DOTALL
)

# 2. Add conflict check helper and method before createAppointment
conflict_methods = """  /// Normalizes a time string (e.g. "09:30:00", "9:30", "09:30") to "HH:mm".
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

  /// Create a new appointment and automatically enqueue WhatsApp confirmation."""

content = re.sub(
    r"\s*/// Create a new appointment and automatically enqueue WhatsApp confirmation\.",
    "\n\n" + conflict_methods,
    content
)

# 3. Add conflict check in createAppointment body
content = re.sub(
    r"(Future<AppointmentModel> createAppointment\(\s*AppointmentModel appointment\s*\) async \{)",
    r"""\1
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
    }""",
    content
)

# 4. Add conflict check in updateAppointment body
content = re.sub(
    r"(Future<void> updateAppointment\(\s*String id,\s*Map<String, dynamic> updates,\s*\) async \{)",
    r"""\1
    if (updates.containsKey('appointment_date') &&
        updates.containsKey('appointment_time') &&
        updates.containsKey('department')) {
      final date = DateTime.tryParse(updates['appointment_date'] as String);
      final time = updates['appointment_time'] as String;
      final dept = updates['department'] as String;

      if (date != null) {
        final conflict = await checkAppointmentConflict(
          date: date,
          time: time,
          department: dept,
          patientId: updates['patient_id'] as String?,
          doctorId: updates['doctor_id'] as String?,
          doctorName: updates['doctor_name'] as String?,
          excludeAppointmentId: id,
        );
        if (conflict != null) {
          throw AppointmentConflictException(conflict);
        }
      }
    }""",
    content
)

with open(file_path, "w", encoding="utf-8", newline="") as f:
    f.write(content)

print(f"File updated. Total lines: {len(content.splitlines())}")

