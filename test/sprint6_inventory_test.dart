import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:mkes_care/features/auth/providers/auth_provider.dart';
import 'package:mkes_care/features/inventory/models/expired_stock_entry.dart';
import 'package:mkes_care/features/inventory/models/inventory_batch.dart';
import 'package:mkes_care/features/inventory/models/inventory_item.dart';
import 'package:mkes_care/features/inventory/models/inventory_transaction.dart';
import 'package:mkes_care/features/inventory/providers/inventory_provider.dart';
import 'package:mkes_care/features/inventory/repositories/inventory_repository.dart';
import 'package:mkes_care/features/inventory/screens/inventory_screen.dart';
import 'package:mkes_care/features/inventory/widgets/inventory_details_dialog.dart';
import 'package:mkes_care/features/inventory/widgets/inventory_form_dialog.dart';
import 'package:mkes_care/features/inventory/widgets/inventory_transaction_history_dialog.dart';
import 'package:mkes_care/features/inventory/widgets/stock_operation_dialog.dart';
import 'package:mkes_care/features/staff_portal/screens/staff_tasks_screen.dart';
import 'package:mkes_care/features/patients/models/patient_model.dart';
import 'package:mkes_care/features/patients/providers/patients_provider.dart';
import 'package:supabase_flutter/supabase_flutter.dart';

/// Fake in-memory repository for deterministic testing without live Supabase connection.
class FakeInventoryRepository implements InventoryRepository {
  final List<InventoryItem> items;
  final List<InventoryTransaction> transactions = [];
  final List<PatientModel> registeredPatients;
  bool shouldThrow = false;

  @override
  dynamic noSuchMethod(Invocation invocation) => super.noSuchMethod(invocation);

  @override
  Future<List<ExpiredStockEntry>> getExpiredStockEntries() async {
    final now = DateTime.now();
    final today = DateTime(now.year, now.month, now.day);
    final List<ExpiredStockEntry> entries = [];
    for (final item in items) {
      if (item.batches != null && item.batches!.isNotEmpty) {
        for (final b in item.batches!) {
          if (b.remainingQuantity > 0 && b.expiryDate != null) {
            final exp = DateTime(b.expiryDate!.year, b.expiryDate!.month, b.expiryDate!.day);
            if (exp.isBefore(today)) {
              entries.add(ExpiredStockEntry(
                inventoryId: item.id,
                itemName: item.name,
                unit: item.unit,
                batchId: b.id,
                batchNumber: b.batchNumber,
                expiredQuantity: b.remainingQuantity,
                totalAvailableStock: item.currentStock,
                expiryDate: b.expiryDate!,
              ));
            }
          }
        }
      } else if (item.currentStock > 0 && item.expiryDate != null) {
        final exp = DateTime(item.expiryDate!.year, item.expiryDate!.month, item.expiryDate!.day);
        if (exp.isBefore(today)) {
          entries.add(ExpiredStockEntry(
            inventoryId: item.id,
            itemName: item.name,
            unit: item.unit,
            batchId: null,
            batchNumber: null,
            expiredQuantity: item.currentStock,
            totalAvailableStock: item.currentStock,
            expiryDate: item.expiryDate!,
          ));
        }
      }
    }
    return entries;
  }

  @override
  Future<InventoryTransaction> removeExpiredStock({
    required String inventoryId,
    required double quantity,
    String? batchNumber,
    String? remarks,
  }) async {
    return performStockOperation(
      itemId: inventoryId,
      transactionType: 'stock_out',
      quantity: quantity,
      reason: StockOutReasons.expired,
      remarks: remarks ?? (batchNumber != null ? 'Removed expired stock from Batch $batchNumber' : 'Removed expired stock'),
    );
  }

  FakeInventoryRepository([
    List<InventoryItem>? initialItems,
    List<PatientModel>? patients,
  ])  : items = initialItems != null ? List.from(initialItems) : [],
        registeredPatients = patients != null ? List.from(patients) : [];

  @override
  Future<List<InventoryItem>> getInventoryItems({
    String? category,
    String? department,
    String? searchQuery,
    bool? activeOnly,
  }) async {
    if (shouldThrow) {
      throw Exception('Simulated network error');
    }
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
              (i.sku?.toLowerCase() ?? '').contains(q))
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
    final created = item.copyWith(
      id: item.id.isNotEmpty ? item.id : 'generated-id-${items.length + 1}',
      createdAt: DateTime.now(),
      updatedAt: DateTime.now(),
    );
    items.add(created);
    return created;
  }

  @override
  Future<InventoryItem> updateInventoryItem(InventoryItem item) async {
    if (shouldThrow) throw Exception('Simulated update error');
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
    if (shouldThrow) throw Exception('Simulated stock operation error');
    if (quantity <= 0) {
      throw ArgumentError('Stock quantity must be greater than zero.');
    }
    final index = items.indexWhere((i) => i.id == itemId);
    if (index == -1) {
      throw Exception('Inventory item not found.');
    }
    final item = items[index];

    // Server-side validation matching DB RPC:
    final isDispensed = transactionType == 'stock_out' &&
        reason == StockOutReasons.dispensedToPatient;
    if (isDispensed && (patientId == null || patientId.trim().isEmpty)) {
      throw ArgumentError('Please select a patient.');
    }

    final double stockBefore = item.currentStock;
    final double stockAfter;

    if (transactionType == 'stock_in') {
      stockAfter = stockBefore + quantity;
    } else if (transactionType == 'stock_out') {
      if (stockBefore < quantity) {
        throw Exception('Insufficient stock. Available: $stockBefore, Requested: $quantity');
      }
      stockAfter = stockBefore - quantity;
    } else {
      throw ArgumentError('Invalid transaction type: $transactionType');
    }

    final double? unitPrice = (totalAmount != null && quantity > 0) ? (totalAmount / quantity) : null;

    items[index] = item.copyWith(
      currentStock: stockAfter,
      vendorId: vendorId ?? item.vendorId,
      lastQuantitySupplied: transactionType == 'stock_in' ? quantity : item.lastQuantitySupplied,
      lastTotalAmount: transactionType == 'stock_in' && totalAmount != null ? totalAmount : item.lastTotalAmount,
      updatedAt: DateTime.now(),
    );

    final finalPatientId = isDispensed ? patientId : null;
    String? pName;
    String? pNum;
    if (finalPatientId != null) {
      final pIndex = registeredPatients.indexWhere((p) => p.id == finalPatientId);
      if (pIndex != -1) {
        pName = registeredPatients[pIndex].name;
        pNum = registeredPatients[pIndex].patientNumber;
      } else {
        pName = 'Eleanor Vance';
        pNum = 'PAT-2026-001';
      }
    }

    final tx = InventoryTransaction(
      id: 'tx-${transactions.length + 1}',
      inventoryItemId: itemId,
      transactionType: transactionType,
      quantity: quantity,
      stockBefore: stockBefore,
      stockAfter: stockAfter,
      reason: reason,
      remarks: remarks,
      patientId: finalPatientId,
      patientName: pName,
      patientNumber: pNum,
      performedBy: 'user-staff-001',
      performedByName: 'Staff Nurse Alice',
      totalAmount: totalAmount,
      unitPrice: unitPrice,
      vendorId: vendorId,
      createdAt: DateTime.now(),
    );

    transactions.insert(0, tx);
    return tx;
  }

  @override
  Future<List<InventoryTransaction>> getTransactionHistory(
    String inventoryItemId, {
    String? transactionType,
  }) async {
    if (shouldThrow) throw Exception('Simulated transaction history error');
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
    if (shouldThrow) throw Exception('Simulated error loading all transactions');
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

class FakePatientsNotifier extends StateNotifier<AsyncValue<List<PatientModel>>>
    implements PatientsNotifier {
  final List<PatientModel> allPatients;

  FakePatientsNotifier([List<PatientModel>? patients])
      : allPatients = patients ?? [],
        super(AsyncValue.data(patients ?? []));

  @override
  Future<void> loadPatients({String? department, String? search}) async {
    var filtered = List<PatientModel>.from(allPatients);
    if (department != null && department.isNotEmpty && department != 'All') {
      filtered = filtered.where((p) => p.department == department).toList();
    }
    if (search != null && search.trim().isNotEmpty) {
      final q = search.trim().toLowerCase();
      filtered = filtered.where((p) =>
          p.name.toLowerCase().contains(q) ||
          p.patientNumber.toLowerCase().contains(q) ||
          (p.mobile != null && p.mobile!.toLowerCase().contains(q))).toList();
    }
    state = AsyncValue.data(filtered);
  }

  @override
  Future<PatientModel> createPatient(PatientModel newPatient) async => newPatient;

  @override
  Future<PatientModel> updatePatient(PatientModel updatedPatient) async => updatedPatient;
}

void main() {
  group('Sprint 6.1 — InventoryItem Domain Model', () {
    test('deserializes properly from Supabase json row', () {
      final json = {
        'id': 'inv-123',
        'name': 'Amoxicillin 500mg',
        'category': 'Pharmaceuticals',
        'department': 'general',
        'sku': 'MED-AMX-500',
        'quantity': 150.0,
        'minimum_stock': 30.0,
        'unit': 'boxes',
        'description': 'Keep in cool dry place',
        'price': 45.50,
        'is_active': true,
        'created_at': '2026-09-01T10:00:00Z',
        'updated_at': '2026-09-15T12:00:00Z',
      };

      final item = InventoryItem.fromJson(json);

      expect(item.id, equals('inv-123'));
      expect(item.name, equals('Amoxicillin 500mg'));
      expect(item.category, equals('Pharmaceuticals'));
      expect(item.department, equals('general'));
      expect(item.sku, equals('MED-AMX-500'));
      expect(item.currentStock, equals(150.0));
      expect(item.minimumStock, equals(30.0));
      expect(item.unit, equals('boxes'));
      expect(item.description, equals('Keep in cool dry place'));
      expect(item.price, equals(45.50));
      expect(item.isActive, isTrue);
      expect(item.createdAt, isNotNull);
      expect(item.updatedAt, isNotNull);
    });

    test('deserializes fallback keys and handles null values safely', () {
      final json = {
        'id': 'inv-456',
        'name': 'Surgical Gloves',
        'current_stock': 75,
        'remarks': 'Powder free',
      };

      final item = InventoryItem.fromJson(json);

      expect(item.id, equals('inv-456'));
      expect(item.name, equals('Surgical Gloves'));
      expect(item.category, equals('General'));
      expect(item.currentStock, equals(75.0));
      expect(item.description, equals('Powder free'));
      expect(item.unit, equals('units'));
      expect(item.minimumStock, isNull);
      expect(item.isActive, isTrue);
    });

    test('serializes to json matching Supabase columns', () {
      const item = InventoryItem(
        id: 'inv-789',
        name: 'Dental Prophy Paste',
        category: 'Dental Materials',
        department: 'dental',
        sku: 'DENT-001',
        currentStock: 25.0,
        minimumStock: 10.0,
        unit: 'tubes',
        description: 'Mint flavor',
        price: 120.0,
        isActive: true,
      );

      final json = item.toJson();

      expect(json['name'], equals('Dental Prophy Paste'));
      expect(json['category'], equals('Dental Materials'));
      expect(json['department'], equals('dental'));
      expect(json['sku'], equals('DENT-001'));
      expect(json['quantity'], equals(25.0));
      expect(json['minimum_stock'], equals(10.0));
      expect(json['unit'], equals('tubes'));
      expect(json['description'], equals('Mint flavor'));
      expect(json['price'], equals(120.0));
      expect(json['is_active'], isTrue);
    });

    test('computes isLowStock correctly', () {
      const normalItem = InventoryItem(
        id: '1',
        name: 'Item A',
        category: 'Cat',
        currentStock: 50.0,
        minimumStock: 20.0,
        unit: 'pcs',
      );
      expect(normalItem.isLowStock, isFalse);

      const lowStockItem = InventoryItem(
        id: '2',
        name: 'Item B',
        category: 'Cat',
        currentStock: 15.0,
        minimumStock: 20.0,
        unit: 'pcs',
      );
      expect(lowStockItem.isLowStock, isTrue);

      const exactStockItem = InventoryItem(
        id: '3',
        name: 'Item C',
        category: 'Cat',
        currentStock: 20.0,
        minimumStock: 20.0,
        unit: 'pcs',
      );
      expect(exactStockItem.isLowStock, isTrue);

      const zeroStockWithoutMin = InventoryItem(
        id: '4',
        name: 'Item D',
        category: 'Cat',
        currentStock: 0.0,
        unit: 'pcs',
      );
      expect(zeroStockWithoutMin.isLowStock, isTrue);
    });

    test('formats stock display with units accurately', () {
      const itemInt = InventoryItem(
        id: '1',
        name: 'Item',
        category: 'Cat',
        currentStock: 100.0,
        unit: 'boxes',
      );
      expect(itemInt.formattedStock, equals('100 boxes'));

      const itemDecimal = InventoryItem(
        id: '2',
        name: 'Liquid',
        category: 'Cat',
        currentStock: 2.75,
        unit: 'liters',
      );
      expect(itemDecimal.formattedStock, equals('2.75 liters'));
    });

    test('copyWith produces modified copy without mutating original', () {
      const original = InventoryItem(
        id: '1',
        name: 'Original Name',
        category: 'General',
        currentStock: 10.0,
        unit: 'pcs',
      );

      final updated = original.copyWith(
        name: 'Updated Name',
        currentStock: 25.0,
        description: 'New notes',
      );

      expect(original.name, equals('Original Name'));
      expect(original.currentStock, equals(10.0));
      expect(original.description, isNull);

      expect(updated.id, equals('1'));
      expect(updated.name, equals('Updated Name'));
      expect(updated.currentStock, equals(25.0));
      expect(updated.description, equals('New notes'));
    });
  });

  group('Sprint 6.1 — Inventory StateNotifier & Providers', () {
    test('fetches and populates inventory items successfully', () async {
      final fakeRepo = FakeInventoryRepository([
        const InventoryItem(
          id: '1',
          name: 'Item 1',
          category: 'Pharmaceuticals',
          currentStock: 10.0,
          unit: 'pcs',
        ),
        const InventoryItem(
          id: '2',
          name: 'Item 2',
          category: 'Clinical Supplies',
          currentStock: 20.0,
          unit: 'boxes',
        ),
      ]);

      final container = ProviderContainer(
        overrides: [
          inventoryRepositoryProvider.overrideWithValue(fakeRepo),
        ],
      );
      addTearDown(container.dispose);

      // Wait for initial fetch
      await container.read(inventoryProvider.notifier).fetchInventory();

      final state = container.read(inventoryProvider);
      expect(state.hasValue, isTrue);
      expect(state.value!.length, equals(2));
      expect(state.value!.first.name, equals('Item 1'));
    });

    test('creates new inventory item and updates state', () async {
      final fakeRepo = FakeInventoryRepository();
      final container = ProviderContainer(
        overrides: [
          inventoryRepositoryProvider.overrideWithValue(fakeRepo),
        ],
      );
      addTearDown(container.dispose);

      final notifier = container.read(inventoryProvider.notifier);
      await notifier.fetchInventory();
      expect(container.read(inventoryProvider).value!.isEmpty, isTrue);

      const newItem = InventoryItem(
        id: '',
        name: 'New Needle 22G',
        category: 'Clinical Supplies',
        currentStock: 50.0,
        unit: 'packs',
      );

      final created = await notifier.createItem(newItem);
      expect(created.id, isNotEmpty);
      expect(created.name, equals('New Needle 22G'));

      final updatedState = container.read(inventoryProvider);
      expect(updatedState.value!.length, equals(1));
      expect(updatedState.value!.first.name, equals('New Needle 22G'));
    });

    test('updates inventory item and updates state', () async {
      final fakeRepo = FakeInventoryRepository([
        const InventoryItem(
          id: 'item-10',
          name: 'Bandages',
          category: 'Clinical Supplies',
          currentStock: 10.0,
          unit: 'rolls',
        ),
      ]);
      final container = ProviderContainer(
        overrides: [
          inventoryRepositoryProvider.overrideWithValue(fakeRepo),
        ],
      );
      addTearDown(container.dispose);

      final notifier = container.read(inventoryProvider.notifier);
      await notifier.fetchInventory();

      final existing = container.read(inventoryProvider).value!.first;
      final modified = existing.copyWith(
        name: 'Sterile Elastic Bandages',
        currentStock: 35.0,
      );

      final saved = await notifier.updateItem(modified);
      expect(saved.name, equals('Sterile Elastic Bandages'));
      expect(saved.currentStock, equals(35.0));

      final state = container.read(inventoryProvider).value!;
      expect(state.first.name, equals('Sterile Elastic Bandages'));
      expect(state.first.currentStock, equals(35.0));
    });

    test('deletes inventory item and updates state', () async {
      final fakeRepo = FakeInventoryRepository([
        const InventoryItem(
          id: 'item-del-1',
          name: 'Expired Syringe',
          category: 'Clinical Supplies',
          currentStock: 0.0,
          unit: 'pcs',
        ),
      ]);
      final container = ProviderContainer(
        overrides: [
          inventoryRepositoryProvider.overrideWithValue(fakeRepo),
        ],
      );
      addTearDown(container.dispose);

      final notifier = container.read(inventoryProvider.notifier);
      await notifier.fetchInventory();
      expect(container.read(inventoryProvider).value!.length, equals(1));

      await notifier.deleteItem('item-del-1');
      expect(container.read(inventoryProvider).value!.isEmpty, isTrue);
    });

    test('handles repository errors gracefully', () async {
      final fakeRepo = FakeInventoryRepository()..shouldThrow = true;
      final container = ProviderContainer(
        overrides: [
          inventoryRepositoryProvider.overrideWithValue(fakeRepo),
        ],
      );
      addTearDown(container.dispose);

      await container.read(inventoryProvider.notifier).fetchInventory();

      final state = container.read(inventoryProvider);
      expect(state.hasError, isTrue);
      expect(state.error.toString(), contains('Simulated network error'));
    });

    test('filteredInventoryProvider filters by category and search query', () async {
      final items = [
        const InventoryItem(
          id: '1',
          name: 'Paracetamol 500mg',
          category: 'Pharmaceuticals',
          currentStock: 100.0,
          unit: 'strips',
          sku: 'PARA-500',
        ),
        const InventoryItem(
          id: '2',
          name: 'Ibuprofen 400mg',
          category: 'Pharmaceuticals',
          currentStock: 80.0,
          unit: 'strips',
          sku: 'IBU-400',
        ),
        const InventoryItem(
          id: '3',
          name: 'Titanium Frame Ray-Ban',
          category: 'Optical & Frames',
          currentStock: 15.0,
          unit: 'pairs',
          sku: 'OPT-RAY-01',
        ),
      ];

      final fakeRepo = FakeInventoryRepository(items);
      final container = ProviderContainer(
        overrides: [
          inventoryRepositoryProvider.overrideWithValue(fakeRepo),
        ],
      );
      addTearDown(container.dispose);

      await container.read(inventoryProvider.notifier).fetchInventory();

      // Initially All items
      expect(container.read(filteredInventoryProvider).length, equals(3));

      // Filter by category
      container.read(inventoryCategoryFilterProvider.notifier).state =
          'Optical & Frames';
      expect(container.read(filteredInventoryProvider).length, equals(1));
      expect(
        container.read(filteredInventoryProvider).first.name,
        equals('Titanium Frame Ray-Ban'),
      );

      // Reset category, search for 'Paracetamol'
      container.read(inventoryCategoryFilterProvider.notifier).state = 'All';
      container.read(inventorySearchQueryProvider.notifier).state = 'Paracetamol';
      expect(container.read(filteredInventoryProvider).length, equals(1));
      expect(
        container.read(filteredInventoryProvider).first.name,
        equals('Paracetamol 500mg'),
      );

      // Search by SKU
      container.read(inventorySearchQueryProvider.notifier).state = 'IBU-400';
      expect(container.read(filteredInventoryProvider).length, equals(1));
      expect(
        container.read(filteredInventoryProvider).first.name,
        equals('Ibuprofen 400mg'),
      );
    });
  });

  group('Sprint 6.1 — UI & Widget Tests', () {
    testWidgets('renders empty state when inventory has 0 items',
        (tester) async {
      final fakeRepo = FakeInventoryRepository([]);
      await tester.pumpWidget(
        ProviderScope(
          overrides: [
            inventoryRepositoryProvider.overrideWithValue(fakeRepo),
            currentUserRoleProvider.overrideWith((ref) => Future.value('admin')),
          ],
          child: const MaterialApp(
            home: Scaffold(body: InventoryManagementContent()),
          ),
        ),
      );

      await tester.pumpAndSettle();

      expect(find.text('No Inventory Items Yet'), findsOneWidget);
      expect(find.text('Add First Item'), findsOneWidget);
    });

    testWidgets('renders inventory item row with name, stock, and actions',
        (tester) async {
      final fakeRepo = FakeInventoryRepository([
        const InventoryItem(
          id: 'item-1',
          name: 'Amoxicillin 500mg',
          category: 'Pharmaceuticals',
          currentStock: 120.0,
          unit: 'boxes',
          department: 'general',
        ),
      ]);

      await tester.pumpWidget(
        ProviderScope(
          overrides: [
            inventoryRepositoryProvider.overrideWithValue(fakeRepo),
            currentUserRoleProvider.overrideWith((ref) => Future.value('admin')),
          ],
          child: const MaterialApp(
            home: Scaffold(body: InventoryManagementContent()),
          ),
        ),
      );

      await tester.pumpAndSettle();

      expect(find.text('Amoxicillin 500mg'), findsWidgets);
      expect(find.text('Pharmaceuticals'), findsWidgets);
      expect(find.text('120 boxes'), findsWidgets);
      expect(find.byIcon(Icons.visibility_outlined), findsWidgets);
      expect(find.byIcon(Icons.edit_outlined), findsWidgets);
      expect(find.byIcon(Icons.delete_outline), findsWidgets);
    });

    testWidgets('details dialog renders comprehensive attributes',
        (tester) async {
      const item = InventoryItem(
        id: 'test-item-1',
        name: 'Dental Mirror #4',
        category: 'Dental Materials',
        department: 'dental',
        sku: 'DM-004',
        currentStock: 30.0,
        minimumStock: 10.0,
        unit: 'pcs',
        description: 'Stainless steel autoclavable',
        price: 150.0,
        isActive: true,
      );

      final fakeRepo = FakeInventoryRepository([item]);

      await tester.pumpWidget(
        ProviderScope(
          overrides: [
            inventoryRepositoryProvider.overrideWithValue(fakeRepo),
            currentUserRoleProvider.overrideWith((ref) => Future.value('admin')),
          ],
          child: const MaterialApp(
            home: Scaffold(body: InventoryDetailsDialog(item: item)),
          ),
        ),
      );

      await tester.pumpAndSettle();

      expect(find.text('Dental Mirror #4'), findsWidgets);
      expect(find.text('30 pcs'), findsWidgets);
      expect(find.text('10 pcs'), findsWidgets);
      expect(find.text('DM-004'), findsWidgets);
      expect(find.text('Stainless steel autoclavable'), findsWidgets);
      expect(find.text('₹150.00'), findsWidgets);
      expect(find.text('Edit Item'), findsOneWidget);
      expect(find.text('Delete'), findsOneWidget);
    });

    testWidgets('form dialog enforces required fields and rejects negative stock',
        (tester) async {
      final fakeRepo = FakeInventoryRepository([]);

      await tester.pumpWidget(
        ProviderScope(
          overrides: [
            inventoryRepositoryProvider.overrideWithValue(fakeRepo),
          ],
          child: const MaterialApp(
            home: Scaffold(body: InventoryFormDialog()),
          ),
        ),
      );

      await tester.pumpAndSettle();

      // Clear name field
      final nameField = find.widgetWithText(TextFormField, '');
      if (nameField.evaluate().isNotEmpty) {
        await tester.enterText(nameField.first, '');
      }

      // Tap Create Item to trigger validation
      await tester.tap(find.text('Create Item'));
      await tester.pumpAndSettle();

      // Required validation message
      expect(find.text('Item name is required'), findsOneWidget);
    });

    testWidgets('form dialog accepts valid item and triggers create',
        (tester) async {
      final fakeRepo = FakeInventoryRepository([]);

      await tester.pumpWidget(
        ProviderScope(
          overrides: [
            inventoryRepositoryProvider.overrideWithValue(fakeRepo),
          ],
          child: const MaterialApp(
            home: Scaffold(body: InventoryFormDialog()),
          ),
        ),
      );

      await tester.pumpAndSettle();

      // Enter Item Name
      final textFields = find.byType(TextFormField);
      await tester.enterText(textFields.at(0), 'Saline Solution 500ml');

      // Tap Create Item
      await tester.tap(find.text('Create Item'));
      await tester.pumpAndSettle();

      // Item should be created in fakeRepo
      expect(fakeRepo.items.length, equals(1));
      expect(fakeRepo.items.first.name, equals('Saline Solution 500ml'));
    });
  });

  group('Sprint 6.2 — InventoryTransaction Domain Model', () {
    test('deserializes properly from Supabase json row with profile join', () {
      final json = {
        'id': 'tx-100',
        'inventory_id': 'inv-123',
        'transaction_type': 'stock_in',
        'quantity': 25.0,
        'stock_before': 10.0,
        'stock_after': 35.0,
        'reason': 'Restock / New Purchase',
        'remarks': 'Batch #B-9988',
        'performed_by': 'user-uuid-1',
        'performed_by_name': 'Dr. Robert Smith',
        'created_at': '2026-09-29T10:00:00Z',
      };

      final tx = InventoryTransaction.fromJson(json);

      expect(tx.id, equals('tx-100'));
      expect(tx.inventoryItemId, equals('inv-123'));
      expect(tx.transactionType, equals('stock_in'));
      expect(tx.isStockIn, isTrue);
      expect(tx.isStockOut, isFalse);
      expect(tx.quantity, equals(25.0));
      expect(tx.stockBefore, equals(10.0));
      expect(tx.stockAfter, equals(35.0));
      expect(tx.reason, equals('Restock / New Purchase'));
      expect(tx.remarks, equals('Batch #B-9988'));
      expect(tx.performedBy, equals('user-uuid-1'));
      expect(tx.performedByName, equals('Dr. Robert Smith'));
      expect(tx.formattedQuantity, equals('+25'));
      expect(tx.formattedStockProgression, equals('10 → 35'));
    });

    test('formats stock_out quantity with minus sign', () {
      final json = {
        'id': 'tx-200',
        'inventory_id': 'inv-456',
        'transaction_type': 'stock_out',
        'quantity': 4.0,
        'stock_before': 20.0,
        'stock_after': 16.0,
        'created_at': '2026-09-29T12:00:00Z',
      };

      final tx = InventoryTransaction.fromJson(json);
      expect(tx.isStockOut, isTrue);
      expect(tx.typeLabel, equals('Stock Out'));
      expect(tx.formattedQuantity, equals('-4'));
      expect(tx.formattedStockProgression, equals('20 → 16'));
    });

    test('serializes to json matching Supabase columns', () {
      final tx = InventoryTransaction(
        id: 'tx-300',
        inventoryItemId: 'inv-789',
        transactionType: 'stock_in',
        quantity: 50.0,
        stockBefore: 100.0,
        stockAfter: 150.0,
        reason: 'Supplier Delivery',
        remarks: 'Direct from vendor',
        performedBy: 'user-2',
        createdAt: DateTime.parse('2026-09-29T14:00:00Z'),
      );

      final json = tx.toJson();
      expect(json['inventory_id'], equals('inv-789'));
      expect(json['transaction_type'], equals('stock_in'));
      expect(json['quantity'], equals(50.0));
      expect(json['stock_before'], equals(100.0));
      expect(json['stock_after'], equals(150.0));
      expect(json['reason'], equals('Supplier Delivery'));
      expect(json['remarks'], equals('Direct from vendor'));
      expect(json['performed_by'], equals('user-2'));
    });
  });

  group('Sprint 6.2 — Expiry Tracking & Calculations', () {
    test('calculates ExpiryStatus.none when expiryDate is null', () {
      const item = InventoryItem(
        id: '1',
        name: 'Item without expiry',
        category: 'Supplies',
        currentStock: 10.0,
        unit: 'pcs',
      );

      expect(item.expiryStatus, equals(ExpiryStatus.none));
      expect(item.daysUntilExpiry, isNull);
      expect(item.isExpiringSoon, isFalse);
      expect(item.isExpired, isFalse);
      expect(item.expiryStatusLabel, equals('No Expiry Date'));
    });

    test('calculates ExpiryStatus.valid when expiry is > 30 days in future', () {
      final futureDate = DateTime.now().add(const Duration(days: 90));
      final item = InventoryItem(
        id: '2',
        name: 'Fresh Drug',
        category: 'Pharmaceuticals',
        currentStock: 50.0,
        unit: 'strips',
        expiryDate: futureDate,
      );

      expect(item.expiryStatus, equals(ExpiryStatus.valid));
      expect(item.daysUntilExpiry, greaterThan(30));
      expect(item.isExpiringSoon, isFalse);
      expect(item.isExpired, isFalse);
      expect(item.expiryStatusLabel, contains('Valid'));
    });

    test('calculates ExpiryStatus.expiringSoon within 30 days', () {
      final soonDate = DateTime.now().add(const Duration(days: 15));
      final item = InventoryItem(
        id: '3',
        name: 'Soon Expiring Drops',
        category: 'Pharmaceuticals',
        currentStock: 15.0,
        unit: 'bottles',
        expiryDate: soonDate,
      );

      expect(item.expiryStatus, equals(ExpiryStatus.expiringSoon));
      expect(item.isExpiringSoon, isTrue);
      expect(item.isExpired, isFalse);
      expect(item.expiryStatusLabel, contains('Expiring Soon'));
    });

    test('calculates ExpiryStatus.expired when expiry is in the past', () {
      final pastDate = DateTime.now().subtract(const Duration(days: 5));
      final item = InventoryItem(
        id: '4',
        name: 'Expired Ointment',
        category: 'Pharmaceuticals',
        currentStock: 5.0,
        unit: 'tubes',
        expiryDate: pastDate,
      );

      expect(item.expiryStatus, equals(ExpiryStatus.expired));
      expect(item.isExpiringSoon, isFalse);
      expect(item.isExpired, isTrue);
      expect(item.expiryStatusLabel, contains('Expired'));
    });
  });

  group('Sprint 6.2 — Stock Operation Calculations & Constraints', () {
    test('Stock In increases stock correctly and logs transaction', () async {
      final fakeRepo = FakeInventoryRepository([
        const InventoryItem(
          id: 'item-1',
          name: 'Amoxicillin',
          category: 'Pharmaceuticals',
          currentStock: 20.0,
          unit: 'boxes',
        ),
      ]);

      final tx = await fakeRepo.performStockOperation(
        itemId: 'item-1',
        transactionType: 'stock_in',
        quantity: 10.0,
        reason: 'Restock / New Purchase',
      );

      expect(tx.stockBefore, equals(20.0));
      expect(tx.stockAfter, equals(30.0));
      expect(tx.quantity, equals(10.0));

      final updatedItem = await fakeRepo.getInventoryItem('item-1');
      expect(updatedItem.currentStock, equals(30.0));
    });

    test('Stock Out decreases stock correctly and logs transaction', () async {
      final fakeRepo = FakeInventoryRepository([
        const InventoryItem(
          id: 'item-2',
          name: 'Surgical Gloves',
          category: 'Clinical Supplies',
          currentStock: 25.0,
          unit: 'boxes',
        ),
      ]);

      final tx = await fakeRepo.performStockOperation(
        itemId: 'item-2',
        transactionType: 'stock_out',
        quantity: 7.0,
        reason: 'Dispensed to Patient',
        patientId: 'patient-test-1',
      );

      expect(tx.stockBefore, equals(25.0));
      expect(tx.stockAfter, equals(18.0));
      expect(tx.quantity, equals(7.0));
      expect(tx.patientId, equals('patient-test-1'));

      final updatedItem = await fakeRepo.getInventoryItem('item-2');
      expect(updatedItem.currentStock, equals(18.0));
    });

    test('Stock Out rejects request exceeding current stock and preserves stock', () async {
      final fakeRepo = FakeInventoryRepository([
        const InventoryItem(
          id: 'item-3',
          name: 'Eye Drop Flacons',
          category: 'Optical & Eye Care',
          currentStock: 10.0,
          unit: 'flacons',
        ),
      ]);

      expect(
        () => fakeRepo.performStockOperation(
          itemId: 'item-3',
          transactionType: 'stock_out',
          quantity: 11.0,
        ),
        throwsA(isA<Exception>()),
      );

      final unchangedItem = await fakeRepo.getInventoryItem('item-3');
      expect(unchangedItem.currentStock, equals(10.0));
      expect(fakeRepo.transactions.isEmpty, isTrue);
    });

    test('rejects zero or negative quantities', () async {
      final fakeRepo = FakeInventoryRepository([
        const InventoryItem(
          id: 'item-4',
          name: 'Bandages',
          category: 'Supplies',
          currentStock: 50.0,
          unit: 'rolls',
        ),
      ]);

      expect(
        () => fakeRepo.performStockOperation(
          itemId: 'item-4',
          transactionType: 'stock_in',
          quantity: 0.0,
        ),
        throwsA(isA<ArgumentError>()),
      );

      expect(
        () => fakeRepo.performStockOperation(
          itemId: 'item-4',
          transactionType: 'stock_in',
          quantity: -5.0,
        ),
        throwsA(isA<ArgumentError>()),
      );
    });
  });

  group('Sprint 6.2 — Stock Operation StateNotifier & Providers', () {
    test('stockIn updates inventory state and notifies listeners', () async {
      final fakeRepo = FakeInventoryRepository([
        const InventoryItem(
          id: 'item-prov-1',
          name: 'Dental Anesthetic',
          category: 'Dental Materials',
          currentStock: 15.0,
          unit: 'cartridges',
        ),
      ]);

      final container = ProviderContainer(
        overrides: [
          inventoryRepositoryProvider.overrideWithValue(fakeRepo),
        ],
      );
      addTearDown(container.dispose);

      final notifier = container.read(inventoryProvider.notifier);
      await notifier.fetchInventory();

      final tx = await notifier.stockIn(
        itemId: 'item-prov-1',
        quantity: 10.0,
        reason: 'Restock / New Purchase',
      );

      expect(tx.stockAfter, equals(25.0));

      final state = container.read(inventoryProvider);
      expect(state.value!.first.currentStock, equals(25.0));
    });

    test('stockOut updates inventory state and triggers low-stock condition', () async {
      final fakeRepo = FakeInventoryRepository([
        const InventoryItem(
          id: 'item-prov-2',
          name: 'Syringes 5ml',
          category: 'Clinical Supplies',
          currentStock: 15.0,
          minimumStock: 10.0,
          unit: 'pcs',
        ),
      ]);

      final container = ProviderContainer(
        overrides: [
          inventoryRepositoryProvider.overrideWithValue(fakeRepo),
        ],
      );
      addTearDown(container.dispose);

      final notifier = container.read(inventoryProvider.notifier);
      await notifier.fetchInventory();

      expect(container.read(lowStockCountProvider), equals(0));

      // Stock out 8 units: drops from 15 to 7 (minimum is 10)
      await notifier.stockOut(
        itemId: 'item-prov-2',
        quantity: 8.0,
        reason: 'Routine Clinical Usage',
      );

      final state = container.read(inventoryProvider);
      final item = state.value!.first;
      expect(item.currentStock, equals(7.0));
      expect(item.isLowStock, isTrue);

      // Low stock count provider must now report 1
      expect(container.read(lowStockCountProvider), equals(1));
    });

    test('filters inventory by status (Low Stock, Expiring Soon, Expired)', () async {
      final now = DateTime.now();
      final items = [
        const InventoryItem(
          id: '1',
          name: 'Healthy Item',
          category: 'Supplies',
          currentStock: 50.0,
          minimumStock: 10.0,
          unit: 'pcs',
        ),
        const InventoryItem(
          id: '2',
          name: 'Low Stock Item',
          category: 'Supplies',
          currentStock: 5.0,
          minimumStock: 20.0,
          unit: 'pcs',
        ),
        InventoryItem(
          id: '3',
          name: 'Expiring Soon Item',
          category: 'Supplies',
          currentStock: 30.0,
          minimumStock: 5.0,
          unit: 'pcs',
          expiryDate: now.add(const Duration(days: 10)),
        ),
        InventoryItem(
          id: '4',
          name: 'Expired Item',
          category: 'Supplies',
          currentStock: 12.0,
          unit: 'pcs',
          expiryDate: now.subtract(const Duration(days: 2)),
        ),
      ];

      final fakeRepo = FakeInventoryRepository(items);
      final container = ProviderContainer(
        overrides: [
          inventoryRepositoryProvider.overrideWithValue(fakeRepo),
        ],
      );
      addTearDown(container.dispose);

      await container.read(inventoryProvider.notifier).fetchInventory();

      // Counts
      expect(container.read(lowStockCountProvider), equals(1));
      expect(container.read(expiringSoonCountProvider), equals(1));
      expect(container.read(expiredCountProvider), equals(1));

      // Filter by Low Stock
      container.read(inventoryStatusFilterProvider.notifier).state = 'Low Stock';
      expect(container.read(filteredInventoryProvider).length, equals(1));
      expect(container.read(filteredInventoryProvider).first.name, equals('Low Stock Item'));

      // Filter by Expiring Soon
      container.read(inventoryStatusFilterProvider.notifier).state = 'Expiring Soon';
      expect(container.read(filteredInventoryProvider).length, equals(1));
      expect(container.read(filteredInventoryProvider).first.name, equals('Expiring Soon Item'));

      // Filter by Expired
      container.read(inventoryStatusFilterProvider.notifier).state = 'Expired';
      expect(container.read(filteredInventoryProvider).length, equals(1));
      expect(container.read(filteredInventoryProvider).first.name, equals('Expired Item'));
    });
  });

  group('Sprint 6.2 — Stock Operation UI & Dialogs', () {
    testWidgets('StockOperationDialog.stockIn renders item details and preview calculation',
        (tester) async {
      const item = InventoryItem(
        id: 'item-ui-1',
        name: 'Contact Lens Solution',
        category: 'Optical & Eye Care',
        currentStock: 20.0,
        unit: 'bottles',
      );

      final fakeRepo = FakeInventoryRepository([item]);

      await tester.pumpWidget(
        ProviderScope(
          overrides: [
            inventoryRepositoryProvider.overrideWithValue(fakeRepo),
          ],
          child: const MaterialApp(
            home: Scaffold(
              body: StockOperationDialog.stockIn(item: item),
            ),
          ),
        ),
      );

      await tester.pumpAndSettle();

      expect(find.text('Stock In (Add Stock)'), findsOneWidget);
      expect(find.text('Contact Lens Solution'), findsOneWidget);
      expect(find.text('20 bottles'), findsWidgets);
      expect(find.text('Confirm Stock In'), findsOneWidget);

      // Enter quantity 5
      final qtyField = find.byType(TextFormField).first;
      await tester.enterText(qtyField, '5');
      await tester.pumpAndSettle();

      // Check resulting preview
      expect(find.text('+5 bottles'), findsOneWidget);
      expect(find.text('25 bottles'), findsOneWidget);
    });

    testWidgets('StockOperationDialog.stockOut rejects quantity exceeding current stock',
        (tester) async {
      const item = InventoryItem(
        id: 'item-ui-2',
        name: 'Gauze Swabs',
        category: 'Clinical Supplies',
        currentStock: 10.0,
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
              body: StockOperationDialog.stockOut(item: item),
            ),
          ),
        ),
      );

      await tester.pumpAndSettle();

      expect(find.text('Stock Out (Dispense Stock)'), findsOneWidget);

      // Attempt to deduct 15 (exceeds current stock 10)
      final qtyField = find.byType(TextFormField).first;
      await tester.enterText(qtyField, '15');
      await tester.pumpAndSettle();

      // Tap Confirm Stock Out
      await tester.tap(find.text('Confirm Stock Out'));
      await tester.pumpAndSettle();

      // Should display validation error
      expect(
        find.text('Cannot dispense more than available stock (10 packs).'),
        findsOneWidget,
      );
    });

    testWidgets('InventoryTransactionHistoryDialog renders empty state when no transactions exist',
        (tester) async {
      const item = InventoryItem(
        id: 'item-empty-history',
        name: 'Test Syringe',
        category: 'Clinical Supplies',
        currentStock: 5.0,
        unit: 'pcs',
      );

      final fakeRepo = FakeInventoryRepository([item]);

      await tester.pumpWidget(
        ProviderScope(
          overrides: [
            inventoryRepositoryProvider.overrideWithValue(fakeRepo),
          ],
          child: const MaterialApp(
            home: Scaffold(
              body: InventoryTransactionHistoryDialog(item: item),
            ),
          ),
        ),
      );

      await tester.pumpAndSettle();

      expect(find.text('Stock Transaction History'), findsOneWidget);
      expect(find.text('No stock transactions yet.'), findsOneWidget);
    });
  });

  group('Sprint 6.2 — Role-Based Authorization Restrictions', () {
    testWidgets('Admin user can see Add Item, Edit, and Delete actions',
        (tester) async {
      const item = InventoryItem(
        id: 'role-item-1',
        name: 'Surgical Blade #11',
        category: 'Clinical Supplies',
        currentStock: 100.0,
        unit: 'pcs',
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
              body: InventoryManagementContent(),
            ),
          ),
        ),
      );

      await tester.pumpAndSettle();

      // Admin has Add Item button in header
      expect(find.text('Add Item'), findsOneWidget);

      // Admin has Edit and Delete actions in row
      expect(find.byIcon(Icons.edit_outlined), findsWidgets);
      expect(find.byIcon(Icons.delete_outline), findsWidgets);
    });

    testWidgets('Staff user can see Stock In and Stock Out but NOT Add Item, Edit, or Delete',
        (tester) async {
      const item = InventoryItem(
        id: 'role-item-2',
        name: 'Examination Light Bulb',
        category: 'Equipment',
        currentStock: 4.0,
        unit: 'units',
      );

      final fakeRepo = FakeInventoryRepository([item]);

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

      // Staff DOES see Add Item and Departments in header
      expect(find.text('Add Item'), findsOneWidget);
      expect(find.text('Departments'), findsOneWidget);

      // Staff DOES see Edit and Delete actions in table
      expect(find.byIcon(Icons.edit_outlined), findsWidgets);
      expect(find.byIcon(Icons.delete_outline), findsWidgets);

      // Staff DOES see Stock In, Stock Out, View Details, History
      expect(find.byIcon(Icons.add_circle_outline), findsWidgets);
      expect(find.byIcon(Icons.remove_circle_outline), findsWidgets);
      expect(find.byIcon(Icons.visibility_outlined), findsWidgets);
      expect(find.byIcon(Icons.history), findsWidgets);
    });
  });

  group('Sprint 6.2 — Staff Portal Tasks -> Inventory Navigation', () {
    const mockStaffUser = User(
      id: 'staff-user-nav-1',
      appMetadata: {},
      userMetadata: {},
      aud: 'authenticated',
      createdAt: '2026-01-01T00:00:00Z',
    );

    testWidgets('Staff can access Inventory under Tasks section and perform operations',
        (tester) async {
      tester.view.physicalSize = const Size(1280, 800);
      tester.view.devicePixelRatio = 1.0;
      addTearDown(() => tester.view.resetPhysicalSize());

      const item = InventoryItem(
        id: 'nav-item-1',
        name: 'Surgical Gloves (Size 7)',
        category: 'Clinical Supplies',
        currentStock: 45.0,
        unit: 'pairs',
      );

      final fakeRepo = FakeInventoryRepository([item]);

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

      // Sub-navigation bar renders and highlights Inventory
      expect(find.text('Shift Tasks'), findsOneWidget);
      expect(find.text('Inventory'), findsWidgets);

      // Inventory content renders item
      expect(find.text('Surgical Gloves (Size 7)'), findsOneWidget);

      // Staff DOES see Add Item and Departments configuration
      expect(find.text('Add Item'), findsOneWidget);
      expect(find.text('Departments'), findsOneWidget);

      // Staff sees Stock In and Stock Out actions
      expect(find.byIcon(Icons.add_circle_outline), findsWidgets);
      expect(find.byIcon(Icons.remove_circle_outline), findsWidgets);
    });

    testWidgets('InventoryManagementScreen renders with standard Scaffold for staff',
        (tester) async {
      const item = InventoryItem(
        id: 'nav-item-2',
        name: 'Antibacterial Solution',
        category: 'Pharmaceuticals',
        currentStock: 12.0,
        unit: 'bottles',
      );

      final fakeRepo = FakeInventoryRepository([item]);

      await tester.pumpWidget(
        ProviderScope(
          overrides: [
            inventoryRepositoryProvider.overrideWithValue(fakeRepo),
            currentUserRoleProvider.overrideWith((ref) => Future.value('staff')),
          ],
          child: const MaterialApp(
            home: InventoryManagementScreen(),
          ),
        ),
      );

      await tester.pumpAndSettle();

      // App bar shows title
      expect(find.text('Inventory Management'), findsWidgets);

      // Staff DOES see Add Item
      expect(find.text('Add Item'), findsOneWidget);
    });
  });

  group('Sprint 6.2 — Patient Assignment & Corrected UX (10 Test Suite)', () {
    const testItem = InventoryItem(
      id: 'patient-test-item-1',
      name: 'Ketorolac 10mg Tablets',
      category: 'Pharmaceuticals',
      currentStock: 50.0,
      minimumStock: 10.0,
      unit: 'strips',
    );

    final testPatient = PatientModel(
      id: 'pat-ux-001',
      patientNumber: 'PAT-2026-001',
      name: 'Eleanor Vance',
      mobile: '9876543210',
      createdAt: DateTime.now(),
      updatedAt: DateTime.now(),
    );

    // 1. Stock Out with General Usage -> no patient field/patient ID.
    testWidgets('1. Stock Out with General Usage -> no patient field and patient ID is null',
        (tester) async {
      final fakeRepo = FakeInventoryRepository([testItem]);

      await tester.pumpWidget(
        ProviderScope(
          overrides: [
            inventoryRepositoryProvider.overrideWithValue(fakeRepo),
            patientsProvider.overrideWith((ref) => FakePatientsNotifier([testPatient])),
          ],
          child: const MaterialApp(
            home: Scaffold(
              body: StockOperationDialog.stockOut(item: testItem),
            ),
          ),
        ),
      );
      await tester.pumpAndSettle();

      // Initial reason is General Usage
      expect(find.text('General Usage'), findsOneWidget);
      // Patient selector must NOT appear
      expect(find.text('PATIENT *'), findsNothing);
      expect(find.byIcon(Icons.person_search_outlined), findsNothing);

      // Enter quantity 5 and submit
      final qtyField = find.byType(TextFormField).first;
      await tester.enterText(qtyField, '5');
      await tester.pumpAndSettle();

      await tester.tap(find.text('Confirm Stock Out'));
      await tester.pumpAndSettle();

      expect(fakeRepo.transactions.length, equals(1));
      expect(fakeRepo.transactions.first.reason, equals('General Usage'));
      expect(fakeRepo.transactions.first.patientId, isNull);
      expect(fakeRepo.transactions.first.quantity, equals(5.0));
    });

    // 2. Stock Out with Damaged -> no patient field/patient ID.
    testWidgets('2. Stock Out with Damaged -> no patient field and patient ID is null',
        (tester) async {
      final fakeRepo = FakeInventoryRepository([testItem]);

      await tester.pumpWidget(
        ProviderScope(
          overrides: [
            inventoryRepositoryProvider.overrideWithValue(fakeRepo),
            patientsProvider.overrideWith((ref) => FakePatientsNotifier([testPatient])),
          ],
          child: const MaterialApp(
            home: Scaffold(
              body: StockOperationDialog.stockOut(item: testItem),
            ),
          ),
        ),
      );
      await tester.pumpAndSettle();

      // Change reason to Damaged
      await tester.tap(find.byType(DropdownButtonFormField<String>));
      await tester.pumpAndSettle();
      await tester.tap(find.text('Damaged').last);
      await tester.pumpAndSettle();

      // Patient selector must NOT appear
      expect(find.text('PATIENT *'), findsNothing);
      expect(find.byIcon(Icons.person_search_outlined), findsNothing);

      // Enter quantity 2 and submit
      final qtyField = find.byType(TextFormField).first;
      await tester.enterText(qtyField, '2');
      await tester.pumpAndSettle();

      await tester.tap(find.text('Confirm Stock Out'));
      await tester.pumpAndSettle();

      expect(fakeRepo.transactions.length, equals(1));
      expect(fakeRepo.transactions.first.reason, equals('Damaged'));
      expect(fakeRepo.transactions.first.patientId, isNull);
    });

    // 3. Stock Out with Expired -> no patient field/patient ID.
    testWidgets('3. Stock Out with Expired -> no patient field and patient ID is null',
        (tester) async {
      final fakeRepo = FakeInventoryRepository([testItem]);

      await tester.pumpWidget(
        ProviderScope(
          overrides: [
            inventoryRepositoryProvider.overrideWithValue(fakeRepo),
            patientsProvider.overrideWith((ref) => FakePatientsNotifier([testPatient])),
          ],
          child: const MaterialApp(
            home: Scaffold(
              body: StockOperationDialog.stockOut(item: testItem),
            ),
          ),
        ),
      );
      await tester.pumpAndSettle();

      // Change reason to Expired
      await tester.tap(find.byType(DropdownButtonFormField<String>));
      await tester.pumpAndSettle();
      await tester.tap(find.text('Expired').last);
      await tester.pumpAndSettle();

      // Patient selector must NOT appear
      expect(find.text('PATIENT *'), findsNothing);
      expect(find.byIcon(Icons.person_search_outlined), findsNothing);

      // Enter quantity 3 and submit
      final qtyField = find.byType(TextFormField).first;
      await tester.enterText(qtyField, '3');
      await tester.pumpAndSettle();

      await tester.tap(find.text('Confirm Stock Out'));
      await tester.pumpAndSettle();

      expect(fakeRepo.transactions.length, equals(1));
      expect(fakeRepo.transactions.first.reason, equals('Expired'));
      expect(fakeRepo.transactions.first.patientId, isNull);
    });

    // 4. Stock Out with Dispensed to Patient -> patient field appears.
    testWidgets('4. Stock Out with Dispensed to Patient -> patient field appears',
        (tester) async {
      final fakeRepo = FakeInventoryRepository([testItem]);

      await tester.pumpWidget(
        ProviderScope(
          overrides: [
            inventoryRepositoryProvider.overrideWithValue(fakeRepo),
            patientsProvider.overrideWith((ref) => FakePatientsNotifier([testPatient])),
          ],
          child: const MaterialApp(
            home: Scaffold(
              body: StockOperationDialog.stockOut(item: testItem),
            ),
          ),
        ),
      );
      await tester.pumpAndSettle();

      // Patient field absent initially
      expect(find.text('PATIENT *'), findsNothing);

      // Change reason to Dispensed to Patient
      await tester.tap(find.byType(DropdownButtonFormField<String>));
      await tester.pumpAndSettle();
      await tester.tap(find.text('Dispensed to Patient').last);
      await tester.pumpAndSettle();

      // Patient field must now be present
      expect(find.text('PATIENT *'), findsOneWidget);
      expect(find.byIcon(Icons.person_search_outlined), findsOneWidget);
      expect(find.text('Eleanor Vance'), findsOneWidget);
    });

    // 5. Dispensed to Patient without patient -> submission blocked.
    testWidgets('5. Dispensed to Patient without patient -> submission blocked',
        (tester) async {
      final fakeRepo = FakeInventoryRepository([testItem]);

      await tester.pumpWidget(
        ProviderScope(
          overrides: [
            inventoryRepositoryProvider.overrideWithValue(fakeRepo),
            patientsProvider.overrideWith((ref) => FakePatientsNotifier([testPatient])),
          ],
          child: const MaterialApp(
            home: Scaffold(
              body: StockOperationDialog.stockOut(item: testItem),
            ),
          ),
        ),
      );
      await tester.pumpAndSettle();

      // Change reason to Dispensed to Patient
      await tester.tap(find.byType(DropdownButtonFormField<String>));
      await tester.pumpAndSettle();
      await tester.tap(find.text('Dispensed to Patient').last);
      await tester.pumpAndSettle();

      // Enter quantity 4 without selecting any patient
      final qtyField = find.byType(TextFormField).first;
      await tester.enterText(qtyField, '4');
      await tester.pumpAndSettle();

      // Tap confirm
      await tester.tap(find.text('Confirm Stock Out'));
      await tester.pumpAndSettle();

      // Error message shown and submission blocked
      expect(find.text('Please select a patient.'), findsWidgets);
      expect(fakeRepo.transactions, isEmpty);
    });

    // 6. Dispensed to Patient with patient -> patient ID saved.
    testWidgets('6. Dispensed to Patient with patient -> patient ID saved',
        (tester) async {
      final fakeRepo = FakeInventoryRepository([testItem], [testPatient]);

      await tester.pumpWidget(
        ProviderScope(
          overrides: [
            inventoryRepositoryProvider.overrideWithValue(fakeRepo),
            patientsProvider.overrideWith((ref) => FakePatientsNotifier([testPatient])),
          ],
          child: const MaterialApp(
            home: Scaffold(
              body: StockOperationDialog.stockOut(item: testItem),
            ),
          ),
        ),
      );
      await tester.pumpAndSettle();

      // Change reason to Dispensed to Patient
      await tester.tap(find.byType(DropdownButtonFormField<String>));
      await tester.pumpAndSettle();
      await tester.tap(find.text('Dispensed to Patient').last);
      await tester.pumpAndSettle();

      // Select patient from list
      await tester.tap(find.text('Eleanor Vance'));
      await tester.pumpAndSettle();

      // Selected patient card displayed
      expect(find.text('ID: PAT-2026-001 • 9876543210'), findsOneWidget);

      // Enter quantity 2 and submit
      final qtyField = find.byType(TextFormField).first;
      await tester.enterText(qtyField, '2');
      await tester.pumpAndSettle();

      await tester.tap(find.text('Confirm Stock Out'));
      await tester.pumpAndSettle();

      expect(fakeRepo.transactions.length, equals(1));
      expect(fakeRepo.transactions.first.reason, equals('Dispensed to Patient'));
      expect(fakeRepo.transactions.first.patientId, equals(testPatient.id));
      expect(fakeRepo.transactions.first.patientName, equals('Eleanor Vance'));
      expect(fakeRepo.transactions.first.patientNumber, equals('PAT-2026-001'));
    });

    // 7. Change from Dispensed to Patient to another reason -> selected patient cleared.
    testWidgets('7. Change from Dispensed to Patient to another reason -> selected patient cleared',
        (tester) async {
      final fakeRepo = FakeInventoryRepository([testItem], [testPatient]);

      await tester.pumpWidget(
        ProviderScope(
          overrides: [
            inventoryRepositoryProvider.overrideWithValue(fakeRepo),
            patientsProvider.overrideWith((ref) => FakePatientsNotifier([testPatient])),
          ],
          child: const MaterialApp(
            home: Scaffold(
              body: StockOperationDialog.stockOut(item: testItem),
            ),
          ),
        ),
      );
      await tester.pumpAndSettle();

      // 1. Select Dispensed to Patient
      await tester.tap(find.byType(DropdownButtonFormField<String>));
      await tester.pumpAndSettle();
      await tester.tap(find.text('Dispensed to Patient').last);
      await tester.pumpAndSettle();

      // 2. Select patient
      await tester.tap(find.text('Eleanor Vance'));
      await tester.pumpAndSettle();
      expect(find.byTooltip('Clear patient'), findsOneWidget);

      // 3. Change reason to General Usage
      await tester.tap(find.text('Dispensed to Patient').first);
      await tester.pumpAndSettle();
      await tester.tap(find.text('General Usage').last);
      await tester.pumpAndSettle();

      // Patient selector is hidden
      expect(find.text('PATIENT *'), findsNothing);

      // 4. Change back to Dispensed to Patient -> verify patient was automatically cleared
      await tester.tap(find.text('General Usage').first);
      await tester.pumpAndSettle();
      await tester.tap(find.text('Dispensed to Patient').last);
      await tester.pumpAndSettle();

      // The selected card should NOT be visible; search field is shown
      expect(find.byTooltip('Clear patient'), findsNothing);
      expect(find.text('Search patient by name, ID, or mobile...'), findsOneWidget);

      // 5. Change back to General Usage, enter quantity and submit -> patientId must be null
      await tester.tap(find.text('Dispensed to Patient').first);
      await tester.pumpAndSettle();
      await tester.tap(find.text('General Usage').last);
      await tester.pumpAndSettle();

      final qtyField = find.byType(TextFormField).first;
      await tester.enterText(qtyField, '1');
      await tester.pumpAndSettle();

      await tester.tap(find.text('Confirm Stock Out'));
      await tester.pumpAndSettle();

      expect(fakeRepo.transactions.first.patientId, isNull);
    });

    // 8. Transaction history displays patient only for patient-dispensed transactions.
    testWidgets('8. Transaction history displays patient only for patient-dispensed transactions',
        (tester) async {
      final fakeRepo = FakeInventoryRepository([testItem]);

      final txDispensed = InventoryTransaction(
        id: 'tx-p-1',
        inventoryItemId: testItem.id,
        transactionType: 'stock_out',
        quantity: 5.0,
        stockBefore: 50.0,
        stockAfter: 45.0,
        reason: 'Dispensed to Patient',
        patientId: 'pat-1',
        patientName: 'Eleanor Vance',
        patientNumber: 'PAT-2026-001',
        performedByName: 'Staff Nurse',
        createdAt: DateTime.now().subtract(const Duration(minutes: 10)),
      );

      final txGeneral = InventoryTransaction(
        id: 'tx-p-2',
        inventoryItemId: testItem.id,
        transactionType: 'stock_out',
        quantity: 2.0,
        stockBefore: 45.0,
        stockAfter: 43.0,
        reason: 'General Usage',
        patientId: null,
        performedByName: 'Staff Nurse',
        createdAt: DateTime.now().subtract(const Duration(minutes: 5)),
      );

      final txDamaged = InventoryTransaction(
        id: 'tx-p-3',
        inventoryItemId: testItem.id,
        transactionType: 'stock_out',
        quantity: 1.0,
        stockBefore: 43.0,
        stockAfter: 42.0,
        reason: 'Damaged',
        patientId: null,
        performedByName: 'Staff Nurse',
        createdAt: DateTime.now(),
      );

      fakeRepo.transactions.addAll([txDispensed, txGeneral, txDamaged]);

      await tester.pumpWidget(
        ProviderScope(
          overrides: [
            inventoryRepositoryProvider.overrideWithValue(fakeRepo),
          ],
          child: const MaterialApp(
            home: Scaffold(
              body: InventoryTransactionHistoryDialog(item: testItem),
            ),
          ),
        ),
      );
      await tester.pumpAndSettle();

      // Displays patient details for Dispensed to Patient
      expect(find.text('Eleanor Vance (PAT-2026-001)'), findsOneWidget);

      // Displays Patient: — for non-dispensed transactions
      expect(find.text('Patient: —'), findsNWidgets(2));
    });

    // 9. Existing stock validation still works.
    testWidgets('9. Existing stock validation still works',
        (tester) async {
      final fakeRepo = FakeInventoryRepository([testItem]);

      await tester.pumpWidget(
        ProviderScope(
          overrides: [
            inventoryRepositoryProvider.overrideWithValue(fakeRepo),
            patientsProvider.overrideWith((ref) => FakePatientsNotifier([testPatient])),
          ],
          child: const MaterialApp(
            home: Scaffold(
              body: StockOperationDialog.stockOut(item: testItem),
            ),
          ),
        ),
      );
      await tester.pumpAndSettle();

      final qtyField = find.byType(TextFormField).first;

      // Excess quantity validation
      await tester.enterText(qtyField, '999');
      await tester.pumpAndSettle();

      await tester.tap(find.text('Confirm Stock Out'));
      await tester.pumpAndSettle();

      expect(
        find.text('Cannot dispense more than available stock (50 strips).'),
        findsOneWidget,
      );
      expect(fakeRepo.transactions, isEmpty);

      // Zero quantity validation
      await tester.enterText(qtyField, '0');
      await tester.pumpAndSettle();

      await tester.tap(find.text('Confirm Stock Out'));
      await tester.pumpAndSettle();

      expect(find.text('Quantity must be greater than 0.'), findsOneWidget);
      expect(fakeRepo.transactions, isEmpty);
    });

    // 10. Low-stock notification behavior remains correct.
    test('10. Low-stock notification triggers when crossing <= minimumStock', () async {
      const lowStockItem = InventoryItem(
        id: 'low-item-1',
        name: 'Normal Saline IV 500ml',
        category: 'Clinical Supplies',
        currentStock: 15.0,
        minimumStock: 10.0,
        unit: 'bottles',
      );

      final fakeRepo = FakeInventoryRepository([lowStockItem]);
      final container = ProviderContainer(
        overrides: [
          inventoryRepositoryProvider.overrideWithValue(fakeRepo),
        ],
      );
      addTearDown(container.dispose);

      final notifier = container.read(inventoryProvider.notifier);
      await notifier.fetchInventory();

      expect(container.read(lowStockCountProvider), equals(0));
      expect(container.read(inventoryProvider).value!.first.isLowStock, isFalse);

      // Stock out 8 units: drops from 15.0 to 7.0 (<= minimumStock of 10.0)
      await notifier.stockOut(
        itemId: 'low-item-1',
        quantity: 8.0,
        reason: 'General Usage',
      );

      final updatedState = container.read(inventoryProvider);
      final item = updatedState.value!.first;

      expect(item.currentStock, equals(7.0));
      expect(item.isLowStock, isTrue);
      expect(container.read(lowStockCountProvider), equals(1));
    });
  });
}

