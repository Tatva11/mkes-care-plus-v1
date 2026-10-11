import 'package:flutter_riverpod/flutter_riverpod.dart';

import '../models/expired_stock_entry.dart';
import '../models/inventory_batch.dart';
import '../models/inventory_item.dart';
import '../models/inventory_transaction.dart';
import '../repositories/inventory_repository.dart';

/// Notifier managing the full list of inventory items.
class InventoryNotifier extends StateNotifier<AsyncValue<List<InventoryItem>>> {
  final InventoryRepository _repository;

  InventoryNotifier(this._repository) : super(const AsyncValue.loading()) {
    fetchInventory();
  }

  /// Fetches all inventory items from the repository.
  Future<void> fetchInventory() async {
    state = const AsyncValue.loading();
    try {
      final items = await _repository.getInventoryItems();
      state = AsyncValue.data(items);
    } catch (e, st) {
      state = AsyncValue.error(e, st);
    }
  }

  /// Refreshes the inventory list while preserving previous data in background if needed.
  Future<void> refresh() async {
    await fetchInventory();
  }

  /// Creates a new inventory item and updates state.
  Future<InventoryItem> createItem(InventoryItem item) async {
    final created = await _repository.createInventoryItem(item);
    await fetchInventory();
    return created;
  }

  /// Updates an existing inventory item and updates state.
  Future<InventoryItem> updateItem(InventoryItem item) async {
    final updated = await _repository.updateInventoryItem(item);
    await fetchInventory();
    return updated;
  }

  /// Deletes an inventory item by ID and updates state.
  Future<void> deleteItem(String id) async {
    await _repository.deleteInventoryItem(id);
    await fetchInventory();
  }

  /// Performs an atomic Stock In operation and refreshes inventory state.
  Future<InventoryTransaction> stockIn({
    required String itemId,
    required double quantity,
    String? reason,
    String? remarks,
    double? totalAmount,
    String? vendorId,
  }) async {
    final transaction = await _repository.performStockOperation(
      itemId: itemId,
      transactionType: 'stock_in',
      quantity: quantity,
      reason: reason,
      remarks: remarks,
      totalAmount: totalAmount,
      vendorId: vendorId,
    );
    await fetchInventory();
    return transaction;
  }

  /// Performs an atomic Stock Out operation and refreshes inventory state.
  Future<InventoryTransaction> stockOut({
    required String itemId,
    required double quantity,
    String? reason,
    String? remarks,
    String? patientId,
  }) async {
    final transaction = await _repository.performStockOperation(
      itemId: itemId,
      transactionType: 'stock_out',
      quantity: quantity,
      reason: reason,
      remarks: remarks,
      patientId: patientId,
    );
    await fetchInventory();
    return transaction;
  }

  /// Atomically removes expired stock for an item and refreshes inventory state.
  Future<InventoryTransaction> removeExpiredStock({
    required String inventoryId,
    required double quantity,
    String? batchNumber,
    String? remarks,
  }) async {
    final transaction = await _repository.removeExpiredStock(
      inventoryId: inventoryId,
      quantity: quantity,
      batchNumber: batchNumber,
      remarks: remarks,
    );
    await fetchInventory();
    return transaction;
  }
}

/// Provider for the [InventoryNotifier].
final inventoryProvider =
    StateNotifierProvider<InventoryNotifier, AsyncValue<List<InventoryItem>>>(
  (ref) => InventoryNotifier(ref.watch(inventoryRepositoryProvider)),
);

/// Provider fetching all expired stock items and batches.
final expiredStockEntriesProvider = FutureProvider<List<ExpiredStockEntry>>((ref) async {
  ref.watch(inventoryProvider);
  final repo = ref.watch(inventoryRepositoryProvider);
  return repo.getExpiredStockEntries();
});

/// State provider for the active search query.
final inventorySearchQueryProvider = StateProvider<String>((ref) => '');

/// State provider for the active category filter ('All' for everything).
final inventoryCategoryFilterProvider = StateProvider<String>((ref) => 'All');

/// State provider for the active department filter ('All' for everything).
final inventoryDepartmentFilterProvider = StateProvider<String>((ref) => 'All');

/// State provider for status filter ('All', 'Low Stock', 'Expiring Soon', 'Expired').
final inventoryStatusFilterProvider = StateProvider<String>((ref) => 'All');

/// Computed count of items currently in low stock state.
final lowStockCountProvider = Provider<int>((ref) {
  final items = ref.watch(inventoryProvider).value ?? [];
  return items.where((i) => i.isLowStock).length;
});

/// Computed count of items expiring within 30 days.
final expiringSoonCountProvider = Provider<int>((ref) {
  final items = ref.watch(inventoryProvider).value ?? [];
  return items.where((i) => i.expiryStatus == ExpiryStatus.expiringSoon).length;
});

/// Computed count of items that have already expired.
final expiredCountProvider = Provider<int>((ref) {
  final items = ref.watch(inventoryProvider).value ?? [];
  return items.where((i) => i.expiryStatus == ExpiryStatus.expired).length;
});

/// Computed provider that returns unique categories from the loaded items
/// combined with the standard category defaults.
final availableCategoriesProvider = Provider<List<String>>((ref) {
  final itemsAsync = ref.watch(inventoryProvider);
  final Set<String> categories = {...InventoryCategories.defaults};

  itemsAsync.whenData((items) {
    for (final item in items) {
      if (item.category.trim().isNotEmpty) {
        categories.add(item.category.trim());
      }
    }
  });

  final sorted = categories.toList()..sort();
  return ['All', ...sorted];
});

/// Computed provider returning the filtered and searched inventory list.
final filteredInventoryProvider = Provider<List<InventoryItem>>((ref) {
  final itemsState = ref.watch(inventoryProvider);
  final items = itemsState.value ?? [];

  final query = ref.watch(inventorySearchQueryProvider).trim().toLowerCase();
  final category = ref.watch(inventoryCategoryFilterProvider);
  final department = ref.watch(inventoryDepartmentFilterProvider);
  final status = ref.watch(inventoryStatusFilterProvider);

  return items.where((item) {
    // 1. Status Filter (Low Stock, Expiring Soon, Expired)
    if (status == 'Low Stock' && !item.isLowStock) {
      return false;
    }
    if (status == 'Expiring Soon' && item.expiryStatus != ExpiryStatus.expiringSoon) {
      return false;
    }
    if (status == 'Expired' && item.expiryStatus != ExpiryStatus.expired) {
      return false;
    }

    // 2. Category filter
    if (category != 'All' && item.category.toLowerCase() != category.toLowerCase()) {
      return false;
    }

    // 3. Department filter
    if (department != 'All' &&
        (item.department?.toLowerCase() ?? '') != department.toLowerCase()) {
      return false;
    }

    // 4. Search query filter
    if (query.isNotEmpty) {
      final nameMatches = item.name.toLowerCase().contains(query);
      final catMatches = item.category.toLowerCase().contains(query);
      final skuMatches = (item.sku?.toLowerCase() ?? '').contains(query);
      final brandMatches = (item.brand?.toLowerCase() ?? '').contains(query);
      final descMatches = (item.description?.toLowerCase() ?? '').contains(query);

      if (!nameMatches && !catMatches && !skuMatches && !brandMatches && !descMatches) {
        return false;
      }
    }

    return true;
  }).toList();
});

/// Provider for inspecting a single inventory item by ID.
final inventoryItemDetailsProvider =
    FutureProvider.family<InventoryItem, String>((ref, id) async {
  final repository = ref.watch(inventoryRepositoryProvider);
  return repository.getInventoryItem(id);
});

/// Provider for fetching transaction history for a specific inventory item.
final itemTransactionsProvider =
    FutureProvider.family<List<InventoryTransaction>, String>((ref, id) async {
  final repository = ref.watch(inventoryRepositoryProvider);
  return repository.getTransactionHistory(id);
});

/// Provider for fetching active inventory batches for a specific product.
final itemBatchesProvider =
    FutureProvider.family<List<InventoryBatch>, String>((ref, id) async {
  final repository = ref.watch(inventoryRepositoryProvider);
  return repository.getInventoryBatches(id);
});

/// Provider for fetching inventory batches received under a specific Purchase Order.
final poBatchesProvider =
    FutureProvider.family<List<InventoryBatch>, String>((ref, poId) async {
  final repository = ref.watch(inventoryRepositoryProvider);
  return repository.getBatchesForPO(poId);
});

