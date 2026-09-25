import 'dart:math';

import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:supabase_flutter/supabase_flutter.dart';

import '../../../core/providers/supabase_provider.dart';
import '../models/patient.dart';

final patientRepositoryProvider = Provider<PatientRepository>((ref) {
  return PatientRepository(ref.watch(supabaseProvider));
});

class PatientRepository {
  final SupabaseClient _supabase;

  PatientRepository(this._supabase);

  Future<List<Patient>> fetchPatients({String search = ''}) async {
    var query = _supabase.from('patients').select();
    final trimmedSearch = search.trim();
    if (trimmedSearch.isNotEmpty) {
      query = query.or(
          'name.ilike.%$trimmedSearch%,patient_number.ilike.%$trimmedSearch%,mobile.ilike.%$trimmedSearch%');
    }
    final response = await query.order('created_at', ascending: false);
    return (response as List).map((json) => Patient.fromJson(json)).toList();
  }

  Future<Patient> getPatient(String id) async {
    final response = await _supabase
        .from('patients')
        .select()
        .eq('id', id)
        .single();
    return Patient.fromJson(response);
  }

  Future<Patient> createPatient({
    required String fullName,
    required String mobile,
    required String department,
    DateTime? dateOfBirth,
    String? address,
    String? reference,
  }) async {
    final normalizedDepartment = Patient.normalizeDepartment(department);
    if (normalizedDepartment == null) {
      throw ArgumentError(
        'Invalid department. Allowed values: ${Patient.allowedDepartments.join(', ')}.',
      );
    }

    final response = await _supabase.from('patients').insert({
      'patient_number': _generatePatientNumber(),
      'name': fullName.trim(),
      'mobile': mobile.trim(),
      'department': normalizedDepartment,
      'dob': dateOfBirth?.toIso8601String().split('T').first,
      'address': (address?.trim().isEmpty ?? true) ? null : address?.trim(),
      'reference':
          (reference?.trim().isEmpty ?? true) ? null : reference?.trim(),
      'visit_date': DateTime.now().toIso8601String().split('T').first,
    }).select().single();
    return Patient.fromJson(response);
  }

  /// Generates a unique registration number in the format P-YYYYMMDD-XXXX.
  /// patient_number is NOT NULL with no server-side DEFAULT on the patients
  /// table, so the client must always supply a value on INSERT.
  String _generatePatientNumber() {
    final now = DateTime.now();
    final date =
        '${now.year.toString().padLeft(4, '0')}${now.month.toString().padLeft(2, '0')}${now.day.toString().padLeft(2, '0')}';
    final suffix = (1000 + Random().nextInt(9000)).toString(); // 4-digit random
    return 'P-$date-$suffix';
  }

  Future<Patient> updatePatient({
    required String id,
    required String fullName,
    required String mobile,
    required String department,
    DateTime? dateOfBirth,
    String? address,
    String? reference,
  }) async {
    final normalizedDepartment = Patient.normalizeDepartment(department);
    if (normalizedDepartment == null) {
      throw ArgumentError(
        'Invalid department. Allowed values: ${Patient.allowedDepartments.join(', ')}.',
      );
    }

    final response = await _supabase.from('patients').update({
      'name': fullName.trim(),
      'mobile': mobile.trim(),
      'department': normalizedDepartment,
      'dob': dateOfBirth?.toIso8601String().split('T').first,
      'address': (address?.trim().isEmpty ?? true) ? null : address?.trim(),
      'reference':
          (reference?.trim().isEmpty ?? true) ? null : reference?.trim(),
      'updated_at': DateTime.now().toUtc().toIso8601String(),
    }).eq('id', id).select().single();
    return Patient.fromJson(response);
  }
}
