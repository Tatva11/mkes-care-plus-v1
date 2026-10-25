import 'package:flutter/foundation.dart';
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
        .select('*, profiles!leave_requests_staff_id_fkey(full_name)')
        .eq('staff_id', staffId)
        .order('created_at', ascending: false);
    return (response as List).map((json) => LeaveRequest.fromJson(json)).toList();
  }

  /// All leave requests (pending + non-pending) with staff names for the admin view.
  Future<List<LeaveRequest>> fetchAllLeaveRequests() async {
    final response = await _supabase
        .from('leave_requests')
        .select('*, profiles!leave_requests_staff_id_fkey(full_name)')
        .order('created_at', ascending: false);
    return (response as List).map((json) => LeaveRequest.fromJson(json)).toList();
  }

  Future<List<LeaveRequest>> fetchAllPendingLeaveRequests() async {
    final response = await _supabase
        .from('leave_requests')
        .select('*, profiles!leave_requests_staff_id_fkey(full_name)')
        .eq('status', 'pending')
        .order('created_at', ascending: false);
    return (response as List).map((json) => LeaveRequest.fromJson(json)).toList();
  }

  /// Calculates leave days excluding Sundays (the weekly holiday),
  /// accounting for partial-day duties (morning/afternoon = 0.5 days).
  static double calculateLeaveDays(
    DateTime start,
    DateTime end, {
    String dutyPeriod = 'full_day',
  }) {
    double count = 0;
    final normalized = dutyPeriod.toLowerCase();
    final isPartial = normalized == 'morning' || normalized == 'afternoon';
    for (var d = start;
        !d.isAfter(end);
        d = d.add(const Duration(days: 1))) {
      if (d.weekday != DateTime.sunday) {
        count += isPartial ? 0.5 : 1.0;
      }
    }
    return count;
  }

  static bool _isValidUuid(String? value) {
    if (value == null) return false;
    return RegExp(
      r'^[0-9a-fA-F]{8}-[0-9a-fA-F]{4}-[0-9a-fA-F]{4}-[0-9a-fA-F]{4}-[0-9a-fA-F]{12}$',
    ).hasMatch(value);
  }

  Future<void> createLeaveRequest({
    required String staffId,
    required DateTime startDate,
    required DateTime endDate,
    required String reason,
    String dutyPeriod = 'full_day',
  }) async {
    // Exclude Sundays when calculating leave days and account for duty period.
    final days = calculateLeaveDays(startDate, endDate, dutyPeriod: dutyPeriod);
    if (days <= 0) throw Exception('Selected date range contains no working days (Sundays are excluded).');

    final normalizedDuty = dutyPeriod.toLowerCase();

    final response = await _supabase.from('leave_requests').insert({
      'staff_id': staffId,
      'start_date': startDate.toIso8601String().split('T').first,
      'end_date': endDate.toIso8601String().split('T').first,
      'leave_days': days,
      'reason': reason,
      'status': 'pending',
      'duty_period': normalizedDuty,
    }).select().single();

    final leaveId = response['id'] as String?;
    final validLeaveId = _isValidUuid(leaveId) ? leaveId : null;

    // Notify all admins about the new leave request.
    try {
      final staffProfile = await _supabase
          .from('profiles')
          .select('full_name')
          .eq('id', staffId)
          .maybeSingle();
      final staffName = (staffProfile?['full_name'] as String?) ?? 'A staff member';
      final message = '$staffName has requested leave from '
          '${startDate.toIso8601String().split('T').first} to '
          '${endDate.toIso8601String().split('T').first}.';

      debugPrint('[LeaveRepository] Creating leave request notification for admins. Staff: $staffName ($staffId)');

      // 1. Try SECURITY DEFINER RPC
      bool rpcSuccess = false;
      try {
        await _supabase.rpc('notify_all_admins', params: {
          'p_title': 'New Leave Request',
          'p_message': message,
          'p_type': 'leave_request',
          'p_related_id': validLeaveId,
        });
        rpcSuccess = true;
        debugPrint('[LeaveRepository] notify_all_admins RPC succeeded for leave request');
      } catch (rpcErr) {
        debugPrint('[LeaveRepository] notify_all_admins RPC error: $rpcErr');
      }

      // 2. Direct fallback if RPC failed
      if (!rpcSuccess) {
        debugPrint('[LeaveRepository] Falling back to direct admin profile query and notification insert');
        try {
          final admins = await _supabase
              .from('profiles')
              .select('id')
              .eq('role', 'admin')
              .eq('is_active', true);

          for (final admin in (admins as List)) {
            final adminId = admin['id'] as String;
            await _supabase.from('notifications').insert({
              'user_id': adminId,
              'title': 'New Leave Request',
              'message': message,
              'type': 'leave_request',
              if (validLeaveId != null) 'related_id': validLeaveId,
            });
            debugPrint('[LeaveRepository] Direct notification inserted for admin $adminId');
          }
        } catch (directErr) {
          debugPrint('[LeaveRepository] Direct admin notification fallback failed: $directErr');
        }
      }
    } catch (e) {
      // Notification failure is non-critical — log but don't rethrow.
      debugPrint('[LeaveRepository] FAILED to send admin notifications: $e');
    }
  }

  Future<void> cancelLeaveRequest(String id) async {
    await _supabase.from('leave_requests').update({
      'status': 'cancelled',
      'updated_at': DateTime.now().toIso8601String(),
    }).eq('id', id).eq('status', 'pending');
  }

  Future<void> approveLeaveRequest(String id, String adminId) async {
    // 1. Update leave request status.
    await _supabase.from('leave_requests').update({
      'status': 'approved',
      'approved_by': adminId,
      'approved_at': DateTime.now().toIso8601String(),
      'updated_at': DateTime.now().toIso8601String(),
    }).eq('id', id);

    // 2. Mark attendance records as 'leave' for each working day in the range.
    final req = await _supabase
        .from('leave_requests')
        .select()
        .eq('id', id)
        .single();
    final start = DateTime.parse(req['start_date'] as String);
    final end = DateTime.parse(req['end_date'] as String);
    final staffId = req['staff_id'] as String;

    final dutyPeriod =
        (req['duty_period'] as String?)?.toLowerCase() ?? 'full_day';

    final shiftsToMark = <String>[];
    if (dutyPeriod == 'morning') {
      shiftsToMark.add('morning');
    } else if (dutyPeriod == 'afternoon' || dutyPeriod == 'evening') {
      shiftsToMark.add('afternoon');
    } else {
      shiftsToMark.addAll(['morning', 'afternoon']);
    }

    for (var d = start;
        !d.isAfter(end);
        d = d.add(const Duration(days: 1))) {
      // Sunday is the weekly holiday — skip.
      if (d.weekday == DateTime.sunday) continue;

      final dateStr = d.toIso8601String().split('T').first;
      for (final shift in shiftsToMark) {
        await _supabase.from('staff_attendance').upsert({
          'staff_id': staffId,
          'record_date': dateStr,
          'shift': shift,
          'status': 'leave',
          'updated_at': DateTime.now().toIso8601String(),
        }, onConflict: 'staff_id, record_date, shift');
      }
    }

    // 3. Notify the staff member.
    try {
      final validId = _isValidUuid(id) ? id : null;
      debugPrint('[LeaveRepository] Sending leave approval notification to staff $staffId');
      await _notifyUser(
        userId: staffId,
        title: 'Leave Approved',
        message: 'Your leave request from '
            '${start.toIso8601String().split('T').first} to '
            '${end.toIso8601String().split('T').first} has been approved.',
        type: 'leave_approved',
        relatedId: validId,
      );
      debugPrint('[LeaveRepository] Leave approval notification successfully sent for $staffId');
    } catch (e) {
      debugPrint('[LeaveRepository] FAILED to notify staff on approval: $e');
    }
  }

  Future<void> rejectLeaveRequest(
      String id, String adminId, String rejectionReason) async {
    await _supabase.from('leave_requests').update({
      'status': 'rejected',
      'approved_by': adminId,
      'rejection_reason': rejectionReason,
      'updated_at': DateTime.now().toIso8601String(),
    }).eq('id', id);

    // Notify the staff member.
    try {
      final req = await _supabase
          .from('leave_requests')
          .select('staff_id, start_date, end_date')
          .eq('id', id)
          .single();
      final staffId = req['staff_id'] as String;
      final start = req['start_date'] as String;
      final end = req['end_date'] as String;
      final validId = _isValidUuid(id) ? id : null;

      debugPrint('[LeaveRepository] Sending leave rejection notification to staff $staffId');
      await _notifyUser(
        userId: staffId,
        title: 'Leave Rejected',
        message: 'Your leave request from $start to $end was rejected. '
            'Reason: $rejectionReason',
        type: 'leave_rejected',
        relatedId: validId,
      );
      debugPrint('[LeaveRepository] Leave rejection notification successfully sent for $staffId');
    } catch (e) {
      debugPrint('[LeaveRepository] FAILED to notify staff on rejection: $e');
    }
  }

  /// Internal helper to send a notification to a specific user,
  /// trying the SECURITY DEFINER RPC `notify_user` first, then direct insert.
  Future<void> _notifyUser({
    required String userId,
    required String title,
    required String message,
    required String type,
    String? relatedId,
  }) async {
    final validRelatedId = _isValidUuid(relatedId) ? relatedId : null;
    try {
      await _supabase.rpc('notify_user', params: {
        'p_user_id': userId,
        'p_title': title,
        'p_message': message,
        'p_type': type,
        'p_related_id': validRelatedId,
      });
      debugPrint('[LeaveRepository SUCCESS] notify_user RPC sent notification to user $userId');
      return;
    } catch (rpcErr) {
      debugPrint('[LeaveRepository] notify_user RPC unavailable ($rpcErr). Falling back to direct insert.');
    }

    await _supabase.from('notifications').insert({
      'user_id': userId,
      'title': title,
      'message': message,
      'type': type,
      if (validRelatedId != null) 'related_id': validRelatedId,
    });
    debugPrint('[LeaveRepository SUCCESS] Direct notification inserted for user $userId');
  }
}
