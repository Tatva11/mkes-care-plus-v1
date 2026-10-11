import 'package:flutter/foundation.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:supabase_flutter/supabase_flutter.dart';

import '../../../core/providers/supabase_provider.dart';
import '../models/notification_model.dart';

final notificationRepositoryProvider = Provider<NotificationRepository>((ref) {
  return NotificationRepository(ref.watch(supabaseProvider));
});

class NotificationRepository {
  final SupabaseClient _supabase;

  NotificationRepository(this._supabase);

  static bool _isValidUuid(String? value) {
    if (value == null) return false;
    return RegExp(
      r'^[0-9a-fA-F]{8}-[0-9a-fA-F]{4}-[0-9a-fA-F]{4}-[0-9a-fA-F]{4}-[0-9a-fA-F]{12}$',
    ).hasMatch(value);
  }

  static bool _isCheckConstraintViolation(Object err) {
    final s = err.toString().toLowerCase();
    return s.contains('23514') ||
        s.contains('check constraint') ||
        s.contains('notifications_type_check');
  }

  /// Fetch all notifications for the given user, newest first.
  Future<List<NotificationModel>> fetchForUser(String userId) async {
    try {
      debugPrint('[NotificationRepo] Fetching notifications for user: $userId');
      final response = await _supabase
          .from('notifications')
          .select()
          .eq('user_id', userId)
          .order('created_at', ascending: false)
          .limit(50);

      final items = (response as List)
          .map((json) => NotificationModel.fromJson(json))
          .toList();
      debugPrint('[NotificationRepo] Successfully fetched ${items.length} notification(s) for user: $userId');
      return items;
    } catch (e, st) {
      debugPrint('[NotificationRepo ERROR] fetchForUser failed for $userId: $e\n$st');
      rethrow;
    }
  }

  /// Mark a single notification as read.
  Future<void> markRead(String notificationId) async {
    try {
      debugPrint('[NotificationRepo] Marking notification $notificationId as read');
      await _supabase
          .from('notifications')
          .update({'is_read': true})
          .eq('id', notificationId);
      debugPrint('[NotificationRepo SUCCESS] Marked notification $notificationId as read');
    } catch (e) {
      debugPrint('[NotificationRepo ERROR] markRead failed for $notificationId: $e');
      rethrow;
    }
  }

  /// Mark all notifications for a user as read.
  Future<void> markAllRead(String userId) async {
    try {
      debugPrint('[NotificationRepo] Marking all notifications as read for user $userId');
      await _supabase
          .from('notifications')
          .update({'is_read': true})
          .eq('user_id', userId)
          .eq('is_read', false);
      debugPrint('[NotificationRepo SUCCESS] Marked all notifications as read for user $userId');
    } catch (e) {
      debugPrint('[NotificationRepo ERROR] markAllRead failed for $userId: $e');
      rethrow;
    }
  }

  /// Delete a single notification.
  Future<void> delete(String notificationId) async {
    try {
      debugPrint('[NotificationRepo] Deleting notification $notificationId');
      await _supabase
          .from('notifications')
          .delete()
          .eq('id', notificationId);
      debugPrint('[NotificationRepo SUCCESS] Deleted notification $notificationId');
    } catch (e) {
      debugPrint('[NotificationRepo ERROR] delete failed for $notificationId: $e');
      rethrow;
    }
  }

  /// Delete all notifications for a user.
  Future<void> deleteAll(String userId) async {
    try {
      debugPrint('[NotificationRepo] Deleting all notifications for user $userId');
      await _supabase
          .from('notifications')
          .delete()
          .eq('user_id', userId);
      debugPrint('[NotificationRepo SUCCESS] Deleted all notifications for user $userId');
    } catch (e) {
      debugPrint('[NotificationRepo ERROR] deleteAll failed for $userId: $e');
      rethrow;
    }
  }

  /// Insert a notification for a specific user.
  /// If [idempotent] is true, checks for existing notification with same user, title, and message
  /// to avoid duplicate delivery on retries.
  /// First attempts the SECURITY DEFINER RPC `notify_user` to bypass any client RLS limits.
  /// Falls back to direct INSERT if the RPC is not loaded.
  /// If the remote database check constraint rejects custom types (e.g., 'duty_assignment' before migration),
  /// automatically retries with 'system' so notification creation never fails.
  Future<void> insertNotification({
    required String userId,
    required String title,
    required String message,
    required String type,
    String? relatedId,
    bool idempotent = false,
  }) async {
    final validRelatedId = _isValidUuid(relatedId) ? relatedId : null;

    if (idempotent) {
      try {
        final existing = await _supabase
            .from('notifications')
            .select('id')
            .eq('user_id', userId)
            .eq('title', title)
            .eq('message', message)
            .limit(1);
        if (existing.isNotEmpty) {
          debugPrint('[NotificationRepo] Idempotent notification already exists for user $userId. Skipping duplicate insert.');
          return;
        }
      } catch (checkErr) {
        debugPrint('[NotificationRepo] Idempotency check error ($checkErr). Proceeding with insert.');
      }
    }

    // 1. Try SECURITY DEFINER RPC notify_user
    try {
      debugPrint('[NotificationRepo] Attempting notify_user RPC for user: $userId (type: $type, title: "$title")');
      final params = <String, dynamic>{
        'p_user_id': userId,
        'p_title': title,
        'p_message': message,
        'p_type': type,
        if (validRelatedId != null) 'p_related_id': validRelatedId,
      };
      await _supabase.rpc('notify_user', params: params);
      debugPrint('[NotificationRepo SUCCESS] notify_user RPC succeeded for user: $userId');
      return;
    } catch (rpcErr) {
      if (_isCheckConstraintViolation(rpcErr) && type != 'system') {
        debugPrint('[NotificationRepo] notify_user RPC failed with check constraint for type "$type". Retrying with fallback "system"...');
        try {
          final fallbackParams = <String, dynamic>{
            'p_user_id': userId,
            'p_title': title,
            'p_message': message,
            'p_type': 'system',
            if (validRelatedId != null) 'p_related_id': validRelatedId,
          };
          await _supabase.rpc('notify_user', params: fallbackParams);
          debugPrint('[NotificationRepo SUCCESS] notify_user RPC succeeded with fallback type "system" for user: $userId');
          return;
        } catch (fallbackRpcErr) {
          debugPrint('[NotificationRepo] Fallback notify_user RPC also failed: $fallbackRpcErr');
        }
      }
      debugPrint('[NotificationRepo] notify_user RPC unavailable or failed ($rpcErr). Falling back to direct insert...');
    }

    // 2. Direct INSERT fallback
    try {
      debugPrint('[NotificationRepo] Inserting notification directly for user: $userId');
      await _supabase.from('notifications').insert({
        'user_id': userId,
        'title': title,
        'message': message,
        'type': type,
        if (validRelatedId != null) 'related_id': validRelatedId,
      });
      debugPrint('[NotificationRepo SUCCESS] Notification inserted successfully for user: $userId');
    } catch (e) {
      if (_isCheckConstraintViolation(e) && type != 'system') {
        debugPrint('[NotificationRepo] Direct insert failed with check constraint for type "$type". Retrying with fallback "system"...');
        try {
          await _supabase.from('notifications').insert({
            'user_id': userId,
            'title': title,
            'message': message,
            'type': 'system',
            if (validRelatedId != null) 'related_id': validRelatedId,
          });
          debugPrint('[NotificationRepo SUCCESS] Direct insert succeeded with fallback type "system" for user: $userId');
          return;
        } catch (fallbackDirectErr) {
          debugPrint('[NotificationRepo ERROR] Fallback direct insert failed: $fallbackDirectErr');
          rethrow;
        }
      }
      debugPrint('[NotificationRepo ERROR] insertNotification failed for user $userId: $e');
      rethrow;
    }
  }

  /// Notify all active administrators.
  /// First calls the SECURITY DEFINER RPC `notify_all_admins`.
  /// Falls back to direct insert if RPC isn't loaded.
  Future<void> notifyAllAdmins({
    required String title,
    required String message,
    required String type,
    String? relatedId,
  }) async {
    final validRelatedId = _isValidUuid(relatedId) ? relatedId : null;

    // 1. Try SECURITY DEFINER RPC
    try {
      debugPrint('[NotificationRepo] Attempting notify_all_admins RPC...');
      await _supabase.rpc('notify_all_admins', params: {
        'p_title': title,
        'p_message': message,
        'p_type': type,
        'p_related_id': validRelatedId,
      });
      debugPrint('[NotificationRepo SUCCESS] notify_all_admins RPC succeeded.');
      return;
    } catch (e) {
      debugPrint('[NotificationRepo] notify_all_admins RPC not found or failed: $e. Falling back to direct admin lookup...');
    }

    // 2. Direct fallback
    try {
      final admins = await _supabase
          .from('profiles')
          .select('id')
          .eq('role', 'admin')
          .eq('is_active', true);

      final adminList = admins as List;
      debugPrint('[NotificationRepo] Found ${adminList.length} active admin(s) for notification.');

      for (final admin in adminList) {
        final adminId = admin['id'] as String;
        await insertNotification(
          userId: adminId,
          title: title,
          message: message,
          type: type,
          relatedId: validRelatedId,
        );
      }
    } catch (e) {
      debugPrint('[NotificationRepo ERROR] Direct notify admins fallback failed: $e');
    }
  }
}
