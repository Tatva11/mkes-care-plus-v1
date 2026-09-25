import 'dart:async';

import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:supabase_flutter/supabase_flutter.dart';

import '../../../core/providers/supabase_provider.dart';
import '../models/patient_attendance.dart';

final patientAttendanceRepositoryProvider = Provider<PatientAttendanceRepository>((ref) {
  return PatientAttendanceRepository(ref.watch(supabaseProvider));
});

class PatientAttendanceRepository {
  final SupabaseClient _supabase;

  PatientAttendanceRepository(this._supabase);

  Future<List<PatientAttendance>> fetchForStaff(String staffId, DateTime date) async {
    final response = await _supabase
        .from('patient_attendance')
        .select('*, profiles!patient_attendance_staff_id_fkey(full_name, role)')
        .eq('staff_id', staffId)
        .eq('attendance_date', _dateKey(date))
        .order('attended_at', ascending: false)
        .timeout(const Duration(seconds: 15));
    return (response as List).map((json) => PatientAttendance.fromJson(json)).toList();
  }

  Future<List<PatientAttendance>> fetchForAdmin(DateTime date) async {
    final response = await _supabase
        .from('patient_attendance')
        .select('*, profiles!patient_attendance_staff_id_fkey(full_name, role)')
        .eq('profiles.role', 'staff')
        .eq('attendance_date', _dateKey(date))
        .order('attended_at', ascending: false)
        .timeout(const Duration(seconds: 15));
    return (response as List).map((json) => PatientAttendance.fromJson(json)).toList();
  }

  Future<List<PatientAttendance>> fetchForPatient(String patientId) async {
    final response = await _supabase
        .from('patient_attendance')
        .select('*, profiles!patient_attendance_staff_id_fkey(full_name, role)')
        .eq('patient_id', patientId)
        .order('attended_at', ascending: false)
        .timeout(const Duration(seconds: 15));
    return (response as List).map((json) => PatientAttendance.fromJson(json)).toList();
  }

  Future<void> markAttended({required String patientId, required String staffId, DateTime? now}) async {
    final timestamp = now ?? DateTime.now();
    await _supabase.from('patient_attendance').insert({
      'patient_id': patientId,
      'staff_id': staffId,
      'attendance_date': _dateKey(timestamp),
      'attended_at': timestamp.toUtc().toIso8601String(),
      'status': 'attended',
    });
  }

  String _dateKey(DateTime date) => '${date.year.toString().padLeft(4, '0')}-${date.month.toString().padLeft(2, '0')}-${date.day.toString().padLeft(2, '0')}';
}
