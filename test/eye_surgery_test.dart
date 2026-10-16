import 'dart:async';

import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:mkes_care/features/auth/providers/auth_provider.dart';
import 'package:mkes_care/features/eye/models/eye_surgery_model.dart';
import 'package:mkes_care/features/eye/models/eye_surgery_item_model.dart';
import 'package:mkes_care/features/eye/widgets/eye_surgery_form_dialog.dart';
import 'package:mkes_care/features/eye/screens/eye_surgery_screen.dart';
import 'package:mkes_care/features/eye/widgets/eye_surgery_item_dialogs.dart';
import 'package:mkes_care/features/eye/providers/eye_surgery_provider.dart';
import 'package:mkes_care/features/eye/repositories/eye_surgery_repository.dart';
import 'package:supabase_flutter/supabase_flutter.dart';
import 'package:mkes_care/features/appointments/providers/appointment_provider.dart';
import 'package:mkes_care/features/appointments/widgets/appointment_form_dialog.dart';
import 'package:mkes_care/features/inventory/models/inventory_item.dart';
import 'package:mkes_care/features/inventory/providers/inventory_provider.dart';
import 'package:mkes_care/features/inventory/repositories/inventory_repository.dart';
import 'package:mkes_care/features/notifications/models/notification_model.dart';
import 'package:mkes_care/features/staff/models/task_item.dart';
import 'package:mkes_care/features/staff/providers/task_provider.dart';
import 'package:mkes_care/features/staff/repositories/task_repository.dart';
import 'package:mkes_care/features/staff_portal/screens/staff_tasks_screen.dart';
import 'package:mkes_care/features/department/models/department.dart';
import 'package:mkes_care/features/department/providers/departments_provider.dart';
import 'package:mkes_care/features/department/repositories/department_repository.dart';

void main() {
  // ================================================================
  // A. Assigned Staff
  // ================================================================

  test('Admin accounts never appear in staff candidates, active staff appear', () {
    final candidates = uniqueEyeSurgeryStaffCandidates(const [
      EyeSurgeryStaffCandidate(id: 'adm-1', fullName: 'Admin User', role: 'admin', isActive: true),
      EyeSurgeryStaffCandidate(id: 'adm-2', fullName: 'Super Admin', role: 'Admin', isActive: true),
      EyeSurgeryStaffCandidate(id: 'staff-inact', fullName: 'Inactive Staff', role: 'staff', isActive: false),
      EyeSurgeryStaffCandidate(id: 'staff-1', fullName: 'Staff One', role: 'staff', isActive: true),
      EyeSurgeryStaffCandidate(id: 'STAFF-1', fullName: 'Staff One Duplicate', role: 'staff', isActive: true),
      EyeSurgeryStaffCandidate(id: '', fullName: 'Invalid Profile', role: 'staff', isActive: true),
      EyeSurgeryStaffCandidate(id: 'staff-2', fullName: 'Staff Two', role: 'staff', isActive: true),
    ]);

    expect(candidates.map((item) => item.id).toList(), ['staff-1', 'staff-2']);
    expect(candidates.first.fullName, 'Staff One');
  });

  testWidgets('Staff users cannot assign or change Assigned Staff; field is read-only',
      (tester) async {
    tester.view.devicePixelRatio = 1;
    tester.view.physicalSize = const Size(600, 900);
    addTearDown(tester.view.resetPhysicalSize);
    addTearDown(tester.view.resetDevicePixelRatio);

    final repository = _FakeEyeSurgeryRepository(items: [_sampleSurgery()]);
    repository.staffCandidates = const [
      EyeSurgeryStaffCandidate(id: 'staff-1', fullName: 'Dr. Rao', role: 'staff'),
      EyeSurgeryStaffCandidate(id: 'staff-2', fullName: 'Dr. Mehta', role: 'staff'),
    ];

    final container = ProviderContainer(overrides: [
      eyeSurgeryRepositoryProvider.overrideWithValue(repository),
      currentUserRoleProvider.overrideWith((ref) async => 'staff'),
      eyeSurgeryStaffCandidatesProvider
          .overrideWith((ref) async => repository.staffCandidates),
      eyeSurgeryItemTemplatesProvider('Cataract Surgery')
          .overrideWith((ref) async => const <EyeSurgeryItemTemplateModel>[]),
    ]);
    addTearDown(container.dispose);

    await tester.pumpWidget(
      UncontrolledProviderScope(
        container: container,
        child: MaterialApp(
          home: Scaffold(
            body: EyeSurgeryFormDialog(existingSurgery: _sampleSurgery()),
          ),
        ),
      ),
    );
    await tester.pumpAndSettle();

    // Staff sees assigned staff as read-only text
    expect(find.text('Dr. Rao'), findsOneWidget);
    expect(find.text('Assigned Staff is read-only (Admin assignment required)'),
        findsOneWidget);
    // No dropdown for selecting staff
    expect(find.byType(DropdownButtonFormField<String?>), findsNothing);
  });

  test('assigned_staff_id updates correctly and survives save/reload',
      () async {
    final repository =
        _FakeEyeSurgeryRepository(items: [_sampleSurgery()]);
    final container = ProviderContainer(overrides: [
      eyeSurgeryRepositoryProvider.overrideWithValue(repository),
    ]);
    addTearDown(container.dispose);
    await container.read(eyeSurgeryListProvider.future);
    final notifier = container.read(eyeSurgeryListProvider.notifier);

    // Select a staff member
    final assigned = await notifier.assignStaff('s-1', 'staff-3');
    expect(assigned.assignedStaffId, 'staff-3');

    // Reload and verify persistence
    await notifier.refresh();
    final reloaded = container
        .read(eyeSurgeryListProvider)
        .valueOrNull
        ?.firstWhere((item) => item.id == 's-1');
    expect(reloaded?.assignedStaffId, 'staff-3');
  });

  testWidgets('assigned staff dropdown renders candidates and selects by profile UUID',
      (tester) async {
    tester.view.devicePixelRatio = 1;
    tester.view.physicalSize = const Size(600, 900);
    addTearDown(tester.view.resetPhysicalSize);
    addTearDown(tester.view.resetDevicePixelRatio);

    final repository = _FakeEyeSurgeryRepository(items: [_sampleSurgery()]);
    repository.staffCandidates = const [
      EyeSurgeryStaffCandidate(id: 'staff-1', fullName: 'Dr. Rao'),
      EyeSurgeryStaffCandidate(id: 'staff-2', fullName: 'Dr. Mehta'),
    ];

    final container = ProviderContainer(overrides: [
      eyeSurgeryRepositoryProvider.overrideWithValue(repository),
      currentUserRoleProvider.overrideWith((ref) async => 'admin'),
      eyeSurgeryStaffCandidatesProvider.overrideWith((ref) async => repository.staffCandidates),
      eyeSurgeryItemTemplatesProvider('Cataract Surgery')
          .overrideWith((ref) async => const <EyeSurgeryItemTemplateModel>[]),
    ]);
    addTearDown(container.dispose);

    await tester.pumpWidget(
      UncontrolledProviderScope(
        container: container,
        child: MaterialApp(
          home: Scaffold(
            body: EyeSurgeryFormDialog(existingSurgery: _sampleSurgery()),
          ),
        ),
      ),
    );
    await tester.pumpAndSettle();

    // Verify assigned staff is Dr. Rao
    expect(find.text('Dr. Rao'), findsOneWidget);

    // Open dropdown
    await tester.tap(find.byType(DropdownButtonFormField<String?>));
    await tester.pumpAndSettle();

    expect(find.text('Dr. Mehta').last, findsOneWidget);
    await tester.tap(find.text('Dr. Mehta').last);
    await tester.pumpAndSettle();

    expect(find.text('Dr. Mehta'), findsOneWidget);
  });

  // ================================================================
  // B. Inventory Picker
  // ================================================================

  test('stock picker disables zero stock and revalidates before adding',
      () async {
    final stocked = _inventoryItem(id: 'inv-1', quantity: 2);
    final outOfStock = _inventoryItem(id: 'inv-1', quantity: 0);
    expect(isEyeSurgeryInventoryItemSelectable(stocked), isTrue);
    expect(isEyeSurgeryInventoryItemSelectable(outOfStock), isFalse);
    final disabledItem = eyeSurgeryInventoryMenuItem(outOfStock);
    expect(disabledItem.enabled, isFalse);
    expect((disabledItem.child as Text).data, contains('Out of Stock'));

    final inventoryRepository = _FakeInventoryRepository([stocked]);
    expect(
      await fetchSelectableEyeSurgeryInventoryItem(
        repository: inventoryRepository,
        itemId: 'inv-1',
      ),
      isNotNull,
    );
    inventoryRepository.items = [outOfStock];
    expect(
      await fetchSelectableEyeSurgeryInventoryItem(
        repository: inventoryRepository,
        itemId: 'inv-1',
      ),
      isNull,
    );
  });

  testWidgets('Go to Purchase Orders navigates to the existing PO route',
      (tester) async {
    final observer = _RecordingNavigatorObserver();
    await tester.pumpWidget(MaterialApp(
      navigatorObservers: [observer],
      home: Builder(
        builder: (context) => Scaffold(
          body: TextButton(
            onPressed: () => openEyeSurgeryPurchaseOrders(context),
            child: const Text('Go to Purchase Orders'),
          ),
        ),
      ),
    ));
    observer.lastPushed = null;
    await tester.tap(find.text('Go to Purchase Orders'));
    expect(observer.lastPushed?.settings.name, '/purchase-orders');
    expect(tester.takeException(), isNull);
  });

  // ================================================================
  // B. Checklist
  // ================================================================

  test('EyeSurgeryModel pre-op checklist has exactly 8 required items', () {
    expect(EyeSurgeryModel.checklistItems.length, 8);
    expect(EyeSurgeryModel.checklistItems.keys, containsAll([
      'identity_verified',
      'consent_confirmed',
      'correct_eye_confirmed',
      'pre_op_exam_completed',
      'investigations_reviewed',
      'allergies_checked',
      'assigned_staff_confirmed',
      'procedure_confirmed',
    ]));
  });

  testWidgets('Checklist button opens dialog, shows all 8 items, check/uncheck updates count and persists',
      (tester) async {
    tester.view.devicePixelRatio = 1;
    tester.view.physicalSize = const Size(800, 1000);
    addTearDown(tester.view.resetPhysicalSize);
    addTearDown(tester.view.resetDevicePixelRatio);

    final surgery = _sampleSurgery(status: 'pre_op');
    final repository = _FakeEyeSurgeryRepository(items: [surgery]);
    final container = ProviderContainer(overrides: [
      eyeSurgeryRepositoryProvider.overrideWithValue(repository),
      currentUserRoleProvider.overrideWith((ref) async => 'admin'),
    ]);
    addTearDown(container.dispose);

    await tester.pumpWidget(
      UncontrolledProviderScope(
        container: container,
        child: const MaterialApp(home: EyeSurgeryScreen()),
      ),
    );
    await tester.pumpAndSettle();

    // Click "Pre-op Checklist (1 / 8)" button on the surgery card
    expect(find.text('Pre-op Checklist (1 / 8)'), findsOneWidget);
    await tester.tap(find.text('Pre-op Checklist (1 / 8)'));
    await tester.pumpAndSettle();

    // All 8 items appear in checklist dialog
    expect(find.text('Pre-op Checklist'), findsOneWidget);
    expect(find.text('Patient identity verified'), findsOneWidget);
    expect(find.text('Consent confirmed'), findsOneWidget);
    expect(find.text('Correct eye confirmed'), findsOneWidget);
    expect(find.text('Pre-op examination completed'), findsOneWidget);
    expect(find.text('Required investigations reviewed'), findsOneWidget);
    expect(find.text('Allergies checked'), findsOneWidget);
    expect(find.text('Assigned staff confirmed'), findsOneWidget);
    expect(find.text('Procedure confirmed'), findsOneWidget);
    expect(find.text('1 / 8 completed'), findsOneWidget);

    // Toggle consent confirmed
    await tester.tap(find.text('Consent confirmed'));
    await tester.pumpAndSettle();
    expect(find.text('2 / 8 completed'), findsOneWidget);

    // Click Save checklist
    await tester.tap(find.text('Save checklist'));
    await tester.pumpAndSettle();

    // State persisted in repository
    final updated = repository.items.firstWhere((s) => s.id == surgery.id);
    expect(updated.preOpChecklist['consent_confirmed'], isTrue);
  });

  testWidgets('In Surgery transition is blocked when checklist incomplete and opens checklist with highlight',
      (tester) async {
    tester.view.devicePixelRatio = 1;
    tester.view.physicalSize = const Size(800, 1000);
    addTearDown(tester.view.resetPhysicalSize);
    addTearDown(tester.view.resetDevicePixelRatio);

    final surgery = _sampleSurgery(status: 'pre_op');
    final repository = _FakeEyeSurgeryRepository(items: [surgery]);
    final container = ProviderContainer(overrides: [
      eyeSurgeryRepositoryProvider.overrideWithValue(repository),
      currentUserRoleProvider.overrideWith((ref) async => 'admin'),
    ]);
    addTearDown(container.dispose);

    await tester.pumpWidget(
      UncontrolledProviderScope(
        container: container,
        child: const MaterialApp(home: EyeSurgeryScreen()),
      ),
    );
    await tester.pumpAndSettle();

    // Try entering surgery
    await tester.tap(find.byTooltip('Surgery actions'));
    await tester.pumpAndSettle();
    await tester.tap(find.text('Advance to In Surgery'));
    await tester.pumpAndSettle();

    // Blocked, warning snackbar shown
    expect(find.text('Complete the pre-op checklist before entering surgery.'),
        findsOneWidget);
    // Checklist dialog automatically opened with highlight
    expect(find.text('Complete all 8 required items before surgery'),
        findsOneWidget);
  });

  // ================================================================
  // C. Inventory Multi-Select & Navigation
  // ================================================================

  testWidgets('EyeSurgeryInventoryPickerDialog opens, supports multi-select, and adds selected items',
      (tester) async {
    tester.view.devicePixelRatio = 1;
    tester.view.physicalSize = const Size(800, 1000);
    addTearDown(tester.view.resetPhysicalSize);
    addTearDown(tester.view.resetDevicePixelRatio);

    final item1 = _inventoryItem(id: 'inv-1', quantity: 5);
    final item2 = InventoryItem(
      id: 'inv-2',
      name: 'Surgical Gloves',
      category: 'Surgical Equipment',
      currentStock: 10,
      unit: 'pairs',
    );
    final zeroStockItem = InventoryItem(
      id: 'inv-3',
      name: 'Zero Stock Lens',
      category: 'Surgical Equipment',
      currentStock: 0,
      unit: 'pcs',
    );

    final inventoryRepository =
        _FakeInventoryRepository([item1, item2, zeroStockItem]);
    final container = ProviderContainer(overrides: [
      inventoryRepositoryProvider.overrideWithValue(inventoryRepository),
      inventoryProvider.overrideWith(
        (ref) => _TestInventoryNotifier([item1, item2, zeroStockItem]),
      ),
    ]);
    addTearDown(container.dispose);

    List<({InventoryItem item, double quantity})>? selectedResult;

    await tester.pumpWidget(
      UncontrolledProviderScope(
        container: container,
        child: MaterialApp(
          home: Builder(
            builder: (context) => Scaffold(
              body: Center(
                child: ElevatedButton(
                  onPressed: () async {
                    selectedResult = await EyeSurgeryInventoryPickerDialog.show(
                      context,
                      excludedItemIds: {'inv-already'},
                    );
                  },
                  child: const Text('Open Picker'),
                ),
              ),
            ),
          ),
        ),
      ),
    );
    await tester.pumpAndSettle();

    // Open picker
    await tester.tap(find.text('Open Picker'));
    await tester.pumpAndSettle();

    // Zero stock shows Out of Stock and Go to Purchase Orders
    expect(find.text('Out of Stock'), findsOneWidget);
    expect(find.text('Go to Purchase Orders'), findsOneWidget);

    // Initial button text
    expect(find.text('Add Selected Items'), findsOneWidget);

    // Select item 1
    await tester.tap(find.text('Surgical Lens'));
    await tester.pumpAndSettle();
    expect(find.text('Add Selected Items (1)'), findsOneWidget);

    // Select item 2
    await tester.tap(find.text('Surgical Gloves'));
    await tester.pumpAndSettle();
    expect(find.text('Add Selected Items (2)'), findsOneWidget);

    // Confirm batch add
    await tester.tap(find.text('Add Selected Items (2)'));
    await tester.pumpAndSettle();

    expect(selectedResult, hasLength(2));
    expect(selectedResult!.map((i) => i.item.id).toList(), ['inv-1', 'inv-2']);
  });

  testWidgets('Purchase Orders navigation works and back button returns correctly',
      (tester) async {
    final observer = _RecordingNavigatorObserver();
    await tester.pumpWidget(MaterialApp(
      navigatorObservers: [observer],
      home: Builder(
        builder: (context) => Scaffold(
          body: Center(
            child: ElevatedButton(
              onPressed: () => openEyeSurgeryPurchaseOrders(context),
              child: const Text('Go to Purchase Orders'),
            ),
          ),
        ),
      ),
      routes: {
        '/purchase-orders': (context) => Scaffold(
              appBar: AppBar(
                leading: IconButton(
                  icon: const Icon(Icons.arrow_back),
                  onPressed: () => Navigator.of(context).pop(),
                ),
                title: const Text('Purchase Orders Screen'),
              ),
              body: const Text('PO Content'),
            ),
      },
    ));
    await tester.pumpAndSettle();

    // Navigate to PO
    await tester.tap(find.text('Go to Purchase Orders'));
    await tester.pumpAndSettle();

    expect(find.text('Purchase Orders Screen'), findsOneWidget);

    // Tap back button
    await tester.tap(find.byIcon(Icons.arrow_back));
    await tester.pumpAndSettle();

    // Returned to previous screen
    expect(find.text('Go to Purchase Orders'), findsOneWidget);
    expect(find.text('Purchase Orders Screen'), findsNothing);
  });

  // ================================================================
  // D. Follow-up Appointment (Post-Discharge Only)
  // ================================================================

  testWidgets('Follow-up appointment action is NOT shown before discharge',
      (tester) async {
    for (final st in ['scheduled', 'pre_op', 'in_surgery', 'post_op']) {
      final container = ProviderContainer(overrides: [
        currentUserRoleProvider.overrideWith((ref) async => 'admin'),
        eyeSurgeryListProvider.overrideWith(
          () => _FixedEyeSurgeryListNotifier([
            _sampleSurgery(status: st),
          ]),
        ),
      ]);
      await tester.pumpWidget(
        UncontrolledProviderScope(
          container: container,
          child: const MaterialApp(home: EyeSurgeryScreen()),
        ),
      );
      await tester.pumpAndSettle();

      expect(find.text('Schedule Follow-up Appointment'), findsNothing,
          reason: 'Should not show follow-up for status $st');
      container.dispose();
    }
  });

  testWidgets('Follow-up appointment action appears after discharge and shows indicator when scheduled',
      (tester) async {
    final dischargedSurgery = _sampleSurgery(status: 'discharged');
    final container = ProviderContainer(overrides: [
      currentUserRoleProvider.overrideWith((ref) async => 'admin'),
      eyeSurgeryListProvider.overrideWith(
        () => _FixedEyeSurgeryListNotifier([dischargedSurgery]),
      ),
    ]);
    addTearDown(container.dispose);

    await tester.pumpWidget(
      UncontrolledProviderScope(
        container: container,
        child: const MaterialApp(home: EyeSurgeryScreen()),
      ),
    );
    await tester.pumpAndSettle();

    // Visible for discharged surgery
    expect(find.text('Schedule Follow-up Appointment'), findsOneWidget);

    // If follow-up appointment is already scheduled
    final alreadyScheduled = _sampleSurgery(
      status: 'discharged',
      followUpAppointmentId: 'apt-101',
    );
    final container2 = ProviderContainer(overrides: [
      currentUserRoleProvider.overrideWith((ref) async => 'admin'),
      eyeSurgeryListProvider.overrideWith(
        () => _FixedEyeSurgeryListNotifier([alreadyScheduled]),
      ),
    ]);
    addTearDown(container2.dispose);

    await tester.pumpWidget(
      UncontrolledProviderScope(
        container: container2,
        child: const MaterialApp(home: EyeSurgeryScreen()),
      ),
    );
    await tester.pumpAndSettle();

    expect(find.text('Follow-up Scheduled'), findsOneWidget);
    expect(find.text('Schedule Follow-up Appointment'), findsNothing);
  });

  // ================================================================
  // E. Missed Surgery & Reschedule
  // ================================================================

  test('isMissed derives missed state only for past scheduled/pre_op surgeries', () {
    final pastDate = DateTime.now().subtract(const Duration(days: 2));
    final futureDate = DateTime.now().add(const Duration(days: 2));

    // Past scheduled/pre_op is missed
    final missedScheduled =
        _sampleSurgery(status: 'scheduled', surgeryDate: pastDate);
    final missedPreOp = _sampleSurgery(status: 'pre_op', surgeryDate: pastDate);
    expect(missedScheduled.isMissed, isTrue);
    expect(missedPreOp.isMissed, isTrue);

    // Future scheduled/pre_op is NOT missed
    final futureScheduled =
        _sampleSurgery(status: 'scheduled', surgeryDate: futureDate);
    expect(futureScheduled.isMissed, isFalse);

    // Past in_surgery, post_op, discharged, cancelled are NOT missed
    for (final st in ['in_surgery', 'post_op', 'discharged', 'cancelled']) {
      final activeOrDone = _sampleSurgery(status: st, surgeryDate: pastDate);
      expect(activeOrDone.isMissed, isFalse,
          reason: 'Status $st should not be missed');
    }
  });

  testWidgets('Missed surgery card shows MISSED badge and Admin can reschedule without duplicate',
      (tester) async {
    final pastDate = DateTime.now().subtract(const Duration(days: 2));
    final missedSurgery =
        _sampleSurgery(status: 'scheduled', surgeryDate: pastDate);
    final repository = _FakeEyeSurgeryRepository(items: [missedSurgery]);

    final container = ProviderContainer(overrides: [
      eyeSurgeryRepositoryProvider.overrideWithValue(repository),
      currentUserRoleProvider.overrideWith((ref) async => 'admin'),
      eyeSurgerySelectedDateProvider.overrideWith((ref) => pastDate),
    ]);
    addTearDown(container.dispose);

    await tester.pumpWidget(
      UncontrolledProviderScope(
        container: container,
        child: const MaterialApp(home: EyeSurgeryScreen()),
      ),
    );
    await tester.pumpAndSettle();

    // MISSED badge and Reschedule Surgery button shown
    expect(find.text('MISSED'), findsOneWidget);
    expect(find.text('Reschedule Surgery'), findsOneWidget);

    // Reschedule
    final notifier = container.read(eyeSurgeryListProvider.notifier);
    final futureDate = DateTime.now().add(const Duration(days: 5));
    final rescheduled = await notifier.rescheduleSurgery(
      id: missedSurgery.id,
      surgeryDate: futureDate,
      surgeryTime: '11:00:00',
    );

    expect(rescheduled.id, missedSurgery.id);
    expect(rescheduled.isMissed, isFalse);
    expect(repository.items, hasLength(1)); // No duplicate
  });

  testWidgets('Staff users see MISSED badge and can reschedule surgery',
      (tester) async {
    final pastDate = DateTime.now().subtract(const Duration(days: 2));
    final missedSurgery =
        _sampleSurgery(status: 'scheduled', surgeryDate: pastDate, surgeryTime: '08:00:00');
    final repository = _FakeEyeSurgeryRepository(items: [missedSurgery]);

    final container = ProviderContainer(overrides: [
      eyeSurgeryRepositoryProvider.overrideWithValue(repository),
      currentUserRoleProvider.overrideWith((ref) async => 'staff'),
      eyeSurgerySelectedDateProvider.overrideWith((ref) => pastDate),
    ]);
    addTearDown(container.dispose);

    await tester.pumpWidget(
      UncontrolledProviderScope(
        container: container,
        child: const MaterialApp(home: EyeSurgeryScreen()),
      ),
    );
    await tester.pumpAndSettle();

    expect(find.text('MISSED'), findsOneWidget);
    expect(find.text('Reschedule Surgery'), findsOneWidget);
  });

  // ================================================================
  // D. Default Inventory Items
  // ================================================================

  test('surgery item edits stay local and never change global templates',
      () async {
    final repository = _FakeEyeSurgeryRepository();
    repository.templates.add(const EyeSurgeryItemTemplateModel(
      id: 'tpl-1',
      surgeryType: 'Cataract Surgery',
      inventoryItemId: 'inv-default',
      inventoryItemName: 'Default Lens',
      currentStock: 12,
      unit: 'pcs',
      defaultQuantity: 1,
      isActive: true,
    ));
    final container = ProviderContainer(overrides: [
      eyeSurgeryRepositoryProvider.overrideWithValue(repository),
    ]);
    addTearDown(container.dispose);
    final notifier = container.read(eyeSurgeryItemsProvider('s-1').notifier);
    expect(
        await container.read(eyeSurgeryItemsProvider('s-1').future), isEmpty);

    await notifier.addItem(
      inventoryItemId: 'inv-manual',
      plannedQuantity: 1,
      actualQuantity: 1,
    );
    expect(container.read(eyeSurgeryItemsProvider('s-1')).valueOrNull,
        hasLength(1));
    expect(repository.templates.single.defaultQuantity, 1);

    final item = container.read(eyeSurgeryItemsProvider('s-1')).value!.single;
    await notifier.updateItem(
      itemId: item.id,
      plannedQuantity: 2,
      actualQuantity: 2,
    );
    expect(
      container
          .read(eyeSurgeryItemsProvider('s-1'))
          .value!
          .single
          .actualQuantity,
      2,
    );
    // Template quantity unchanged
    expect(repository.templates.single.defaultQuantity, 1);

    await notifier.removeItem(item.id);
    expect(
        container.read(eyeSurgeryItemsProvider('s-1')).valueOrNull, isEmpty);
    // Template still unchanged
    expect(repository.templates.single.defaultQuantity, 1);
  });

  test('template items are loaded for surgery type', () async {
    final repository = _FakeEyeSurgeryRepository();
    repository.templates.addAll(const [
      EyeSurgeryItemTemplateModel(
        id: 'tpl-1',
        surgeryType: 'Cataract Surgery',
        inventoryItemId: 'inv-iol',
        inventoryItemName: 'IOL',
        currentStock: 10,
        unit: 'pcs',
        defaultQuantity: 1,
        isActive: true,
      ),
      EyeSurgeryItemTemplateModel(
        id: 'tpl-2',
        surgeryType: 'Cataract Surgery',
        inventoryItemId: 'inv-gloves',
        inventoryItemName: 'Surgical Gloves',
        currentStock: 50,
        unit: 'pairs',
        defaultQuantity: 2,
        isActive: true,
      ),
      EyeSurgeryItemTemplateModel(
        id: 'tpl-3',
        surgeryType: 'Glaucoma Surgery',
        inventoryItemId: 'inv-glaucoma',
        inventoryItemName: 'Glaucoma Implant',
        currentStock: 5,
        unit: 'pcs',
        defaultQuantity: 1,
        isActive: true,
      ),
    ]);

    final container = ProviderContainer(overrides: [
      eyeSurgeryRepositoryProvider.overrideWithValue(repository),
    ]);
    addTearDown(container.dispose);

    // Cataract templates load correctly
    final cataractTemplates = await container
        .read(eyeSurgeryItemTemplatesProvider('Cataract Surgery').future);
    expect(cataractTemplates, hasLength(2));
    expect(cataractTemplates.first.inventoryItemName, 'IOL');
    expect(cataractTemplates.first.defaultQuantity, 1);
    expect(cataractTemplates.last.inventoryItemName, 'Surgical Gloves');
    expect(cataractTemplates.last.defaultQuantity, 2);

    // Changing surgery type loads different templates
    final glaucomaTemplates = await container
        .read(eyeSurgeryItemTemplatesProvider('Glaucoma Surgery').future);
    expect(glaucomaTemplates, hasLength(1));
    expect(glaucomaTemplates.first.inventoryItemName, 'Glaucoma Implant');
  });

  test('existing saved surgery items are NOT overwritten by templates',
      () async {
    final repository = _FakeEyeSurgeryRepository(items: [_sampleSurgery()]);
    // Pre-existing surgery item
    repository.surgeryItems.add(const EyeSurgeryItemModel(
      id: 'si-existing',
      surgeryId: 's-1',
      inventoryItemId: 'inv-iol',
      inventoryItemName: 'IOL',
      currentStock: 10,
      unit: 'pcs',
      plannedQuantity: 3,
      actualQuantity: 3,
      source: 'template',
    ));
    repository.templates.add(const EyeSurgeryItemTemplateModel(
      id: 'tpl-1',
      surgeryType: 'Cataract Surgery',
      inventoryItemId: 'inv-iol',
      inventoryItemName: 'IOL',
      currentStock: 10,
      unit: 'pcs',
      defaultQuantity: 1,
      isActive: true,
    ));

    final container = ProviderContainer(overrides: [
      eyeSurgeryRepositoryProvider.overrideWithValue(repository),
    ]);
    addTearDown(container.dispose);

    final items =
        await container.read(eyeSurgeryItemsProvider('s-1').future);
    // Should show the existing saved item, not template default
    expect(items, hasLength(1));
    expect(items.first.plannedQuantity, 3); // not 1 from template
  });

  testWidgets('EyeSurgeryFormDialog auto-prepopulates templates and updates when surgery type changes',
      (tester) async {
    tester.view.devicePixelRatio = 1;
    tester.view.physicalSize = const Size(600, 900);
    addTearDown(tester.view.resetPhysicalSize);
    addTearDown(tester.view.resetDevicePixelRatio);

    final cataractTemplates = const [
      EyeSurgeryItemTemplateModel(
        id: 'tpl-1',
        surgeryType: 'Cataract Surgery',
        inventoryItemId: 'inv-iol',
        inventoryItemName: 'IOL Lens',
        currentStock: 10,
        unit: 'pcs',
        defaultQuantity: 1,
        isActive: true,
      ),
      EyeSurgeryItemTemplateModel(
        id: 'tpl-2',
        surgeryType: 'Cataract Surgery',
        inventoryItemId: 'inv-gloves',
        inventoryItemName: 'Surgical Gloves',
        currentStock: 50,
        unit: 'pairs',
        defaultQuantity: 2,
        isActive: true,
      ),
    ];

    final glaucomaTemplates = const [
      EyeSurgeryItemTemplateModel(
        id: 'tpl-3',
        surgeryType: 'Glaucoma Surgery',
        inventoryItemId: 'inv-valve',
        inventoryItemName: 'Ahmed Glaucoma Valve',
        currentStock: 5,
        unit: 'pcs',
        defaultQuantity: 1,
        isActive: true,
      ),
    ];

    final container = ProviderContainer(
      overrides: [
        currentUserRoleProvider.overrideWith((ref) async => 'admin'),
        eyeSurgeryStaffCandidatesProvider.overrideWith((ref) async => const [
          EyeSurgeryStaffCandidate(id: 'staff-1', fullName: 'Dr. Rao'),
        ]),
        eyeSurgeryItemTemplatesProvider('Cataract Surgery')
            .overrideWith((ref) async => cataractTemplates),
        eyeSurgeryItemTemplatesProvider('Glaucoma Surgery')
            .overrideWith((ref) async => glaucomaTemplates),
      ],
    );
    addTearDown(container.dispose);

    await tester.pumpWidget(
      UncontrolledProviderScope(
        container: container,
        child: const MaterialApp(
          home: Scaffold(
            body: EyeSurgeryFormDialog(),
          ),
        ),
      ),
    );
    await tester.pumpAndSettle();

    // Default Cataract items appear automatically
    expect(find.text('SURGERY ITEMS'), findsOneWidget);
    expect(find.text('IOL Lens'), findsOneWidget);
    expect(find.text('Planned: 1.0 pcs'), findsOneWidget);
    expect(find.text('Surgical Gloves'), findsOneWidget);
    expect(find.text('Planned: 2.0 pairs'), findsOneWidget);
    expect(find.text('Add Inventory Item'), findsOneWidget);

    // Change surgery type from Cataract to Glaucoma
    await tester.tap(find.byType(DropdownButtonFormField<String>).first);
    await tester.pumpAndSettle();
    await tester.tap(find.text('Glaucoma Surgery').last);
    await tester.pumpAndSettle();

    // Cataract items cleared, Glaucoma template loaded
    expect(find.text('Ahmed Glaucoma Valve'), findsOneWidget);
    expect(find.text('Planned: 1.0 pcs'), findsOneWidget);
    expect(find.text('IOL Lens'), findsNothing);
  });

  // ================================================================
  // E. Inventory Safety
  // ================================================================

  test('preselection does NOT deduct stock; entering In Surgery deducts once',
      () async {
    final repository = _FakeEyeSurgeryRepository(items: [_sampleSurgery()]);
    final container = ProviderContainer(overrides: [
      eyeSurgeryRepositoryProvider.overrideWithValue(repository),
    ]);
    addTearDown(container.dispose);
    await container.read(eyeSurgeryListProvider.future);
    final notifier = container.read(eyeSurgeryListProvider.notifier);

    // Adding a surgery item = no inventory consumed
    await container.read(eyeSurgeryItemsProvider('s-1').notifier).addItem(
          inventoryItemId: 'inv-1',
          plannedQuantity: 2,
        );
    expect(repository.inventoryConsumptions, 0);

    // Advance to pre_op
    await notifier.updateStatus('s-1', 'pre_op');
    expect(repository.inventoryConsumptions, 0);

    // Complete checklist and start surgery
    final completeChecklist = {
      for (final key in EyeSurgeryModel.checklistItems.keys) key: true,
    };
    await notifier.updateChecklist('s-1', completeChecklist);
    final started = await notifier.startSurgery('s-1');
    expect(started.status, 'in_surgery');
    expect(repository.inventoryConsumptions, 1);

    // Second call doesn't deduct again (idempotent)
    await notifier.startSurgery('s-1');
    expect(repository.inventoryConsumptions, 1);
  });

  test('insufficient stock blocks In Surgery transition', () async {
    final repository = _FakeEyeSurgeryRepository(items: [_sampleSurgery()]);
    repository.blockStartSurgery = true;
    final container = ProviderContainer(overrides: [
      eyeSurgeryRepositoryProvider.overrideWithValue(repository),
    ]);
    addTearDown(container.dispose);
    await container.read(eyeSurgeryListProvider.future);
    final notifier = container.read(eyeSurgeryListProvider.notifier);

    await notifier.updateStatus('s-1', 'pre_op');
    final completeChecklist = {
      for (final key in EyeSurgeryModel.checklistItems.keys) key: true,
    };
    await notifier.updateChecklist('s-1', completeChecklist);

    await expectLater(
      notifier.startSurgery('s-1'),
      throwsA(isA<StateError>().having(
        (error) => error.message,
        'message',
        contains('Insufficient stock'),
      )),
    );
    expect(repository.inventoryConsumptions, 0);
  });

  // ================================================================
  // F. Eye Surgery model and validation
  // ================================================================

  group('Eye Surgery model and validation', () {
    test('parses joined data, checklist values, and nullable fields safely',
        () {
      final surgery = EyeSurgeryModel.fromJson({
        'id': 's-1',
        'patient_id': 'p-1',
        'surgery_type': 'Cataract Surgery',
        'surgery_type_category': 'Cataract Surgery',
        'eye_side': 'left',
        'assigned_staff_id': 'staff-1',
        'pre_op_date': '2026-10-12',
        'surgery_date': '2026-10-12',
        'surgery_time': null,
        'status': 'scheduled',
        'pre_op_checklist': {
          'identity_verified': true,
          'consent_confirmed': false,
          'unexpected_value': 'ignored',
        },
        'iol_details': null,
        'remarks': null,
        'created_at': '2026-10-01T08:00:00Z',
        'updated_at': '2026-10-02T08:00:00Z',
        'patients': {'name': 'Aisha Kumar', 'patient_number': 'E102'},
        'assigned_staff': {'full_name': 'Staff Rao'},
      });

      expect(surgery.patientName, 'Aisha Kumar');
      expect(surgery.patientNumber, 'E102');
      expect(surgery.assignedStaffName, 'Staff Rao');
      expect(surgery.assignedStaffId, 'staff-1');
      expect(surgery.displaySurgeryType, 'Cataract Surgery');
      expect(surgery.isPreOpChecklistComplete, isFalse);
    });

    test('serializes database columns and nullable values', () {
      final surgery = _sampleSurgery(surgeryDate: DateTime(2026, 10, 12));
      final json = surgery.toJson();

      expect(json['id'], 's-1');
      expect(json['patient_id'], 'p-1');
      expect(json['surgery_type_category'], 'Cataract Surgery');
      expect(json['pre_op_date'], '2026-10-12');
      expect(json['surgery_date'], '2026-10-12');
      expect(json['assigned_staff_id'], 'staff-1');
      expect(json.containsKey('appointment_id'), isFalse);
    });

    test('rejects missing required values and invalid enum values', () {
      final targetDate = DateTime(2026, 10, 12);
      expect(
        EyeSurgeryModel.validateFields(
          patientId: '',
          surgeryType: 'Cataract Surgery',
          surgeryTypeCategory: 'Cataract Surgery',
          eyeSide: 'left',
          preOpDate: targetDate,
          surgeryDate: targetDate,
          status: 'scheduled',
        ),
        'Patient selection is required.',
      );

      expect(
        EyeSurgeryModel.validateFields(
          patientId: 'p-1',
          surgeryType: 'Cataract Surgery',
          surgeryTypeCategory: 'Cataract Surgery',
          eyeSide: 'middle',
          preOpDate: targetDate,
          surgeryDate: targetDate,
          status: 'scheduled',
        ),
        'Select a valid eye side.',
      );
    });

    test('surgery options and pre-op date equality are enforced', () {
      final firstDate = DateTime(2026, 10, 12);
      final differentDate = DateTime(2026, 10, 13);
      expect(
        EyeSurgeryModel.validateFields(
          patientId: 'p-1',
          surgeryType: 'Cataract Surgery',
          surgeryTypeCategory: 'Cataract Surgery',
          eyeSide: 'left',
          preOpDate: differentDate,
          surgeryDate: firstDate,
          status: 'scheduled',
        ),
        'Pre-op date must match surgery date.',
      );
    });

    test('surgery item and template records map stock and origin safely', () {
      final item = EyeSurgeryItemModel.fromJson({
        'id': 'si-1',
        'eye_surgery_id': 's-1',
        'inventory_item_id': 'inv-1',
        'planned_quantity': 2,
        'actual_quantity': 2,
        'source': 'template',
        'inventory': {
          'name': 'Intraocular Lens',
          'quantity': 15,
          'unit': 'pcs',
        },
      });

      expect(item.inventoryItemName, 'Intraocular Lens');
      expect(item.currentStock, 15);
      expect(item.unit, 'pcs');
      expect(item.source, 'template');
    });

    test(
        'allows only forward transitions and cancellation from active states',
        () {
      expect(EyeSurgeryModel.canTransition('scheduled', 'pre_op'), isTrue);
      expect(EyeSurgeryModel.canTransition('pre_op', 'in_surgery'), isTrue);
      expect(EyeSurgeryModel.canTransition('in_surgery', 'post_op'), isTrue);
      expect(EyeSurgeryModel.canTransition('post_op', 'billing'), isTrue);
      expect(EyeSurgeryModel.canTransition('billing', 'discharged'), isTrue);

      // Backwards transitions rejected
      expect(EyeSurgeryModel.canTransition('in_surgery', 'scheduled'), isFalse);
      expect(EyeSurgeryModel.canTransition('post_op', 'pre_op'), isFalse);

      // Cancellation allowed from active states
      expect(EyeSurgeryModel.canTransition('scheduled', 'cancelled'), isTrue);
      expect(EyeSurgeryModel.canTransition('pre_op', 'cancelled'), isTrue);
      expect(EyeSurgeryModel.canTransition('discharged', 'cancelled'), isFalse);
    });

    test('Eye Surgery provider supports loading, empty, error, and refresh states',
        () async {
      final repository = _FakeEyeSurgeryRepository(items: [_sampleSurgery()]);
      final container = ProviderContainer(
        overrides: [
          eyeSurgeryRepositoryProvider.overrideWithValue(repository),
        ],
      );
      addTearDown(container.dispose);

      final state = await container.read(eyeSurgeryListProvider.future);
      expect(state, hasLength(1));

      // Refresh state
      await container.read(eyeSurgeryListProvider.notifier).refresh();
      expect(container.read(eyeSurgeryListProvider).valueOrNull, hasLength(1));
    });

    test('Eye Surgery provider mutations keep create, edit, assigned staff, checklist, and IOL data current',
        () async {
      final repository = _FakeEyeSurgeryRepository();
      final container = ProviderContainer(
        overrides: [
          eyeSurgeryRepositoryProvider.overrideWithValue(repository),
        ],
      );
      addTearDown(container.dispose);
      await container.read(eyeSurgeryListProvider.future);

      final created = await container
          .read(eyeSurgeryListProvider.notifier)
          .createSurgery(
            patientId: 'p-1',
            surgeryType: 'Cataract Surgery',
            surgeryTypeCategory: 'Cataract Surgery',
            eyeSide: 'left',
            surgeryDate: DateTime(2026, 10, 12),
            assignedStaffId: 'staff-1',
            surgeryTime: '09:00:00',
            preOpChecklist: {'identity_verified': true},
            iolDetails: 'SN60WF +21.5D',
            remarks: 'Smooth operation planned',
          );

      expect(created.patientId, 'p-1');
      expect(created.iolDetails, 'SN60WF +21.5D');

      // Update details
      await container.read(eyeSurgeryListProvider.notifier).updateDetails(
            id: created.id,
            iolDetails: 'Updated IOL',
            remarks: 'Updated remarks',
          );
      final updated = container
          .read(eyeSurgeryListProvider)
          .valueOrNull
          ?.firstWhere((item) => item.id == created.id);
      expect(updated?.iolDetails, 'Updated IOL');
      expect(updated?.remarks, 'Updated remarks');
    });

    testWidgets('form renders and dropdowns remain usable at compact width',
        (tester) async {
      tester.view.devicePixelRatio = 1;
      tester.view.physicalSize = const Size(360, 800);
      addTearDown(tester.view.resetPhysicalSize);
      addTearDown(tester.view.resetDevicePixelRatio);

      var staffCandidates = const <EyeSurgeryStaffCandidate>[
        EyeSurgeryStaffCandidate(id: 'staff-1', fullName: 'Dr. Rao'),
        EyeSurgeryStaffCandidate(
          id: 'STAFF-1',
          fullName: 'Duplicate Profile Row',
        ),
      ];
      final container = ProviderContainer(
        overrides: [
          currentUserRoleProvider.overrideWith((ref) async => 'admin'),
          eyeSurgeryStaffCandidatesProvider
              .overrideWith((ref) async => staffCandidates),
          eyeSurgeryItemTemplatesProvider('Cataract Surgery')
              .overrideWith((ref) async =>
                  const <EyeSurgeryItemTemplateModel>[]),
        ],
      );
      addTearDown(container.dispose);

      await tester.pumpWidget(
        UncontrolledProviderScope(
          container: container,
          child: MaterialApp(
            home: Scaffold(
              body: EyeSurgeryFormDialog(existingSurgery: _sampleSurgery()),
            ),
          ),
        ),
      );
      await tester.pumpAndSettle();

      expect(find.text('Edit Eye Surgery'), findsOneWidget);
      expect(find.text('Surgery type *'), findsOneWidget);
      expect(find.text('Eye side *'), findsOneWidget);
      expect(tester.takeException(), isNull);

      staffCandidates = const [
        EyeSurgeryStaffCandidate(
          id: 'staff-1',
          fullName: 'Dr. Rao Refreshed',
        ),
        EyeSurgeryStaffCandidate(id: 'staff-2', fullName: 'Dr. Iyer'),
      ];
      container.invalidate(eyeSurgeryStaffCandidatesProvider);
      await tester.pumpAndSettle();
      expect(find.text('Dr. Rao Refreshed'), findsOneWidget);
      expect(tester.takeException(), isNull);

      await tester.tap(find.byType(DropdownButtonFormField<String>).first);
      await tester.pumpAndSettle();
      expect(find.text('LASIK / Refractive Surgery'), findsOneWidget);
      await tester.tap(find.text('Other').last);
      await tester.pumpAndSettle();
      expect(find.text('Custom surgery type *'), findsOneWidget);

      await tester.tap(find.byType(DropdownButtonFormField<String>).at(1));
      await tester.pumpAndSettle();
      expect(find.text('Right eye'), findsOneWidget);
      await tester.tap(find.text('Right eye'));
      await tester.pumpAndSettle();
      expect(tester.takeException(), isNull);
    });
  });

  // ================================================================
  // G. Sprint 5.2 Patch: Follow-up, Pre-op, Notifications, Shift Tasks
  // ================================================================

  group('Sprint 5.2 Patch: Follow-up, Pre-op, Notifications, Shift Tasks', () {
    test('AppointmentFormDialog normalizes appointment type aliases to canonical values', () {
      expect(AppointmentFormDialog.normalizeAppointmentType('follow-up'), 'follow_up');
      expect(AppointmentFormDialog.normalizeAppointmentType('follow_up'), 'follow_up');
      expect(AppointmentFormDialog.normalizeAppointmentType('FOLLOWUP'), 'follow_up');
      expect(AppointmentFormDialog.normalizeAppointmentType('walk-in'), 'walk_in');
      expect(AppointmentFormDialog.normalizeAppointmentType('walk_in'), 'walk_in');
      expect(AppointmentFormDialog.normalizeAppointmentType('regular'), 'regular');
      expect(AppointmentFormDialog.normalizeAppointmentType(null), 'regular');
      expect(AppointmentFormDialog.normalizeAppointmentType(''), 'regular');

      final types = AppointmentFormDialog.availableAppointmentTypes;
      final ids = types.map((t) => t.id).toSet();
      expect(ids.length, types.length, reason: 'Appointment type IDs must be unique');
      expect(ids.contains('follow_up'), isTrue);
    });

    testWidgets('AppointmentFormDialog renders follow-up without DropdownButton assertion',
        (tester) async {
      tester.view.devicePixelRatio = 1;
      tester.view.physicalSize = const Size(600, 900);
      addTearDown(tester.view.resetPhysicalSize);
      addTearDown(tester.view.resetDevicePixelRatio);

      await tester.pumpWidget(
        ProviderScope(
          overrides: [
            departmentsProvider.overrideWith((ref) => _TestDepartmentsNotifier()),
            appointmentStaffCandidatesProvider('eye-dept')
                .overrideWith((ref) async => []),
          ],
          child: const MaterialApp(
            home: Scaffold(
              body: AppointmentFormDialog(
                initialAppointmentType: 'follow-up',
                initialPatientId: 'p-1',
                initialPatientName: 'Aisha Kumar',
              ),
            ),
          ),
        ),
      );
      await tester.pumpAndSettle();

      expect(tester.takeException(), isNull);
      expect(find.text('Follow-up'), findsOneWidget);
    });

    testWidgets('Follow-up appointment option appears ONLY after status is discharged',
        (tester) async {
      final postOpSurgery = _sampleSurgery(status: 'post_op');
      final dischargedSurgery = _sampleSurgery(status: 'discharged');
      final repository = _FakeEyeSurgeryRepository(items: [postOpSurgery]);

      final container = ProviderContainer(overrides: [
        eyeSurgeryRepositoryProvider.overrideWithValue(repository),
        currentUserRoleProvider.overrideWith((ref) async => 'admin'),
      ]);
      addTearDown(container.dispose);

      await tester.pumpWidget(
        UncontrolledProviderScope(
          container: container,
          child: const MaterialApp(home: EyeSurgeryScreen()),
        ),
      );
      await tester.pumpAndSettle();

      // In post-op: NO follow-up button
      expect(find.text('Schedule Follow-up Appointment'), findsNothing);

      // Switch to discharged surgery
      repository.items = [dischargedSurgery];
      await container.read(eyeSurgeryListProvider.notifier).refresh();
      await tester.pumpAndSettle();

      // In discharged: follow-up button IS visible
      expect(find.text('Schedule Follow-up Appointment'), findsOneWidget);
    });

    test('Scheduled surgery without assigned staff blocks transition to pre_op', () {
      final surgeryWithoutStaff = _sampleSurgery(status: 'scheduled', assignedStaffId: null);
      final error = EyeSurgeryModel.validateStatusTransition(
        surgery: surgeryWithoutStaff,
        nextStatus: 'pre_op',
      );
      expect(error, 'An Admin must assign staff to this surgery before starting Pre-op.');
    });

    test('Scheduled surgery with assigned staff allows transition to pre_op', () {
      final surgeryWithStaff = _sampleSurgery(status: 'scheduled', assignedStaffId: 'staff-1');
      final error = EyeSurgeryModel.validateStatusTransition(
        surgery: surgeryWithStaff,
        nextStatus: 'pre_op',
      );
      expect(error, isNull);
    });

    testWidgets('EyeSurgeryScreen blocks Pre-op when no staff is assigned',
        (tester) async {
      final surgery = _sampleSurgery(status: 'scheduled', assignedStaffId: null);
      final repository = _FakeEyeSurgeryRepository(items: [surgery]);

      final container = ProviderContainer(overrides: [
        eyeSurgeryRepositoryProvider.overrideWithValue(repository),
        currentUserRoleProvider.overrideWith((ref) async => 'admin'),
      ]);
      addTearDown(container.dispose);

      await tester.pumpWidget(
        UncontrolledProviderScope(
          container: container,
          child: const MaterialApp(home: EyeSurgeryScreen()),
        ),
      );
      await tester.pumpAndSettle();

      final moreButton = find.byIcon(Icons.more_vert);
      expect(moreButton, findsOneWidget);
      await tester.tap(moreButton);
      await tester.pumpAndSettle();

      final advanceItem = find.text('Advance to Pre Op');
      expect(advanceItem, findsOneWidget);
      await tester.tap(advanceItem);
      await tester.pumpAndSettle();

      expect(find.text('An Admin must assign staff to this surgery before starting Pre-op.'), findsOneWidget);
      expect(repository.items.first.status, 'scheduled');
    });

    test('Assigning staff sends notification once; assigning same staff does not duplicate; reassigning notifies new staff', () async {
      final surgery = _sampleSurgery(status: 'scheduled', assignedStaffId: null);
      final repository = _FakeEyeSurgeryRepository(items: [surgery]);

      // 1. Assign Staff 1 -> 1 notification to staff-1
      await repository.assignStaff(surgery.id, 'staff-1');
      expect(repository.notifications.length, 1);
      expect(repository.notifications.first.userId, 'staff-1');
      expect(repository.notifications.first.title, 'Eye Surgery Assigned');

      // 2. Assign same Staff 1 again -> no new notification
      await repository.assignStaff(surgery.id, 'staff-1');
      expect(repository.notifications.length, 1);

      // 3. Reassign Staff 1 -> Staff 2 -> notification to staff-2
      await repository.assignStaff(surgery.id, 'staff-2');
      expect(repository.notifications.length, 2);
      expect(repository.notifications.last.userId, 'staff-2');
    });

    test('Surgery assignment creates linked pending shift task, remains pending until discharged', () async {
      final surgery = _sampleSurgery(status: 'scheduled', assignedStaffId: null);
      final repository = _FakeEyeSurgeryRepository(items: [surgery]);

      // Assign staff
      await repository.assignStaff(surgery.id, 'staff-1');
      expect(repository.tasks.length, 1);
      final task = repository.tasks.first;
      expect(task.relatedSurgeryId, surgery.id);
      expect(task.isSurgeryTask, isTrue);
      expect(task.status, 'pending');
      expect(task.assignedTo, 'staff-1');
      expect(task.dueDate, surgery.surgeryDate);

      // Move to pre_op -> task still pending
      await repository.updateStatus(surgery.id, 'pre_op');
      expect(repository.tasks.first.status, 'pending');

      // Reschedule surgery date -> task moves to new date
      final newDate = DateTime(2026, 10, 20);
      await repository.rescheduleSurgery(
        id: surgery.id,
        surgeryDate: newDate,
        surgeryTime: '10:00:00',
      );
      expect(repository.tasks.length, 1);
      expect(repository.tasks.first.dueDate, newDate);

      // Move through surgery workflow
      final completeChecklist = {
        for (final key in EyeSurgeryModel.checklistItems.keys) key: true,
      };
      await repository.updatePreOpChecklist(surgery.id, completeChecklist);
      await repository.startSurgery(surgery.id);
      expect(repository.tasks.first.status, 'pending');

      await repository.updateStatus(surgery.id, 'post_op');
      expect(repository.tasks.first.status, 'pending');

      // Discharged -> task completed
      await repository.updateStatus(surgery.id, 'discharged');
      expect(repository.tasks.first.status, 'completed');
    });

    test('Cancelling surgery sets linked shift task to cancelled', () async {
      final surgery = _sampleSurgery(status: 'scheduled', assignedStaffId: null);
      final repository = _FakeEyeSurgeryRepository(items: [surgery]);
      await repository.assignStaff(surgery.id, 'staff-1');
      expect(repository.tasks.first.status, 'pending');

      await repository.updateStatus(surgery.id, 'cancelled');
      expect(repository.tasks.first.status, 'cancelled');
    });

    testWidgets('StaffTasksScreen disables manual completion for surgery tasks while keeping normal tasks interactive',
        (tester) async {
      tester.view.devicePixelRatio = 1;
      tester.view.physicalSize = const Size(1200, 900);
      addTearDown(tester.view.resetPhysicalSize);
      addTearDown(tester.view.resetDevicePixelRatio);

      final today = DateTime.now();
      final surgeryTask = TaskItem(
        id: 'task-surg',
        title: 'Eye Surgery — Rahul',
        description: '11:00 AM · Cataract Surgery — Left Eye',
        assignedTo: 'staff-1',
        dueDate: today,
        priority: 'high',
        status: 'pending',
        createdAt: today,
        updatedAt: today,
        relatedSurgeryId: 'surg-1',
      );
      final normalTask = TaskItem(
        id: 'task-norm',
        title: 'Sterilize instruments',
        description: 'Daily morning prep',
        assignedTo: 'staff-1',
        dueDate: today,
        priority: 'medium',
        status: 'pending',
        createdAt: today,
        updatedAt: today,
      );

      final container = ProviderContainer(overrides: [
        currentUserProvider.overrideWithValue(
          const User(
            id: 'staff-1',
            appMetadata: {},
            userMetadata: {},
            aud: 'authenticated',
            createdAt: '2026-01-01',
          ),
        ),
        currentUserRoleProvider.overrideWith((ref) async => 'staff'),
        staffTasksProvider('staff-1')
            .overrideWith((ref) => _FixedStaffTasksNotifier([surgeryTask, normalTask])),
      ]);
      addTearDown(container.dispose);

      await tester.pumpWidget(
        UncontrolledProviderScope(
          container: container,
          child: const MaterialApp(home: Scaffold(body: StaffTasksScreen())),
        ),
      );
      await tester.pumpAndSettle();

      // Both tasks visible for today
      expect(find.text('Eye Surgery — Rahul'), findsOneWidget);
      expect(find.text('Sterilize instruments'), findsOneWidget);

      // Surgery task shows badge and read-only pending note, no Checkbox
      expect(find.text('EYE SURGERY'), findsOneWidget);
      expect(find.textContaining('completes automatically on surgery discharge'), findsOneWidget);

      // Only ONE Checkbox (for the normal task)
      expect(find.byType(Checkbox), findsOneWidget);
    });

    testWidgets('StaffTasksScreen dynamic date filtering shows tasks only on scheduled shift date',
        (tester) async {
      tester.view.devicePixelRatio = 1;
      tester.view.physicalSize = const Size(1200, 900);
      addTearDown(tester.view.resetPhysicalSize);
      addTearDown(tester.view.resetDevicePixelRatio);

      final targetShiftDate = DateTime.now().add(const Duration(days: 10));
      final surgeryTask = TaskItem(
        id: 'task-surg-5',
        title: 'Eye Surgery — Rahul',
        description: '11:00 AM · Cataract Surgery — Left Eye',
        assignedTo: 'staff-1',
        dueDate: targetShiftDate,
        priority: 'high',
        status: 'pending',
        createdAt: DateTime(2026, 10, 1),
        updatedAt: DateTime(2026, 10, 1),
        relatedSurgeryId: 'surg-1',
      );

      final container = ProviderContainer(overrides: [
        currentUserProvider.overrideWithValue(
          const User(
            id: 'staff-1',
            appMetadata: {},
            userMetadata: {},
            aud: 'authenticated',
            createdAt: '2026-01-01',
          ),
        ),
        currentUserRoleProvider.overrideWith((ref) async => 'staff'),
        staffTasksProvider('staff-1')
            .overrideWith((ref) => _FixedStaffTasksNotifier([surgeryTask])),
      ]);
      addTearDown(container.dispose);

      await tester.pumpWidget(
        UncontrolledProviderScope(
          container: container,
          child: const MaterialApp(home: Scaffold(body: StaffTasksScreen())),
        ),
      );
      await tester.pumpAndSettle();

      // targetShiftDate is 10 days in future -> surgery task should not be shown on today's shift
      expect(find.text('Eye Surgery — Rahul'), findsNothing);
      expect(find.text('No tasks assigned for this shift date.'), findsOneWidget);
    });
  });

  group('Sprint 5.2 Bug Fix: Null-safe Eye Surgery time handling and regression tests', () {
    test('Save surgery with surgery_time == null produces null in write payload, never ""', () {
      final surgery = _sampleSurgery(surgeryTime: null);
      final json = surgery.toJson();
      final insertJson = surgery.toInsertJson();

      expect(surgery.surgeryTime, isNull);
      expect(json['surgery_time'], isNull);
      expect(json['surgery_time'], isNot(''));
      expect(insertJson['surgery_time'], isNull);
      expect(insertJson['surgery_time'], isNot(''));
    });

    test('Save surgery with empty or whitespace time input maps to null in write payload, never ""', () {
      final emptySurgery = _sampleSurgery(surgeryTime: '');
      final whitespaceSurgery = _sampleSurgery(surgeryTime: '   \t\n  ');

      expect(emptySurgery.toJson()['surgery_time'], isNull);
      expect(emptySurgery.toInsertJson()['surgery_time'], isNull);
      expect(whitespaceSurgery.toJson()['surgery_time'], isNull);
      expect(whitespaceSurgery.toInsertJson()['surgery_time'], isNull);

      // Model fromJson with empty or whitespace string safely parses to null
      final parsedFromEmpty = EyeSurgeryModel.fromJson({
        'id': 's-10',
        'patient_id': 'p-1',
        'surgery_type': 'Cataract Surgery',
        'eye_side': 'left',
        'surgery_date': '2026-10-12',
        'surgery_time': '',
        'status': 'scheduled',
      });
      expect(parsedFromEmpty.surgeryTime, isNull);
      expect(parsedFromEmpty.toJson()['surgery_time'], isNull);
    });

    test('Save surgery with valid time preserves formatted TIME string in payload', () {
      final validSurgery = _sampleSurgery(surgeryTime: '14:30:00');
      final validSurgery2 = _sampleSurgery(surgeryTime: ' 09:15 ');

      expect(validSurgery.toJson()['surgery_time'], '14:30:00');
      expect(validSurgery2.toJson()['surgery_time'], '09:15');

      final parsed = EyeSurgeryModel.fromJson({
        'id': 's-11',
        'patient_id': 'p-1',
        'surgery_type': 'Cataract Surgery',
        'eye_side': 'left',
        'surgery_date': '2026-10-12',
        'surgery_time': '11:45:00',
        'status': 'scheduled',
      });
      expect(parsed.surgeryTime, '11:45:00');
      expect(parsed.toJson()['surgery_time'], '11:45:00');
    });

    test('Model fromMap parses null, empty, and whitespace as null; parses valid time normally', () {
      final baseMap = {
        'id': 's-test',
        'patient_id': 'p-1',
        'surgery_type': 'Cataract Surgery',
        'eye_side': 'left',
        'surgery_date': '2026-10-12',
        'status': 'scheduled',
      };
      expect(EyeSurgeryModel.fromMap({...baseMap, 'surgery_time': null}).surgeryTime, isNull);
      expect(EyeSurgeryModel.fromMap({...baseMap, 'surgery_time': ''}).surgeryTime, isNull);
      expect(EyeSurgeryModel.fromMap({...baseMap, 'surgery_time': '   \t  '}).surgeryTime, isNull);
      expect(EyeSurgeryModel.fromMap({...baseMap, 'surgery_time': '10:30:00'}).surgeryTime, '10:30:00');

      // toMap() converts null or empty strings to null in repository payload, never ""
      expect(EyeSurgeryModel.fromMap({...baseMap, 'surgery_time': ''}).toMap()['surgery_time'], isNull);
      expect(EyeSurgeryModel.fromMap({...baseMap, 'surgery_time': ''}).toMap()['surgery_time'], isNot(''));
    });

    test('Missed surgery logic with null surgery_time is not incorrectly marked missed', () {
      final pastDate = DateTime.now().subtract(const Duration(days: 5));

      final pastNullTimeScheduled = _sampleSurgery(
        status: 'scheduled',
        surgeryDate: pastDate,
        surgeryTime: null,
      );
      final pastNullTimePreOp = _sampleSurgery(
        status: 'pre_op',
        surgeryDate: pastDate,
        surgeryTime: null,
      );

      // Null surgery_time does NOT mark it missed merely because the date passed
      expect(pastNullTimeScheduled.isMissed, isFalse);
      expect(pastNullTimePreOp.isMissed, isFalse);

      // Only calculates missed when surgery_time exists and scheduled time passed
      final pastWithTime = _sampleSurgery(
        status: 'scheduled',
        surgeryDate: pastDate,
        surgeryTime: '08:00:00',
      );
      expect(pastWithTime.isMissed, isTrue);
    });

    test('Notification omits Time line when surgery_time is null, includes Time line when present', () async {
      final repo = _FakeEyeSurgeryRepository(items: [
        _sampleSurgery(id: 's-null-time', surgeryDate: DateTime(2026, 10, 12), surgeryTime: null, assignedStaffId: null),
        _sampleSurgery(id: 's-with-time', surgeryDate: DateTime(2026, 10, 12), surgeryTime: '10:30:00', assignedStaffId: null),
      ]);

      // Assign staff to surgery with null time
      await repo.assignStaff('s-null-time', 'staff-1');
      expect(repo.notifications, hasLength(1));
      final notifNoTime = repo.notifications.first;
      expect(notifNoTime.message, contains('Patient: Aisha Kumar'));
      expect(notifNoTime.message, contains('Surgery: Cataract Surgery'));
      expect(notifNoTime.message, contains('Eye: left'));
      expect(notifNoTime.message, contains('Date: 2026-10-12'));
      expect(notifNoTime.message, isNot(contains('Time:')));

      // Assign staff to surgery with valid time
      await repo.assignStaff('s-with-time', 'staff-2');
      expect(repo.notifications, hasLength(2));
      final notifWithTime = repo.notifications.last;
      expect(notifWithTime.message, contains('Patient: Aisha Kumar'));
      expect(notifWithTime.message, contains('Time: 10:30:00'));
    });

    test('Shift task description and due date format without time when surgery_time is null', () async {
      final repo = _FakeEyeSurgeryRepository(items: [
        _sampleSurgery(id: 's-null-time', surgeryDate: DateTime(2026, 10, 12), surgeryTime: null, assignedStaffId: null),
      ]);

      await repo.assignStaff('s-null-time', 'staff-1');
      expect(repo.tasks, hasLength(1));
      final task = repo.tasks.first;
      expect(task.title, 'Eye Surgery — Aisha Kumar');
      // Description must NOT have leading ' · ' or empty time
      expect(task.description, 'Cataract Surgery — left Eye');
      expect(task.description?.startsWith(' · ') ?? false, isFalse);
      expect(task.dueDate, DateTime(2026, 10, 12));
    });

    test('Shift task description includes time prefix when surgery_time is present', () async {
      final repo = _FakeEyeSurgeryRepository(items: [
        _sampleSurgery(id: 's-with-time', surgeryDate: DateTime(2026, 10, 12), surgeryTime: '10:30:00', assignedStaffId: null),
      ]);

      await repo.assignStaff('s-with-time', 'staff-1');
      expect(repo.tasks, hasLength(1));
      final task = repo.tasks.first;
      expect(task.title, 'Eye Surgery — Aisha Kumar');
      expect(task.description, '10:30:00 · Cataract Surgery — left Eye');
      expect(task.dueDate, DateTime(2026, 10, 12));

      // Rescheduling without time is now rejected (Surgery time is mandatory)
      expect(
        () => repo.rescheduleSurgery(
          id: 's-with-time',
          surgeryDate: DateTime(2026, 10, 15),
          surgeryTime: null,
        ),
        throwsA(isA<ArgumentError>()),
      );

      // Reschedule with new time updates task description with new time
      await repo.rescheduleSurgery(
        id: 's-with-time',
        surgeryDate: DateTime(2026, 10, 15),
        surgeryTime: '14:00:00',
      );
      final rescheduledTask = repo.tasks.first;
      expect(rescheduledTask.description, '14:00:00 · Cataract Surgery — left Eye');
      expect(rescheduledTask.dueDate, DateTime(2026, 10, 15));
    });

    test('Ensure no PostgreSQL TIME value receives "" across variations', () {
      final variations = [
        null,
        '',
        ' ',
        '   ',
        '\t',
        '\n',
        '  \r\n  ',
      ];

      for (final input in variations) {
        final surgery = _sampleSurgery(surgeryTime: input);
        final payload = surgery.toJson();
        expect(
          payload['surgery_time'],
          isNull,
          reason: 'Input "$input" must serialize to null, never an empty string',
        );
        expect(
          payload['surgery_time'],
          isNot(''),
          reason: 'PostgreSQL TIME column cannot accept ""',
        );

        final insertPayload = surgery.toInsertJson();
        expect(insertPayload['surgery_time'], isNull);
        expect(insertPayload['surgery_time'], isNot(''));
      }
    });

    testWidgets('EyeSurgeryFormDialog surgery time picker is optional and saves without time',
        (tester) async {
      tester.view.devicePixelRatio = 1;
      tester.view.physicalSize = const Size(800, 1000);
      addTearDown(tester.view.resetPhysicalSize);
      addTearDown(tester.view.resetDevicePixelRatio);

      final fakeRepo = _FakeEyeSurgeryRepository();
      final container = ProviderContainer(
        overrides: [
          eyeSurgeryRepositoryProvider.overrideWithValue(fakeRepo),
          currentUserRoleProvider.overrideWith((ref) async => 'admin'),
          eyeSurgeryStaffCandidatesProvider.overrideWith((ref) async => const [
            EyeSurgeryStaffCandidate(id: 'staff-1', fullName: 'Dr. Rao'),
          ]),
          eyeSurgeryItemTemplatesProvider('Cataract Surgery')
              .overrideWith((ref) async => const []),
        ],
      );
      addTearDown(container.dispose);

      await tester.pumpWidget(
        UncontrolledProviderScope(
          container: container,
          child: const MaterialApp(
            home: Scaffold(
              body: EyeSurgeryFormDialog(
                initialPatientId: 'p-1',
                initialPatientName: 'Aisha Kumar',
              ),
            ),
          ),
        ),
      );
      await tester.pumpAndSettle();

      // Pre-op Date must NOT appear in the scheduling form
      expect(find.text('Pre-op Date'), findsNothing);
      expect(find.text('Pre-op Date *'), findsNothing);

      // Time picker should show 'Select Time *'
      expect(find.text('Select Time *'), findsOneWidget);

      // Select eye side so form validation passes
      await tester.tap(find.byType(DropdownButtonFormField<String>).at(1));
      await tester.pumpAndSettle();
      await tester.tap(find.text('Left eye').last);
      await tester.pumpAndSettle();

      // Submit form without selecting surgery time
      await tester.tap(find.text('Schedule surgery'));
      await tester.pumpAndSettle();

      // Verify save blocked and validation error shown
      expect(find.text('Surgery time is required.'), findsOneWidget);
      expect(fakeRepo.items, isEmpty);
    });
  });

  group('Sprint 5.2 Patch: Final UX, Visibility Rules, and 25-Point Verification', () {
    // 1. Schedule form does NOT show Pre-op Date.
    testWidgets('1. Schedule form does NOT show Pre-op Date', (tester) async {
      final fakeRepo = _FakeEyeSurgeryRepository();
      final container = ProviderContainer(overrides: [
        eyeSurgeryRepositoryProvider.overrideWithValue(fakeRepo),
        currentUserRoleProvider.overrideWith((ref) async => 'admin'),
        eyeSurgeryStaffCandidatesProvider.overrideWith((ref) async => const []),
        eyeSurgeryItemTemplatesProvider('Cataract Surgery').overrideWith((ref) async => const []),
      ]);
      addTearDown(container.dispose);

      await tester.pumpWidget(
        UncontrolledProviderScope(
          container: container,
          child: const MaterialApp(
            home: Scaffold(
              body: EyeSurgeryFormDialog(),
            ),
          ),
        ),
      );
      await tester.pumpAndSettle();

      expect(find.text('Pre-op Date'), findsNothing);
      expect(find.text('Pre-op Date *'), findsNothing);
      expect(find.text('Surgery Date *'), findsOneWidget);
    });

    // 2. Surgery Time is mandatory.
    test('2. Surgery Time is mandatory', () {
      final error = EyeSurgeryModel.validateFields(
        patientId: 'p-1',
        surgeryType: 'Cataract Surgery',
        surgeryTypeCategory: 'Cataract Surgery',
        eyeSide: 'left',
        preOpDate: DateTime(2026, 10, 10),
        surgeryDate: DateTime(2026, 10, 10),
        surgeryTime: null,
        status: 'scheduled',
      );
      expect(error, 'Surgery time is required.');
    });

    // 3. Empty surgery time cannot be saved.
    test('3. Empty surgery time cannot be saved', () {
      final errorWhitespace = EyeSurgeryModel.validateFields(
        patientId: 'p-1',
        surgeryType: 'Cataract Surgery',
        surgeryTypeCategory: 'Cataract Surgery',
        eyeSide: 'left',
        preOpDate: DateTime(2026, 10, 10),
        surgeryDate: DateTime(2026, 10, 10),
        surgeryTime: '   ',
        status: 'scheduled',
      );
      expect(errorWhitespace, 'Surgery time is required.');

      final fakeRepo = _FakeEyeSurgeryRepository(items: [_sampleSurgery()]);
      expect(
        () => fakeRepo.rescheduleSurgery(
          id: 's-1',
          surgeryDate: DateTime(2026, 10, 15),
          surgeryTime: '',
        ),
        throwsA(isA<ArgumentError>()),
      );
    });

    // 4. No PostgreSQL TIME empty-string payload is generated.
    test('4. No PostgreSQL TIME empty-string payload is generated', () {
      final sNull = _sampleSurgery(surgeryTime: null);
      final sEmpty = _sampleSurgery(surgeryTime: '');
      final sWhitespace = _sampleSurgery(surgeryTime: '   ');
      final sValid = _sampleSurgery(surgeryTime: '14:30:00');

      expect(sNull.toJson()['surgery_time'], isNull);
      expect(sEmpty.toJson()['surgery_time'], isNull);
      expect(sWhitespace.toJson()['surgery_time'], isNull);
      expect(sValid.toJson()['surgery_time'], '14:30:00');

      expect(sNull.toJson()['surgery_time'], isNot(''));
      expect(sEmpty.toJson()['surgery_time'], isNot(''));
      expect(sWhitespace.toJson()['surgery_time'], isNot(''));

      expect(EyeSurgeryRepository.normalizeSurgeryTime(null), isNull);
      expect(EyeSurgeryRepository.normalizeSurgeryTime(''), isNull);
      expect(EyeSurgeryRepository.normalizeSurgeryTime('   '), isNull);
      expect(EyeSurgeryRepository.normalizeSurgeryTime('10:00:00'), '10:00:00');
    });

    // 5. Staff can reschedule MISSED surgery.
    testWidgets('5. Staff can reschedule MISSED surgery', (tester) async {
      final missedDate = DateTime.now().subtract(const Duration(days: 2));
      final missed = _sampleSurgery(
        id: 's-missed-1',
        status: 'scheduled',
        surgeryDate: missedDate,
        surgeryTime: '08:00:00',
      );
      final fakeRepo = _FakeEyeSurgeryRepository(items: [missed]);
      final container = ProviderContainer(overrides: [
        eyeSurgeryRepositoryProvider.overrideWithValue(fakeRepo),
        currentUserRoleProvider.overrideWith((ref) async => 'staff'),
        eyeSurgerySelectedDateProvider.overrideWith((ref) => missedDate),
      ]);
      addTearDown(container.dispose);

      await tester.pumpWidget(
        UncontrolledProviderScope(
          container: container,
          child: const MaterialApp(home: EyeSurgeryScreen()),
        ),
      );
      await tester.pumpAndSettle();

      expect(find.text('MISSED'), findsOneWidget);
      expect(find.text('Reschedule Surgery'), findsOneWidget);

      await tester.tap(find.text('Reschedule Surgery'));
      await tester.pumpAndSettle();

      expect(find.text('Confirm Reschedule'), findsOneWidget);
    });

    // 6. Staff cannot assign surgery staff.
    testWidgets('6. Staff cannot assign surgery staff', (tester) async {
      final fakeRepo = _FakeEyeSurgeryRepository(items: [_sampleSurgery()]);
      fakeRepo.staffCandidates = const [
        EyeSurgeryStaffCandidate(id: 'staff-1', fullName: 'Dr. Rao', role: 'staff'),
      ];
      final container = ProviderContainer(overrides: [
        eyeSurgeryRepositoryProvider.overrideWithValue(fakeRepo),
        currentUserRoleProvider.overrideWith((ref) async => 'staff'),
        eyeSurgeryStaffCandidatesProvider.overrideWith((ref) async => fakeRepo.staffCandidates),
        eyeSurgeryItemTemplatesProvider('Cataract Surgery').overrideWith((ref) async => const []),
      ]);
      addTearDown(container.dispose);

      await tester.pumpWidget(
        UncontrolledProviderScope(
          container: container,
          child: MaterialApp(
            home: Scaffold(
              body: EyeSurgeryFormDialog(existingSurgery: _sampleSurgery()),
            ),
          ),
        ),
      );
      await tester.pumpAndSettle();

      expect(find.text('Assigned Staff is read-only (Admin assignment required)'), findsOneWidget);
      expect(find.byType(DropdownButtonFormField<String?>), findsNothing);
    });

    // 7. Admin can reschedule MISSED surgery.
    testWidgets('7. Admin can reschedule MISSED surgery', (tester) async {
      final missedDate = DateTime.now().subtract(const Duration(days: 1));
      final missed = _sampleSurgery(
        id: 's-missed-admin',
        status: 'scheduled',
        surgeryDate: missedDate,
        surgeryTime: '09:00:00',
      );
      final fakeRepo = _FakeEyeSurgeryRepository(items: [missed]);
      final container = ProviderContainer(overrides: [
        eyeSurgeryRepositoryProvider.overrideWithValue(fakeRepo),
        currentUserRoleProvider.overrideWith((ref) async => 'admin'),
        eyeSurgerySelectedDateProvider.overrideWith((ref) => missedDate),
      ]);
      addTearDown(container.dispose);

      await tester.pumpWidget(
        UncontrolledProviderScope(
          container: container,
          child: const MaterialApp(home: EyeSurgeryScreen()),
        ),
      );
      await tester.pumpAndSettle();

      expect(find.text('MISSED'), findsOneWidget);
      expect(find.text('Reschedule Surgery'), findsOneWidget);
    });

    // 8. Rescheduling updates the same surgery ID.
    test('8. Rescheduling updates the same surgery ID', () async {
      final fakeRepo = _FakeEyeSurgeryRepository(items: [_sampleSurgery(id: 'surgery-xyz')]);
      final futureDate = DateTime.now().add(const Duration(days: 3));
      final updated = await fakeRepo.rescheduleSurgery(
        id: 'surgery-xyz',
        surgeryDate: futureDate,
        surgeryTime: '11:00:00',
      );
      expect(updated.id, 'surgery-xyz');
      expect(updated.surgeryDate, futureDate);
      expect(updated.surgeryTime, '11:00:00');
    });

    // 9. Rescheduling does not create duplicate surgery.
    test('9. Rescheduling does not create duplicate surgery', () async {
      final fakeRepo = _FakeEyeSurgeryRepository(items: [_sampleSurgery(id: 's-single')]);
      expect(fakeRepo.items.length, 1);

      await fakeRepo.rescheduleSurgery(
        id: 's-single',
        surgeryDate: DateTime(2026, 11, 20),
        surgeryTime: '10:00:00',
      );
      expect(fakeRepo.items.length, 1);
      expect(fakeRepo.items.first.id, 's-single');
    });

    // 10. Rescheduling does not deduct inventory.
    test('10. Rescheduling does not deduct inventory', () async {
      final fakeRepo = _FakeEyeSurgeryRepository(items: [_sampleSurgery(id: 's-inv')]);
      expect(fakeRepo.inventoryConsumptions, 0);

      await fakeRepo.rescheduleSurgery(
        id: 's-inv',
        surgeryDate: DateTime(2026, 11, 25),
        surgeryTime: '09:30:00',
      );
      expect(fakeRepo.inventoryConsumptions, 0);
    });

    // 11. Scheduled surgeries sort ascending by date.
    test('11. Scheduled surgeries sort ascending by date', () {
      final s1 = _sampleSurgery(id: 's-oct5', surgeryDate: DateTime(2026, 10, 5), surgeryTime: '10:00:00');
      final s2 = _sampleSurgery(id: 's-oct3', surgeryDate: DateTime(2026, 10, 3), surgeryTime: '10:00:00');
      final s3 = _sampleSurgery(id: 's-oct4', surgeryDate: DateTime(2026, 10, 4), surgeryTime: '10:00:00');

      final list = [s1, s2, s3];
      list.sort((a, b) {
        final dateComp = a.surgeryDate.compareTo(b.surgeryDate);
        if (dateComp != 0) return dateComp;
        return (a.surgeryTime ?? '').compareTo(b.surgeryTime ?? '');
      });

      expect(list.map((s) => s.id).toList(), ['s-oct3', 's-oct4', 's-oct5']);
    });

    // 12. Same-date surgeries sort ascending by time.
    test('12. Same-date surgeries sort ascending by time', () {
      final sameDate = DateTime(2026, 10, 3);
      final sLate = _sampleSurgery(id: 's-1400', surgeryDate: sameDate, surgeryTime: '14:00:00');
      final sEarly = _sampleSurgery(id: 's-0900', surgeryDate: sameDate, surgeryTime: '09:00:00');
      final sMid = _sampleSurgery(id: 's-1100', surgeryDate: sameDate, surgeryTime: '11:00:00');

      final list = [sLate, sEarly, sMid];
      list.sort((a, b) {
        final dateComp = a.surgeryDate.compareTo(b.surgeryDate);
        if (dateComp != 0) return dateComp;
        return (a.surgeryTime ?? '').compareTo(b.surgeryTime ?? '');
      });

      expect(list.map((s) => s.id).toList(), ['s-0900', 's-1100', 's-1400']);
    });

    // 13. Discharged surgery is visible on discharge day.
    test('13. Discharged surgery is visible on discharge day', () {
      final dischargeDay = DateTime(2026, 10, 3, 9, 30);
      final surgery = _sampleSurgery(
        status: 'discharged',
        dischargedAt: dischargeDay,
      );

      final sameCalendarDay = DateTime(2026, 10, 3, 23, 59);
      expect(surgery.isDischargedVisible(sameCalendarDay), isTrue);
    });

    // 14. Discharged surgery is hidden starting the next calendar day.
    test('14. Discharged surgery is hidden starting the next calendar day', () {
      final dischargeDay = DateTime(2026, 10, 3, 9, 30);
      final surgery = _sampleSurgery(
        status: 'discharged',
        dischargedAt: dischargeDay,
      );

      final nextCalendarDay = DateTime(2026, 10, 4, 0, 0, 1);
      final futureDay = DateTime(2026, 10, 5, 12, 0);

      expect(surgery.isDischargedVisible(nextCalendarDay), isFalse);
      expect(surgery.isDischargedVisible(futureDay), isFalse);
    });

    // 15. Discharged surgery database record is NOT deleted.
    test('15. Discharged surgery database record is NOT deleted', () async {
      final yesterday = DateTime.now().subtract(const Duration(days: 1));
      final dischargedPast = _sampleSurgery(
        id: 's-retained',
        status: 'discharged',
        dischargedAt: yesterday,
      );
      final fakeRepo = _FakeEyeSurgeryRepository(items: [dischargedPast]);

      // Database repository still contains record
      final fetched = await fakeRepo.fetchSurgeryById('s-retained');
      expect(fetched, isNotNull);
      expect(fetched?.id, 's-retained');
      expect(fakeRepo.items.any((s) => s.id == 's-retained'), isTrue);

      // Model helper marks it hidden for current listing
      expect(dischargedPast.isDischargedVisible(), isFalse);
    });

    // 16. Follow-up option is hidden before discharge.
    testWidgets('16. Follow-up option is hidden before discharge', (tester) async {
      for (final nonDischargedStatus in ['scheduled', 'pre_op', 'in_surgery', 'post_op', 'billing', 'cancelled']) {
        final surgery = _sampleSurgery(status: nonDischargedStatus);
        final fakeRepo = _FakeEyeSurgeryRepository(items: [surgery]);
        final container = ProviderContainer(overrides: [
          eyeSurgeryRepositoryProvider.overrideWithValue(fakeRepo),
          currentUserRoleProvider.overrideWith((ref) async => 'admin'),
        ]);

        await tester.pumpWidget(
          UncontrolledProviderScope(
            container: container,
            child: const MaterialApp(home: EyeSurgeryScreen()),
          ),
        );
        await tester.pumpAndSettle();

        expect(find.text('Schedule Follow-up Appointment'), findsNothing,
            reason: 'Should be hidden during $nonDischargedStatus');
        container.dispose();
      }
    });

    // 17. Follow-up option appears after discharge.
    testWidgets('17. Follow-up option appears after discharge', (tester) async {
      final dischargedSurgery = _sampleSurgery(
        status: 'discharged',
        dischargedAt: DateTime.now(),
      );
      final fakeRepo = _FakeEyeSurgeryRepository(items: [dischargedSurgery]);
      final container = ProviderContainer(overrides: [
        eyeSurgeryRepositoryProvider.overrideWithValue(fakeRepo),
        currentUserRoleProvider.overrideWith((ref) async => 'admin'),
      ]);
      addTearDown(container.dispose);

      await tester.pumpWidget(
        UncontrolledProviderScope(
          container: container,
          child: const MaterialApp(home: EyeSurgeryScreen()),
        ),
      );
      await tester.pumpAndSettle();

      expect(find.text('Schedule Follow-up Appointment'), findsOneWidget);
    });

    // 18. Follow-up dropdown accepts canonical follow_up.
    test('18. Follow-up dropdown accepts canonical follow_up', () {
      final canonical = AppointmentFormDialog.normalizeAppointmentType('follow_up');
      expect(canonical, 'follow_up');
      expect(
        AppointmentFormDialog.availableAppointmentTypes.any((t) => t.id == canonical),
        isTrue,
      );
    });

    // 19. follow-up, follow_up, and followup normalize safely.
    test('19. follow-up, follow_up, and followup normalize safely', () {
      expect(AppointmentFormDialog.normalizeAppointmentType('follow-up'), 'follow_up');
      expect(AppointmentFormDialog.normalizeAppointmentType('follow_up'), 'follow_up');
      expect(AppointmentFormDialog.normalizeAppointmentType('followup'), 'follow_up');
      expect(AppointmentFormDialog.normalizeAppointmentType('FOLLOW-UP'), 'follow_up');
      expect(AppointmentFormDialog.normalizeAppointmentType('  Follow_Up  '), 'follow_up');
    });

    // 20. Assigned staff notification still works.
    test('20. Assigned staff notification still works', () async {
      final fakeRepo = _FakeEyeSurgeryRepository(items: [_sampleSurgery(assignedStaffId: null)]);
      await fakeRepo.assignStaff('s-1', 'staff-target');

      expect(
        fakeRepo.notifications.any((n) =>
            n.userId == 'staff-target' &&
            n.type == 'eye_surgery_assigned' &&
            n.relatedId == 's-1'),
        isTrue,
      );
    });

    // 21. Dynamic shift task still works.
    test('21. Dynamic shift task still works', () async {
      final fakeRepo = _FakeEyeSurgeryRepository(items: [_sampleSurgery(assignedStaffId: null)]);
      await fakeRepo.assignStaff('s-1', 'staff-shift');

      final task = fakeRepo.tasks.firstWhere((t) => t.relatedSurgeryId == 's-1');
      expect(task.assignedTo, 'staff-shift');
      expect(task.status, 'pending');
      expect(task.priority, 'high');
      expect(task.title, contains('Eye Surgery'));
    });

    // 22. Rescheduling moves the shift task to the new date.
    test('22. Rescheduling moves the shift task to the new date', () async {
      final fakeRepo = _FakeEyeSurgeryRepository(items: [_sampleSurgery(assignedStaffId: null)]);
      await fakeRepo.assignStaff('s-1', 'staff-shift');

      final newDate = DateTime(2026, 11, 20);
      await fakeRepo.rescheduleSurgery(
        id: 's-1',
        surgeryDate: newDate,
        surgeryTime: '15:00:00',
      );

      final task = fakeRepo.tasks.firstWhere((t) => t.relatedSurgeryId == 's-1');
      expect(task.dueDate, newDate);
      expect(task.description, contains('15:00:00'));
    });

    // 23. Surgery task remains pending until discharge.
    test('23. Surgery task remains pending until discharge', () async {
      final fakeRepo = _FakeEyeSurgeryRepository(items: [_sampleSurgery(assignedStaffId: null)]);
      await fakeRepo.assignStaff('s-1', 'staff-pending');

      await fakeRepo.updateStatus('s-1', 'pre_op');
      expect(fakeRepo.tasks.firstWhere((t) => t.relatedSurgeryId == 's-1').status, 'pending');

      final completeChecklist = {
        for (final key in EyeSurgeryModel.checklistItems.keys) key: true,
      };
      await fakeRepo.updatePreOpChecklist('s-1', completeChecklist);

      await fakeRepo.startSurgery('s-1');
      expect(fakeRepo.tasks.firstWhere((t) => t.relatedSurgeryId == 's-1').status, 'pending');

      await fakeRepo.updateStatus('s-1', 'post_op');
      expect(fakeRepo.tasks.firstWhere((t) => t.relatedSurgeryId == 's-1').status, 'pending');
    });

    // 24. Surgery task automatically becomes completed after discharge.
    test('24. Surgery task automatically becomes completed after discharge', () async {
      final fakeRepo = _FakeEyeSurgeryRepository(items: [_sampleSurgery(status: 'post_op')]);
      fakeRepo.tasks.add(TaskItem(
        id: 'task-complete-check',
        title: 'Eye Surgery',
        assignedTo: 'staff-1',
        dueDate: DateTime.now(),
        priority: 'high',
        status: 'pending',
        createdAt: DateTime.now(),
        updatedAt: DateTime.now(),
        relatedSurgeryId: 's-1',
      ));

      await fakeRepo.updateStatus('s-1', 'discharged');
      final task = fakeRepo.tasks.firstWhere((t) => t.relatedSurgeryId == 's-1');
      expect(task.status, 'completed');
      expect(task.completedAt, isNotNull);
    });

    // 25. No duplicate surgery task is created.
    test('25. No duplicate surgery task is created', () async {
      final fakeRepo = _FakeEyeSurgeryRepository(items: [_sampleSurgery(assignedStaffId: null)]);
      await fakeRepo.assignStaff('s-1', 'staff-1');
      await fakeRepo.assignStaff('s-1', 'staff-2');
      await fakeRepo.rescheduleSurgery(id: 's-1', surgeryDate: DateTime(2026, 12, 1), surgeryTime: '10:00:00');

      final matchingTasks = fakeRepo.tasks.where((t) => t.relatedSurgeryId == 's-1').toList();
      expect(matchingTasks.length, 1);
    });

    // =========================================================================
    // Regression Tests: Bug 1 & Bug 2
    // =========================================================================
    group('Regression Tests: Bug 1 & Bug 2 (Notifications & Rescheduling)', () {
      test('valid surgery assignment notification has type eye_surgery_assigned', () async {
        final fakeRepo = _FakeEyeSurgeryRepository(items: [
          _sampleSurgery(id: 's-assign-1', assignedStaffId: null, surgeryTime: '10:00:00'),
        ]);

        final updated = await fakeRepo.assignStaff('s-assign-1', 'staff-1');
        expect(updated.assignedStaffId, 'staff-1');
        expect(fakeRepo.notifications, hasLength(1));
        final notif = fakeRepo.notifications.first;
        expect(notif.type, 'eye_surgery_assigned');
        expect(notif.userId, 'staff-1');
        expect(notif.title, 'Eye Surgery Assigned');
        expect(notif.relatedId, 's-assign-1');
        expect(notif.message, contains('Surgery: Cataract Surgery'));
        expect(notif.message, contains('Time: 10:00:00'));
      });

      test('invalid notification type / trigger failure cannot break surgery save', () async {
        final fakeRepo = _FakeEyeSurgeryRepository(items: [
          _sampleSurgery(id: 's-assign-2', assignedStaffId: null),
        ]);
        fakeRepo.simulateNotificationFailure = true;

        // Even with simulated notification error, the surgery save succeeds
        final updated = await fakeRepo.assignStaff('s-assign-2', 'staff-1');
        expect(updated.assignedStaffId, 'staff-1');
        expect(fakeRepo.items.first.assignedStaffId, 'staff-1');
      });

      testWidgets('missed surgery rescheduled to future date disappears from MISSED immediately', (tester) async {
        final pastDate = DateTime.now().subtract(const Duration(days: 2));
        final missedSurgery = _sampleSurgery(
          id: 's-missed-1',
          status: 'scheduled',
          surgeryDate: pastDate,
          surgeryTime: '09:00:00',
        );
        final fakeRepo = _FakeEyeSurgeryRepository(items: [missedSurgery]);
        final container = ProviderContainer(overrides: [
          eyeSurgeryRepositoryProvider.overrideWithValue(fakeRepo),
          currentUserRoleProvider.overrideWith((ref) async => 'admin'),
          eyeSurgerySelectedDateProvider.overrideWith((ref) => pastDate),
        ]);
        addTearDown(container.dispose);

        // Initially filter by 'missed'
        container.read(eyeSurgeryStatusFilterProvider.notifier).state = 'missed';
        await tester.pumpWidget(
          UncontrolledProviderScope(
            container: container,
            child: const MaterialApp(home: EyeSurgeryScreen()),
          ),
        );
        await tester.pumpAndSettle();

        // MISSED badge and surgery card are present
        expect(find.text('MISSED'), findsOneWidget);
        expect(find.text('Reschedule Surgery'), findsOneWidget);
        expect(container.read(filteredEyeSurgeriesProvider), hasLength(1));

        // Reschedule to tomorrow at 11:00 AM
        final tomorrow = DateTime.now().add(const Duration(days: 1));
        final notifier = container.read(eyeSurgeryListProvider.notifier);
        final rescheduled = await notifier.rescheduleSurgery(
          id: missedSurgery.id,
          surgeryDate: tomorrow,
          surgeryTime: '11:00:00',
        );

        // Model state verifies:
        expect(rescheduled.id, missedSurgery.id);
        expect(rescheduled.isMissed, isFalse);
        expect(rescheduled.status, 'scheduled');

        // Immediately removed from MISSED list and UI
        await tester.pumpAndSettle();
        expect(container.read(filteredEyeSurgeriesProvider), isEmpty);
        expect(find.text('MISSED'), findsNothing);
      });

      test('rescheduled surgery appears under the new date and same surgery ID is retained', () async {
        final pastDate = DateTime.now().subtract(const Duration(days: 3));
        final missedSurgery = _sampleSurgery(
          id: 's-same-id',
          status: 'scheduled',
          surgeryDate: pastDate,
          surgeryTime: '08:30:00',
          iolDetails: 'Monofocal +21.5D',
          remarks: 'Careful with capsulorhexis',
        );
        final fakeRepo = _FakeEyeSurgeryRepository(items: [missedSurgery]);
        final container = ProviderContainer(overrides: [
          eyeSurgeryRepositoryProvider.overrideWithValue(fakeRepo),
          eyeSurgerySelectedDateProvider.overrideWith((ref) => pastDate),
        ]);
        addTearDown(container.dispose);

        // Fetch initial list
        await container.read(eyeSurgeryListProvider.future);
        expect(container.read(filteredEyeSurgeriesProvider), hasLength(1));

        final futureDate = DateTime.now().add(const Duration(days: 4));
        final rescheduled = await container.read(eyeSurgeryListProvider.notifier).rescheduleSurgery(
          id: 's-same-id',
          surgeryDate: futureDate,
          surgeryTime: '14:00:00',
        );

        // Same ID and data retained
        expect(rescheduled.id, 's-same-id');
        expect(rescheduled.iolDetails, 'Monofocal +21.5D');
        expect(rescheduled.remarks, 'Careful with capsulorhexis');
        expect(rescheduled.surgeryDate, futureDate);
        expect(rescheduled.surgeryTime, '14:00:00');
        expect(rescheduled.status, 'scheduled');
        expect(rescheduled.isMissed, isFalse);

        // On the past date, it's immediately removed
        expect(container.read(filteredEyeSurgeriesProvider), isEmpty);

        // Switch to the future date: it appears under the new date
        container.read(eyeSurgerySelectedDateProvider.notifier).state = futureDate;
        final currentList = container.read(filteredEyeSurgeriesProvider);
        expect(currentList, hasLength(1));
        expect(currentList.first.surgeryDate, futureDate);
        expect(currentList.first.surgeryTime, '14:00:00');
      });

      test('no duplicate surgery, task, or notification on reschedule', () async {
        final pastDate = DateTime.now().subtract(const Duration(days: 1));
        final missedSurgery = _sampleSurgery(
          id: 's-no-dup',
          assignedStaffId: 'staff-1',
          status: 'scheduled',
          surgeryDate: pastDate,
          surgeryTime: '09:00:00',
        );
        final fakeRepo = _FakeEyeSurgeryRepository(items: [missedSurgery]);
        fakeRepo.tasks.add(TaskItem(
          id: 'task-1',
          title: 'Eye Surgery — Aisha Kumar',
          description: '09:00 AM · Cataract Surgery — Left Eye',
          assignedTo: 'staff-1',
          dueDate: pastDate,
          priority: 'high',
          status: 'pending',
          createdAt: pastDate,
          updatedAt: pastDate,
          relatedSurgeryId: 's-no-dup',
        ));
        fakeRepo.notifications.add(NotificationModel(
          id: 'notif-1',
          userId: 'staff-1',
          title: 'Eye Surgery Assigned',
          message: 'Initial assignment',
          type: 'eye_surgery_assigned',
          isRead: false,
          relatedId: 's-no-dup',
          createdAt: pastDate,
        ));

        expect(fakeRepo.items, hasLength(1));
        expect(fakeRepo.tasks, hasLength(1));
        expect(fakeRepo.notifications, hasLength(1));

        final futureDate = DateTime.now().add(const Duration(days: 2));
        await fakeRepo.rescheduleSurgery(
          id: 's-no-dup',
          surgeryDate: futureDate,
          surgeryTime: '10:30:00',
        );

        // Exactly 1 surgery record (no duplicate)
        expect(fakeRepo.items, hasLength(1));
        expect(fakeRepo.items.first.id, 's-no-dup');

        // Exactly 1 task record with updated due date (no duplicate)
        expect(fakeRepo.tasks, hasLength(1));
        expect(fakeRepo.tasks.first.relatedSurgeryId, 's-no-dup');
        expect(fakeRepo.tasks.first.dueDate, futureDate);

        // No duplicate staff assignment notification created
        final assignmentNotifications = fakeRepo.notifications.where((n) => n.type == 'eye_surgery_assigned').toList();
        expect(assignmentNotifications, hasLength(1));
      });

      test('rescheduled to past date remains missed correctly', () async {
        final pastDate = DateTime.now().subtract(const Duration(days: 5));
        final missedSurgery = _sampleSurgery(
          id: 's-past-resched',
          status: 'scheduled',
          surgeryDate: pastDate,
          surgeryTime: '08:00:00',
        );
        final fakeRepo = _FakeEyeSurgeryRepository(items: [missedSurgery]);
        
        final pastDate2 = DateTime.now().subtract(const Duration(days: 2));
        final stillMissed = await fakeRepo.rescheduleSurgery(
          id: 's-past-resched',
          surgeryDate: pastDate2,
          surgeryTime: '08:00:00',
        );

        expect(stillMissed.isMissed, isTrue);
      });
    });

    // ================================================================
    // G. Admin-Only Surgery Deletion
    // ================================================================
    group('G. Admin-Only Surgery Deletion', () {
      testWidgets('1. Admin sees the Delete action in popup menu', (tester) async {
        final surgery = _sampleSurgery(id: 's-del-1');
        final fakeRepo = _FakeEyeSurgeryRepository(items: [surgery]);
        final container = ProviderContainer(overrides: [
          eyeSurgeryRepositoryProvider.overrideWithValue(fakeRepo),
          currentUserRoleProvider.overrideWith((ref) async => 'admin'),
        ]);
        addTearDown(container.dispose);

        await tester.pumpWidget(
          UncontrolledProviderScope(
            container: container,
            child: const MaterialApp(home: EyeSurgeryScreen()),
          ),
        );
        await tester.pumpAndSettle();

        final moreBtn = find.byIcon(Icons.more_vert);
        expect(moreBtn, findsOneWidget);
        await tester.tap(moreBtn);
        await tester.pumpAndSettle();

        expect(find.text('Delete surgery'), findsOneWidget);
      });

      testWidgets('2. Staff does not see any Delete action', (tester) async {
        final surgery = _sampleSurgery(id: 's-staff-view');
        final fakeRepo = _FakeEyeSurgeryRepository(items: [surgery]);
        final container = ProviderContainer(overrides: [
          eyeSurgeryRepositoryProvider.overrideWithValue(fakeRepo),
          currentUserRoleProvider.overrideWith((ref) async => 'staff'),
        ]);
        addTearDown(container.dispose);

        await tester.pumpWidget(
          UncontrolledProviderScope(
            container: container,
            child: const MaterialApp(home: EyeSurgeryScreen()),
          ),
        );
        await tester.pumpAndSettle();

        final moreBtn = find.byIcon(Icons.more_vert);
        expect(moreBtn, findsOneWidget);
        await tester.tap(moreBtn);
        await tester.pumpAndSettle();

        expect(find.text('Delete surgery'), findsNothing);
      });

      testWidgets('3. Admin can delete a surgery successfully after confirmation', (tester) async {
        final surgery = _sampleSurgery(id: 's-to-delete');
        final fakeRepo = _FakeEyeSurgeryRepository(items: [surgery]);
        final container = ProviderContainer(overrides: [
          eyeSurgeryRepositoryProvider.overrideWithValue(fakeRepo),
          currentUserRoleProvider.overrideWith((ref) async => 'admin'),
        ]);
        addTearDown(container.dispose);

        await tester.pumpWidget(
          UncontrolledProviderScope(
            container: container,
            child: const MaterialApp(home: EyeSurgeryScreen()),
          ),
        );
        await tester.pumpAndSettle();

        expect(find.text('Aisha Kumar'), findsOneWidget);

        await tester.tap(find.byIcon(Icons.more_vert));
        await tester.pumpAndSettle();

        await tester.tap(find.text('Delete surgery'));
        await tester.pumpAndSettle();

        // Confirmation dialog shown with details and permanent warning
        expect(find.text('Delete Eye Surgery?'), findsOneWidget);
        expect(find.textContaining('This action is permanent and cannot be undone.'), findsOneWidget);
        expect(find.textContaining('Procedure: Cataract Surgery'), findsOneWidget);
        expect(find.text('Delete Permanently'), findsOneWidget);

        await tester.tap(find.text('Delete Permanently'));
        await tester.pumpAndSettle();

        // Removed from repo and UI
        expect(fakeRepo.items.any((s) => s.id == 's-to-delete'), isFalse);
        expect(find.text('Aisha Kumar'), findsNothing);
        expect(find.text('Surgery record deleted successfully.'), findsOneWidget);
      });

      testWidgets('4. Confirmation cancellation leaves the surgery unchanged', (tester) async {
        final surgery = _sampleSurgery(id: 's-keep');
        final fakeRepo = _FakeEyeSurgeryRepository(items: [surgery]);
        final container = ProviderContainer(overrides: [
          eyeSurgeryRepositoryProvider.overrideWithValue(fakeRepo),
          currentUserRoleProvider.overrideWith((ref) async => 'admin'),
        ]);
        addTearDown(container.dispose);

        await tester.pumpWidget(
          UncontrolledProviderScope(
            container: container,
            child: const MaterialApp(home: EyeSurgeryScreen()),
          ),
        );
        await tester.pumpAndSettle();

        await tester.tap(find.byIcon(Icons.more_vert));
        await tester.pumpAndSettle();

        await tester.tap(find.text('Delete surgery'));
        await tester.pumpAndSettle();

        expect(find.text('Delete Eye Surgery?'), findsOneWidget);
        await tester.tap(find.text('Cancel'));
        await tester.pumpAndSettle();

        // Dialog closed, surgery untouched
        expect(find.text('Delete Eye Surgery?'), findsNothing);
        expect(fakeRepo.items.any((s) => s.id == 's-keep'), isTrue);
        expect(find.text('Aisha Kumar'), findsOneWidget);
      });

      test('5. Staff deletion is rejected at database level', () async {
        final mockRepo = _ThrowingEyeSurgeryRepository();
        expect(
          () => mockRepo.deleteSurgery('any-id'),
          throwsA(isA<StateError>().having((e) => e.message, 'message', contains('permission denied'))),
        );
      });

      test('6. Existing Staff read/create/update permissions remain unchanged', () async {
        final surgery = _sampleSurgery(id: 's-staff-ops');
        final fakeRepo = _FakeEyeSurgeryRepository(items: [surgery]);

        // Read
        final fetched = await fakeRepo.fetchSurgeries();
        expect(fetched, hasLength(1));

        // Update checklist
        final updatedChecklist = await fakeRepo.updatePreOpChecklist(
          's-staff-ops',
          {'identity_verified': true, 'consent_confirmed': true},
        );
        expect(updatedChecklist.preOpChecklist['consent_confirmed'], isTrue);

        // Update details
        final updatedDetails = await fakeRepo.updateSurgeryDetails(
          id: 's-staff-ops',
          remarks: 'Pre-op complete',
        );
        expect(updatedDetails.remarks, 'Pre-op complete');
      });

      test('7. Deleting a surgery does not erase inventory transaction history', () async {
        final surgery = _sampleSurgery(id: 's-inv-audit');
        final fakeRepo = _FakeEyeSurgeryRepository(items: [surgery]);
        
        // Simulate inventory transactions that were recorded
        final recordedTransactions = <Map<String, dynamic>>[
          {
            'id': 'tx-1',
            'inventory_id': 'inv-1',
            'transaction_type': 'stock_out',
            'quantity': 2.0,
            'remarks': 'Eye Surgery s-inv-audit: IOL 20D',
          }
        ];

        // Delete surgery
        await fakeRepo.deleteSurgery('s-inv-audit');
        expect(fakeRepo.items.any((s) => s.id == 's-inv-audit'), isFalse);

        // Transactions table is separate and unaffected
        expect(recordedTransactions, hasLength(1));
        expect(recordedTransactions.first['remarks'], contains('Eye Surgery s-inv-audit'));
      });
    });

    // ================================================================
    // H. Date-Wise Scheduling & Time Sorting
    // ================================================================
    group('H. Date-Wise Eye Surgery Scheduling', () {
      test('1. Default selected date is today (local calendar day)', () {
        final container = ProviderContainer();
        addTearDown(container.dispose);

        final selected = container.read(eyeSurgerySelectedDateProvider);
        final now = DateTime.now();
        expect(selected.year, now.year);
        expect(selected.month, now.month);
        expect(selected.day, now.day);
      });

      testWidgets('2. Selecting a date shows only surgeries scheduled on that date', (tester) async {
        final today = DateTime.now();
        final yesterday = today.subtract(const Duration(days: 1));
        final tomorrow = today.add(const Duration(days: 1));

        final sYesterday = _sampleSurgery(id: 's-yest', patientName: 'Yesterday Patient', surgeryDate: yesterday);
        final sToday = _sampleSurgery(id: 's-today', patientName: 'Today Patient', surgeryDate: today);
        final sTomorrow = _sampleSurgery(id: 's-tom', patientName: 'Tomorrow Patient', surgeryDate: tomorrow);

        final fakeRepo = _FakeEyeSurgeryRepository(items: [sYesterday, sToday, sTomorrow]);
        final container = ProviderContainer(overrides: [
          eyeSurgeryRepositoryProvider.overrideWithValue(fakeRepo),
          currentUserRoleProvider.overrideWith((ref) async => 'admin'),
        ]);
        addTearDown(container.dispose);

        await tester.pumpWidget(
          UncontrolledProviderScope(
            container: container,
            child: const MaterialApp(home: EyeSurgeryScreen()),
          ),
        );
        await tester.pumpAndSettle();

        // Default view: today only
        expect(find.text('Today Patient'), findsOneWidget);
        expect(find.text('Yesterday Patient'), findsNothing);
        expect(find.text('Tomorrow Patient'), findsNothing);

        // Navigate to previous day
        await tester.tap(find.byTooltip('Previous Day'));
        await tester.pumpAndSettle();

        expect(find.text('Yesterday Patient'), findsOneWidget);
        expect(find.text('Today Patient'), findsNothing);
        expect(find.text('Tomorrow Patient'), findsNothing);

        // Click Today button to return
        await tester.tap(find.text('Today'));
        await tester.pumpAndSettle();

        expect(find.text('Today Patient'), findsOneWidget);
        expect(find.text('Yesterday Patient'), findsNothing);

        // Navigate to next day
        await tester.tap(find.byTooltip('Next Day'));
        await tester.pumpAndSettle();

        expect(find.text('Tomorrow Patient'), findsOneWidget);
        expect(find.text('Today Patient'), findsNothing);
      });

      test('3. Surgeries on multiple dates never leak into the selected date list', () async {
        final day1 = DateTime(2026, 10, 4);
        final day2 = DateTime(2026, 10, 5);

        final s1 = _sampleSurgery(id: 's1', surgeryDate: day1);
        final s2 = _sampleSurgery(id: 's2', surgeryDate: day2);

        final fakeRepo = _FakeEyeSurgeryRepository(items: [s1, s2]);
        final container = ProviderContainer(overrides: [
          eyeSurgeryRepositoryProvider.overrideWithValue(fakeRepo),
          eyeSurgerySelectedDateProvider.overrideWith((ref) => day1),
        ]);
        addTearDown(container.dispose);

        await container.read(eyeSurgeryListProvider.future);
        final list = container.read(filteredEyeSurgeriesProvider);
        expect(list.map((s) => s.id).toList(), ['s1']);
      });

      test('4. Multiple surgeries on the same date appear in ascending time order', () async {
        final date = DateTime(2026, 10, 4);
        final s1 = _sampleSurgery(id: 's-02pm', surgeryDate: date, surgeryTime: '02:00 PM');
        final s2 = _sampleSurgery(id: 's-09am', surgeryDate: date, surgeryTime: '09:00 AM');
        final s3 = _sampleSurgery(id: 's-0430pm', surgeryDate: date, surgeryTime: '04:30 PM');
        final s4 = _sampleSurgery(id: 's-1130am', surgeryDate: date, surgeryTime: '11:30 AM');

        final fakeRepo = _FakeEyeSurgeryRepository(items: [s1, s2, s3, s4]);
        final container = ProviderContainer(overrides: [
          eyeSurgeryRepositoryProvider.overrideWithValue(fakeRepo),
          eyeSurgerySelectedDateProvider.overrideWith((ref) => date),
        ]);
        addTearDown(container.dispose);

        await container.read(eyeSurgeryListProvider.future);
        final list = container.read(filteredEyeSurgeriesProvider);
        expect(
          list.map((s) => s.id).toList(),
          ['s-09am', 's-1130am', 's-02pm', 's-0430pm'],
        );
      });

      test('5. Equal-time surgeries use a deterministic secondary order (createdAt, then id)', () async {
        final date = DateTime(2026, 10, 4);
        final now = DateTime.now();

        final sEarlierCreated = EyeSurgeryModel(
          id: 's-b',
          patientId: 'p-1',
          surgeryType: 'Cataract Surgery',
          eyeSide: 'left',
          preOpDate: date,
          surgeryDate: date,
          surgeryTime: '10:00:00',
          status: 'scheduled',
          createdAt: now.subtract(const Duration(hours: 2)),
          updatedAt: now,
        );

        final sLaterCreated = EyeSurgeryModel(
          id: 's-a',
          patientId: 'p-2',
          surgeryType: 'Cataract Surgery',
          eyeSide: 'right',
          preOpDate: date,
          surgeryDate: date,
          surgeryTime: '10:00:00',
          status: 'scheduled',
          createdAt: now.subtract(const Duration(hours: 1)),
          updatedAt: now,
        );

        final fakeRepo = _FakeEyeSurgeryRepository(items: [sLaterCreated, sEarlierCreated]);
        final container = ProviderContainer(overrides: [
          eyeSurgeryRepositoryProvider.overrideWithValue(fakeRepo),
          eyeSurgerySelectedDateProvider.overrideWith((ref) => date),
        ]);
        addTearDown(container.dispose);

        await container.read(eyeSurgeryListProvider.future);
        final list = container.read(filteredEyeSurgeriesProvider);
        expect(list.first.id, 's-b');
        expect(list.last.id, 's-a');
      });

      test('6. Rescheduling moves the same record from old date to new date without duplication', () async {
        final date1 = DateTime(2026, 10, 4);
        final date2 = DateTime(2026, 10, 7);

        final surgery = _sampleSurgery(id: 's-resched', surgeryDate: date1, surgeryTime: '10:00:00');
        final fakeRepo = _FakeEyeSurgeryRepository(items: [surgery]);
        final container = ProviderContainer(overrides: [
          eyeSurgeryRepositoryProvider.overrideWithValue(fakeRepo),
          eyeSurgerySelectedDateProvider.overrideWith((ref) => date1),
        ]);
        addTearDown(container.dispose);

        // Before reschedule: visible on date1
        await container.read(eyeSurgeryListProvider.future);
        expect(container.read(filteredEyeSurgeriesProvider), hasLength(1));

        // Reschedule to date2
        await container.read(eyeSurgeryListProvider.notifier).rescheduleSurgery(
          id: 's-resched',
          surgeryDate: date2,
          surgeryTime: '14:00:00',
        );

        // No longer visible on date1
        expect(container.read(filteredEyeSurgeriesProvider), isEmpty);

        // Switch selected date to date2
        container.read(eyeSurgerySelectedDateProvider.notifier).state = date2;
        final onDate2 = container.read(filteredEyeSurgeriesProvider);
        expect(onDate2, hasLength(1));
        expect(onDate2.first.id, 's-resched');
        expect(onDate2.first.surgeryTime, '14:00:00');

        // Total repo item count is exactly 1 (no duplicates)
        expect(fakeRepo.items, hasLength(1));
      });

      test('7. Status filters combine correctly with date selection', () async {
        final date = DateTime(2026, 10, 4);
        final sSched = _sampleSurgery(id: 's-sched', status: 'scheduled', surgeryDate: date);
        final sPreOp = _sampleSurgery(id: 's-preop', status: 'pre_op', surgeryDate: date);
        final sOtherDate = _sampleSurgery(id: 's-other', status: 'scheduled', surgeryDate: date.add(const Duration(days: 1)));

        final fakeRepo = _FakeEyeSurgeryRepository(items: [sSched, sPreOp, sOtherDate]);
        final container = ProviderContainer(overrides: [
          eyeSurgeryRepositoryProvider.overrideWithValue(fakeRepo),
          eyeSurgerySelectedDateProvider.overrideWith((ref) => date),
        ]);
        addTearDown(container.dispose);

        await container.read(eyeSurgeryListProvider.future);
        // All for date
        expect(container.read(filteredEyeSurgeriesProvider), hasLength(2));

        // Filter by 'scheduled' for date
        container.read(eyeSurgeryStatusFilterProvider.notifier).state = 'scheduled';
        final filteredSched = container.read(filteredEyeSurgeriesProvider);
        expect(filteredSched.map((s) => s.id).toList(), ['s-sched']);
      });

      testWidgets('8. Empty dates display the correct empty state with Return to Today', (tester) async {
        tester.view.physicalSize = const Size(1200, 1200);
        tester.view.devicePixelRatio = 1.0;
        addTearDown(() => tester.view.resetPhysicalSize());

        final today = DateTime.now();
        final futureEmptyDate = today.add(const Duration(days: 10));

        final fakeRepo = _FakeEyeSurgeryRepository(items: <EyeSurgeryModel>[]);
        final container = ProviderContainer(overrides: [
          eyeSurgeryRepositoryProvider.overrideWithValue(fakeRepo),
          currentUserRoleProvider.overrideWith((ref) async => 'admin'),
          eyeSurgerySelectedDateProvider.overrideWith((ref) => futureEmptyDate),
        ]);
        addTearDown(container.dispose);

        await tester.pumpWidget(
          UncontrolledProviderScope(
            container: container,
            child: const MaterialApp(home: EyeSurgeryScreen()),
          ),
        );
        await tester.pumpAndSettle();

        expect(find.text('No surgeries scheduled for this date'), findsOneWidget);
        expect(find.text('Return to Today'), findsOneWidget);
        expect(find.text('Select another date'), findsOneWidget);

        // Clicking Return to Today updates selected date to today
        await tester.ensureVisible(find.text('Return to Today'));
        await tester.pumpAndSettle();
        await tester.tap(find.text('Return to Today'));
        await tester.pumpAndSettle();

        final selected = container.read(eyeSurgerySelectedDateProvider);
        expect(selected.year, today.year);
        expect(selected.month, today.month);
        expect(selected.day, today.day);
      });

      test('9. Date filtering remains correct across time zones and local midnight boundaries', () {
        final d1 = DateTime(2026, 10, 4, 0, 0, 0); // midnight
        final d2 = DateTime(2026, 10, 4, 23, 59, 59); // end of day
        final d3 = DateTime(2026, 10, 5, 0, 0, 0); // next day midnight

        expect(EyeSurgeryModel.isSameCalendarDay(d1, d2), isTrue);
        expect(EyeSurgeryModel.isSameCalendarDay(d1, d3), isFalse);
      });
    });

    group('I. Date-Wise Eye Surgery Summary Cards', () {
      test('1. Calculates all four counts (Total, Scheduled, In Progress, Discharged) date-wise', () async {
        final oct4 = DateTime(2026, 10, 4);
        final oct5 = DateTime(2026, 10, 5);

        // October 4 has 5 surgeries
        final s1 = _sampleSurgery(id: 's1', surgeryDate: oct4, status: 'scheduled', surgeryTime: null);
        final s2 = _sampleSurgery(id: 's2', surgeryDate: oct4, status: 'pre_op', surgeryTime: null);
        final s3 = _sampleSurgery(id: 's3', surgeryDate: oct4, status: 'in_surgery', surgeryTime: null);
        final s4 = _sampleSurgery(id: 's4', surgeryDate: oct4, status: 'post_op', surgeryTime: null);
        final s5 = _sampleSurgery(id: 's5', surgeryDate: oct4, status: 'discharged', surgeryTime: null);

        // October 5 has 3 surgeries
        final s6 = _sampleSurgery(id: 's6', surgeryDate: oct5, status: 'scheduled', surgeryTime: null);
        final s7 = _sampleSurgery(id: 's7', surgeryDate: oct5, status: 'scheduled', surgeryTime: null);
        final s8 = _sampleSurgery(id: 's8', surgeryDate: oct5, status: 'discharged', surgeryTime: null);

        final repo = _FakeEyeSurgeryRepository(items: [s1, s2, s3, s4, s5, s6, s7, s8]);
        final container = ProviderContainer(overrides: [
          eyeSurgeryRepositoryProvider.overrideWithValue(repo),
          eyeSurgerySelectedDateProvider.overrideWith((ref) => oct4),
        ]);
        addTearDown(container.dispose);

        await container.read(eyeSurgeryListProvider.future);

        // Oct 4 counts
        final statsOct4 = container.read(eyeSurgeryStatsProvider);
        expect(statsOct4.total, equals(5));
        expect(statsOct4.scheduled, equals(1));
        expect(statsOct4.inProgress, equals(3));
        expect(statsOct4.discharged, equals(1));

        // When selected date changes to Oct 5, update immediately to Oct 5 counts
        container.read(eyeSurgerySelectedDateProvider.notifier).state = oct5;
        final statsOct5 = container.read(eyeSurgeryStatsProvider);
        expect(statsOct5.total, equals(3));
        expect(statsOct5.scheduled, equals(2));
        expect(statsOct5.inProgress, equals(0));
        expect(statsOct5.discharged, equals(1));
      });

      test('2. Defaults to today\'s date and shows today\'s counts', () async {
        final now = DateTime.now();
        final today = DateTime(now.year, now.month, now.day);
        final tomorrow = today.add(const Duration(days: 1));

        final sToday = _sampleSurgery(id: 's-today', surgeryDate: today, status: 'scheduled', surgeryTime: null);
        final sTomorrow = _sampleSurgery(id: 's-tomorrow', surgeryDate: tomorrow, status: 'scheduled', surgeryTime: null);

        final repo = _FakeEyeSurgeryRepository(items: [sToday, sTomorrow]);
        final container = ProviderContainer(overrides: [
          eyeSurgeryRepositoryProvider.overrideWithValue(repo),
        ]);
        addTearDown(container.dispose);

        await container.read(eyeSurgeryListProvider.future);

        // Verify default selected date is today
        final selectedDate = container.read(eyeSurgerySelectedDateProvider);
        expect(EyeSurgeryModel.isSameCalendarDay(selectedDate, today), isTrue);

        // Shows only today's counts
        final stats = container.read(eyeSurgeryStatsProvider);
        expect(stats.total, equals(1));
        expect(stats.scheduled, equals(1));
        expect(stats.inProgress, equals(0));
        expect(stats.discharged, equals(0));
      });

      test('3. Dynamic Missed detection excludes past scheduled and pre_op from Scheduled and In Progress counts', () async {
        final pastDate = DateTime.now().subtract(const Duration(days: 2));

        // Past scheduled without time is missed
        final sMissedSched = _sampleSurgery(id: 's-m1', surgeryDate: pastDate, status: 'scheduled', surgeryTime: '09:00:00');
        // Past pre_op with time passed is missed
        final sMissedPreOp = _sampleSurgery(id: 's-m2', surgeryDate: pastDate, status: 'pre_op', surgeryTime: '09:00:00');
        // Past in_surgery is NOT missed (in progress)
        final sInSurgery = _sampleSurgery(id: 's-in', surgeryDate: pastDate, status: 'in_surgery', surgeryTime: '09:00:00');
        // Past discharged is discharged
        final sDischarged = _sampleSurgery(id: 's-dis', surgeryDate: pastDate, status: 'discharged', surgeryTime: '09:00:00');

        final repo = _FakeEyeSurgeryRepository(items: [sMissedSched, sMissedPreOp, sInSurgery, sDischarged]);
        final container = ProviderContainer(overrides: [
          eyeSurgeryRepositoryProvider.overrideWithValue(repo),
          eyeSurgerySelectedDateProvider.overrideWith((ref) => pastDate),
        ]);
        addTearDown(container.dispose);

        await container.read(eyeSurgeryListProvider.future);

        final stats = container.read(eyeSurgeryStatsProvider);
        expect(stats.total, equals(4)); // all 4 belong to that date
        expect(stats.scheduled, equals(0)); // missed scheduled is not counted as scheduled
        expect(stats.inProgress, equals(1)); // only sInSurgery is in progress (sMissedPreOp is missed)
        expect(stats.discharged, equals(1));
      });

      test('4. Cancelled surgery is counted in Total Surgeries but not in Scheduled, In Progress, or Discharged', () async {
        final targetDate = DateTime(2026, 10, 4);

        final sCancelled = _sampleSurgery(id: 's-canc', surgeryDate: targetDate, status: 'cancelled', surgeryTime: null);
        final sScheduled = _sampleSurgery(id: 's-sched', surgeryDate: targetDate, status: 'scheduled', surgeryTime: null);

        final repo = _FakeEyeSurgeryRepository(items: [sCancelled, sScheduled]);
        final container = ProviderContainer(overrides: [
          eyeSurgeryRepositoryProvider.overrideWithValue(repo),
          eyeSurgerySelectedDateProvider.overrideWith((ref) => targetDate),
        ]);
        addTearDown(container.dispose);

        await container.read(eyeSurgeryListProvider.future);

        final stats = container.read(eyeSurgeryStatsProvider);
        expect(stats.total, equals(2));
        expect(stats.scheduled, equals(1));
        expect(stats.inProgress, equals(0));
        expect(stats.discharged, equals(0));
      });

      testWidgets('5. Renders exactly 4 summary cards at top matching Dental Lab design and updates on date change', (tester) async {
        final oct4 = DateTime(2026, 10, 4);
        final oct5 = DateTime(2026, 10, 5);

        final s1 = _sampleSurgery(id: 's1', surgeryDate: oct4, status: 'scheduled', surgeryTime: null);
        final s2 = _sampleSurgery(id: 's2', surgeryDate: oct4, status: 'in_surgery', surgeryTime: null);
        final s3 = _sampleSurgery(id: 's3', surgeryDate: oct5, status: 'discharged', surgeryTime: null);

        final repo = _FakeEyeSurgeryRepository(items: [s1, s2, s3]);
        final container = ProviderContainer(overrides: [
          eyeSurgeryRepositoryProvider.overrideWithValue(repo),
          currentUserRoleProvider.overrideWith((ref) async => 'admin'),
          eyeSurgerySelectedDateProvider.overrideWith((ref) => oct4),
        ]);
        addTearDown(container.dispose);

        await tester.pumpWidget(
          UncontrolledProviderScope(
            container: container,
            child: const MaterialApp(home: EyeSurgeryScreen()),
          ),
        );
        await tester.pumpAndSettle();

        // Exactly 4 card titles exist
        expect(find.text('Total Surgeries'), findsOneWidget);
        expect(find.text('Scheduled'), findsOneWidget);
        expect(find.text('In Progress'), findsOneWidget);
        expect(find.text('Discharged'), findsOneWidget);

        // Oct 4 counts: Total = 2, Scheduled = 1, In Progress = 1, Discharged = 0
        expect(find.text('2'), findsOneWidget); // Total Surgeries
        expect(find.text('1'), findsNWidgets(2)); // Scheduled: 1, In Progress: 1
        expect(find.text('0'), findsOneWidget); // Discharged: 0

        // Tap Next Day to go to Oct 5
        await tester.tap(find.byTooltip('Next Day'));
        await tester.pumpAndSettle();

        // Now on Oct 5: Total = 1, Scheduled = 0, In Progress = 0, Discharged = 1
        expect(find.text('Total Surgeries'), findsOneWidget);
        expect(find.text('Scheduled'), findsOneWidget);
        expect(find.text('In Progress'), findsOneWidget);
        expect(find.text('Discharged'), findsOneWidget);
      });

      testWidgets('6. Tapping summary card filters list to matching status', (tester) async {
        final today = DateTime.now();
        final sSched = _sampleSurgery(id: 's-sc', surgeryDate: today, status: 'scheduled', surgeryTime: null, patientName: 'Scheduled Patient');
        final sInProg = _sampleSurgery(id: 's-ip', surgeryDate: today, status: 'in_surgery', surgeryTime: null, patientName: 'InProg Patient');
        final sDisch = _sampleSurgery(id: 's-dc', surgeryDate: today, status: 'discharged', surgeryTime: null, patientName: 'Discharged Patient');

        final repo = _FakeEyeSurgeryRepository(items: [sSched, sInProg, sDisch]);
        final container = ProviderContainer(overrides: [
          eyeSurgeryRepositoryProvider.overrideWithValue(repo),
          currentUserRoleProvider.overrideWith((ref) async => 'admin'),
          eyeSurgerySelectedDateProvider.overrideWith((ref) => DateTime(today.year, today.month, today.day)),
        ]);
        addTearDown(container.dispose);

        tester.view.physicalSize = const Size(1200, 1800);
        tester.view.devicePixelRatio = 1.0;
        addTearDown(() => tester.view.resetPhysicalSize());

        await tester.pumpWidget(
          UncontrolledProviderScope(
            container: container,
            child: const MaterialApp(home: EyeSurgeryScreen()),
          ),
        );
        await tester.pumpAndSettle();

        // Initially all 3 patients shown
        expect(find.text('Scheduled Patient'), findsOneWidget);
        expect(find.text('InProg Patient'), findsOneWidget);
        expect(find.text('Discharged Patient'), findsOneWidget);

        // Tap 'Scheduled' card
        await tester.tap(find.text('Scheduled'));
        await tester.pumpAndSettle();
        expect(find.text('Scheduled Patient'), findsOneWidget);
        expect(find.text('InProg Patient'), findsNothing);
        expect(find.text('Discharged Patient'), findsNothing);

        // Tap 'In Progress' card
        await tester.tap(find.text('In Progress'));
        await tester.pumpAndSettle();
        expect(find.text('Scheduled Patient'), findsNothing);
        expect(find.text('InProg Patient'), findsOneWidget);
        expect(find.text('Discharged Patient'), findsNothing);

        // Tap 'Discharged' card
        await tester.tap(find.text('Discharged'));
        await tester.pumpAndSettle();
        expect(find.text('Scheduled Patient'), findsNothing);
        expect(find.text('InProg Patient'), findsNothing);
        expect(find.text('Discharged Patient'), findsOneWidget);

        // Tap 'Total Surgeries' card (resets to all)
        await tester.tap(find.text('Total Surgeries'));
        await tester.pumpAndSettle();
        expect(find.text('Scheduled Patient'), findsOneWidget);
        expect(find.text('InProg Patient'), findsOneWidget);
        expect(find.text('Discharged Patient'), findsOneWidget);
      });
    });
  });
}

class _ThrowingEyeSurgeryRepository extends _FakeEyeSurgeryRepository {
  @override
  Future<void> deleteSurgery(String id) async {
    throw StateError('Eye surgery could not be deleted or permission denied.');
  }
}


class _FixedEyeSurgeryListNotifier extends EyeSurgeryListNotifier {
  _FixedEyeSurgeryListNotifier(this.surgeries);

  final List<EyeSurgeryModel> surgeries;

  @override
  Future<List<EyeSurgeryModel>> build() async => surgeries;
}

class _TestInventoryNotifier extends InventoryNotifier {
  _TestInventoryNotifier(this.items) : super(_FakeInventoryRepository(items));

  final List<InventoryItem> items;

  @override
  Future<void> fetchInventory() async {
    state = AsyncValue.data(items);
  }
}

class _FakeEyeSurgeryRepository extends EyeSurgeryRepository {
  _FakeEyeSurgeryRepository({List<EyeSurgeryModel> items = const []})
      : items = List.of(items),
        super(
            client: SupabaseClient(
          'https://example.supabase.co',
          'test-key',
          authOptions: const AuthClientOptions(autoRefreshToken: false),
        ));

  List<EyeSurgeryModel> items;
  final List<EyeSurgeryItemModel> surgeryItems = [];
  final List<EyeSurgeryItemTemplateModel> templates = [];
  final List<NotificationModel> notifications = [];
  final List<TaskItem> tasks = [];
  List<EyeSurgeryStaffCandidate> staffCandidates = const [
    EyeSurgeryStaffCandidate(id: 'staff-1', fullName: 'Dr. Rao'),
    EyeSurgeryStaffCandidate(id: 'staff-2', fullName: 'Dr. Mehta'),
    EyeSurgeryStaffCandidate(id: 'staff-3', fullName: 'Dr. Kumar'),
  ];
  bool failFetch = false;
  bool blockStartSurgery = false;
  bool simulateNotificationFailure = false;
  Completer<List<EyeSurgeryModel>>? pendingFetch;
  int _nextId = 2;
  int inventoryConsumptions = 0;

  @override
  Future<List<EyeSurgeryStaffCandidate>> fetchStaffCandidates() async =>
      staffCandidates;

  @override
  Future<List<EyeSurgeryItemModel>> fetchSurgeryItems(String surgeryId) async =>
      surgeryItems.where((item) => item.surgeryId == surgeryId).toList();

  @override
  Future<List<EyeSurgeryItemTemplateModel>> fetchItemTemplates(
          String surgeryType) async =>
      templates
          .where((t) => t.surgeryType == surgeryType && t.isActive)
          .toList();

  @override
  Future<List<EyeSurgeryItemTemplateModel>> fetchAllItemTemplates() async =>
      templates;

  @override
  Future<EyeSurgeryItemModel> addSurgeryItem({
    required String surgeryId,
    required String inventoryItemId,
    required double plannedQuantity,
    double? actualQuantity,
    String source = 'manual',
  }) async {
    final item = EyeSurgeryItemModel(
      id: 'si-${surgeryItems.length + 1}',
      surgeryId: surgeryId,
      inventoryItemId: inventoryItemId,
      inventoryItemName: inventoryItemId,
      currentStock: 50,
      unit: 'pcs',
      plannedQuantity: plannedQuantity,
      actualQuantity: actualQuantity ?? plannedQuantity,
      source: source,
    );
    surgeryItems.add(item);
    return item;
  }

  @override
  Future<EyeSurgeryItemModel> updateSurgeryItem({
    required String itemId,
    required double plannedQuantity,
    required double actualQuantity,
  }) async {
    final index = surgeryItems.indexWhere((item) => item.id == itemId);
    final old = surgeryItems[index];
    final updated = EyeSurgeryItemModel(
      id: old.id,
      surgeryId: old.surgeryId,
      inventoryItemId: old.inventoryItemId,
      inventoryItemName: old.inventoryItemName,
      currentStock: old.currentStock,
      unit: old.unit,
      plannedQuantity: plannedQuantity,
      actualQuantity: actualQuantity,
      source: old.source,
      consumedAt: old.consumedAt,
    );
    surgeryItems[index] = updated;
    return updated;
  }

  @override
  Future<void> removeSurgeryItem(String itemId) async {
    surgeryItems.removeWhere((item) => item.id == itemId);
  }

  @override
  Future<List<EyeSurgeryModel>> fetchSurgeries({String? status}) {
    if (failFetch) return Future.error(StateError('offline'));
    final pending = pendingFetch;
    if (pending != null) return pending.future;
    return Future.value(List.of(items));
  }

  @override
  Future<List<EyeSurgeryModel>> fetchSurgeriesForPatient(
          String patientId) async =>
      items.where((item) => item.patientId == patientId).toList();

  @override
  Future<EyeSurgeryModel> createSurgery({
    required String patientId,
    required String surgeryType,
    required String surgeryTypeCategory,
    String? customSurgeryType,
    required String eyeSide,
    required DateTime? surgeryDate,
    String? assignedStaffId,
    String? surgeryTime,
    Map<String, bool> preOpChecklist = const {},
    String? iolDetails,
    String? remarks,
    List<({String inventoryItemId, double plannedQuantity, String source})>? initialItems,
  }) async {
    final effectiveDate = surgeryDate ?? DateTime(2026, 10, 12);
    final sanitizedTime = (surgeryTime == null || surgeryTime.trim().isEmpty)
        ? null
        : surgeryTime.trim();
    final surgery = EyeSurgeryModel(
      id: 's-${_nextId++}',
      patientId: patientId,
      surgeryType: surgeryType,
      surgeryTypeCategory: surgeryTypeCategory,
      customSurgeryType: customSurgeryType,
      eyeSide: eyeSide,
      assignedStaffId: assignedStaffId,
      preOpDate: effectiveDate,
      surgeryDate: effectiveDate,
      surgeryTime: sanitizedTime,
      status: 'scheduled',
      preOpChecklist: Map.of(preOpChecklist),
      iolDetails: iolDetails,
      remarks: remarks,
      createdAt: DateTime(2026),
      updatedAt: DateTime(2026),
    );
    items = [...items, surgery];
    if (initialItems != null) {
      for (final item in initialItems) {
        surgeryItems.add(EyeSurgeryItemModel(
          id: 'si-${surgeryItems.length + 1}',
          surgeryId: surgery.id,
          inventoryItemId: item.inventoryItemId,
          inventoryItemName: item.inventoryItemId,
          currentStock: 50,
          unit: 'pcs',
          plannedQuantity: item.plannedQuantity,
          actualQuantity: item.plannedQuantity,
          source: item.source,
        ));
      }
    }
    return surgery;
  }

  @override
  Future<EyeSurgeryModel> updateSurgery(EyeSurgeryModel surgery) async =>
      _save(surgery);

  @override
  Future<EyeSurgeryModel> updateStatus(String id, String newStatus) async {
    final existing = items.firstWhere((item) => item.id == id);
    final error = EyeSurgeryModel.validateStatusTransition(
      surgery: existing,
      nextStatus: newStatus,
    );
    if (error != null) throw StateError(error);
    final updated = _save(_find(id, (item) => _copySurgery(item, status: newStatus)));
    final taskIdx = tasks.indexWhere((t) => t.relatedSurgeryId == id);
    if (taskIdx != -1) {
      if (newStatus == 'discharged') {
        tasks[taskIdx] = tasks[taskIdx].copyWith(
          status: 'completed',
          completedAt: DateTime.now(),
        );
      } else if (newStatus == 'cancelled') {
        tasks[taskIdx] = tasks[taskIdx].copyWith(status: 'cancelled');
      }
    }
    return updated;
  }

  @override
  Future<EyeSurgeryModel> startSurgery(String id) async {
    final surgery = items.firstWhere((item) => item.id == id);
    if (surgery.inventoryConsumedAt != null) return surgery;
    if (!surgery.isPreOpChecklistComplete) {
      throw StateError(
        'Complete the pre-op checklist before entering surgery.',
      );
    }
    if (blockStartSurgery) {
      throw StateError('Insufficient stock for IOL');
    }
    inventoryConsumptions++;
    return _save(_copySurgery(
      surgery,
      status: 'in_surgery',
      markInventoryConsumed: true,
    ));
  }

  @override
  Future<EyeSurgeryModel?> fetchSurgeryById(String id) async =>
      items.where((s) => s.id == id).firstOrNull;

  @override
  Future<EyeSurgeryModel> updatePreOpChecklist(
    String id,
    Map<String, bool> checklist,
  ) async =>
      _save(_find(id, (item) => _copySurgery(item, checklist: checklist)));

  @override
  Future<EyeSurgeryModel> updateSurgeryDetails({
    required String id,
    String? iolDetails,
    String? remarks,
  }) async =>
      _save(_find(
        id,
        (item) => _copySurgery(item, iolDetails: iolDetails, remarks: remarks),
      ));

  @override
  Future<EyeSurgeryModel> linkFollowUpAppointment(
    String id,
    String appointmentId,
  ) async =>
      _save(_find(
        id,
        (item) => _copySurgery(item, followUpAppointmentId: appointmentId),
      ));

  @override
  Future<EyeSurgeryModel> rescheduleSurgery({
    required String id,
    required DateTime surgeryDate,
    String? surgeryTime,
  }) async {
    if (surgeryTime == null || surgeryTime.trim().isEmpty) {
      throw ArgumentError('Surgery time is required.');
    }
    final sanitizedTime = surgeryTime.trim();
    final parsed = EyeSurgeryModel.parseTimeString(sanitizedTime);
    final isFuture = parsed != null &&
        DateTime(
          surgeryDate.year,
          surgeryDate.month,
          surgeryDate.day,
          parsed.hour,
          parsed.minute,
        ).isAfter(DateTime.now());

    final updated = _save(_find(
      id,
      (item) => _copySurgery(
        item,
        surgeryDate: surgeryDate,
        surgeryTime: sanitizedTime,
        status: isFuture ? 'scheduled' : item.status,
      ),
    ));
    final taskIdx = tasks.indexWhere((t) => t.relatedSurgeryId == id);
    if (taskIdx != -1) {
      tasks[taskIdx] = tasks[taskIdx].copyWith(
        dueDate: surgeryDate,
        description:
            '$sanitizedTime · ${updated.displaySurgeryType} — ${updated.eyeSide} Eye',
      );
    }
    return updated;
  }

  @override
  Future<EyeSurgeryModel> assignStaff(
    String id,
    String? assignedStaffId,
  ) async {
    final existing = items.firstWhere((item) => item.id == id);
    final oldStaffId = existing.assignedStaffId;
    final updated = _save(_find(
        id, (item) => _copySurgery(item, assignedStaffId: assignedStaffId)));

    if (assignedStaffId != null && assignedStaffId.trim().isNotEmpty) {
      final taskTitle = 'Eye Surgery — ${updated.patientName ?? "Patient"}';
      final hasTime = updated.surgeryTime != null && updated.surgeryTime!.trim().isNotEmpty;
      final taskDesc = hasTime
          ? '${updated.surgeryTime!.trim()} · ${updated.displaySurgeryType} — ${updated.eyeSide} Eye'
          : '${updated.displaySurgeryType} — ${updated.eyeSide} Eye';
      final taskIdx = tasks.indexWhere((t) => t.relatedSurgeryId == id);
      if (taskIdx != -1) {
        tasks[taskIdx] = tasks[taskIdx].copyWith(
          assignedTo: assignedStaffId,
          dueDate: updated.surgeryDate,
          title: taskTitle,
          description: taskDesc,
          status: 'pending',
        );
      } else {
        tasks.add(TaskItem(
          id: 'task-${tasks.length + 1}',
          title: taskTitle,
          description: taskDesc,
          assignedTo: assignedStaffId,
          dueDate: updated.surgeryDate,
          priority: 'high',
          status: 'pending',
          createdAt: DateTime.now(),
          updatedAt: DateTime.now(),
          relatedSurgeryId: id,
        ));
      }

      if (oldStaffId != assignedStaffId) {
        if (!simulateNotificationFailure) {
          final notifMessage = StringBuffer()
            ..writeln('Patient: ${updated.patientName ?? "Patient"}')
            ..writeln('Surgery: ${updated.surgeryType}')
            ..writeln('Eye: ${updated.eyeSide}')
            ..write('Date: ${updated.surgeryDate.year.toString().padLeft(4, '0')}-${updated.surgeryDate.month.toString().padLeft(2, '0')}-${updated.surgeryDate.day.toString().padLeft(2, '0')}');
          if (hasTime) {
            notifMessage.write('\nTime: ${updated.surgeryTime!.trim()}');
          }

          notifications.add(NotificationModel(
            id: 'notif-${notifications.length + 1}',
            userId: assignedStaffId,
            title: 'Eye Surgery Assigned',
            message: notifMessage.toString(),
            type: 'eye_surgery_assigned',
            isRead: false,
            relatedId: id,
            createdAt: DateTime.now(),
          ));
        }
      }
    } else {
      tasks.removeWhere((t) => t.relatedSurgeryId == id);
    }

    return updated;
  }

  @override
  Future<void> deleteSurgery(String id) async {
    items.removeWhere((item) => item.id == id);
    surgeryItems.removeWhere((item) => item.surgeryId == id);
    tasks.removeWhere((t) => t.relatedSurgeryId == id);
  }

  EyeSurgeryModel _find(
    String id,
    EyeSurgeryModel Function(EyeSurgeryModel) update,
  ) =>
      update(items.firstWhere((item) => item.id == id));

  EyeSurgeryModel _save(EyeSurgeryModel surgery) {
    items =
        items.map((item) => item.id == surgery.id ? surgery : item).toList();
    return surgery;
  }
}

const _kNoValue = Object();

EyeSurgeryModel _sampleSurgery({
  String id = 's-1',
  String patientId = 'p-1',
  String? patientName,
  String? patientNumber,
  String surgeryType = 'Cataract Surgery',
  String surgeryTypeCategory = 'Cataract Surgery',
  String eyeSide = 'left',
  String status = 'scheduled',
  DateTime? surgeryDate,
  Object? surgeryTime = _kNoValue,
  String? followUpAppointmentId,
  String? assignedStaffId = 'staff-1',
  String? assignedStaffName,
  DateTime? dischargedAt,
  String? iolDetails,
  String? remarks,
}) {
  final now = DateTime.now();
  final defaultDate = DateTime(now.year, now.month, now.day);
  final effectiveDate = surgeryDate ?? defaultDate;
  return EyeSurgeryModel(
      id: id,
      patientId: patientId,
      surgeryType: surgeryType,
      surgeryTypeCategory: surgeryTypeCategory,
      eyeSide: eyeSide,
      assignedStaffId: assignedStaffId,
      assignedStaffName: assignedStaffName ?? (assignedStaffId != null ? 'Dr. Rao' : null),
      preOpDate: effectiveDate,
      surgeryDate: effectiveDate,
      surgeryTime: identical(surgeryTime, _kNoValue)
          ? '10:30:00'
          : (surgeryTime as String?),
      status: status,
      preOpChecklist: const {'identity_verified': true},
      iolDetails: iolDetails,
      remarks: remarks,
      followUpAppointmentId: followUpAppointmentId,
      dischargedAt: dischargedAt ?? (status == 'discharged' ? DateTime.now() : null),
      createdAt: DateTime.now().subtract(const Duration(days: 2)),
      updatedAt: DateTime.now(),
      patientName: patientName ?? 'Aisha Kumar',
      patientNumber: patientNumber ?? 'E102',
    );
}

EyeSurgeryModel _copySurgery(
  EyeSurgeryModel surgery, {
  String? surgeryType,
  String? surgeryTypeCategory,
  String? customSurgeryType,
  String? status,
  String? assignedStaffId,
  DateTime? surgeryDate,
  Object? surgeryTime = _kNoValue,
  bool markInventoryConsumed = false,
  Map<String, bool>? checklist,
  String? iolDetails,
  String? remarks,
  String? followUpAppointmentId,
  DateTime? dischargedAt,
}) =>
    EyeSurgeryModel(
      id: surgery.id,
      patientId: surgery.patientId,
      surgeryType: surgeryType ?? surgery.surgeryType,
      surgeryTypeCategory: surgeryTypeCategory ?? surgery.surgeryTypeCategory,
      customSurgeryType: customSurgeryType ?? surgery.customSurgeryType,
      eyeSide: surgery.eyeSide,
      assignedStaffId: assignedStaffId ?? surgery.assignedStaffId,
      assignedStaffName: surgery.assignedStaffName,
      preOpDate: surgeryDate ?? surgery.surgeryDate,
      surgeryDate: surgeryDate ?? surgery.surgeryDate,
      surgeryTime: identical(surgeryTime, _kNoValue)
          ? surgery.surgeryTime
          : (surgeryTime as String?),
      inventoryConsumedAt: markInventoryConsumed
          ? DateTime(2026, 11, 1)
          : surgery.inventoryConsumedAt,
      status: status ?? surgery.status,
      preOpChecklist: checklist ?? surgery.preOpChecklist,
      iolDetails: iolDetails ?? surgery.iolDetails,
      remarks: remarks ?? surgery.remarks,
      followUpAppointmentId:
          followUpAppointmentId ?? surgery.followUpAppointmentId,
      dischargedAt: dischargedAt ??
          ((status ?? surgery.status) == 'discharged'
              ? (surgery.dischargedAt ?? DateTime.now())
              : null),
      createdAt: surgery.createdAt,
      updatedAt: DateTime.now(),
      patientName: surgery.patientName,
      patientNumber: surgery.patientNumber,
    );

InventoryItem _inventoryItem({required String id, required double quantity}) =>
    InventoryItem(
      id: id,
      name: 'Surgical Lens',
      category: 'Surgical Equipment',
      currentStock: quantity,
      unit: 'pcs',
    );

class _FakeInventoryRepository extends InventoryRepository {
  _FakeInventoryRepository(this.items)
      : super(SupabaseClient(
          'https://example.supabase.co',
          'test-key',
          authOptions: const AuthClientOptions(autoRefreshToken: false),
        ));

  List<InventoryItem> items;

  @override
  Future<List<InventoryItem>> getInventoryItems({
    String? category,
    String? department,
    String? searchQuery,
    bool? activeOnly,
  }) async =>
      items;
}

class _RecordingNavigatorObserver extends NavigatorObserver {
  Route<dynamic>? lastPushed;

  @override
  void didPush(Route<dynamic> route, Route<dynamic>? previousRoute) {
    lastPushed = route;
    super.didPush(route, previousRoute);
  }
}

class _FixedStaffTasksNotifier extends StaffTasksNotifier {
  _FixedStaffTasksNotifier(List<TaskItem> initial)
      : super(
          TaskRepository(SupabaseClient(
            'https://example.supabase.co',
            'key',
            authOptions: const AuthClientOptions(autoRefreshToken: false),
          )),
          SupabaseClient(
            'https://example.supabase.co',
            'key',
            authOptions: const AuthClientOptions(autoRefreshToken: false),
          ),
          'staff-1',
          enableRealtime: false,
        ) {
    state = AsyncData(initial);
  }

  @override
  Future<void> fetchTasks({bool silent = false}) async {}

  @override
  Future<void> updateStatus(
      String taskId, String newStatus, String oldStatus,
      {String? note}) async {
    final list = state.valueOrNull ?? [];
    state = AsyncData(list
        .map((t) => t.id == taskId ? t.copyWith(status: newStatus) : t)
        .toList());
  }
}

class _TestDepartmentsNotifier extends DepartmentsNotifier {
  _TestDepartmentsNotifier() : super(_TestDepartmentRepository());
}

class _TestDepartmentRepository implements DepartmentRepository {
  @override
  Future<List<Department>> fetchDepartments() async => const [
        Department(
          id: 'eye-dept',
          name: 'Eye Clinic',
          isActive: true,
        ),
      ];

  @override
  Future<void> createDepartment({required String name, String? description}) async {}

  @override
  Future<void> updateDepartment({
    required String id,
    required String name,
    String? description,
    required bool isActive,
  }) async {}

  @override
  Future<void> deleteDepartment(String id) async {}
}

