import 'package:intl/intl.dart';
import 'package:supabase_flutter/supabase_flutter.dart';

import '../models/eye_surgery_model.dart';
import '../models/eye_surgery_item_model.dart';

class EyeSurgeryRepository {
  EyeSurgeryRepository({SupabaseClient? client})
      : _client = client ?? Supabase.instance.client;

  final SupabaseClient _client;

  // Removed appointments join — Eye Surgery is independent of appointments.
  static const _select =
      '*, patients!eye_surgeries_patient_id_fkey(id, name, patient_number), '
      'assigned_staff:profiles!eye_surgeries_assigned_staff_id_fkey(id, full_name)';
  static const _itemSelect =
      '*, inventory!eye_surgery_items_inventory_item_id_fkey(name, quantity, unit)';
  static const _templateSelect =
      '*, inventory!eye_surgery_item_templates_inventory_item_id_fkey(name, quantity, unit)';

  Future<List<EyeSurgeryModel>> fetchSurgeries({String? status}) async {
    if (status != null &&
        status != 'all' &&
        !EyeSurgeryModel.isValidStatus(status)) {
      throw ArgumentError.value(status, 'status', 'Invalid surgery status.');
    }

    var query = _client.from('eye_surgeries').select(_select);
    if (status != null && status != 'all') {
      query = query.eq('status', status);
    }
    final response = await query
        .order('surgery_date', ascending: true)
        .order('surgery_time', ascending: true);
    return (response as List<dynamic>)
        .map((row) => EyeSurgeryModel.fromJson(_stringMap(row)))
        .toList();
  }

  Future<List<EyeSurgeryModel>> fetchSurgeriesForPatient(
    String patientId,
  ) async {
    final response = await _client
        .from('eye_surgeries')
        .select(_select)
        .eq('patient_id', patientId)
        .order('surgery_date', ascending: false);
    return (response as List<dynamic>)
        .map((row) => EyeSurgeryModel.fromJson(_stringMap(row)))
        .toList();
  }

  Future<EyeSurgeryModel?> fetchSurgeryById(String id) async {
    final response = await _client
        .from('eye_surgeries')
        .select(_select)
        .eq('id', id)
        .maybeSingle();
    if (response == null) return null;
    return EyeSurgeryModel.fromJson(_stringMap(response));
  }

  Future<List<EyeSurgeryStaffCandidate>> fetchStaffCandidates() async {
    try {
      final response = await _client
          .from('profiles')
          .select('id, full_name, role, is_active, department_id, department:departments(name)')
          .eq('is_active', true)
          .eq('role', 'staff')
          .order('full_name');
      final rows = response as List<dynamic>;
      final allStaff = rows.map((r) {
        final map = _stringMap(r);
        final deptMap = map['department'];
        String? deptName;
        if (deptMap is Map && deptMap['name'] is String) {
          deptName = deptMap['name'] as String;
        }
        return EyeSurgeryStaffCandidate(
          id: (map['id'] as String?)?.trim().toLowerCase() ?? '',
          fullName: (map['full_name'] as String?)?.trim() ?? 'Staff',
          department: deptName,
          role: (map['role'] as String?) ?? 'staff',
          isActive: (map['is_active'] as bool?) ?? true,
        );
      }).where((s) => s.id.isNotEmpty && s.role.toLowerCase() == 'staff' && s.isActive).toList();

      final eyeStaff = allStaff.where((s) {
        final d = (s.department ?? '').toLowerCase();
        return d.contains('eye') || d.contains('ophthal');
      }).toList();

      if (eyeStaff.isNotEmpty) {
        return eyeStaff;
      }
      return allStaff;
    } catch (_) {
      return const [];
    }
  }

  Future<EyeSurgeryModel> createSurgery({
    required String patientId,
    required String surgeryType,
    required String surgeryTypeCategory,
    String? customSurgeryType,
    required String eyeSide,
    required DateTime? surgeryDate,
    String? assignedStaffId,
    String? surgeryTime,
    Map<String, bool> preOpChecklist = const {},
    String? iolDetails,
    String? remarks,
    List<({String inventoryItemId, double plannedQuantity, String source})>? initialItems,
  }) async {
    final validationError = EyeSurgeryModel.validateFields(
      patientId: patientId,
      surgeryType: surgeryType,
      surgeryTypeCategory: surgeryTypeCategory,
      customSurgeryType: customSurgeryType,
      eyeSide: eyeSide,
      preOpDate: surgeryDate,
      surgeryDate: surgeryDate,
      surgeryTime: surgeryTime,
      status: 'scheduled',
    );
    if (validationError != null) throw ArgumentError(validationError);
    _validateChecklist(preOpChecklist);
    await _ensureEyePatient(patientId);
    final scheduledDate =
        surgeryDate ?? (throw ArgumentError('Surgery date is required.'));

    final response = await _client
        .from('eye_surgeries')
        .insert({
          'patient_id': patientId.trim(),
          'surgery_type': surgeryType.trim(),
          'surgery_type_category': surgeryTypeCategory,
          'custom_surgery_type': _nullableTrim(customSurgeryType),
          'eye_side': eyeSide,
          'assigned_staff_id': _nullableTrim(assignedStaffId),
          'pre_op_date': _dateOnly(scheduledDate),
          'surgery_date': _dateOnly(scheduledDate),
          'surgery_time': _nullableTrim(surgeryTime),
          'status': 'scheduled',
          'pre_op_checklist': preOpChecklist,
          'iol_details': _nullableTrim(iolDetails),
          'remarks': _nullableTrim(remarks),
        })
        .select(_select)
        .single();
    final createdSurgery = EyeSurgeryModel.fromJson(_stringMap(response));
    if (initialItems != null && initialItems.isNotEmpty) {
      for (final item in initialItems) {
        if (item.plannedQuantity > 0) {
          try {
            await _client.from('eye_surgery_items').insert({
              'eye_surgery_id': createdSurgery.id,
              'inventory_item_id': item.inventoryItemId,
              'planned_quantity': item.plannedQuantity,
              'actual_quantity': item.plannedQuantity,
              'source': item.source,
            });
          } catch (_) {}
        }
      }

      // Deduct Central Inventory immediately upon Eye Surgery scheduling
      // with atomic rollback on insufficient stock
      try {
        await _client.rpc(
          'schedule_surgery_with_inventory',
          params: {'p_surgery_id': createdSurgery.id},
        );
      } catch (e) {
        // Atomic rollback: delete created surgery and items if inventory deduction fails
        try {
          await _client
              .from('eye_surgery_items')
              .delete()
              .eq('eye_surgery_id', createdSurgery.id);
          await _client
              .from('eye_surgeries')
              .delete()
              .eq('id', createdSurgery.id);
        } catch (_) {}
        throw StateError(
          'Cannot schedule surgery: $e',
        );
      }
    }
    _enqueueSurgeryBookingWhatsApp(createdSurgery);
    return createdSurgery;
  }

  Future<EyeSurgeryModel> updateSurgery(EyeSurgeryModel surgery) async {
    final validationError = EyeSurgeryModel.validateFields(
      patientId: surgery.patientId,
      surgeryType: surgery.surgeryType,
      surgeryTypeCategory: surgery.surgeryTypeCategory,
      customSurgeryType: surgery.customSurgeryType,
      eyeSide: surgery.eyeSide,
      preOpDate: surgery.preOpDate,
      surgeryDate: surgery.surgeryDate,
      surgeryTime: surgery.surgeryTime,
      status: surgery.status,
    );
    if (validationError != null) throw ArgumentError(validationError);
    _validateChecklist(surgery.preOpChecklist);
    await _ensureEyePatient(surgery.patientId);

    final payload = surgery.toJson()
      ..remove('id')
      ..remove('created_at')
      ..remove('updated_at');
    final response = await _client
        .from('eye_surgeries')
        .update(payload)
        .eq('id', surgery.id)
        .select(_select)
        .single();
    final updated = EyeSurgeryModel.fromJson(_stringMap(response));
    if (updated.status == 'discharged') {
      _enqueueSurgeryPostOpWhatsApp(updated);
    }
    return updated;
  }

  Future<void> deleteSurgery(String id) async {
    // Restore allocated central inventory before deleting surgery
    try {
      await _client.rpc(
        'restore_surgery_inventory',
        params: {'p_surgery_id': id},
      );
    } catch (_) {}

    final deleted = await _client
        .from('eye_surgeries')
        .delete()
        .eq('id', id)
        .select('id');
    if ((deleted as List<dynamic>).isEmpty) {
      throw StateError('Eye surgery could not be deleted or permission denied.');
    }
  }

  Future<EyeSurgeryModel> updateStatus(String id, String newStatus) async {
    if (!EyeSurgeryModel.isValidStatus(newStatus)) {
      throw ArgumentError.value(
          newStatus, 'newStatus', 'Invalid surgery status.');
    }
    final existing = await fetchSurgeryById(id);
    if (existing == null) throw StateError('Eye surgery not found.');
    final transitionError = EyeSurgeryModel.validateStatusTransition(
      surgery: existing,
      nextStatus: newStatus,
    );
    if (transitionError != null) {
      throw StateError(transitionError);
    }
    if (newStatus == 'in_surgery') {
      throw StateError('Use startSurgery to atomically consume inventory.');
    }

    // Restore central inventory if surgery was cancelled
    if (newStatus == 'cancelled') {
      try {
        await _client.rpc(
          'restore_surgery_inventory',
          params: {'p_surgery_id': id},
        );
      } catch (_) {}
    }

    final payload = <String, dynamic>{'status': newStatus};
    if (newStatus == 'discharged') {
      payload['discharged_at'] = DateTime.now().toIso8601String();
    }
    final updated = await _update(id, payload);
    if (newStatus == 'discharged') {
      _enqueueSurgeryPostOpWhatsApp(updated);
    }
    return updated;
  }

  void _enqueueSurgeryBookingWhatsApp(EyeSurgeryModel surgery) async {
    try {
      final pRes = await _client
          .from('patients')
          .select('name, mobile, whatsapp_opt_out')
          .eq('id', surgery.patientId)
          .maybeSingle();

      if (pRes == null) return;
      if (pRes['whatsapp_opt_out'] == true) return;

      final rawMobile = pRes['mobile']?.toString() ?? '';
      final digits = rawMobile.replaceAll(RegExp(r'[^0-9]'), '');
      if (digits.length < 10) return;
      final clean10 = digits.substring(digits.length - 10);

      // Duplicate prevention
      final existing = await _client
          .from('whatsapp_messages_outbox')
          .select('id')
          .or('template_key.eq.eye_surgery_${surgery.id},message_text.ilike.%scheduled with ${surgery.assignedStaffName ?? "Clinical Surgical Team"}%')
          .maybeSingle();

      if (existing != null) return;

      final patientName = pRes['name']?.toString() ?? surgery.patientName ?? 'Valued Patient';
      final formattedDate = DateFormat('d MMMM yyyy').format(surgery.surgeryDate);
      final surgeryTimeStr = (surgery.surgeryTime != null && surgery.surgeryTime!.trim().isNotEmpty)
          ? surgery.surgeryTime!
          : 'Morning Session';
      final surgeon = surgery.assignedStaffName ?? 'Clinical Surgical Team';

      final messageText = '🏥 *MKES Eye Surgery Booking Confirmation*\n\n'
          'Dear $patientName,\n'
          'Your ${surgery.surgeryTypeCategory} (${surgery.eyeSide.toUpperCase()} eye) has been scheduled with $surgeon.\n\n'
          '📅 *Date:* $formattedDate\n'
          '⏰ *Scheduled Time:* $surgeryTimeStr\n'
          '👨‍⚕️ *Attending Surgeon / Team:* $surgeon\n\n'
          '📋 *Pre-Operative Preparation Instructions:*\n'
          '1. Fasting (NPO): Do not eat or drink anything for 6 hours prior to your scheduled time (light water permitted up to 2 hours prior unless instructed otherwise).\n'
          '2. Medications: Take regular blood pressure medicines with a sip of water. Stop blood thinners only if explicitly directed by your surgeon.\n'
          '3. Hygiene: Wash hair and face before arriving. Do not apply eye makeup, face creams, lotions, or perfume.\n'
          '4. Escort: Please arrange for an accompanying adult to escort you home after the procedure.\n'
          '5. Items to Bring: Bring all current eye drops and existing medical records.\n\n'
          'Reply STOP to unsubscribe.';

      try {
        await _client.from('whatsapp_messages_outbox').insert({
          'recipient_phone': clean10,
          'patient_id': surgery.patientId,
          'department': 'eye',
          'message_type': 'eye_surgery',
          'template_key': 'eye_surgery_${surgery.id}',
          'message_text': messageText,
          'status': 'pending',
        });
      } catch (_) {
        // Fallback to SECURITY DEFINER stored procedure for staff/RLS
        await _client.rpc('send_staff_whatsapp_message', params: {
          'p_recipient_phone': clean10,
          'p_patient_id': surgery.patientId,
          'p_department': 'eye',
          'p_message_text': messageText,
        });
      }
    } catch (_) {}
  }

  void _enqueueSurgeryPostOpWhatsApp(EyeSurgeryModel surgery) async {
    try {
      final pRes = await _client
          .from('patients')
          .select('name, mobile, whatsapp_opt_out')
          .eq('id', surgery.patientId)
          .maybeSingle();

      if (pRes == null) return;
      if (pRes['whatsapp_opt_out'] == true) return;

      final rawMobile = pRes['mobile']?.toString() ?? '';
      final digits = rawMobile.replaceAll(RegExp(r'[^0-9]'), '');
      if (digits.length < 10) return;
      final clean10 = digits.substring(digits.length - 10);

      // Duplicate prevention
      final existing = await _client
          .from('whatsapp_messages_outbox')
          .select('id')
          .or('template_key.eq.eye_postop_${surgery.id},message_text.ilike.%MKES Eye Surgery Post-Operative Instructions%')
          .maybeSingle();

      if (existing != null) return;

      final patientName = pRes['name']?.toString() ?? surgery.patientName ?? 'Valued Patient';

      final messageText = '👁️ *MKES Eye Surgery Post-Operative Instructions*\n\n'
          'Dear $patientName,\n'
          'Congratulations on completing your surgery. Please adhere strictly to the following post-operative care instructions:\n\n'
          '1. Eye Protection: Wear your protective eye shield while sleeping as instructed.\n'
          '2. Eye Drops: Instill your prescribed post-operative eye drops at the directed intervals. Wash your hands thoroughly before instilling drops.\n'
          '3. Cleanliness: Do not splash water into the operated eye, rub the eye, or engage in strenuous activities.\n'
          '4. Warning Signs: If you experience sudden vision deterioration, severe pain, or severe redness, contact our clinic immediately.\n\n'
          'Reply STOP to unsubscribe.';

      try {
        await _client.from('whatsapp_messages_outbox').insert({
          'recipient_phone': clean10,
          'patient_id': surgery.patientId,
          'department': 'eye',
          'message_type': 'eye_postop',
          'template_key': 'eye_postop_${surgery.id}',
          'message_text': messageText,
          'status': 'pending',
        });
      } catch (_) {
        // Fallback to SECURITY DEFINER stored procedure for staff/RLS
        await _client.rpc('send_staff_whatsapp_message', params: {
          'p_recipient_phone': clean10,
          'p_patient_id': surgery.patientId,
          'p_department': 'eye',
          'p_message_text': messageText,
        });
      }
    } catch (_) {}
  }

  Future<EyeSurgeryModel> startSurgery(String id) async {
    final existing = await fetchSurgeryById(id);
    if (existing == null) throw StateError('Eye surgery not found.');
    if (existing.status == 'in_surgery') {
      return existing;
    }
    if (existing.status != 'pre_op') {
      throw StateError('Surgery must be in Pre-op before entering surgery.');
    }
    if (!existing.isPreOpChecklistComplete) {
      throw StateError(
        'Complete the pre-op checklist before entering surgery.',
      );
    }
    try {
      await _client.rpc(
        'consume_eye_surgery_inventory',
        params: {'p_eye_surgery_id': id},
      );
    } catch (error) {
      if (error.toString().toLowerCase().contains('insufficient stock')) {
        try {
          await _client.rpc(
            'notify_eye_surgery_insufficient_stock',
            params: {
              'p_eye_surgery_id': id,
              'p_detail': error.toString(),
            },
          );
        } catch (_) {}
      }
      rethrow;
    }
    final updated = await fetchSurgeryById(id);
    if (updated == null) throw StateError('Eye Surgery not found.');
    return updated;
  }

  Future<EyeSurgeryModel> updatePreOpChecklist(
    String id,
    Map<String, bool> checklist,
  ) async {
    _validateChecklist(checklist);
    return _update(id, {'pre_op_checklist': checklist});
  }

  Future<EyeSurgeryModel> updateSurgeryDetails({
    required String id,
    String? iolDetails,
    String? remarks,
  }) {
    return _update(id, {
      'iol_details': _nullableTrim(iolDetails),
      'remarks': _nullableTrim(remarks),
    });
  }

  Future<EyeSurgeryModel> assignStaff(String id, String? assignedStaffId) {
    return _update(id, {'assigned_staff_id': _nullableTrim(assignedStaffId)});
  }

  Future<EyeSurgeryModel> linkFollowUpAppointment(
    String id,
    String appointmentId,
  ) {
    return _update(id, {'follow_up_appointment_id': appointmentId});
  }

  Future<EyeSurgeryModel> rescheduleSurgery({
    required String id,
    required DateTime surgeryDate,
    String? surgeryTime,
  }) {
    final sanitizedTime = _nullableTrim(surgeryTime);
    if (sanitizedTime == null) {
      throw ArgumentError('Surgery time is required.');
    }
    final parsed = EyeSurgeryModel.parseTimeString(sanitizedTime);
    final isFuture = parsed != null &&
        DateTime(
          surgeryDate.year,
          surgeryDate.month,
          surgeryDate.day,
          parsed.hour,
          parsed.minute,
        ).isAfter(DateTime.now());

    final payload = <String, dynamic>{
      'surgery_date': _dateOnly(surgeryDate),
      'pre_op_date': _dateOnly(surgeryDate),
      'surgery_time': sanitizedTime,
    };
    if (isFuture) {
      payload['status'] = 'scheduled';
    }
    return _update(id, payload);
  }

  Future<List<EyeSurgeryItemModel>> fetchSurgeryItems(String surgeryId) async {
    final response = await _client
        .from('eye_surgery_items')
        .select(_itemSelect)
        .eq('eye_surgery_id', surgeryId)
        .order('created_at');
    return (response as List<dynamic>)
        .map((row) => EyeSurgeryItemModel.fromJson(_stringMap(row)))
        .toList();
  }

  Future<List<EyeSurgeryItemTemplateModel>> fetchItemTemplates(
    String surgeryType,
  ) async {
    final response = await _client
        .from('eye_surgery_item_templates')
        .select(_templateSelect)
        .eq('surgery_type', surgeryType)
        .eq('is_active', true)
        .order('created_at');
    return (response as List<dynamic>)
        .map((row) => EyeSurgeryItemTemplateModel.fromJson(_stringMap(row)))
        .toList();
  }

  Future<List<EyeSurgeryItemTemplateModel>> fetchAllItemTemplates() async {
    final response = await _client
        .from('eye_surgery_item_templates')
        .select(_templateSelect)
        .order('surgery_type')
        .order('created_at');
    return (response as List<dynamic>)
        .map((row) => EyeSurgeryItemTemplateModel.fromJson(_stringMap(row)))
        .toList();
  }

  Future<EyeSurgeryItemTemplateModel> saveItemTemplate({
    required String surgeryType,
    required String inventoryItemId,
    required double defaultQuantity,
  }) async {
    if (!EyeSurgeryModel.surgeryTypeOptions.contains(surgeryType) ||
        defaultQuantity <= 0) {
      throw ArgumentError('Select a surgery type and positive quantity.');
    }
    final response = await _client
        .from('eye_surgery_item_templates')
        .upsert({
          'surgery_type': surgeryType,
          'inventory_item_id': inventoryItemId,
          'default_quantity': defaultQuantity,
          'is_active': true,
        }, onConflict: 'surgery_type,inventory_item_id')
        .select(_templateSelect)
        .single();
    return EyeSurgeryItemTemplateModel.fromJson(_stringMap(response));
  }

  Future<void> deleteItemTemplate(String templateId) async {
    await _client
        .from('eye_surgery_item_templates')
        .delete()
        .eq('id', templateId);
  }

  Future<EyeSurgeryItemModel> addSurgeryItem({
    required String surgeryId,
    required String inventoryItemId,
    required double plannedQuantity,
    double? actualQuantity,
    String source = 'manual',
  }) async {
    if (plannedQuantity <= 0 || (actualQuantity ?? plannedQuantity) <= 0) {
      throw ArgumentError('Item quantities must be greater than zero.');
    }
    final response = await _client
        .from('eye_surgery_items')
        .insert({
          'eye_surgery_id': surgeryId,
          'inventory_item_id': inventoryItemId,
          'planned_quantity': plannedQuantity,
          'actual_quantity': actualQuantity ?? plannedQuantity,
          'source': source,
        })
        .select(_itemSelect)
        .single();
    final item = EyeSurgeryItemModel.fromJson(_stringMap(response));
    // Immediately allocate if surgery is active/scheduled
    try {
      await _client.rpc(
        'schedule_surgery_with_inventory',
        params: {'p_surgery_id': surgeryId},
      );
    } catch (_) {}
    return item;
  }

  Future<EyeSurgeryItemModel> updateSurgeryItem({
    required String itemId,
    required double plannedQuantity,
    required double actualQuantity,
  }) async {
    if (plannedQuantity <= 0 || actualQuantity <= 0) {
      throw ArgumentError('Item quantities must be greater than zero.');
    }
    // Attempt atomic server reconciliation if item was already allocated
    try {
      await _client.rpc(
        'reconcile_surgery_item_inventory',
        params: {
          'p_surgery_item_id': itemId,
          'p_new_quantity': plannedQuantity,
        },
      );
    } catch (_) {}

    final response = await _client
        .from('eye_surgery_items')
        .update({
          'planned_quantity': plannedQuantity,
          'actual_quantity': actualQuantity,
        })
        .eq('id', itemId)
        .select(_itemSelect)
        .single();
    return EyeSurgeryItemModel.fromJson(_stringMap(response));
  }

  Future<void> removeSurgeryItem(String itemId) async {
    // Check if item was allocated and restore inventory before deletion
    try {
      final existing = await _client
          .from('eye_surgery_items')
          .select('inventory_item_id, planned_quantity, allocation_status, eye_surgery_id')
          .eq('id', itemId)
          .maybeSingle();
      if (existing != null && existing['allocation_status'] == 'allocated') {
        final qty = (existing['planned_quantity'] as num).toDouble();
        final invId = existing['inventory_item_id'] as String;
        final inv = await _client.from('inventory').select('quantity').eq('id', invId).maybeSingle();
        if (inv != null) {
          final cur = (inv['quantity'] as num).toDouble();
          await _client.from('inventory').update({'quantity': cur + qty}).eq('id', invId);
          await _client.from('inventory_transactions').insert({
            'inventory_id': invId,
            'transaction_type': 'surgery_return',
            'quantity': qty,
            'reference_id': existing['eye_surgery_id'],
            'remarks': 'Item removed from surgery',
          });
        }
      }
    } catch (_) {}
    await _client.from('eye_surgery_items').delete().eq('id', itemId);
  }

  Future<EyeSurgeryModel> _update(
      String id, Map<String, dynamic> payload) async {
    final response = await _client
        .from('eye_surgeries')
        .update(payload)
        .eq('id', id)
        .select(_select)
        .single();
    return EyeSurgeryModel.fromJson(_stringMap(response));
  }

  Future<void> _ensureEyePatient(String patientId) async {
    final response = await _client
        .from('patients')
        .select('id, department')
        .eq('id', patientId.trim())
        .maybeSingle();
    if (response == null ||
        (response['department'] as String?)?.toLowerCase() != 'eye') {
      throw ArgumentError('Select a patient registered in the Eye department.');
    }
  }

  static void _validateChecklist(Map<String, bool> checklist) {
    final unknown = checklist.keys
        .where((key) => !EyeSurgeryModel.checklistItems.containsKey(key));
    if (unknown.isNotEmpty) {
      throw ArgumentError.value(
          unknown.first, 'checklist', 'Unknown checklist item.');
    }
  }

  static String? normalizeSurgeryTime(String? value) => _nullableTrim(value);

  static String? _nullableTrim(String? value) {
    final trimmed = value?.trim();
    return trimmed == null || trimmed.isEmpty ? null : trimmed;
  }

  static String _dateOnly(DateTime date) =>
      '${date.year.toString().padLeft(4, '0')}-'
      '${date.month.toString().padLeft(2, '0')}-'
      '${date.day.toString().padLeft(2, '0')}';

  static Map<String, dynamic> _stringMap(Object? value) {
    if (value is! Map) return const {};
    return {
      for (final entry in value.entries)
        if (entry.key is String) entry.key as String: entry.value,
    };
  }
}
