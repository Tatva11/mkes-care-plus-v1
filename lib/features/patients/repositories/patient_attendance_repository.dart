import 'dart:async';

import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:supabase_flutter/supabase_flutter.dart';

import '../../../core/providers/supabase_provider.dart';
import '../models/patient_attendance.dart';

final patientAttendanceRepositoryProvider =
    Provider<PatientAttendanceRepository>((ref) {
  return PatientAttendanceRepository(ref.watch(supabaseProvider));
});

// ─────────────────────────────────────────────────────────────────────────────
// Supabase select strings — defined once so changes are easy to track.
// ─────────────────────────────────────────────────────────────────────────────

/// Selects attendance + attending staff name + patient info.
/// Used by admin and patient-detail views.
const _kSelectFull =
    '*, '
    'profiles!patient_attendance_staff_id_fkey(full_name), '
    'patients!patient_attendance_patient_id_fkey(name, patient_number, department)';

/// Selects attendance + attending staff name only (no patient join needed
/// when the patient context is already known, e.g. per-staff fetch).
const _kSelectWithStaff =
    '*, '
    'profiles!patient_attendance_staff_id_fkey(full_name)';

class PatientAttendanceRepository {
  final SupabaseClient _supabase;

  PatientAttendanceRepository(this._supabase);

  // ── Staff: fetch own attendance for a specific date ──────────────────────

    Future<List<PatientAttendance>> fetchForStaff(
      String staffId, DateTime date) async {
    final response = await _supabase
        .from('patient_attendance')
        .select(_kSelectWithStaff)
        .eq('staff_id', staffId)
        .eq('attendance_date', _dateKey(date))
        .order('attended_at', ascending: false)
        .timeout(const Duration(seconds: 15));
    return (response as List)
        .map((json) => PatientAttendance.fromJson(json))
        .toList();
  }

  // ── Staff: fetch all attendance for today across all staff ────────────────
  //
  // Uses the "Staff can read today patient attendance" RLS policy.
  // This allows any active staff to see which patients have already been
  // attended today by any staff member, preventing duplicate attempts.
  Future<List<PatientAttendance>> fetchTodayForAllStaff({DateTime? today}) async {
    final referenceDate = today ?? DateTime.now();
    final response = await _supabase
        .from('patient_attendance')
        .select(_kSelectWithStaff)
        .eq('attendance_date', _dateKey(referenceDate))
        .order('attended_at', ascending: true)
        .timeout(const Duration(seconds: 15));
    return (response as List)
        .map((json) => PatientAttendance.fromJson(json))
        .toList();
  }

  // ── Admin: fetch all attendance for a specific date ──────────────────────
  //
  // NOTE: We simply fetch all records for the date — every row in
  // patient_attendance was inserted by a staff member due to the INSERT RLS
  // policy enforcing role = 'staff'.

  Future<List<PatientAttendance>> fetchForAdmin(DateTime date) async {
    final response = await _supabase
        .from('patient_attendance')
        .select(_kSelectFull)
        .eq('attendance_date', _dateKey(date))
        .order('attended_at', ascending: false)
        .timeout(const Duration(seconds: 15));
    return (response as List)
        .map((json) => PatientAttendance.fromJson(json))
        .toList();
  }

  // ── Patient history (admin / details screen) ─────────────────────────────

  Future<List<PatientAttendance>> fetchForPatient(String patientId) async {
    final response = await _supabase
        .from('patient_attendance')
        .select(_kSelectWithStaff)
        .eq('patient_id', patientId)
        .order('attended_at', ascending: false)
        .timeout(const Duration(seconds: 15));
    return (response as List)
        .map((json) => PatientAttendance.fromJson(json))
        .toList();
  }

  // ── Staff: mark patient as attended ─────────────────────────────────────
  //
  // Throws PostgrestException with code '23505' on duplicate
  // (same staff + patient + date).  Callers should handle that code
  // gracefully instead of surfacing it as an error to the user.

  Future<void> markAttended({
    required String patientId,
    required String staffId,
    DateTime? now,
  }) async {
    final timestamp = now ?? DateTime.now();
    await _supabase.from('patient_attendance').insert({
      'patient_id': patientId,
      'staff_id': staffId,
      'attendance_date': _dateKey(timestamp),
      'attended_at': timestamp.toUtc().toIso8601String(),
      'status': 'attended',
    });
  }

  // ── Helpers ──────────────────────────────────────────────────────────────

  String _dateKey(DateTime date) =>
      '${date.year.toString().padLeft(4, '0')}-'
      '${date.month.toString().padLeft(2, '0')}-'
      '${date.day.toString().padLeft(2, '0')}';
}
