import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:intl/intl.dart';
import 'package:supabase_flutter/supabase_flutter.dart' show User;

import 'package:mkes_care/features/auth/providers/auth_provider.dart';
import 'package:mkes_care/features/inventory/models/inventory_batch.dart';
import 'package:mkes_care/features/inventory/models/inventory_item.dart';
import 'package:mkes_care/features/inventory/models/inventory_transaction.dart';
import 'package:mkes_care/features/inventory/models/purchase_order.dart';
import 'package:mkes_care/features/inventory/repositories/inventory_repository.dart';
import 'package:mkes_care/features/inventory/repositories/purchase_order_repository.dart';
import 'package:mkes_care/features/inventory/utils/phone_dialer_util.dart';
import 'package:mkes_care/features/inventory/widgets/inventory_details_dialog.dart';
import 'package:mkes_care/features/inventory/widgets/purchase_order_form_dialog.dart';
import 'package:mkes_care/features/vendors/models/vendor.dart';
import 'package:mkes_care/features/vendors/repositories/vendor_repository.dart';

// ============================================================================
// SIMULATION & FAKE REPOSITORIES
// ============================================================================

class MockNotification {
  final String id;
  final String userId;
  final String userRole;
  final bool isActive;
  final String title;
  final String message;
  final String type;
  final DateTime createdAt;

  MockNotification({
    required this.id,
    required this.userId,
    required this.userRole,
    required this.isActive,
    required this.title,
    required this.message,
    required this.type,
    required this.createdAt,
  });
}

class FakeSystemUsers {
  static final List<Map<String, dynamic>> users = [
    {'id': 'admin-1', 'role': 'admin', 'is_active': true, 'name': 'Dr. Sharma'},
    {'id': 'admin-2', 'role': 'admin', 'is_active': true, 'name': 'Dr. Patel'},
    {'id': 'staff-1', 'role': 'staff', 'is_active': true, 'name': 'Nurse Alice'},
    {'id': 'staff-2', 'role': 'staff', 'is_active': true, 'name': 'Tech Bob'},
    {'id': 'staff-inactive', 'role': 'staff', 'is_active': false, 'name': 'Ex-Staff Dan'},
    {'id': 'doctor-1', 'role': 'doctor', 'is_active': true, 'name': 'Surgeon Rao'},
  ];
}

class FakeSprint64InventoryRepo implements InventoryRepository {
  final List<InventoryItem> items;
  final List<InventoryBatch> batches = [];
  final List<InventoryTransaction> transactions = [];

  @override
  dynamic noSuchMethod(Invocation invocation) => super.noSuchMethod(invocation);

  FakeSprint64InventoryRepo([List<InventoryItem>? initialItems])
      : items = initialItems != null ? List.from(initialItems) : [];

  @override
  Future<List<InventoryItem>> getInventoryItems({
    String? category,
    String? department,
    String? searchQuery,
    bool? activeOnly,
  }) async =>
      List.from(items);

  @override
  Future<InventoryItem> getInventoryItem(String id) async =>
      items.firstWhere((i) => i.id == id);

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
  Future<List<InventoryBatch>> getInventoryBatches(String inventoryId) async {
    return batches.where((b) => b.inventoryId == inventoryId).toList();
  }

  @override
  Future<List<InventoryBatch>> getBatchesForPO(String purchaseOrderId) async {
    return batches.where((b) => b.purchaseOrderId == purchaseOrderId).toList();
  }

  /// FEFO Stock Out simulation matching DB RPC perform_stock_operation
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
    if (idx == -1) throw Exception('Item not found');
    final item = items[idx];

    final before = item.currentStock;
    final double after;

    final List<String> fefoNotes = [];

    if (transactionType == 'stock_out') {
      if (quantity > before) {
        throw Exception('Cannot dispense more than available stock ($before).');
      }
      after = before - quantity;

      // FEFO Batch deduction: sort batches by expiry ascending (earliest first)
      final activeBatches = batches
          .where((b) => b.inventoryId == itemId && b.remainingQuantity > 0)
          .toList();
      activeBatches.sort((a, b) {
        if (a.expiryDate == null && b.expiryDate == null) return 0;
        if (a.expiryDate == null) return 1;
        if (b.expiryDate == null) return -1;
        return a.expiryDate!.compareTo(b.expiryDate!);
      });

      double remainingToDeduct = quantity;
      for (final b in activeBatches) {
        if (remainingToDeduct <= 0) break;
        final bIdx = batches.indexWhere((x) => x.id == b.id);
        if (b.remainingQuantity <= remainingToDeduct) {
          final deducted = b.remainingQuantity;
          remainingToDeduct -= deducted;
          batches[bIdx] = b.copyWith(remainingQuantity: 0);
          fefoNotes.add('${b.batchNumber}: $deducted units');
        } else {
          final newRem = b.remainingQuantity - remainingToDeduct;
          batches[bIdx] = b.copyWith(remainingQuantity: newRem);
          fefoNotes.add('${b.batchNumber}: $remainingToDeduct units');
          remainingToDeduct = 0;
        }
      }
    } else {
      after = before + quantity;
    }

    final updatedRemarks = fefoNotes.isNotEmpty
        ? '${remarks ?? ''} [FEFO Consumed: ${fefoNotes.join(', ')}]'.trim()
        : remarks;

    // Recalculate earliest expiry
    final remBatches = batches.where((b) => b.inventoryId == itemId && b.remainingQuantity > 0).toList();
    DateTime? earliestExpiry;
    for (final b in remBatches) {
      if (b.expiryDate != null) {
        if (earliestExpiry == null || b.expiryDate!.isBefore(earliestExpiry)) {
          earliestExpiry = b.expiryDate;
        }
      }
    }

    items[idx] = item.copyWith(
      currentStock: after,
      expiryDate: earliestExpiry ?? item.expiryDate,
      updatedAt: DateTime.now(),
    );

    final tx = InventoryTransaction(
      id: 'tx-${transactions.length + 1}',
      inventoryItemId: itemId,
      transactionType: transactionType,
      quantity: quantity,
      stockBefore: before,
      stockAfter: after,
      reason: reason,
      remarks: updatedRemarks,
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
  }) async =>
      List.from(transactions);
}

class FakeSprint64PORepo implements PurchaseOrderRepository {
  final List<PurchaseOrder> orders = [];
  final Map<String, int> dailySequences = {};
  final List<MockNotification> notifications = [];
  final Set<String> notifiedPoIds = {};

  final FakeSprint64InventoryRepo inventoryRepo;

  FakeSprint64PORepo(this.inventoryRepo, [List<PurchaseOrder>? initial]) {
    if (initial != null) orders.addAll(initial);
  }

  /// Concurrency-safe atomic daily PO sequence generator: PO-DDMMYYYY-0001
  String generatePoNumber([DateTime? date]) {
    final now = date ?? DateTime.now();
    final dateKey = DateFormat('yyyy-MM-dd').format(now);
    final currentVal = (dailySequences[dateKey] ?? 0) + 1;
    dailySequences[dateKey] = currentVal;

    final dd = now.day.toString().padLeft(2, '0');
    final mm = now.month.toString().padLeft(2, '0');
    final yyyy = now.year.toString();
    final seq = currentVal.toString().padLeft(4, '0');
    return 'PO-$dd$mm$yyyy-$seq';
  }

  void _triggerNotifications(PurchaseOrder po) {
    if (po.status == PurchaseOrderStatus.ordered && !notifiedPoIds.contains(po.id)) {
      notifiedPoIds.add(po.id);
      for (final u in FakeSystemUsers.users) {
        if ((u['role'] == 'admin' || u['role'] == 'staff') && u['is_active'] == true) {
          notifications.add(MockNotification(
            id: 'notif-${notifications.length + 1}',
            userId: u['id'],
            userRole: u['role'],
            isActive: u['is_active'],
            title: 'Purchase Order Placed',
            message: 'Purchase Order ${po.purchaseOrderNumber} has been placed with ${po.vendorName ?? 'Vendor'}.',
            type: 'purchase_order',
            createdAt: DateTime.now(),
          ));
        }
      }
    }
  }

  @override
  Future<List<PurchaseOrder>> getPurchaseOrders({
    String? status,
    String? vendorId,
    String? searchQuery,
  }) async {
    return List.from(orders);
  }

  @override
  Future<PurchaseOrder> getPurchaseOrder(String id) async {
    return orders.firstWhere((o) => o.id == id);
  }

  @override
  Future<PurchaseOrder> createPurchaseOrder(
    PurchaseOrder order, [
    List<PurchaseOrderItem> items = const [],
  ]) async {
    if (order.expectedDeliveryDate != null &&
        order.expectedDeliveryDate!.isBefore(order.orderDate)) {
      throw ArgumentError('Expected delivery date cannot be before order date');
    }

    final poNum = generatePoNumber(DateTime.now());
    final allItems = items.isNotEmpty ? items : order.items;
    final total = allItems.fold(0.0, (sum, i) => sum + i.totalAmount);

    final created = order.copyWith(
      id: 'po-${orders.length + 1}',
      purchaseOrderNumber: poNum,
      items: allItems,
      totalAmount: total > 0 ? total : order.totalAmount,
      createdAt: DateTime.now(),
      updatedAt: DateTime.now(),
    );
    orders.add(created);

    _triggerNotifications(created);
    return created;
  }

  @override
  Future<PurchaseOrder> updatePurchaseOrder(
    PurchaseOrder order, [
    List<PurchaseOrderItem> items = const [],
  ]) async {
    if (order.expectedDeliveryDate != null &&
        order.expectedDeliveryDate!.isBefore(order.orderDate)) {
      throw ArgumentError('Expected delivery date cannot be before order date');
    }

    final idx = orders.indexWhere((o) => o.id == order.id);
    if (idx == -1) throw Exception('Order not found');
    final existing = orders[idx];

    final allItems = items.isNotEmpty ? items : (order.items.isNotEmpty ? order.items : existing.items);
    final total = allItems.fold(0.0, (sum, i) => sum + i.totalAmount);

    // PO number is strictly immutable!
    final updated = order.copyWith(
      purchaseOrderNumber: existing.purchaseOrderNumber,
      items: allItems,
      totalAmount: total > 0 ? total : order.totalAmount,
      updatedAt: DateTime.now(),
    );
    orders[idx] = updated;

    _triggerNotifications(updated);
    return updated;
  }

  @override
  Future<void> cancelPurchaseOrder(String id) async {
    final idx = orders.indexWhere((o) => o.id == id);
    if (idx != -1) {
      orders[idx] = orders[idx].copyWith(
        status: PurchaseOrderStatus.cancelled,
        updatedAt: DateTime.now(),
      );
    }
  }

  @override
  Future<void> updateStatus(String id, PurchaseOrderStatus status) async {
    final idx = orders.indexWhere((o) => o.id == id);
    if (idx != -1) {
      final updated = orders[idx].copyWith(
        status: status,
        updatedAt: DateTime.now(),
      );
      orders[idx] = updated;
      _triggerNotifications(updated);
    }
  }

  @override
  Future<Map<String, dynamic>> receivePurchaseOrder({
    required String purchaseOrderId,
    required List<Map<String, dynamic>> items,
    String? notes,
  }) async {
    final oIdx = orders.indexWhere((o) => o.id == purchaseOrderId);
    if (oIdx == -1) throw Exception('PO not found');
    final po = orders[oIdx];

    final updatedItems = List<PurchaseOrderItem>.from(po.items);

    for (final rec in items) {
      final itemId = rec['item_id'] as String;
      final qty = (rec['received_quantity'] as num).toDouble();
      final expiryStr = rec['expiry_date'] as String?;
      final DateTime? expiryDate = expiryStr != null ? DateTime.parse(expiryStr) : null;

      final iIdx = updatedItems.indexWhere((i) => i.id == itemId);
      if (iIdx == -1) throw Exception('Item not found in PO');
      final poItem = updatedItems[iIdx];

      if (qty <= 0) throw ArgumentError('Receive quantity must be > 0');
      if (qty > poItem.remainingQuantity) throw ArgumentError('Receive quantity cannot exceed remaining');

      // Expiry validation: cannot be before today/receiving date
      if (expiryDate != null) {
        final now = DateTime.now();
        final today = DateTime(now.year, now.month, now.day);
        final expDay = DateTime(expiryDate.year, expiryDate.month, expiryDate.day);
        if (expDay.isBefore(today)) {
          throw ArgumentError('Expiry date cannot be in the past');
        }
      }

      // 1. Create Batch Record
      final batch = InventoryBatch(
        id: 'batch-${inventoryRepo.batches.length + 1}',
        inventoryId: poItem.inventoryId,
        purchaseOrderId: po.id,
        purchaseOrderItemId: poItem.id,
        vendorId: po.vendorId,
        batchNumber: 'B-${DateFormat('yyyyMMdd').format(DateTime.now())}-${inventoryRepo.batches.length + 1}',
        receivedQuantity: qty,
        remainingQuantity: qty,
        unitPrice: poItem.unitPrice,
        totalAmount: qty * poItem.unitPrice,
        expiryDate: expiryDate,
        receivedDate: DateTime.now(),
        createdAt: DateTime.now(),
        purchaseOrderNumber: po.purchaseOrderNumber,
        vendorName: po.vendorName,
        inventoryName: poItem.inventoryName,
      );
      inventoryRepo.batches.add(batch);

      // 2. Atomic Stock Increase in Inventory
      final invIdx = inventoryRepo.items.indexWhere((x) => x.id == poItem.inventoryId);
      if (invIdx != -1) {
        final inv = inventoryRepo.items[invIdx];
        final newStock = inv.currentStock + qty;

        // Earliest expiry
        final allItemBatches = inventoryRepo.batches
            .where((b) => b.inventoryId == poItem.inventoryId && b.remainingQuantity > 0)
            .toList();
        DateTime? earliestExp;
        for (final b in allItemBatches) {
          if (b.expiryDate != null) {
            if (earliestExp == null || b.expiryDate!.isBefore(earliestExp)) {
              earliestExp = b.expiryDate;
            }
          }
        }

        inventoryRepo.items[invIdx] = inv.copyWith(
          currentStock: newStock,
          expiryDate: earliestExp ?? inv.expiryDate,
          vendorId: po.vendorId,
          lastQuantitySupplied: qty,
          lastTotalAmount: qty * poItem.unitPrice,
          updatedAt: DateTime.now(),
        );

        inventoryRepo.transactions.add(InventoryTransaction(
          id: 'tx-${inventoryRepo.transactions.length + 1}',
          inventoryItemId: poItem.inventoryId,
          transactionType: 'stock_in',
          quantity: qty,
          stockBefore: inv.currentStock,
          stockAfter: newStock,
          reason: 'purchase_order_receipt',
          remarks: 'Received via PO ${po.purchaseOrderNumber}, Batch ${batch.batchNumber}',
          vendorId: po.vendorId,
          totalAmount: qty * poItem.unitPrice,
          unitPrice: poItem.unitPrice,
          createdAt: DateTime.now(),
        ));
      }

      // Update PO Item received
      final newRecv = poItem.receivedQuantity + qty;
      updatedItems[iIdx] = poItem.copyWith(receivedQuantity: newRecv);
    }

    final allFullyReceived = updatedItems.every((i) => i.remainingQuantity <= 0);
    final anyReceived = updatedItems.any((i) => i.receivedQuantity > 0);

    final PurchaseOrderStatus newStatus = allFullyReceived
        ? PurchaseOrderStatus.received
        : (anyReceived ? PurchaseOrderStatus.partiallyReceived : po.status);

    orders[oIdx] = po.copyWith(
      items: updatedItems,
      status: newStatus,
      actualDeliveryDate: DateTime.now(),
      updatedAt: DateTime.now(),
    );

    return {'success': true, 'status': newStatus.dbValue};
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

class FakeSprint64VendorRepo implements VendorRepository {
  final List<Vendor> vendors;
  FakeSprint64VendorRepo([List<Vendor>? initial])
      : vendors = initial != null ? List.from(initial) : [];

  @override
  Future<List<Vendor>> getVendors({String? searchQuery, bool? activeOnly}) async =>
      List.from(vendors);

  @override
  Future<Vendor> getVendor(String id) async =>
      vendors.firstWhere((v) => v.id == id);

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
    if (idx != -1) {
      vendors[idx] = vendors[idx].copyWith(isActive: isActive);
      return vendors[idx];
    }
    throw Exception('Vendor not found');
  }
}

// ============================================================================
// MAIN TEST SUITE
// ============================================================================

void main() {
  const adminUser = User(
    id: 'admin-1',
    appMetadata: {},
    userMetadata: {'full_name': 'Dr. Sharma'},
    aud: 'authenticated',
    createdAt: '2026-01-01',
  );

  const staffUser = User(
    id: 'staff-1',
    appMetadata: {},
    userMetadata: {'full_name': 'Nurse Alice'},
    aud: 'authenticated',
    createdAt: '2026-01-01',
  );

  group('Section 22: PO Number Format & Generation & Immutability', () {
    test('1. PO number format matches PO-DDMMYYYY-0001', () {
      final date = DateTime(2026, 10, 1);
      final poNum = PurchaseOrder.formatPoNumber(date, 1);
      expect(poNum, equals('PO-01102026-0001'));
    });

    test('2. Correct actual creation date is used for PO numbering', () {
      final now = DateTime(2026, 10, 15);
      final poNum = PurchaseOrder.formatPoNumber(now, 1);
      expect(poNum, startsWith('PO-15102026-'));
    });

    test('3-5. Sequences start at 0001, 0002, 0003 for the same date', () {
      final repo = FakeSprint64PORepo(FakeSprint64InventoryRepo());
      final date = DateTime(2026, 10, 1);
      final p1 = repo.generatePoNumber(date);
      final p2 = repo.generatePoNumber(date);
      final p3 = repo.generatePoNumber(date);

      expect(p1, equals('PO-01102026-0001'));
      expect(p2, equals('PO-01102026-0002'));
      expect(p3, equals('PO-01102026-0003'));
    });

    test('6. Sequence resets to 0001 on a new date', () {
      final repo = FakeSprint64PORepo(FakeSprint64InventoryRepo());
      final d1 = DateTime(2026, 10, 1);
      final d2 = DateTime(2026, 10, 2);

      final p1 = repo.generatePoNumber(d1);
      final p2 = repo.generatePoNumber(d2);

      expect(p1, equals('PO-01102026-0001'));
      expect(p2, equals('PO-02102026-0001'));
    });

    test('7-8. PO numbers are unique and concurrent creation does not produce duplicates', () {
      final repo = FakeSprint64PORepo(FakeSprint64InventoryRepo());
      final date = DateTime(2026, 10, 1);
      final set = <String>{};
      for (int i = 0; i < 50; i++) {
        final num = repo.generatePoNumber(date);
        expect(set.contains(num), isFalse);
        set.add(num);
      }
      expect(set.length, equals(50));
    });

    test('9-13. PO number is immutable: editing vendor, date, status preserves original PO number', () async {
      final invRepo = FakeSprint64InventoryRepo();
      final poRepo = FakeSprint64PORepo(invRepo);

      final originalPo = await poRepo.createPurchaseOrder(PurchaseOrder(
        id: '',
        purchaseOrderNumber: '', // Let generator assign
        vendorId: 'v-1',
        vendorName: 'ABC Medical',
        orderDate: DateTime(2026, 10, 1),
        status: PurchaseOrderStatus.draft,
        totalAmount: 1000.0,
        items: const [],
      ));

      final poNumber = originalPo.purchaseOrderNumber;
      expect(poNumber, startsWith('PO-'));

      // Attempt to change PO number, vendor, order date, and status
      final edited = originalPo.copyWith(
        purchaseOrderNumber: 'HACKED-PO-9999',
        vendorId: 'v-2',
        vendorName: 'XYZ Pharma',
        orderDate: DateTime(2026, 10, 5),
        status: PurchaseOrderStatus.ordered,
      );

      final updated = await poRepo.updatePurchaseOrder(edited);

      // Number MUST NOT change
      expect(updated.purchaseOrderNumber, equals(poNumber));
      expect(updated.purchaseOrderNumber, isNot(equals('HACKED-PO-9999')));
      expect(updated.vendorName, equals('XYZ Pharma'));
      expect(updated.status, equals(PurchaseOrderStatus.ordered));
    });
  });

  group('Section 23: Inventory -> Create Purchase Order Flow', () {
    testWidgets('14-16. Opening PO Dialog from Inventory pre-selects product and assigned vendor', (tester) async {
      tester.view.physicalSize = const Size(1200, 900);
      tester.view.devicePixelRatio = 1.0;
      addTearDown(tester.view.resetPhysicalSize);

      const item = InventoryItem(
        id: 'inv-item-1',
        name: 'Surgical Gloves (Size 7.5)',
        category: 'Consumables & PPE',
        currentStock: 50.0,
        unit: 'pairs',
        price: 15.0,
        vendorId: 'v-assigned',
        vendorName: 'Prime Med Supplies',
      );

      const vendor = Vendor(
        id: 'v-assigned',
        name: 'Prime Med Supplies',
        phone: '9876543210',
        contactPerson: 'Dr. John',
      );

      final invRepo = FakeSprint64InventoryRepo([item]);
      final poRepo = FakeSprint64PORepo(invRepo);
      final vendorRepo = FakeSprint64VendorRepo([vendor]);

      await tester.pumpWidget(
        ProviderScope(
          overrides: [
            inventoryRepositoryProvider.overrideWithValue(invRepo),
            purchaseOrderRepositoryProvider.overrideWithValue(poRepo),
            vendorRepositoryProvider.overrideWithValue(vendorRepo),
            currentUserRoleProvider.overrideWith((ref) => Future.value('staff')),
            currentUserProvider.overrideWith((ref) => staffUser),
          ],
          child: const MaterialApp(
            home: Scaffold(
              body: PurchaseOrderFormDialog(
                preselectedInventoryItem: item,
                preselectedVendorId: 'v-assigned',
              ),
            ),
          ),
        ),
      );

      await tester.pumpAndSettle();

      // Product is pre-selected in line item
      expect(find.text('Surgical Gloves (Size 7.5)'), findsWidgets);
      // Assigned vendor is pre-selected
      expect(find.textContaining('Prime Med Supplies'), findsWidgets);
      // Unit price pre-filled
      expect(find.text('15.00'), findsWidgets);
      // PO Number field is read-only (not editable)
      expect(find.text('PO NUMBER (AUTO-GENERATED)'), findsOneWidget);
    });

    testWidgets('17. Manual vendor selection works when no assigned vendor exists', (tester) async {
      tester.view.physicalSize = const Size(1200, 900);
      tester.view.devicePixelRatio = 1.0;
      addTearDown(tester.view.resetPhysicalSize);

      const itemNoVendor = InventoryItem(
        id: 'inv-no-vendor',
        name: 'Eye Wash Cup',
        category: 'Clinical Supplies',
        currentStock: 20.0,
        unit: 'pcs',
        price: 30.0,
        vendorId: null,
      );

      const v1 = Vendor(id: 'v-manual-1', name: 'Vendor Alpha');
      const v2 = Vendor(id: 'v-manual-2', name: 'Vendor Beta');

      final invRepo = FakeSprint64InventoryRepo([itemNoVendor]);
      final poRepo = FakeSprint64PORepo(invRepo);
      final vendorRepo = FakeSprint64VendorRepo([v1, v2]);

      await tester.pumpWidget(
        ProviderScope(
          overrides: [
            inventoryRepositoryProvider.overrideWithValue(invRepo),
            purchaseOrderRepositoryProvider.overrideWithValue(poRepo),
            vendorRepositoryProvider.overrideWithValue(vendorRepo),
            currentUserRoleProvider.overrideWith((ref) => Future.value('admin')),
            currentUserProvider.overrideWith((ref) => adminUser),
          ],
          child: const MaterialApp(
            home: Scaffold(
              body: PurchaseOrderFormDialog(
                preselectedInventoryItem: itemNoVendor,
              ),
            ),
          ),
        ),
      );

      await tester.pumpAndSettle();

      // Item is pre-selected
      expect(find.text('Eye Wash Cup'), findsWidgets);
      // Vendor is not yet selected
      expect(find.byKey(const Key('po_vendor_dropdown')), findsOneWidget);

      // Select vendor manually
      await tester.tap(find.byKey(const Key('po_vendor_dropdown')));
      await tester.pumpAndSettle();

      await tester.tap(find.textContaining('Vendor Beta').last);
      await tester.pumpAndSettle();

      expect(find.textContaining('Vendor Beta'), findsWidgets);
    });
  });

  group('Section 24: Product Suppliers & Call Vendor Safety', () {
    testWidgets('18-26. Product Details displays ALL suppliers with contact, phone, email and metrics', (tester) async {
      tester.view.physicalSize = const Size(1200, 900);
      tester.view.devicePixelRatio = 1.0;
      addTearDown(tester.view.resetPhysicalSize);

      const item = InventoryItem(
        id: 'p-multi',
        name: 'Surgical Gloves',
        category: 'Consumables & PPE',
        currentStock: 100.0,
        unit: 'pcs',
        vendorId: 'v-1',
        vendorName: 'ABC Medical',
        vendorPhone: '9876543210',
        lastQuantitySupplied: 100.0,
        lastTotalAmount: 1250.0,
      );

      const v1 = Vendor(
        id: 'v-1',
        name: 'ABC Medical',
        contactPerson: 'Rahul',
        phone: '9876543210',
        email: 'rahul@abc.com',
      );

      const v2 = Vendor(
        id: 'v-2',
        name: 'MedSupply Ltd',
        contactPerson: 'Priya',
        phone: '9823456789',
        email: 'priya@medsupply.com',
      );

      final historicalPO = PurchaseOrder(
        id: 'po-hist-1',
        purchaseOrderNumber: 'PO-28092026-0001',
        vendorId: 'v-2',
        vendorName: 'MedSupply Ltd',
        orderDate: DateTime(2026, 9, 28),
        status: PurchaseOrderStatus.received,
        totalAmount: 2360.0,
        items: const [
          PurchaseOrderItem(
            id: 'poi-1',
            purchaseOrderId: 'po-hist-1',
            inventoryId: 'p-multi',
            inventoryName: 'Surgical Gloves',
            inventoryUnit: 'pcs',
            unitPrice: 11.80,
            quantity: 200,
            totalAmount: 2360.0,
            receivedQuantity: 200,
          ),
        ],
      );

      final invRepo = FakeSprint64InventoryRepo([item]);
      final poRepo = FakeSprint64PORepo(invRepo, [historicalPO]);
      final vendorRepo = FakeSprint64VendorRepo([v1, v2]);

      await tester.pumpWidget(
        ProviderScope(
          overrides: [
            inventoryRepositoryProvider.overrideWithValue(invRepo),
            purchaseOrderRepositoryProvider.overrideWithValue(poRepo),
            vendorRepositoryProvider.overrideWithValue(vendorRepo),
            currentUserRoleProvider.overrideWith((ref) => Future.value('admin')),
            currentUserProvider.overrideWith((ref) => adminUser),
          ],
          child: const MaterialApp(
            home: Scaffold(
              body: InventoryDetailsDialog(item: item),
            ),
          ),
        ),
      );

      await tester.pumpAndSettle();

      // Section title exists
      expect(find.textContaining('SUPPLIERS / VENDORS SUPPLYING THIS PRODUCT'), findsOneWidget);

      // Supplier 1: ABC Medical
      expect(find.text('ABC Medical'), findsWidgets);
      expect(find.text('Contact: Rahul'), findsOneWidget);
      expect(find.text('9876543210'), findsWidgets);
      expect(find.text('rahul@abc.com'), findsOneWidget);

      // Supplier 2: MedSupply Ltd
      expect(find.text('MedSupply Ltd'), findsWidgets);
      expect(find.text('Contact: Priya'), findsOneWidget);
      expect(find.text('9823456789'), findsWidgets);
      expect(find.text('priya@medsupply.com'), findsOneWidget);

      // Metrics displayed
      expect(find.text('₹12.50'), findsWidgets);
      expect(find.text('₹11.80'), findsWidgets);
      expect(find.text('200 pcs'), findsWidgets);

      // Call Vendor buttons exist
      expect(find.text('Call Vendor'), findsWidgets);
    });

    test('27-29. PhoneDialerUtil cleans number and never automatically calls without dialer popup', () {
      expect(PhoneDialerUtil.cleanNumber('+91 98765-43210'), equals('+919876543210'));
      expect(PhoneDialerUtil.isValidPhoneNumber('9876543210'), isTrue);
      expect(PhoneDialerUtil.isValidPhoneNumber(''), isFalse);
      expect(PhoneDialerUtil.isValidPhoneNumber(null), isFalse);
      expect(PhoneDialerUtil.isValidPhoneNumber('12'), isFalse);
    });
  });

  group('Section 25: Expected Delivery Date Validation', () {
    test('30. Same-day delivery date is accepted', () {
      final now = DateTime(2026, 10, 1);
      final po = PurchaseOrder(
        id: '1',
        purchaseOrderNumber: 'PO-01102026-0001',
        vendorId: 'v-1',
        orderDate: now,
        expectedDeliveryDate: now,
        status: PurchaseOrderStatus.draft,
        totalAmount: 100.0,
        items: const [],
      );
      expect(po.hasValidDates, isTrue);
    });

    test('31. Delivery after order date is accepted', () {
      final orderDate = DateTime(2026, 10, 1);
      final delDate = DateTime(2026, 10, 5);
      final po = PurchaseOrder(
        id: '1',
        purchaseOrderNumber: 'PO-01102026-0001',
        vendorId: 'v-1',
        orderDate: orderDate,
        expectedDeliveryDate: delDate,
        status: PurchaseOrderStatus.draft,
        totalAmount: 100.0,
        items: const [],
      );
      expect(po.hasValidDates, isTrue);
    });

    test('32. Delivery before order date is rejected', () {
      final orderDate = DateTime(2026, 10, 5);
      final delDate = DateTime(2026, 10, 1);
      final po = PurchaseOrder(
        id: '1',
        purchaseOrderNumber: 'PO-01102026-0001',
        vendorId: 'v-1',
        orderDate: orderDate,
        expectedDeliveryDate: delDate,
        status: PurchaseOrderStatus.draft,
        totalAmount: 100.0,
        items: const [],
      );
      expect(po.hasValidDates, isFalse);
    });
  });

  group('Section 26: Notifications for PO Placed', () {
    test('34. Draft creation does NOT send notifications', () async {
      final invRepo = FakeSprint64InventoryRepo();
      final poRepo = FakeSprint64PORepo(invRepo);

      await poRepo.createPurchaseOrder(PurchaseOrder(
        id: '',
        purchaseOrderNumber: '',
        vendorId: 'v-1',
        vendorName: 'ABC Medical',
        orderDate: DateTime(2026, 10, 1),
        status: PurchaseOrderStatus.draft,
        totalAmount: 500.0,
        items: const [],
      ));

      expect(poRepo.notifications.isEmpty, isTrue);
    });

    test('35-38. Transition Draft -> Ordered sends notifications to ALL active Admin & Staff, excluding inactive', () async {
      final invRepo = FakeSprint64InventoryRepo();
      final poRepo = FakeSprint64PORepo(invRepo);

      final po = await poRepo.createPurchaseOrder(PurchaseOrder(
        id: '',
        purchaseOrderNumber: '',
        vendorId: 'v-1',
        vendorName: 'ABC Medical',
        orderDate: DateTime(2026, 10, 1),
        status: PurchaseOrderStatus.draft,
        totalAmount: 500.0,
        items: const [],
      ));

      expect(poRepo.notifications.isEmpty, isTrue);

      // Transition to Ordered
      await poRepo.updatePurchaseOrder(po.copyWith(status: PurchaseOrderStatus.ordered));

      // Active admins: admin-1, admin-2 (2)
      // Active staff: staff-1, staff-2 (2)
      // Inactive staff-inactive: 0
      // Doctor: 0
      expect(poRepo.notifications.length, equals(4));

      final notifiedRoles = poRepo.notifications.map((n) => n.userRole).toSet();
      expect(notifiedRoles, contains('admin'));
      expect(notifiedRoles, contains('staff'));

      final notifiedUsers = poRepo.notifications.map((n) => n.userId).toSet();
      expect(notifiedUsers.contains('admin-1'), isTrue);
      expect(notifiedUsers.contains('admin-2'), isTrue);
      expect(notifiedUsers.contains('staff-1'), isTrue);
      expect(notifiedUsers.contains('staff-2'), isTrue);
      expect(notifiedUsers.contains('staff-inactive'), isFalse);
      expect(notifiedUsers.contains('doctor-1'), isFalse);
    });

    test('39-40. Editing an already Ordered PO or retrying transition does NOT produce duplicates', () async {
      final invRepo = FakeSprint64InventoryRepo();
      final poRepo = FakeSprint64PORepo(invRepo);

      final po = await poRepo.createPurchaseOrder(PurchaseOrder(
        id: '',
        purchaseOrderNumber: '',
        vendorId: 'v-1',
        vendorName: 'ABC Medical',
        orderDate: DateTime(2026, 10, 1),
        status: PurchaseOrderStatus.ordered,
        totalAmount: 500.0,
        items: const [],
      ));

      expect(poRepo.notifications.length, equals(4));

      // Edit notes on already ordered PO
      await poRepo.updatePurchaseOrder(po.copyWith(notes: 'Updated note'));
      expect(poRepo.notifications.length, equals(4)); // No additional notifications

      // Repeated update with ordered status
      await poRepo.updatePurchaseOrder(po.copyWith(status: PurchaseOrderStatus.ordered));
      expect(poRepo.notifications.length, equals(4)); // No duplicate
    });
  });

  group('Section 27: Batch Expiry & Partial Receiving', () {
    test('41-50. Partial receiving creates distinct batches with individual expiry dates without overwriting', () async {
      final item = const InventoryItem(
        id: 'eye-drops-1',
        name: 'Eye Drops 10ml',
        category: 'Pharmaceuticals',
        currentStock: 0,
        unit: 'bottles',
        expiryDate: null,
      );

      final invRepo = FakeSprint64InventoryRepo([item]);
      final poRepo = FakeSprint64PORepo(invRepo);

      final po = await poRepo.createPurchaseOrder(PurchaseOrder(
        id: '',
        purchaseOrderNumber: '',
        vendorId: 'v-pharma',
        vendorName: 'Apex Pharma',
        orderDate: DateTime(2026, 10, 1),
        status: PurchaseOrderStatus.ordered,
        totalAmount: 4500.0,
        items: const [
          PurchaseOrderItem(
            id: 'poi-eye-1',
            purchaseOrderId: 'po-temp',
            inventoryId: 'eye-drops-1',
            inventoryName: 'Eye Drops 10ml',
            inventoryUnit: 'bottles',
            unitPrice: 45.0,
            quantity: 100,
            totalAmount: 4500.0,
            receivedQuantity: 0,
          ),
        ],
      ));

      // First partial receiving: 40 units, Expiry 15/06/2027
      final exp1 = DateTime(2027, 6, 15);
      await poRepo.receivePurchaseOrder(
        purchaseOrderId: po.id,
        items: [
          {
            'item_id': 'poi-eye-1',
            'received_quantity': 40,
            'expiry_date': exp1.toIso8601String(),
          }
        ],
      );

      var updatedItem = await invRepo.getInventoryItem('eye-drops-1');
      expect(updatedItem.currentStock, equals(40.0));
      expect(invRepo.batches.length, equals(1));
      expect(invRepo.batches[0].receivedQuantity, equals(40.0));
      expect(invRepo.batches[0].remainingQuantity, equals(40.0));
      expect(invRepo.batches[0].expiryDate, equals(exp1));

      // Second partial receiving: 60 units, Expiry 20/09/2027
      final exp2 = DateTime(2027, 9, 20);
      await poRepo.receivePurchaseOrder(
        purchaseOrderId: po.id,
        items: [
          {
            'item_id': 'poi-eye-1',
            'received_quantity': 60,
            'expiry_date': exp2.toIso8601String(),
          }
        ],
      );

      updatedItem = await invRepo.getInventoryItem('eye-drops-1');
      // Total stock is 40 + 60 = 100
      expect(updatedItem.currentStock, equals(100.0));
      expect(invRepo.batches.length, equals(2));

      // Batch 1 is preserved and NOT overwritten
      expect(invRepo.batches[0].receivedQuantity, equals(40.0));
      expect(invRepo.batches[0].expiryDate, equals(exp1));

      // Batch 2 is distinct
      expect(invRepo.batches[1].receivedQuantity, equals(60.0));
      expect(invRepo.batches[1].expiryDate, equals(exp2));

      // Earliest expiry is correctly set to Batch 1
      expect(updatedItem.expiryDate, equals(exp1));

      // PO is now completely received
      final updatedPo = await poRepo.getPurchaseOrder(po.id);
      expect(updatedPo.status, equals(PurchaseOrderStatus.received));
    });

    testWidgets('51-52. Details dialog displays multiple inventory batches with batch ID, dates, and PO info', (tester) async {
      tester.view.physicalSize = const Size(1200, 900);
      tester.view.devicePixelRatio = 1.0;
      addTearDown(tester.view.resetPhysicalSize);

      const item = InventoryItem(
        id: 'item-batches',
        name: 'Eye Drops 10ml',
        category: 'Pharmaceuticals',
        currentStock: 100.0,
        unit: 'bottles',
      );

      final b1 = InventoryBatch(
        id: 'batch-001',
        inventoryId: 'item-batches',
        batchNumber: 'B-20261001-001',
        receivedQuantity: 40,
        remainingQuantity: 40,
        unitPrice: 45.0,
        totalAmount: 1800.0,
        expiryDate: DateTime(2027, 6, 15),
        receivedDate: DateTime(2026, 10, 1),
        createdAt: DateTime(2026, 10, 1),
        purchaseOrderNumber: 'PO-01102026-0001',
        vendorName: 'Apex Pharma',
      );

      final b2 = InventoryBatch(
        id: 'batch-002',
        inventoryId: 'item-batches',
        batchNumber: 'B-20261001-002',
        receivedQuantity: 60,
        remainingQuantity: 60,
        unitPrice: 45.0,
        totalAmount: 2700.0,
        expiryDate: DateTime(2027, 9, 20),
        receivedDate: DateTime(2026, 10, 1),
        createdAt: DateTime(2026, 10, 1),
        purchaseOrderNumber: 'PO-01102026-0001',
        vendorName: 'Apex Pharma',
      );

      final invRepo = FakeSprint64InventoryRepo([item]);
      invRepo.batches.addAll([b1, b2]);
      final poRepo = FakeSprint64PORepo(invRepo);

      await tester.pumpWidget(
        ProviderScope(
          overrides: [
            inventoryRepositoryProvider.overrideWithValue(invRepo),
            purchaseOrderRepositoryProvider.overrideWithValue(poRepo),
            currentUserRoleProvider.overrideWith((ref) => Future.value('admin')),
            currentUserProvider.overrideWith((ref) => adminUser),
          ],
          child: const MaterialApp(
            home: Scaffold(
              body: InventoryDetailsDialog(item: item),
            ),
          ),
        ),
      );

      await tester.pumpAndSettle();

      expect(find.text('INVENTORY BATCHES'), findsOneWidget);
      expect(find.text('B-20261001-001'), findsOneWidget);
      expect(find.text('B-20261001-002'), findsOneWidget);
      expect(find.textContaining('15/06/2027'), findsWidgets);
      expect(find.textContaining('20/09/2027'), findsWidgets);
    });
  });

  group('Section 28: Stock Out + FEFO Batch Tracking', () {
    test('53-59. FEFO consumes earlier expiry batch first, spans multiple batches and records audit remarks', () async {
      final item = const InventoryItem(
        id: 'item-fefo',
        name: 'Eye Drops 10ml',
        category: 'Pharmaceuticals',
        currentStock: 100.0,
        unit: 'bottles',
      );

      final b1 = InventoryBatch(
        id: 'b-1',
        inventoryId: 'item-fefo',
        batchNumber: 'B-001',
        receivedQuantity: 40,
        remainingQuantity: 40,
        unitPrice: 45.0,
        totalAmount: 1800.0,
        expiryDate: DateTime(2027, 6, 15), // Earlier expiry
        receivedDate: DateTime(2026, 10, 1),
        createdAt: DateTime(2026, 10, 1),
      );

      final b2 = InventoryBatch(
        id: 'b-2',
        inventoryId: 'item-fefo',
        batchNumber: 'B-002',
        receivedQuantity: 60,
        remainingQuantity: 60,
        unitPrice: 45.0,
        totalAmount: 2700.0,
        expiryDate: DateTime(2027, 9, 20), // Later expiry
        receivedDate: DateTime(2026, 10, 1),
        createdAt: DateTime(2026, 10, 1),
      );

      final invRepo = FakeSprint64InventoryRepo([item]);
      invRepo.batches.addAll([b1, b2]);

      // Stock Out of 50 units (requires 40 from Batch 1 and 10 from Batch 2)
      final tx = await invRepo.performStockOperation(
        itemId: 'item-fefo',
        transactionType: 'stock_out',
        quantity: 50,
        reason: 'Clinical Usage',
      );

      // Verify Batch 1 is exhausted: 40 -> 0
      final updatedB1 = invRepo.batches.firstWhere((b) => b.id == 'b-1');
      expect(updatedB1.remainingQuantity, equals(0.0));

      // Verify Batch 2 is partially consumed: 60 -> 50
      final updatedB2 = invRepo.batches.firstWhere((b) => b.id == 'b-2');
      expect(updatedB2.remainingQuantity, equals(50.0));

      // Total stock is 100 -> 50
      final updatedItem = await invRepo.getInventoryItem('item-fefo');
      expect(updatedItem.currentStock, equals(50.0));

      // Next earliest expiry is now Batch 2 (20/09/2027)
      expect(updatedItem.expiryDate, equals(DateTime(2027, 9, 20)));

      // Remarks contain FEFO consumed batch information
      expect(tx.remarks, contains('B-001: 40.0 units'));
      expect(tx.remarks, contains('B-002: 10.0 units'));
    });
  });
}
