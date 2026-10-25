import 'package:flutter_riverpod/flutter_riverpod.dart';

import '../models/whatsapp_message.dart';
import '../repositories/whatsapp_repository.dart';

final whatsappConversationsProvider =
    AsyncNotifierProvider<WhatsAppConversationsNotifier, List<WhatsAppConversation>>(
  WhatsAppConversationsNotifier.new,
);

class WhatsAppConversationsNotifier
    extends AsyncNotifier<List<WhatsAppConversation>> {
  @override
  Future<List<WhatsAppConversation>> build() async {
    return _fetch();
  }

  Future<List<WhatsAppConversation>> _fetch() async {
    final repo = ref.read(whatsappRepositoryProvider);
    return repo.fetchConversations();
  }

  Future<void> refresh() async {
    state = const AsyncValue.loading();
    state = await AsyncValue.guard(_fetch);
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
      // Refresh conversations list to show outgoing message
      await refresh();
      return true;
    }
    return false;
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
