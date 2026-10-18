import 'package:flutter_riverpod/flutter_riverpod.dart';

import '../models/attendance_record.dart';
import '../models/shift_configuration.dart';
import '../repositories/attendance_repository.dart';

final attendanceProvider = StateNotifierProvider.family<AttendanceNotifier,
    AsyncValue<List<AttendanceRecord>>, String>((ref, staffId) {
  final repo = ref.watch(attendanceRepositoryProvider);
  return AttendanceNotifier(repo, staffId);
});

final adminAttendanceForDateProvider =
    FutureProvider.family<List<AttendanceRecord>, DateTime>((ref, date) {
  final repo = ref.watch(attendanceRepositoryProvider);
  return repo.fetchAllStaffAttendanceForDate(date);
});

final adminAttendanceSummaryProvider =
    FutureProvider.family<Map<String, int>, DateTime>((ref, date) {
  final repo = ref.watch(attendanceRepositoryProvider);
  return repo.fetchDailySummary(date);
});

final shiftConfigurationsProvider =
    FutureProvider<List<ShiftConfiguration>>((ref) async {
  final repo = ref.watch(attendanceRepositoryProvider);
  return repo.fetchShiftConfigurations();
});

final staffAssignedShiftProvider =
    FutureProvider.family<String?, String>((ref, staffId) async {
  final repo = ref.watch(attendanceRepositoryProvider);
  return repo.fetchStaffShiftAssignment(staffId);
});

final staffAssignedShiftForDateProvider =
    FutureProvider.family<String?, ({String staffId, DateTime date})>(
        (ref, params) async {
  final repo = ref.watch(attendanceRepositoryProvider);
  return repo.fetchStaffShiftAssignment(params.staffId, forDate: params.date);
});

final staffActiveAttendanceProvider =
    FutureProvider.family<AttendanceRecord?, String>((ref, staffId) async {
  final repo = ref.watch(attendanceRepositoryProvider);
  return repo.fetchActiveAttendance(staffId);
});

class AttendanceNotifier
    extends StateNotifier<AsyncValue<List<AttendanceRecord>>> {
  final AttendanceRepository _repository;
  final String _staffId;

  AttendanceNotifier(this._repository, this._staffId)
      : super(const AsyncValue.loading()) {
    fetchCurrentMonth();
  }

  Future<void> fetchCurrentMonth({String? shift}) async {
    final now = DateTime.now();
    await fetchMonth(now.year, now.month, shift: shift);
  }

  Future<void> fetchMonth(int year, int month, {String? shift}) async {
    state = const AsyncValue.loading();
    try {
      final records = await _repository
          .fetchMonthlyAttendance(_staffId, year, month, shift: shift);
      state = AsyncValue.data(records);
    } catch (e, st) {
      state = AsyncValue.error(e, st);
    }
  }

  Future<void> checkIn(
      {String shift = 'morning', ShiftConfiguration? config}) async {
    try {
      await _repository.checkIn(_staffId, shift: shift, config: config);
      await fetchCurrentMonth();
    } catch (e) {
      rethrow;
    }
  }

  Future<void> checkOut(
      {String shift = 'morning', ShiftConfiguration? config}) async {
    try {
      await _repository.checkOut(_staffId, shift: shift, config: config);
      await fetchCurrentMonth();
    } catch (e) {
      rethrow;
    }
  }
}

final todayAttendanceProvider =
    FutureProvider.family<AttendanceRecord?, String>((ref, staffId) async {
  final repo = ref.watch(attendanceRepositoryProvider);
  return repo.fetchTodayAttendance(staffId, shift: 'morning');
});

final todayShiftAttendanceProvider = FutureProvider.family<
    AttendanceRecord?,
    ({
      String staffId,
      String shift,
      ShiftConfiguration? config
    })>((ref, params) async {
  final repo = ref.watch(attendanceRepositoryProvider);
  return repo.fetchTodayAttendance(params.staffId,
      shift: params.shift, config: params.config);
});
