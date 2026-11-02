file_path = "lib/features/appointments/repositories/appointment_repository.dart"
with open(file_path, "r", encoding="utf-8") as f:
    content = f.read()

update_old = """  /// Update appointment fields.
  Future<void> updateAppointment(
    String id,
    Map<String, dynamic> updates,
  ) async {
    final payload = Map<String, dynamic>.from(updates);
    payload['updated_at'] = DateTime.now().toUtc().toIso8601String();

    await _supabase.from('appointments').update(payload).eq('id', id);
  }"""

update_new = """  /// Update appointment fields.
  Future<void> updateAppointment(
    String id,
    Map<String, dynamic> updates,
  ) async {
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
    }

    final payload = Map<String, dynamic>.from(updates);
    payload['updated_at'] = DateTime.now().toUtc().toIso8601String();

    await _supabase.from('appointments').update(payload).eq('id', id);
  }"""

content_norm = content.replace("\r\n", "\n")
update_old_norm = update_old.replace("\r\n", "\n")
update_new_norm = update_new.replace("\r\n", "\n")

if update_old_norm in content_norm:
    content_norm = content_norm.replace(update_old_norm, update_new_norm)
    print("updateAppointment pattern replaced successfully.")
else:
    print("updateAppointment pattern not found!")

with open(file_path, "w", encoding="utf-8") as f:
    f.write(content_norm.replace("\n", "\r\n"))

print("Finished updating updateAppointment.")

