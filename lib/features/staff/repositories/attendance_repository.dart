import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:supabase_flutter/supabase_flutter.dart';

import '../../../core/providers/supabase_provider.dart';
import '../models/attendance_record.dart';
import 'attendance_source.dart';

final attendanceRepositoryProvider = Provider<AttendanceRepository>((ref) {
  return AttendanceRepository(ref.watch(supabaseProvider));
});

class ManualAttendanceSource implements AttendanceSource {
  final SupabaseClient _supabase;
  ManualAttendanceSource(this._supabase);

  @override
  Future<void> recordCheckIn(String staffId, DateTime time) async {
    final dateStr = time.toIso8601String().split('T').first;
    final existing = await _supabase
        .from('staff_attendance')
        .select('id, check_out_time')
        .eq('staff_id', staffId)
        .eq('record_date', dateStr)
        .maybeSingle();

    if (existing != null) {
      final hasClockedOut = existing['check_out_time'] != null;
      if (!hasClockedOut) {
        throw Exception('Attendance already recorded for today. Please clock out instead.');
      }
      throw Exception('Attendance for today has already been completed.');
    }

    final isLate = time.hour > 9 || (time.hour == 9 && time.minute > 0);
    final lateMinutes = isLate ? ((time.hour - 9) * 60 + time.minute).clamp(0, 999) : 0;

    await _supabase.from('staff_attendance').insert({
      'staff_id': staffId,
      'record_date': dateStr,
      'check_in_time': time.toIso8601String(),
      'status': isLate ? 'late' : 'present',
      'is_late': isLate,
      'late_minutes': lateMinutes,
      'updated_at': DateTime.now().toIso8601String(),
    });
  }

  @override
  Future<void> recordCheckOut(String staffId, DateTime time) async {
    final dateStr = time.toIso8601String().split('T').first;

    final existing = await _supabase
        .from('staff_attendance')
        .select('check_in_time, check_out_time')
        .eq('staff_id', staffId)
        .eq('record_date', dateStr)
        .maybeSingle();

    if (existing == null) {
      throw Exception('No attendance record found for today. Please clock in first.');
    }

    if (existing['check_out_time'] != null) {
      throw Exception('Attendance for today has already been clocked out.');
    }

    final checkIn = DateTime.parse(existing['check_in_time'] as String);
    final workingHours = time.difference(checkIn).inMinutes / 60.0;

    await _supabase.from('staff_attendance').update({
      'check_out_time': time.toIso8601String(),
      'working_hours': workingHours,
      'updated_at': DateTime.now().toIso8601String(),
    }).eq('staff_id', staffId).eq('record_date', dateStr);
  }
}

class AttendanceRepository {
  final SupabaseClient _supabase;
  late final AttendanceSource _source;

  AttendanceRepository(this._supabase) {
    _source = ManualAttendanceSource(_supabase);
  }

  /// Get attendance for a specific user and month
  Future<List<AttendanceRecord>> fetchMonthlyAttendance(String staffId, int year, int month) async {
    final startDate = DateTime(year, month, 1).toIso8601String().split('T').first;
    final endDate = DateTime(year, month + 1, 0).toIso8601String().split('T').first;

    final response = await _supabase
        .from('staff_attendance')
        .select()
        .eq('staff_id', staffId)
        .gte('record_date', startDate)
        .lte('record_date', endDate)
        .order('record_date', ascending: false);

    return (response as List).map((json) => AttendanceRecord.fromJson(json)).toList();
  }

  Future<List<AttendanceRecord>> fetchAllStaffAttendanceForDate(DateTime date) async {
    final dateKey = date.toIso8601String().split('T').first;
    final response = await _supabase
        .from('staff_attendance')
      .select('*, profiles!staff_attendance_staff_id_fkey!inner(full_name, role)')
      .eq('profiles.role', 'staff')
        .eq('record_date', dateKey)
        .order('staff_id', ascending: true);

    final records = (response as List)
        .map((json) => AttendanceRecord.fromJson(json))
        .toList();

    return records;
  }

  Future<Map<String, int>> fetchDailySummary(DateTime date) async {
    final records = await fetchAllStaffAttendanceForDate(date);
    final summary = {'present': 0, 'late': 0, 'absent': 0, 'leave': 0, 'holiday': 0};

    for (final record in records) {
      final status = record.status.toLowerCase();
      if (summary.containsKey(status)) {
        summary[status] = summary[status]! + 1;
      }
    }

    return summary;
  }

  Future<AttendanceRecord?> fetchTodayAttendance(String staffId) async {
    final today = DateTime.now().toIso8601String().split('T').first;
    final response = await _supabase
        .from('staff_attendance')
        .select()
        .eq('staff_id', staffId)
        .eq('record_date', today)
        .maybeSingle();

    if (response == null) return null;
    return AttendanceRecord.fromJson(response);
  }

  Future<void> checkIn(String staffId) async {
    await _source.recordCheckIn(staffId, DateTime.now());
  }

  Future<void> checkOut(String staffId) async {
    await _source.recordCheckOut(staffId, DateTime.now());
  }
}
