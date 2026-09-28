import 'dart:async';

import 'package:flutter/foundation.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:supabase_flutter/supabase_flutter.dart';

import '../../../core/providers/supabase_provider.dart';
import '../../auth/providers/auth_provider.dart';
import '../models/notification_model.dart';
import '../repositories/notification_repository.dart';

// ---------------------------------------------------------------------------
// Provider — fetches real notifications for the current user from Supabase
// and keeps them synchronized via Supabase Realtime postgres changes.
// ---------------------------------------------------------------------------
final notificationsProvider = StateNotifierProvider<NotificationsNotifier,
    AsyncValue<List<NotificationModel>>>(
  (ref) {
    final repo = ref.watch(notificationRepositoryProvider);
    final supabase = ref.watch(supabaseProvider);
    final user = ref.watch(currentUserProvider);
    return NotificationsNotifier(repo, supabase, user?.id);
  },
);

final unreadNotificationCountProvider = Provider<int>((ref) {
  final notifAsync = ref.watch(notificationsProvider);
  return notifAsync.valueOrNull?.where((n) => !n.isRead).length ?? 0;
});

class NotificationsNotifier
    extends StateNotifier<AsyncValue<List<NotificationModel>>> {
  final NotificationRepository _repository;
  final SupabaseClient _supabase;
  final String? _initialUserId;
  RealtimeChannel? _realtimeChannel;
  StreamSubscription<AuthState>? _authSub;

  NotificationsNotifier(this._repository, this._supabase, this._initialUserId)
      : super(const AsyncValue.loading()) {
    final uid = currentUserId;
    if (uid != null) {
      debugPrint('[NotificationsNotifier] Initialized for user: $uid');
      fetch();
      _setupRealtime();
    } else {
      debugPrint('[NotificationsNotifier] Initialized with null user ID; waiting for session');
      state = const AsyncValue.data([]);
    }

    // Auto-sync when auth state changes (e.g. login, token refresh, initial session)
    _authSub = _supabase.auth.onAuthStateChange.listen((data) {
      final activeUid = data.session?.user.id ?? _supabase.auth.currentUser?.id;
      if (activeUid != null) {
        debugPrint('[NotificationsNotifier] Auth state changed (event=${data.event}, uid=$activeUid) -> refreshing notifications');
        fetch();
        _setupRealtime();
      } else if (data.event == AuthChangeEvent.signedOut) {
        debugPrint('[NotificationsNotifier] User signed out; clearing channel & notifications');
        _realtimeChannel?.unsubscribe();
        _realtimeChannel = null;
        state = const AsyncValue.data([]);
      }
    });
  }

  /// Resolves the current user's UUID, preferring the live Supabase Auth session.
  String? get currentUserId => _supabase.auth.currentUser?.id ?? _initialUserId;

  void _setupRealtime() {
    final uid = currentUserId;
    if (uid == null) return;
    try {
      _realtimeChannel?.unsubscribe();
      debugPrint('[NotificationsNotifier] Subscribing to notifications channel for user: $uid');
      _realtimeChannel = _supabase
          .channel('public:notifications:$uid')
          .onPostgresChanges(
            event: PostgresChangeEvent.all,
            schema: 'public',
            table: 'notifications',
            callback: (payload) {
              debugPrint('[NotificationsNotifier Realtime] Event ${payload.eventType} received on notifications table. Refreshing for $uid');
              fetch();
            },
          )
          .subscribe((status, [error]) {
            debugPrint('[NotificationsNotifier Realtime] Status: $status, error: $error');
          });
    } catch (e) {
      debugPrint('[NotificationsNotifier ERROR] Realtime subscription failed: $e');
    }
  }

  @override
  void dispose() {
    debugPrint('[NotificationsNotifier] Disposing notifier for user: $currentUserId');
    _authSub?.cancel();
    _realtimeChannel?.unsubscribe();
    super.dispose();
  }

  Future<void> fetch() async {
    final uid = currentUserId;
    if (uid == null) {
      debugPrint('[NotificationsNotifier] Cannot fetch: no authenticated user found');
      state = const AsyncValue.data([]);
      return;
    }
    try {
      debugPrint('[NotificationsNotifier] Fetching notifications for user: $uid');
      final items = await _repository.fetchForUser(uid);
      state = AsyncValue.data(items);
      debugPrint('[NotificationsNotifier SUCCESS] Fetched ${items.length} notification(s) for user: $uid');
    } catch (e, st) {
      debugPrint('[NotificationsNotifier ERROR] fetch error for $uid: $e');
      state = AsyncValue.error(e, st);
    }
  }

  Future<void> markRead(String id) async {
    final current = state.valueOrNull ?? [];
    // Optimistic update
    state = AsyncValue.data([
      for (final n in current)
        if (n.id == id) n.copyWith(isRead: true) else n,
    ]);
    try {
      await _repository.markRead(id);
    } catch (e) {
      debugPrint('[NotificationsNotifier ERROR] markRead error: $e');
      await fetch();
    }
  }

  Future<void> markAllRead() async {
    final uid = currentUserId;
    if (uid == null) return;
    final current = state.valueOrNull ?? [];
    // Optimistic update
    state = AsyncValue.data([
      for (final n in current) n.copyWith(isRead: true),
    ]);
    try {
      await _repository.markAllRead(uid);
    } catch (e) {
      debugPrint('[NotificationsNotifier ERROR] markAllRead error: $e');
      await fetch();
    }
  }

  Future<void> delete(String id) async {
    final current = state.valueOrNull ?? [];
    // Optimistic update
    state = AsyncValue.data(current.where((n) => n.id != id).toList());
    try {
      await _repository.delete(id);
    } catch (e) {
      debugPrint('[NotificationsNotifier ERROR] delete error: $e');
      await fetch();
    }
  }

  Future<void> deleteAll() async {
    final uid = currentUserId;
    if (uid == null) return;
    // Optimistic update
    state = const AsyncValue.data([]);
    try {
      await _repository.deleteAll(uid);
    } catch (e) {
      debugPrint('[NotificationsNotifier ERROR] deleteAll error: $e');
      await fetch();
    }
  }

  int get unreadCount =>
      (state.valueOrNull ?? []).where((n) => !n.isRead).length;
}
