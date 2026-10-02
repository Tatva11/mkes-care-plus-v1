import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:mkes_care/features/auth/providers/auth_provider.dart';
import 'package:mkes_care/features/inventory/models/inventory_batch.dart';
import 'package:mkes_care/features/inventory/models/inventory_item.dart';
import 'package:mkes_care/features/inventory/models/inventory_transaction.dart';
import 'package:mkes_care/features/inventory/repositories/inventory_repository.dart';
import 'package:mkes_care/features/inventory/utils/phone_dialer_util.dart';
import 'package:mkes_care/features/inventory/widgets/inventory_details_dialog.dart';
import 'package:mkes_care/features/inventory/widgets/stock_operation_dialog.dart';
import 'package:mkes_care/features/vendors/models/vendor.dart';
import 'package:mkes_care/features/vendors/repositories/vendor_repository.dart';
import 'package:mkes_care/features/vendors/widgets/vendor_details_dialog.dart';
import 'package:mkes_care/features/vendors/widgets/vendor_form_dialog.dart';

/// Fake repository for inventory operations with vendor and pricing persistence.
class FakeInventoryRepository implements InventoryRepository {
  final List<InventoryItem> items;
  final List<InventoryTransaction> transactions = [];

  FakeInventoryRepository([List<InventoryItem>? initial])
      : items = initial != null ? List.from(initial) : [];

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
    final created = item.copyWith(id: 'item-${items.length + 1}');
    items.add(created);
    return created;
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
    if (quantity <= 0) {
      throw ArgumentError('Quantity must be greater than zero.');
    }
    final idx = items.indexWhere((i) => i.id == itemId);
    if (idx == -1) throw Exception('Item not found');
    final item = items[idx];

    final double stockBefore = item.currentStock;
    final double stockAfter = transactionType == 'stock_in'
        ? stockBefore + quantity
        : stockBefore - quantity;

    final double? unitPrice = (totalAmount != null && quantity > 0)
        ? (totalAmount / quantity)
        : null;

    items[idx] = item.copyWith(
      currentStock: stockAfter,
      vendorId: vendorId ?? item.vendorId,
      lastQuantitySupplied: transactionType == 'stock_in' ? quantity : item.lastQuantitySupplied,
      lastTotalAmount: transactionType == 'stock_in' && totalAmount != null
          ? totalAmount
          : item.lastTotalAmount,
      updatedAt: DateTime.now(),
    );

    final tx = InventoryTransaction(
      id: 'tx-${transactions.length + 1}',
      inventoryItemId: itemId,
      transactionType: transactionType,
      quantity: quantity,
      stockBefore: stockBefore,
      stockAfter: stockAfter,
      reason: reason,
      remarks: remarks,
      patientId: patientId,
      totalAmount: totalAmount,
      unitPrice: unitPrice,
      vendorId: vendorId,
      performedBy: 'user-001',
      performedByName: 'Admin',
      createdAt: DateTime.now(),
    );
    transactions.insert(0, tx);
    return tx;
  }

  @override
  Future<List<InventoryTransaction>> getTransactionHistory(
    String inventoryItemId, {
    String? transactionType,
  }) async =>
      transactions.where((t) => t.inventoryItemId == inventoryItemId).toList();

  @override
  Future<List<InventoryTransaction>> getAllTransactions({
    String? transactionType,
    String? searchQuery,
    int? limit,
  }) async =>
      transactions;

  @override
  Future<List<InventoryBatch>> getInventoryBatches(String inventoryId) async => [];

  @override
  Future<List<InventoryBatch>> getBatchesForPO(String purchaseOrderId) async => [];
}

/// Fake repository for vendor operations.
class FakeVendorRepository implements VendorRepository {
  final List<Vendor> vendors;

  FakeVendorRepository([List<Vendor>? initial])
      : vendors = initial != null ? List.from(initial) : [];

  @override
  Future<List<Vendor>> getVendors({String? searchQuery, bool? activeOnly}) async =>
      List.from(vendors);

  @override
  Future<Vendor> getVendor(String id) async =>
      vendors.firstWhere((v) => v.id == id);

  @override
  Future<Vendor> createVendor(Vendor vendor) async {
    final created = vendor.copyWith(id: 'v-${vendors.length + 1}');
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
    final updated = vendors[idx].copyWith(isActive: isActive);
    vendors[idx] = updated;
    return updated;
  }
}

void main() {
  group('Sprint 6 Enhancements — A. Price Calculation Unit & Math Tests', () {
    test('Quantity 100 + Total ₹5,000 = ₹50 per piece on Vendor', () {
      const vendor = Vendor(
        id: 'v1',
        name: 'Apex Pharma',
        lastQuantity: 100.0,
        lastTotalAmount: 5000.0,
      );

      expect(vendor.pricePerPiece, equals(50.0));
      expect(vendor.formattedPricePerPiece, equals('₹50.00'));
      expect(vendor.formattedLastTotalAmount, equals('₹5000.00'));
      expect(vendor.formattedLastQuantity, equals('100'));
    });

    test('Quantity 100 + Total ₹5,000 = ₹50 per piece on InventoryItem', () {
      const item = InventoryItem(
        id: 'i1',
        name: 'Surgical Gloves',
        category: 'Clinical Supplies',
        currentStock: 100.0,
        unit: 'pairs',
        lastQuantitySupplied: 100.0,
        lastTotalAmount: 5000.0,
      );

      expect(item.calculatedPricePerPiece, equals(50.0));
      expect(item.formattedCalculatedPricePerPiece, equals('₹50.00'));
      expect(item.formattedLastTotalAmount, equals('₹5000.00'));
      expect(item.formattedLastQuantitySupplied, equals('100'));
    });

    test('Decimal quantity and total amount calculations are supported', () {
      const vendor = Vendor(
        id: 'v2',
        name: 'Precision Optical',
        lastQuantity: 25.5,
        lastTotalAmount: 1275.0,
      );

      // 1275.0 / 25.5 = 50.0
      expect(vendor.pricePerPiece, equals(50.0));
      expect(vendor.formattedPricePerPiece, equals('₹50.00'));

      const item = InventoryItem(
        id: 'i2',
        name: 'Saline Solution',
        category: 'Clinical Supplies',
        currentStock: 3.0,
        unit: 'liters',
        lastQuantitySupplied: 3.0,
        lastTotalAmount: 100.0,
      );

      // 100.0 / 3.0 = 33.333333333333336
      expect(item.calculatedPricePerPiece, closeTo(33.33, 0.01));
      expect(item.formattedCalculatedPricePerPiece, equals('₹33.33'));
    });

    test('Zero quantity prevents division by zero and returns null', () {
      const vendorZero = Vendor(
        id: 'v3',
        name: 'Zero Qty Vendor',
        lastQuantity: 0.0,
        lastTotalAmount: 5000.0,
      );

      expect(vendorZero.pricePerPiece, isNull);
      expect(vendorZero.formattedPricePerPiece, equals('—'));

      const itemZero = InventoryItem(
        id: 'i3',
        name: 'Zero Qty Item',
        category: 'Clinical Supplies',
        currentStock: 0.0,
        unit: 'pcs',
        lastQuantitySupplied: 0.0,
        lastTotalAmount: 2500.0,
      );

      expect(itemZero.calculatedPricePerPiece, isNull);
      expect(itemZero.formattedCalculatedPricePerPiece, equals('—'));
    });

    test('Negative total amount or quantity returns null safely', () {
      const vendorNeg = Vendor(
        id: 'v4',
        name: 'Negative Vendor',
        lastQuantity: -10.0,
        lastTotalAmount: 500.0,
      );

      expect(vendorNeg.pricePerPiece, isNull);

      const itemNegTotal = InventoryItem(
        id: 'i4',
        name: 'Neg Total Item',
        category: 'Clinical Supplies',
        currentStock: 10.0,
        unit: 'pcs',
        lastQuantitySupplied: 10.0,
        lastTotalAmount: -50.0,
      );

      expect(itemNegTotal.calculatedPricePerPiece, isNull);
    });
  });

  group('Sprint 6 Enhancements — B. Restock Flow UI & Calculation Tests', () {
    testWidgets('Selecting Restock shows total amount field and auto-calculates price per piece',
        (tester) async {
      tester.view.physicalSize = const Size(1200, 900);
      tester.view.devicePixelRatio = 1.0;
      addTearDown(tester.view.resetPhysicalSize);

      const item = InventoryItem(
        id: 'item-restock-1',
        name: 'Surgical Gauze Pads',
        category: 'Clinical Supplies',
        currentStock: 50.0,
        unit: 'packs',
      );

      final fakeRepo = FakeInventoryRepository([item]);

      await tester.pumpWidget(
        ProviderScope(
          overrides: [
            inventoryRepositoryProvider.overrideWithValue(fakeRepo),
          ],
          child: const MaterialApp(
            home: Scaffold(
              body: StockOperationDialog.stockIn(
                item: item,
              ),
            ),
          ),
        ),
      );

      await tester.pumpAndSettle();

      // Initial default reason is 'Restock'
      expect(find.text(StockInReasons.restock), findsWidgets);

      // Verify total amount field is present
      expect(find.text('TOTAL AMOUNT PAID (₹) *'), findsOneWidget);
      expect(find.text('AUTOMATIC PRICE PER PIECE'), findsOneWidget);

      // Enter quantity: 100
      final formFields = find.byType(TextFormField);
      final qtyField = formFields.first;
      await tester.enterText(qtyField, '100');
      await tester.pumpAndSettle();

      // Enter total amount: 5000
      final totalField = find.widgetWithText(TextFormField, 'Enter total amount paid (e.g. 5000)');
      expect(totalField, findsOneWidget);
      await tester.enterText(totalField, '5000');
      await tester.pumpAndSettle();

      // Verify calculated price per piece is displayed: ₹50.00 / packs
      expect(find.text('₹50.00 / packs'), findsOneWidget);
      expect(find.text('Quantity: 100 packs'), findsOneWidget);
      expect(find.text('Total Paid: ₹5000.00'), findsOneWidget);

      // Submit Stock In
      await tester.tap(find.text('Confirm Stock In'));
      await tester.pumpAndSettle();

      // Check persistence in fakeRepo
      expect(fakeRepo.items.first.currentStock, equals(150.0));
      expect(fakeRepo.items.first.lastQuantitySupplied, equals(100.0));
      expect(fakeRepo.items.first.lastTotalAmount, equals(5000.0));
      expect(fakeRepo.items.first.calculatedPricePerPiece, equals(50.0));

      expect(fakeRepo.transactions.length, equals(1));
      expect(fakeRepo.transactions.first.totalAmount, equals(5000.0));
      expect(fakeRepo.transactions.first.unitPrice, equals(50.0));
      expect(fakeRepo.transactions.first.formattedUnitPrice, equals('₹50.00'));
    });

    testWidgets('Restock rejects non-positive quantity and empty total amount',
        (tester) async {
      tester.view.physicalSize = const Size(1200, 900);
      tester.view.devicePixelRatio = 1.0;
      addTearDown(tester.view.resetPhysicalSize);

      const item = InventoryItem(
        id: 'item-restock-val',
        name: 'Antibacterial Wipes',
        category: 'Clinical Supplies',
        currentStock: 20.0,
        unit: 'tubs',
      );

      final fakeRepo = FakeInventoryRepository([item]);

      await tester.pumpWidget(
        ProviderScope(
          overrides: [
            inventoryRepositoryProvider.overrideWithValue(fakeRepo),
          ],
          child: const MaterialApp(
            home: Scaffold(
              body: StockOperationDialog.stockIn(
                item: item,
              ),
            ),
          ),
        ),
      );

      await tester.pumpAndSettle();

      // Enter 0 quantity
      final qtyField = find.byType(TextFormField).first;
      await tester.enterText(qtyField, '0');

      // Attempt submit without entering total amount
      await tester.tap(find.text('Confirm Stock In'));
      await tester.pumpAndSettle();

      // Validation errors should be triggered
      expect(find.text('Quantity must be greater than 0.'), findsOneWidget);
      expect(find.text('Total amount paid is required.'), findsOneWidget);
      expect(fakeRepo.transactions.isEmpty, isTrue);
    });
  });

  group('Sprint 6 Enhancements — C. Supplier Delivery Flow UI & Calculation Tests', () {
    testWidgets('Selecting Supplier Delivery shows pricing fields and associates vendor',
        (tester) async {
      tester.view.physicalSize = const Size(1200, 1000);
      tester.view.devicePixelRatio = 1.0;
      addTearDown(tester.view.resetPhysicalSize);

      const item = InventoryItem(
        id: 'item-delivery-1',
        name: 'Disposable Syringes 5ml',
        category: 'Clinical Supplies',
        currentStock: 200.0,
        unit: 'units',
      );

      const vendor = Vendor(
        id: 'v-med-supply',
        name: 'MedSupply Co',
        phone: '+91 9876543210',
        isActive: true,
      );

      final fakeRepo = FakeInventoryRepository([item]);
      final fakeVendorRepo = FakeVendorRepository([vendor]);

      await tester.pumpWidget(
        ProviderScope(
          overrides: [
            inventoryRepositoryProvider.overrideWithValue(fakeRepo),
            vendorRepositoryProvider.overrideWithValue(fakeVendorRepo),
          ],
          child: const MaterialApp(
            home: Scaffold(
              body: StockOperationDialog.stockIn(
                item: item,
              ),
            ),
          ),
        ),
      );

      await tester.pumpAndSettle();

      // Select 'Supplier Delivery' from reasons dropdown
      final reasonDropdown = find.byType(DropdownButtonFormField<String>).first;
      await tester.tap(reasonDropdown);
      await tester.pumpAndSettle();

      await tester.tap(find.text(StockInReasons.supplierDelivery).last);
      await tester.pumpAndSettle();

      // Pricing card and total amount fields are displayed
      expect(find.text('TOTAL AMOUNT PAID (₹) *'), findsOneWidget);
      expect(find.text('AUTOMATIC PRICE PER PIECE'), findsOneWidget);

      // Enter quantity: 50
      final qtyField = find.byType(TextFormField).first;
      await tester.enterText(qtyField, '50');

      // Enter total amount: 1500 -> Price per piece = ₹30.00 / units
      final totalField = find.widgetWithText(TextFormField, 'Enter total amount paid (e.g. 5000)');
      await tester.enterText(totalField, '1500');
      await tester.pumpAndSettle();

      expect(find.text('₹30.00 / units'), findsOneWidget);
      expect(find.text('Quantity: 50 units'), findsOneWidget);
      expect(find.text('Total Paid: ₹1500.00'), findsOneWidget);

      // Submit
      await tester.tap(find.text('Confirm Stock In'));
      await tester.pumpAndSettle();

      // Verify persistence
      expect(fakeRepo.items.first.currentStock, equals(250.0));
      expect(fakeRepo.items.first.lastQuantitySupplied, equals(50.0));
      expect(fakeRepo.items.first.lastTotalAmount, equals(1500.0));
      expect(fakeRepo.items.first.calculatedPricePerPiece, equals(30.0));
    });
  });

  group('Sprint 6 Enhancements — D. Other Stock In Reasons Behavior', () {
    testWidgets('Other stock-in reasons do NOT show total amount or price preview fields',
        (tester) async {
      tester.view.physicalSize = const Size(1200, 1000);
      tester.view.devicePixelRatio = 1.0;
      addTearDown(tester.view.resetPhysicalSize);

      const item = InventoryItem(
        id: 'item-other-1',
        name: 'Ophthalmic Ointment',
        category: 'Optical & Eye Care',
        currentStock: 15.0,
        unit: 'tubes',
      );

      final fakeRepo = FakeInventoryRepository([item]);

      await tester.pumpWidget(
        ProviderScope(
          overrides: [
            inventoryRepositoryProvider.overrideWithValue(fakeRepo),
          ],
          child: const MaterialApp(
            home: Scaffold(
              body: StockOperationDialog.stockIn(
                item: item,
              ),
            ),
          ),
        ),
      );

      await tester.pumpAndSettle();

      // Change reason from 'Restock' to 'Return from Department'
      final reasonDropdown = find.byType(DropdownButtonFormField<String>).first;
      await tester.tap(reasonDropdown);
      await tester.pumpAndSettle();

      await tester.tap(find.text('Return from Department').last);
      await tester.pumpAndSettle();

      // Pricing fields must NOT be displayed
      expect(find.text('TOTAL AMOUNT PAID (₹) *'), findsNothing);
      expect(find.text('AUTOMATIC PRICE PER PIECE'), findsNothing);
      expect(find.text('Price Per Piece'), findsNothing);
    });
  });

  group('Sprint 6 Enhancements — E. Vendor Information & Auto Price Per Piece', () {
    testWidgets('VendorDetailsDialog displays Latest Quantity, Total Payment, and Price Per Piece',
        (tester) async {
      tester.view.physicalSize = const Size(1200, 900);
      tester.view.devicePixelRatio = 1.0;
      addTearDown(tester.view.resetPhysicalSize);

      final vendor = const Vendor(
        id: 'v-disp-1',
        name: 'Optic Instruments Ltd',
        contactPerson: 'Suresh Patel',
        phone: '+91 9123456780',
        lastQuantity: 100.0,
        lastTotalAmount: 5000.0,
        isActive: true,
      );

      final fakeVendorRepo = FakeVendorRepository([vendor]);

      await tester.pumpWidget(
        ProviderScope(
          overrides: [
            vendorRepositoryProvider.overrideWithValue(fakeVendorRepo),
            currentUserRoleProvider.overrideWith((ref) => Future.value('admin')),
          ],
          child: MaterialApp(
            home: Scaffold(
              body: VendorDetailsDialog(vendor: vendor),
            ),
          ),
        ),
      );

      await tester.pumpAndSettle();

      // Verify supply stats are displayed
      expect(find.text('100'), findsOneWidget);
      expect(find.text('₹5000.00'), findsOneWidget);
      expect(find.text('₹50.00'), findsOneWidget);
    });

    testWidgets('VendorFormDialog calculates price per piece preview as user types',
        (tester) async {
      tester.view.physicalSize = const Size(1200, 1000);
      tester.view.devicePixelRatio = 1.0;
      addTearDown(tester.view.resetPhysicalSize);

      final fakeVendorRepo = FakeVendorRepository([]);

      await tester.pumpWidget(
        ProviderScope(
          overrides: [
            vendorRepositoryProvider.overrideWithValue(fakeVendorRepo),
          ],
          child: const MaterialApp(
            home: Scaffold(
              body: VendorFormDialog(),
            ),
          ),
        ),
      );

      await tester.pumpAndSettle();

      // Find Quantity and Total Amount fields
      final qtyField = find.widgetWithText(TextFormField, 'E.g. 500');
      final totalField = find.widgetWithText(TextFormField, 'E.g. 5000');

      expect(qtyField, findsOneWidget);
      expect(totalField, findsOneWidget);

      // Enter quantity: 200, total: 10000 -> Price per piece: ₹50.00
      await tester.enterText(qtyField, '200');
      await tester.enterText(totalField, '10000');
      await tester.pumpAndSettle();

      expect(find.text('₹50.00 / piece'), findsOneWidget);
    });
  });

  group('Sprint 6 Enhancements — F. Call Vendor Implementation & Graceful Fallback', () {
    testWidgets('InventoryDetailsDialog renders Call Vendor button and details',
        (tester) async {
      tester.view.physicalSize = const Size(1200, 900);
      tester.view.devicePixelRatio = 1.0;
      addTearDown(tester.view.resetPhysicalSize);

      const item = InventoryItem(
        id: 'item-call-1',
        name: 'Ophthalmic Slit Lamp Bulb',
        category: 'Optical & Eye Care',
        currentStock: 8.0,
        unit: 'pcs',
        vendorId: 'v-call-1',
        vendorName: 'Vision Care Instruments',
        vendorPhone: '+91 9876543210',
        lastQuantitySupplied: 50.0,
        lastTotalAmount: 2500.0,
      );

      final fakeRepo = FakeInventoryRepository([item]);

      await tester.pumpWidget(
        ProviderScope(
          overrides: [
            inventoryRepositoryProvider.overrideWithValue(fakeRepo),
            currentUserRoleProvider.overrideWith((ref) => Future.value('admin')),
          ],
          child: const MaterialApp(
            home: Scaffold(
              body: InventoryDetailsDialog(item: item),
            ),
          ),
        ),
      );

      await tester.pumpAndSettle();

      // Verify supplier card
      expect(find.text('LAST SUPPLIED VENDOR & PRICING'), findsOneWidget);
      expect(find.text('Vision Care Instruments'), findsWidgets);
      expect(find.text('+91 9876543210'), findsOneWidget);
      expect(find.text('Call Vendor'), findsOneWidget);

      // Verify latest restock numbers
      expect(find.text('50 pcs'), findsWidgets);
      expect(find.text('₹2500.00'), findsWidgets);
      expect(find.text('₹50.00'), findsWidgets);
    });

    testWidgets('InventoryDetailsDialog shows appropriate state when vendor has no phone number',
        (tester) async {
      tester.view.physicalSize = const Size(1200, 900);
      tester.view.devicePixelRatio = 1.0;
      addTearDown(tester.view.resetPhysicalSize);

      const item = InventoryItem(
        id: 'item-call-no-phone',
        name: 'Microfiber Lens Cloth',
        category: 'Optical & Eye Care',
        currentStock: 100.0,
        unit: 'pcs',
        vendorId: 'v-no-phone',
        vendorName: 'Cloth Supplier Corp',
        vendorPhone: null, // Phone unavailable
      );

      final fakeRepo = FakeInventoryRepository([item]);

      await tester.pumpWidget(
        ProviderScope(
          overrides: [
            inventoryRepositoryProvider.overrideWithValue(fakeRepo),
            currentUserRoleProvider.overrideWith((ref) => Future.value('admin')),
          ],
          child: const MaterialApp(
            home: Scaffold(
              body: InventoryDetailsDialog(item: item),
            ),
          ),
        ),
      );

      await tester.pumpAndSettle();

      expect(find.text('Cloth Supplier Corp'), findsWidgets);
      expect(find.text('Phone number unavailable'), findsWidgets);
    });

    testWidgets('InventoryDetailsDialog shows unavailable state when no vendor is associated',
        (tester) async {
      tester.view.physicalSize = const Size(1200, 900);
      tester.view.devicePixelRatio = 1.0;
      addTearDown(tester.view.resetPhysicalSize);

      const item = InventoryItem(
        id: 'item-no-vendor',
        name: 'Unassigned Item',
        category: 'General',
        currentStock: 10.0,
        unit: 'pcs',
        vendorId: null,
      );

      final fakeRepo = FakeInventoryRepository([item]);

      await tester.pumpWidget(
        ProviderScope(
          overrides: [
            inventoryRepositoryProvider.overrideWithValue(fakeRepo),
            currentUserRoleProvider.overrideWith((ref) => Future.value('admin')),
          ],
          child: const MaterialApp(
            home: Scaffold(
              body: InventoryDetailsDialog(item: item),
            ),
          ),
        ),
      );

      await tester.pumpAndSettle();

      expect(find.text('No Vendor Associated'), findsOneWidget);
    });

    test('PhoneDialerUtil cleans phone numbers and validates format without auto-dialing', () {
      final valid = PhoneDialerUtil.isValidPhoneNumber('+91 (987) 654-3210');
      expect(valid, isTrue);

      final clean = PhoneDialerUtil.cleanNumber('+91 (987) 654-3210');
      expect(clean, equals('+919876543210'));

      final invalid = PhoneDialerUtil.isValidPhoneNumber('');
      expect(invalid, isFalse);

      final nullPhone = PhoneDialerUtil.isValidPhoneNumber(null);
      expect(nullPhone, isFalse);
    });
  });
}
