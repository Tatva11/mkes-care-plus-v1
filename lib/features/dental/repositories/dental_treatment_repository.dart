import 'package:supabase_flutter/supabase_flutter.dart';
import '../models/dental_treatment_model.dart';

class DentalTreatmentRepository {
  DentalTreatmentRepository({SupabaseClient? client})
      : _client = client ?? Supabase.instance.client;

  final SupabaseClient _client;

  static const String _fullSelect =
      '*, patients(name, patient_number), appointments(appointment_date, appointment_time, status), dental_lab(case_number, case_type), profiles(full_name)';
  static const String _fallbackSelect =
      '*, patients(name, patient_number)';

  /// Fetches dental treatment records for a patient or appointment or lab case.
  Future<List<DentalTreatmentModel>> fetchTreatments({
    String? patientId,
    String? appointmentId,
    String? dentalLabCaseId,
  }) async {
    dynamic response;
    try {
      var query = _client.from('dental_treatments').select(_fullSelect);
      if (patientId != null && patientId.isNotEmpty) {
        query = query.eq('patient_id', patientId);
      }
      if (appointmentId != null && appointmentId.isNotEmpty) {
        query = query.eq('appointment_id', appointmentId);
      }
      if (dentalLabCaseId != null && dentalLabCaseId.isNotEmpty) {
        query = query.eq('dental_lab_case_id', dentalLabCaseId);
      }
      response = await query.order('treatment_date', ascending: false).order('created_at', ascending: false);
    } catch (_) {
      var query = _client.from('dental_treatments').select(_fallbackSelect);
      if (patientId != null && patientId.isNotEmpty) {
        query = query.eq('patient_id', patientId);
      }
      if (appointmentId != null && appointmentId.isNotEmpty) {
        query = query.eq('appointment_id', appointmentId);
      }
      if (dentalLabCaseId != null && dentalLabCaseId.isNotEmpty) {
        query = query.eq('dental_lab_case_id', dentalLabCaseId);
      }
      response = await query.order('treatment_date', ascending: false).order('created_at', ascending: false);
    }

    final list = (response as List<dynamic>)
        .map((json) => DentalTreatmentModel.fromJson(_asStringMap(json) ?? {}))
        .toList();
    return list;
  }

  /// Fetches a single treatment by ID.
  Future<DentalTreatmentModel?> fetchTreatmentById(String id) async {
    try {
      final response = await _client
          .from('dental_treatments')
          .select(_fullSelect)
          .eq('id', id)
          .single();
      return DentalTreatmentModel.fromJson(_asStringMap(response) ?? {});
    } catch (_) {
      final response = await _client
          .from('dental_treatments')
          .select(_fallbackSelect)
          .eq('id', id)
          .single();
      return DentalTreatmentModel.fromJson(_asStringMap(response) ?? {});
    }
  }

  /// Creates a new dental treatment record.
  Future<DentalTreatmentModel> createTreatment(
    DentalTreatmentModel treatment,
  ) async {
    final currentUserId = _client.auth.currentUser?.id;
    final payload = treatment.toInsertJson();
    if (currentUserId != null) {
      payload['created_by'] = currentUserId;
    }

    final response = await _client
        .from('dental_treatments')
        .insert(payload)
        .select(_fullSelect)
        .single();

    return DentalTreatmentModel.fromJson(_asStringMap(response) ?? {});
  }

  /// Updates an existing dental treatment record.
  Future<DentalTreatmentModel> updateTreatment(
    DentalTreatmentModel treatment,
  ) async {
    final payload = treatment.toJson()
      ..remove('id')
      ..remove('created_at')
      ..['updated_at'] = DateTime.now().toIso8601String();

    final response = await _client
        .from('dental_treatments')
        .update(payload)
        .eq('id', treatment.id)
        .select(_fullSelect)
        .single();

    return DentalTreatmentModel.fromJson(_asStringMap(response) ?? {});
  }

  /// Deletes a dental treatment record (admin only).
  Future<void> deleteTreatment(String id) async {
    await _client.from('dental_treatments').delete().eq('id', id);
  }

  static Map<String, dynamic>? _asStringMap(Object? value) {
    if (value is! Map) return null;
    return {
      for (final entry in value.entries)
        if (entry.key is String) entry.key as String: entry.value,
    };
  }
}
