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
// Per-patient history provider — used by PatientDetailsScreen.
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

  /// Patient IDs that this staff member has already attended today (locally
  /// tracked so the UI reacts instantly after a successful insert).
  final Set<String> _attendedPatientIds = {};

  StaffPatientAttendanceNotifier(this._repository, this._staffId)
      : super(const AsyncValue.loading()) {
    _fetch(DateTime.now());
  }

  // ── Public API ────────────────────────────────────────────────────────────

  /// Whether an insert is currently in-flight for [patientId].
  bool isLoading(String patientId) => _loadingPatientIds.contains(patientId);

  /// Whether this staff has recorded attendance for [patientId] today.
  /// Derived from the fetched list so it survives provider re-creation.
  bool hasAttended(String patientId) {
    // Check the in-memory set (optimistic) first.
    if (_attendedPatientIds.contains(patientId)) return true;
    // Fall back to the fetched state.
    final records = state.valueOrNull;
    if (records == null) return false;
    return records.any((r) => r.patientId == patientId);
  }

  /// Records attendance for [patientId] by the current staff member.
  ///
  /// Returns `true` on success, `false` if already recorded (duplicate).
  /// Throws on other network/server errors.
  Future<bool> markAttended(String patientId) async {
    // Guard: already attended or already loading.
    if (hasAttended(patientId) || isLoading(patientId)) return false;

    _loadingPatientIds.add(patientId);
    // Notify listeners that loading state changed (state value unchanged).
    if (mounted) state = state; // trigger rebuild via same value trick

    try {
      await _repository.markAttended(
        patientId: patientId,
        staffId: _staffId,
      );
      // Optimistic update — mark attended immediately.
      _attendedPatientIds.add(patientId);
      // Refresh the full list in the background.
      await _fetch(DateTime.now());
      return true;
    } on PostgrestException catch (e) {
      if (e.code == _kDuplicateKeyCode) {
        // Already attended by this staff today — treat as success.
        _attendedPatientIds.add(patientId);
        if (mounted) state = state;
        return false; // signals "already recorded"
      }
      rethrow;
    } finally {
      _loadingPatientIds.remove(patientId);
      if (mounted) state = state;
    }
  }

  // ── Internal ─────────────────────────────────────────────────────────────

  Future<void> _fetch(DateTime date) async {
    // Don't reset to loading while individual buttons are in-flight —
    // that would hide the per-patient spinner state.
    final wasData = state is AsyncData;
    if (!wasData) state = const AsyncValue.loading();

    try {
      final records = await _repository.fetchForStaff(_staffId, date);
      // Sync the attended set from the fetched records.
      for (final r in records) {
        _attendedPatientIds.add(r.patientId);
      }
      if (mounted) state = AsyncValue.data(records);
    } catch (error, stackTrace) {
      if (mounted) state = AsyncValue.error(error, stackTrace);
    }
  }
}
