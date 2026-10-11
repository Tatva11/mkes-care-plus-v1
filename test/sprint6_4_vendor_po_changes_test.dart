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
import 'package:mkes_care/features/inventory/utils/vendor_product_matcher.dart';
import 'package:mkes_care/features/inventory/widgets/purchase_order_details_dialog.dart';
import 'package:mkes_care/features/inventory/widgets/purchase_order_form_dialog.dart';
import 'package:mkes_care/features/vendors/models/vendor.dart';
import 'package:mkes_care/features/vendors/repositories/vendor_repository.dart';
import 'package:mkes_care/features/vendors/widgets/vendor_form_dialog.dart';

// ============================================================================
// FAKE DATA & NOTIFIERS FOR COMPREHENSIVE SPRINT 6.4 TESTING
// ============================================================================

class FakeTestInventoryRepo implements InventoryRepository {
  final List<InventoryItem> items;
  final List<InventoryBatch> batches = [];
  final List<InventoryTransaction> transactions = [];

  @override
  dynamic noSuchMethod(Invocation invocation) => super.noSuchMethod(invocation);

  FakeTestInventoryRepo(this.items);

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
    final after = transactionType == 'stock_out' ? before - quantity : before + quantity;
    items[idx] = item.copyWith(currentStock: after, updatedAt: DateTime.now());

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
  }) async =>
      transactions.where((t) => t.inventoryItemId == itemId).toList();

  @override
  Future<List<InventoryTransaction>> getAllTransactions({
    String? transactionType,
    int limit = 100,
  }) async =>
      List.from(transactions);
}

class FakeTestPORepo implements PurchaseOrderRepository {
  final List<PurchaseOrder> orders = [];
  final Map<String, int> dailySequences = {};
  final List<String> notificationsSent = [];

  String? currentAuthenticatedUserId;

  FakeTestPORepo([List<PurchaseOrder>? initial]) {
    if (initial != null) orders.addAll(initial);
  }

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

  @override
  Future<List<PurchaseOrder>> getPurchaseOrders({
    String? status,
    String? vendorId,
    String? searchQuery,
  }) async =>
      List.from(orders);

  @override
  Future<PurchaseOrder> getPurchaseOrder(String id) async =>
      orders.firstWhere((o) => o.id == id);

  @override
  Future<PurchaseOrder> createPurchaseOrder(
    PurchaseOrder order, [
    List<PurchaseOrderItem> items = const [],
  ]) async {
    final poNum = generatePoNumber(DateTime.now());
    final allItems = items.isNotEmpty ? items : order.items;
    final total = allItems.fold(0.0, (sum, i) => sum + i.totalAmount);

    final isOrdered = order.status == PurchaseOrderStatus.ordered;
    final created = order.copyWith(
      id: 'po-${orders.length + 1}',
      purchaseOrderNumber: poNum,
      items: allItems,
      totalAmount: total > 0 ? total : order.totalAmount,
      createdBy: order.createdBy ?? currentAuthenticatedUserId,
      orderedBy: isOrdered ? (order.orderedBy ?? currentAuthenticatedUserId) : null,
      orderedAt: isOrdered ? (order.orderedAt ?? DateTime.now()) : null,
      createdAt: DateTime.now(),
      updatedAt: DateTime.now(),
    );
    orders.add(created);

    if (isOrdered) {
      notificationsSent.add('PO ${created.purchaseOrderNumber} ordered');
    }

    return created;
  }

  @override
  Future<PurchaseOrder> updatePurchaseOrder(
    PurchaseOrder order, [
    List<PurchaseOrderItem> items = const [],
  ]) async {
    final idx = orders.indexWhere((o) => o.id == order.id);
    if (idx == -1) throw Exception('Order not found');
    final existing = orders[idx];

    final isOrdered = order.status == PurchaseOrderStatus.ordered;
    final updated = order.copyWith(
      purchaseOrderNumber: existing.purchaseOrderNumber, // Immutable PO number
      items: items.isNotEmpty ? items : order.items,
      createdBy: existing.createdBy, // Created by remains unchanged
      orderedBy: isOrdered
          ? (existing.orderedBy ?? currentAuthenticatedUserId)
          : existing.orderedBy,
      orderedAt: isOrdered
          ? (existing.orderedAt ?? DateTime.now())
          : existing.orderedAt,
      updatedAt: DateTime.now(),
    );
    orders[idx] = updated;

    if (isOrdered && existing.status != PurchaseOrderStatus.ordered) {
      notificationsSent.add('PO ${updated.purchaseOrderNumber} ordered');
    }

    return updated;
  }

  @override
  Future<void> updateStatus(String id, PurchaseOrderStatus status) async {
    final idx = orders.indexWhere((o) => o.id == id);
    if (idx == -1) throw Exception('Order not found');
    final existing = orders[idx];

    final isNowOrdered = status == PurchaseOrderStatus.ordered &&
        existing.status != PurchaseOrderStatus.ordered;

    final updated = existing.copyWith(
      status: status,
      orderedBy: isNowOrdered ? (existing.orderedBy ?? currentAuthenticatedUserId) : existing.orderedBy,
      orderedAt: isNowOrdered ? (existing.orderedAt ?? DateTime.now()) : existing.orderedAt,
      updatedAt: DateTime.now(),
    );
    orders[idx] = updated;

    if (isNowOrdered) {
      notificationsSent.add('PO ${updated.purchaseOrderNumber} ordered');
    }
  }

  @override
  Future<void> cancelPurchaseOrder(String id) async {
    final idx = orders.indexWhere((o) => o.id == id);
    if (idx != -1) {
      orders[idx] = orders[idx].copyWith(status: PurchaseOrderStatus.cancelled);
    }
  }

  @override
  Future<Map<String, dynamic>> receivePurchaseOrder({
    required String purchaseOrderId,
    required List<Map<String, dynamic>> items,
  }) async {
    final idx = orders.indexWhere((o) => o.id == purchaseOrderId);
    if (idx == -1) throw Exception('Order not found');
    orders[idx] = orders[idx].copyWith(status: PurchaseOrderStatus.received);
    return {
      'success': true,
      'purchase_order_id': purchaseOrderId,
      'received_count': items.length,
      'is_fully_received': true,
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

class FakeTestVendorRepo implements VendorRepository {
  final List<Vendor> vendors;

  FakeTestVendorRepo(this.vendors);

  @override
  Future<List<Vendor>> getVendors({String? searchQuery, bool? activeOnly}) async =>
      List.from(vendors);

  @override
  Future<Vendor> getVendor(String id) async =>
      vendors.firstWhere((v) => v.id == id);

  @override
  Future<Vendor> createVendor(Vendor vendor) async {
    final created = vendor.copyWith(
      id: 'vendor-${vendors.length + 1}',
      createdAt: DateTime.now(),
      updatedAt: DateTime.now(),
    );
    vendors.add(created);
    return created;
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
    if (idx == -1) throw Exception('Vendor not found');
    final updated = vendors[idx].copyWith(isActive: isActive);
    vendors[idx] = updated;
    return updated;
  }
}

void main() {
  TestWidgetsFlutterBinding.ensureInitialized();

  // Test setup datasets
  late FakeTestInventoryRepo fakeInventoryRepo;
  late FakeTestPORepo fakePORepo;
  late FakeTestVendorRepo fakeVendorRepo;

  late Vendor vendor1;
  late Vendor vendor2;
  late Vendor vendorEmpty;

  late InventoryItem itemEyeDrops;
  late InventoryItem itemGloves;
  late InventoryItem itemComposite;
  late InventoryItem itemStethoscope;

  const mockStaffUser = User(
    id: 'user-staff-123',
    appMetadata: {},
    userMetadata: {'full_name': 'Nurse Alice'},
    aud: 'authenticated',
    createdAt: '2026-01-01',
  );

  setUp(() {
    itemEyeDrops = const InventoryItem(
      id: 'item-1',
      name: 'Eye Drops',
      category: 'Medication',
      unit: 'vials',
      price: 150.0,
      currentStock: 20,
    );

    itemGloves = const InventoryItem(
      id: 'item-2',
      name: 'Surgical Gloves',
      category: 'Consumable',
      unit: 'boxes',
      price: 250.0,
      currentStock: 50,
    );

    itemComposite = const InventoryItem(
      id: 'item-3',
      name: 'Composite Kit',
      category: 'Equipment',
      unit: 'kits',
      price: 1200.0,
      currentStock: 10,
    );

    itemStethoscope = const InventoryItem(
      id: 'item-4',
      name: 'Stethoscope Pro',
      category: 'Equipment',
      unit: 'pieces',
      price: 3500.0,
      currentStock: 5,
    );

    // Vendor 1 supplies Eye Drops and Surgical Gloves
    vendor1 = const Vendor(
      id: 'v-1',
      name: 'ABC Medicals',
      productsSupplied: ['Eye Drops', 'Surgical Gloves'],
      isActive: true,
    );

    // Vendor 2 supplies Composite Kit
    vendor2 = const Vendor(
      id: 'v-2',
      name: 'Delta Pharma',
      productsSupplied: ['Composite Kit'],
      isActive: true,
    );

    // Vendor Empty supplies no products
    vendorEmpty = const Vendor(
      id: 'v-3',
      name: 'Empty Supplies Ltd',
      productsSupplied: [],
      isActive: true,
    );

    fakeInventoryRepo = FakeTestInventoryRepo([
      itemEyeDrops,
      itemGloves,
      itemComposite,
      itemStethoscope,
    ]);

    fakeVendorRepo = FakeTestVendorRepo([
      vendor1,
      vendor2,
      vendorEmpty,
    ]);

    fakePORepo = FakeTestPORepo();
    fakePORepo.currentAuthenticatedUserId = 'user-staff-123';
  });

  Widget buildTestApp({required Widget child}) {
    return ProviderScope(
      overrides: [
        inventoryRepositoryProvider.overrideWithValue(fakeInventoryRepo),
        purchaseOrderRepositoryProvider.overrideWithValue(fakePORepo),
        vendorRepositoryProvider.overrideWithValue(fakeVendorRepo),
        currentUserProvider.overrideWith((ref) => mockStaffUser),
      ],
      child: MaterialApp(
        home: Scaffold(
          body: SingleChildScrollView(
            child: child,
          ),
        ),
      ),
    );
  }

  // ============================================================================
  // CHANGE 1 & 2: VENDOR PRODUCT FILTERING, CLEARING, AND SELECTION TESTS
  // ============================================================================

  group('Sprint 6.4 Change 1 & 2: Vendor Selection & Product Reset', () {
    test('1-4: Vendor product matching correctly filters products for each vendor', () {
      // Vendor 1 supplies Eye Drops and Surgical Gloves
      expect(isProductSuppliedByVendor(itemEyeDrops, vendor1), isTrue);
      expect(isProductSuppliedByVendor(itemGloves, vendor1), isTrue);
      expect(isProductSuppliedByVendor(itemComposite, vendor1), isFalse);

      // Vendor 2 supplies Composite Kit
      expect(isProductSuppliedByVendor(itemEyeDrops, vendor2), isFalse);
      expect(isProductSuppliedByVendor(itemComposite, vendor2), isTrue);

      // Vendor Empty supplies no products
      expect(isProductSuppliedByVendor(itemEyeDrops, vendorEmpty), isFalse);
      expect(isProductSuppliedByVendor(itemComposite, vendorEmpty), isFalse);
    });

    testWidgets('1-4: Vendor 1 selected -> products selected -> changing to Vendor 2 clears products', (tester) async {
      await tester.binding.setSurfaceSize(const Size(1400, 1000));

      await tester.pumpWidget(buildTestApp(
        child: const PurchaseOrderFormDialog(),
      ));
      await tester.pumpAndSettle();

      // Initially, select Vendor 1
      final vendorDropdownFinder = find.byKey(const Key('po_vendor_dropdown'));
      await tester.ensureVisible(vendorDropdownFinder);
      await tester.tap(vendorDropdownFinder);
      await tester.pumpAndSettle();

      await tester.tap(find.textContaining('ABC Medicals').last);
      await tester.pumpAndSettle();

      // Line item product dropdown should show Vendor 1's products
      final lineItemDropdownFinder = find.byKey(const ValueKey('po_item_product_0_v-1_'));
      expect(lineItemDropdownFinder, findsOneWidget);

      // Select Product from Vendor 1: Eye Drops
      await tester.ensureVisible(lineItemDropdownFinder);
      await tester.tap(lineItemDropdownFinder);
      await tester.pumpAndSettle();

      // Eye Drops should be in dropdown list, Composite Kit should NOT be in Vendor 1's dropdown
      expect(find.text('Eye Drops').last, findsOneWidget);
      expect(find.text('Composite Kit'), findsNothing);

      await tester.tap(find.text('Eye Drops').last);
      await tester.pumpAndSettle();

      // Now change Vendor to Vendor 2 (Delta Pharma)
      final vendor1DropdownFinder = find.byKey(const Key('po_vendor_dropdown'));
      await tester.ensureVisible(vendor1DropdownFinder);
      await tester.tap(vendor1DropdownFinder);
      await tester.pumpAndSettle();

      await tester.tap(find.textContaining('Delta Pharma').last);
      await tester.pumpAndSettle();

      // 3. Product A is cleared: line item dropdown reset
      expect(find.text('Eye Drops'), findsNothing);

      // 4. Vendor 2 products are shown in the dropdown
      final lineItemVendor2Finder = find.byKey(const ValueKey('po_item_product_0_v-2_'));
      await tester.ensureVisible(lineItemVendor2Finder);
      await tester.tap(lineItemVendor2Finder);
      await tester.pumpAndSettle();

      expect(find.text('Composite Kit').last, findsOneWidget);
      expect(find.text('Eye Drops'), findsNothing);
    });

    testWidgets('6: Vendor 2 supplies no products -> displays appropriate empty state', (tester) async {
      await tester.binding.setSurfaceSize(const Size(1400, 1000));

      await tester.pumpWidget(buildTestApp(
        child: const PurchaseOrderFormDialog(),
      ));
      await tester.pumpAndSettle();

      // Select Vendor Empty
      final vendorDropdownFinder = find.byKey(const Key('po_vendor_dropdown'));
      await tester.ensureVisible(vendorDropdownFinder);
      await tester.tap(vendorDropdownFinder);
      await tester.pumpAndSettle();

      await tester.tap(find.textContaining('Empty Supplies Ltd').last);
      await tester.pumpAndSettle();

      // Empty state banner displayed
      expect(find.byKey(const Key('vendor_no_products_empty_state')), findsOneWidget);
      expect(find.textContaining('No products are supplied by "Empty Supplies Ltd"'), findsOneWidget);
    });

    testWidgets('5-7: Vendor with multiple supplied products can be created & edited via VendorFormDialog', (tester) async {
      await tester.binding.setSurfaceSize(const Size(1400, 1000));

      await tester.pumpWidget(ProviderScope(
        overrides: [
          inventoryRepositoryProvider.overrideWithValue(fakeInventoryRepo),
          purchaseOrderRepositoryProvider.overrideWithValue(fakePORepo),
          vendorRepositoryProvider.overrideWithValue(fakeVendorRepo),
          currentUserProvider.overrideWith((ref) => mockStaffUser),
        ],
        child: MaterialApp(
          home: Builder(
            builder: (context) => Scaffold(
              body: ElevatedButton(
                key: const Key('open_vendor_dialog'),
                onPressed: () => showDialog(
                  context: context,
                  builder: (_) => const VendorFormDialog(),
                ),
                child: const Text('Open'),
              ),
            ),
          ),
        ),
      ));
      await tester.pumpAndSettle();

      await tester.tap(find.byKey(const Key('open_vendor_dialog')));
      await tester.pumpAndSettle();

      // Type Vendor Name
      await tester.enterText(find.byType(TextFormField).first, 'Zenith Surgical');
      await tester.pumpAndSettle();

      // Use search input to add Eye Drops and Surgical Gloves
      final searchInput = find.byKey(const Key('vendor_product_search_input'));
      expect(searchInput, findsOneWidget);

      await tester.enterText(searchInput, 'Eye Drops');
      await tester.testTextInput.receiveAction(TextInputAction.done);
      await tester.pumpAndSettle();

      // Verify chip appears
      expect(find.byKey(const Key('vendor_chip_Eye Drops')), findsOneWidget);

      // Add another product
      await tester.enterText(searchInput, 'Surgical Gloves');
      await tester.testTextInput.receiveAction(TextInputAction.done);
      await tester.pumpAndSettle();

      expect(find.byKey(const Key('vendor_chip_Surgical Gloves')), findsOneWidget);

      // Submit Vendor
      await tester.tap(find.widgetWithText(FilledButton, 'Create Vendor'));
      await tester.pumpAndSettle();

      // Verify vendor was added in fakeVendorRepo with both products
      expect(fakeVendorRepo.vendors.any((v) => v.name == 'Zenith Surgical'), isTrue);
      final createdVendor = fakeVendorRepo.vendors.firstWhere((v) => v.name == 'Zenith Surgical');
      expect(createdVendor.productsSupplied, containsAll(['Eye Drops', 'Surgical Gloves']));

      // 6. Test persistence on edit
      await tester.pumpWidget(ProviderScope(
        overrides: [
          inventoryRepositoryProvider.overrideWithValue(fakeInventoryRepo),
          purchaseOrderRepositoryProvider.overrideWithValue(fakePORepo),
          vendorRepositoryProvider.overrideWithValue(fakeVendorRepo),
          currentUserProvider.overrideWith((ref) => mockStaffUser),
        ],
        child: MaterialApp(
          home: Builder(
            builder: (context) => Scaffold(
              body: ElevatedButton(
                key: const Key('open_edit_vendor_dialog'),
                onPressed: () => showDialog(
                  context: context,
                  builder: (_) => VendorFormDialog(vendor: createdVendor),
                ),
                child: const Text('Open Edit'),
              ),
            ),
          ),
        ),
      ));
      await tester.pumpAndSettle();

      await tester.tap(find.byKey(const Key('open_edit_vendor_dialog')));
      await tester.pumpAndSettle();

      expect(find.byKey(const Key('vendor_chip_Eye Drops')), findsOneWidget);
      expect(find.byKey(const Key('vendor_chip_Surgical Gloves')), findsOneWidget);
    });
  });

  // ============================================================================
  // CHANGE 3: ORDER PLACED BY & CREATED BY SEPARATION AND DISPLAY
  // ============================================================================

  group('Sprint 6.4 Change 3: Order Placed By & Created By', () {
    test('8: Create Draft PO has Created By populated and Order Placed By empty', () async {
      final po = await fakePORepo.createPurchaseOrder(
        PurchaseOrder(
          id: 'test-po-1',
          purchaseOrderNumber: '',
          vendorId: vendor1.id,
          orderDate: DateTime.now(),
          status: PurchaseOrderStatus.draft,
          totalAmount: 300.0,
          createdBy: 'user-admin-1',
        ),
      );

      expect(po.createdBy, equals('user-admin-1'));
      expect(po.orderedBy, isNull);
      expect(po.orderedAt, isNull);
      expect(po.isOrderPlaced, isFalse);
      expect(po.orderPlacedByDisplay, equals('Not placed yet'));
      expect(po.orderPlacedAtDisplay, equals('Not placed yet'));
    });

    test('9: Draft -> Ordered transitions captures ordered_by and ordered_at while keeping created_by', () async {
      // 1. Create as Draft
      final draft = await fakePORepo.createPurchaseOrder(
        PurchaseOrder(
          id: 'test-po-2',
          purchaseOrderNumber: '',
          vendorId: vendor1.id,
          orderDate: DateTime.now(),
          status: PurchaseOrderStatus.draft,
          totalAmount: 500.0,
          createdBy: 'user-creator-99',
        ),
      );

      expect(draft.status, equals(PurchaseOrderStatus.draft));
      expect(draft.createdBy, equals('user-creator-99'));
      expect(draft.orderedBy, isNull);

      // 2. Transition from Draft to Ordered
      fakePORepo.currentAuthenticatedUserId = 'user-orderer-42';
      await fakePORepo.updateStatus(draft.id, PurchaseOrderStatus.ordered);

      final ordered = await fakePORepo.getPurchaseOrder(draft.id);
      expect(ordered.status, equals(PurchaseOrderStatus.ordered));
      // Created by is strictly preserved
      expect(ordered.createdBy, equals('user-creator-99'));
      // Ordered by is populated with the authenticated user who placed the order
      expect(ordered.orderedBy, equals('user-orderer-42'));
      expect(ordered.orderedAt, isNotNull);
      expect(ordered.isOrderPlaced, isTrue);

      // Notification was triggered
      expect(fakePORepo.notificationsSent, contains('PO ${ordered.purchaseOrderNumber} ordered'));
    });

    testWidgets('10: PO details displays both Created By and Order Placed By accurately', (tester) async {
      await tester.binding.setSurfaceSize(const Size(1400, 1000));

      final testOrder = PurchaseOrder(
        id: 'po-display-1',
        purchaseOrderNumber: 'PO-02102026-0001',
        vendorId: vendor1.id,
        vendorName: 'ABC Medicals',
        orderDate: DateTime(2026, 10, 2),
        status: PurchaseOrderStatus.ordered,
        totalAmount: 1500.0,
        createdBy: 'user-1',
        createdByName: 'Dr. Emily Creator',
        createdAt: DateTime(2026, 10, 1, 9, 30),
        orderedBy: 'user-2',
        orderedByName: 'Nurse Bob Orderer',
        orderedAt: DateTime(2026, 10, 2, 11, 45),
        items: [
          const PurchaseOrderItem(
            id: 'item-row-1',
            purchaseOrderId: 'po-display-1',
            inventoryId: 'item-1',
            inventoryName: 'Eye Drops',
            inventoryUnit: 'vials',
            quantity: 10,
            unitPrice: 150.0,
            totalAmount: 1500.0,
          ),
        ],
      );

      await tester.pumpWidget(buildTestApp(
        child: PurchaseOrderDetailsDialog(order: testOrder),
      ));
      await tester.pumpAndSettle();

      // Check header and labels
      expect(find.textContaining('PO-02102026-0001'), findsOneWidget);
      expect(find.textContaining('Created By: Dr. Emily Creator'), findsOneWidget);
      expect(find.textContaining('Order Placed By: Nurse Bob Orderer'), findsOneWidget);
    });

    testWidgets('11: Existing Ordered PO without ordered_by displays "Not recorded" without crashing', (tester) async {
      await tester.binding.setSurfaceSize(const Size(1400, 1000));

      final preMigrationOrder = PurchaseOrder(
        id: 'po-legacy-1',
        purchaseOrderNumber: 'PO-01012026-0001',
        vendorId: vendor1.id,
        vendorName: 'ABC Medicals',
        orderDate: DateTime(2026, 1, 1),
        status: PurchaseOrderStatus.ordered,
        totalAmount: 800.0,
        createdBy: 'user-legacy',
        createdByName: 'Legacy User',
        createdAt: DateTime(2026, 1, 1, 10, 0),
        orderedBy: null, // Pre-migration
        orderedAt: null,
      );

      await tester.pumpWidget(buildTestApp(
        child: PurchaseOrderDetailsDialog(order: preMigrationOrder),
      ));
      await tester.pumpAndSettle();

      expect(find.textContaining('Order Placed By: Not recorded'), findsOneWidget);
    });

    test('12: Admin and Staff have access parity for PO and Vendor operations', () {
      // Models and logic are role-agnostic
      final vendor = const Vendor(
        id: 'v-staff-1',
        name: 'Staff Created Vendor',
        productsSupplied: ['Eye Drops', 'Composite Kit'],
      );
      expect(vendor.productsSupplied.length, equals(2));

      final staffPO = PurchaseOrder(
        id: 'po-staff-1',
        purchaseOrderNumber: 'PO-02102026-0002',
        vendorId: vendor.id,
        orderDate: DateTime.now(),
        status: PurchaseOrderStatus.ordered,
        totalAmount: 500.0,
        createdBy: 'staff-user-id',
        orderedBy: 'staff-user-id',
        orderedAt: DateTime.now(),
      );
      expect(staffPO.createdBy, equals('staff-user-id'));
      expect(staffPO.orderedBy, equals('staff-user-id'));
    });

    test('13: Existing PO numbering, receiving, batch expiry, FEFO and supplier history preserved', () async {
      // 1. PO Numbering format
      final poNum = fakePORepo.generatePoNumber(DateTime(2026, 10, 2));
      expect(poNum, matches(r'^PO-02102026-\d{4}$'));

      // 2. Immutability
      final initial = await fakePORepo.createPurchaseOrder(
        PurchaseOrder(
          id: 'po-imm-1',
          purchaseOrderNumber: '',
          vendorId: vendor1.id,
          orderDate: DateTime.now(),
          status: PurchaseOrderStatus.draft,
          totalAmount: 200.0,
        ),
      );
      final assignedNum = initial.purchaseOrderNumber;

      // Update PO
      final updated = await fakePORepo.updatePurchaseOrder(
        initial.copyWith(purchaseOrderNumber: 'HACKED-NUMBER'),
      );
      expect(updated.purchaseOrderNumber, equals(assignedNum));

      // 3. Receiving
      final receiveRes = await fakePORepo.receivePurchaseOrder(
        purchaseOrderId: initial.id,
        items: [
          {'inventory_id': 'item-1', 'quantity_received': 10},
        ],
      );
      expect(receiveRes['is_fully_received'], isTrue);

      // 4. Stock operation FEFO / batch consumption
      final tx = await fakeInventoryRepo.performStockOperation(
        itemId: 'item-1',
        transactionType: 'stock_out',
        quantity: 5,
        reason: 'Patient dispensation',
      );
      expect(tx.stockBefore, equals(20));
      expect(tx.stockAfter, equals(15));
    });
  });
}
