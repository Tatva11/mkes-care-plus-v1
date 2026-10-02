import 'package:intl/intl.dart';
import 'package:supabase_flutter/supabase_flutter.dart';
import '../models/dental_lab_model.dart';

class DentalLabRepository {
  DentalLabRepository({SupabaseClient? client})
      : _client = client ?? Supabase.instance.client;

  final SupabaseClient _client;

  /// Fetches dental lab cases with joined patient details.
  Future<List<DentalLabModel>> fetchCases({
    String? status,
    String? patientId,
    String? searchQuery,
  }) async {
    try {
      var query = _client.from('dental_lab').select('*, patients(*)');

      if (status != null && status != 'all' && status.isNotEmpty) {
        query = query.eq('status', status.toLowerCase());
      }

      if (patientId != null && patientId.isNotEmpty) {
        query = query.eq('patient_id', patientId);
      }

      final response = await query.order('created_at', ascending: false);

      final list = (response as List<dynamic>)
          .map((json) => DentalLabModel.fromJson(json as Map<String, dynamic>))
          .toList();

      if (searchQuery != null && searchQuery.trim().isNotEmpty) {
        final q = searchQuery.trim().toLowerCase();
        return list.where((item) {
          final caseNum = item.caseNumber.toLowerCase();
          final caseType = item.caseType.toLowerCase();
          final patientName = (item.patientName ?? '').toLowerCase();
          final patientNum = (item.patientNumber ?? '').toLowerCase();
          final remarks = (item.remarks ?? '').toLowerCase();
          return caseNum.contains(q) ||
              caseType.contains(q) ||
              patientName.contains(q) ||
              patientNum.contains(q) ||
              remarks.contains(q);
        }).toList();
      }

      return list;
    } catch (e) {
      throw Exception('Failed to fetch dental lab cases: $e');
    }
  }

  /// Fetches a single dental lab case by ID.
  Future<DentalLabModel?> fetchCaseById(String id) async {
    try {
      final response = await _client
          .from('dental_lab')
          .select('*, patients(*)')
          .eq('id', id)
          .maybeSingle();

      if (response == null) return null;
      return DentalLabModel.fromJson(response);
    } catch (e) {
      throw Exception('Failed to fetch dental lab case #$id: $e');
    }
  }

  /// Concurrency-safe / formatted case number generation (e.g. DEN-YYYYMMDD-0001).
  Future<String> generateNextCaseNumber() async {
    final now = DateTime.now();
    final dateStr = DateFormat('yyyyMMdd').format(now);
    final prefix = 'DEN-$dateStr-';

    try {
      final response = await _client
          .from('dental_lab')
          .select('case_number')
          .like('case_number', '$prefix%')
          .order('case_number', ascending: false)
          .limit(1);

      if (response.isNotEmpty) {
        final lastCase = response.first['case_number'] as String;
        final parts = lastCase.split('-');
        if (parts.length >= 3) {
          final lastSeq = int.tryParse(parts.last) ?? 0;
          final nextSeq = (lastSeq + 1).toString().padLeft(4, '0');
          return '$prefix$nextSeq';
        }
      }
    } catch (_) {
      // Fallback if query fails
    }

    return '${prefix}0001';
  }

  /// Creates a new dental lab case in Supabase.
  Future<DentalLabModel> createCase({
    required String patientId,
    required String caseNumber,
    required String caseType,
    required DateTime sentDate,
    String? remarks,
  }) async {
    if (patientId.trim().isEmpty) {
      throw ArgumentError('Patient selection is required.');
    }
    if (caseNumber.trim().isEmpty) {
      throw ArgumentError('Case number is required.');
    }
    if (caseType.trim().isEmpty) {
      throw ArgumentError('Case type is required.');
    }

    final sentDateFormatted = DateFormat('yyyy-MM-dd').format(sentDate);

    try {
      final payload = {
        'patient_id': patientId,
        'case_number': caseNumber.trim(),
        'case_type': caseType.trim(),
        'status': 'processing',
        'sent_date': sentDateFormatted,
        if (remarks != null && remarks.trim().isNotEmpty)
          'remarks': remarks.trim(),
      };

      final response = await _client
          .from('dental_lab')
          .insert(payload)
          .select('*, patients(*)')
          .single();

      return DentalLabModel.fromJson(response);
    } catch (e) {
      throw Exception('Failed to create dental lab case: $e');
    }
  }

  /// Updates an existing dental lab case details.
  Future<DentalLabModel> updateCase({
    required String id,
    String? caseType,
    DateTime? sentDate,
    DateTime? readyDate,
    DateTime? deliveredDate,
    String? remarks,
  }) async {
    final existing = await fetchCaseById(id);
    if (existing == null) {
      throw Exception('Dental lab case not found.');
    }

    final effectiveSent = sentDate ?? existing.sentDate;
    final effectiveReady = readyDate ?? existing.readyDate;
    final effectiveDelivered = deliveredDate ?? existing.deliveredDate;

    final validationError = DentalLabModel.validateDates(
      sentDate: effectiveSent,
      readyDate: effectiveReady,
      deliveredDate: effectiveDelivered,
    );
    if (validationError != null) {
      throw ArgumentError(validationError);
    }

    final formatter = DateFormat('yyyy-MM-dd');
    final payload = <String, dynamic>{
      if (caseType != null && caseType.trim().isNotEmpty)
        'case_type': caseType.trim(),
      if (sentDate != null) 'sent_date': formatter.format(sentDate),
      if (readyDate != null) 'ready_date': formatter.format(readyDate),
      if (deliveredDate != null)
        'delivered_date': formatter.format(deliveredDate),
      if (remarks != null) 'remarks': remarks.trim(),
    };

    try {
      final response = await _client
          .from('dental_lab')
          .update(payload)
          .eq('id', id)
          .select('*, patients(*)')
          .single();

      return DentalLabModel.fromJson(response);
    } catch (e) {
      throw Exception('Failed to update dental lab case: $e');
    }
  }

  /// Transitions a dental lab case status with appropriate date recording and validation.
  /// Status progression: processing -> ready -> delivered.
  Future<DentalLabModel> updateStatus({
    required String id,
    required String newStatus,
    DateTime? transitionDate,
  }) async {
    final statusNormalized = newStatus.trim().toLowerCase();
    if (!DentalLabModel.validStatuses.contains(statusNormalized)) {
      throw ArgumentError(
        'Invalid status "$newStatus". Must be one of: ${DentalLabModel.validStatuses.join(", ")}.',
      );
    }

    final existing = await fetchCaseById(id);
    if (existing == null) {
      throw Exception('Dental lab case not found.');
    }

    final formatter = DateFormat('yyyy-MM-dd');
    final dateToUse = transitionDate ?? DateTime.now();

    final payload = <String, dynamic>{
      'status': statusNormalized,
    };

    if (statusNormalized == 'ready') {
      final validationError = DentalLabModel.validateDates(
        sentDate: existing.sentDate,
        readyDate: dateToUse,
        deliveredDate: existing.deliveredDate,
      );
      if (validationError != null) {
        throw ArgumentError(validationError);
      }
      payload['ready_date'] = formatter.format(dateToUse);
    } else if (statusNormalized == 'delivered') {
      final validationError = DentalLabModel.validateDates(
        sentDate: existing.sentDate,
        readyDate: existing.readyDate ?? dateToUse,
        deliveredDate: dateToUse,
      );
      if (validationError != null) {
        throw ArgumentError(validationError);
      }
      payload['delivered_date'] = formatter.format(dateToUse);
      if (existing.readyDate == null) {
        payload['ready_date'] = formatter.format(existing.sentDate);
      }
    }

    try {
      final response = await _client
          .from('dental_lab')
          .update(payload)
          .eq('id', id)
          .select('*, patients(*)')
          .single();

      return DentalLabModel.fromJson(response);
    } catch (e) {
      throw Exception('Failed to update dental lab case status to "$statusNormalized": $e');
    }
  }

  /// Deletes a dental lab case from Supabase.
  Future<void> deleteCase(String id) async {
    try {
      await _client.from('dental_lab').delete().eq('id', id);
    } catch (e) {
      throw Exception('Failed to delete dental lab case: $e');
    }
  }
}
