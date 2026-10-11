import 'package:flutter_riverpod/flutter_riverpod.dart';

import '../../patients/models/patient_model.dart';
import '../../patients/repositories/patient_repository.dart';
import '../models/eye_surgery_model.dart';
import '../models/eye_surgery_item_model.dart';
import '../repositories/eye_surgery_repository.dart';

final eyeSurgeryRepositoryProvider = Provider<EyeSurgeryRepository>((ref) {
  return EyeSurgeryRepository();
});

final eyeSurgerySearchQueryProvider = StateProvider<String>((ref) => '');
final eyeSurgeryStatusFilterProvider = StateProvider<String>((ref) => 'all');
final eyeSurgerySelectedDateProvider = StateProvider<DateTime>((ref) {
  final now = DateTime.now();
  return DateTime(now.year, now.month, now.day);
});

class EyeSurgeryListNotifier extends AsyncNotifier<List<EyeSurgeryModel>> {
  @override
  Future<List<EyeSurgeryModel>> build() {
    return ref.read(eyeSurgeryRepositoryProvider).fetchSurgeries();
  }

  Future<void> refresh() async {
    state = const AsyncLoading();
    state = await AsyncValue.guard(
      () => ref.read(eyeSurgeryRepositoryProvider).fetchSurgeries(),
    );
  }

  Future<void> deleteSurgery(String id) async {
    await ref.read(eyeSurgeryRepositoryProvider).deleteSurgery(id);
    final current = state.valueOrNull;
    if (current != null) {
      state = AsyncData(current.where((item) => item.id != id).toList());
    } else {
      await refresh();
    }
  }

  Future<EyeSurgeryModel> createSurgery({
    required String patientId,
    required String surgeryType,
    required String surgeryTypeCategory,
    String? customSurgeryType,
    required String eyeSide,
    required DateTime? surgeryDate,
    String? assignedStaffId,
    String? surgeryTime,
    Map<String, bool> preOpChecklist = const {},
    String? iolDetails,
    String? remarks,
    List<({String inventoryItemId, double plannedQuantity, String source})>? initialItems,
  }) async {
    final surgery = await ref.read(eyeSurgeryRepositoryProvider).createSurgery(
          patientId: patientId,
          surgeryType: surgeryType,
          surgeryTypeCategory: surgeryTypeCategory,
          customSurgeryType: customSurgeryType,
          eyeSide: eyeSide,
          surgeryDate: surgeryDate,
          assignedStaffId: assignedStaffId,
          surgeryTime: surgeryTime,
          preOpChecklist: preOpChecklist,
          iolDetails: iolDetails,
          remarks: remarks,
          initialItems: initialItems,
        );
    await _upsert(surgery);
    return surgery;
  }

  Future<EyeSurgeryModel> updateSurgery(EyeSurgeryModel surgery) async {
    final updated =
        await ref.read(eyeSurgeryRepositoryProvider).updateSurgery(surgery);
    await _upsert(updated);
    return updated;
  }

  Future<EyeSurgeryModel> updateStatus(String id, String status) async {
    final updated =
        await ref.read(eyeSurgeryRepositoryProvider).updateStatus(id, status);
    await _upsert(updated);
    return updated;
  }

  Future<EyeSurgeryModel> startSurgery(String id) async {
    final current =
        state.valueOrNull?.where((item) => item.id == id).firstOrNull;
    if (current != null && !current.isPreOpChecklistComplete) {
      throw StateError(
        'Complete the pre-op checklist before entering surgery.',
      );
    }
    final updated =
        await ref.read(eyeSurgeryRepositoryProvider).startSurgery(id);
    await _upsert(updated);
    return updated;
  }

  Future<EyeSurgeryModel> updateChecklist(
    String id,
    Map<String, bool> checklist,
  ) async {
    final updated = await ref
        .read(eyeSurgeryRepositoryProvider)
        .updatePreOpChecklist(id, checklist);
    await _upsert(updated);
    return updated;
  }

  Future<EyeSurgeryModel> updateDetails({
    required String id,
    String? iolDetails,
    String? remarks,
  }) async {
    final updated =
        await ref.read(eyeSurgeryRepositoryProvider).updateSurgeryDetails(
              id: id,
              iolDetails: iolDetails,
              remarks: remarks,
            );
    await _upsert(updated);
    return updated;
  }

  Future<EyeSurgeryModel> assignStaff(
    String id,
    String? assignedStaffId,
  ) async {
    final updated = await ref
        .read(eyeSurgeryRepositoryProvider)
        .assignStaff(id, assignedStaffId);
    await _upsert(updated);
    return updated;
  }

  Future<EyeSurgeryModel> linkFollowUpAppointment(
    String id,
    String appointmentId,
  ) async {
    final updated = await ref
        .read(eyeSurgeryRepositoryProvider)
        .linkFollowUpAppointment(id, appointmentId);
    await _upsert(updated);
    return updated;
  }

  Future<EyeSurgeryModel> rescheduleSurgery({
    required String id,
    required DateTime surgeryDate,
    String? surgeryTime,
  }) async {
    final updated = await ref
        .read(eyeSurgeryRepositoryProvider)
        .rescheduleSurgery(
          id: id,
          surgeryDate: surgeryDate,
          surgeryTime: surgeryTime,
        );
    await _upsert(updated);
    return updated;
  }

  Future<void> _upsert(EyeSurgeryModel updated) async {
    final current = state.valueOrNull;
    if (current == null) {
      await refresh();
      return;
    }
    final exists = current.any((item) => item.id == updated.id);
    final next = exists
        ? current.map((item) => item.id == updated.id ? updated : item).toList()
        : [updated, ...current];
    next.sort((a, b) {
      final dateComp = a.surgeryDate.compareTo(b.surgeryDate);
      if (dateComp != 0) return dateComp;
      final aMin = _extractSurgeryTimeMinutes(a.surgeryTime);
      final bMin = _extractSurgeryTimeMinutes(b.surgeryTime);
      final timeComp = aMin.compareTo(bMin);
      if (timeComp != 0) return timeComp;
      final createdComp = a.createdAt.compareTo(b.createdAt);
      if (createdComp != 0) return createdComp;
      return a.id.compareTo(b.id);
    });
    state = AsyncData(next);
  }
}

final eyeSurgeryListProvider =
    AsyncNotifierProvider<EyeSurgeryListNotifier, List<EyeSurgeryModel>>(
  EyeSurgeryListNotifier.new,
);

final filteredEyeSurgeriesProvider = Provider<List<EyeSurgeryModel>>((ref) {
  final surgeries = ref.watch(eyeSurgeryListProvider).valueOrNull ?? const [];
  final selectedDate = ref.watch(eyeSurgerySelectedDateProvider);
  final status = ref.watch(eyeSurgeryStatusFilterProvider);
  final query = ref.watch(eyeSurgerySearchQueryProvider).trim().toLowerCase();
  final list = surgeries.where((surgery) {
    if (!surgery.isDischargedVisible()) {
      return false;
    }
    if (!EyeSurgeryModel.isSameCalendarDay(surgery.surgeryDate, selectedDate)) {
      return false;
    }
    if (status == 'missed') {
      if (!surgery.isMissed) return false;
    } else if (status == 'in_progress') {
      final s = surgery.status.toLowerCase();
      final isInProgress = !surgery.isMissed &&
          (s == 'in_surgery' ||
              s == 'pre_op' ||
              s == 'post_op' ||
              s == 'in_progress');
      if (!isInProgress) return false;
    } else if (status != 'all' && surgery.status != status) {
      return false;
    }
    if (query.isEmpty) return true;
    return surgery.surgeryType.toLowerCase().contains(query) ||
        (surgery.patientName ?? '').toLowerCase().contains(query) ||
        (surgery.patientNumber ?? '').toLowerCase().contains(query) ||
        (surgery.assignedStaffName ?? '').toLowerCase().contains(query) ||
        surgery.eyeSide.toLowerCase().contains(query);
  }).toList();

  list.sort((a, b) {
    final aMin = _extractSurgeryTimeMinutes(a.surgeryTime);
    final bMin = _extractSurgeryTimeMinutes(b.surgeryTime);
    final timeComp = aMin.compareTo(bMin);
    if (timeComp != 0) return timeComp;
    final createdComp = a.createdAt.compareTo(b.createdAt);
    if (createdComp != 0) return createdComp;
    return a.id.compareTo(b.id);
  });

  return list;
});

/// Summary KPI statistics for the Eye Surgery screen.
class EyeSurgeryStats {
  final int total;
  final int scheduled;
  final int inProgress;
  final int discharged;

  const EyeSurgeryStats({
    required this.total,
    required this.scheduled,
    required this.inProgress,
    required this.discharged,
  });
}

/// Provider computing date-wise Eye Surgery summary stats.
final eyeSurgeryStatsProvider = Provider<EyeSurgeryStats>((ref) {
  final surgeries = ref.watch(eyeSurgeryListProvider).valueOrNull ?? const [];
  final selectedDate = ref.watch(eyeSurgerySelectedDateProvider);

  final daySurgeries = surgeries.where((s) {
    return EyeSurgeryModel.isSameCalendarDay(s.surgeryDate, selectedDate);
  }).toList();

  int scheduled = 0;
  int inProgress = 0;
  int discharged = 0;

  for (final s in daySurgeries) {
    if (s.status == 'discharged') {
      discharged++;
    } else if (s.status == 'in_surgery' ||
        s.status == 'post_op' ||
        s.status == 'in_progress' ||
        (s.status == 'pre_op' && !s.isMissed)) {
      inProgress++;
    } else if (s.status == 'scheduled' && !s.isMissed) {
      scheduled++;
    }
  }

  return EyeSurgeryStats(
    total: daySurgeries.length,
    scheduled: scheduled,
    inProgress: inProgress,
    discharged: discharged,
  );
});

int _extractSurgeryTimeMinutes(String? timeStr) {
  if (timeStr == null || timeStr.trim().isEmpty) return 999999;
  final parsed = EyeSurgeryModel.parseTimeString(timeStr);
  if (parsed == null) return 999999;
  return parsed.hour * 60 + parsed.minute;
}

final eyeSurgeriesForPatientProvider =
    FutureProvider.family<List<EyeSurgeryModel>, String>((ref, patientId) {
  return ref
      .watch(eyeSurgeryRepositoryProvider)
      .fetchSurgeriesForPatient(patientId);
});

final eyeSurgeryItemsProvider = AsyncNotifierProvider.family<
    EyeSurgeryItemsNotifier,
    List<EyeSurgeryItemModel>,
    String>(EyeSurgeryItemsNotifier.new);

class EyeSurgeryItemsNotifier
    extends FamilyAsyncNotifier<List<EyeSurgeryItemModel>, String> {
  @override
  Future<List<EyeSurgeryItemModel>> build(String surgeryId) {
    return ref.read(eyeSurgeryRepositoryProvider).fetchSurgeryItems(surgeryId);
  }

  Future<void> addItem({
    required String inventoryItemId,
    required double plannedQuantity,
    double? actualQuantity,
    String source = 'manual',
  }) async {
    final item = await ref.read(eyeSurgeryRepositoryProvider).addSurgeryItem(
          surgeryId: arg,
          inventoryItemId: inventoryItemId,
          plannedQuantity: plannedQuantity,
          actualQuantity: actualQuantity,
          source: source,
        );
    final current = state.valueOrNull ?? const <EyeSurgeryItemModel>[];
    state = AsyncData([...current, item]);
  }

  Future<void> addItems(List<({String inventoryItemId, double plannedQuantity, String source})> items) async {
    final repo = ref.read(eyeSurgeryRepositoryProvider);
    final newItems = <EyeSurgeryItemModel>[];
    for (final entry in items) {
      final added = await repo.addSurgeryItem(
        surgeryId: arg,
        inventoryItemId: entry.inventoryItemId,
        plannedQuantity: entry.plannedQuantity,
        source: entry.source,
      );
      newItems.add(added);
    }
    final current = state.valueOrNull ?? const <EyeSurgeryItemModel>[];
    state = AsyncData([...current, ...newItems]);
  }

  Future<void> updateItem({
    required String itemId,
    required double plannedQuantity,
    required double actualQuantity,
  }) async {
    final item = await ref.read(eyeSurgeryRepositoryProvider).updateSurgeryItem(
          itemId: itemId,
          plannedQuantity: plannedQuantity,
          actualQuantity: actualQuantity,
        );
    final current = state.valueOrNull ?? const <EyeSurgeryItemModel>[];
    state = AsyncData(
        current.map((old) => old.id == item.id ? item : old).toList());
  }

  Future<void> removeItem(String itemId) async {
    await ref.read(eyeSurgeryRepositoryProvider).removeSurgeryItem(itemId);
    final current = state.valueOrNull ?? const <EyeSurgeryItemModel>[];
    state = AsyncData(current.where((item) => item.id != itemId).toList());
  }
}

final eyeSurgeryItemTemplatesProvider =
    FutureProvider.family<List<EyeSurgeryItemTemplateModel>, String>(
        (ref, surgeryType) {
  return ref
      .watch(eyeSurgeryRepositoryProvider)
      .fetchItemTemplates(surgeryType);
});

final allEyeSurgeryItemTemplatesProvider =
    FutureProvider<List<EyeSurgeryItemTemplateModel>>((ref) {
  return ref.watch(eyeSurgeryRepositoryProvider).fetchAllItemTemplates();
});

final eyeSurgeryPatientSearchProvider =
    FutureProvider.family<List<PatientModel>, String>(
  (ref, query) => ref.read(patientRepositoryProvider).fetchPatients(
        department: 'eye',
        searchQuery: query,
      ),
);

final eyeSurgeryStaffCandidatesProvider =
    FutureProvider<List<EyeSurgeryStaffCandidate>>((ref) async {
  final candidates =
      await ref.watch(eyeSurgeryRepositoryProvider).fetchStaffCandidates();
  return uniqueEyeSurgeryStaffCandidates(candidates);
});
