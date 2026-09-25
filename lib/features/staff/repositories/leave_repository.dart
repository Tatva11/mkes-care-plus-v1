import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:supabase_flutter/supabase_flutter.dart';

import '../../../core/providers/supabase_provider.dart';
import '../models/leave_request.dart';

final leaveRepositoryProvider = Provider<LeaveRepository>((ref) {
  return LeaveRepository(ref.watch(supabaseProvider));
});

class LeaveRepository {
  final SupabaseClient _supabase;

  LeaveRepository(this._supabase);

  Future<List<LeaveRequest>> fetchStaffLeaveRequests(String staffId) async {
    final response = await _supabase
        .from('leave_requests')
        .select()
        .eq('staff_id', staffId)
        .order('created_at', ascending: false);
    return (response as List).map((json) => LeaveRequest.fromJson(json)).toList();
  }

  Future<List<LeaveRequest>> fetchAllPendingLeaveRequests() async {
    final response = await _supabase
        .from('leave_requests')
        .select('*, profiles!leave_requests_staff_id_fkey!inner(full_name, role)')
        .eq('status', 'pending')
        .eq('profiles.role', 'staff')
        .order('created_at', ascending: false);
    return (response as List).map((json) => LeaveRequest.fromJson(json)).toList();
  }

  Future<void> createLeaveRequest({
    required String staffId,
    required DateTime startDate,
    required DateTime endDate,
    required String reason,
  }) async {
    LeaveRequest.validateSubmission(
      startDate: startDate,
      endDate: endDate,
      reason: reason,
    );

    final days = endDate.difference(startDate).inDays + 1.0;
    if (days <= 0) {
      throw Exception('End date must be on or after the start date.');
    }

    await _supabase.from('leave_requests').insert({
      'staff_id': staffId,
      'start_date': startDate.toIso8601String().split('T').first,
      'end_date': endDate.toIso8601String().split('T').first,
      'leave_days': days,
      'reason': reason.trim(),
      'status': 'pending',
    });
  }

  Future<void> cancelLeaveRequest(String id) async {
    await _supabase.from('leave_requests').update({
      'status': 'cancelled',
      'updated_at': DateTime.now().toIso8601String(),
    }).eq('id', id).eq('status', 'pending');
  }

  Future<void> approveLeaveRequest(String id, String adminId) async {
    // 1. Update leave request
    await _supabase.from('leave_requests').update({
      'status': 'approved',
      'approved_by': adminId,
      'approved_at': DateTime.now().toIso8601String(),
      'updated_at': DateTime.now().toIso8601String(),
    }).eq('id', id);
    
    // 2. We should ideally update attendance for the approved leave days.
    // In Supabase we can do this via an edge function, trigger, or client loop (if days are few).
    // For Sprint 2 client-side, we can loop over days to upsert attendance as 'leave'.
    final req = await _supabase.from('leave_requests').select().eq('id', id).single();
    final start = DateTime.parse(req['start_date'] as String);
    final end = DateTime.parse(req['end_date'] as String);
    final staffId = req['staff_id'] as String;
    
    for (var d = start; d.isBefore(end.add(const Duration(days: 1))); d = d.add(const Duration(days: 1))) {
      // Don't mark Sunday as leave, it's a holiday
      if (d.weekday == DateTime.sunday) continue;
      
      final dateStr = d.toIso8601String().split('T').first;
      await _supabase.from('staff_attendance').upsert({
        'staff_id': staffId,
        'record_date': dateStr,
        'status': 'leave',
        'updated_at': DateTime.now().toIso8601String(),
      }, onConflict: 'staff_id, record_date');
    }
  }

  Future<void> rejectLeaveRequest(String id, String adminId, String rejectionReason) async {
    await _supabase.from('leave_requests').update({
      'status': 'rejected',
      'approved_by': adminId,
      'rejection_reason': rejectionReason,
      'updated_at': DateTime.now().toIso8601String(),
    }).eq('id', id);
  }
}
