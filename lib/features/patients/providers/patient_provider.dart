import 'package:flutter_riverpod/flutter_riverpod.dart';

import '../models/patient.dart';
import '../repositories/patient_repository.dart';

final patientsProvider =
    StateNotifierProvider<PatientsNotifier, AsyncValue<List<Patient>>>((ref) {
  return PatientsNotifier(ref.watch(patientRepositoryProvider));
});

class PatientsNotifier extends StateNotifier<AsyncValue<List<Patient>>> {
  final PatientRepository _repository;
  String _search = '';

  PatientsNotifier(this._repository) : super(const AsyncValue.loading()) {
    fetchPatients();
  }

  Future<void> fetchPatients() async {
    state = const AsyncValue.loading();
    try {
      state =
          AsyncValue.data(await _repository.fetchPatients(search: _search));
    } catch (error, stackTrace) {
      state = AsyncValue.error(error, stackTrace);
    }
  }

  Future<void> search(String value) async {
    _search = value;
    await fetchPatients();
  }

  Future<void> createPatient({
    required String fullName,
    required String mobile,
    required String department,
    DateTime? dateOfBirth,
    String? address,
    String? reference,
  }) async {
    if (fullName.trim().isEmpty) throw ArgumentError('Full name is required.');
    if (mobile.trim().isEmpty) throw ArgumentError('Phone number is required.');
    if (department.trim().isEmpty) {
      throw ArgumentError('Department is required.');
    }
    await _repository.createPatient(
      fullName: fullName,
      mobile: mobile,
      department: department,
      dateOfBirth: dateOfBirth,
      address: address,
      reference: reference,
    );
    await fetchPatients();
  }

  Future<void> updatePatient({
    required String id,
    required String fullName,
    required String mobile,
    required String department,
    DateTime? dateOfBirth,
    String? address,
    String? reference,
  }) async {
    await _repository.updatePatient(
      id: id,
      fullName: fullName,
      mobile: mobile,
      department: department,
      dateOfBirth: dateOfBirth,
      address: address,
      reference: reference,
    );
    await fetchPatients();
  }
}

final patientDetailsProvider =
    FutureProvider.family<Patient, String>((ref, id) {
  return ref.watch(patientRepositoryProvider).getPatient(id);
});
