import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:flutter_test/flutter_test.dart';

import 'package:mkes_care/features/auth/providers/auth_provider.dart';
import 'package:mkes_care/features/inventory/models/inventory_item.dart';
import 'package:mkes_care/features/inventory/models/inventory_transaction.dart';
import 'package:mkes_care/features/inventory/models/purchase_order.dart';
import 'package:mkes_care/features/inventory/repositories/inventory_repository.dart';
import 'package:mkes_care/features/inventory/repositories/purchase_order_repository.dart';
import 'package:mkes_care/features/inventory/screens/purchase_order_list_screen.dart';
import 'package:mkes_care/features/inventory/widgets/purchase_order_details_dialog.dart';
import 'package:mkes_care/features/inventory/widgets/purchase_order_form_dialog.dart';
import 'package:mkes_care/features/inventory/widgets/receive_purchase_order_dialog.dart';
import 'package:mkes_care/features/vendors/models/vendor.dart';
import 'package:mkes_care/features/vendors/repositories/vendor_repository.dart';
import 'package:mkes_care/features/vendors/widgets/vendor_details_dialog.dart';

// ============================================================================
// FAKES & SIMULATIONS
// ============================================================================

class FakeInventoryRepoForPO implements InventoryRepository {
  final List<InventoryItem> items;
  final List<InventoryTransaction> transactions = [];

  FakeInventoryRepoForPO([List<InventoryItem>? initial])
      : items = initial != null ? List.from(initial) : [];

  @override
  Future<List<InventoryItem>> getInventoryItems({
    String? category,
    String? department,
    String? searchQuery,
    bool? activeOnly,
  }) async {
    return List.from(items);
  }

  @override
  Future<InventoryItem> getInventoryItem(String id) async {
    return items.firstWhere((i) => i.id == id);
  }

  @override
  Future<InventoryItem> createInventoryItem(InventoryItem item) async {
    items.add(item);
    return item;
  }

  @override
  Future<InventoryItem> updateInventoryItem(InventoryItem item) async {
    final idx = items.indexWhere((i) => i.id == item.id);
    if (idx != -1) items[idx] = item;
    return item;
  }

  @override
  Future<void> deleteInventoryItem(String id) async {
    items.removeWhere((i) => i.id == id);
  }

  @override
  Future<InventoryTransaction> performStockOperation({
    required String itemId,
    required String transactionType,
    required double quantity,
    String? reason,
    String? remarks,
    String? patientId,
    double? totalAmount,
    String? vendorId,
  }) async {
    final idx = items.indexWhere((i) => i.id == itemId);
    final current = items[idx];
    final before = current.currentStock;
    final after = transactionType == 'stock_in' ? before + quantity : before - quantity;
    final updated = current.copyWith(
      currentStock: after,
      vendorId: vendorId ?? current.vendorId,
      lastQuantitySupplied: quantity,
      lastTotalAmount: totalAmount,
    );
    items[idx] = updated;

    final tx = InventoryTransaction(
      id: 'tx-${transactions.length + 1}',
      inventoryItemId: itemId,
      transactionType: transactionType,
      quantity: quantity,
      stockBefore: before,
      stockAfter: after,
      reason: reason,
      remarks: remarks,
      vendorId: vendorId,
      totalAmount: totalAmount,
      createdAt: DateTime.now(),
    );
    transactions.add(tx);
    return tx;
  }

  @override
  Future<List<InventoryTransaction>> getTransactionHistory(
    String itemId, {
    String? transactionType,
    int limit = 50,
  }) async {
    return transactions.where((t) => t.inventoryItemId == itemId).toList();
  }

  @override
  Future<List<InventoryTransaction>> getAllTransactions({
    String? transactionType,
    int limit = 100,
  }) async {
    return List.from(transactions);
  }
}

class FakeVendorRepoForPO implements VendorRepository {
  final List<Vendor> vendors;

  FakeVendorRepoForPO([List<Vendor>? initial])
      : vendors = initial != null ? List.from(initial) : [];

  @override
  Future<List<Vendor>> getVendors({String? searchQuery, bool? activeOnly}) async {
    return List.from(vendors);
  }

  @override
  Future<Vendor> getVendor(String id) async {
    return vendors.firstWhere((v) => v.id == id);
  }

  @override
  Future<Vendor> createVendor(Vendor vendor) async {
    vendors.add(vendor);
    return vendor;
  }

  @override
  Future<Vendor> updateVendor(Vendor vendor) async {
    final idx = vendors.indexWhere((v) => v.id == vendor.id);
    if (idx != -1) vendors[idx] = vendor;
    return vendor;
  }

  @override
  Future<void> deleteVendor(String id) async {
    vendors.removeWhere((v) => v.id == id);
  }

  @override
  Future<Vendor> toggleVendorStatus(String id, bool isActive) async {
    final idx = vendors.indexWhere((v) => v.id == id);
    final updated = vendors[idx].copyWith(isActive: isActive);
    vendors[idx] = updated;
    return updated;
  }
}

class FakePurchaseOrderRepository implements PurchaseOrderRepository {
  final List<PurchaseOrder> orders;
  final FakeInventoryRepoForPO inventoryRepo;
  final FakeVendorRepoForPO vendorRepo;
  String? callerRole; // 'admin' or 'staff' or other

  FakePurchaseOrderRepository({
    List<PurchaseOrder>? initial,
    required this.inventoryRepo,
    required this.vendorRepo,
    this.callerRole = 'admin',
  }) : orders = initial != null ? List.from(initial) : [];

  void _checkPermission() {
    if (callerRole != 'admin' && callerRole != 'staff') {
      throw Exception('row-level security policy blocks access for role $callerRole');
    }
  }

  @override
  Future<List<PurchaseOrder>> getPurchaseOrders({
    String? status,
    String? vendorId,
    String? searchQuery,
  }) async {
    var result = List<PurchaseOrder>.from(orders);
    if (status != null && status.isNotEmpty && status.toLowerCase() != 'all') {
      final s = PurchaseOrderStatus.fromString(status);
      result = result.where((o) => o.status == s).toList();
    }
    if (vendorId != null && vendorId.isNotEmpty && vendorId.toLowerCase() != 'all') {
      result = result.where((o) => o.vendorId == vendorId).toList();
    }
    if (searchQuery != null && searchQuery.trim().isNotEmpty) {
      final q = searchQuery.trim().toLowerCase();
      result = result.where((o) {
        return o.purchaseOrderNumber.toLowerCase().contains(q) ||
            (o.vendorName?.toLowerCase().contains(q) ?? false) ||
            o.items.any((i) => i.inventoryName.toLowerCase().contains(q));
      }).toList();
    }
    return result;
  }

  @override
  Future<PurchaseOrder> getPurchaseOrder(String id) async {
    return orders.firstWhere((o) => o.id == id);
  }

  @override
  Future<PurchaseOrder> createPurchaseOrder(
    PurchaseOrder order,
    List<PurchaseOrderItem> items,
  ) async {
    _checkPermission();
    if (!order.hasValidDates) {
      throw Exception('Expected delivery date cannot be before the order date.');
    }
    final id = order.id.isNotEmpty ? order.id : 'po-${orders.length + 1}';
    final total = items.fold(0.0, (sum, i) => sum + i.totalAmount);
    final poItems = items.map((i) {
      return i.copyWith(
        id: i.id.isNotEmpty ? i.id : 'item-${orders.length + 1}-${i.inventoryId}',
        purchaseOrderId: id,
      );
    }).toList();

    final created = order.copyWith(
      id: id,
      subtotal: total,
      totalAmount: total,
      items: poItems,
      createdAt: DateTime.now(),
      updatedAt: DateTime.now(),
    );
    orders.insert(0, created);
    return created;
  }

  @override
  Future<PurchaseOrder> updatePurchaseOrder(
    PurchaseOrder order,
    List<PurchaseOrderItem> items,
  ) async {
    _checkPermission();
    if (!order.hasValidDates) {
      throw Exception('Expected delivery date cannot be before the order date.');
    }
    final idx = orders.indexWhere((o) => o.id == order.id);
    if (idx == -1) throw Exception('Purchase order not found');

    final total = items.fold(0.0, (sum, i) => sum + i.totalAmount);
    final updated = order.copyWith(
      subtotal: total,
      totalAmount: total,
      items: items,
      updatedAt: DateTime.now(),
    );
    orders[idx] = updated;
    return updated;
  }

  @override
  Future<void> updateStatus(String id, PurchaseOrderStatus status) async {
    _checkPermission();
    final idx = orders.indexWhere((o) => o.id == id);
    if (idx != -1) {
      orders[idx] = orders[idx].copyWith(status: status, updatedAt: DateTime.now());
    }
  }

  @override
  Future<void> cancelPurchaseOrder(String id) async {
    _checkPermission();
    final idx = orders.indexWhere((o) => o.id == id);
    if (idx == -1) throw Exception('Purchase order not found');
    final po = orders[idx];
    if (!po.canCancel) {
      throw Exception('Cannot cancel purchase order with status "${po.status.label}".');
    }
    orders[idx] = po.copyWith(status: PurchaseOrderStatus.cancelled, updatedAt: DateTime.now());
  }

  @override
  Future<Map<String, dynamic>> receivePurchaseOrder({
    required String purchaseOrderId,
    required List<Map<String, dynamic>> items,
  }) async {
    _checkPermission();
    final idx = orders.indexWhere((o) => o.id == purchaseOrderId);
    if (idx == -1) throw Exception('Purchase order not found');

    final po = orders[idx];
    if (po.status == PurchaseOrderStatus.draft) {
      throw Exception('Cannot receive a draft purchase order. Please mark it as Ordered first.');
    }
    if (po.status == PurchaseOrderStatus.cancelled) {
      throw Exception('Cannot receive a cancelled purchase order.');
    }
    if (po.status == PurchaseOrderStatus.received) {
      throw Exception('Purchase order has already been fully received.');
    }

    // Atomic pre-validation
    for (final reqItem in items) {
      final poItemId = reqItem['item_id'] as String;
      final receiveQty = (reqItem['receive_quantity'] as num).toDouble();
      final poItem = po.items.firstWhere((i) => i.id == poItemId);

      if (receiveQty <= 0) continue;
      if (poItem.receivedQuantity + receiveQty > poItem.quantity) {
        throw Exception(
          'Cannot receive more than remaining quantity. Allowed: ${poItem.remainingQuantity}, Requested: $receiveQty',
        );
      }
    }

    // Apply receiving atomically
    double totalBatchQty = 0;
    double totalBatchAmount = 0;
    final updatedItems = List<PurchaseOrderItem>.from(po.items);

    for (final reqItem in items) {
      final poItemId = reqItem['item_id'] as String;
      final receiveQty = (reqItem['receive_quantity'] as num).toDouble();
      if (receiveQty <= 0) continue;

      final itemIndex = updatedItems.indexWhere((i) => i.id == poItemId);
      final currentItem = updatedItems[itemIndex];
      final newReceivedQty = currentItem.receivedQuantity + receiveQty;
      final batchAmount = receiveQty * currentItem.unitPrice;

      updatedItems[itemIndex] = currentItem.copyWith(receivedQuantity: newReceivedQty);

      // Increase inventory stock & create audit transaction
      await inventoryRepo.performStockOperation(
        itemId: currentItem.inventoryId,
        transactionType: 'stock_in',
        quantity: receiveQty,
        reason: 'Purchase Order Delivery',
        remarks: 'Received against PO #${po.purchaseOrderNumber}',
        vendorId: po.vendorId,
        totalAmount: batchAmount,
      );

      totalBatchQty += receiveQty;
      totalBatchAmount += batchAmount;
    }

    // Determine new PO status
    final allFullyReceived = updatedItems.every((i) => i.isFullyReceived);
    final newStatus = allFullyReceived
        ? PurchaseOrderStatus.received
        : PurchaseOrderStatus.partiallyReceived;

    orders[idx] = po.copyWith(
      items: updatedItems,
      status: newStatus,
      actualDeliveryDate: DateTime.now(),
      updatedAt: DateTime.now(),
    );

    // Update vendor supply info
    final vendorIdx = vendorRepo.vendors.indexWhere((v) => v.id == po.vendorId);
    if (vendorIdx != -1) {
      final v = vendorRepo.vendors[vendorIdx];
      vendorRepo.vendors[vendorIdx] = v.copyWith(
        lastQuantity: totalBatchQty,
        lastTotalAmount: totalBatchAmount,
        lastDeliveryDate: DateTime.now(),
      );
    }

    return {
      'success': true,
      'purchase_order_id': purchaseOrderId,
      'status': newStatus.dbValue,
      'total_batch_quantity': totalBatchQty,
      'total_batch_amount': totalBatchAmount,
    };
  }

  @override
  Future<List<PurchaseOrder>> getVendorPurchaseOrders(String vendorId) async {
    return orders.where((o) => o.vendorId == vendorId).toList();
  }

  @override
  Future<List<PurchaseOrder>> getInventoryPurchaseOrders(String inventoryId) async {
    return orders.where((o) => o.items.any((i) => i.inventoryId == inventoryId)).toList();
  }
}

// ============================================================================
// MAIN TEST SUITE
// ============================================================================

void main() {
  late FakeInventoryRepoForPO fakeInventory;
  late FakeVendorRepoForPO fakeVendors;
  late InventoryItem itemGloves;
  late InventoryItem itemSyringes;
  late Vendor vendorCipla;

  setUp(() {
    itemGloves = const InventoryItem(
      id: 'inv-gloves-1',
      name: 'Latex Gloves Medium',
      category: 'Consumables & PPE',
      currentStock: 100.0,
      minimumStock: 30.0,
      unit: 'boxes',
      price: 45.0,
      sku: 'GLV-MED-100',
    );

    itemSyringes = const InventoryItem(
      id: 'inv-syringes-1',
      name: 'Disposable Syringes 5ml',
      category: 'Consumables & PPE',
      currentStock: 200.0,
      minimumStock: 50.0,
      unit: 'pcs',
      price: 12.0,
      sku: 'SYR-5ML-50',
    );

    vendorCipla = const Vendor(
      id: 'vendor-cipla-1',
      name: 'Cipla Healthcare Ltd',
      phone: '+919876543210',
      contactPerson: 'Rahul Sharma',
      productsSupplied: ['Latex Gloves Medium', 'Disposable Syringes 5ml'],
      isActive: true,
    );

    fakeInventory = FakeInventoryRepoForPO([itemGloves, itemSyringes]);
    fakeVendors = FakeVendorRepoForPO([vendorCipla]);
  });

  group('Sprint 6.4: Purchase Orders — Admin & Staff Parity', () {
    // ------------------------------------------------------------------------
    // 1. ADMIN: Create Purchase Order (Draft & Ordered)
    // ------------------------------------------------------------------------
    test('1. Admin can create PO with multiple items, auto-calculating totals', () async {
      final poRepo = FakePurchaseOrderRepository(
        inventoryRepo: fakeInventory,
        vendorRepo: fakeVendors,
        callerRole: 'admin',
      );

      final lineItems = [
        const PurchaseOrderItem(
          id: '',
          purchaseOrderId: '',
          inventoryId: 'inv-gloves-1',
          inventoryName: 'Latex Gloves Medium',
          quantity: 100.0,
          unitPrice: 45.0,
          totalAmount: 4500.0,
        ),
        const PurchaseOrderItem(
          id: '',
          purchaseOrderId: '',
          inventoryId: 'inv-syringes-1',
          inventoryName: 'Disposable Syringes 5ml',
          quantity: 50.0,
          unitPrice: 12.0,
          totalAmount: 600.0,
        ),
      ];

      final po = PurchaseOrder(
        id: '',
        purchaseOrderNumber: 'PO-20261001-001',
        vendorId: 'vendor-cipla-1',
        orderDate: DateTime.now(),
        status: PurchaseOrderStatus.ordered,
        totalAmount: 5100.0,
      );

      final created = await poRepo.createPurchaseOrder(po, lineItems);

      expect(created.id, isNotEmpty);
      expect(created.purchaseOrderNumber, 'PO-20261001-001');
      expect(created.totalAmount, 5100.0);
      expect(created.items.length, 2);
      expect(created.isOrdered, isTrue);
    });

    // ------------------------------------------------------------------------
    // 2. STAFF: Create Purchase Order (Exact Same as Admin)
    // ------------------------------------------------------------------------
    test('2. Staff has identical permission to create PO with multiple items', () async {
      final poRepo = FakePurchaseOrderRepository(
        inventoryRepo: fakeInventory,
        vendorRepo: fakeVendors,
        callerRole: 'staff',
      );

      final lineItems = [
        const PurchaseOrderItem(
          id: '',
          purchaseOrderId: '',
          inventoryId: 'inv-gloves-1',
          inventoryName: 'Latex Gloves Medium',
          quantity: 50.0,
          unitPrice: 45.0,
          totalAmount: 2250.0,
        ),
      ];

      final po = PurchaseOrder(
        id: '',
        purchaseOrderNumber: 'PO-20261001-002',
        vendorId: 'vendor-cipla-1',
        orderDate: DateTime.now(),
        status: PurchaseOrderStatus.ordered,
        totalAmount: 2250.0,
      );

      final created = await poRepo.createPurchaseOrder(po, lineItems);

      expect(created.id, isNotEmpty);
      expect(created.totalAmount, 2250.0);
      expect(poRepo.orders.length, 1);
    });

    // ------------------------------------------------------------------------
    // 3. UNAUTHORIZED ROLE: Blocked at database/RLS simulation level
    // ------------------------------------------------------------------------
    test('3. Unauthorized roles (e.g. doctor) are blocked from creating PO', () async {
      final poRepo = FakePurchaseOrderRepository(
        inventoryRepo: fakeInventory,
        vendorRepo: fakeVendors,
        callerRole: 'doctor',
      );

      final po = PurchaseOrder(
        id: '',
        purchaseOrderNumber: 'PO-HACK',
        vendorId: 'vendor-cipla-1',
        orderDate: DateTime.now(),
        totalAmount: 1000.0,
      );

      expect(
        () => poRepo.createPurchaseOrder(po, []),
        throwsA(isA<Exception>()),
      );
    });

    // ------------------------------------------------------------------------
    // 4. ADMIN & STAFF: Partial Receiving & Atomic Inventory Update
    // ------------------------------------------------------------------------
    test('4. Partial Receiving increases inventory stock and logs transaction atomically', () async {
      final poRepo = FakePurchaseOrderRepository(
        inventoryRepo: fakeInventory,
        vendorRepo: fakeVendors,
        callerRole: 'staff',
      );

      // Initial gloves stock: 100
      expect(fakeInventory.items.first.currentStock, 100.0);

      final lineItem = const PurchaseOrderItem(
        id: 'item-1',
        purchaseOrderId: 'po-1',
        inventoryId: 'inv-gloves-1',
        inventoryName: 'Latex Gloves Medium',
        quantity: 100.0,
        unitPrice: 45.0,
        totalAmount: 4500.0,
        receivedQuantity: 0.0,
      );

      final po = PurchaseOrder(
        id: 'po-1',
        purchaseOrderNumber: 'PO-20261001-PARTIAL',
        vendorId: 'vendor-cipla-1',
        orderDate: DateTime.now(),
        status: PurchaseOrderStatus.ordered,
        totalAmount: 4500.0,
        items: [lineItem],
      );

      poRepo.orders.add(po);

      // Staff receives partial 40 out of 100
      final result = await poRepo.receivePurchaseOrder(
        purchaseOrderId: 'po-1',
        items: [
          {'item_id': 'item-1', 'receive_quantity': 40.0},
        ],
      );

      expect(result['success'], isTrue);
      expect(result['status'], 'partially_received');

      // 1. PO item received quantity updated to 40
      final updatedPO = await poRepo.getPurchaseOrder('po-1');
      expect(updatedPO.isPartiallyReceived, isTrue);
      expect(updatedPO.items.first.receivedQuantity, 40.0);
      expect(updatedPO.items.first.remainingQuantity, 60.0);

      // 2. Inventory stock increased by 40 (100 -> 140)
      final updatedGloves = await fakeInventory.getInventoryItem('inv-gloves-1');
      expect(updatedGloves.currentStock, 140.0);
      expect(updatedGloves.lastQuantitySupplied, 40.0);
      expect(updatedGloves.lastTotalAmount, 1800.0); // 40 * 45

      // 3. Inventory transaction logged with stock_in & Purchase Order Delivery
      expect(fakeInventory.transactions.length, 1);
      final tx = fakeInventory.transactions.first;
      expect(tx.transactionType, 'stock_in');
      expect(tx.quantity, 40.0);
      expect(tx.stockBefore, 100.0);
      expect(tx.stockAfter, 140.0);
      expect(tx.reason, 'Purchase Order Delivery');
      expect(tx.vendorId, 'vendor-cipla-1');
      expect(tx.totalAmount, 1800.0);

      // 4. Vendor latest supply updated
      final updatedVendor = await fakeVendors.getVendor('vendor-cipla-1');
      expect(updatedVendor.lastQuantity, 40.0);
      expect(updatedVendor.lastTotalAmount, 1800.0);
    });

    // ------------------------------------------------------------------------
    // 5. Full Receiving marks PO status as received
    // ------------------------------------------------------------------------
    test('5. Full Receiving completes PO and marks status as Received', () async {
      final poRepo = FakePurchaseOrderRepository(
        inventoryRepo: fakeInventory,
        vendorRepo: fakeVendors,
        callerRole: 'admin',
      );

      final lineItem = const PurchaseOrderItem(
        id: 'item-2',
        purchaseOrderId: 'po-2',
        inventoryId: 'inv-syringes-1',
        inventoryName: 'Disposable Syringes 5ml',
        quantity: 50.0,
        unitPrice: 12.0,
        totalAmount: 600.0,
        receivedQuantity: 0.0,
      );

      final po = PurchaseOrder(
        id: 'po-2',
        purchaseOrderNumber: 'PO-20261001-FULL',
        vendorId: 'vendor-cipla-1',
        orderDate: DateTime.now(),
        status: PurchaseOrderStatus.ordered,
        totalAmount: 600.0,
        items: [lineItem],
      );

      poRepo.orders.add(po);

      // Receive all 50 units
      final result = await poRepo.receivePurchaseOrder(
        purchaseOrderId: 'po-2',
        items: [
          {'item_id': 'item-2', 'receive_quantity': 50.0},
        ],
      );

      expect(result['status'], 'received');
      final updatedPO = await poRepo.getPurchaseOrder('po-2');
      expect(updatedPO.isReceived, isTrue);
      expect(updatedPO.items.first.isFullyReceived, isTrue);

      // Syringes stock increased: 200 -> 250
      final updatedSyringes = await fakeInventory.getInventoryItem('inv-syringes-1');
      expect(updatedSyringes.currentStock, 250.0);
    });

    // ------------------------------------------------------------------------
    // 6. Validation: Cannot receive more than remaining quantity
    // ------------------------------------------------------------------------
    test('6. Validation rejects receiving more than remaining quantity', () async {
      final poRepo = FakePurchaseOrderRepository(
        inventoryRepo: fakeInventory,
        vendorRepo: fakeVendors,
        callerRole: 'staff',
      );

      final lineItem = const PurchaseOrderItem(
        id: 'item-3',
        purchaseOrderId: 'po-3',
        inventoryId: 'inv-gloves-1',
        quantity: 50.0,
        unitPrice: 45.0,
        totalAmount: 2250.0,
        receivedQuantity: 30.0, // Remaining: 20
      );

      final po = PurchaseOrder(
        id: 'po-3',
        purchaseOrderNumber: 'PO-EXCEED',
        vendorId: 'vendor-cipla-1',
        orderDate: DateTime.now(),
        status: PurchaseOrderStatus.partiallyReceived,
        totalAmount: 2250.0,
        items: [lineItem],
      );

      poRepo.orders.add(po);

      // Attempt to receive 25 (only 20 remaining) -> must throw!
      expect(
        () => poRepo.receivePurchaseOrder(
          purchaseOrderId: 'po-3',
          items: [
            {'item_id': 'item-3', 'receive_quantity': 25.0},
          ],
        ),
        throwsA(isA<Exception>()),
      );

      // Verify stock was NOT modified (atomic guarantee)
      expect(fakeInventory.items.first.currentStock, 100.0);
    });

    // ------------------------------------------------------------------------
    // 7. Validation: Cannot receive cancelled or already fully received PO
    // ------------------------------------------------------------------------
    test('7. Validation rejects receiving cancelled or fully received POs', () async {
      final poRepo = FakePurchaseOrderRepository(
        inventoryRepo: fakeInventory,
        vendorRepo: fakeVendors,
        callerRole: 'admin',
      );

      final cancelledPO = PurchaseOrder(
        id: 'po-cancelled',
        purchaseOrderNumber: 'PO-CANCELLED',
        vendorId: 'vendor-cipla-1',
        orderDate: DateTime.now(),
        status: PurchaseOrderStatus.cancelled,
        totalAmount: 1000.0,
        items: [
          const PurchaseOrderItem(
            id: 'item-c',
            purchaseOrderId: 'po-cancelled',
            inventoryId: 'inv-gloves-1',
            quantity: 20.0,
            unitPrice: 45.0,
            totalAmount: 900.0,
          ),
        ],
      );

      final receivedPO = PurchaseOrder(
        id: 'po-received',
        purchaseOrderNumber: 'PO-RECEIVED',
        vendorId: 'vendor-cipla-1',
        orderDate: DateTime.now(),
        status: PurchaseOrderStatus.received,
        totalAmount: 900.0,
        items: [
          const PurchaseOrderItem(
            id: 'item-r',
            purchaseOrderId: 'po-received',
            inventoryId: 'inv-gloves-1',
            quantity: 20.0,
            unitPrice: 45.0,
            totalAmount: 900.0,
            receivedQuantity: 20.0,
          ),
        ],
      );

      poRepo.orders.addAll([cancelledPO, receivedPO]);

      expect(
        () => poRepo.receivePurchaseOrder(
          purchaseOrderId: 'po-cancelled',
          items: [{'item_id': 'item-c', 'receive_quantity': 10.0}],
        ),
        throwsA(isA<Exception>()),
      );

      expect(
        () => poRepo.receivePurchaseOrder(
          purchaseOrderId: 'po-received',
          items: [{'item_id': 'item-r', 'receive_quantity': 5.0}],
        ),
        throwsA(isA<Exception>()),
      );
    });

    // ------------------------------------------------------------------------
    // 8. Cancel PO: Valid for Draft/Ordered, Invalid for Received/Cancelled
    // ------------------------------------------------------------------------
    test('8. Staff and Admin can cancel draft/ordered POs', () async {
      final poRepo = FakePurchaseOrderRepository(
        inventoryRepo: fakeInventory,
        vendorRepo: fakeVendors,
        callerRole: 'staff',
      );

      final draftPO = PurchaseOrder(
        id: 'po-draft',
        purchaseOrderNumber: 'PO-DRAFT',
        vendorId: 'vendor-cipla-1',
        orderDate: DateTime.now(),
        status: PurchaseOrderStatus.draft,
        totalAmount: 500.0,
      );

      poRepo.orders.add(draftPO);
      expect(draftPO.canCancel, isTrue);

      await poRepo.cancelPurchaseOrder('po-draft');
      final cancelled = await poRepo.getPurchaseOrder('po-draft');
      expect(cancelled.isCancelled, isTrue);
      expect(cancelled.canCancel, isFalse);
    });

    // ------------------------------------------------------------------------
    // 9. Vendor Purchase History
    // ------------------------------------------------------------------------
    test('9. Vendor Purchase History retrieves all POs for a specific vendor', () async {
      final poRepo = FakePurchaseOrderRepository(
        inventoryRepo: fakeInventory,
        vendorRepo: fakeVendors,
        callerRole: 'staff',
      );

      final po1 = PurchaseOrder(
        id: 'po-v1-1',
        purchaseOrderNumber: 'PO-CIPLA-001',
        vendorId: 'vendor-cipla-1',
        orderDate: DateTime.now().subtract(const Duration(days: 5)),
        status: PurchaseOrderStatus.received,
        totalAmount: 12500.0,
      );

      final po2 = PurchaseOrder(
        id: 'po-v1-2',
        purchaseOrderNumber: 'PO-CIPLA-002',
        vendorId: 'vendor-cipla-1',
        orderDate: DateTime.now(),
        status: PurchaseOrderStatus.ordered,
        totalAmount: 8200.0,
      );

      final poOther = PurchaseOrder(
        id: 'po-other',
        purchaseOrderNumber: 'PO-OTHER-001',
        vendorId: 'vendor-other-2',
        orderDate: DateTime.now(),
        status: PurchaseOrderStatus.draft,
        totalAmount: 3000.0,
      );

      poRepo.orders.addAll([po1, po2, poOther]);

      final ciplaHistory = await poRepo.getVendorPurchaseOrders('vendor-cipla-1');
      expect(ciplaHistory.length, 2);
      expect(ciplaHistory.any((p) => p.purchaseOrderNumber == 'PO-CIPLA-001'), isTrue);
      expect(ciplaHistory.any((p) => p.purchaseOrderNumber == 'PO-CIPLA-002'), isTrue);
      expect(ciplaHistory.any((p) => p.purchaseOrderNumber == 'PO-OTHER-001'), isFalse);
    });

    // ------------------------------------------------------------------------
    // 10. Product Purchase History
    // ------------------------------------------------------------------------
    test('10. Inventory Product Purchase History finds all POs supplying a product', () async {
      final poRepo = FakePurchaseOrderRepository(
        inventoryRepo: fakeInventory,
        vendorRepo: fakeVendors,
        callerRole: 'staff',
      );

      final poWithGloves = PurchaseOrder(
        id: 'po-glv',
        purchaseOrderNumber: 'PO-GLV-01',
        vendorId: 'vendor-cipla-1',
        orderDate: DateTime.now(),
        totalAmount: 4500.0,
        items: [
          const PurchaseOrderItem(
            id: 'item-glv',
            purchaseOrderId: 'po-glv',
            inventoryId: 'inv-gloves-1',
            quantity: 100.0,
            unitPrice: 45.0,
            totalAmount: 4500.0,
          ),
        ],
      );

      final poWithoutGloves = PurchaseOrder(
        id: 'po-syr',
        purchaseOrderNumber: 'PO-SYR-01',
        vendorId: 'vendor-cipla-1',
        orderDate: DateTime.now(),
        totalAmount: 600.0,
        items: [
          const PurchaseOrderItem(
            id: 'item-syr',
            purchaseOrderId: 'po-syr',
            inventoryId: 'inv-syringes-1',
            quantity: 50.0,
            unitPrice: 12.0,
            totalAmount: 600.0,
          ),
        ],
      );

      poRepo.orders.addAll([poWithGloves, poWithoutGloves]);

      final glovePOs = await poRepo.getInventoryPurchaseOrders('inv-gloves-1');
      expect(glovePOs.length, 1);
      expect(glovePOs.first.purchaseOrderNumber, 'PO-GLV-01');
    });

    // ------------------------------------------------------------------------
    // 11. UI: Staff can view Purchase Orders screen, see KPI cards and New PO button
    // ------------------------------------------------------------------------
    testWidgets('11. Staff can view Purchase Orders screen with full parity', (tester) async {
      tester.view.physicalSize = const Size(1280, 800);
      tester.view.devicePixelRatio = 1.0;
      addTearDown(() => tester.view.resetPhysicalSize());

      final poRepo = FakePurchaseOrderRepository(
        inventoryRepo: fakeInventory,
        vendorRepo: fakeVendors,
        callerRole: 'staff',
        initial: [
          PurchaseOrder(
            id: 'po-ui-1',
            purchaseOrderNumber: 'PO-20261001-STAFF',
            vendorId: 'vendor-cipla-1',
            vendorName: 'Cipla Healthcare Ltd',
            orderDate: DateTime.now(),
            status: PurchaseOrderStatus.ordered,
            totalAmount: 5100.0,
            items: [
              const PurchaseOrderItem(
                id: 'i-1',
                purchaseOrderId: 'po-ui-1',
                inventoryId: 'inv-gloves-1',
                inventoryName: 'Latex Gloves Medium',
                quantity: 100.0,
                unitPrice: 45.0,
                totalAmount: 4500.0,
              ),
            ],
          ),
        ],
      );

      await tester.pumpWidget(
        ProviderScope(
          overrides: [
            purchaseOrderRepositoryProvider.overrideWithValue(poRepo),
            inventoryRepositoryProvider.overrideWithValue(fakeInventory),
            vendorRepositoryProvider.overrideWithValue(fakeVendors),
            currentUserRoleProvider.overrideWith((ref) => Future.value('staff')),
          ],
          child: const MaterialApp(
            home: Scaffold(
              body: PurchaseOrderManagementContent(),
            ),
          ),
        ),
      );

      await tester.pumpAndSettle();

      // Verify Header & Parity Buttons
      expect(find.text('Purchase Orders'), findsOneWidget);
      expect(find.text('New Purchase Order'), findsOneWidget);

      // Verify KPI Cards
      expect(find.text('Total POs'), findsOneWidget);
      expect(find.text('Ordered'), findsWidgets);

      // Verify Table row rendered
      expect(find.text('PO-20261001-STAFF'), findsOneWidget);
      expect(find.text('Cipla Healthcare Ltd'), findsOneWidget);
      expect(find.text('₹5100.00'), findsOneWidget);

      // Staff sees Receive Items and View Details buttons
      expect(find.byIcon(Icons.inventory), findsOneWidget);
      expect(find.byIcon(Icons.visibility_outlined), findsOneWidget);
    });

    // ------------------------------------------------------------------------
    // 12. UI: Details Dialog opens, displays products, and supports Call Vendor
    // ------------------------------------------------------------------------
    testWidgets('12. Details dialog displays supplier contact, Call Vendor button and line items',
        (tester) async {
      tester.view.physicalSize = const Size(1280, 800);
      tester.view.devicePixelRatio = 1.0;
      addTearDown(() => tester.view.resetPhysicalSize());

      final po = PurchaseOrder(
        id: 'po-details-1',
        purchaseOrderNumber: 'PO-CALL-VENDOR',
        vendorId: 'vendor-cipla-1',
        vendorName: 'Cipla Healthcare Ltd',
        vendorPhone: '+919876543210',
        orderDate: DateTime.now(),
        status: PurchaseOrderStatus.ordered,
        totalAmount: 4500.0,
        items: [
          const PurchaseOrderItem(
            id: 'i-1',
            purchaseOrderId: 'po-details-1',
            inventoryId: 'inv-gloves-1',
            inventoryName: 'Latex Gloves Medium',
            quantity: 100.0,
            unitPrice: 45.0,
            totalAmount: 4500.0,
          ),
        ],
      );

      final poRepo = FakePurchaseOrderRepository(
        inventoryRepo: fakeInventory,
        vendorRepo: fakeVendors,
        initial: [po],
        callerRole: 'staff',
      );

      await tester.pumpWidget(
        ProviderScope(
          overrides: [
            purchaseOrderRepositoryProvider.overrideWithValue(poRepo),
            inventoryRepositoryProvider.overrideWithValue(fakeInventory),
            vendorRepositoryProvider.overrideWithValue(fakeVendors),
            currentUserRoleProvider.overrideWith((ref) => Future.value('staff')),
          ],
          child: MaterialApp(
            home: Scaffold(
              body: PurchaseOrderDetailsDialog(order: po),
            ),
          ),
        ),
      );

      await tester.pumpAndSettle();

      expect(find.text('PO #PO-CALL-VENDOR'), findsOneWidget);
      expect(find.text('Cipla Healthcare Ltd'), findsOneWidget);
      expect(find.text('Call Vendor'), findsOneWidget);
      expect(find.text('Latex Gloves Medium'), findsOneWidget);
      expect(find.text('Receive Items'), findsOneWidget);
      expect(find.text('Close'), findsOneWidget);
    });

    // ------------------------------------------------------------------------
    // 13. UI: Receive Purchase Order dialog allows entering partial quantity
    // ------------------------------------------------------------------------
    testWidgets('13. Receive dialog displays ordered/remaining and confirms receiving',
        (tester) async {
      tester.view.physicalSize = const Size(1280, 800);
      tester.view.devicePixelRatio = 1.0;
      addTearDown(() => tester.view.resetPhysicalSize());

      final po = PurchaseOrder(
        id: 'po-recv-dialog',
        purchaseOrderNumber: 'PO-RECV-DLG',
        vendorId: 'vendor-cipla-1',
        vendorName: 'Cipla Healthcare Ltd',
        orderDate: DateTime.now(),
        status: PurchaseOrderStatus.ordered,
        totalAmount: 4500.0,
        items: [
          const PurchaseOrderItem(
            id: 'item-recv-1',
            purchaseOrderId: 'po-recv-dialog',
            inventoryId: 'inv-gloves-1',
            inventoryName: 'Latex Gloves Medium',
            quantity: 100.0,
            unitPrice: 45.0,
            totalAmount: 4500.0,
          ),
        ],
      );

      final poRepo = FakePurchaseOrderRepository(
        inventoryRepo: fakeInventory,
        vendorRepo: fakeVendors,
        initial: [po],
        callerRole: 'staff',
      );

      await tester.pumpWidget(
        ProviderScope(
          overrides: [
            purchaseOrderRepositoryProvider.overrideWithValue(poRepo),
            inventoryRepositoryProvider.overrideWithValue(fakeInventory),
            vendorRepositoryProvider.overrideWithValue(fakeVendors),
            currentUserRoleProvider.overrideWith((ref) => Future.value('staff')),
          ],
          child: MaterialApp(
            home: Scaffold(
              body: ReceivePurchaseOrderDialog(order: po),
            ),
          ),
        ),
      );

      await tester.pumpAndSettle();

      expect(find.text('Receive Purchase Order'), findsOneWidget);
      expect(find.text('Latex Gloves Medium'), findsOneWidget);
      expect(find.text('Confirm Receiving'), findsOneWidget);

      // Confirm receiving
      await tester.tap(find.text('Confirm Receiving'));
      await tester.pumpAndSettle();

      // Inventory stock should now be increased
      final gloves = await fakeInventory.getInventoryItem('inv-gloves-1');
      expect(gloves.currentStock, 200.0); // 100 + 100
    });

    // ------------------------------------------------------------------------
    // 14. UI: Vendor Details displays Purchase History section
    // ------------------------------------------------------------------------
    testWidgets('14. Vendor Details dialog displays Purchase History section',
        (tester) async {
      tester.view.physicalSize = const Size(1280, 800);
      tester.view.devicePixelRatio = 1.0;
      addTearDown(() => tester.view.resetPhysicalSize());

      final po = PurchaseOrder(
        id: 'po-v-history',
        purchaseOrderNumber: 'PO-VEND-001',
        vendorId: 'vendor-cipla-1',
        orderDate: DateTime.now(),
        status: PurchaseOrderStatus.received,
        totalAmount: 12500.0,
      );

      final poRepo = FakePurchaseOrderRepository(
        inventoryRepo: fakeInventory,
        vendorRepo: fakeVendors,
        initial: [po],
        callerRole: 'staff',
      );

      await tester.pumpWidget(
        ProviderScope(
          overrides: [
            purchaseOrderRepositoryProvider.overrideWithValue(poRepo),
            inventoryRepositoryProvider.overrideWithValue(fakeInventory),
            vendorRepositoryProvider.overrideWithValue(fakeVendors),
            currentUserRoleProvider.overrideWith((ref) => Future.value('staff')),
          ],
          child: MaterialApp(
            home: Scaffold(
              body: VendorDetailsDialog(vendor: vendorCipla),
            ),
          ),
        ),
      );

      await tester.pumpAndSettle();

      // Vendor details headers
      expect(find.text('Cipla Healthcare Ltd'), findsOneWidget);
      expect(find.text('PURCHASE ORDER HISTORY'), findsOneWidget);
      expect(find.text('PO-VEND-001'), findsOneWidget);
      expect(find.text('₹12500.00'), findsOneWidget);
    });

    // ------------------------------------------------------------------------
    // 15. Expected Delivery Date >= Order Date: Model validation
    // ------------------------------------------------------------------------
    test('15. PurchaseOrder model hasValidDates enforces expectedDeliveryDate >= orderDate', () {
      final now = DateTime(2026, 10, 10);

      // Same-day order and delivery -> passes
      final sameDayPO = PurchaseOrder(
        id: 'po-same-day',
        purchaseOrderNumber: 'PO-DATE-001',
        vendorId: 'vendor-1',
        orderDate: now,
        expectedDeliveryDate: DateTime(2026, 10, 10),
        totalAmount: 1000.0,
      );
      expect(sameDayPO.hasValidDates, isTrue);

      // Delivery after order -> passes
      final futureDeliveryPO = PurchaseOrder(
        id: 'po-future',
        purchaseOrderNumber: 'PO-DATE-002',
        vendorId: 'vendor-1',
        orderDate: now,
        expectedDeliveryDate: DateTime(2026, 10, 15),
        totalAmount: 1000.0,
      );
      expect(futureDeliveryPO.hasValidDates, isTrue);

      // Null delivery date -> passes
      final nullDeliveryPO = PurchaseOrder(
        id: 'po-null',
        purchaseOrderNumber: 'PO-DATE-003',
        vendorId: 'vendor-1',
        orderDate: now,
        expectedDeliveryDate: null,
        totalAmount: 1000.0,
      );
      expect(nullDeliveryPO.hasValidDates, isTrue);

      // Delivery before order -> rejected
      final invalidPO = PurchaseOrder(
        id: 'po-invalid',
        purchaseOrderNumber: 'PO-DATE-004',
        vendorId: 'vendor-1',
        orderDate: now,
        expectedDeliveryDate: DateTime(2026, 10, 5),
        totalAmount: 1000.0,
      );
      expect(invalidPO.hasValidDates, isFalse);
    });

    // ------------------------------------------------------------------------
    // 16. Repository blocks creating or updating PO with delivery before order
    // ------------------------------------------------------------------------
    test('16. Repository blocks creating or updating PO with delivery before order date', () async {
      final poRepo = FakePurchaseOrderRepository(
        inventoryRepo: fakeInventory,
        vendorRepo: fakeVendors,
        initial: [],
        callerRole: 'admin',
      );

      final invalidPO = PurchaseOrder(
        id: 'po-invalid-repo',
        purchaseOrderNumber: 'PO-DATE-FAIL',
        vendorId: 'vendor-cipla-1',
        orderDate: DateTime(2026, 10, 10),
        expectedDeliveryDate: DateTime(2026, 10, 5),
        totalAmount: 100.0,
      );

      // Creation rejected
      expect(
        () => poRepo.createPurchaseOrder(invalidPO, []),
        throwsA(
          predicate(
            (e) => e.toString().contains('Expected delivery date cannot be before the order date.'),
          ),
        ),
      );
    });

    // ------------------------------------------------------------------------
    // 17. PO Form Dialog blocks submission with delivery before order date
    // ------------------------------------------------------------------------
    testWidgets('17. PO Form Dialog blocks submission with delivery before order date and shows clear error',
        (tester) async {
      tester.view.physicalSize = const Size(1280, 800);
      tester.view.devicePixelRatio = 1.0;
      addTearDown(() => tester.view.resetPhysicalSize());

      final invalidPO = PurchaseOrder(
        id: 'po-edit-invalid',
        purchaseOrderNumber: 'PO-INVALID-EDIT',
        vendorId: 'vendor-cipla-1',
        orderDate: DateTime(2026, 10, 20),
        expectedDeliveryDate: DateTime(2026, 10, 10),
        totalAmount: 4500.0,
        items: [
          const PurchaseOrderItem(
            id: 'item-1',
            purchaseOrderId: 'po-edit-invalid',
            inventoryId: 'inv-gloves-1',
            inventoryName: 'Latex Gloves Medium',
            quantity: 100.0,
            unitPrice: 45.0,
            totalAmount: 4500.0,
          ),
        ],
      );

      final poRepo = FakePurchaseOrderRepository(
        inventoryRepo: fakeInventory,
        vendorRepo: fakeVendors,
        initial: [invalidPO],
        callerRole: 'staff',
      );

      await tester.pumpWidget(
        ProviderScope(
          overrides: [
            purchaseOrderRepositoryProvider.overrideWithValue(poRepo),
            inventoryRepositoryProvider.overrideWithValue(fakeInventory),
            vendorRepositoryProvider.overrideWithValue(fakeVendors),
            currentUserRoleProvider.overrideWith((ref) => Future.value('staff')),
          ],
          child: MaterialApp(
            home: Scaffold(
              body: PurchaseOrderFormDialog(order: invalidPO),
            ),
          ),
        ),
      );

      await tester.pumpAndSettle();

      // Attempt to save changes
      await tester.tap(find.text('Save Changes'));
      await tester.pumpAndSettle();

      // Error message is displayed and submission is blocked
      expect(
        find.text('Expected delivery date cannot be before the order date.'),
        findsOneWidget,
      );
    });

    // ------------------------------------------------------------------------
    // 18. Dynamic validation: changing order date clears invalid delivery date
    // ------------------------------------------------------------------------
    testWidgets('18. Dynamic validation: changing order date after delivery date clears the invalid delivery date',
        (tester) async {
      tester.view.physicalSize = const Size(1280, 800);
      tester.view.devicePixelRatio = 1.0;
      addTearDown(() => tester.view.resetPhysicalSize());

      final validPO = PurchaseOrder(
        id: 'po-dynamic-test',
        purchaseOrderNumber: 'PO-DYN-01',
        vendorId: 'vendor-cipla-1',
        orderDate: DateTime(2026, 10, 10),
        expectedDeliveryDate: DateTime(2026, 10, 15),
        totalAmount: 4500.0,
        items: [
          const PurchaseOrderItem(
            id: 'item-1',
            purchaseOrderId: 'po-dynamic-test',
            inventoryId: 'inv-gloves-1',
            inventoryName: 'Latex Gloves Medium',
            quantity: 100.0,
            unitPrice: 45.0,
            totalAmount: 4500.0,
          ),
        ],
      );

      final poRepo = FakePurchaseOrderRepository(
        inventoryRepo: fakeInventory,
        vendorRepo: fakeVendors,
        initial: [validPO],
        callerRole: 'admin',
      );

      await tester.pumpWidget(
        ProviderScope(
          overrides: [
            purchaseOrderRepositoryProvider.overrideWithValue(poRepo),
            inventoryRepositoryProvider.overrideWithValue(fakeInventory),
            vendorRepositoryProvider.overrideWithValue(fakeVendors),
            currentUserRoleProvider.overrideWith((ref) => Future.value('admin')),
          ],
          child: MaterialApp(
            home: Scaffold(
              body: PurchaseOrderFormDialog(order: validPO),
            ),
          ),
        ),
      );

      await tester.pumpAndSettle();

      // Initial dates are displayed
      expect(find.text('2026-10-10'), findsOneWidget); // Order date
      expect(find.text('2026-10-15'), findsOneWidget); // Expected delivery date

      // Tap order date to open picker
      await tester.tap(find.text('2026-10-10'));
      await tester.pumpAndSettle();

      // In showDatePicker, select 20 Oct 2026 (day '20')
      await tester.tap(find.text('20'));
      await tester.tap(find.text('OK'));
      await tester.pumpAndSettle();

      // Order date should now be 2026-10-20
      expect(find.text('2026-10-20'), findsOneWidget);

      // The delivery date (was 15 Oct) is now before Order Date, so it was automatically cleared
      expect(find.text('2026-10-15'), findsNothing);
      expect(find.text('Not specified'), findsOneWidget);
    });
  });
}
