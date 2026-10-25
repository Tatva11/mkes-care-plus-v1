import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:intl/intl.dart';
import 'package:supabase_flutter/supabase_flutter.dart';

import '../../../core/providers/supabase_provider.dart';
import '../models/appointment_model.dart';

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

  /// Create a new appointment and automatically enqueue WhatsApp confirmation.
  Future<AppointmentModel> createAppointment(
      AppointmentModel appointment) async {
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
