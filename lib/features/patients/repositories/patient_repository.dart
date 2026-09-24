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
      query = query.eq('department', department.toLowerCase());
    }

    if (searchQuery != null && searchQuery.isNotEmpty) {
      query = query.or(
        'name.ilike.%$searchQuery%,patient_number.ilike.%$searchQuery%,mobile.ilike.%$searchQuery%',
      );
    }

    final response = await query.order('name', ascending: true);

    return (response as List)
        .map((json) => PatientModel.fromJson(json as Map<String, dynamic>))
        .toList();
  }

  /// Create a new patient in the database.
  Future<PatientModel> createPatient(PatientModel patient) async {
    final response = await _supabase.rpc(
      'create_patient',
      params: {
        'p_name': patient.name,
        'p_department': patient.department,
        'p_dob': patient.dob?.toIso8601String().split('T').first,
        'p_address': patient.address,
        'p_mobile': patient.mobile,
        'p_reference': patient.reference,
        'p_visit_date': patient.visitDate?.toIso8601String().split('T').first,
      },
    );

    return PatientModel.fromJson(response as Map<String, dynamic>);
  }
}
