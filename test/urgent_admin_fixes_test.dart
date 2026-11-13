import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:flutter_test/flutter_test.dart';

import 'package:mkes_care/features/admin/models/user_profile.dart';
import 'package:mkes_care/features/admin/providers/users_provider.dart';
import 'package:mkes_care/features/admin/widgets/inventory_alerts_card.dart';
import 'package:mkes_care/features/admin/widgets/patient_summary_card.dart';
import 'package:mkes_care/features/appointments/models/appointment_model.dart';
import 'package:mkes_care/features/inventory/models/inventory_item.dart';
import 'package:mkes_care/features/inventory/models/purchase_order.dart';
import 'package:mkes_care/features/inventory/providers/inventory_provider.dart';
import 'package:mkes_care/features/inventory/providers/purchase_order_provider.dart';
import 'package:mkes_care/features/inventory/widgets/purchase_order_details_dialog.dart';
import 'package:mkes_care/features/patients/models/patient_model.dart';
import 'package:mkes_care/features/patients/providers/patients_provider.dart';
import 'package:mkes_care/features/reports/widgets/reports_chart_painters.dart';
import 'package:mkes_care/features/reports/widgets/reports_metric_card.dart';
import 'package:mkes_care/features/staff/models/attendance_record.dart';
import 'package:mkes_care/features/staff/providers/attendance_provider.dart';
import 'package:mkes_care/features/staff/widgets/staff_attendance_summary_card.dart';
import 'package:mkes_care/features/staff/widgets/staff_member_tile.dart';

// Fakes
class _FakeInventoryNotifier extends StateNotifier<AsyncValue<List<InventoryItem>>>
    implements InventoryNotifier {
  _FakeInventoryNotifier(super.state);
  @override
  dynamic noSuchMethod(Invocation invocation) => super.noSuchMethod(invocation);
}

class _FakeUsersNotifier extends StateNotifier<AsyncValue<List<UserProfile>>>
    implements UsersNotifier {
  _FakeUsersNotifier(super.state);
  @override
  dynamic noSuchMethod(Invocation invocation) => super.noSuchMethod(invocation);
}

class _FakePONotifier extends StateNotifier<AsyncValue<List<PurchaseOrder>>>
    implements PurchaseOrdersNotifier {
  _FakePONotifier(super.state);
  @override
  dynamic noSuchMethod(Invocation invocation) => super.noSuchMethod(invocation);
}

class _FakePatientsNotifier extends StateNotifier<AsyncValue<List<PatientModel>>>
    implements PatientsNotifier {
  _FakePatientsNotifier(super.state);
  @override
  dynamic noSuchMethod(Invocation invocation) => super.noSuchMethod(invocation);
}

void main() {
  TestWidgetsFlutterBinding.ensureInitialized();

  group('Fix 4A: Critical Inventory Displays All Qualifying Items', () {
    testWidgets('Displays all 5 qualifying critical products instead of capping at 3',
        (tester) async {
      tester.view.physicalSize = const Size(800, 1000);
      tester.view.devicePixelRatio = 1.0;
      addTearDown(tester.view.resetPhysicalSize);

      final criticalItems = <InventoryItem>[
        InventoryItem(
          id: 'item-1',
          name: 'Critical Product 1 (Low Stock)',
          category: 'Consumables',
          currentStock: 2,
          minimumStock: 10,
          isActive: true,
          unit: 'vials',
          department: 'eye',
        ),
        InventoryItem(
          id: 'item-2',
          name: 'Critical Product 2 (Expiring Soon)',
          category: 'Medications',
          currentStock: 15,
          minimumStock: 5,
          isActive: true,
          expiryDate: DateTime.now().add(const Duration(days: 10)),
          unit: 'boxes',
          department: 'dental',
        ),
        InventoryItem(
          id: 'item-3',
          name: 'Critical Product 3 (Expired)',
          category: 'Supplies',
          currentStock: 8,
          minimumStock: 5,
          isActive: true,
          expiryDate: DateTime.now().subtract(const Duration(days: 5)),
          unit: 'strips',
          department: 'eye',
        ),
        InventoryItem(
          id: 'item-4',
          name: 'Critical Product 4 (Zero Stock)',
          category: 'Instruments',
          currentStock: 0,
          minimumStock: 20,
          isActive: true,
          unit: 'units',
          department: 'dental',
        ),
        InventoryItem(
          id: 'item-5',
          name: 'Critical Product 5 (Low Stock)',
          category: 'Dental Material',
          currentStock: 1,
          minimumStock: 15,
          isActive: true,
          unit: 'bottles',
          department: 'eye',
        ),
      ];

      await tester.pumpWidget(
        ProviderScope(
          overrides: [
            inventoryProvider.overrideWith(
              (ref) => _FakeInventoryNotifier(AsyncValue.data(criticalItems)),
            ),
            purchaseOrdersProvider.overrideWith(
              (ref) => _FakePONotifier(const AsyncValue.data([])),
            ),
          ],
          child: const MaterialApp(
            home: Scaffold(
              body: SingleChildScrollView(
                child: InventoryAlertsCard(),
              ),
            ),
          ),
        ),
      );

      await tester.pumpAndSettle();

      // Verify that ALL 5 qualifying products are visible in the UI
      expect(find.text('Critical Product 1 (Low Stock)'), findsOneWidget);
      expect(find.text('Critical Product 2 (Expiring Soon)'), findsOneWidget);
      expect(find.text('Critical Product 3 (Expired)'), findsOneWidget);
      expect(find.text('Critical Product 4 (Zero Stock)'), findsOneWidget);
      expect(find.text('Critical Product 5 (Low Stock)'), findsOneWidget);
    });
  });

  group('Fix 6A & 6B: Admin Patient Statistics & Separation of Tickets', () {
    test('PatientModel correctly parses registration_date and handles null created_at', () {
      final json = {
        'id': 'p-test-1',
        'patient_number': 'MKES-001',
        'name': 'Test Patient',
        'registration_date': '2026-11-01',
        'created_at': null,
      };

      final patient = PatientModel.fromJson(json);
      expect(patient.registrationDate, isNotNull);
      expect(patient.registrationDate!.year, 2026);
      expect(patient.registrationDate!.month, 11);
      expect(patient.registrationDate!.day, 1);
      expect(patient.createdAt.isBefore(DateTime.now().subtract(const Duration(days: 1))), isTrue);
    });

    testWidgets('PatientSummaryCard separates Appointment Tickets from New Registrations and excludes yesterday registrations',
        (tester) async {
      tester.view.physicalSize = const Size(800, 800);
      tester.view.devicePixelRatio = 1.0;
      addTearDown(tester.view.resetPhysicalSize);

      final now = DateTime.now();
      final todayLocal = DateTime(now.year, now.month, now.day, 11, 0);
      final yesterdayLocal = todayLocal.subtract(const Duration(days: 1));

      final patients = [
        PatientModel(
          id: 'p-yesterday',
          patientNumber: 'E-001',
          name: 'Yesterday Patient',
          createdAt: yesterdayLocal,
          registrationDate: yesterdayLocal,
          updatedAt: yesterdayLocal,
        ),
        PatientModel(
          id: 'p-today-1',
          patientNumber: 'E-002',
          name: 'Today Patient 1',
          createdAt: todayLocal,
          registrationDate: todayLocal,
          updatedAt: todayLocal,
        ),
        PatientModel(
          id: 'p-today-2',
          patientNumber: 'D-001',
          name: 'Today Patient 2',
          createdAt: todayLocal.add(const Duration(hours: 1)),
          registrationDate: todayLocal.add(const Duration(hours: 1)),
          updatedAt: todayLocal,
        ),
      ];

      final scheduledPatients = [
        ScheduledPatientEntry(
          patient: patients[1],
          todayAppointments: [
            AppointmentModel(
              id: 'appt-1',
              patientId: 'p-today-1',
              patientName: 'Today Patient 1',
              appointmentDate: todayLocal,
              appointmentTime: '10:00',
              department: 'eye',
              status: 'scheduled',
              createdAt: todayLocal,
              updatedAt: todayLocal,
            ),
            AppointmentModel(
              id: 'appt-2',
              patientId: 'p-today-1',
              patientName: 'Today Patient 1',
              appointmentDate: todayLocal,
              appointmentTime: '14:00',
              department: 'eye',
              status: 'scheduled',
              createdAt: todayLocal,
              updatedAt: todayLocal,
            ),
          ],
        ),
        ScheduledPatientEntry(
          patient: patients[2],
          todayAppointments: [
            AppointmentModel(
              id: 'appt-3',
              patientId: 'p-today-2',
              patientName: 'Today Patient 2',
              appointmentDate: todayLocal,
              appointmentTime: '11:00',
              department: 'dental',
              status: 'scheduled',
              createdAt: todayLocal,
              updatedAt: todayLocal,
            ),
          ],
        ),
      ];

      await tester.pumpWidget(
        ProviderScope(
          overrides: [
            patientsProvider.overrideWith(
              (ref) => _FakePatientsNotifier(AsyncValue.data(patients)),
            ),
            todayScheduledPatientsProvider.overrideWith(
              (ref) => Future.value(scheduledPatients),
            ),
          ],
          child: const MaterialApp(
            home: Scaffold(
              body: PatientSummaryCard(),
            ),
          ),
        ),
      );

      await tester.pumpAndSettle();

      // 1. Verify "Today's Appointment Tickets" tile exists and shows 3 tickets
      expect(find.text("Today's Appointment Tickets"), findsOneWidget);
      expect(find.text('3'), findsOneWidget);
      expect(find.text('3 tickets · 2 patients'), findsOneWidget);

      // 2. Verify "New Registrations Today" tile exists and shows 2 (excluding the 1 yesterday patient)
      expect(find.text('New Registrations Today'), findsOneWidget);
      expect(find.text('2'), findsOneWidget);
      expect(find.text('2 registered today'), findsOneWidget);
    });
  });

  group('Fix 2A & 2B: Staff Checked In Today & Geo-bypass message', () {
    testWidgets('StaffAttendanceSummaryCard displays Staff Checked In Today and removes Morning/Evening shifts',
        (tester) async {
      tester.view.physicalSize = const Size(800, 800);
      tester.view.devicePixelRatio = 1.0;
      addTearDown(tester.view.resetPhysicalSize);

      final now = DateTime.now();
      final todayDate = DateTime(now.year, now.month, now.day);

      final staffList = <UserProfile>[
        UserProfile(
          id: 'staff-1',
          email: 'aarav@mkes.com',
          fullName: 'Dr. Aarav Patel',
          role: 'staff',
          department: 'eye',
          isActive: true,
          createdAt: DateTime.now(),
        ),
        UserProfile(
          id: 'staff-2',
          email: 'neha@mkes.com',
          fullName: 'Dr. Neha Sharma',
          role: 'staff',
          department: 'dental',
          isActive: true,
          createdAt: DateTime.now(),
        ),
      ];

      final attendanceRecords = [
        AttendanceRecord(
          id: 'rec-1',
          staffId: 'staff-1',
          staffName: 'Dr. Aarav Patel',
          date: todayDate,
          checkInTime: DateTime(todayDate.year, todayDate.month, todayDate.day, 9, 15),
          status: 'present',
          isLate: false,
          lateMinutes: 0,
        ),
        AttendanceRecord(
          id: 'rec-2',
          staffId: 'staff-2',
          staffName: 'Dr. Neha Sharma',
          date: todayDate,
          checkInTime: DateTime(todayDate.year, todayDate.month, todayDate.day, 9, 45),
          status: 'present',
          isLate: true,
          lateMinutes: 15,
        ),
      ];

      await tester.pumpWidget(
        ProviderScope(
          overrides: [
            usersProvider.overrideWith(
              (ref) => _FakeUsersNotifier(AsyncValue.data(staffList)),
            ),
            adminAttendanceForDateProvider(todayDate).overrideWith(
              (ref) => Future.value(attendanceRecords),
            ),
          ],
          child: MaterialApp(
            home: Scaffold(
              body: StaffAttendanceSummaryCard(targetDate: todayDate),
            ),
          ),
        ),
      );

      await tester.pumpAndSettle();

      // Verify "Staff Checked In Today" header & badge
      expect(find.text('Staff Checked In Today'), findsOneWidget);
      expect(find.text('2 Checked In'), findsOneWidget);

      // Verify actual checked-in staff members are displayed
      expect(find.text('Dr. Aarav Patel'), findsOneWidget);
      expect(find.text('Dr. Neha Sharma'), findsOneWidget);
      expect(find.text('On Time'), findsOneWidget);
      expect(find.text('Late (15m)'), findsOneWidget);

      // Verify Morning Shift & Evening Shift categories are completely removed
      expect(find.textContaining('Morning Shift'), findsNothing);
      expect(find.textContaining('Evening Shift'), findsNothing);
    });

    testWidgets('StaffMemberTile bypass message renders on 320px mobile viewport without overflow',
        (tester) async {
      tester.view.physicalSize = const Size(320, 600);
      tester.view.devicePixelRatio = 1.0;
      addTearDown(tester.view.resetPhysicalSize);

      final userWithBypass = UserProfile(
        id: 'staff-bypass',
        email: 'test@mkes.com',
        fullName: 'Dr. Test Staff Member Long Name',
        role: 'staff',
        department: 'eye',
        isActive: true,
        gpsBypassUntil: DateTime.now().add(const Duration(hours: 3)),
        createdAt: DateTime.now(),
      );

      await tester.pumpWidget(
        MaterialApp(
          home: Scaffold(
            body: StaffMemberTile(
              user: userWithBypass,
              todayAttendance: null,
            ),
          ),
        ),
      );

      await tester.pumpAndSettle();

      expect(tester.takeException(), isNull);
      expect(find.textContaining('Bypass Active'), findsOneWidget);
    });
  });

  group('Fix 4B: PO Details Dialog Mobile Optimization', () {
    testWidgets('PurchaseOrderDetailsDialog renders on 320px screen without overflow',
        (tester) async {
      tester.view.physicalSize = const Size(320, 640);
      tester.view.devicePixelRatio = 1.0;
      addTearDown(tester.view.resetPhysicalSize);

      final po = PurchaseOrder(
        id: 'po-123',
        purchaseOrderNumber: 'PO-2026-009988',
        vendorId: 'v-1',
        vendorName: 'Global Medical Supplies Pvt Ltd',
        vendorPhone: '+919876543210',
        orderDate: DateTime.now(),
        status: PurchaseOrderStatus.ordered,
        subtotal: 15000,
        totalAmount: 15000,
        items: [
          PurchaseOrderItem(
            id: 'line-1',
            purchaseOrderId: 'po-123',
            inventoryId: 'inv-1',
            inventoryName: 'Sterile Gauze Pads (Pack of 100)',
            quantity: 50,
            unitPrice: 300,
            totalAmount: 15000,
          ),
        ],
      );

      await tester.pumpWidget(
        ProviderScope(
          overrides: [
            purchaseOrdersProvider.overrideWith(
              (ref) => _FakePONotifier(AsyncValue.data([po])),
            ),
          ],
          child: MaterialApp(
            home: Scaffold(
              body: PurchaseOrderDetailsDialog(order: po),
            ),
          ),
        ),
      );

      await tester.pumpAndSettle();

      expect(tester.takeException(), isNull);
      expect(find.text('PO #PO-2026-009988'), findsOneWidget);
      expect(find.text('Global Medical Supplies Pvt Ltd'), findsOneWidget);
    });
  });

  group('Fix 1: Reports Section Mobile Responsiveness & No Overflow', () {
    testWidgets('ReportsMetricCard, DonutChart, and RatioBar render on 320px width with zero overflow',
        (tester) async {
      tester.view.physicalSize = const Size(320, 800);
      tester.view.devicePixelRatio = 1.0;
      addTearDown(tester.view.resetPhysicalSize);

      await tester.pumpWidget(
        MaterialApp(
          home: Scaffold(
            body: SingleChildScrollView(
              child: Column(
                children: [
                  const ReportsMetricCard(
                    title: 'Total Invoiced Sales',
                    value: '₹1,245,000',
                    subtitle: 'Revenue: ₹1,120,000 in selected period',
                    icon: Icons.account_balance_wallet_outlined,
                  ),
                  const SizedBox(height: 16),
                  ReportsDonutChart(
                    centerTitle: '52',
                    centerSubtitle: 'Total Visits',
                    segments: [
                      DonutSegment(label: 'Regular', value: 30, color: Colors.blue),
                      DonutSegment(label: 'Walk-in', value: 15, color: Colors.orange),
                      DonutSegment(label: 'Follow-up', value: 7, color: Colors.teal),
                    ],
                  ),
                  const SizedBox(height: 16),
                  const DepartmentRatioBar(
                    eyePercentage: 45.5,
                    dentalPercentage: 54.5,
                    eyeCount: 120,
                    dentalCount: 140,
                  ),
                ],
              ),
            ),
          ),
        ),
      );

      await tester.pumpAndSettle();

      expect(tester.takeException(), isNull);
      expect(find.text('Total Invoiced Sales'), findsOneWidget);
      expect(find.text('₹1,245,000'), findsOneWidget);
      expect(find.text('52'), findsOneWidget);
      expect(find.textContaining('Eye Care: 120'), findsOneWidget);
    });
  });
}
