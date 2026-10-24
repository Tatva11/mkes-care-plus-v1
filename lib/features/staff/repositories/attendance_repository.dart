import 'package:flutter/foundation.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:supabase_flutter/supabase_flutter.dart';

import '../../../core/providers/supabase_provider.dart';
import '../models/attendance_record.dart';
import '../models/shift_configuration.dart';
import 'attendance_source.dart';

final attendanceRepositoryProvider = Provider<AttendanceRepository>((ref) {
  return AttendanceRepository(ref.watch(supabaseProvider));
});

class ManualAttendanceSource implements AttendanceSource {
  final SupabaseClient _supabase;
  ManualAttendanceSource(this._supabase);

  /// Computes the logical shift date.
  /// For night shifts (e.g. 11:00 PM - 07:00 AM), early morning hours
  /// belong to the shift that started the previous evening.
  static String getShiftDateStr(
    DateTime time,
    String shift, {
    ShiftConfiguration? config,
  }) {
    if (config != null) {
      return config.getLogicalShiftDateStr(time);
    }
    if (shift.toLowerCase() == 'night' && time.hour < 8) {
      final prevDay = time.subtract(const Duration(days: 1));
      return prevDay.toIso8601String().split('T').first;
    }
    return time.toIso8601String().split('T').first;
  }

  @override
  Future<void> recordCheckIn(
    String staffId,
    DateTime time, {
    String shift = 'morning',
    ShiftConfiguration? config,
  }) async {
    final normalizedShift =
        shift.toLowerCase() == 'night' ? 'afternoon' : shift.toLowerCase();
    final dateStr = getShiftDateStr(time, normalizedShift, config: config);

    // Check if user already clocked into this shift today
    final existing = await _supabase
        .from('staff_attendance')
        .select('id, check_out_time')
        .eq('staff_id', staffId)
        .eq('record_date', dateStr)
        .eq('shift', normalizedShift)
        .maybeSingle();

    if (existing != null) {
      final hasClockedOut = existing['check_out_time'] != null;
      if (!hasClockedOut) {
        // Idempotent: already clocked in for this shift today (e.g. repeated tap)
        return;
      }
      throw Exception(
        'Attendance for this $shift shift today has already been completed.',
      );
    }

    // Determine late status based on Admin-configured shift timings
    bool isLate;
    int lateMinutes;

    if (config != null) {
      lateMinutes = config.calculateLateMinutes(time);
      isLate = lateMinutes > 0;
    } else {
      // Fallback hardcoded defaults if no config object passed
      if (normalizedShift == 'afternoon' || normalizedShift == 'night') {
        isLate = time.hour > 13 || (time.hour == 13 && time.minute > 15);
        lateMinutes =
            isLate ? ((time.hour - 13) * 60 + time.minute).clamp(0, 999) : 0;
      } else {
        isLate = time.hour > 8 || (time.hour == 8 && time.minute > 15);
        lateMinutes =
            isLate ? ((time.hour - 8) * 60 + time.minute).clamp(0, 999) : 0;
      }
    }

    try {
      await _supabase.from('staff_attendance').insert({
        'staff_id': staffId,
        'record_date': dateStr,
        'shift': normalizedShift,
        'check_in_time': time.toUtc().toIso8601String(),
        'status': isLate ? 'late' : 'present',
        'is_late': isLate,
        'late_minutes': lateMinutes,
        'updated_at': DateTime.now().toUtc().toIso8601String(),
      });
    } on PostgrestException catch (e) {
      if (e.code == '23505' ||
          e.message.contains('unique') ||
          e.message.contains('duplicate')) {
        // Concurrent duplicate tap: already inserted
        return;
      }
      rethrow;
    }
  }

  @override
  Future<void> recordCheckOut(
    String staffId,
    DateTime time, {
    String shift = 'morning',
    ShiftConfiguration? config,
  }) async {
    final normalizedShift =
        shift.toLowerCase() == 'night' ? 'afternoon' : shift.toLowerCase();
    final dateStr = getShiftDateStr(time, normalizedShift, config: config);

    // 1. Look for active unclosed check-in for this specific staff member, shift, and logical shift date.
    final active = await _supabase
        .from('staff_attendance')
        .select('id, record_date, shift, check_in_time, check_out_time')
        .eq('staff_id', staffId)
        .eq('record_date', dateStr)
        .eq('shift', normalizedShift)
        .not('check_in_time', 'is', null)
        .isFilter('check_out_time', null)
        .maybeSingle();

    if (active != null) {
      final checkInStr = active['check_in_time']?.toString();
      final checkIn = checkInStr != null ? DateTime.tryParse(checkInStr)?.toLocal() : null;
      if (checkIn != null) {
        final workingHours = double.parse(
            (time.toLocal().difference(checkIn).inMinutes / 60.0)
                .clamp(0.0, 24.0)
                .toStringAsFixed(2));

        await _supabase.from('staff_attendance').update({
          'check_out_time': time.toUtc().toIso8601String(),
          'working_hours': workingHours,
          'updated_at': DateTime.now().toUtc().toIso8601String(),
        }).eq('id', active['id']);
        return;
      }
    }

    // 2. Check if a record exists for this shift today that is already closed
    final existing = await _supabase
        .from('staff_attendance')
        .select('id, check_in_time, check_out_time')
        .eq('staff_id', staffId)
        .eq('record_date', dateStr)
        .eq('shift', normalizedShift)
        .maybeSingle();

    if (existing == null) {
      throw Exception(
        'No active attendance session found for $shift shift today. Please clock in first.',
      );
    }

    if (existing['check_out_time'] != null) {
      // Idempotent: already clocked out for this shift today (e.g. repeated tap)
      return;
    }
  }
}

class AttendanceRepository {
  final SupabaseClient _supabase;
  late final AttendanceSource _source;

  AttendanceRepository(this._supabase) {
    _source = ManualAttendanceSource(_supabase);
  }

  /// Get attendance for a specific user and month (staff only)
  Future<List<AttendanceRecord>> fetchMonthlyAttendance(
    String staffId,
    int year,
    int month, {
    String? shift,
  }) async {
    final startDate =
        DateTime(year, month, 1).toIso8601String().split('T').first;
    final endDate =
        DateTime(year, month + 1, 0).toIso8601String().split('T').first;

    var query = _supabase
        .from('staff_attendance')
        .select(
            '*, profiles!staff_attendance_staff_id_fkey!inner(full_name, role)')
        .eq('profiles.role', 'staff')
        .eq('staff_id', staffId)
        .gte('record_date', startDate)
        .lte('record_date', endDate);

    if (shift != null && shift.isNotEmpty && shift != 'all') {
      query = query.eq('shift', shift.toLowerCase());
    }

    final response = await query.order('record_date', ascending: false);

    return (response as List)
        .map((json) => AttendanceRecord.fromJson(json))
        .toList();
  }

  Future<List<AttendanceRecord>> fetchAllStaffAttendanceForDate(
    DateTime date, {
    String? shift,
  }) async {
    // Ensure any open overdue shifts are finalized so all views are synchronized
    try {
      await autoTerminateOverdueAttendance();
    } catch (_) {}

    final dateKey = date.toIso8601String().split('T').first;
    var query = _supabase
        .from('staff_attendance')
        .select(
            '*, profiles!staff_attendance_staff_id_fkey!inner(full_name, role)')
        .eq('profiles.role', 'staff')
        .eq('record_date', dateKey);

    if (shift != null && shift.isNotEmpty && shift != 'all') {
      query = query.eq('shift', shift.toLowerCase());
    }

    final response = await query.order('staff_id', ascending: true);

    return (response as List)
        .map((json) => AttendanceRecord.fromJson(json))
        .toList();
  }

  Future<Map<String, int>> fetchDailySummary(DateTime date,
      {String? shift}) async {
    final records = await fetchAllStaffAttendanceForDate(date, shift: shift);
    final summary = {
      'present': 0,
      'late': 0,
      'absent': 0,
      'leave': 0,
      'holiday': 0
    };

    for (final record in records) {
      final status = record.status.toLowerCase();
      // An account is only counted as present or late if they recorded a valid check-in
      if (record.checkInTime != null) {
        if (record.isLate || status == 'late') {
          summary['late'] = summary['late']! + 1;
        } else {
          summary['present'] = summary['present']! + 1;
        }
      } else if (status == 'leave') {
        summary['leave'] = summary['leave']! + 1;
      } else if (status == 'absent') {
        summary['absent'] = summary['absent']! + 1;
      } else if (status == 'holiday') {
        summary['holiday'] = summary['holiday']! + 1;
      }
    }

    return summary;
  }

  Future<AttendanceRecord?> fetchTodayAttendance(
    String staffId, {
    String shift = 'morning',
    ShiftConfiguration? config,
  }) async {
    final now = DateTime.now();
    final normShift =
        (shift.toLowerCase() == 'night' || shift.toLowerCase() == 'evening')
            ? 'afternoon'
            : shift.toLowerCase();
    final today =
        ManualAttendanceSource.getShiftDateStr(now, normShift, config: config);

    final response = await _supabase
        .from('staff_attendance')
        .select()
        .eq('staff_id', staffId)
        .eq('record_date', today)
        .eq('shift', normShift)
        .maybeSingle();

    if (response == null) return null;
    final record = AttendanceRecord.fromJson(response);

    // Automatic termination safeguard if past configured end time and still unclosed
    if (record.checkInTime != null &&
        record.checkOutTime == null &&
        config != null) {
      if (config.isTimePastShiftEnd(now)) {
        try {
          await _supabase.rpc('auto_terminate_overdue_shifts');
        } catch (_) {
          final endDateTime =
              config.getShiftEndDateTime(record.checkInTime!.toLocal());
          final effectiveClose = now.isAfter(endDateTime) ? endDateTime : now;
          final workingHours = double.parse(
              (effectiveClose.difference(record.checkInTime!.toLocal()).inMinutes / 60.0)
                  .clamp(0.0, 24.0)
                  .toStringAsFixed(2));
          await _supabase.from('staff_attendance').update({
            'check_out_time': effectiveClose.toUtc().toIso8601String(),
            'working_hours': workingHours,
            'notes': (record.notes == null || record.notes!.isEmpty)
                ? 'Auto-clocked out at configured shift end time'
                : '${record.notes} | Auto-clocked out at configured shift end time',
            'updated_at': DateTime.now().toUtc().toIso8601String(),
          }).eq('id', record.id);
        }
        final updatedResp = await _supabase
            .from('staff_attendance')
            .select()
            .eq('id', record.id)
            .maybeSingle();
        if (updatedResp != null) {
          return AttendanceRecord.fromJson(updatedResp);
        }
      }
    }

    return record;
  }

  /// Closes any open attendance records that have exceeded their scheduled shift-end time.
  /// Sets check_out_time to the scheduled shift end time (not the current time).
  Future<int> autoTerminateOverdueAttendance() async {
    try {
      final res = await _supabase.rpc('auto_terminate_overdue_shifts');
      final count =
          (res is int) ? res : int.tryParse(res?.toString() ?? '0') ?? 0;
      if (count > 0) return count;
    } catch (e) {
      debugPrint('autoTerminateOverdueAttendance RPC error: $e');
    }

    // Resilient fallback: query open attendance records and close if past shift end
    try {
      final configs = await fetchShiftConfigurations();
      final now = DateTime.now();

      final unclosedRecords = await _supabase
          .from('staff_attendance')
          .select()
          .not('check_in_time', 'is', null)
          .isFilter('check_out_time', null);

      int closedCount = 0;
      for (final raw in (unclosedRecords as List)) {
        final rec = AttendanceRecord.fromJson(raw);
        if (rec.status.toLowerCase() == 'leave' ||
            rec.status.toLowerCase() == 'holiday' ||
            rec.status.toLowerCase() == 'absent') {
          continue;
        }

        final shiftName = (rec.shift.toLowerCase() == 'night' ||
                rec.shift.toLowerCase() == 'evening')
            ? 'afternoon'
            : rec.shift.toLowerCase();
        final config = configs.firstWhere(
          (c) => c.shift.toLowerCase() == shiftName,
          orElse: () => shiftName == 'morning'
              ? ShiftConfiguration.defaultMorning
              : ShiftConfiguration.defaultAfternoon,
        );

        if (rec.checkInTime != null && config.isTimePastShiftEnd(now)) {
          final endDateTime =
              config.getShiftEndDateTime(rec.checkInTime!.toLocal());
          final effectiveClose = now.isAfter(endDateTime) ? endDateTime : now;
          final workingHours = double.parse(
              (effectiveClose.difference(rec.checkInTime!.toLocal()).inMinutes / 60.0)
                  .clamp(0.0, 24.0)
                  .toStringAsFixed(2));

          await _supabase
              .from('staff_attendance')
              .update({
                'check_out_time': effectiveClose.toUtc().toIso8601String(),
                'working_hours': workingHours,
                'notes': (rec.notes == null || rec.notes!.isEmpty)
                    ? 'Auto-clocked out at configured shift end time'
                    : (rec.notes!.contains('Auto-clocked out')
                        ? rec.notes
                        : '${rec.notes} | Auto-clocked out at configured shift end time'),
                'updated_at': DateTime.now().toUtc().toIso8601String(),
              })
              .eq('id', rec.id)
              .isFilter('check_out_time', null);

          closedCount++;
        }
      }
      return closedCount;
    } catch (fallbackError) {
      debugPrint(
          'autoTerminateOverdueAttendance fallback error: $fallbackError');
      return 0;
    }
  }

  /// Fetches an active (clocked-in but not clocked-out) attendance session for the staff member.
  /// If [shift] is provided, matches that shift on the logical shift date.
  /// Only matches sessions for today's logical shift date.
  Future<AttendanceRecord?> fetchActiveAttendance(
    String staffId, {
    String? shift,
    ShiftConfiguration? config,
    DateTime? forTime,
  }) async {
    try {
      final checkTime = forTime ?? DateTime.now();
      var query = _supabase
          .from('staff_attendance')
          .select()
          .eq('staff_id', staffId)
          .not('check_in_time', 'is', null)
          .isFilter('check_out_time', null);

      if (shift != null && shift.isNotEmpty && shift.toLowerCase() != 'both') {
        final normShift =
            (shift.toLowerCase() == 'night' || shift.toLowerCase() == 'evening')
                ? 'afternoon'
                : shift.toLowerCase();
        final dateStr = ManualAttendanceSource.getShiftDateStr(
            checkTime, normShift,
            config: config);
        query = query.eq('shift', normShift).eq('record_date', dateStr);
      } else {
        final todayStr = checkTime.toIso8601String().split('T').first;
        query = query.eq('record_date', todayStr);
      }

      final response = await query
          .order('check_in_time', ascending: false)
          .limit(1)
          .maybeSingle();

      if (response == null) return null;
      final record = AttendanceRecord.fromJson(response);

      // If active session has passed scheduled shift end time, auto-close at shift end
      ShiftConfiguration? activeConfig = config;
      if (activeConfig == null) {
        try {
          final configs = await fetchShiftConfigurations();
          final norm = (record.shift.toLowerCase() == 'night' ||
                  record.shift.toLowerCase() == 'evening')
              ? 'afternoon'
              : record.shift.toLowerCase();
          activeConfig = configs.firstWhere(
            (c) => c.shift.toLowerCase() == norm,
            orElse: () => norm == 'morning'
                ? ShiftConfiguration.defaultMorning
                : ShiftConfiguration.defaultAfternoon,
          );
        } catch (_) {}
      }

      if (record.checkInTime != null &&
          activeConfig != null &&
          activeConfig.isTimePastShiftEnd(checkTime)) {
        final endDateTime =
            activeConfig.getShiftEndDateTime(record.checkInTime!.toLocal());
        final effectiveClose =
            checkTime.isAfter(endDateTime) ? endDateTime : checkTime;
        final workingHours = double.parse(
            (effectiveClose.difference(record.checkInTime!.toLocal()).inMinutes / 60.0)
                .clamp(0.0, 24.0)
                .toStringAsFixed(2));
        await _supabase.from('staff_attendance').update({
          'check_out_time': effectiveClose.toUtc().toIso8601String(),
          'working_hours': workingHours,
          'notes': (record.notes == null || record.notes!.isEmpty)
              ? 'Auto-clocked out at configured shift end time'
              : (record.notes!.contains('Auto-clocked out')
                  ? record.notes
                  : '${record.notes} | Auto-clocked out at configured shift end time'),
          'updated_at': DateTime.now().toUtc().toIso8601String(),
        }).eq('id', record.id);
        return null;
      }

      return record;
    } catch (e) {
      debugPrint('fetchActiveAttendance error: $e');
      return null;
    }
  }

  /// Shift Configurations
  Future<List<ShiftConfiguration>> fetchShiftConfigurations() async {
    try {
      final response = await _supabase
          .from('shift_configurations')
          .select()
          .order('name', ascending: true);

      final rows = response as List;
      if (rows.isEmpty) {
        return const [
          ShiftConfiguration.defaultMorning,
          ShiftConfiguration.defaultAfternoon,
        ];
      }

      final list = rows
          .map((json) =>
              ShiftConfiguration.fromJson(json as Map<String, dynamic>))
          .toList();

      // Ensure both morning and afternoon are present
      final hasMorning = list.any((s) => s.name == 'morning');
      final hasAfternoon =
          list.any((s) => s.name == 'afternoon' || s.name == 'night');

      return [
        if (hasMorning)
          list.firstWhere((s) => s.name == 'morning')
        else
          ShiftConfiguration.defaultMorning,
        if (hasAfternoon)
          list.firstWhere((s) => s.name == 'afternoon' || s.name == 'night')
        else
          ShiftConfiguration.defaultAfternoon,
      ];
    } catch (e) {
      debugPrint('fetchShiftConfigurations error (using defaults): $e');
      return const [
        ShiftConfiguration.defaultMorning,
        ShiftConfiguration.defaultAfternoon,
      ];
    }
  }

  Future<void> updateShiftConfiguration(ShiftConfiguration config) async {
    try {
      await _supabase.from('shift_configurations').upsert(
            config.toJson(),
            onConflict: 'name',
          );
    } catch (e) {
      debugPrint('updateShiftConfiguration error: $e');
      rethrow;
    }
  }

  /// Staff Shift Assignment with effective-dated scheduling (profiles.assigned_shift / next_shift).
  /// If [effectiveDate] is omitted, defaults to the next calendar day (tomorrow) in clinic time.
  /// When effective from tomorrow or future date:
  /// - Stores `next_shift` and `shift_effective_date` on `profiles`.
  /// - Does NOT overwrite `assigned_shift` or existing attendance records for today.
  /// - Deliberately replaces any existing future assignment without conflict.
  /// - Records the assignment in `staff_shift_assignments` table.
  /// If [effectiveDate] is explicitly today or in the past:
  /// - Updates `assigned_shift` directly, clearing `next_shift` and `shift_effective_date`.
  Future<void> updateStaffShiftAssignment(
    String staffId,
    String shift, {
    DateTime? effectiveDate,
  }) async {
    final normalized = shift.toLowerCase().trim();
    if (normalized != 'morning' &&
        normalized != 'afternoon' &&
        normalized != 'evening' &&
        normalized != 'both' &&
        normalized != 'night') {
      throw ArgumentError(
          'Invalid shift: $shift. Must be morning, evening, or both.');
    }

    final storedShift = (normalized == 'night' || normalized == 'evening')
        ? 'afternoon'
        : normalized;

    final now = DateTime.now();
    final today = DateTime(now.year, now.month, now.day);
    final targetDate = effectiveDate != null
        ? DateTime(effectiveDate.year, effectiveDate.month, effectiveDate.day)
        : today.add(const Duration(days: 1)); // Default: next calendar day

    final targetDateStr =
        '${targetDate.year.toString().padLeft(4, '0')}-${targetDate.month.toString().padLeft(2, '0')}-${targetDate.day.toString().padLeft(2, '0')}';

    try {
      final isFutureEffective = targetDate.isAfter(today);

      final updatePayload = <String, dynamic>{
        'updated_at': DateTime.now().toUtc().toIso8601String(),
      };

      if (isFutureEffective) {
        // Effective from tomorrow or a future date:
        // Schedule in next_shift / shift_effective_date without overwriting today's working shift.
        updatePayload['next_shift'] = storedShift;
        updatePayload['shift_effective_date'] = targetDateStr;
      } else {
        // Effective today: update active assigned_shift directly
        updatePayload['assigned_shift'] = storedShift;
        updatePayload['next_shift'] = null;
        updatePayload['shift_effective_date'] = null;
      }

      await _supabase.from('profiles').update(updatePayload).eq('id', staffId);

      // Best-effort record in staff_shift_assignments table (idempotent upsert)
      try {
        await _supabase.from('staff_shift_assignments').upsert({
          'staff_id': staffId,
          'shift': storedShift,
          'effective_date': targetDateStr,
          'created_at': DateTime.now().toUtc().toIso8601String(),
        }, onConflict: 'staff_id,effective_date');
      } catch (tableErr) {
        debugPrint(
            'Note: staff_shift_assignments table insert skipped or unavailable: $tableErr');
      }
    } catch (e) {
      debugPrint('updateStaffShiftAssignment error: $e');
      rethrow;
    }
  }

  /// Fetches staff shift assignment for a given calendar date (defaults to today).
  /// If a scheduled shift change exists and [forDate] is on or after [shift_effective_date],
  /// returns [next_shift]. Otherwise returns [assigned_shift].
  /// Returns null if no shift is assigned (honest unassigned state).
  Future<String?> fetchStaffShiftAssignment(String staffId,
      {DateTime? forDate}) async {
    try {
      final response = await _supabase
          .from('profiles')
          .select('assigned_shift, next_shift, shift_effective_date')
          .eq('id', staffId)
          .maybeSingle();

      if (response != null) {
        final assigned =
            response['assigned_shift']?.toString().toLowerCase().trim();
        final next = response['next_shift']?.toString().toLowerCase().trim();
        final effStr = response['shift_effective_date']?.toString();

        if (next != null &&
            next.isNotEmpty &&
            effStr != null &&
            effStr.isNotEmpty) {
          final now = DateTime.now();
          final target = forDate ?? now;
          final targetOnly = DateTime(target.year, target.month, target.day);

          DateTime? effDate;
          final match =
              RegExp(r'^(\d{4})-(\d{2})-(\d{2})').firstMatch(effStr.trim());
          if (match != null) {
            effDate = DateTime(
              int.parse(match.group(1)!),
              int.parse(match.group(2)!),
              int.parse(match.group(3)!),
            );
          } else {
            effDate = DateTime.tryParse(effStr);
          }

          if (effDate != null) {
            final effOnly = DateTime(effDate.year, effDate.month, effDate.day);
            if (!targetOnly.isBefore(effOnly)) {
              if (next == 'both') return 'both';
              if (next == 'afternoon' || next == 'evening' || next == 'night') {
                return 'afternoon';
              }
              if (next == 'morning') return 'morning';
              return next;
            }
          }
        }

        if (assigned != null && assigned.isNotEmpty) {
          if (assigned == 'both') return 'both';
          if (assigned == 'afternoon' ||
              assigned == 'evening' ||
              assigned == 'night') {
            return 'afternoon';
          }
          if (assigned == 'morning') return 'morning';
          return assigned;
        }
      }
      return null;
    } catch (e) {
      debugPrint('fetchStaffShiftAssignment error: $e');
      return null;
    }
  }

  Future<void> checkIn(
    String staffId, {
    String shift = 'morning',
    ShiftConfiguration? config,
  }) async {
    await _source.recordCheckIn(staffId, DateTime.now(),
        shift: shift, config: config);
  }

  Future<void> checkOut(
    String staffId, {
    String shift = 'morning',
    ShiftConfiguration? config,
  }) async {
    await _source.recordCheckOut(staffId, DateTime.now(),
        shift: shift, config: config);
  }
}
