import 'package:flutter_riverpod/flutter_riverpod.dart';

import '../../vendors/providers/vendor_provider.dart';
import '../models/purchase_order.dart';
import '../repositories/purchase_order_repository.dart';
import 'inventory_provider.dart';

/// Search query filter for Purchase Orders.
final purchaseOrderSearchQueryProvider = StateProvider<String>((ref) => '');

/// Status filter for Purchase Orders ('All', 'draft', 'ordered', 'partially_received', 'received', 'cancelled').
final purchaseOrderStatusFilterProvider = StateProvider<String>((ref) => 'All');

/// Vendor ID filter for Purchase Orders (null or vendor UUID).
final purchaseOrderVendorFilterProvider = StateProvider<String?>((ref) => null);

/// Main StateNotifier provider managing the list of [PurchaseOrder]s.
final purchaseOrdersProvider =
    StateNotifierProvider<PurchaseOrdersNotifier, AsyncValue<List<PurchaseOrder>>>(
  (ref) => PurchaseOrdersNotifier(
    ref.watch(purchaseOrderRepositoryProvider),
    ref,
  ),
);

class PurchaseOrdersNotifier
    extends StateNotifier<AsyncValue<List<PurchaseOrder>>> {
  PurchaseOrdersNotifier(this._repository, this._ref)
      : super(const AsyncValue.loading()) {
    fetchOrders();
  }

  final PurchaseOrderRepository _repository;
  final Ref _ref;

  Future<void> fetchOrders() async {
    state = const AsyncValue.loading();
    try {
      final orders = await _repository.getPurchaseOrders();
      state = AsyncValue.data(orders);
    } catch (e, st) {
      state = AsyncValue.error(e, st);
    }
  }

  Future<PurchaseOrder> createOrder(
    PurchaseOrder order,
    List<PurchaseOrderItem> items,
  ) async {
    try {
      final created = await _repository.createPurchaseOrder(order, items);
      await fetchOrders();
      return created;
    } catch (e) {
      rethrow;
    }
  }

  Future<PurchaseOrder> updateOrder(
    PurchaseOrder order,
    List<PurchaseOrderItem> items,
  ) async {
    try {
      final updated = await _repository.updatePurchaseOrder(order, items);
      await fetchOrders();
      return updated;
    } catch (e) {
      rethrow;
    }
  }

  Future<void> updateStatus(String id, PurchaseOrderStatus status) async {
    try {
      await _repository.updateStatus(id, status);
      await fetchOrders();
    } catch (e) {
      rethrow;
    }
  }

  Future<void> cancelOrder(String id) async {
    try {
      await _repository.cancelPurchaseOrder(id);
      await fetchOrders();
    } catch (e) {
      rethrow;
    }
  }

  Future<Map<String, dynamic>> receiveOrder({
    required String purchaseOrderId,
    required List<Map<String, dynamic>> items,
  }) async {
    try {
      final result = await _repository.receivePurchaseOrder(
        purchaseOrderId: purchaseOrderId,
        items: items,
      );

      // Refresh orders, inventory, and vendor providers automatically
      await fetchOrders();
      await _ref.read(inventoryProvider.notifier).refresh();
      await _ref.read(vendorsProvider.notifier).fetchVendors();

      return result;
    } catch (e) {
      rethrow;
    }
  }
}

/// Filtered purchase orders based on search query, status filter, and vendor filter.
final filteredPurchaseOrdersProvider = Provider<List<PurchaseOrder>>((ref) {
  final ordersState = ref.watch(purchaseOrdersProvider);
  final searchQuery = ref.watch(purchaseOrderSearchQueryProvider).trim().toLowerCase();
  final statusFilter = ref.watch(purchaseOrderStatusFilterProvider);
  final vendorFilter = ref.watch(purchaseOrderVendorFilterProvider);

  return ordersState.maybeWhen(
    data: (orders) {
      return orders.where((po) {
        // Status filter
        if (statusFilter != 'All') {
          final targetStatus = statusFilter.toLowerCase().replaceAll(' ', '_');
          if (po.status.dbValue != targetStatus) return false;
        }

        // Vendor filter
        if (vendorFilter != null && vendorFilter.isNotEmpty && vendorFilter != 'All') {
          if (po.vendorId != vendorFilter) return false;
        }

        // Search query
        if (searchQuery.isNotEmpty) {
          final numberMatch = po.purchaseOrderNumber.toLowerCase().contains(searchQuery);
          final vendorMatch = po.vendorName?.toLowerCase().contains(searchQuery) ?? false;
          final notesMatch = po.notes?.toLowerCase().contains(searchQuery) ?? false;
          final itemsMatch = po.items.any(
            (i) => i.inventoryName.toLowerCase().contains(searchQuery),
          );
          if (!numberMatch && !vendorMatch && !notesMatch && !itemsMatch) {
            return false;
          }
        }

        return true;
      }).toList();
    },
    orElse: () => [],
  );
});

/// Count of purchase orders currently in Draft status.
final draftPOCountProvider = Provider<int>((ref) {
  final orders = ref.watch(purchaseOrdersProvider).valueOrNull ?? [];
  return orders.where((po) => po.isDraft).length;
});

/// Count of purchase orders currently in Ordered status.
final orderedPOCountProvider = Provider<int>((ref) {
  final orders = ref.watch(purchaseOrdersProvider).valueOrNull ?? [];
  return orders.where((po) => po.isOrdered).length;
});

/// Count of purchase orders currently in Partially Received status.
final partiallyReceivedPOCountProvider = Provider<int>((ref) {
  final orders = ref.watch(purchaseOrdersProvider).valueOrNull ?? [];
  return orders.where((po) => po.isPartiallyReceived).length;
});

/// Count of purchase orders currently in Received status.
final receivedPOCountProvider = Provider<int>((ref) {
  final orders = ref.watch(purchaseOrdersProvider).valueOrNull ?? [];
  return orders.where((po) => po.isReceived).length;
});

/// Provider family for fetching purchase orders by vendor ID.
final vendorPurchaseOrdersProvider =
    FutureProvider.family<List<PurchaseOrder>, String>((ref, vendorId) async {
  final repository = ref.watch(purchaseOrderRepositoryProvider);
  return repository.getVendorPurchaseOrders(vendorId);
});

/// Provider family for fetching purchase orders for a specific inventory product.
final inventoryPurchaseOrdersProvider =
    FutureProvider.family<List<PurchaseOrder>, String>((ref, inventoryId) async {
  final repository = ref.watch(purchaseOrderRepositoryProvider);
  return repository.getInventoryPurchaseOrders(inventoryId);
});
