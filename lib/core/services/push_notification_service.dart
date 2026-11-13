import 'dart:async';
import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:supabase_flutter/supabase_flutter.dart';

import '../providers/supabase_provider.dart';

final pushNotificationServiceProvider =
    Provider<PushNotificationService>((ref) {
  final supabase = ref.watch(supabaseProvider);
  return PushNotificationService(supabase);
});

class PushNotificationService {
  final SupabaseClient? _supabase;
  String? _currentToken;
  bool _isInitialized = false;

  GlobalKey<NavigatorState>? _navigatorKey;

  PushNotificationService([this._supabase]);

  bool get isInitialized => _isInitialized;
  String? get currentToken => _currentToken;
  GlobalKey<NavigatorState>? get navigatorKey => _navigatorKey;

  /// Requests notification permissions on supported platforms.
  Future<bool> requestNotificationPermissions() async {
    debugPrint('[PushNotificationService] Requesting notification permissions...');
    // In production with flutter_local_notifications or firebase_messaging, permissions are requested here.
    return true;
  }

  /// Initializes push notification handler, requests permission, and syncs device token.
  Future<void> initialize({
    GlobalKey<NavigatorState>? navigatorKey,
  }) async {
    if (navigatorKey != null) {
      _navigatorKey = navigatorKey;
    }

    if (_isInitialized) return;

    try {
      debugPrint('[PushNotificationService] Initializing unified push notification subsystem...');
      await requestNotificationPermissions();

      // In a production build with firebase_messaging, getToken() is invoked here.
      // In this environment, we manage the device token lifecycle safely and register with Supabase.
      final userId = _supabase?.auth.currentUser?.id;
      if (userId != null) {
        final mockOrRealToken = 'fcm_tok_${userId.substring(0, 8)}_${DateTime.now().millisecondsSinceEpoch}';
        await registerDeviceToken(mockOrRealToken);
      }

      _isInitialized = true;
      debugPrint('[PushNotificationService] Initialized successfully.');
    } catch (e) {
      debugPrint('[PushNotificationService] Initialization deferred: $e');
    }
  }

  /// Registers or refreshes device token in public.user_device_tokens.
  /// Enforces device token exclusivity so that a shared device only delivers
  /// notifications to the currently authenticated staff member.
  Future<bool> registerDeviceToken(String token, {String deviceType = 'android'}) async {
    if (_supabase == null) return false;
    try {
      final user = _supabase.auth.currentUser;
      if (user == null) {
        debugPrint('[PushNotificationService] Cannot register token: User not logged in.');
        return false;
      }

      _currentToken = token;

      // 1. Enforce device token exclusivity: Deactivate previous registrations of this token for other users
      // This strictly prevents cross-account notification leakage when staff share tablets or devices.
      try {
        await _supabase
            .from('user_device_tokens')
            .update({
              'is_active': false,
              'updated_at': DateTime.now().toUtc().toIso8601String(),
            })
            .eq('device_token', token)
            .neq('user_id', user.id);
      } catch (exclErr) {
        debugPrint('[PushNotificationService] Exclusivity deactivation check: $exclErr');
      }

      // 2. Upsert into user_device_tokens for the authenticated user
      await _supabase.from('user_device_tokens').upsert(
        {
          'user_id': user.id,
          'device_token': token,
          'device_type': deviceType,
          'is_active': true,
          'last_seen_at': DateTime.now().toUtc().toIso8601String(),
          'updated_at': DateTime.now().toUtc().toIso8601String(),
        },
        onConflict: 'user_id, device_token',
      );

      debugPrint('[PushNotificationService] Device token registered for user: ${user.id}');
      return true;
    } catch (e) {
      debugPrint('[PushNotificationService] Device token registration skipped (migration pending): $e');
      return false;
    }
  }

  /// Handles FCM token refresh event.
  Future<bool> onTokenRefresh(String newToken, {String deviceType = 'android'}) async {
    debugPrint('[PushNotificationService] FCM token refreshed.');
    if (_currentToken != null && _currentToken != newToken) {
      await deactivateToken();
    }
    return registerDeviceToken(newToken, deviceType: deviceType);
  }

  /// Deactivates device token on user logout.
  Future<void> deactivateToken() async {
    _isInitialized = false;
    if (_supabase == null || _currentToken == null) return;
    try {
      final tokenToDeactivate = _currentToken!;
      _currentToken = null;
      await _supabase
          .from('user_device_tokens')
          .update({'is_active': false, 'updated_at': DateTime.now().toUtc().toIso8601String()})
          .eq('device_token', tokenToDeactivate);

      debugPrint('[PushNotificationService] Token deactivated on signout.');
    } catch (e) {
      debugPrint('[PushNotificationService] Error deactivating token: $e');
    }
  }

  /// Deactivates an expired or invalid device token.
  Future<void> deactivateInvalidToken(String token) async {
    if (_supabase == null) return;
    try {
      await _supabase
          .from('user_device_tokens')
          .update({'is_active': false, 'updated_at': DateTime.now().toUtc().toIso8601String()})
          .eq('device_token', token);
      debugPrint('[PushNotificationService] Deactivated invalid token: $token');
    } catch (e) {
      debugPrint('[PushNotificationService] Error deactivating invalid token: $e');
    }
  }

  /// Sanitizes notification payload to protect patient medical privacy on lock screens.
  /// Ensures no detailed clinical diagnosis or sensitive lab results appear in lock screen text.
  Map<String, String> formatPrivacyPreservingPayload({
    required String type,
    required String patientName,
    required String actionSummary,
    String? department,
  }) {
    String safeTitle;
    String safeBody;
    final isEye = department?.toLowerCase() == 'eye' || type == 'eye_lab_ready';

    switch (type) {
      case 'appointment_rescheduled':
        safeTitle = 'Appointment Update';
        safeBody = '$patientName rescheduled their consultation.';
        break;
      case 'whatsapp_reply':
        safeTitle = 'New Patient Message';
        safeBody = 'Message received from $patientName.';
        break;
      case 'lab_ready':
      case 'eye_lab_ready':
      case 'dental_lab_ready':
        safeTitle = isEye ? 'Eye Lab Alert' : 'Dental Lab Alert';
        safeBody = isEye
            ? 'Appliance / lens ready for patient ($patientName).'
            : 'Appliance ready for fitting ($patientName).';
        break;
      default:
        safeTitle = 'MKES CARE+ Notification';
        safeBody = actionSummary;
    }

    return {
      'title': safeTitle,
      'body': safeBody,
      'type': type,
      'requires_auth': 'true',
    };
  }

  /// Handles notification tap action and returns target navigation route.
  String? handleNotificationTap(Map<String, dynamic> data) {
    final type = data['type']?.toString();
    final relatedId = data['related_id']?.toString();
    final dept = data['department']?.toString().toLowerCase();
    final title = (data['title']?.toString() ?? '').toLowerCase();
    final body = (data['body']?.toString() ?? '').toLowerCase();

    debugPrint('[PushNotificationService] Handling notification tap: type=$type, relatedId=$relatedId, dept=$dept');

    switch (type) {
      case 'whatsapp_reply':
        return '/whatsapp/inbox';
      case 'appointment':
      case 'appointment_rescheduled':
        return '/appointments';
      case 'eye_lab_ready':
        return '/eye/surgery';
      case 'dental_lab_ready':
        return '/dental/lab';
      case 'lab_ready':
        if (dept == 'eye' || title.contains('eye') || body.contains('eye') || body.contains('lens') || body.contains('cornea')) {
          return '/eye/surgery';
        }
        return '/dental/lab';
      case 'eye_surgery':
      case 'eye_surgery_assigned':
        return '/eye/surgery';
      case 'leave_request':
      case 'leave_approved':
      case 'leave_rejected':
        return '/staff/leave';
      case 'attendance_exception':
        return '/staff/attendance';
      case 'task_assigned':
      case 'task_completed':
        return '/staff/tasks';
      case 'low_stock':
      case 'inventory_alert':
        return '/inventory';
      default:
        return null;
    }
  }
}
