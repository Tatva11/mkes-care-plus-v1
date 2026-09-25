import 'package:flutter_riverpod/flutter_riverpod.dart';

import '../models/patient_attendance.dart';
import '../repositories/patient_attendance_repository.dart';

final staffPatientAttendanceProvider = StateNotifierProvider.family<StaffPatientAttendanceNotifier, AsyncValue<List<PatientAttendance>>, String>((ref, staffId) {
  return StaffPatientAttendanceNotifier(ref.watch(patientAttendanceRepositoryProvider), staffId);
});

final adminPatientAttendanceProvider = FutureProvider<List<PatientAttendance>>((ref) {
  return ref.watch(patientAttendanceRepositoryProvider).fetchForAdmin(DateTime.now());
});

final patientAttendanceHistoryProvider = FutureProvider.family<List<PatientAttendance>, String>((ref, patientId) {
  return ref.watch(patientAttendanceRepositoryProvider).fetchForPatient(patientId);
});

class StaffPatientAttendanceNotifier extends StateNotifier<AsyncValue<List<PatientAttendance>>> {
  final PatientAttendanceRepository _repository;
  final String _staffId;

  StaffPatientAttendanceNotifier(this._repository, this._staffId) : super(const AsyncValue.loading()) {
    fetch(DateTime.now());
  }

  Future<void> fetch(DateTime date) async {
    state = const AsyncValue.loading();
    try {
      state = AsyncValue.data(await _repository.fetchForStaff(_staffId, date));
    } catch (error, stackTrace) {
      state = AsyncValue.error(error, stackTrace);
    }
  }

  Future<void> markAttended(String patientId) async {
    await _repository.markAttended(patientId: patientId, staffId: _staffId);
    await fetch(DateTime.now());
  }
}
