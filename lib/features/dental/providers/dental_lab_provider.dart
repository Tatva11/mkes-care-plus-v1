import 'package:flutter_riverpod/flutter_riverpod.dart';
import '../models/dental_lab_model.dart';
import '../repositories/dental_lab_repository.dart';

/// Provider for DentalLabRepository.
final dentalLabRepositoryProvider = Provider<DentalLabRepository>((ref) {
  return DentalLabRepository();
});

/// Search query provider for dental lab tracking.
final dentalLabSearchQueryProvider = StateProvider<String>((ref) => '');

/// Status filter provider ('all', 'processing', 'ready', 'delivered').
final dentalLabStatusFilterProvider = StateProvider<String>((ref) => 'all');

/// Notifier managing the list of dental lab cases.
class DentalLabListNotifier extends AsyncNotifier<List<DentalLabModel>> {
  @override
  Future<List<DentalLabModel>> build() async {
    return _fetchCases();
  }

  Future<List<DentalLabModel>> _fetchCases() async {
    final repo = ref.read(dentalLabRepositoryProvider);
    return repo.fetchCases();
  }

  /// Refreshes the list from Supabase.
  Future<void> refresh() async {
    state = const AsyncLoading();
    state = await AsyncValue.guard(() => _fetchCases());
  }

  /// Creates a new dental lab case and updates local state.
  Future<DentalLabModel> createCase({
    required String patientId,
    required String caseNumber,
    required String caseType,
    required DateTime sentDate,
    String? remarks,
  }) async {
    final repo = ref.read(dentalLabRepositoryProvider);
    final created = await repo.createCase(
      patientId: patientId,
      caseNumber: caseNumber,
      caseType: caseType,
      sentDate: sentDate,
      remarks: remarks,
    );

    // Update local state immediately
    state.whenData((currentList) {
      state = AsyncData([created, ...currentList]);
    });

    return created;
  }

  /// Updates an existing dental lab case and updates local state.
  Future<DentalLabModel> updateCase({
    required String id,
    String? caseType,
    DateTime? sentDate,
    DateTime? readyDate,
    DateTime? deliveredDate,
    String? remarks,
  }) async {
    final repo = ref.read(dentalLabRepositoryProvider);
    final updated = await repo.updateCase(
      id: id,
      caseType: caseType,
      sentDate: sentDate,
      readyDate: readyDate,
      deliveredDate: deliveredDate,
      remarks: remarks,
    );

    state.whenData((currentList) {
      state = AsyncData(
        currentList.map((c) => c.id == id ? updated : c).toList(),
      );
    });

    return updated;
  }

  /// Updates the status of a dental lab case and updates local state.
  Future<DentalLabModel> updateStatus({
    required String id,
    required String newStatus,
    DateTime? transitionDate,
  }) async {
    final repo = ref.read(dentalLabRepositoryProvider);
    final updated = await repo.updateStatus(
      id: id,
      newStatus: newStatus,
      transitionDate: transitionDate,
    );

    state.whenData((currentList) {
      state = AsyncData(
        currentList.map((c) => c.id == id ? updated : c).toList(),
      );
    });

    return updated;
  }

  /// Explicitly marks a case as ready and idempotently schedules/links the follow-up appointment.
  Future<DentalLabModel> markReady({
    required String id,
    DateTime? readyDate,
  }) async {
    final repo = ref.read(dentalLabRepositoryProvider);
    final updated = await repo.markCaseReadyWithAppointment(
      id: id,
      readyDate: readyDate,
    );

    state.whenData((currentList) {
      state = AsyncData(
        currentList.map((c) => c.id == id ? updated : c).toList(),
      );
    });

    return updated;
  }

  /// Deletes a dental lab case and removes it from local state.
  Future<void> deleteCase(String id) async {
    final repo = ref.read(dentalLabRepositoryProvider);
    await repo.deleteCase(id);

    state.whenData((currentList) {
      state = AsyncData(currentList.where((c) => c.id != id).toList());
    });
  }
}

/// Provider managing the list of all dental lab cases.
final dentalLabListProvider =
    AsyncNotifierProvider<DentalLabListNotifier, List<DentalLabModel>>(() {
  return DentalLabListNotifier();
});

/// Computes filtered cases based on search query and status filter.
final filteredDentalLabListProvider = Provider<List<DentalLabModel>>((ref) {
  final casesAsync = ref.watch(dentalLabListProvider);
  final cases = casesAsync.valueOrNull ?? [];
  final status = ref.watch(dentalLabStatusFilterProvider).toLowerCase();
  final search = ref.watch(dentalLabSearchQueryProvider).trim().toLowerCase();

  return cases.where((c) {
    // Status check
    if (status != 'all' && c.status.toLowerCase() != status) {
      return false;
    }

    // Search query check
    if (search.isNotEmpty) {
      final caseNum = c.caseNumber.toLowerCase();
      final caseType = c.caseType.toLowerCase();
      final patientName = (c.patientName ?? '').toLowerCase();
      final patientNum = (c.patientNumber ?? '').toLowerCase();
      final remarks = (c.remarks ?? '').toLowerCase();

      final matches = caseNum.contains(search) ||
          caseType.contains(search) ||
          patientName.contains(search) ||
          patientNum.contains(search) ||
          remarks.contains(search);

      if (!matches) return false;
    }

    return true;
  }).toList();
});

/// Summary KPI statistics for the dental lab dashboard.
class DentalLabStats {
  final int total;
  final int processing;
  final int ready;
  final int delivered;

  const DentalLabStats({
    required this.total,
    required this.processing,
    required this.ready,
    required this.delivered,
  });
}

/// Provider computing counts for Total, Processing, Ready, Delivered cases.
final dentalLabStatsProvider = Provider<DentalLabStats>((ref) {
  final casesAsync = ref.watch(dentalLabListProvider);
  final cases = casesAsync.valueOrNull ?? [];

  int processing = 0;
  int ready = 0;
  int delivered = 0;

  for (final c in cases) {
    if (c.isProcessing) {
      processing++;
    } else if (c.isReady) {
      ready++;
    } else if (c.isDelivered) {
      delivered++;
    }
  }

  return DentalLabStats(
    total: cases.length,
    processing: processing,
    ready: ready,
    delivered: delivered,
  );
});

/// Family provider returning dental lab cases for a specific patient.
final patientDentalLabCasesProvider =
    Provider.family<List<DentalLabModel>, String>((ref, patientId) {
  final casesAsync = ref.watch(dentalLabListProvider);
  final cases = casesAsync.valueOrNull ?? [];
  return cases.where((c) => c.patientId == patientId).toList();
});
