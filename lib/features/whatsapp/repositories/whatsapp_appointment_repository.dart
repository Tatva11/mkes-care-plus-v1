import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:supabase_flutter/supabase_flutter.dart';

import '../../../core/providers/supabase_provider.dart';
import '../models/whatsapp_appointment_request.dart';

final whatsappAppointmentRepositoryProvider =
    Provider<WhatsAppAppointmentRepository>((ref) {
  return WhatsAppAppointmentRepository(ref.watch(supabaseProvider));
});

class WhatsAppAppointmentRepository {
  final SupabaseClient _supabase;

  WhatsAppAppointmentRepository(this._supabase);

  /// Fetch WhatsApp appointment requests with optional status and department filters.
  Future<List<WhatsAppAppointmentRequest>> fetchRequests({
    String? status,
    String? department,
  }) async {
    try {
      var query = _supabase.from('whatsapp_appointment_requests').select('*');

      if (status != null && status.isNotEmpty && status != 'all') {
        query = query.eq('status', status.toLowerCase());
      }

      if (department != null && department.isNotEmpty && department != 'all') {
        query = query.eq('department', department.toLowerCase());
      }

      final response = await query
          .order('requested_date', ascending: true)
          .order('requested_time', ascending: true);

      return (response as List)
          .map((json) =>
              WhatsAppAppointmentRequest.fromJson(json as Map<String, dynamic>))
          .toList();
    } catch (e) {
      // In non-migrated or mock environments, fallback to empty list
      return [];
    }
  }

  /// Approve request via secure server-side RPC.
  /// Automatically creates appointment in public.appointments and enqueues WhatsApp confirmation.
  Future<Map<String, dynamic>> approveRequest({
    required String requestId,
    String? doctorId,
    String? doctorName,
  }) async {
    final response = await _supabase.rpc(
      'approve_whatsapp_appointment_request',
      params: {
        'p_request_id': requestId,
        'p_doctor_id': doctorId,
        'p_doctor_name': doctorName,
      },
    );

    if (response is Map) {
      return Map<String, dynamic>.from(response);
    }
    return {'success': false, 'message': 'Unexpected response format from server.'};
  }

  /// Reject request via secure server-side RPC.
  /// Sets request status to 'rejected' and enqueues WhatsApp rejection notice.
  Future<Map<String, dynamic>> rejectRequest({
    required String requestId,
    required String reason,
  }) async {
    final response = await _supabase.rpc(
      'reject_whatsapp_appointment_request',
      params: {
        'p_request_id': requestId,
        'p_reason': reason,
      },
    );

    if (response is Map) {
      return Map<String, dynamic>.from(response);
    }
    return {'success': false, 'message': 'Unexpected response format from server.'};
  }
}
