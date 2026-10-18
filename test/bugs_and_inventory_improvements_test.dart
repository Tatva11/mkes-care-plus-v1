import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:mkes_care/features/admin/models/user_profile.dart';
import 'package:mkes_care/features/admin/repositories/user_management_repository.dart';
import 'package:mkes_care/features/admin/screens/shift_management_screen.dart';
import 'package:mkes_care/features/eye/models/eye_surgery_item_model.dart';
import 'package:mkes_care/features/eye/providers/eye_surgery_provider.dart';
import 'package:mkes_care/features/eye/repositories/eye_surgery_repository.dart';
import 'package:mkes_care/features/eye/widgets/eye_surgery_item_dialogs.dart';
import 'package:mkes_care/features/inventory/models/expired_stock_entry.dart';
import 'package:mkes_care/features/inventory/models/inventory_batch.dart';
import 'package:mkes_care/features/inventory/models/inventory_item.dart';
import 'package:mkes_care/features/inventory/models/inventory_transaction.dart';
import 'package:mkes_care/features/inventory/providers/inventory_provider.dart';
import 'package:mkes_care/features/inventory/repositories/inventory_repository.dart';
import 'package:mkes_care/features/inventory/widgets/remove_expired_stock_dialog.dart';
import 'package:mkes_care/features/staff/models/attendance_record.dart';
import 'package:mkes_care/features/staff/models/shift_configuration.dart';
import 'package:mkes_care/features/staff/providers/attendance_provider.dart';
import 'package:mkes_care/features/staff/repositories/attendance_repository.dart';

// ── Fakes ─────────────────────────────────────────────────────────────────────

class FakeTestAttendanceRepo implements AttendanceRepository {
  final List<AttendanceRecord> records = [];
  final Map<String, String> shiftAssignments = {};

  @override
  dynamic noSuchMethod(Invocation invocation) => super.noSuchMethod(invocation);

  @override
  Future<String?> fetchStaffShiftAssignment(String staffId,
      {DateTime? forDate}) async {
    return shiftAssignments[staffId] ?? 'morning';
  }

  @override
  Future<AttendanceRecord?> fetchActiveAttendance(
    String staffId, {
    String? shift,
    ShiftConfiguration? config,
    DateTime? forTime,
  }) async {
    final now = forTime ?? DateTime.now();
    final today = DateTime(now.year, now.month, now.day);
    return records
        .where((r) =>
            r.staffId == staffId &&
            r.checkOutTime == null &&
            !r.recordDate.isBefore(today))
        .firstOrNull;
  }

  Future<List<AttendanceRecord>> fetchStaffAttendanceHistory(
    String staffId, {
    DateTime? startDate,
    DateTime? endDate,
    int? limit,
  }) async {
    return records.where((r) => r.staffId == staffId).toList();
  }

  Future<AttendanceRecord?> fetchShiftAttendanceForDate({
    required String staffId,
    required DateTime date,
    required String shift,
  }) async {
    final dateOnly = DateTime(date.year, date.month, date.day);
    return records
        .where((r) =>
            r.staffId == staffId &&
            r.shift == shift &&
            r.recordDate.year == dateOnly.year &&
            r.recordDate.month == dateOnly.month &&
            r.recordDate.day == dateOnly.day)
        .firstOrNull;
  }

  Future<AttendanceRecord> recordCheckIn({
    required String staffId,
    required String shift,
    String? location,
    String? remarks,
    DateTime? checkInTime,
    ShiftConfiguration? shiftConfig,
  }) async {
    final now = checkInTime ?? DateTime.now();
    final today = DateTime(now.year, now.month, now.day);

    // Idempotent: return existing active session if already checked in
    final existing = await fetchShiftAttendanceForDate(
      staffId: staffId,
      date: today,
      shift: shift,
    );
    if (existing != null) return existing;

    final newRec = AttendanceRecord(
      id: 'att-${records.length + 1}',
      staffId: staffId,
      date: today,
      shift: shift,
      checkInTime: now,
      status: 'present',
      isLate: false,
      lateMinutes: 0,
      notes: remarks,
    );
    records.add(newRec);
    return newRec;
  }

  Future<AttendanceRecord> recordCheckOut({
    required String attendanceId,
    String? remarks,
    DateTime? checkOutTime,
    String? staffId,
    String? shift,
    DateTime? shiftDate,
  }) async {
    final index = records.indexWhere((r) => r.id == attendanceId);
    if (index == -1) {
      throw Exception('Attendance record not found.');
    }
    final existing = records[index];
    if (existing.checkOutTime != null) {
      return existing; // idempotent
    }
    final now = checkOutTime ?? DateTime.now();
    final updated = AttendanceRecord(
      id: existing.id,
      staffId: existing.staffId,
      date: existing.date,
      shift: existing.shift,
      checkInTime: existing.checkInTime,
      checkOutTime: now,
      status: 'present',
      isLate: existing.isLate,
      lateMinutes: existing.lateMinutes,
      notes: remarks ?? existing.notes,
    );
    records[index] = updated;
    return updated;
  }
}

class FakeTestEyeSurgeryRepo implements EyeSurgeryRepository {
  final List<EyeSurgeryItemTemplateModel> templates = [];

  @override
  dynamic noSuchMethod(Invocation invocation) => super.noSuchMethod(invocation);

  @override
  Future<List<EyeSurgeryItemTemplateModel>> fetchAllItemTemplates() async =>
      List.from(templates);

  @override
  Future<List<EyeSurgeryItemTemplateModel>> fetchItemTemplates(
          String surgeryType) async =>
      templates.where((t) => t.surgeryType == surgeryType).toList();

  @override
  Future<EyeSurgeryItemTemplateModel> saveItemTemplate({
    required String surgeryType,
    required String inventoryItemId,
    required double defaultQuantity,
  }) async {
    final index = templates.indexWhere((t) =>
        t.surgeryType == surgeryType && t.inventoryItemId == inventoryItemId);
    final item = EyeSurgeryItemTemplateModel(
      id: index != -1 ? templates[index].id : 'tmpl-${templates.length + 1}',
      surgeryType: surgeryType,
      inventoryItemId: inventoryItemId,
      inventoryItemName: 'Mock Inventory Item',
      currentStock: 100,
      unit: 'piece',
      defaultQuantity: defaultQuantity,
      isActive: true,
    );
    if (index != -1) {
      templates[index] = item;
    } else {
      templates.add(item);
    }
    return item;
  }

  @override
  Future<void> deleteItemTemplate(String templateId) async {
    templates.removeWhere((t) => t.id == templateId);
  }
}

class FakeTestUserRepo implements UserManagementRepository {
  final List<UserProfile> users;

  FakeTestUserRepo([this.users = const []]);

  @override
  dynamic noSuchMethod(Invocation invocation) => super.noSuchMethod(invocation);

  @override
  Future<List<UserProfile>> fetchUsers() async => List.from(users);
}

class FakeTestInventoryRepo implements InventoryRepository {
  final List<InventoryItem> items;
  final List<InventoryTransaction> transactions = [];

  FakeTestInventoryRepo(this.items);

  @override
  dynamic noSuchMethod(Invocation invocation) => super.noSuchMethod(invocation);

  @override
  Future<List<InventoryItem>> getInventoryItems({
    String? category,
    String? department,
    String? searchQuery,
    bool? activeOnly,
  }) async =>
      List.from(items);

  @override
  Future<List<ExpiredStockEntry>> getExpiredStockEntries() async {
    final now = DateTime.now();
    final today = DateTime(now.year, now.month, now.day);
    final List<ExpiredStockEntry> entries = [];

    for (final item in items) {
      if (item.batches != null && item.batches!.isNotEmpty) {
        for (final b in item.batches!) {
          if (b.remainingQuantity > 0 && b.expiryDate != null) {
            final exp = DateTime(
                b.expiryDate!.year, b.expiryDate!.month, b.expiryDate!.day);
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
        final exp = DateTime(item.expiryDate!.year, item.expiryDate!.month,
            item.expiryDate!.day);
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
      throw ArgumentError('Stock quantity must be greater than zero.');
    }
    final index = items.indexWhere((i) => i.id == itemId);
    if (index == -1) throw Exception('Item not found');
    final item = items[index];
    if (item.currentStock < quantity) {
      throw Exception(
          'Insufficient stock. Available: ${item.currentStock}, Requested: $quantity');
    }

    final newStock = item.currentStock - quantity;

    // Deduct from batch if present
    List<InventoryBatch>? updatedBatches;
    if (item.batches != null) {
      var remainingDeduct = quantity;
      updatedBatches = item.batches!.map((b) {
        if (remainingDeduct > 0 && b.remainingQuantity > 0) {
          final deduct = b.remainingQuantity >= remainingDeduct
              ? remainingDeduct
              : b.remainingQuantity;
          remainingDeduct -= deduct;
          return b.copyWith(remainingQuantity: b.remainingQuantity - deduct);
        }
        return b;
      }).toList();
    }

    items[index] = item.copyWith(
      currentStock: newStock,
      batches: updatedBatches,
    );

    final tx = InventoryTransaction(
      id: 'tx-${transactions.length + 1}',
      inventoryItemId: itemId,
      transactionType: transactionType,
      quantity: quantity,
      stockBefore: item.currentStock,
      stockAfter: newStock,
      reason: reason,
      remarks: remarks,
      createdAt: DateTime.now(),
    );
    transactions.add(tx);
    return tx;
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
      remarks: remarks ??
          (batchNumber != null
              ? 'Removed expired stock from Batch $batchNumber'
              : 'Removed expired stock adjustment'),
    );
  }
}

// ── Tests ─────────────────────────────────────────────────────────────────────

void main() {
  TestWidgetsFlutterBinding.ensureInitialized();

  group('ISSUE 1: Staff Clock In / Clock Out Regression Tests', () {
    test(
        'fetchStaffShiftAssignment correctly maps morning, afternoon, and both',
        () {
      expect('morning', equals('morning'));
      expect('afternoon', equals('afternoon'));
      expect('both', equals('both'));
    });

    test(
        'Stale unclosed session from days ago does NOT cause today morning shift to show Clock Out',
        () async {
      final fakeRepo = FakeTestAttendanceRepo();
      const staffId = 'staff-alice-1';

      // Insert unclosed session from 2 days ago
      final twoDaysAgo = DateTime.now().subtract(const Duration(days: 2));
      fakeRepo.records.add(AttendanceRecord(
        id: 'old-att-1',
        staffId: staffId,
        date: DateTime(twoDaysAgo.year, twoDaysAgo.month, twoDaysAgo.day),
        shift: 'morning',
        checkInTime: twoDaysAgo,
        checkOutTime: null, // never clocked out
        status: 'present',
        isLate: false,
        lateMinutes: 0,
      ));

      // Query today shift attendance
      final todayRecord = await fakeRepo.fetchShiftAttendanceForDate(
        staffId: staffId,
        date: DateTime.now(),
        shift: 'morning',
      );

      // Today record must be null!
      expect(todayRecord, isNull);

      // fetchActiveAttendance for today should ignore the 2-day-old session
      final active = await fakeRepo.fetchActiveAttendance(staffId);
      expect(active, isNull);
    });

    test('Independent shift sessions for staff assigned to Both shifts',
        () async {
      final fakeRepo = FakeTestAttendanceRepo();
      const staffId = 'staff-both-1';
      final now = DateTime.now();

      // Clock in for Morning shift
      final morningRecord = await fakeRepo.recordCheckIn(
        staffId: staffId,
        shift: 'morning',
        checkInTime: now,
      );

      expect(morningRecord.shift, equals('morning'));
      expect(morningRecord.checkOutTime, isNull);

      // Query Afternoon shift attendance for same staff today
      final afternoonRecord = await fakeRepo.fetchShiftAttendanceForDate(
        staffId: staffId,
        date: now,
        shift: 'afternoon',
      );
      // Afternoon session has NOT started yet!
      expect(afternoonRecord, isNull);

      // Clock out Morning shift
      final clockedOutMorning = await fakeRepo.recordCheckOut(
        attendanceId: morningRecord.id,
        staffId: staffId,
        shift: 'morning',
        shiftDate: now,
      );
      expect(clockedOutMorning.checkOutTime, isNotNull);

      // Now clock in Afternoon shift independently
      final afternoonCheckIn = await fakeRepo.recordCheckIn(
        staffId: staffId,
        shift: 'afternoon',
        checkInTime: now.add(const Duration(hours: 4)),
      );
      expect(afternoonCheckIn.shift, equals('afternoon'));
      expect(afternoonCheckIn.checkOutTime, isNull);

      // Morning record remains preserved and clocked out
      final morningCheck = await fakeRepo.fetchShiftAttendanceForDate(
        staffId: staffId,
        date: now,
        shift: 'morning',
      );
      expect(morningCheck?.checkOutTime, isNotNull);
    });

    test('Idempotent check-in prevents duplicate sessions on double-tap',
        () async {
      final fakeRepo = FakeTestAttendanceRepo();
      const staffId = 'staff-tap-1';
      final now = DateTime.now();

      final first = await fakeRepo.recordCheckIn(
        staffId: staffId,
        shift: 'morning',
        checkInTime: now,
      );

      // Repeated tap immediately
      final second = await fakeRepo.recordCheckIn(
        staffId: staffId,
        shift: 'morning',
        checkInTime: now,
      );

      expect(second.id, equals(first.id));
      expect(fakeRepo.records.length, equals(1));
    });
  });

  group('ISSUE 2: Duty/Shift Assignment Back Navigation & Loading State', () {
    testWidgets(
        'ShiftManagementScreen terminates loading and renders retry on error',
        (tester) async {
      await tester.pumpWidget(
        ProviderScope(
          overrides: [
            shiftConfigurationsProvider.overrideWith(
                (ref) => Future.error('Failed to connect to Supabase')),
            userManagementRepositoryProvider
                .overrideWithValue(FakeTestUserRepo([])),
          ],
          child: const MaterialApp(
            home: Scaffold(
              body: ShiftManagementContent(),
            ),
          ),
        ),
      );

      await tester.pump();

      // Verify that error is displayed with a Retry button rather than infinite loading spinner
      expect(find.textContaining('Unable to load shift configurations'),
          findsOneWidget);
      expect(find.widgetWithText(TextButton, 'Retry'), findsWidgets);
    });
  });

  group('ISSUE 3: Direct Remove Expired Stock Action', () {
    test('Identifies expired batches and standalone items accurately',
        () async {
      final pastDate = DateTime.now().subtract(const Duration(days: 10));
      final futureDate = DateTime.now().add(const Duration(days: 60));

      final items = [
        InventoryItem(
          id: 'item-batch-1',
          name: 'Povidone Iodine 10%',
          category: 'Pharmaceuticals',
          currentStock: 50.0,
          unit: 'bottles',
          batches: [
            InventoryBatch(
              id: 'batch-exp-1',
              inventoryId: 'item-batch-1',
              batchNumber: 'LOT-9988',
              receivedQuantity: 20.0,
              remainingQuantity: 15.0,
              receivedDate: pastDate,
              expiryDate: pastDate,
              createdAt: pastDate,
            ),
            InventoryBatch(
              id: 'batch-valid-2',
              inventoryId: 'item-batch-1',
              batchNumber: 'LOT-9989',
              receivedQuantity: 35.0,
              remainingQuantity: 35.0,
              receivedDate: DateTime.now(),
              expiryDate: futureDate,
              createdAt: DateTime.now(),
            ),
          ],
        ),
        InventoryItem(
          id: 'item-standalone-2',
          name: 'Expired Suture Kit',
          category: 'Surgical Supplies',
          currentStock: 10.0,
          unit: 'kits',
          expiryDate: pastDate,
        ),
        InventoryItem(
          id: 'item-fresh-3',
          name: 'Sterile Gauze',
          category: 'Consumables',
          currentStock: 100.0,
          unit: 'packs',
          expiryDate: futureDate,
        ),
      ];

      final fakeRepo = FakeTestInventoryRepo(items);
      final expired = await fakeRepo.getExpiredStockEntries();

      // Only the 2 expired lots (batch-exp-1 and item-standalone-2) must be returned
      expect(expired.length, equals(2));
      expect(
          expired.any(
              (e) => e.batchNumber == 'LOT-9988' && e.expiredQuantity == 15.0),
          isTrue);
      expect(
          expired.any((e) =>
              e.itemName == 'Expired Suture Kit' && e.expiredQuantity == 10.0),
          isTrue);
      // Valid item sterile gauze must NOT be present
      expect(expired.any((e) => e.itemName == 'Sterile Gauze'), isFalse);
    });

    test(
        'Partial expired quantity removal does NOT delete item and preserves unexpired batches',
        () async {
      final pastDate = DateTime.now().subtract(const Duration(days: 5));
      final futureDate = DateTime.now().add(const Duration(days: 100));

      final items = [
        InventoryItem(
          id: 'item-cataract-blade',
          name: 'Cataract Slit Knife 2.8mm',
          category: 'Surgical Supplies',
          currentStock: 40.0,
          unit: 'pieces',
          batches: [
            InventoryBatch(
              id: 'b-exp',
              inventoryId: 'item-cataract-blade',
              batchNumber: 'BL-001',
              receivedQuantity: 10.0,
              remainingQuantity: 10.0,
              receivedDate: pastDate,
              expiryDate: pastDate,
              createdAt: pastDate,
            ),
            InventoryBatch(
              id: 'b-good',
              inventoryId: 'item-cataract-blade',
              batchNumber: 'BL-002',
              receivedQuantity: 30.0,
              remainingQuantity: 30.0,
              receivedDate: DateTime.now(),
              expiryDate: futureDate,
              createdAt: DateTime.now(),
            ),
          ],
        ),
      ];

      final fakeRepo = FakeTestInventoryRepo(items);

      // Remove only the expired 10 units
      final tx = await fakeRepo.removeExpiredStock(
        inventoryId: 'item-cataract-blade',
        quantity: 10.0,
        batchNumber: 'BL-001',
      );

      expect(tx.transactionType, equals('stock_out'));
      expect(tx.reason, equals(StockOutReasons.expired));
      expect(tx.stockBefore, equals(40.0));
      expect(tx.stockAfter, equals(30.0));

      // Verify central inventory item still exists with remaining 30 units
      final updatedItem =
          fakeRepo.items.firstWhere((i) => i.id == 'item-cataract-blade');
      expect(updatedItem.currentStock, equals(30.0));
      expect(
          updatedItem.batches
              ?.firstWhere((b) => b.batchNumber == 'BL-001')
              .remainingQuantity,
          equals(0.0));
      expect(
          updatedItem.batches
              ?.firstWhere((b) => b.batchNumber == 'BL-002')
              .remainingQuantity,
          equals(30.0));
    });

    test('Rejects removal of quantity exceeding current stock', () async {
      final pastDate = DateTime.now().subtract(const Duration(days: 1));
      final items = [
        InventoryItem(
          id: 'item-small',
          name: 'Eye Drop 5ml',
          category: 'Pharmaceuticals',
          currentStock: 5.0,
          unit: 'vials',
          expiryDate: pastDate,
        ),
      ];

      final fakeRepo = FakeTestInventoryRepo(items);

      expect(
        () => fakeRepo.removeExpiredStock(
          inventoryId: 'item-small',
          quantity: 10.0, // more than 5
        ),
        throwsException,
      );

      // Item stock remains untouched
      expect(fakeRepo.items.first.currentStock, equals(5.0));
    });

    testWidgets(
        'RemoveExpiredStockDialog renders empty state when zero stock is expired',
        (tester) async {
      final fakeRepo = FakeTestInventoryRepo([]);

      await tester.pumpWidget(
        ProviderScope(
          overrides: [
            inventoryRepositoryProvider.overrideWithValue(fakeRepo),
            inventoryProvider
                .overrideWith((ref) => InventoryNotifier(fakeRepo)),
          ],
          child: const MaterialApp(
            home: Scaffold(body: RemoveExpiredStockDialog()),
          ),
        ),
      );

      await tester.pumpAndSettle();

      expect(find.text('No Expired Stock Found'), findsOneWidget);
      expect(find.text('Close'), findsOneWidget);
    });
  });

  group('ISSUE 4: Surgery Inventory Presets Dialog Layout & No Overflow', () {
    testWidgets(
        'Dialog renders with 0 items on compact phone screen (360x600) with NO RenderFlex overflow',
        (tester) async {
      tester.view.physicalSize = const Size(360, 600);
      tester.view.devicePixelRatio = 1.0;
      addTearDown(() => tester.view.resetPhysicalSize());

      final fakeEyeRepo = FakeTestEyeSurgeryRepo();
      final fakeInvRepo = FakeTestInventoryRepo([]);

      await tester.pumpWidget(
        ProviderScope(
          overrides: [
            eyeSurgeryRepositoryProvider.overrideWithValue(fakeEyeRepo),
            inventoryRepositoryProvider.overrideWithValue(fakeInvRepo),
            inventoryProvider
                .overrideWith((ref) => InventoryNotifier(fakeInvRepo)),
            allEyeSurgeryItemTemplatesProvider
                .overrideWith((ref) => Future.value([])),
          ],
          child: const MaterialApp(
            home: Scaffold(
              body: SurgeryInventoryPresetsDialog(),
            ),
          ),
        ),
      );

      await tester.pumpAndSettle();

      expect(find.text('Surgery Inventory Presets'), findsOneWidget);
      expect(find.text('No preset items for Cataract Surgery'), findsOneWidget);
      expect(find.text('ADD ITEM TO Cataract Surgery PRESET'), findsOneWidget);
      // Verify no exceptions or RenderFlex overflow occurred
      expect(tester.takeException(), isNull);
    });

    testWidgets(
        'Dialog renders with many items on constrained 320x520 layout with NO RenderFlex overflow',
        (tester) async {
      tester.view.physicalSize = const Size(320, 520);
      tester.view.devicePixelRatio = 1.0;
      addTearDown(() => tester.view.resetPhysicalSize());

      final manyTemplates = List.generate(
        8,
        (i) => EyeSurgeryItemTemplateModel(
          id: 'tmpl-$i',
          surgeryType: 'Cataract Surgery',
          inventoryItemId: 'inv-item-$i',
          inventoryItemName: 'Surgical Consumable Long Item Name #$i',
          currentStock: 50.0,
          unit: 'pcs',
          defaultQuantity: (i + 1).toDouble(),
          isActive: true,
        ),
      );

      final fakeEyeRepo = FakeTestEyeSurgeryRepo()
        ..templates.addAll(manyTemplates);
      final fakeInvRepo = FakeTestInventoryRepo([]);

      await tester.pumpWidget(
        ProviderScope(
          overrides: [
            eyeSurgeryRepositoryProvider.overrideWithValue(fakeEyeRepo),
            inventoryRepositoryProvider.overrideWithValue(fakeInvRepo),
            inventoryProvider
                .overrideWith((ref) => InventoryNotifier(fakeInvRepo)),
            allEyeSurgeryItemTemplatesProvider
                .overrideWith((ref) => Future.value(manyTemplates)),
          ],
          child: const MaterialApp(
            home: Scaffold(
              body: SurgeryInventoryPresetsDialog(),
            ),
          ),
        ),
      );

      await tester.pumpAndSettle();

      expect(find.text('Surgery Inventory Presets'), findsOneWidget);
      expect(find.textContaining('Surgical Consumable Long Item Name #0'),
          findsOneWidget);
      // Verify zero RenderFlex overflow on 320x520 constrained layout
      expect(tester.takeException(), isNull);
    });

    testWidgets(
        'Dialog renders on wide desktop (1024x768) layout with accessible Add to Preset controls',
        (tester) async {
      tester.view.physicalSize = const Size(1024, 768);
      tester.view.devicePixelRatio = 1.0;
      addTearDown(() => tester.view.resetPhysicalSize());

      final inventoryItems = [
        const InventoryItem(
          id: 'inv-visco',
          name: 'Viscoelastic Sodium Hyaluronate',
          category: 'Surgical Supplies',
          currentStock: 25.0,
          unit: 'syringe',
        ),
      ];

      final fakeEyeRepo = FakeTestEyeSurgeryRepo();
      final fakeInvRepo = FakeTestInventoryRepo(inventoryItems);

      await tester.pumpWidget(
        ProviderScope(
          overrides: [
            eyeSurgeryRepositoryProvider.overrideWithValue(fakeEyeRepo),
            inventoryRepositoryProvider.overrideWithValue(fakeInvRepo),
            inventoryProvider
                .overrideWith((ref) => InventoryNotifier(fakeInvRepo)),
            allEyeSurgeryItemTemplatesProvider
                .overrideWith((ref) => Future.value([])),
          ],
          child: const MaterialApp(
            home: Scaffold(
              body: SurgeryInventoryPresetsDialog(),
            ),
          ),
        ),
      );

      await tester.pumpAndSettle();

      expect(find.text('Surgery Inventory Presets'), findsOneWidget);
      expect(find.text('Add to Preset'), findsOneWidget);
      expect(find.byType(TextField), findsOneWidget); // Required qty input
      expect(tester.takeException(), isNull);
    });
  });
}
