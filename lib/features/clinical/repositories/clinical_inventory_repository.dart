import 'package:supabase_flutter/supabase_flutter.dart';
import '../models/clinical_inventory_usage_model.dart';

class ClinicalInventoryRepository {
  ClinicalInventoryRepository({SupabaseClient? client})
      : _client = client ?? Supabase.instance.client;

  final SupabaseClient _client;

  static const String _fullSelect =
      '*, inventory(name, unit, quantity), patients(name, patient_number), profiles(full_name), departments(name)';
  static const String _fallbackSelect =
      '*, inventory(name, unit, quantity)';

  /// Atomically consumes inventory for a patient clinical record via DB RPC.
  Future<ClinicalInventoryUsageModel> recordConsumption({
    required String patientId,
    required String recordType,
    required String recordId,
    required String inventoryId,
    required double quantity,
    String? remarks,
    String? departmentId,
    String? idempotencyKey,
  }) async {
    if (quantity <= 0) {
      throw ArgumentError('Quantity must be greater than zero.');
    }

    final params = <String, dynamic>{
      'p_patient_id': patientId,
      'p_record_type': recordType,
      'p_record_id': recordId,
      'p_inventory_id': inventoryId,
      'p_quantity': quantity,
      'p_remarks': remarks?.trim().isEmpty ?? true ? null : remarks!.trim(),
      if (departmentId != null && departmentId.trim().isNotEmpty)
        'p_department_id': departmentId.trim(),
      if (idempotencyKey != null && idempotencyKey.trim().isNotEmpty)
        'p_idempotency_key': idempotencyKey.trim(),
    };

    final response = await _client.rpc(
      'record_clinical_inventory_consumption',
      params: params,
    );

    if (response is Map) {
      final usageId = response['usage_id']?.toString();
      if (usageId != null && usageId.isNotEmpty) {
        // Fetch complete record with joined inventory and patient
        final completeRecord = await fetchUsageById(usageId);
        if (completeRecord != null) return completeRecord;
      }
    }

    // Fallback if RPC returns standard response
    return ClinicalInventoryUsageModel(
      id: response is Map ? response['usage_id']?.toString() ?? '' : '',
      patientId: patientId,
      recordType: recordType,
      recordId: recordId,
      inventoryId: inventoryId,
      quantity: quantity,
      transactionId: response is Map ? response['transaction_id']?.toString() : null,
      remarks: remarks,
      consumedAt: DateTime.now(),
      createdAt: DateTime.now(),
      updatedAt: DateTime.now(),
      departmentId: departmentId,
    );
  }

  /// Fetches clinical inventory usage entries for a specific record.
  Future<List<ClinicalInventoryUsageModel>> fetchUsageForRecord({
    required String recordType,
    required String recordId,
  }) async {
    dynamic response;
    try {
      response = await _client
          .from('clinical_inventory_usage')
          .select(_fullSelect)
          .eq('record_type', recordType)
          .eq('record_id', recordId)
          .order('consumed_at', ascending: false);
    } catch (_) {
      response = await _client
          .from('clinical_inventory_usage')
          .select(_fallbackSelect)
          .eq('record_type', recordType)
          .eq('record_id', recordId)
          .order('consumed_at', ascending: false);
    }

    return (response as List<dynamic>)
        .map((json) =>
            ClinicalInventoryUsageModel.fromJson(_asStringMap(json) ?? {}))
        .toList();
  }

  /// Fetches clinical inventory usage for a specific patient.
  Future<List<ClinicalInventoryUsageModel>> fetchUsageForPatient(
    String patientId,
  ) async {
    dynamic response;
    try {
      response = await _client
          .from('clinical_inventory_usage')
          .select(_fullSelect)
          .eq('patient_id', patientId)
          .order('consumed_at', ascending: false);
    } catch (_) {
      response = await _client
          .from('clinical_inventory_usage')
          .select(_fallbackSelect)
          .eq('patient_id', patientId)
          .order('consumed_at', ascending: false);
    }

    return (response as List<dynamic>)
        .map((json) =>
            ClinicalInventoryUsageModel.fromJson(_asStringMap(json) ?? {}))
        .toList();
  }

  /// Fetches a single usage record by ID.
  Future<ClinicalInventoryUsageModel?> fetchUsageById(String usageId) async {
    try {
      final response = await _client
          .from('clinical_inventory_usage')
          .select(_fullSelect)
          .eq('id', usageId)
          .single();
      return ClinicalInventoryUsageModel.fromJson(
          _asStringMap(response) ?? {});
    } catch (_) {
      try {
        final response = await _client
            .from('clinical_inventory_usage')
            .select(_fallbackSelect)
            .eq('id', usageId)
            .single();
        return ClinicalInventoryUsageModel.fromJson(
            _asStringMap(response) ?? {});
      } catch (_) {
        return null;
      }
    }
  }

  static Map<String, dynamic>? _asStringMap(Object? value) {
    if (value is! Map) return null;
    return {
      for (final entry in value.entries)
        if (entry.key is String) entry.key as String: entry.value,
    };
  }
}
