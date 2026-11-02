import 'package:flutter/foundation.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:intl/intl.dart';
import 'package:supabase_flutter/supabase_flutter.dart';

import '../../../core/providers/supabase_provider.dart';
import '../models/appointment_model.dart';

class AppointmentConflictException implements Exception {
  final String message;
  AppointmentConflictException(this.message);

  @override
  String toString() => message;
}

final appointmentRepositoryProvider = Provider<AppointmentRepository>((ref) {
  return AppointmentRepository(ref.watch(supabaseProvider));
});

class AppointmentRepository {
  final SupabaseClient _supabase;

  AppointmentRepository(this._supabase);

  /// Fetch list of appointments with optional filtering for date, doctor, department, and status.
  Future<List<AppointmentModel>> fetchAppointments({
    DateTime? date,
    String? doctorId,
    String? department,
    String? status,
  }) async {
    var query = _supabase.from('appointments').select(
          '*, patients!appointments_patient_id_fkey(*), profiles!appointments_doctor_id_fkey(*)',
        );

    if (date != null) {
      final dateStr = date.toIso8601String().split('T').first;
      query = query.eq('appointment_date', dateStr);
    }

    if (doctorId != null && doctorId.isNotEmpty) {
      query = query.eq('doctor_id', doctorId);
    }

    if (department != null && department.isNotEmpty) {
      query = query.eq('department', department.toLowerCase());
    }

    if (status != null && status.isNotEmpty) {
      query = query.eq('status', status.toLowerCase());
    }

    final response = await query
        .order('appointment_date', ascending: true)
        .order('appointment_time', ascending: true);

    return (response as List)
        .map((json) => AppointmentModel.fromJson(json as Map<String, dynamic>))
        .toList();
  }

  Future<List<AppointmentModel>> fetchPatientAppointments({
    required String patientId,
    required String department,
  }) async {
    final response = await _supabase
        .from('appointments')
        .select(
          '*, patients!appointments_patient_id_fkey(*), profiles!appointments_doctor_id_fkey(*)',
        )
        .eq('patient_id', patientId)
        .eq('department', department.toLowerCase())
        .order('appointment_date', ascending: true)
        .order('appointment_time', ascending: true);

    return (response as List)
        .map((json) => AppointmentModel.fromJson(json as Map<String, dynamic>))
        .toList();
  }

  Future<List<AppointmentStaffCandidate>> fetchDepartmentStaffCandidates(
    String departmentId,
  ) async {
    final response = await _supabase.rpc(
      'get_active_department_staff_candidates',
      params: {'p_department_id': departmentId},
    );

    return (response as List)
        .map(
          (row) => AppointmentStaffCandidate.fromJson(
            Map<String, dynamic>.from(row as Map),
          ),
        )
        .toList();
  }

  /// Convenience method to fetch today's appointments.
  Future<List<AppointmentModel>> fetchTodayAppointments({
    String? doctorId,
    String? department,
  }) async {
    return fetchAppointments(
      date: DateTime.now(),
      doctorId: doctorId,
      department: department,
    );
  }

  /// Fetch a single appointment by ID.
  Future<AppointmentModel?> fetchAppointmentById(String id) async {
    final response = await _supabase
        .from('appointments')
        .select(
          '*, patients!appointments_patient_id_fkey(*), profiles!appointments_doctor_id_fkey(*)',
        )
        .eq('id', id)
        .maybeSingle();

    if (response == null) return null;
    return AppointmentModel.fromJson(response);
  }

  /// Normalizes a time string (e.g. "09:30:00", "9:30", "09:30") to "HH:mm".
  static String normalizeTimePrefix(String time) {
    final clean = time.trim();
    if (clean.isEmpty) return '';
    final parts = clean.split(':');
    if (parts.length < 2) return clean;
    final h = parts[0].padLeft(2, '0');
    final m = parts[1].padLeft(2, '0');
    return '$h:$m';
  }

  /// Checks for conflicting appointments on the same date and time.
  /// Returns a human-readable conflict description if a conflict exists, or null if clear.
  Future<String?> checkAppointmentConflict({
    required DateTime date,
    required String time,
    required String department,
    String? patientId,
    String? doctorId,
    String? doctorName,
    String? excludeAppointmentId,
  }) async {
    final normTime = normalizeTimePrefix(time);
    final dateStr = date.toIso8601String().split('T').first;

    try {
      final response = await _supabase
          .from('appointments')
          .select('id, patient_id, department, doctor_id, doctor_name, appointment_time, status, notes')
          .eq('appointment_date', dateStr)
          .neq('status', 'cancelled');

      final list = (response as List).cast<Map<String, dynamic>>();

      for (final row in list) {
        final id = row['id']?.toString() ?? '';
        if (excludeAppointmentId != null && id == excludeAppointmentId) {
          continue;
        }

        final rowTime = normalizeTimePrefix(row['appointment_time']?.toString() ?? '');
        if (rowTime != normTime) {
          continue;
        }

        // 1. Patient Conflict: Same patient cannot have 2 appointments at the same time
        final rowPatientId = row['patient_id']?.toString();
        if (patientId != null && patientId.isNotEmpty && rowPatientId == patientId) {
          return 'This patient already has an active appointment scheduled on $dateStr at ${row['appointment_time'] ?? normTime}.';
        }

        // 2. Department Conflict: Same department cannot have 2 appointments at the same time
        final rowDept = (row['department']?.toString() ?? '').toLowerCase().trim();
        if (rowDept == department.toLowerCase().trim()) {
          final deptLabel = department.toUpperCase();
          return 'The $deptLabel clinic already has an appointment scheduled at ${row['appointment_time'] ?? normTime} on $dateStr. Please select another time slot.';
        }

        // 3. Doctor Conflict: Same doctor cannot have 2 appointments at the same time
        final rowDocId = row['doctor_id']?.toString();
        final rowDocName = row['doctor_name']?.toString() ??
            AppointmentModel.extractDoctorNameFromNotes(row['notes']?.toString());

        final isSameDocId = doctorId != null && doctorId.isNotEmpty && rowDocId == doctorId;
        final isSameDocName = doctorName != null &&
            doctorName.trim().isNotEmpty &&
            rowDocName != null &&
            rowDocName.trim().toLowerCase() == doctorName.trim().toLowerCase();

        if (isSameDocId || isSameDocName) {
          final docLabel = doctorName ?? rowDocName ?? 'The selected doctor';
          return '$docLabel already has an appointment scheduled at ${row['appointment_time'] ?? normTime} on $dateStr. Please select another time slot or doctor.';
        }
      }
    } catch (e) {
      debugPrint('AppointmentRepository.checkAppointmentConflict error: $e');
    }

    return null;
  }

  /// Create a new appointment and automatically enqueue WhatsApp confirmation.
  Future<AppointmentModel> createAppointment(
      AppointmentModel appointment) async {
    final conflict = await checkAppointmentConflict(
      date: appointment.appointmentDate,
      time: appointment.appointmentTime,
      department: appointment.department,
      patientId: appointment.patientId,
      doctorId: appointment.doctorId,
      doctorName: appointment.doctorName,
    );
    if (conflict != null) {
      throw AppointmentConflictException(conflict);
    }
    final response = await _supabase
        .from('appointments')
        .insert(appointment.toInsertJson())
        .select(
          '*, patients!appointments_patient_id_fkey(*), profiles!appointments_doctor_id_fkey(*)',
        )
        .single();

    final created = AppointmentModel.fromJson(response);

    // Auto-send WhatsApp confirmation & schedule reminders on successful booking (Requirement 1)
    _scheduleAppointmentNotifications(created, response['patients'] as Map<String, dynamic>?);

    return created;
  }

  void _scheduleAppointmentNotifications(
    AppointmentModel appt,
    Map<String, dynamic>? patientMap,
  ) async {
    try {
      if (appt.status.toLowerCase() == 'cancelled') return;
      if (appt.patientId == null || appt.patientId!.trim().isEmpty) return;

      final dept = appt.department.trim().toLowerCase();
      // Strict departmental boundary: Optical is strictly excluded
      if (dept != 'eye' && dept != 'dental') return;

      Map<String, dynamic>? pData = patientMap;
      if (pData == null || pData['mobile'] == null) {
        final pRes = await _supabase
            .from('patients')
            .select('name, mobile, whatsapp_opt_out')
            .eq('id', appt.patientId!)
            .maybeSingle();
        if (pRes != null) pData = Map<String, dynamic>.from(pRes);
      }

      if (pData == null) return;
      if (pData['whatsapp_opt_out'] == true) return;

      final rawMobile = pData['mobile']?.toString() ?? '';
      final digits = rawMobile.replaceAll(RegExp(r'[^0-9]'), '');
      if (digits.length < 10) return;
      final clean10 = digits.substring(digits.length - 10);

      final patientName = pData['name']?.toString() ?? appt.patientName ?? 'Valued Patient';
      final formattedDate = DateFormat('d MMMM yyyy').format(appt.appointmentDate);
      final docStr = (appt.doctorName != null && appt.doctorName!.trim().isNotEmpty)
          ? ' with ${appt.doctorName}'
          : '';

      // Calculate appointment DateTime in UTC from IST date and wall clock time
      final timeParts = appt.appointmentTime.split(':');
      final hour = int.tryParse(timeParts[0]) ?? 9;
      final minute = timeParts.length > 1 ? (int.tryParse(timeParts[1]) ?? 0) : 0;
      // IST is UTC+5:30. So UTC time = IST time - 5 hours 30 minutes.
      final apptDateTimeUtc = DateTime.utc(
        appt.appointmentDate.year,
        appt.appointmentDate.month,
        appt.appointmentDate.day,
        hour,
        minute,
      ).subtract(const Duration(hours: 5, minutes: 30));

      final nowUtc = DateTime.now().toUtc();

      // 1. Immediate Appointment Confirmation
      await _enqueueOutboxReminder(
        phone: clean10,
        patientId: appt.patientId!,
        appointmentId: appt.id,
        department: dept,
        messageType: 'confirmation',
        templateKey: 'appointment_confirmation_${appt.id}',
        messageText: '✅ *MKES CARE+ Appointment Confirmed!*\n\n'
            'Dear $patientName,\n'
            'Your ${dept.toUpperCase()} appointment is confirmed for *$formattedDate* at *${appt.formattedTime}*$docStr.\n\n'
            'Please arrive 10 minutes prior to your scheduled time.\n'
            'Reply STOP to unsubscribe.',
        scheduledFor: nowUtc,
      );

      // 2. 24-Hour Prior Reminder (if appointment is >= 24h away)
      final reminder24hUtc = apptDateTimeUtc.subtract(const Duration(hours: 24));
      if (reminder24hUtc.isAfter(nowUtc)) {
        await _enqueueOutboxReminder(
          phone: clean10,
          patientId: appt.patientId!,
          appointmentId: appt.id,
          department: dept,
          messageType: 'reminder_24h',
          templateKey: 'reminder_24h_${appt.id}',
          messageText: 'Hello $patientName, this is a reminder of your ${dept.toUpperCase()} appointment at MKES CARE+ tomorrow, $formattedDate at ${appt.formattedTime}$docStr.\n\n'
              'Please arrive 10 minutes prior to your scheduled time.\n'
              'Reply STOP to unsubscribe.',
          scheduledFor: reminder24hUtc,
        );
      }

      // 3. Same-Day 8:00 AM IST Reminder (at 08:00 AM IST on appointment date = 02:30 UTC)
      final sameday8amUtc = DateTime.utc(
        appt.appointmentDate.year,
        appt.appointmentDate.month,
        appt.appointmentDate.day,
        2,
        30,
      );
      if (sameday8amUtc.isAfter(nowUtc) && sameday8amUtc.isBefore(apptDateTimeUtc)) {
        await _enqueueOutboxReminder(
          phone: clean10,
          patientId: appt.patientId!,
          appointmentId: appt.id,
          department: dept,
          messageType: 'appointment_reminder',
          templateKey: 'reminder_sameday_8am_${appt.id}',
          messageText: 'Good morning $patientName,\n\n'
              'This is a reminder of your ${dept.toUpperCase()} appointment today, $formattedDate at ${appt.formattedTime}$docStr.\n\n'
              'Please arrive 10 minutes prior to your scheduled time.\n'
              'Reply STOP to unsubscribe.',
          scheduledFor: sameday8amUtc,
        );
      }

      // 4. 2-Hour Prior Reminder (if appointment is >= 2h away)
      final reminder2hUtc = apptDateTimeUtc.subtract(const Duration(hours: 2));
      if (reminder2hUtc.isAfter(nowUtc)) {
        await _enqueueOutboxReminder(
          phone: clean10,
          patientId: appt.patientId!,
          appointmentId: appt.id,
          department: dept,
          messageType: 'reminder_2h',
          templateKey: 'reminder_2h_${appt.id}',
          messageText: 'Dear $patientName, your ${dept.toUpperCase()} appointment at MKES CARE+ is today in 2 hours at ${appt.formattedTime}$docStr.\n\n'
              'Reply STOP to unsubscribe.',
          scheduledFor: reminder2hUtc,
        );
      }
    } catch (_) {
      // Non-blocking: background messaging failure should not fail appointment creation
    }
  }

  Future<void> _enqueueOutboxReminder({
    required String phone,
    required String patientId,
    required String appointmentId,
    required String department,
    required String messageType,
    required String templateKey,
    required String messageText,
    required DateTime scheduledFor,
  }) async {
    try {
      // Duplicate prevention: check if this specific reminder is already enqueued
      final existing = await _supabase
          .from('whatsapp_messages_outbox')
          .select('id')
          .eq('appointment_id', appointmentId)
          .eq('template_key', templateKey)
          .maybeSingle();

      if (existing != null) return;

      try {
        await _supabase.rpc('send_staff_whatsapp_message', params: {
          'p_recipient_phone': phone,
          'p_patient_id': patientId,
          'p_department': department,
          'p_message_text': messageText,
          'p_media_url': null,
          'p_template_key': templateKey,
          'p_message_type': messageType,
          'p_scheduled_for': scheduledFor.toIso8601String(),
          'p_appointment_id': appointmentId,
        });
      } catch (_) {
        // Fallback to direct outbox insert if RPC signature is legacy
        await _supabase.from('whatsapp_messages_outbox').insert({
          'recipient_phone': phone,
          'patient_id': patientId,
          'appointment_id': appointmentId,
          'department': department,
          'message_type': messageType,
          'template_key': templateKey,
          'message_text': messageText,
          'scheduled_for': scheduledFor.toIso8601String(),
          'status': 'pending',
        });
      }
    } catch (_) {}
  }

  /// Cancels all pending reminders for an appointment in the outbox.
  Future<void> _cancelPendingReminders(String appointmentId) async {
    try {
      await _supabase
          .from('whatsapp_messages_outbox')
          .update({
            'status': 'cancelled',
            'last_error': 'Appointment cancelled or rescheduled by staff',
            'updated_at': DateTime.now().toUtc().toIso8601String(),
          })
          .eq('appointment_id', appointmentId)
          .eq('status', 'pending');
    } catch (_) {}
  }

  /// Update appointment fields.
  Future<void> updateAppointment(
    String id,
    Map<String, dynamic> updates,
  ) async {
    if (updates.containsKey('appointment_date') &&
        updates.containsKey('appointment_time') &&
        updates.containsKey('department')) {
      final date = DateTime.tryParse(updates['appointment_date'] as String);
      final time = updates['appointment_time'] as String;
      final dept = updates['department'] as String;

      if (date != null) {
        final conflict = await checkAppointmentConflict(
          date: date,
          time: time,
          department: dept,
          patientId: updates['patient_id'] as String?,
          doctorId: updates['doctor_id'] as String?,
          doctorName: updates['doctor_name'] as String?,
          excludeAppointmentId: id,
        );
        if (conflict != null) {
          throw AppointmentConflictException(conflict);
        }
      }
    }
    final payload = Map<String, dynamic>.from(updates);
    payload['updated_at'] = DateTime.now().toUtc().toIso8601String();

    final isRescheduled = updates.containsKey('appointment_date') || updates.containsKey('appointment_time');

    await _supabase.from('appointments').update(payload).eq('id', id);

    // If rescheduled, cancel old pending reminders and re-schedule new ones
    if (isRescheduled) {
      await _cancelPendingReminders(id);
      final updatedAppt = await fetchAppointmentById(id);
      if (updatedAppt != null && updatedAppt.status.toLowerCase() != 'cancelled') {
        _scheduleAppointmentNotifications(updatedAppt, null);
      }
    }
  }

  /// Update appointment status (e.g. 'scheduled', 'confirmed', 'completed', 'cancelled').
  Future<void> updateStatus(String id, String status) async {
    final lowerStatus = status.toLowerCase();
    await _supabase.from('appointments').update({
      'status': lowerStatus,
      'updated_at': DateTime.now().toUtc().toIso8601String(),
    }).eq('id', id);

    // Cancel reminders immediately if appointment is cancelled
    if (lowerStatus == 'cancelled') {
      await _cancelPendingReminders(id);
    }
  }

  /// Delete an appointment.
  Future<void> deleteAppointment(String id) async {
    await _cancelPendingReminders(id);
    await _supabase.from('appointments').delete().eq('id', id);
  }
}
