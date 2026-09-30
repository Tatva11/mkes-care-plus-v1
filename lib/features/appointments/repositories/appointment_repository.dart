import 'package:flutter_riverpod/flutter_riverpod.dart';
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

  /// Create a new appointment.
  Future<AppointmentModel> createAppointment(
      AppointmentModel appointment) async {
    final response = await _supabase
        .from('appointments')
        .insert(appointment.toInsertJson())
        .select(
          '*, patients!appointments_patient_id_fkey(*), profiles!appointments_doctor_id_fkey(*)',
        )
        .single();

    return AppointmentModel.fromJson(response);
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
