import 'package:flutter/foundation.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';

import '../models/patient_model.dart';
import '../repositories/patient_repository.dart';

final initialFallbackPatients = [
  PatientModel(
    id: 'f0000000-0000-0000-0000-000000000001',
    patientNumber: 'E1',
    name: 'Sarah Jenkins',
    department: 'eye',
    mobile: '+1 (555) 234-5678',
    createdAt: DateTime.now(),
    updatedAt: DateTime.now(),
  ),
  PatientModel(
    id: 'f0000000-0000-0000-0000-000000000002',
    patientNumber: 'E2',
    name: 'Michael Chen',
    department: 'eye',
    mobile: '+1 (555) 876-5432',
    createdAt: DateTime.now(),
    updatedAt: DateTime.now(),
  ),
  PatientModel(
    id: 'f0000000-0000-0000-0000-000000000003',
    patientNumber: 'E3',
    name: 'Elena Rodriguez',
    department: 'eye',
    mobile: '+1 (555) 345-6789',
    createdAt: DateTime.now(),
    updatedAt: DateTime.now(),
  ),
  PatientModel(
    id: 'f0000000-0000-0000-0000-000000000004',
    patientNumber: 'E4',
    name: 'James Wilson',
    department: 'eye',
    mobile: '+1 (555) 987-6543',
    createdAt: DateTime.now(),
    updatedAt: DateTime.now(),
  ),
  PatientModel(
    id: 'f0000000-0000-0000-0000-000000000005',
    patientNumber: 'D1',
    name: 'Amanda Taylor',
    department: 'dental',
    mobile: '+1 (555) 456-7890',
    createdAt: DateTime.now(),
    updatedAt: DateTime.now(),
  ),
];

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
    try {
      final items = await _repository.fetchPatients(
        department: department,
        searchQuery: search,
      );

      if (items.isNotEmpty) {
        state = AsyncValue.data(items);
      } else {
        state = AsyncValue.data(initialFallbackPatients);
      }
    } catch (e) {
      debugPrint('Error loading patients from Supabase: $e');
      state = AsyncValue.data(initialFallbackPatients);
    }
  }

  Future<PatientModel> createPatient(PatientModel newPatient) async {
    try {
      final created = await _repository.createPatient(newPatient);
      final current = state.value ?? [];
      state = AsyncValue.data([...current, created]);
      return created;
    } catch (e) {
      debugPrint('Error creating patient: $e');
      rethrow;
    }
  }
}
