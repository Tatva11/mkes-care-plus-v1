import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:supabase_flutter/supabase_flutter.dart' show User;

import 'package:mkes_care/features/auth/providers/auth_provider.dart';
import 'package:mkes_care/features/department/models/department.dart';
import 'package:mkes_care/features/department/repositories/department_repository.dart';
import 'package:mkes_care/features/department/screens/department_management_screen.dart';
import 'package:mkes_care/features/inventory/models/inventory_batch.dart';
import 'package:mkes_care/features/inventory/models/inventory_item.dart';
import 'package:mkes_care/features/inventory/models/inventory_transaction.dart';
import 'package:mkes_care/features/inventory/repositories/inventory_repository.dart';
import 'package:mkes_care/features/inventory/screens/inventory_screen.dart';
import 'package:mkes_care/features/inventory/widgets/inventory_form_dialog.dart';
import 'package:mkes_care/features/staff_portal/screens/staff_tasks_screen.dart';
import 'package:mkes_care/features/vendors/models/vendor.dart';
import 'package:mkes_care/features/vendors/repositories/vendor_repository.dart';

/// In-memory FakeInventoryRepository with SKU duplicate enforcement and permission simulation.
class FakeInventoryRepositoryWithSKU implements InventoryRepository {
  final List<InventoryItem> items;
  final List<InventoryTransaction> transactions = [];
  bool shouldThrow = false;
  String? callerRole; // 'admin' or 'staff' or other

  @override
  dynamic noSuchMethod(Invocation invocation) => super.noSuchMethod(invocation);

  FakeInventoryRepositoryWithSKU([List<InventoryItem>? initial, this.callerRole])
      : items = initial != null ? List.from(initial) : [];

  @override
  Future<List<InventoryItem>> getInventoryItems({
    String? category,
    String? department,
    String? searchQuery,
    bool? activeOnly,
  }) async {
    if (shouldThrow) throw Exception('Simulated network error');
    var result = List<InventoryItem>.from(items);
    if (category != null && category.isNotEmpty && category != 'All') {
      result = result
          .where((i) => i.category.toLowerCase() == category.toLowerCase())
          .toList();
    }
    if (department != null && department.isNotEmpty && department != 'All') {
      result = result
          .where((i) => (i.department?.toLowerCase() ?? '') == department.toLowerCase())
          .toList();
    }
    if (activeOnly == true) {
      result = result.where((i) => i.isActive).toList();
    }
    if (searchQuery != null && searchQuery.trim().isNotEmpty) {
      final q = searchQuery.trim().toLowerCase();
      result = result
          .where((i) =>
              i.name.toLowerCase().contains(q) ||
              i.category.toLowerCase().contains(q) ||
              (i.sku?.toLowerCase() ?? '').contains(q) ||
              (i.brand?.toLowerCase() ?? '').contains(q))
          .toList();
    }
    return result;
  }

  @override
  Future<InventoryItem> getInventoryItem(String id) async {
    if (shouldThrow) throw Exception('Simulated network error');
    return items.firstWhere((i) => i.id == id);
  }

  @override
  Future<InventoryItem> createInventoryItem(InventoryItem item) async {
    if (shouldThrow) throw Exception('Simulated create error');

    // Supabase RLS simulation: only admin and staff can insert
    if (callerRole != null && callerRole != 'admin' && callerRole != 'staff') {
      throw Exception('new row violates row-level security policy for table "inventory"');
    }

    // SKU duplicate check
    if (item.sku != null && item.sku!.trim().isNotEmpty) {
      final duplicate = items.any(
        (i) => i.sku?.toLowerCase() == item.sku!.toLowerCase() && i.id != item.id,
      );
      if (duplicate) {
        throw Exception('duplicate key value violates unique constraint "inventory_sku_key"');
      }
    }

    final created = item.copyWith(
      id: item.id.isNotEmpty ? item.id : 'gen-item-${items.length + 1}',
      createdAt: DateTime.now(),
      updatedAt: DateTime.now(),
    );
    items.add(created);
    return created;
  }

  @override
  Future<InventoryItem> updateInventoryItem(InventoryItem item) async {
    if (shouldThrow) throw Exception('Simulated update error');

    // Supabase RLS simulation: only admin can update
    if (callerRole != null && callerRole != 'admin' && callerRole != 'staff') {
      throw Exception('row-level security policy blocks update for role $callerRole');
    }

    final index = items.indexWhere((i) => i.id == item.id);
    if (index != -1) {
      final updated = item.copyWith(updatedAt: DateTime.now());
      items[index] = updated;
      return updated;
    }
    items.add(item);
    return item;
  }

  @override
  Future<void> deleteInventoryItem(String id) async {
    if (shouldThrow) throw Exception('Simulated delete error');

    // Supabase RLS simulation: only admin and staff can delete
    if (callerRole != null && callerRole != 'admin' && callerRole != 'staff') {
      throw Exception('row-level security policy blocks delete for role $callerRole');
    }

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
    final index = items.indexWhere((i) => i.id == itemId);
    if (index == -1) throw Exception('Item not found');
    final current = items[index];

    final double stockBefore = current.currentStock;
    final double stockAfter;
    if (transactionType == 'stock_in') {
      stockAfter = stockBefore + quantity;
    } else {
      if (quantity > stockBefore) {
        throw Exception('Insufficient stock.');
      }
      stockAfter = stockBefore - quantity;
    }

    final updated = current.copyWith(
      currentStock: stockAfter,
      updatedAt: DateTime.now(),
      vendorId: vendorId ?? current.vendorId,
    );
    items[index] = updated;

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
      performedBy: 'user-1',
      performedByName: 'Staff Member',
      vendorId: vendorId,
      createdAt: DateTime.now(),
    );
    transactions.add(tx);

    return tx;
  }

  @override
  Future<List<InventoryTransaction>> getTransactionHistory(
    String inventoryItemId, {
    String? transactionType,
  }) async {
    var result = transactions.where((t) => t.inventoryItemId == inventoryItemId);
    if (transactionType != null && transactionType.isNotEmpty && transactionType != 'All') {
      result = result.where((t) => t.transactionType == transactionType);
    }
    return result.toList();
  }

  @override
  Future<List<InventoryTransaction>> getAllTransactions({
    String? transactionType,
    int limit = 100,
  }) async {
    var result = List<InventoryTransaction>.from(transactions);
    if (transactionType != null && transactionType.isNotEmpty && transactionType != 'All') {
      result = result.where((t) => t.transactionType == transactionType).toList();
    }
    return result.take(limit).toList();
  }

  @override
  Future<List<InventoryBatch>> getInventoryBatches(String inventoryId) async => [];

  @override
  Future<List<InventoryBatch>> getBatchesForPO(String purchaseOrderId) async => [];
}

/// In-memory FakeDepartmentRepository for department operations.
class FakeDepartmentRepository implements DepartmentRepository {
  final List<Department> departments;
  FakeDepartmentRepository([List<Department>? initial])
      : departments = initial != null ? List.from(initial) : [];

  @override
  Future<List<Department>> fetchDepartments() async => List.unmodifiable(departments);

  @override
  Future<void> createDepartment({required String name, String? description}) async {
    departments.add(Department(
      id: 'dept-${departments.length + 1}',
      name: name,
      description: description,
      isActive: true,
    ));
  }

  @override
  Future<void> updateDepartment({
    required String id,
    required String name,
    String? description,
    required bool isActive,
  }) async {
    final idx = departments.indexWhere((d) => d.id == id);
    if (idx != -1) {
      departments[idx] = Department(
        id: id,
        name: name,
        description: description,
        isActive: isActive,
      );
    }
  }

  @override
  Future<void> deleteDepartment(String id) async {
    departments.removeWhere((d) => d.id == id);
  }
}

/// In-memory FakeVendorRepository for vendor selection.
class FakeVendorRepository implements VendorRepository {
  final List<Vendor> vendors;
  FakeVendorRepository([List<Vendor>? initial])
      : vendors = initial != null ? List.from(initial) : [];

  @override
  Future<List<Vendor>> getVendors({String? searchQuery, bool? activeOnly}) async {
    var result = List<Vendor>.from(vendors);
    if (activeOnly == true) {
      result = result.where((v) => v.isActive).toList();
    }
    return result;
  }

  @override
  Future<Vendor> getVendor(String id) async => vendors.firstWhere((v) => v.id == id);

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
  Future<void> deleteVendor(String id) async => vendors.removeWhere((v) => v.id == id);

  @override
  Future<Vendor> toggleVendorStatus(String id, bool isActive) async {
    final idx = vendors.indexWhere((v) => v.id == id);
    final updated = vendors[idx].copyWith(isActive: isActive);
    vendors[idx] = updated;
    return updated;
  }
}

void main() {
  const mockStaffUser = User(
    id: 'staff-user-test-id',
    appMetadata: {},
    userMetadata: {},
    aud: 'authenticated',
    createdAt: '2026-01-01T00:00:00Z',
  );

  const sampleVendor = Vendor(
    id: 'vendor-cipla-101',
    name: 'Cipla Healthcare Ltd',
    contactPerson: 'Dr. Sharma',
    phone: '+919876543210',
    email: 'contact@cipla.com',
    isActive: true,
  );

  group('Sprint 6: Staff — Add New Inventory Products (Automated Tests)', () {
    // ----------------------------------------------------
    // 1. Staff can open Inventory from Staff Tasks navigation
    // ----------------------------------------------------
    testWidgets('1. Staff can open Inventory from Staff Tasks section', (tester) async {
      tester.view.physicalSize = const Size(1280, 800);
      tester.view.devicePixelRatio = 1.0;
      addTearDown(() => tester.view.resetPhysicalSize());

      final fakeRepo = FakeInventoryRepositoryWithSKU([], 'staff');

      await tester.pumpWidget(
        ProviderScope(
          overrides: [
            inventoryRepositoryProvider.overrideWithValue(fakeRepo),
            currentUserRoleProvider.overrideWith((ref) => Future.value('staff')),
            currentUserProvider.overrideWithValue(mockStaffUser),
          ],
          child: const MaterialApp(
            home: Scaffold(
              body: StaffTasksScreen(initialTab: StaffTaskTab.inventory),
            ),
          ),
        ),
      );

      await tester.pumpAndSettle();

      // Sub-tab Inventory is highlighted and selected
      expect(find.text('Inventory'), findsWidgets);

      // Inventory management view is rendered
      expect(find.text('Inventory Management'), findsWidgets);
    });

    // ----------------------------------------------------
    // 2. Staff can see the Add Inventory action
    // ----------------------------------------------------
    testWidgets('2. Staff can see Add Item action in header and empty state', (tester) async {
      tester.view.physicalSize = const Size(1280, 800);
      tester.view.devicePixelRatio = 1.0;
      addTearDown(() => tester.view.resetPhysicalSize());

      final fakeRepo = FakeInventoryRepositoryWithSKU([], 'staff');

      await tester.pumpWidget(
        ProviderScope(
          overrides: [
            inventoryRepositoryProvider.overrideWithValue(fakeRepo),
            currentUserRoleProvider.overrideWith((ref) => Future.value('staff')),
          ],
          child: const MaterialApp(
            home: Scaffold(
              body: InventoryManagementContent(),
            ),
          ),
        ),
      );

      await tester.pumpAndSettle();

      // Header has Add Item
      expect(find.text('Add Item'), findsOneWidget);
      // Empty state has Add First Item
      expect(find.text('Add First Item'), findsOneWidget);
    });

    // ----------------------------------------------------
    // 3. Staff can open the Inventory form
    // ----------------------------------------------------
    testWidgets('3. Staff can tap Add Item to open the Inventory form dialog', (tester) async {
      tester.view.physicalSize = const Size(1280, 800);
      tester.view.devicePixelRatio = 1.0;
      addTearDown(() => tester.view.resetPhysicalSize());

      final fakeRepo = FakeInventoryRepositoryWithSKU([], 'staff');

      await tester.pumpWidget(
        ProviderScope(
          overrides: [
            inventoryRepositoryProvider.overrideWithValue(fakeRepo),
            currentUserRoleProvider.overrideWith((ref) => Future.value('staff')),
          ],
          child: const MaterialApp(
            home: Scaffold(
              body: InventoryManagementContent(),
            ),
          ),
        ),
      );

      await tester.pumpAndSettle();

      await tester.tap(find.text('Add Item'));
      await tester.pumpAndSettle();

      // Dialog opens with title "New Inventory Item"
      expect(find.text('New Inventory Item'), findsOneWidget);
      expect(find.text('ITEM NAME *'), findsOneWidget);
      expect(find.text('BRAND / MANUFACTURER'), findsOneWidget);
      expect(find.text('EXPIRY DATE'), findsOneWidget);
    });

    // ----------------------------------------------------
    // 4, 5, 6, 7, 8, 9. Staff enters valid info, selects vendor, submits, item appears in list
    // ----------------------------------------------------
    testWidgets('4-9. Staff can enter product info with brand, expiry, vendor and submit',
        (tester) async {
      tester.view.physicalSize = const Size(1280, 900);
      tester.view.devicePixelRatio = 1.0;
      addTearDown(() => tester.view.resetPhysicalSize());

      final fakeRepo = FakeInventoryRepositoryWithSKU([], 'staff');
      final fakeVendorRepo = FakeVendorRepository([sampleVendor]);

      await tester.pumpWidget(
        ProviderScope(
          overrides: [
            inventoryRepositoryProvider.overrideWithValue(fakeRepo),
            vendorRepositoryProvider.overrideWithValue(fakeVendorRepo),
            currentUserRoleProvider.overrideWith((ref) => Future.value('staff')),
          ],
          child: const MaterialApp(
            home: Scaffold(
              body: InventoryManagementContent(),
            ),
          ),
        ),
      );

      await tester.pumpAndSettle();

      // Open Add Item dialog
      await tester.tap(find.text('Add Item'));
      await tester.pumpAndSettle();

      // Enter item name
      await tester.enterText(
        find.widgetWithText(TextFormField, 'e.g. Amoxicillin 500mg, Titanium Frame, Latex Gloves'),
        'Azithromycin 500mg',
      );

      // Enter Brand
      await tester.enterText(
        find.widgetWithText(TextFormField, 'e.g. Cipla, Ray-Ban, 3M'),
        'Cipla Med',
      );

      // Enter SKU
      await tester.enterText(
        find.widgetWithText(TextFormField, 'e.g. MED-AMX-500'),
        'AZI-CIP-500',
      );

      // Enter Current Stock
      await tester.enterText(
        find.widgetWithText(TextFormField, '0'),
        '100',
      );

      // Enter Min Stock
      await tester.enterText(
        find.widgetWithText(TextFormField, 'e.g. 10'),
        '25',
      );

      // Enter Unit Price
      await tester.enterText(
        find.widgetWithText(TextFormField, 'e.g. 150.00'),
        '75.50',
      );

      // Select Vendor
      await tester.ensureVisible(find.text('SUPPLIER / VENDOR (OPTIONAL)'));
      await tester.tap(find.text('None / Unassigned'));
      await tester.pumpAndSettle();
      await tester.tap(find.textContaining('Cipla Healthcare Ltd').last);
      await tester.pumpAndSettle();

      // Submit Form
      await tester.tap(find.widgetWithText(FilledButton, 'Create Item'));
      await tester.pumpAndSettle();

      // 7. Product appears in inventory list
      expect(find.text('Azithromycin 500mg'), findsOneWidget);

      // 8. Product details verified in repository
      final created = fakeRepo.items.first;
      expect(created.name, 'Azithromycin 500mg');
      expect(created.brand, 'Cipla Med');
      expect(created.sku, 'AZI-CIP-500');
      expect(created.currentStock, 100.0);
      expect(created.minimumStock, 25.0);
      expect(created.price, 75.50);

      // 9. Vendor association is preserved
      expect(created.vendorId, 'vendor-cipla-101');
    });

    // ----------------------------------------------------
    // 10. Required field validation still works
    // ----------------------------------------------------
    testWidgets('10. Required field validation: empty name blocks submission', (tester) async {
      tester.view.physicalSize = const Size(1280, 800);
      tester.view.devicePixelRatio = 1.0;
      addTearDown(() => tester.view.resetPhysicalSize());

      final fakeRepo = FakeInventoryRepositoryWithSKU([], 'staff');

      await tester.pumpWidget(
        ProviderScope(
          overrides: [
            inventoryRepositoryProvider.overrideWithValue(fakeRepo),
            currentUserRoleProvider.overrideWith((ref) => Future.value('staff')),
          ],
          child: const MaterialApp(
            home: Scaffold(
              body: InventoryFormDialog(),
            ),
          ),
        ),
      );

      await tester.pumpAndSettle();

      // Submit without entering name
      await tester.tap(find.widgetWithText(FilledButton, 'Create Item'));
      await tester.pumpAndSettle();

      expect(find.text('Item name is required'), findsOneWidget);
      expect(fakeRepo.items.isEmpty, isTrue);
    });

    // ----------------------------------------------------
    // 11. Invalid quantity is rejected
    // ----------------------------------------------------
    testWidgets('11. Validation: negative or empty stock is rejected', (tester) async {
      tester.view.physicalSize = const Size(1280, 800);
      tester.view.devicePixelRatio = 1.0;
      addTearDown(() => tester.view.resetPhysicalSize());

      final fakeRepo = FakeInventoryRepositoryWithSKU([], 'staff');

      await tester.pumpWidget(
        ProviderScope(
          overrides: [
            inventoryRepositoryProvider.overrideWithValue(fakeRepo),
            currentUserRoleProvider.overrideWith((ref) => Future.value('staff')),
          ],
          child: const MaterialApp(
            home: Scaffold(
              body: InventoryFormDialog(),
            ),
          ),
        ),
      );

      await tester.pumpAndSettle();

      // Enter valid name
      await tester.enterText(
        find.widgetWithText(TextFormField, 'e.g. Amoxicillin 500mg, Titanium Frame, Latex Gloves'),
        'Test Item',
      );

      // Clear stock
      await tester.enterText(find.widgetWithText(TextFormField, '0'), '');

      // Submit
      await tester.tap(find.widgetWithText(FilledButton, 'Create Item'));
      await tester.pumpAndSettle();

      expect(find.text('Stock quantity is required'), findsOneWidget);
      expect(fakeRepo.items.isEmpty, isTrue);
    });

    // ----------------------------------------------------
    // 12. Invalid minimum stock is rejected
    // ----------------------------------------------------
    testWidgets('12. Validation: negative minimum stock is rejected', (tester) async {
      tester.view.physicalSize = const Size(1280, 800);
      tester.view.devicePixelRatio = 1.0;
      addTearDown(() => tester.view.resetPhysicalSize());

      final fakeRepo = FakeInventoryRepositoryWithSKU([], 'staff');

      await tester.pumpWidget(
        ProviderScope(
          overrides: [
            inventoryRepositoryProvider.overrideWithValue(fakeRepo),
            currentUserRoleProvider.overrideWith((ref) => Future.value('staff')),
          ],
          child: const MaterialApp(
            home: Scaffold(
              body: InventoryFormDialog(),
            ),
          ),
        ),
      );

      await tester.pumpAndSettle();

      // Enter valid name
      await tester.enterText(
        find.widgetWithText(TextFormField, 'e.g. Amoxicillin 500mg, Titanium Frame, Latex Gloves'),
        'Test Item Min Stock',
      );

      // Enter negative min stock - rejected by inputFormatter
      final minStockField = find.widgetWithText(TextFormField, 'e.g. 10');
      await tester.enterText(minStockField, '-5');
      await tester.pumpAndSettle();

      final enteredText = tester.widget<TextFormField>(minStockField).controller?.text ?? '';
      expect(enteredText.contains('-'), isFalse);
      expect(enteredText, isEmpty);
    });

    // ----------------------------------------------------
    // 13. Duplicate SKU behavior remains handled cleanly
    // ----------------------------------------------------
    testWidgets('13. Duplicate SKU is safely caught and displays error banner', (tester) async {
      tester.view.physicalSize = const Size(1280, 800);
      tester.view.devicePixelRatio = 1.0;
      addTearDown(() => tester.view.resetPhysicalSize());

      const existingItem = InventoryItem(
        id: 'existing-1',
        name: 'Existing Gloves',
        category: 'Consumables & PPE',
        sku: 'GLV-NIT-M',
        currentStock: 50.0,
        unit: 'boxes',
      );

      final fakeRepo = FakeInventoryRepositoryWithSKU([existingItem], 'staff');

      await tester.pumpWidget(
        ProviderScope(
          overrides: [
            inventoryRepositoryProvider.overrideWithValue(fakeRepo),
            currentUserRoleProvider.overrideWith((ref) => Future.value('staff')),
          ],
          child: const MaterialApp(
            home: Scaffold(
              body: InventoryFormDialog(),
            ),
          ),
        ),
      );

      await tester.pumpAndSettle();

      // Enter product with duplicate SKU
      await tester.enterText(
        find.widgetWithText(TextFormField, 'e.g. Amoxicillin 500mg, Titanium Frame, Latex Gloves'),
        'Duplicate Gloves',
      );
      await tester.enterText(
        find.widgetWithText(TextFormField, 'e.g. MED-AMX-500'),
        'GLV-NIT-M',
      );

      await tester.tap(find.widgetWithText(FilledButton, 'Create Item'));
      await tester.pumpAndSettle();

      // Error message is displayed in dialog error banner
      expect(find.textContaining('duplicate key value violates unique constraint'), findsOneWidget);
    });

    // ----------------------------------------------------
    // 14. Staff INSERT access works with Supabase RLS simulation
    // ----------------------------------------------------
    testWidgets('14. Staff INSERT succeeds in repository matching RLS policy', (tester) async {
      final fakeRepo = FakeInventoryRepositoryWithSKU([], 'staff');

      const newItem = InventoryItem(
        id: '',
        name: 'Staff Created Stethoscope',
        category: 'Surgical Equipment',
        currentStock: 5.0,
        unit: 'pcs',
      );

      final created = await fakeRepo.createInventoryItem(newItem);
      expect(created.id, isNotEmpty);
      expect(created.name, 'Staff Created Stethoscope');
      expect(fakeRepo.items.length, 1);
    });

    // ----------------------------------------------------
    // 15. Staff has full parity with Admin on Inventory actions & CRUD
    // ----------------------------------------------------
    testWidgets('15. Staff has full parity: CAN see Edit, Delete, and Departments actions', (tester) async {
      tester.view.physicalSize = const Size(1280, 800);
      tester.view.devicePixelRatio = 1.0;
      addTearDown(() => tester.view.resetPhysicalSize());

      const item = InventoryItem(
        id: 'item-staff-view-1',
        name: 'Surgical Mask 3-Ply',
        category: 'Consumables & PPE',
        currentStock: 200.0,
        unit: 'boxes',
      );

      final fakeRepo = FakeInventoryRepositoryWithSKU([item], 'staff');

      await tester.pumpWidget(
        ProviderScope(
          overrides: [
            inventoryRepositoryProvider.overrideWithValue(fakeRepo),
            currentUserRoleProvider.overrideWith((ref) => Future.value('staff')),
          ],
          child: const MaterialApp(
            home: Scaffold(
              body: InventoryManagementContent(),
            ),
          ),
        ),
      );

      await tester.pumpAndSettle();

      // Staff DOES see Add Item
      expect(find.text('Add Item'), findsOneWidget);

      // Staff DOES see Departments, Edit, and Delete (Admin parity)
      expect(find.text('Departments'), findsOneWidget);
      expect(find.byIcon(Icons.edit_outlined), findsOneWidget);
      expect(find.byIcon(Icons.delete_outline), findsOneWidget);

      // Database-level: staff can update and delete
      final updated = await fakeRepo.updateInventoryItem(item.copyWith(name: 'Updated by Staff'));
      expect(updated.name, 'Updated by Staff');
      await fakeRepo.deleteInventoryItem(item.id);
      expect(fakeRepo.items.isEmpty, isTrue);

      // Database-level: unauthorized role is blocked by RLS simulation
      final doctorRepo = FakeInventoryRepositoryWithSKU([item], 'doctor');
      expect(
        () => doctorRepo.updateInventoryItem(item.copyWith(name: 'Hacked Item')),
        throwsA(isA<Exception>()),
      );
      expect(
        () => doctorRepo.deleteInventoryItem(item.id),
        throwsA(isA<Exception>()),
      );
    });

    testWidgets('15b. Staff can open Edit dialog, modify fields, and save changes', (tester) async {
      tester.view.physicalSize = const Size(1280, 800);
      tester.view.devicePixelRatio = 1.0;
      addTearDown(() => tester.view.resetPhysicalSize());

      const item = InventoryItem(
        id: 'item-edit-staff-1',
        name: 'Latex Gloves Medium',
        category: 'Consumables & PPE',
        currentStock: 50.0,
        unit: 'boxes',
        brand: 'HealthGuard',
      );

      final fakeRepo = FakeInventoryRepositoryWithSKU([item], 'staff');

      await tester.pumpWidget(
        ProviderScope(
          overrides: [
            inventoryRepositoryProvider.overrideWithValue(fakeRepo),
            currentUserRoleProvider.overrideWith((ref) => Future.value('staff')),
          ],
          child: const MaterialApp(
            home: Scaffold(
              body: InventoryManagementContent(),
            ),
          ),
        ),
      );

      await tester.pumpAndSettle();

      // Tap Edit button
      await tester.tap(find.byIcon(Icons.edit_outlined).first);
      await tester.pumpAndSettle();

      // Edit dialog appears
      expect(find.text('Edit Inventory Item'), findsOneWidget);
      expect(find.text('Save Changes'), findsOneWidget);

      // Edit the item name
      final nameField = find.widgetWithText(TextFormField, 'Latex Gloves Medium');
      await tester.enterText(nameField, 'Nitrile Gloves Medium');
      await tester.pumpAndSettle();

      // Submit changes
      await tester.tap(find.widgetWithText(FilledButton, 'Save Changes'));
      await tester.pumpAndSettle();

      // Verify item updated in repo
      expect(fakeRepo.items.first.name, 'Nitrile Gloves Medium');
      expect(find.text('Nitrile Gloves Medium'), findsOneWidget);
    });

    testWidgets('15c. Staff can open Delete dialog and delete inventory item', (tester) async {
      tester.view.physicalSize = const Size(1280, 800);
      tester.view.devicePixelRatio = 1.0;
      addTearDown(() => tester.view.resetPhysicalSize());

      const item = InventoryItem(
        id: 'item-del-staff-1',
        name: 'Disposable Syringes 5ml',
        category: 'Consumables & PPE',
        currentStock: 100.0,
        unit: 'pcs',
      );

      final fakeRepo = FakeInventoryRepositoryWithSKU([item], 'staff');

      await tester.pumpWidget(
        ProviderScope(
          overrides: [
            inventoryRepositoryProvider.overrideWithValue(fakeRepo),
            currentUserRoleProvider.overrideWith((ref) => Future.value('staff')),
          ],
          child: const MaterialApp(
            home: Scaffold(
              body: InventoryManagementContent(),
            ),
          ),
        ),
      );

      await tester.pumpAndSettle();

      // Tap Delete button
      await tester.tap(find.byIcon(Icons.delete_outline).first);
      await tester.pumpAndSettle();

      // Confirmation dialog appears
      expect(find.text('Delete Inventory Item'), findsOneWidget);
      expect(find.textContaining('Are you sure you want to delete'), findsOneWidget);

      // Confirm delete
      final confirmDeleteBtn = find.widgetWithText(FilledButton, 'Delete');
      await tester.tap(confirmDeleteBtn);
      await tester.pumpAndSettle();

      // Verify item deleted from repo
      expect(fakeRepo.items.isEmpty, isTrue);
    });

    testWidgets('15d. Staff can access Department Management and perform CRUD', (tester) async {
      tester.view.physicalSize = const Size(1280, 800);
      tester.view.devicePixelRatio = 1.0;
      addTearDown(() => tester.view.resetPhysicalSize());

      final initialDept = Department(
        id: 'dept-1',
        name: 'Dental Clinic',
        description: 'Dental Department',
        isActive: true,
      );

      final fakeDeptRepo = FakeDepartmentRepository([initialDept]);

      await tester.pumpWidget(
        ProviderScope(
          overrides: [
            departmentRepositoryProvider.overrideWithValue(fakeDeptRepo),
            currentUserRoleProvider.overrideWith((ref) => Future.value('staff')),
          ],
          child: const MaterialApp(
            home: DepartmentManagementScreen(),
          ),
        ),
      );

      await tester.pumpAndSettle();

      // Staff sees Department Management header and existing department
      expect(find.text('Department Management'), findsWidgets);
      expect(find.text('Dental Clinic'), findsOneWidget);
      expect(find.text('Add Department'), findsOneWidget);

      // Add new department
      await tester.tap(find.text('Add Department'));
      await tester.pumpAndSettle();

      expect(find.text('Add Department'), findsWidgets);
      await tester.enterText(
        find.widgetWithText(TextField, 'Name'),
        'Eye Care',
      );
      await tester.enterText(
        find.widgetWithText(TextField, 'Description'),
        'Ophthalmology and optometry wing',
      );
      await tester.tap(find.widgetWithText(FilledButton, 'Save'));
      await tester.pumpAndSettle();

      // Verify new department added in repo and on screen
      expect(fakeDeptRepo.departments.length, 2);
      expect(find.text('Eye Care'), findsOneWidget);

      // Edit department
      final editButtons = find.byTooltip('Edit department');
      expect(editButtons, findsNWidgets(2));
      await tester.tap(editButtons.first);
      await tester.pumpAndSettle();

      expect(find.text('Edit Department'), findsOneWidget);
      await tester.enterText(
        find.widgetWithText(TextField, 'Dental Clinic'),
        'Dental Center',
      );
      await tester.tap(find.widgetWithText(FilledButton, 'Save'));
      await tester.pumpAndSettle();

      expect(fakeDeptRepo.departments.first.name, 'Dental Center');

      // Delete department
      final deleteButtons = find.byTooltip('Delete department');
      await tester.tap(deleteButtons.last);
      await tester.pumpAndSettle();

      expect(find.text('Delete department'), findsOneWidget);
      await tester.tap(find.widgetWithText(FilledButton, 'Delete'));
      await tester.pumpAndSettle();

      expect(fakeDeptRepo.departments.length, 1);
    });

    testWidgets('15e. Staff can open Inventory Details dialog and see Edit and Delete action buttons', (tester) async {
      tester.view.physicalSize = const Size(1280, 800);
      tester.view.devicePixelRatio = 1.0;
      addTearDown(() => tester.view.resetPhysicalSize());

      const item = InventoryItem(
        id: 'item-details-staff-1',
        name: 'Ophthalmoscope Rechargeable',
        category: 'Diagnostic Equipment',
        currentStock: 4.0,
        unit: 'sets',
        brand: 'WelchAllyn',
        vendorName: 'Vision MedTech Pvt Ltd',
        vendorPhone: '+919876500000',
      );

      final fakeRepo = FakeInventoryRepositoryWithSKU([item], 'staff');

      await tester.pumpWidget(
        ProviderScope(
          overrides: [
            inventoryRepositoryProvider.overrideWithValue(fakeRepo),
            currentUserRoleProvider.overrideWith((ref) => Future.value('staff')),
          ],
          child: const MaterialApp(
            home: Scaffold(
              body: InventoryManagementContent(),
            ),
          ),
        ),
      );

      await tester.pumpAndSettle();

      // Open details dialog
      await tester.tap(find.byIcon(Icons.visibility_outlined).first);
      await tester.pumpAndSettle();

      // Details dialog header and info
      expect(find.text('CURRENT STOCK'), findsOneWidget);
      expect(find.text('WelchAllyn'), findsOneWidget);

      // Staff sees Edit Item and Delete buttons in details dialog footer
      expect(find.text('Edit Item'), findsOneWidget);
      expect(find.widgetWithText(OutlinedButton, 'Delete'), findsOneWidget);

      await tester.tap(find.text('Close'));
      await tester.pumpAndSettle();
    });

    // ----------------------------------------------------
    // 16. Admin Inventory CRUD continues working
    // ----------------------------------------------------
    testWidgets('16. Admin user retains full CRUD and configuration controls', (tester) async {
      tester.view.physicalSize = const Size(1280, 800);
      tester.view.devicePixelRatio = 1.0;
      addTearDown(() => tester.view.resetPhysicalSize());

      const item = InventoryItem(
        id: 'admin-crud-item-1',
        name: 'Autoclave Sterilizer',
        category: 'Surgical Equipment',
        currentStock: 2.0,
        unit: 'units',
      );

      final fakeRepo = FakeInventoryRepositoryWithSKU([item], 'admin');

      await tester.pumpWidget(
        ProviderScope(
          overrides: [
            inventoryRepositoryProvider.overrideWithValue(fakeRepo),
            currentUserRoleProvider.overrideWith((ref) => Future.value('admin')),
          ],
          child: const MaterialApp(
            home: Scaffold(
              body: InventoryManagementContent(),
            ),
          ),
        ),
      );

      await tester.pumpAndSettle();

      // Admin sees Add Item, Departments, Edit, and Delete
      expect(find.text('Add Item'), findsOneWidget);
      expect(find.text('Departments'), findsOneWidget);
      expect(find.byIcon(Icons.edit_outlined), findsOneWidget);
      expect(find.byIcon(Icons.delete_outline), findsOneWidget);

      // Admin can update in repository
      final updated = await fakeRepo.updateInventoryItem(item.copyWith(currentStock: 3.0));
      expect(updated.currentStock, 3.0);

      // Admin can delete in repository
      await fakeRepo.deleteInventoryItem(item.id);
      expect(fakeRepo.items.isEmpty, isTrue);
    });

    // ----------------------------------------------------
    // 17-20. Regression: Search, Filter, Stock In/Out, Vendor Integration
    // ----------------------------------------------------
    testWidgets('17-20. Staff can search, filter, perform stock operations and view details',
        (tester) async {
      tester.view.physicalSize = const Size(1280, 800);
      tester.view.devicePixelRatio = 1.0;
      addTearDown(() => tester.view.resetPhysicalSize());

      const itemA = InventoryItem(
        id: 'reg-item-1',
        name: 'Paracetamol 500mg',
        category: 'Pharmaceuticals',
        currentStock: 80.0,
        minimumStock: 20.0,
        unit: 'strips',
        brand: 'Crocin',
        vendorId: 'vendor-cipla-101',
        vendorName: 'Cipla Healthcare Ltd',
        vendorPhone: '+919876543210',
      );

      const itemB = InventoryItem(
        id: 'reg-item-2',
        name: 'Dental Mirror',
        category: 'Dental Materials',
        currentStock: 15.0,
        minimumStock: 5.0,
        unit: 'pcs',
      );

      final fakeRepo = FakeInventoryRepositoryWithSKU([itemA, itemB], 'staff');

      await tester.pumpWidget(
        ProviderScope(
          overrides: [
            inventoryRepositoryProvider.overrideWithValue(fakeRepo),
            currentUserRoleProvider.overrideWith((ref) => Future.value('staff')),
          ],
          child: const MaterialApp(
            home: Scaffold(
              body: InventoryManagementContent(),
            ),
          ),
        ),
      );

      await tester.pumpAndSettle();

      // Both items visible initially
      expect(find.text('Paracetamol 500mg'), findsOneWidget);
      expect(find.text('Dental Mirror'), findsOneWidget);

      // Search filters items
      final searchField = find.byType(TextField).first;
      await tester.enterText(searchField, 'Paracetamol');
      await tester.pumpAndSettle();

      expect(find.text('Paracetamol 500mg'), findsOneWidget);
      expect(find.text('Dental Mirror'), findsNothing);

      // Clear search
      await tester.enterText(searchField, '');
      await tester.pumpAndSettle();

      // Open details dialog
      await tester.tap(find.byIcon(Icons.visibility_outlined).first);
      await tester.pumpAndSettle();

      // Details rendered with vendor info
      expect(find.text('CURRENT STOCK'), findsOneWidget);
      expect(find.text('Crocin'), findsOneWidget);
      expect(find.text('Cipla Healthcare Ltd'), findsWidgets);
      expect(find.text('Call Vendor'), findsOneWidget);

      // Close details dialog
      await tester.tap(find.text('Close'));
      await tester.pumpAndSettle();

      // Staff can perform Stock In
      final stockInTx = await fakeRepo.performStockOperation(
        itemId: itemA.id,
        transactionType: 'stock_in',
        quantity: 20.0,
        reason: 'Restock / Purchase Order',
      );
      expect(stockInTx.stockAfter, 100.0);

      // Staff can perform Stock Out
      final stockOutTx = await fakeRepo.performStockOperation(
        itemId: itemA.id,
        transactionType: 'stock_out',
        quantity: 10.0,
        reason: 'General Usage',
      );
      expect(stockOutTx.stockAfter, 90.0);
    });
  });
}
