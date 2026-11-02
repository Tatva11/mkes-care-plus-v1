import 'package:flutter/foundation.dart';
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
});

class AppointmentRepository {
  final SupabaseClient _supabase;

  AppointmentRepository(this._supabase);

  /// Fetch list of appointments with optional filtering for date, doctor, department, and status.
  Future<List<AppointmentModel>> fetchAppointments({
    DateTime? date,
    String? doctorId,
    String? department,
    String? status,
  }) async {
    var query = _supabase.from('appointments').select(
          '*, patients!appointments_patient_id_fkey(*), profiles!appointments_doctor_id_fkey(*)',
        );

    if (date != null) {
      final dateStr = date.toIso8601String().split('T').first;
      query = query.eq('appointment_date', dateStr);
    }

    if (doctorId != null && doctorId.isNotEmpty) {
      query = query.eq('doctor_id', doctorId);
    }

    if (department != null && department.isNotEmpty) {
      query = query.eq('department', department.toLowerCase());
    }

    if (status != null && status.isNotEmpty) {
      query = query.eq('status', status.toLowerCase());
    }

    final response = await query
        .order('appointment_date', ascending: true)
        .order('appointment_time', ascending: true);

    return (response as List)
        .map((json) => AppointmentModel.fromJson(json as Map<String, dynamic>))
        .toList();
  }

  Future<List<AppointmentModel>> fetchPatientAppointments({
    required String patientId,
    required String department,
  }) async {
    final response = await _supabase
        .from('appointments')
        .select(
          '*, patients!appointments_patient_id_fkey(*), profiles!appointments_doctor_id_fkey(*)',
        )
        .eq('patient_id', patientId)
        .eq('department', department.toLowerCase())
        .order('appointment_date', ascending: true)
        .order('appointment_time', ascending: true);

    return (response as List)
        .map((json) => AppointmentModel.fromJson(json as Map<String, dynamic>))
        .toList();
  }

  Future<List<AppointmentStaffCandidate>> fetchDepartmentStaffCandidates(
    String departmentId,
  ) async {
    final response = await _supabase.rpc(
      'get_active_department_staff_candidates',
      params: {'p_department_id': departmentId},
    );

    return (response as List)
        .map(
          (row) => AppointmentStaffCandidate.fromJson(
            Map<String, dynamic>.from(row as Map),
          ),
        )
        .toList();
  }

  /// Convenience method to fetch today's appointments.
  Future<List<AppointmentModel>> fetchTodayAppointments({
    String? doctorId,
    String? department,
  }) async {
    return fetchAppointments(
      date: DateTime.now(),
      doctorId: doctorId,
      department: department,
    );
  }

  /// Fetch a single appointment by ID.
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
    }
    final response = await _supabase
        .from('appointments')
        .insert(appointment.toInsertJson())
        .select(
          '*, patients!appointments_patient_id_fkey(*), profiles!appointments_doctor_id_fkey(*)',
        )
        .single();

    final created = AppointmentModel.fromJson(response);

    // Auto-send WhatsApp confirmation on successful booking (Requirement 3)
    _enqueueWhatsAppConfirmation(created, response['patients'] as Map<String, dynamic>?);

    return created;
  }

  void _enqueueWhatsAppConfirmation(
    AppointmentModel appt,
    Map<String, dynamic>? patientMap,
  ) async {
    try {
      if (appt.status.toLowerCase() == 'cancelled') return;
      if (appt.patientId == null || appt.patientId!.trim().isEmpty) return;

      Map<String, dynamic>? pData = patientMap;
      if (pData == null || pData['mobile'] == null) {
        final pRes = await _supabase
            .from('patients')
            .select('name, mobile, whatsapp_opt_out')
            .eq('id', appt.patientId!)
            .maybeSingle();
        if (pRes != null) pData = Map<String, dynamic>.from(pRes);
      }

      if (pData == null) return;
      if (pData['whatsapp_opt_out'] == true) return;

      final rawMobile = pData['mobile']?.toString() ?? '';
      final digits = rawMobile.replaceAll(RegExp(r'[^0-9]'), '');
      if (digits.length < 10) return;
      final clean10 = digits.substring(digits.length - 10);

      // Duplicate prevention: check if confirmation already exists for this appointment
      final existing = await _supabase
          .from('whatsapp_messages_outbox')
          .select('id')
          .eq('appointment_id', appt.id)
          .eq('message_type', 'confirmation')
          .maybeSingle();

      if (existing != null) return;

      final patientName = pData['name']?.toString() ?? appt.patientName ?? 'Valued Patient';
      final formattedDate = DateFormat('d MMMM yyyy').format(appt.appointmentDate);
      final docStr = (appt.doctorName != null && appt.doctorName!.trim().isNotEmpty)
          ? ' with ${appt.doctorName}'
          : '';

      final messageText = '✅ *MKES CARE+ Appointment Confirmed!*\n\n'
          'Dear $patientName,\n'
          'Your ${appt.department.toUpperCase()} appointment is confirmed for *$formattedDate* at *${appt.formattedTime}*$docStr.\n\n'
          'Please arrive 10 minutes prior to your scheduled time.\n'
          'Reply STOP to unsubscribe.';

      await _supabase.from('whatsapp_messages_outbox').insert({
        'recipient_phone': clean10,
        'patient_id': appt.patientId,
        'appointment_id': appt.id,
        'department': appt.department.toLowerCase(),
        'message_type': 'confirmation',
        'template_key': 'appointment_confirmation',
        'message_text': messageText,
        'status': 'pending',
      });
    } catch (_) {
      // Non-blocking: background messaging failure should not fail appointment creation
    }
  }

  /// Update appointment fields.
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
  }

  /// Update appointment status (e.g. 'scheduled', 'confirmed', 'completed', 'cancelled').
  Future<void> updateStatus(String id, String status) async {
    await _supabase.from('appointments').update({
      'status': status.toLowerCase(),
      'updated_at': DateTime.now().toUtc().toIso8601String(),
    }).eq('id', id);
  }

  /// Delete an appointment.
  Future<void> deleteAppointment(String id) async {
    await _supabase.from('appointments').delete().eq('id', id);
  }
}
