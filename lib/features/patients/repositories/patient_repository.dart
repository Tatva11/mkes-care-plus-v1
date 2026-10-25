import 'package:flutter/foundation.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:supabase_flutter/supabase_flutter.dart';

import '../../../core/providers/supabase_provider.dart';
import '../models/patient_model.dart';

final patientRepositoryProvider = Provider<PatientRepository>((ref) {
  return PatientRepository(ref.watch(supabaseProvider));
});

class PatientRepository {
  final SupabaseClient _supabase;

  PatientRepository(this._supabase);

  /// Fetch list of patients from Supabase.
  Future<List<PatientModel>> fetchPatients({
    String? department,
    String? searchQuery,
  }) async {
    var query = _supabase.from('patients').select();

    if (department != null && department.isNotEmpty) {
      if (department != 'eye' && department != 'dental') {
        throw ArgumentError.value(
            department, 'department', 'Must be eye or dental.');
      }
      query = query.eq('department', department);
      debugPrint('PatientRepository.fetchPatients department=$department');
    }

    final normalizedSearch = searchQuery?.trim();
    if (normalizedSearch != null && normalizedSearch.isNotEmpty) {
      query = query.or(
        'name.ilike.%$normalizedSearch%,patient_number.ilike.%$normalizedSearch%,mobile.ilike.%$normalizedSearch%',
      );
    }

    final response = await query.order('name', ascending: true);

    final patients = (response as List)
        .map((json) => PatientModel.fromJson(json as Map<String, dynamic>))
        .toList();
    debugPrint(
      'PatientRepository.fetchPatients department=$department returned=${patients.length}',
    );
    return patients;
  }

  /// Create a new patient in the database.
  Future<PatientModel> createPatient(PatientModel patient) async {
    final department = patient.department?.trim().toLowerCase();
    if (department != 'eye' && department != 'dental') {
      throw ArgumentError.value(
          patient.department, 'department', 'Must be eye or dental.');
    }

    final response = await _supabase.rpc(
      'create_patient',
      params: {
        'p_name': patient.name,
        'p_department': department,
        'p_dob': patient.dob?.toIso8601String().split('T').first,
        'p_address': patient.address,
        'p_mobile': patient.mobile,
        'p_reference': patient.reference,
        'p_visit_date': DateTime.now().toIso8601String().split('T').first,
      },
    );

    final map = response is Map<String, dynamic>
        ? response
        : Map<String, dynamic>.from(response as Map);
    return PatientModel.fromJson(map);
  }

  /// Fetch a single patient by ID from Supabase.
  Future<PatientModel> getPatient(String id) async {
    final response = await _supabase
        .from('patients')
        .select()
        .eq('id', id)
        .single();
    return PatientModel.fromJson(response);
  }

  /// Update an existing patient in the database.
  /// Modifies only: name, mobile, department, dob, address, reference, updated_at.
  /// Patient number is strictly preserved.
  Future<PatientModel> updatePatient(PatientModel patient) async {
    final department = patient.department?.trim().toLowerCase();
    if (department != null && department.isNotEmpty) {
      if (department != 'eye' && department != 'dental') {
        throw ArgumentError.value(
            patient.department, 'department', 'Must be eye or dental.');
      }
    }

    final updateData = <String, dynamic>{
      'name': patient.name.trim(),
      'mobile': patient.mobile,
      'department': department,
      'dob': patient.dob?.toIso8601String().split('T').first,
      'address': patient.address,
      'reference': patient.reference,
      'whatsapp_opt_out': patient.whatsappOptOut,
      'updated_at': DateTime.now().toUtc().toIso8601String(),
    };

    final response = await _supabase
        .from('patients')
        .update(updateData)
        .eq('id', patient.id)
        .select()
        .single();

    return PatientModel.fromJson(response);
  }

  /// Toggle or set WhatsApp opt-out preference for a patient.
  Future<bool> setWhatsAppOptOut(String patientId, bool optOut) async {
    await _supabase
        .from('patients')
        .update({
          'whatsapp_opt_out': optOut,
          'updated_at': DateTime.now().toUtc().toIso8601String(),
        })
        .eq('id', patientId);
    return optOut;
  }
}

