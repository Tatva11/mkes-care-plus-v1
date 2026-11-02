import 'package:flutter_riverpod/flutter_riverpod.dart';

import '../../../core/constants/clinic_location_constants.dart';
import '../../auth/providers/auth_provider.dart';
import '../../auth/providers/staff_location_provider.dart';
import '../models/attendance_record.dart';
import '../models/shift_configuration.dart';
import '../repositories/attendance_repository.dart';

final attendanceProvider = StateNotifierProvider.family<AttendanceNotifier,
    AsyncValue<List<AttendanceRecord>>, String>((ref, staffId) {
  final repo = ref.watch(attendanceRepositoryProvider);
  return AttendanceNotifier(repo, staffId, ref: ref);
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
  final Ref? _ref;

  AttendanceNotifier(this._repository, this._staffId, {Ref? ref})
      : _ref = ref,
        super(const AsyncValue.loading()) {
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
    // Verify location freshness before check-in
    if (_ref != null) {
      final isNearClinic = await _ref
          .read(staffLocationProvider.notifier)
          .ensureValidLocation();
      if (!isNearClinic) {
        throw Exception(
          'Location verification failed. You must be physically within the clinic ${ClinicLocationConstants.allowedRadiusMeters.toInt()}m radius to record attendance.',
        );
      }
    }

    try {
      await _repository.checkIn(_staffId, shift: shift, config: config);
      await fetchCurrentMonth();
      _ref?.invalidate(staffClockInStatusProvider);
    } catch (e) {
      rethrow;
    }
  }

  Future<void> checkOut(
      {String shift = 'morning', ShiftConfiguration? config}) async {
    // Verify location freshness before check-out
    if (_ref != null) {
      final isNearClinic = await _ref
          .read(staffLocationProvider.notifier)
          .ensureValidLocation();
      if (!isNearClinic) {
        throw Exception(
          'Location verification failed. You must be physically within the clinic ${ClinicLocationConstants.allowedRadiusMeters.toInt()}m radius to record attendance.',
        );
      }
    }

    try {
      await _repository.checkOut(_staffId, shift: shift, config: config);
      await fetchCurrentMonth();
      _ref?.invalidate(staffClockInStatusProvider);
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

/// Evaluates if the current user is allowed to perform clinic operations.
/// Returns true for Admin users (role == 'admin').
/// Returns true for Staff users who have clocked in for today's working day.
/// Returns false for unclocked Staff users.
final staffClockInStatusProvider = FutureProvider<bool>((ref) async {
  final roleAsync = ref.watch(currentUserRoleProvider);
  final role = roleAsync.value;
  // Admin is never blocked
  if (role == 'admin') return true;
  // If role is null or not staff (e.g. non-staff, test or unauthenticated), do not block
  if (role != null && role != 'staff') return true;

  final user = ref.watch(currentUserProvider);
  if (user == null) return true; // non-authenticated context or unit test

  final repo = ref.watch(attendanceRepositoryProvider);
  return repo.isStaffClockedInToday(user.id);
});
