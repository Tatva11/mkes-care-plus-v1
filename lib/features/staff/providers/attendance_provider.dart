import 'package:flutter_riverpod/flutter_riverpod.dart';

import '../models/attendance_record.dart';
import '../repositories/attendance_repository.dart';

final attendanceProvider = StateNotifierProvider.family<AttendanceNotifier, AsyncValue<List<AttendanceRecord>>, String>((ref, staffId) {
  final repo = ref.watch(attendanceRepositoryProvider);
  return AttendanceNotifier(repo, staffId);
});

final adminAttendanceForDateProvider = FutureProvider.family<List<AttendanceRecord>, DateTime>((ref, date) {
  final repo = ref.watch(attendanceRepositoryProvider);
  return repo.fetchAllStaffAttendanceForDate(date);
});

final adminAttendanceSummaryProvider = FutureProvider.family<Map<String, int>, DateTime>((ref, date) {
  final repo = ref.watch(attendanceRepositoryProvider);
  return repo.fetchDailySummary(date);
});

class AttendanceNotifier extends StateNotifier<AsyncValue<List<AttendanceRecord>>> {
  final AttendanceRepository _repository;
  final String _staffId;

  AttendanceNotifier(this._repository, this._staffId) : super(const AsyncValue.loading()) {
    fetchCurrentMonth();
  }

  Future<void> fetchCurrentMonth() async {
    final now = DateTime.now();
    await fetchMonth(now.year, now.month);
  }

  Future<void> fetchMonth(int year, int month) async {
    state = const AsyncValue.loading();
    try {
      final records = await _repository.fetchMonthlyAttendance(_staffId, year, month);
      state = AsyncValue.data(records);
    } catch (e, st) {
      state = AsyncValue.error(e, st);
    }
  }

  Future<void> checkIn() async {
    try {
      await _repository.checkIn(_staffId);
      await fetchCurrentMonth();
    } catch (e) {
      rethrow;
    }
  }

  Future<void> checkOut() async {
    try {
      await _repository.checkOut(_staffId);
      await fetchCurrentMonth();
    } catch (e) {
      rethrow;
    }
  }
}

final todayAttendanceProvider = FutureProvider.family<AttendanceRecord?, String>((ref, staffId) async {
  final repo = ref.watch(attendanceRepositoryProvider);
  return repo.fetchTodayAttendance(staffId);
});
