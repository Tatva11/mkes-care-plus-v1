import 'dart:async';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:supabase_flutter/supabase_flutter.dart';

import '../../../core/providers/supabase_provider.dart';
import '../models/whatsapp_message.dart';
import '../repositories/whatsapp_repository.dart';

final whatsappConversationsProvider =
    AsyncNotifierProvider<WhatsAppConversationsNotifier, List<WhatsAppConversation>>(
  WhatsAppConversationsNotifier.new,
);

class WhatsAppConversationsNotifier
    extends AsyncNotifier<List<WhatsAppConversation>> {
  Timer? _pollingTimer;
  RealtimeChannel? _subscriptionChannel;

  @override
  Future<List<WhatsAppConversation>> build() async {
    _setupAutoRefresh();
    ref.onDispose(() {
      _pollingTimer?.cancel();
      _subscriptionChannel?.unsubscribe();
    });
    return _fetch();
  }

  void _setupAutoRefresh() {
    _pollingTimer?.cancel();
    // Periodic silent refresh every 8 seconds while provider is active
    _pollingTimer = Timer.periodic(const Duration(seconds: 8), (_) {
      silentRefresh();
    });

    try {
      final supabase = ref.read(supabaseProvider);
      _subscriptionChannel?.unsubscribe();
      _subscriptionChannel = supabase.channel('wa_inbox_live')
        .onPostgresChanges(
          event: PostgresChangeEvent.all,
          schema: 'public',
          table: 'whatsapp_message_logs',
          callback: (_) {
            silentRefresh();
            final activePhone = ref.read(activeConversationPhoneProvider);
            if (activePhone != null) {
              ref.invalidate(activeConversationMessagesProvider(activePhone));
            }
          },
        )
        .onPostgresChanges(
          event: PostgresChangeEvent.all,
          schema: 'public',
          table: 'whatsapp_messages_outbox',
          callback: (_) {
            silentRefresh();
            final activePhone = ref.read(activeConversationPhoneProvider);
            if (activePhone != null) {
              ref.invalidate(activeConversationMessagesProvider(activePhone));
            }
          },
        )
        ..subscribe();
    } catch (_) {}
  }

  Future<List<WhatsAppConversation>> _fetch() async {
    final repo = ref.read(whatsappRepositoryProvider);
    return repo.fetchConversations();
  }

  Future<void> refresh() async {
    state = const AsyncValue.loading();
    state = await AsyncValue.guard(_fetch);
    final activePhone = ref.read(activeConversationPhoneProvider);
    if (activePhone != null) {
      ref.invalidate(activeConversationMessagesProvider(activePhone));
    }
  }

  /// Silently updates conversations without showing a disruptive loading spinner
  Future<void> silentRefresh() async {
    try {
      final updated = await _fetch();
      state = AsyncValue.data(updated);
    } catch (_) {}
  }

  Future<bool> sendMessage({
    required String phone,
    String? patientId,
    required String department,
    required String messageText,
  }) async {
    final repo = ref.read(whatsappRepositoryProvider);
    final res = await repo.sendMessage(
      phone: phone,
      patientId: patientId,
      department: department,
      messageText: messageText,
    );

    if (res['success'] == true) {
      // Refresh conversations list and active conversation messages
      await silentRefresh();
      ref.invalidate(activeConversationMessagesProvider(phone));
      return true;
    }
    return false;
  }

  /// Retries sending a failed message from outbox
  Future<bool> retryMessage({
    required String outboxId,
    required String phone,
  }) async {
    final repo = ref.read(whatsappRepositoryProvider);
    final success = await repo.retryOutboxMessage(outboxId);
    if (success) {
      await silentRefresh();
      ref.invalidate(activeConversationMessagesProvider(phone));
    }
    return success;
  }

  /// Cancels a pending message from outbox
  Future<bool> cancelMessage({
    required String outboxId,
    required String phone,
  }) async {
    final repo = ref.read(whatsappRepositoryProvider);
    final success = await repo.cancelOutboxMessage(outboxId);
    if (success) {
      await silentRefresh();
      ref.invalidate(activeConversationMessagesProvider(phone));
    }
    return success;
  }

  Future<bool> linkPatient({
    required String phone,
    required String patientId,
  }) async {
    final repo = ref.read(whatsappRepositoryProvider);
    final success = await repo.linkPhoneToPatient(phone: phone, patientId: patientId);
    if (success) {
      await refresh();
    }
    return success;
  }
}

final activeConversationPhoneProvider = StateProvider<String?>((ref) => null);

/// Provides the full dedicated message history for a specific phone number.
final activeConversationMessagesProvider =
    FutureProvider.autoDispose.family<List<WhatsAppMessage>, String>((ref, phone) async {
  final repo = ref.watch(whatsappRepositoryProvider);
  return repo.fetchMessagesForPhone(phone);
});

final activeConversationProvider = Provider<WhatsAppConversation?>((ref) {
  final phone = ref.watch(activeConversationPhoneProvider);
  if (phone == null) return null;

  String clean(String p) {
    final d = p.replaceAll(RegExp(r'[^0-9]'), '');
    return d.length >= 10 ? d.substring(d.length - 10) : d;
  }

  final targetClean = clean(phone);
  final conversationsAsync = ref.watch(whatsappConversationsProvider);
  return conversationsAsync.value?.firstWhere(
    (c) => clean(c.phoneNumber) == targetClean,
    orElse: () => WhatsAppConversation(
      phoneNumber: targetClean,
      lastMessage: '',
      lastTimestamp: DateTime.now(),
      messages: [],
    ),
  );
});

final whatsappSettingsProvider =
    FutureProvider.autoDispose<Map<String, dynamic>?>((ref) async {
  final repo = ref.watch(whatsappRepositoryProvider);
  return repo.fetchSettings();
});

final whatsappTemplatesProvider =
    FutureProvider.autoDispose<List<Map<String, dynamic>>>((ref) async {
  final repo = ref.watch(whatsappRepositoryProvider);
  return repo.fetchTemplates();
});

final whatsappOutboxStatsProvider =
    FutureProvider.autoDispose<Map<String, int>>((ref) async {
  final repo = ref.watch(whatsappRepositoryProvider);
  return repo.fetchOutboxStats();
});
