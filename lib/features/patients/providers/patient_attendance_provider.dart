import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:supabase_flutter/supabase_flutter.dart';

import '../models/patient_attendance.dart';
import '../repositories/patient_attendance_repository.dart';

// ─────────────────────────────────────────────────────────────────────────────
// Staff provider — keyed by staffId; owns today's attendance list and
// the per-patient loading/attended state.
// ─────────────────────────────────────────────────────────────────────────────

final staffPatientAttendanceProvider = StateNotifierProvider.family<
    StaffPatientAttendanceNotifier,
    AsyncValue<List<PatientAttendance>>,
    String>((ref, staffId) {
  return StaffPatientAttendanceNotifier(
    ref.watch(patientAttendanceRepositoryProvider),
    staffId,
  );
});

// ─────────────────────────────────────────────────────────────────────────────
// Admin provider — today's full attendance list (joined with patient + staff).
// ─────────────────────────────────────────────────────────────────────────────

final adminPatientAttendanceProvider =
    FutureProvider<List<PatientAttendance>>((ref) {
  return ref
      .watch(patientAttendanceRepositoryProvider)
      .fetchForAdmin(DateTime.now());
});

// ─────────────────────────────────────────────────────────────────────────────
// Per-patient history provider — available for a future patient-details phase.
// ─────────────────────────────────────────────────────────────────────────────

final patientAttendanceHistoryProvider =
    FutureProvider.family<List<PatientAttendance>, String>((ref, patientId) {
  return ref
      .watch(patientAttendanceRepositoryProvider)
      .fetchForPatient(patientId);
});

// ─────────────────────────────────────────────────────────────────────────────
// Notifier
// ─────────────────────────────────────────────────────────────────────────────

/// PostgreSQL unique-violation error code.
const _kDuplicateKeyCode = '23505';

class StaffPatientAttendanceNotifier
    extends StateNotifier<AsyncValue<List<PatientAttendance>>> {
  final PatientAttendanceRepository _repository;
  final String _staffId;

  /// Patient IDs for which an attendance insertion is currently in-flight.
  final Set<String> _loadingPatientIds = {};

  /// Patient IDs that have already been attended today by any staff member.
  final Set<String> _attendedPatientIds = {};

  /// Patient IDs attended today by this specific logged-in staff member.
  final Set<String> _attendedByMePatientIds = {};

  StaffPatientAttendanceNotifier(this._repository, this._staffId)
      : super(const AsyncValue.loading()) {
    _fetch();
  }

  // ── Public API ────────────────────────────────────────────────────────────

  /// Whether an insert is currently in-flight for [patientId].
  bool isLoading(String patientId) => _loadingPatientIds.contains(patientId);

  /// Whether [patientId] has already been attended today (by any staff member).
  bool hasAttended(String patientId) {
    if (_attendedPatientIds.contains(patientId)) return true;
    final records = state.valueOrNull;
    if (records == null) return false;
    return records.any((r) => r.patientId == patientId);
  }

  /// Alias for [hasAttended] to make intent explicit at call sites.
  bool isPatientAttended(String patientId) => hasAttended(patientId);

  /// Whether [patientId] was attended today by THIS logged-in staff member.
  bool isAttendedByMe(String patientId) {
    final record = getAttendance(patientId);
    if (record != null) {
      return record.staffId == _staffId;
    }
    return _attendedByMePatientIds.contains(patientId);
  }

  /// Gets the [PatientAttendance] record for [patientId] today, if one exists.
  PatientAttendance? getAttendance(String patientId) {
    final records = state.valueOrNull;
    if (records == null) return null;
    try {
      return records.firstWhere((r) => r.patientId == patientId);
    } catch (_) {
      return null;
    }
  }

  /// Refreshes today's attendance records from the database.
  Future<void> refresh() => _fetch();

  /// Records attendance for [patientId] by the current staff member.
  ///
  /// Only ONE staff member can record attendance per patient per day.
  /// Returns `true` on success, `false` if already attended by anyone today.
  /// Throws on other network/server errors.
  Future<bool> markAttended(String patientId) async {
    // Guard: already attended today or already loading.
    if (hasAttended(patientId) || isLoading(patientId)) return false;

    _loadingPatientIds.add(patientId);
    // Optimistically update local sets for immediate UI response.
    _attendedPatientIds.add(patientId);
    _attendedByMePatientIds.add(patientId);

    if (mounted) state = state; // trigger rebuild

    try {
      await _repository.markAttended(
        patientId: patientId,
        staffId: _staffId,
      );
      // Fetch the full list to ensure timestamps and names are authoritative.
      await _fetch();
      return true;
    } on PostgrestException catch (e) {
      if (e.code == _kDuplicateKeyCode) {
        // Another staff member already marked attendance today (or duplicate tap).
        // Roll back the optimistic "attended by me" marker and refresh from DB.
        _attendedByMePatientIds.remove(patientId);
        await _fetch();
        return false; // signals "already recorded"
      }
      // Non-duplicate error: roll back optimistic state.
      _attendedPatientIds.remove(patientId);
      _attendedByMePatientIds.remove(patientId);
      rethrow;
    } catch (_) {
      _attendedPatientIds.remove(patientId);
      _attendedByMePatientIds.remove(patientId);
      rethrow;
    } finally {
      _loadingPatientIds.remove(patientId);
      if (mounted) state = state;
    }
  }

  // ── Internal ─────────────────────────────────────────────────────────────

  Future<void> _fetch() async {
    final wasData = state is AsyncData;
    if (!wasData) state = const AsyncValue.loading();

    try {
      final records = await _repository.fetchTodayForAllStaff();
      _attendedPatientIds.clear();
      _attendedByMePatientIds.clear();

      for (final r in records) {
        _attendedPatientIds.add(r.patientId);
        if (r.staffId == _staffId) {
          _attendedByMePatientIds.add(r.patientId);
        }
      }
      if (mounted) state = AsyncValue.data(records);
    } catch (error, stackTrace) {
      if (mounted) state = AsyncValue.error(error, stackTrace);
    }
  }
}

