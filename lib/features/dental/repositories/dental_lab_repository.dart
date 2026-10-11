import 'package:intl/intl.dart';
import 'package:supabase_flutter/supabase_flutter.dart';
import '../models/dental_lab_model.dart';

class DentalLabRepository {
  DentalLabRepository({SupabaseClient? client})
      : _client = client ?? Supabase.instance.client;

  final SupabaseClient _client;

  static const String _dentalLabSelectWithAppointment =
      '*, patients(*), appointments(*)';
  static const String _dentalLabSelectWithoutAppointment =
      '*, patients(*)';

  /// Fetches dental lab cases with joined patient and appointment details.
  Future<List<DentalLabModel>> fetchCases({
    String? status,
    String? patientId,
    String? searchQuery,
  }) async {
    try {
      dynamic response;
      try {
        var query = _client.from('dental_lab').select(_dentalLabSelectWithAppointment);

        if (status != null && status != 'all' && status.isNotEmpty) {
          query = query.eq('status', status.toLowerCase());
        }

        if (patientId != null && patientId.isNotEmpty) {
          query = query.eq('patient_id', patientId);
        }

        response = await query.order('created_at', ascending: false);
      } catch (_) {
        var query = _client.from('dental_lab').select(_dentalLabSelectWithoutAppointment);

        if (status != null && status != 'all' && status.isNotEmpty) {
          query = query.eq('status', status.toLowerCase());
        }

        if (patientId != null && patientId.isNotEmpty) {
          query = query.eq('patient_id', patientId);
        }

        response = await query.order('created_at', ascending: false);
      }

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

  /// Fetches a single dental lab case by ID with full relations.
  Future<DentalLabModel?> fetchCaseById(String id) async {
    try {
      dynamic response;
      try {
        response = await _client
            .from('dental_lab')
            .select(_dentalLabSelectWithAppointment)
            .eq('id', id)
            .maybeSingle();
      } catch (_) {
        response = await _client
            .from('dental_lab')
            .select(_dentalLabSelectWithoutAppointment)
            .eq('id', id)
            .maybeSingle();
      }

      if (response == null) return null;
      return DentalLabModel.fromJson(response as Map<String, dynamic>);
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

  /// Creates a new dental lab case in Supabase with server-side dental patient validation.
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

    // Server-side Dental department enforcement
    try {
      final patientRow = await _client
          .from('patients')
          .select('id, department, name')
          .eq('id', patientId.trim())
          .maybeSingle();

      if (patientRow != null) {
        final dept = (patientRow['department'] as String?)?.toLowerCase();
        if (dept != null && dept != 'dental') {
          throw ArgumentError(
            'Patient "${patientRow['name']}" is registered in "$dept" department. Dental Lab cases can only be created for Dental department patients.',
          );
        }
      }
    } catch (e) {
      if (e is ArgumentError) rethrow;
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

      dynamic response;
      try {
        response = await _client
            .from('dental_lab')
            .insert(payload)
            .select(_dentalLabSelectWithAppointment)
            .single();
      } catch (_) {
        response = await _client
            .from('dental_lab')
            .insert(payload)
            .select(_dentalLabSelectWithoutAppointment)
            .single();
      }

      return DentalLabModel.fromJson(response as Map<String, dynamic>);
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
      dynamic response;
      try {
        response = await _client
            .from('dental_lab')
            .update(payload)
            .eq('id', id)
            .select(_dentalLabSelectWithAppointment)
            .single();
      } catch (_) {
        response = await _client
            .from('dental_lab')
            .update(payload)
            .eq('id', id)
            .select(_dentalLabSelectWithoutAppointment)
            .single();
      }

      return DentalLabModel.fromJson(response as Map<String, dynamic>);
    } catch (e) {
      throw Exception('Failed to update dental lab case: $e');
    }
  }

  /// Atomically and idempotently marks a dental lab case as 'ready', sets ready_date,
  /// and schedules or links a follow-up fitting appointment.
  Future<DentalLabModel> markCaseReadyWithAppointment({
    required String id,
    DateTime? readyDate,
  }) async {
    final existing = await fetchCaseById(id);
    if (existing == null) {
      throw Exception('Dental lab case not found.');
    }

    final effectiveReadyDate = readyDate ?? DateTime.now();
    final validationError = DentalLabModel.validateDates(
      sentDate: existing.sentDate,
      readyDate: effectiveReadyDate,
      deliveredDate: existing.deliveredDate,
    );
    if (validationError != null) {
      throw ArgumentError(validationError);
    }

    // 1. Try atomic RPC if available
    try {
      final rpcRes = await _client.rpc(
        'mark_dental_lab_case_ready_with_appointment',
        params: {
          'p_case_id': id,
          'p_ready_date': DateFormat('yyyy-MM-dd').format(effectiveReadyDate),
        },
      );
      if (rpcRes != null) {
        final refreshed = await fetchCaseById(id);
        if (refreshed != null) return refreshed;
      }
    } catch (_) {
      // Proceed with direct client operations if RPC is not present
    }

    // 2. Direct client operations
    String? appointmentId = existing.appointmentId;

    if (appointmentId == null && existing.patientId != null) {
      // Check if patient already has an upcoming active dental appointment
      try {
        final upcoming = await _client
            .from('appointments')
            .select('id, appointment_date, appointment_time, status')
            .eq('patient_id', existing.patientId!)
            .eq('department', 'dental')
            .inFilter('status', ['scheduled', 'confirmed', 'waiting'])
            .gte('appointment_date', DateFormat('yyyy-MM-dd').format(DateTime.now()))
            .order('appointment_date', ascending: true)
            .limit(1);

        if (upcoming.isNotEmpty) {
          appointmentId = upcoming.first['id'] as String?;
        }
      } catch (_) {}

      // If no existing upcoming appointment, schedule a follow-up appointment
      if (appointmentId == null) {
        try {
          // Schedule 2 days after ready date (skip Sunday)
          DateTime targetDate = effectiveReadyDate.add(const Duration(days: 2));
          if (targetDate.weekday == DateTime.sunday) {
            targetDate = targetDate.add(const Duration(days: 1));
          }

          // Lookup active dental doctor if available
          String? doctorId;
          try {
            final doctorRows = await _client
                .from('profiles')
                .select('id')
                .ilike('department', '%dental%')
                .eq('is_active', true)
                .limit(1);
            if (doctorRows.isNotEmpty) {
              doctorId = doctorRows.first['id'] as String?;
            }
          } catch (_) {}

          final newApptPayload = {
            'patient_id': existing.patientId,
            'department': 'dental',
            if (doctorId != null) 'doctor_id': doctorId,
            'appointment_date': DateFormat('yyyy-MM-dd').format(targetDate),
            'appointment_time': '10:30:00',
            'appointment_type': 'follow_up',
            'status': 'scheduled',
            'notes': 'Follow-up fitting for Dental Lab Case #${existing.caseNumber} (${existing.caseType})',
          };

          final apptRes = await _client
              .from('appointments')
              .insert(newApptPayload)
              .select('id')
              .single();

          appointmentId = apptRes['id'] as String?;
        } catch (e) {
          throw Exception('Failed to schedule follow-up appointment: $e');
        }
      }
    }

    final payload = <String, dynamic>{
      'status': 'ready',
      'ready_date': DateFormat('yyyy-MM-dd').format(effectiveReadyDate),
      if (appointmentId != null) 'appointment_id': appointmentId,
    };

    try {
      dynamic response;
      try {
        response = await _client
            .from('dental_lab')
            .update(payload)
            .eq('id', id)
            .select(_dentalLabSelectWithAppointment)
            .single();
      } catch (_) {
        response = await _client
            .from('dental_lab')
            .update(payload)
            .eq('id', id)
            .select(_dentalLabSelectWithoutAppointment)
            .single();
      }

      return DentalLabModel.fromJson(response as Map<String, dynamic>);
    } catch (e) {
      throw Exception('Failed to update dental lab status: $e');
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

    if (statusNormalized == 'ready') {
      return markCaseReadyWithAppointment(
        id: id,
        readyDate: transitionDate,
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

    if (statusNormalized == 'delivered') {
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
      dynamic response;
      try {
        response = await _client
            .from('dental_lab')
            .update(payload)
            .eq('id', id)
            .select(_dentalLabSelectWithAppointment)
            .single();
      } catch (_) {
        response = await _client
            .from('dental_lab')
            .update(payload)
            .eq('id', id)
            .select(_dentalLabSelectWithoutAppointment)
            .single();
      }

      return DentalLabModel.fromJson(response as Map<String, dynamic>);
    } catch (e) {
      throw Exception('Failed to update dental lab status: $e');
    }
  }

  /// Deletes a dental lab case by ID.
  Future<void> deleteCase(String id) async {
    try {
      await _client.from('dental_lab').delete().eq('id', id);
    } catch (e) {
      throw Exception('Failed to delete dental lab case #$id: $e');
    }
  }
}
