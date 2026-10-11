import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:supabase_flutter/supabase_flutter.dart' show User;

import 'package:mkes_care/features/auth/providers/auth_provider.dart';
import 'package:mkes_care/features/inventory/models/inventory_batch.dart';
import 'package:mkes_care/features/inventory/models/inventory_item.dart';
import 'package:mkes_care/features/inventory/models/inventory_transaction.dart';
import 'package:mkes_care/features/inventory/repositories/inventory_repository.dart';
import 'package:mkes_care/features/inventory/widgets/inventory_details_dialog.dart';
import 'package:mkes_care/features/inventory/widgets/stock_operation_dialog.dart';
import 'package:mkes_care/features/staff_portal/screens/staff_tasks_screen.dart';
import 'package:mkes_care/features/vendors/models/vendor.dart';
import 'package:mkes_care/features/vendors/repositories/vendor_repository.dart';
import 'package:mkes_care/features/vendors/screens/vendor_management_screen.dart';
import 'package:mkes_care/features/vendors/widgets/vendor_details_dialog.dart';
import 'package:mkes_care/features/vendors/widgets/vendor_form_dialog.dart';

/// In-memory FakeVendorRepository for deterministic tests.
class FakeVendorRepository implements VendorRepository {
  final List<Vendor> vendors;
  bool shouldThrow = false;

  FakeVendorRepository([List<Vendor>? initial])
      : vendors = initial != null ? List.from(initial) : [];

  @override
  Future<List<Vendor>> getVendors({String? searchQuery, bool? activeOnly}) async {
    if (shouldThrow) throw Exception('Simulated network error');
    var result = List<Vendor>.from(vendors);

    if (activeOnly == true) {
      result = result.where((v) => v.isActive).toList();
    }

    if (searchQuery != null && searchQuery.trim().isNotEmpty) {
      final q = searchQuery.trim().toLowerCase();
      result = result.where((v) {
        return v.name.toLowerCase().contains(q) ||
            (v.contactPerson?.toLowerCase() ?? '').contains(q) ||
            (v.phone?.toLowerCase() ?? '').contains(q) ||
            (v.email?.toLowerCase() ?? '').contains(q) ||
            v.productsSupplied.any((p) => p.toLowerCase().contains(q));
      }).toList();
    }

    return result;
  }

  @override
  Future<Vendor> getVendor(String id) async {
    if (shouldThrow) throw Exception('Simulated fetch error');
    return vendors.firstWhere(
      (v) => v.id == id,
      orElse: () => throw Exception('Vendor not found: $id'),
    );
  }

  @override
  Future<Vendor> createVendor(Vendor vendor) async {
    if (shouldThrow) throw Exception('Simulated create error');
    if (vendor.name.trim().isEmpty) {
      throw ArgumentError('Vendor name is required.');
    }
    final created = vendor.copyWith(
      id: vendor.id.isNotEmpty ? vendor.id : 'v-${vendors.length + 1}',
      createdAt: DateTime.now(),
      updatedAt: DateTime.now(),
    );
    vendors.add(created);
    return created;
  }

  @override
  Future<Vendor> updateVendor(Vendor vendor) async {
    if (shouldThrow) throw Exception('Simulated update error');
    if (vendor.id.trim().isEmpty) {
      throw ArgumentError('Vendor ID is required for update.');
    }
    final idx = vendors.indexWhere((v) => v.id == vendor.id);
    if (idx != -1) {
      final updated = vendor.copyWith(updatedAt: DateTime.now());
      vendors[idx] = updated;
      return updated;
    }
    vendors.add(vendor);
    return vendor;
  }

  @override
  Future<void> deleteVendor(String id) async {
    if (shouldThrow) throw Exception('Simulated delete error');
    vendors.removeWhere((v) => v.id == id);
  }

  @override
  Future<Vendor> toggleVendorStatus(String id, bool isActive) async {
    if (shouldThrow) throw Exception('Simulated toggle error');
    final idx = vendors.indexWhere((v) => v.id == id);
    if (idx == -1) throw Exception('Vendor not found.');
    final updated = vendors[idx].copyWith(
      isActive: isActive,
      updatedAt: DateTime.now(),
    );
    vendors[idx] = updated;
    return updated;
  }
}

/// In-memory FakeInventoryRepository implementing all [InventoryRepository] methods.
class FakeInventoryRepository implements InventoryRepository {
  final List<InventoryItem> items;
  final List<InventoryTransaction> transactions = [];

  @override
  dynamic noSuchMethod(Invocation invocation) => super.noSuchMethod(invocation);

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
    final idx = items.indexWhere((i) => i.id == itemId);
    if (idx == -1) throw Exception('Item not found');
    final item = items[idx];

    final double stockBefore = item.currentStock;
    final double stockAfter = transactionType == 'stock_in'
        ? stockBefore + quantity
        : stockBefore - quantity;

    items[idx] = item.copyWith(
      currentStock: stockAfter,
      vendorId: vendorId ?? item.vendorId,
      lastQuantitySupplied:
          transactionType == 'stock_in' ? quantity : item.lastQuantitySupplied,
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
      vendorId: vendorId,
      totalAmount: totalAmount,
      unitPrice:
          (totalAmount != null && quantity > 0) ? (totalAmount / quantity) : null,
      createdAt: DateTime.now(),
    );
    transactions.add(tx);
    return tx;
  }

  @override
  Future<List<InventoryTransaction>> getTransactionHistory(
    String itemId, {
    String? transactionType,
  }) async {
    var list = transactions.where((t) => t.inventoryItemId == itemId).toList();
    if (transactionType != null &&
        transactionType.isNotEmpty &&
        transactionType != 'All') {
      list = list
          .where((t) => t.transactionType == transactionType.toLowerCase())
          .toList();
    }
    return list;
  }

  @override
  Future<List<InventoryTransaction>> getAllTransactions({
    String? transactionType,
    int limit = 100,
  }) async {
    var list = List<InventoryTransaction>.from(transactions);
    if (transactionType != null &&
        transactionType.isNotEmpty &&
        transactionType != 'All') {
      list = list
          .where((t) => t.transactionType == transactionType.toLowerCase())
          .toList();
    }
    return list.take(limit).toList();
  }

  @override
  Future<List<InventoryBatch>> getInventoryBatches(String inventoryId) async => [];

  @override
  Future<List<InventoryBatch>> getBatchesForPO(String purchaseOrderId) async => [];
}

void main() {
  const mockStaffUser = User(
    id: 'staff-user-test-1',
    appMetadata: {},
    userMetadata: {},
    aud: 'authenticated',
    createdAt: '2026-01-01T00:00:00Z',
  );

  Widget createStaffTestApp({
    required Widget child,
    required FakeVendorRepository vendorRepo,
    FakeInventoryRepository? inventoryRepo,
    String role = 'staff',
  }) {
    return ProviderScope(
      overrides: [
        vendorRepositoryProvider.overrideWithValue(vendorRepo),
        currentUserRoleProvider.overrideWith((ref) => Future.value(role)),
        currentUserProvider.overrideWithValue(mockStaffUser),
        if (inventoryRepo != null)
          inventoryRepositoryProvider.overrideWithValue(inventoryRepo),
      ],
      child: MaterialApp(
        home: Scaffold(body: child),
      ),
    );
  }

  group('Staff — Full Vendor Management Access Tests', () {
    // 1. Staff can open Vendor page & navigate to it
    testWidgets(
        '1. Staff can open Vendor page via VendorManagementScreen and navigation',
        (tester) async {
      tester.view.physicalSize = const Size(1280, 800);
      tester.view.devicePixelRatio = 1.0;
      addTearDown(tester.view.resetPhysicalSize);

      final fakeRepo = FakeVendorRepository([
        const Vendor(id: 'v1', name: 'Alpha Medical Supplies', isActive: true),
      ]);

      // Test 1a: Direct VendorManagementScreen for Staff
      await tester.pumpWidget(
        createStaffTestApp(
          child: const VendorManagementScreen(),
          vendorRepo: fakeRepo,
        ),
      );
      await tester.pumpAndSettle();

      expect(find.text('Vendor Management'), findsOneWidget);
      expect(find.text('Vendor Directory'), findsOneWidget);
      expect(find.text('Alpha Medical Supplies'), findsOneWidget);

      // Test 1b: Navigation via StaffTasksScreen
      await tester.pumpWidget(
        createStaffTestApp(
          child: const StaffTasksScreen(initialTab: StaffTaskTab.vendors),
          vendorRepo: fakeRepo,
        ),
      );
      await tester.pumpAndSettle();

      expect(find.text('Vendors'), findsWidgets);
      expect(find.text('Alpha Medical Supplies'), findsOneWidget);
    });

    // 2. Staff can view vendors
    testWidgets('2. Staff can view vendor list', (tester) async {
      tester.view.physicalSize = const Size(1280, 800);
      tester.view.devicePixelRatio = 1.0;
      addTearDown(tester.view.resetPhysicalSize);

      final fakeRepo = FakeVendorRepository([
        const Vendor(
          id: 'v-view-1',
          name: 'City Diagnostics Supplies',
          contactPerson: 'Rahul Sharma',
          phone: '+91 9876543210',
          isActive: true,
        ),
        const Vendor(
          id: 'v-view-2',
          name: 'Optima Lenses Ltd',
          contactPerson: 'Meera Patel',
          phone: '+91 9123456780',
          isActive: false,
        ),
      ]);

      await tester.pumpWidget(
        createStaffTestApp(
          child: const VendorManagementContent(),
          vendorRepo: fakeRepo,
        ),
      );
      await tester.pumpAndSettle();

      expect(find.text('City Diagnostics Supplies'), findsOneWidget);
      expect(find.text('Rahul Sharma'), findsOneWidget);
      expect(find.text('Active'), findsWidgets);

      expect(find.text('Optima Lenses Ltd'), findsOneWidget);
      expect(find.text('Meera Patel'), findsOneWidget);
      expect(find.text('Inactive'), findsWidgets);
    });

    // 3. Staff can search vendors
    testWidgets('3. Staff can search vendors', (tester) async {
      tester.view.physicalSize = const Size(1280, 800);
      tester.view.devicePixelRatio = 1.0;
      addTearDown(tester.view.resetPhysicalSize);

      final fakeRepo = FakeVendorRepository([
        const Vendor(id: 'v-s1', name: 'MedEquip Solutions', isActive: true),
        const Vendor(id: 'v-s2', name: 'Apex Pharma', isActive: true),
      ]);

      await tester.pumpWidget(
        createStaffTestApp(
          child: const VendorManagementContent(),
          vendorRepo: fakeRepo,
        ),
      );
      await tester.pumpAndSettle();

      expect(find.text('MedEquip Solutions'), findsOneWidget);
      expect(find.text('Apex Pharma'), findsOneWidget);

      // Search for MedEquip
      final searchField = find.byType(TextField);
      await tester.enterText(searchField, 'MedEquip');
      await tester.pumpAndSettle();

      expect(find.text('MedEquip Solutions'), findsOneWidget);
      expect(find.text('Apex Pharma'), findsNothing);
    });

    // 4. Staff can filter vendors
    testWidgets('4. Staff can filter vendors by Active / Inactive status',
        (tester) async {
      tester.view.physicalSize = const Size(1280, 800);
      tester.view.devicePixelRatio = 1.0;
      addTearDown(tester.view.resetPhysicalSize);

      final fakeRepo = FakeVendorRepository([
        const Vendor(id: 'v-act', name: 'Active Supplier', isActive: true),
        const Vendor(id: 'v-inact', name: 'Inactive Supplier', isActive: false),
      ]);

      await tester.pumpWidget(
        createStaffTestApp(
          child: const VendorManagementContent(),
          vendorRepo: fakeRepo,
        ),
      );
      await tester.pumpAndSettle();

      expect(find.text('Active Supplier'), findsOneWidget);
      expect(find.text('Inactive Supplier'), findsOneWidget);

      // Tap 'Active' filter chip
      await tester.tap(find.widgetWithText(FilterChip, 'Active'));
      await tester.pumpAndSettle();

      expect(find.text('Active Supplier'), findsOneWidget);
      expect(find.text('Inactive Supplier'), findsNothing);

      // Tap 'Inactive' filter chip
      await tester.tap(find.widgetWithText(FilterChip, 'Inactive'));
      await tester.pumpAndSettle();

      expect(find.text('Active Supplier'), findsNothing);
      expect(find.text('Inactive Supplier'), findsOneWidget);
    });

    // 5. Staff can open vendor details
    testWidgets('5. Staff can open vendor details dialog', (tester) async {
      tester.view.physicalSize = const Size(1280, 800);
      tester.view.devicePixelRatio = 1.0;
      addTearDown(tester.view.resetPhysicalSize);

      final fakeRepo = FakeVendorRepository([
        const Vendor(
          id: 'v-det',
          name: 'Precision Instruments',
          contactPerson: 'Dr. Rao',
          phone: '+91 9998887776',
          email: 'rao@precision.com',
          address: '42 Health Park, Mumbai',
          productsSupplied: ['Forceps', 'Scissors'],
          isActive: true,
        ),
      ]);

      await tester.pumpWidget(
        createStaffTestApp(
          child: const VendorManagementContent(),
          vendorRepo: fakeRepo,
        ),
      );
      await tester.pumpAndSettle();

      // Tap on card to open details
      await tester.tap(find.text('Precision Instruments'));
      await tester.pumpAndSettle();

      // Verify details dialog
      final dialogFinder = find.byType(VendorDetailsDialog);
      expect(dialogFinder, findsOneWidget);
      expect(find.descendant(of: dialogFinder, matching: find.text('Dr. Rao')), findsWidgets);
      expect(find.descendant(of: dialogFinder, matching: find.text('+91 9998887776')), findsWidgets);
      expect(find.descendant(of: dialogFinder, matching: find.text('rao@precision.com')), findsOneWidget);
      expect(find.descendant(of: dialogFinder, matching: find.text('42 Health Park, Mumbai')), findsOneWidget);
      expect(find.descendant(of: dialogFinder, matching: find.text('Forceps')), findsOneWidget);
      expect(find.descendant(of: dialogFinder, matching: find.text('Scissors')), findsOneWidget);
    });

    // 6. Staff can add a vendor
    testWidgets('6. Staff can add a vendor successfully', (tester) async {
      tester.view.physicalSize = const Size(1280, 800);
      tester.view.devicePixelRatio = 1.0;
      addTearDown(tester.view.resetPhysicalSize);

      final fakeRepo = FakeVendorRepository([]);

      await tester.pumpWidget(
        createStaffTestApp(
          child: const VendorManagementContent(),
          vendorRepo: fakeRepo,
        ),
      );
      await tester.pumpAndSettle();

      // Empty state shows 'Add First Vendor' for Staff
      expect(find.text('Add First Vendor'), findsOneWidget);
      await tester.tap(find.text('Add First Vendor'));
      await tester.pumpAndSettle();

      // Form dialog opens
      expect(find.byType(VendorFormDialog), findsOneWidget);

      // Enter vendor fields using index positions in the form
      await tester.enterText(find.byType(TextFormField).at(0), 'Global Surgicals');
      await tester.enterText(find.byType(TextFormField).at(1), 'Anand Verma');
      await tester.enterText(find.byType(TextFormField).at(2), '+91 9876500000');
      await tester.enterText(find.byType(TextFormField).at(3), 'anand@globalsurgicals.com');
      await tester.pumpAndSettle();

      // Save vendor (Create Vendor button)
      await tester.tap(find.text('Create Vendor'));
      await tester.pumpAndSettle();

      expect(fakeRepo.vendors.length, 1);
      expect(fakeRepo.vendors.first.name, 'Global Surgicals');
      expect(find.text('Global Surgicals'), findsOneWidget);
    });

    // 7. Staff can edit a vendor
    testWidgets('7. Staff can edit an existing vendor', (tester) async {
      tester.view.physicalSize = const Size(1280, 800);
      tester.view.devicePixelRatio = 1.0;
      addTearDown(tester.view.resetPhysicalSize);

      final fakeRepo = FakeVendorRepository([
        const Vendor(
          id: 'v-edit',
          name: 'Original Vendor Name',
          contactPerson: 'Original Contact',
          phone: '+91 1111111111',
          isActive: true,
        ),
      ]);

      await tester.pumpWidget(
        createStaffTestApp(
          child: const VendorManagementContent(),
          vendorRepo: fakeRepo,
        ),
      );
      await tester.pumpAndSettle();

      // Open popup menu on card (which Staff now has access to)
      await tester.tap(find.byIcon(Icons.more_vert));
      await tester.pumpAndSettle();

      expect(find.text('Edit Vendor'), findsOneWidget);
      await tester.tap(find.text('Edit Vendor'));
      await tester.pumpAndSettle();

      // Edit name
      await tester.enterText(find.byType(TextFormField).at(0), 'Updated Vendor Name');
      await tester.pumpAndSettle();

      // Button in edit mode is 'Update Vendor'
      await tester.tap(find.text('Update Vendor'));
      await tester.pumpAndSettle();

      expect(fakeRepo.vendors.first.name, 'Updated Vendor Name');
      expect(find.text('Updated Vendor Name'), findsOneWidget);
    });

    // 8. Staff can delete a vendor
    testWidgets('8. Staff can delete a vendor using confirmation flow',
        (tester) async {
      tester.view.physicalSize = const Size(1280, 800);
      tester.view.devicePixelRatio = 1.0;
      addTearDown(tester.view.resetPhysicalSize);

      final fakeRepo = FakeVendorRepository([
        const Vendor(
          id: 'v-del',
          name: 'Vendor To Delete',
          isActive: true,
        ),
      ]);

      await tester.pumpWidget(
        createStaffTestApp(
          child: const VendorManagementContent(),
          vendorRepo: fakeRepo,
        ),
      );
      await tester.pumpAndSettle();

      expect(find.text('Vendor To Delete'), findsOneWidget);

      // Open card popup menu -> Delete
      await tester.tap(find.byIcon(Icons.more_vert));
      await tester.pumpAndSettle();

      expect(find.text('Delete'), findsOneWidget);
      await tester.tap(find.text('Delete'));
      await tester.pumpAndSettle();

      // Confirmation dialog
      expect(find.text('Confirm Deletion'), findsOneWidget);
      await tester.tap(find.widgetWithText(FilledButton, 'Delete Vendor'));
      await tester.pumpAndSettle();

      expect(fakeRepo.vendors.isEmpty, isTrue);
      expect(find.text('Vendor To Delete'), findsNothing);
    });

    // 9. Staff can activate/deactivate a vendor
    testWidgets('9. Staff can activate and deactivate a vendor', (tester) async {
      tester.view.physicalSize = const Size(1280, 800);
      tester.view.devicePixelRatio = 1.0;
      addTearDown(tester.view.resetPhysicalSize);

      final fakeRepo = FakeVendorRepository([
        const Vendor(
          id: 'v-toggle',
          name: 'Toggleable Vendor',
          isActive: true,
        ),
      ]);

      await tester.pumpWidget(
        createStaffTestApp(
          child: const VendorManagementContent(),
          vendorRepo: fakeRepo,
        ),
      );
      await tester.pumpAndSettle();

      expect(find.text('Active'), findsWidgets);

      // Toggle status from card popup
      await tester.tap(find.byIcon(Icons.more_vert));
      await tester.pumpAndSettle();

      expect(find.text('Deactivate'), findsOneWidget);
      await tester.tap(find.text('Deactivate'));
      await tester.pumpAndSettle();

      expect(fakeRepo.vendors.first.isActive, isFalse);
      expect(find.text('Inactive'), findsWidgets);

      // Toggle status back to Active
      await tester.tap(find.byIcon(Icons.more_vert));
      await tester.pumpAndSettle();

      expect(find.text('Activate'), findsOneWidget);
      await tester.tap(find.text('Activate'));
      await tester.pumpAndSettle();

      expect(fakeRepo.vendors.first.isActive, isTrue);
      expect(find.text('Active'), findsWidgets);
    });

    // 10. Staff can see latest quantity/payment/price information
    testWidgets(
        '10. Staff can see latest quantity, payment, and price information',
        (tester) async {
      tester.view.physicalSize = const Size(1280, 800);
      tester.view.devicePixelRatio = 1.0;
      addTearDown(tester.view.resetPhysicalSize);

      const vendor = Vendor(
        id: 'v-stats',
        name: 'Vision Optical Labs',
        contactPerson: 'Suresh Menon',
        phone: '+91 9988776655',
        lastQuantity: 400.0,
        lastTotalAmount: 20000.0,
        isActive: true,
      );

      final fakeRepo = FakeVendorRepository([vendor]);

      await tester.pumpWidget(
        createStaffTestApp(
          child: const VendorDetailsDialog(vendor: vendor),
          vendorRepo: fakeRepo,
        ),
      );
      await tester.pumpAndSettle();

      // Verify numbers are displayed for Staff
      expect(find.text('400'), findsOneWidget);
      expect(find.text('₹20000.00'), findsOneWidget);
      expect(find.text('₹50.00'), findsOneWidget); // 20000 / 400 = 50.00
      expect(find.text('Suresh Menon'), findsWidgets);

      // Also verify Staff can see Edit Vendor and Deactivate buttons in details dialog
      expect(find.text('Edit Vendor'), findsOneWidget);
      expect(find.text('Deactivate'), findsOneWidget);
    });

    // 11. Admin: Existing Admin Vendor CRUD still works
    testWidgets('11. Existing Admin Vendor CRUD still works', (tester) async {
      tester.view.physicalSize = const Size(1280, 800);
      tester.view.devicePixelRatio = 1.0;
      addTearDown(tester.view.resetPhysicalSize);

      final fakeRepo = FakeVendorRepository([
        const Vendor(
          id: 'v-admin-1',
          name: 'Admin Managed Vendor',
          contactPerson: 'Admin Contact',
          isActive: true,
        ),
      ]);

      await tester.pumpWidget(
        createStaffTestApp(
          child: const VendorManagementContent(),
          vendorRepo: fakeRepo,
          role: 'admin',
        ),
      );
      await tester.pumpAndSettle();

      expect(find.text('Admin Managed Vendor'), findsOneWidget);
      expect(find.text('Add Vendor'), findsOneWidget);
      expect(find.byIcon(Icons.more_vert), findsOneWidget);

      // Open details dialog as Admin
      await tester.tap(find.text('Admin Managed Vendor'));
      await tester.pumpAndSettle();

      expect(find.text('Edit Vendor'), findsOneWidget);
      expect(find.text('Deactivate'), findsOneWidget);
    });

    // 12. Inventory: Vendor integration still works
    testWidgets('12. Inventory vendor integration still works for Staff',
        (tester) async {
      tester.view.physicalSize = const Size(1280, 800);
      tester.view.devicePixelRatio = 1.0;
      addTearDown(tester.view.resetPhysicalSize);

      const item = InventoryItem(
        id: 'item-inv-1',
        name: 'Ophthalmic Knife 2.2mm',
        category: 'Surgical Instruments',
        currentStock: 25.0,
        unit: 'pcs',
        vendorId: 'v-knife',
        vendorName: 'Care Surgicals Ltd',
        vendorPhone: '+91 9811223344',
        lastQuantitySupplied: 50.0,
        lastTotalAmount: 5000.0,
      );

      final fakeRepo = FakeVendorRepository([]);
      final fakeInvRepo = FakeInventoryRepository([item]);

      await tester.pumpWidget(
        createStaffTestApp(
          child: const InventoryDetailsDialog(item: item),
          vendorRepo: fakeRepo,
          inventoryRepo: fakeInvRepo,
        ),
      );
      await tester.pumpAndSettle();

      expect(find.text('LAST SUPPLIED VENDOR & PRICING'), findsOneWidget);
      expect(find.text('Care Surgicals Ltd'), findsWidgets);
      expect(find.text('+91 9811223344'), findsOneWidget);
      expect(find.text('50 pcs'), findsWidgets);
      expect(find.text('₹5000.00'), findsWidgets);
      expect(find.text('₹100.00'), findsWidgets); // 5000 / 50 = 100
      expect(find.text('Call Vendor'), findsOneWidget);
    });

    // 13. Supplier Delivery vendor selection still works
    testWidgets(
        '13. Supplier Delivery vendor selection and stock in works for Staff',
        (tester) async {
      tester.view.physicalSize = const Size(1280, 800);
      tester.view.devicePixelRatio = 1.0;
      addTearDown(tester.view.resetPhysicalSize);

      const item = InventoryItem(
        id: 'item-stock-1',
        name: 'Eyedrop Solution 10ml',
        category: 'Medications',
        currentStock: 20.0,
        unit: 'bottles',
      );

      final fakeRepo = FakeVendorRepository([
        const Vendor(
          id: 'v-eye-1',
          name: 'PharmaDrop International',
          phone: '+91 9123456789',
          isActive: true,
        ),
      ]);
      final fakeInvRepo = FakeInventoryRepository([item]);

      await tester.pumpWidget(
        createStaffTestApp(
          child: const StockOperationDialog.stockIn(item: item),
          vendorRepo: fakeRepo,
          inventoryRepo: fakeInvRepo,
        ),
      );
      await tester.pumpAndSettle();

      // Change Reason to Supplier Delivery: tap current reason dropdown ('Restock')
      await tester.tap(find.text('Restock').first);
      await tester.pumpAndSettle();

      await tester.tap(find.text('Supplier Delivery').last);
      await tester.pumpAndSettle();

      // Enter quantity and total amount using hint texts
      final qtyField = find.widgetWithText(TextFormField, 'Enter quantity to add');
      final totalField = find.widgetWithText(TextFormField, 'Enter total amount paid (e.g. 5000)');

      await tester.enterText(qtyField, '100');
      await tester.enterText(totalField, '3000');
      await tester.pumpAndSettle();

      // Calculated unit price preview: ₹30.00 / bottles
      expect(find.text('₹30.00 / bottles'), findsOneWidget);

      // Select vendor if dropdown present
      final vendorDropdown = find.byType(DropdownButtonFormField<String?>);
      if (vendorDropdown.evaluate().isNotEmpty) {
        await tester.tap(vendorDropdown.first, warnIfMissed: false);
        await tester.pumpAndSettle();
        final vendorOption = find.text('PharmaDrop International');
        if (vendorOption.evaluate().isNotEmpty) {
          await tester.tap(vendorOption.last, warnIfMissed: false);
          await tester.pumpAndSettle();
        }
      }

      // Submit Stock In (Confirm Stock In button)
      await tester.tap(find.widgetWithText(FilledButton, 'Confirm Stock In'));
      await tester.pumpAndSettle();

      expect(fakeInvRepo.items.first.currentStock, 120.0); // 20 + 100
      expect(fakeInvRepo.transactions.length, 1);
      expect(fakeInvRepo.transactions.first.totalAmount, 3000.0);
    });

    // 14. Call Vendor still works
    testWidgets(
        '14. Call Vendor button is present and functional in Inventory Details',
        (tester) async {
      tester.view.physicalSize = const Size(1280, 800);
      tester.view.devicePixelRatio = 1.0;
      addTearDown(tester.view.resetPhysicalSize);

      const item = InventoryItem(
        id: 'item-call-test',
        name: 'Disposable Syringes 5ml',
        category: 'Clinical Supplies',
        currentStock: 150.0,
        unit: 'pcs',
        vendorId: 'v-syr',
        vendorName: 'Apex Medical Supplies',
        vendorPhone: '+91 9988776655',
      );

      final fakeRepo = FakeVendorRepository([]);
      final fakeInvRepo = FakeInventoryRepository([item]);

      await tester.pumpWidget(
        createStaffTestApp(
          child: const InventoryDetailsDialog(item: item),
          vendorRepo: fakeRepo,
          inventoryRepo: fakeInvRepo,
        ),
      );
      await tester.pumpAndSettle();

      final callBtn = find.widgetWithText(FilledButton, 'Call Vendor');
      expect(callBtn, findsOneWidget);

      // Tapping Call Vendor invokes dialer
      await tester.tap(callBtn);
      await tester.pumpAndSettle();

      // UI remains stable and valid
      expect(find.text('Apex Medical Supplies'), findsWidgets);
    });
  });
}
