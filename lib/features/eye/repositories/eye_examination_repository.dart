import 'package:supabase_flutter/supabase_flutter.dart';
import '../models/eye_examination_model.dart';

class EyeExaminationRepository {
  EyeExaminationRepository({SupabaseClient? client})
      : _client = client ?? Supabase.instance.client;

  final SupabaseClient _client;

  static const String _fullSelect =
      '*, patients(name, patient_number), appointments(appointment_date, appointment_time), profiles(full_name)';
  static const String _fallbackSelect =
      '*, patients(name, patient_number)';

  /// Fetches eye examinations for a specific patient, optionally filtered by appointment.
  Future<List<EyeExaminationModel>> fetchExaminations({
    String? patientId,
    String? appointmentId,
  }) async {
    dynamic response;
    try {
      var query = _client.from('eye_examinations').select(_fullSelect);
      if (patientId != null && patientId.isNotEmpty) {
        query = query.eq('patient_id', patientId);
      }
      if (appointmentId != null && appointmentId.isNotEmpty) {
        query = query.eq('appointment_id', appointmentId);
      }
      response = await query.order('examination_date', ascending: false).order('created_at', ascending: false);
    } catch (_) {
      var query = _client.from('eye_examinations').select(_fallbackSelect);
      if (patientId != null && patientId.isNotEmpty) {
        query = query.eq('patient_id', patientId);
      }
      if (appointmentId != null && appointmentId.isNotEmpty) {
        query = query.eq('appointment_id', appointmentId);
      }
      response = await query.order('examination_date', ascending: false).order('created_at', ascending: false);
    }

    final list = (response as List<dynamic>)
        .map((json) => EyeExaminationModel.fromJson(_asStringMap(json) ?? {}))
        .toList();
    return list;
  }

  /// Fetches a single eye examination by ID.
  Future<EyeExaminationModel?> fetchExaminationById(String id) async {
    try {
      final response = await _client
          .from('eye_examinations')
          .select(_fullSelect)
          .eq('id', id)
          .single();
      return EyeExaminationModel.fromJson(_asStringMap(response) ?? {});
    } catch (_) {
      final response = await _client
          .from('eye_examinations')
          .select(_fallbackSelect)
          .eq('id', id)
          .single();
      return EyeExaminationModel.fromJson(_asStringMap(response) ?? {});
    }
  }

  /// Creates a new eye examination record.
  Future<EyeExaminationModel> createExamination(
    EyeExaminationModel examination,
  ) async {
    final currentUserId = _client.auth.currentUser?.id;
    final payload = examination.toInsertJson();
    if (currentUserId != null) {
      payload['created_by'] = currentUserId;
    }

    final response = await _client
        .from('eye_examinations')
        .insert(payload)
        .select(_fullSelect)
        .single();

    return EyeExaminationModel.fromJson(_asStringMap(response) ?? {});
  }

  /// Updates an existing eye examination record.
  Future<EyeExaminationModel> updateExamination(
    EyeExaminationModel examination,
  ) async {
    final payload = examination.toJson()
      ..remove('id')
      ..remove('created_at')
      ..['updated_at'] = DateTime.now().toIso8601String();

    final response = await _client
        .from('eye_examinations')
        .update(payload)
        .eq('id', examination.id)
        .select(_fullSelect)
        .single();

    return EyeExaminationModel.fromJson(_asStringMap(response) ?? {});
  }

  /// Deletes an eye examination record (admin only).
  Future<void> deleteExamination(String id) async {
    await _client.from('eye_examinations').delete().eq('id', id);
  }

  static Map<String, dynamic>? _asStringMap(Object? value) {
    if (value is! Map) return null;
    return {
      for (final entry in value.entries)
        if (entry.key is String) entry.key as String: entry.value,
    };
  }
}
