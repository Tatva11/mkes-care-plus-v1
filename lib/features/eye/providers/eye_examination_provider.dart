import 'package:flutter_riverpod/flutter_riverpod.dart';
import '../models/eye_examination_model.dart';
import '../repositories/eye_examination_repository.dart';

/// Provider for EyeExaminationRepository.
final eyeExaminationRepositoryProvider = Provider<EyeExaminationRepository>((ref) {
  return EyeExaminationRepository();
});

/// Fetches all eye examinations for a specific patient.
final eyeExaminationsForPatientProvider =
    FutureProvider.family<List<EyeExaminationModel>, String>((ref, patientId) async {
  final repo = ref.watch(eyeExaminationRepositoryProvider);
  return repo.fetchExaminations(patientId: patientId);
});

/// Fetches a single eye examination by ID.
final eyeExaminationDetailsProvider =
    FutureProvider.family<EyeExaminationModel?, String>((ref, id) async {
  final repo = ref.watch(eyeExaminationRepositoryProvider);
  return repo.fetchExaminationById(id);
});

/// Controller/Notifier for eye examination operations (create, update, delete).
class EyeExaminationController extends AsyncNotifier<void> {
  @override
  Future<void> build() async {}

  Future<EyeExaminationModel> createExamination(EyeExaminationModel exam) async {
    state = const AsyncLoading();
    try {
      final repo = ref.read(eyeExaminationRepositoryProvider);
      final created = await repo.createExamination(exam);
      ref.invalidate(eyeExaminationsForPatientProvider(exam.patientId));
      state = const AsyncData(null);
      return created;
    } catch (e, st) {
      state = AsyncError(e, st);
      rethrow;
    }
  }

  Future<EyeExaminationModel> updateExamination(EyeExaminationModel exam) async {
    state = const AsyncLoading();
    try {
      final repo = ref.read(eyeExaminationRepositoryProvider);
      final updated = await repo.updateExamination(exam);
      ref.invalidate(eyeExaminationsForPatientProvider(exam.patientId));
      ref.invalidate(eyeExaminationDetailsProvider(exam.id));
      state = const AsyncData(null);
      return updated;
    } catch (e, st) {
      state = AsyncError(e, st);
      rethrow;
    }
  }

  Future<void> deleteExamination({
    required String id,
    required String patientId,
  }) async {
    state = const AsyncLoading();
    try {
      final repo = ref.read(eyeExaminationRepositoryProvider);
      await repo.deleteExamination(id);
      ref.invalidate(eyeExaminationsForPatientProvider(patientId));
      ref.invalidate(eyeExaminationDetailsProvider(id));
      state = const AsyncData(null);
    } catch (e, st) {
      state = AsyncError(e, st);
      rethrow;
    }
  }
}

final eyeExaminationControllerProvider =
    AsyncNotifierProvider<EyeExaminationController, void>(
  EyeExaminationController.new,
);
