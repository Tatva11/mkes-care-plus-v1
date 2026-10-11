import 'package:flutter_riverpod/flutter_riverpod.dart';
import '../../inventory/providers/inventory_provider.dart';
import '../models/clinical_inventory_usage_model.dart';
import '../repositories/clinical_inventory_repository.dart';

/// Provider for ClinicalInventoryRepository.
final clinicalInventoryRepositoryProvider =
    Provider<ClinicalInventoryRepository>((ref) {
  return ClinicalInventoryRepository();
});

/// Fetches clinical inventory usage entries for a specific clinical record
/// (e.g. eye_examination or dental_treatment).
final clinicalInventoryUsageForRecordProvider = FutureProvider.family<
    List<ClinicalInventoryUsageModel>,
    ({String recordType, String recordId})>((ref, arg) async {
  final repo = ref.watch(clinicalInventoryRepositoryProvider);
  return repo.fetchUsageForRecord(
    recordType: arg.recordType,
    recordId: arg.recordId,
  );
});

/// Fetches all clinical inventory usage entries for a specific patient.
final clinicalInventoryUsageForPatientProvider = FutureProvider.family<
    List<ClinicalInventoryUsageModel>, String>((ref, patientId) async {
  final repo = ref.watch(clinicalInventoryRepositoryProvider);
  return repo.fetchUsageForPatient(patientId);
});

/// Controller for executing atomic clinical inventory consumption.
class ClinicalInventoryController extends AsyncNotifier<void> {
  @override
  Future<void> build() async {}

  /// Atomically consumes inventory via secure database RPC and refreshes all relevant providers.
  Future<ClinicalInventoryUsageModel> recordConsumption({
    required String patientId,
    required String recordType,
    required String recordId,
    required String inventoryId,
    required double quantity,
    String? remarks,
  }) async {
    state = const AsyncLoading();
    try {
      final repo = ref.read(clinicalInventoryRepositoryProvider);
      final usage = await repo.recordConsumption(
        patientId: patientId,
        recordType: recordType,
        recordId: recordId,
        inventoryId: inventoryId,
        quantity: quantity,
        remarks: remarks,
      );

      // Invalidate record-specific and patient-wide usage providers
      ref.invalidate(clinicalInventoryUsageForRecordProvider((
        recordType: recordType,
        recordId: recordId,
      )));
      ref.invalidate(clinicalInventoryUsageForPatientProvider(patientId));

      // Refresh global inventory provider so stock counts update everywhere
      try {
        await ref.read(inventoryProvider.notifier).refresh();
      } catch (_) {}

      state = const AsyncData(null);
      return usage;
    } catch (e, st) {
      state = AsyncError(e, st);
      rethrow;
    }
  }
}

final clinicalInventoryControllerProvider =
    AsyncNotifierProvider<ClinicalInventoryController, void>(
  ClinicalInventoryController.new,
);
