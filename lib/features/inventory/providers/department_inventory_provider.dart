import 'package:flutter_riverpod/flutter_riverpod.dart';

import '../models/department_inventory_item.dart';
import '../models/stock_request_model.dart';
import '../repositories/department_inventory_repository.dart';
import 'inventory_provider.dart';

final departmentInventoryFilterDeptProvider =
    StateProvider<String?>((ref) => null);

final departmentInventorySearchQueryProvider =
    StateProvider<String>((ref) => '');

final departmentInventoryLowStockFilterProvider =
    StateProvider<bool>((ref) => false);

final stockRequestsStatusFilterProvider =
    StateProvider<String>((ref) => 'all');

final stockRequestsSearchQueryProvider =
    StateProvider<String>((ref) => '');

/// Fetches department inventory items for the selected department.
final departmentInventoryItemsProvider =
    FutureProvider.family<List<DepartmentInventoryItem>, String?>((ref, deptId) {
  final repo = ref.watch(departmentInventoryRepositoryProvider);
  final searchQuery = ref.watch(departmentInventorySearchQueryProvider);
  final lowStockOnly = ref.watch(departmentInventoryLowStockFilterProvider);

  return repo.fetchDepartmentInventory(
    departmentId: deptId,
    searchQuery: searchQuery,
    lowStockOnly: lowStockOnly,
  );
});

/// Fetches stock requests with department and status filters.
final stockRequestsListProvider =
    FutureProvider.family<List<StockRequestModel>, String?>((ref, deptId) {
  final repo = ref.watch(departmentInventoryRepositoryProvider);
  final status = ref.watch(stockRequestsStatusFilterProvider);
  final search = ref.watch(stockRequestsSearchQueryProvider);

  return repo.fetchStockRequests(
    departmentId: deptId,
    status: status,
    searchQuery: search,
  );
});

final departmentInventoryControllerProvider =
    StateNotifierProvider<DepartmentInventoryController, AsyncValue<void>>((ref) {
  return DepartmentInventoryController(ref);
});

class DepartmentInventoryController extends StateNotifier<AsyncValue<void>> {
  DepartmentInventoryController(this._ref) : super(const AsyncValue.data(null));

  final Ref _ref;

  DepartmentInventoryRepository get _repo =>
      _ref.read(departmentInventoryRepositoryProvider);

  /// Submits a stock request and atomically transfers stock from central to department.
  /// Replaces the old submit → approve → fulfill workflow.
  Future<void> submitAndTransfer({
    required String inventoryId,
    required double requestedQuantity,
    required String targetDeptId,
    String? notes,
  }) async {
    state = const AsyncValue.loading();
    try {
      await _repo.submitAndTransferStock(
        inventoryId: inventoryId,
        requestedQuantity: requestedQuantity,
        targetDeptId: targetDeptId,
        notes: notes,
      );
      state = const AsyncValue.data(null);
      _invalidateAll();
    } catch (e, st) {
      state = AsyncValue.error(e, st);
      rethrow;
    }
  }

  Future<void> recordConsumption({
    required String departmentId,
    required String inventoryId,
    required double quantity,
    String? patientId,
    String? recordType,
    String? recordId,
    String? remarks,
  }) async {
    state = const AsyncValue.loading();
    try {
      await _repo.recordDepartmentConsumption(
        departmentId: departmentId,
        inventoryId: inventoryId,
        quantity: quantity,
        patientId: patientId,
        recordType: recordType,
        recordId: recordId,
        remarks: remarks,
      );
      state = const AsyncValue.data(null);
      _invalidateAll();
    } catch (e, st) {
      state = AsyncValue.error(e, st);
      rethrow;
    }
  }

  void _invalidateAll() {
    _ref.invalidate(departmentInventoryItemsProvider);
    _ref.invalidate(stockRequestsListProvider);
    // Invalidate central inventory as well because fulfillment transfers central stock
    _ref.invalidate(inventoryProvider);
  }
}
