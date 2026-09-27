import 'package:flutter/foundation.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';

import '../models/patient_model.dart';
import '../repositories/patient_repository.dart';

final patientsProvider =
    StateNotifierProvider<PatientsNotifier, AsyncValue<List<PatientModel>>>(
        (ref) {
  final repository = ref.watch(patientRepositoryProvider);
  return PatientsNotifier(repository);
});

class PatientsNotifier extends StateNotifier<AsyncValue<List<PatientModel>>> {
  final PatientRepository _repository;

  PatientsNotifier(this._repository) : super(const AsyncValue.loading()) {
    loadPatients();
  }

  Future<void> loadPatients({String? department, String? search}) async {
    state = const AsyncValue.loading();
    try {
      final items = await _repository.fetchPatients(
        department: department,
        searchQuery: search,
      );
      state = AsyncValue.data(items);
    } catch (error, stackTrace) {
      debugPrint('Error loading patients from Supabase: $error');
      state = AsyncValue.error(error, stackTrace);
    }
  }

  Future<PatientModel> createPatient(PatientModel newPatient) async {
    try {
      final created = await _repository.createPatient(newPatient);
      await loadPatients();
      return created;
    } catch (e) {
      debugPrint('Error creating patient: $e');
      rethrow;
    }
  }

  Future<PatientModel> updatePatient(PatientModel updatedPatient) async {
    try {
      final updated = await _repository.updatePatient(updatedPatient);
      await loadPatients();
      return updated;
    } catch (e) {
      debugPrint('Error updating patient: $e');
      rethrow;
    }
  }
}

final patientDetailsProvider =
    FutureProvider.family<PatientModel, String>((ref, id) {
  return ref.watch(patientRepositoryProvider).getPatient(id);
});

final patientSearchProvider = FutureProvider.family<List<PatientModel>,
    ({String department, String query})>((ref, params) {
  return ref.watch(patientRepositoryProvider).fetchPatients(
        department: params.department,
        searchQuery: params.query,
      );
});

final patientsByDepartmentProvider =
    FutureProvider.family<List<PatientModel>, String>((ref, department) {
  if (department != 'eye' && department != 'dental') {
    throw ArgumentError.value(department, 'department', 'Must be eye or dental.');
  }

  return ref
      .watch(patientRepositoryProvider)
      .fetchPatients(department: department)
      .then((patients) => patients
          .where((patient) => patient.department == department)
          .toList());
});

