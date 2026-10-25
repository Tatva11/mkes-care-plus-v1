import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:supabase_flutter/supabase_flutter.dart';

import '../../../core/providers/supabase_provider.dart';
import '../models/whatsapp_message.dart';

final whatsappRepositoryProvider = Provider<WhatsAppRepository>((ref) {
  try {
    return WhatsAppRepository(ref.watch(supabaseProvider));
  } catch (_) {
    return WhatsAppRepository(null);
  }
});

class WhatsAppRepository {
  final SupabaseClient? _supabase;

  WhatsAppRepository([this._supabase]);

  /// Helper to extract 10-digit national number
  String _normalizePhone(String phone) {
    final digits = phone.replaceAll(RegExp(r'[^0-9]'), '');
    return digits.length >= 10 ? digits.substring(digits.length - 10) : digits;
  }

  /// Fetches all conversations grouped by phone number with automatic patient linking.
  Future<List<WhatsAppConversation>> fetchConversations() async {
    if (_supabase == null) return [];
    try {
      // 1. Fetch all active patients to build normalized 10-digit phone lookup map
      final Map<String, Map<String, dynamic>> patientsByCleanPhone = {};
      try {
        final patientsRes = await _supabase
            .from('patients')
            .select('id, name, patient_number, mobile, department, whatsapp_opt_out');
        for (final p in (patientsRes as List)) {
          final pMap = Map<String, dynamic>.from(p as Map);
          final mob = pMap['mobile']?.toString() ?? '';
          final clean = _normalizePhone(mob);
          if (clean.length == 10) {
            // First registered patient with this phone gets linked (safe deterministic binding)
            patientsByCleanPhone.putIfAbsent(clean, () => pMap);
          }
        }
      } catch (_) {}

      // 2. Fetch message logs
      final logRows = await _supabase
          .from('whatsapp_message_logs')
          .select('*, patients(id, name, patient_number, department, whatsapp_opt_out)')
          .order('timestamp', ascending: false)
          .limit(250);

      final Map<String, List<WhatsAppMessage>> groupedMessages = {};
      final Map<String, Map<String, dynamic>?> patientMetadata = {};

      for (final raw in logRows as List) {
        final json = Map<String, dynamic>.from(raw as Map);
        final rawPhone = json['phone_number']?.toString() ?? '';
        final cleanPhone = _normalizePhone(rawPhone);
        if (cleanPhone.isEmpty) continue;

        // Auto-enrich patient information if missing from join
        if (json['patients'] == null && patientsByCleanPhone.containsKey(cleanPhone)) {
          json['patients'] = patientsByCleanPhone[cleanPhone];
          json['patient_id'] = patientsByCleanPhone[cleanPhone]!['id'];
        }

        final msg = WhatsAppMessage.fromJson(json);
        groupedMessages.putIfAbsent(cleanPhone, () => []).add(msg);

        if (!patientMetadata.containsKey(cleanPhone)) {
          if (json['patients'] != null && json['patients'] is Map) {
            patientMetadata[cleanPhone] = Map<String, dynamic>.from(json['patients'] as Map);
          } else if (patientsByCleanPhone.containsKey(cleanPhone)) {
            patientMetadata[cleanPhone] = patientsByCleanPhone[cleanPhone];
          }
        }
      }

      // 3. Fetch only pending/processing outbox messages to merge latest active outbound
      try {
        final outboxRows = await _supabase
            .from('whatsapp_messages_outbox')
            .select('id, recipient_phone, patient_id, department, message_text, status, created_at, patients(id, name, patient_number, department, whatsapp_opt_out)')
            .inFilter('status', ['pending', 'processing'])
            .order('created_at', ascending: false)
            .limit(50);

        for (final raw in outboxRows as List) {
          final json = Map<String, dynamic>.from(raw as Map);
          final rawPhone = json['recipient_phone']?.toString() ?? '';
          final cleanPhone = _normalizePhone(rawPhone);
          if (cleanPhone.isEmpty) continue;

          final matchedPatient = (json['patients'] != null && json['patients'] is Map)
              ? Map<String, dynamic>.from(json['patients'] as Map)
              : patientsByCleanPhone[cleanPhone];

          final msg = WhatsAppMessage(
            id: json['id']?.toString() ?? '',
            outboxId: json['id']?.toString(),
            direction: 'outbound',
            phoneNumber: rawPhone,
            patientId: json['patient_id']?.toString() ?? matchedPatient?['id']?.toString(),
            patientName: matchedPatient?['name']?.toString(),
            messageBody: json['message_text']?.toString() ?? '',
            status: json['status']?.toString() ?? 'pending',
            timestamp: json['created_at'] != null
                ? DateTime.tryParse(json['created_at'].toString()) ?? DateTime.now()
                : DateTime.now(),
            department: json['department']?.toString() ?? matchedPatient?['department']?.toString(),
          );

          if (!groupedMessages.containsKey(cleanPhone)) {
            groupedMessages[cleanPhone] = [msg];
          } else {
            // Check if not already logged or duplicated
            final alreadyLogged = groupedMessages[cleanPhone]!.any((m) =>
                m.id == msg.id ||
                m.outboxId == msg.outboxId ||
                (m.messageBody.trim() == msg.messageBody.trim() &&
                    m.timestamp.difference(msg.timestamp).inSeconds.abs() < 120));
            if (!alreadyLogged) {
              groupedMessages[cleanPhone]!.add(msg);
            }
          }

          if (!patientMetadata.containsKey(cleanPhone) && matchedPatient != null) {
            patientMetadata[cleanPhone] = matchedPatient;
          }
        }
      } catch (_) {}

      final List<WhatsAppConversation> conversations = [];

      for (final entry in groupedMessages.entries) {
        final phone = entry.key;
        final rawMsgs = entry.value;

        // Sort latest first
        rawMsgs.sort((a, b) => b.timestamp.compareTo(a.timestamp));

        // Deduplicate messages within the conversation
        final uniqueMsgs = <WhatsAppMessage>[];
        final seenMessageKeys = <String>{};
        for (final m in rawMsgs) {
          final key = m.id.isNotEmpty
              ? m.id
              : '${m.direction}_${m.messageBody.trim()}_${m.timestamp.millisecondsSinceEpoch ~/ 60000}';
          if (seenMessageKeys.add(key)) {
            uniqueMsgs.add(m);
          }
        }

        final pMeta = patientMetadata[phone] ?? patientsByCleanPhone[phone];
        final unreadCount = uniqueMsgs.where((m) => m.isInbound).length;

        conversations.add(WhatsAppConversation(
          phoneNumber: phone,
          patientId: pMeta?['id']?.toString() ?? (uniqueMsgs.isNotEmpty ? uniqueMsgs.first.patientId : null),
          patientName: pMeta?['name']?.toString() ?? (uniqueMsgs.isNotEmpty ? uniqueMsgs.first.patientName : null),
          patientNumber: pMeta?['patient_number']?.toString(),
          department: pMeta?['department']?.toString() ?? (uniqueMsgs.isNotEmpty ? uniqueMsgs.first.department : null),
          isOptedOut: pMeta?['whatsapp_opt_out'] as bool? ?? false,
          lastMessage: uniqueMsgs.isNotEmpty ? uniqueMsgs.first.messageBody : '',
          lastTimestamp: uniqueMsgs.isNotEmpty ? uniqueMsgs.first.timestamp : DateTime.now(),
          unreadCount: unreadCount,
          messages: uniqueMsgs.reversed.toList(), // Chronological order (oldest to newest)
        ));
      }

      conversations.sort((a, b) => b.lastTimestamp.compareTo(a.lastTimestamp));
      return conversations;
    } catch (e) {
      return [];
    }
  }

  /// Fetches messages for a specific phone number.
  Future<List<WhatsAppMessage>> fetchMessagesForPhone(String phone) async {
    if (_supabase == null) return [];
    try {
      final clean = _normalizePhone(phone);
      final response = await _supabase
          .from('whatsapp_message_logs')
          .select('*, patients(id, name, patient_number)')
          .ilike('phone_number', '%$clean')
          .order('timestamp', ascending: true);

      return (response as List)
          .map((json) => WhatsAppMessage.fromJson(Map<String, dynamic>.from(json as Map)))
          .toList();
    } catch (e) {
      return [];
    }
  }

  /// Fetches all messages associated with a patient.
  Future<List<WhatsAppMessage>> fetchMessagesForPatient(String patientId) async {
    if (_supabase == null) return [];
    try {
      final response = await _supabase
          .from('whatsapp_message_logs')
          .select('*, patients(id, name, patient_number)')
          .eq('patient_id', patientId)
          .order('timestamp', ascending: true);

      return (response as List)
          .map((json) => WhatsAppMessage.fromJson(Map<String, dynamic>.from(json as Map)))
          .toList();
    } catch (e) {
      return [];
    }
  }

  /// Enqueues a message to be sent via the WhatsApp service.
  Future<Map<String, dynamic>> sendMessage({
    required String phone,
    String? patientId,
    required String department,
    required String messageText,
  }) async {
    if (_supabase == null) return {'success': false, 'message': 'Database not connected'};
    try {
      // 1. Attempt server-side RPC if available
      try {
        final rpcRes = await _supabase.rpc('send_staff_whatsapp_message', params: {
          'p_recipient_phone': phone,
          'p_patient_id': patientId,
          'p_department': department,
          'p_message_text': messageText,
        });

        if (rpcRes is Map) {
          return Map<String, dynamic>.from(rpcRes);
        }
      } catch (_) {}

      // 2. Direct transactional insert into outbox
      final response = await _supabase.from('whatsapp_messages_outbox').insert({
        'recipient_phone': phone,
        'patient_id': patientId,
        'department': department.toLowerCase(),
        'message_type': 'staff_reply',
        'template_key': 'staff_reply',
        'message_text': messageText,
        'status': 'pending',
      }).select().single();

      return {
        'success': true,
        'outbox_id': response['id']?.toString(),
      };
    } catch (e) {
      return {'success': false, 'message': e.toString()};
    }
  }

  /// Fetches daemon settings (daily limit, operating hours, is_enabled).
  Future<Map<String, dynamic>?> fetchSettings() async {
    if (_supabase == null) return null;
    try {
      final response = await _supabase
          .from('whatsapp_settings')
          .select('*')
          .eq('id', '00000000-0000-0000-0000-000000000001')
          .maybeSingle();

      if (response == null) return null;
      return Map<String, dynamic>.from(response);
    } catch (e) {
      return null;
    }
  }

  /// Updates daemon settings.
  Future<bool> updateSettings(Map<String, dynamic> updates) async {
    if (_supabase == null) return false;
    try {
      final payload = Map<String, dynamic>.from(updates);
      payload['updated_at'] = DateTime.now().toUtc().toIso8601String();

      await _supabase
          .from('whatsapp_settings')
          .update(payload)
          .eq('id', '00000000-0000-0000-0000-000000000001');

      return true;
    } catch (e) {
      return false;
    }
  }

  /// Fetches operational templates.
  Future<List<Map<String, dynamic>>> fetchTemplates() async {
    if (_supabase == null) return [];
    try {
      final response = await _supabase
          .from('whatsapp_templates')
          .select('*')
          .order('template_key', ascending: true);

      return (response as List)
          .map((item) => Map<String, dynamic>.from(item as Map))
          .toList();
    } catch (e) {
      return [];
    }
  }

  /// Toggles template active status.
  Future<bool> setTemplateActive(String templateKey, bool isActive) async {
    if (_supabase == null) return false;
    try {
      await _supabase
          .from('whatsapp_templates')
          .update({'is_active': isActive, 'updated_at': DateTime.now().toUtc().toIso8601String()})
          .eq('template_key', templateKey);
      return true;
    } catch (e) {
      return false;
    }
  }

  /// Fetches delivery statistics for outbox.
  Future<Map<String, int>> fetchOutboxStats() async {
    if (_supabase == null) {
      return {
        'pending': 0,
        'processing': 0,
        'sent': 0,
        'failed': 0,
        'cancelled': 0,
      };
    }
    try {
      final rows = await _supabase
          .from('whatsapp_messages_outbox')
          .select('status');

      final stats = <String, int>{
        'pending': 0,
        'processing': 0,
        'sent': 0,
        'failed': 0,
        'cancelled': 0,
      };

      for (final r in (rows as List)) {
        final status = (r as Map)['status']?.toString() ?? 'pending';
        stats[status] = (stats[status] ?? 0) + 1;
      }

      return stats;
    } catch (e) {
      return {
        'pending': 0,
        'processing': 0,
        'sent': 0,
        'failed': 0,
        'cancelled': 0,
      };
    }
  }

  /// Updates patient opt-out status via RPC.
  Future<bool> setPatientOptOut(String patientId, bool optOut) async {
    if (_supabase == null) return false;
    try {
      final res = await _supabase.rpc('set_patient_whatsapp_opt_out', params: {
        'p_patient_id': patientId,
        'p_opt_out': optOut,
      });

      if (res is Map && res['success'] == true) return true;

      // Fallback direct update
      await _supabase
          .from('patients')
          .update({'whatsapp_opt_out': optOut, 'updated_at': DateTime.now().toUtc().toIso8601String()})
          .eq('id', patientId);

      return true;
    } catch (e) {
      return false;
    }
  }

  /// Links an unmatched phone number to an existing patient record.
  Future<bool> linkPhoneToPatient({
    required String phone,
    required String patientId,
  }) async {
    if (_supabase == null) return false;
    try {
      final clean = _normalizePhone(phone);
      // Update patient mobile
      await _supabase
          .from('patients')
          .update({'mobile': clean, 'updated_at': DateTime.now().toUtc().toIso8601String()})
          .eq('id', patientId);

      // Backfill existing message logs with this patient_id
      await _supabase
          .from('whatsapp_message_logs')
          .update({'patient_id': patientId})
          .ilike('phone_number', '%$clean');

      return true;
    } catch (e) {
      return false;
    }
  }
}
