import 'package:flutter_riverpod/flutter_riverpod.dart';
import '../models/dental_treatment_model.dart';
import '../repositories/dental_treatment_repository.dart';

/// Provider for DentalTreatmentRepository.
final dentalTreatmentRepositoryProvider =
    Provider<DentalTreatmentRepository>((ref) {
  return DentalTreatmentRepository();
});

/// Fetches dental treatment records for a specific patient.
final dentalTreatmentsForPatientProvider =
    FutureProvider.family<List<DentalTreatmentModel>, String>(
        (ref, patientId) async {
  final repo = ref.watch(dentalTreatmentRepositoryProvider);
  return repo.fetchTreatments(patientId: patientId);
});

/// Fetches a single dental treatment by ID.
final dentalTreatmentDetailsProvider =
    FutureProvider.family<DentalTreatmentModel?, String>((ref, id) async {
  final repo = ref.watch(dentalTreatmentRepositoryProvider);
  return repo.fetchTreatmentById(id);
});

/// Controller for creating, updating, and deleting dental treatment records.
class DentalTreatmentController extends AsyncNotifier<void> {
  @override
  Future<void> build() async {}

  Future<DentalTreatmentModel> createTreatment(
    DentalTreatmentModel treatment,
  ) async {
    state = const AsyncLoading();
    try {
      final repo = ref.read(dentalTreatmentRepositoryProvider);
      final created = await repo.createTreatment(treatment);
      ref.invalidate(dentalTreatmentsForPatientProvider(treatment.patientId));
      state = const AsyncData(null);
      return created;
    } catch (e, st) {
      state = AsyncError(e, st);
      rethrow;
    }
  }

  Future<DentalTreatmentModel> updateTreatment(
    DentalTreatmentModel treatment,
  ) async {
    state = const AsyncLoading();
    try {
      final repo = ref.read(dentalTreatmentRepositoryProvider);
      final updated = await repo.updateTreatment(treatment);
      ref.invalidate(dentalTreatmentsForPatientProvider(treatment.patientId));
      ref.invalidate(dentalTreatmentDetailsProvider(treatment.id));
      state = const AsyncData(null);
      return updated;
    } catch (e, st) {
      state = AsyncError(e, st);
      rethrow;
    }
  }

  Future<void> deleteTreatment({
    required String id,
    required String patientId,
  }) async {
    state = const AsyncLoading();
    try {
      final repo = ref.read(dentalTreatmentRepositoryProvider);
      await repo.deleteTreatment(id);
      ref.invalidate(dentalTreatmentsForPatientProvider(patientId));
      ref.invalidate(dentalTreatmentDetailsProvider(id));
      state = const AsyncData(null);
    } catch (e, st) {
      state = AsyncError(e, st);
      rethrow;
    }
  }
}

final dentalTreatmentControllerProvider =
    AsyncNotifierProvider<DentalTreatmentController, void>(
  DentalTreatmentController.new,
);
