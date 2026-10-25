import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:supabase_flutter/supabase_flutter.dart';

import 'package:mkes_care/core/providers/supabase_provider.dart';
import 'package:mkes_care/features/appointments/models/appointment_model.dart';
import 'package:mkes_care/features/appointments/repositories/appointment_repository.dart';
import 'package:mkes_care/features/auth/models/profile_model.dart';
import 'package:mkes_care/features/auth/providers/auth_provider.dart';
import 'package:mkes_care/features/department/models/department.dart';
import 'package:mkes_care/features/department/providers/departments_provider.dart';
import 'package:mkes_care/features/department/repositories/department_repository.dart';
import 'package:mkes_care/features/eye/models/eye_surgery_model.dart';
import 'package:mkes_care/features/eye/providers/eye_surgery_provider.dart';
import 'package:mkes_care/features/eye/repositories/eye_surgery_repository.dart';
import 'package:mkes_care/features/staff/models/shift_configuration.dart';
import 'package:mkes_care/features/staff/models/task_item.dart';
import 'package:mkes_care/features/staff/providers/task_provider.dart';
import 'package:mkes_care/features/staff/repositories/attendance_repository.dart';
import 'package:mkes_care/features/staff/repositories/task_repository.dart';
import 'package:mkes_care/features/staff_portal/screens/staff_schedule_screen.dart';
import 'package:mkes_care/features/staff_portal/screens/staff_tasks_screen.dart';

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
}

class _FixedDepartmentsNotifier extends DepartmentsNotifier {
  _FixedDepartmentsNotifier(List<Department> initial)
      : super(DepartmentRepository(SupabaseClient(
          'https://example.supabase.co',
          'key',
          authOptions: const AuthClientOptions(autoRefreshToken: false),
        ))) {
    state = AsyncData(initial);
  }

  @override
  Future<void> fetchDepartments() async {}
}

class _FakeAppointmentRepository extends Fake implements AppointmentRepository {
  final List<AppointmentModel> appointments;
  _FakeAppointmentRepository(this.appointments);

  @override
  Future<List<AppointmentModel>> fetchTodayAppointments(
      {String? doctorId, String? department}) async {
    return appointments;
  }

  @override
  Future<List<AppointmentModel>> fetchAppointments({
    DateTime? date,
    String? doctorId,
    String? department,
    String? status,
  }) async {
    return appointments;
  }
}

class _FakeEyeSurgeryRepository extends Fake implements EyeSurgeryRepository {
  final List<EyeSurgeryModel> surgeries;
  _FakeEyeSurgeryRepository(this.surgeries);

  @override
  Future<List<EyeSurgeryModel>> fetchSurgeries({String? status}) async =>
      surgeries;
}

class _FakeAttendanceRepository extends Fake implements AttendanceRepository {
  @override
  Future<List<ShiftConfiguration>> fetchShiftConfigurations() async => const [
        ShiftConfiguration.defaultMorning,
        ShiftConfiguration.defaultAfternoon,
      ];

  @override
  Future<String?> fetchStaffShiftAssignment(String staffId,
          {DateTime? forDate}) async =>
      'morning';
}

class _FakeSupabaseClient extends Fake implements SupabaseClient {}

void main() {
  TestWidgetsFlutterBinding.ensureInitialized();

  final fakeSupabase = _FakeSupabaseClient();

  final testUser = const User(
    id: 'staff-1',
    appMetadata: {},
    userMetadata: {},
    aud: 'authenticated',
    createdAt: '2026-01-01',
  );

  final now = DateTime.now();
  final overdueYesterday = now.subtract(const Duration(days: 1));

  final testTasks = [
    TaskItem(
      id: 'task-1',
      title: 'Sterilize instruments for Eye Clinic',
      description: 'Prepare autoclave cycle and verify chemical indicators',
      assignedTo: 'staff-1',
      dueDate: overdueYesterday,
      priority: 'high',
      status: 'pending',
      createdAt: overdueYesterday,
      updatedAt: overdueYesterday,
    ),
    TaskItem(
      id: 'task-2',
      title: 'Restock Dental consumables and PPE',
      description: 'Check gloves, masks, and suction tips in Dental Room 2',
      assignedTo: 'staff-1',
      dueDate: now,
      priority: 'medium',
      status: 'pending',
      createdAt: now,
      updatedAt: now,
    ),
    TaskItem(
      id: 'task-surg',
      title: 'Eye Surgery Prep — Ramesh Patel',
      description: '10:00 AM · Cataract Surgery — Left Eye',
      assignedTo: 'staff-1',
      dueDate: now,
      priority: 'critical',
      status: 'pending',
      createdAt: now,
      updatedAt: now,
      relatedSurgeryId: 'surg-1',
    ),
  ];

  final testAppointments = [
    AppointmentModel(
      id: 'appt-1',
      patientName: 'Sunita Sharma with a Very Long Patient Name',
      patientNumber: 'EYE-1002',
      department: 'eye',
      appointmentDate: now,
      appointmentTime: '10:30',
      appointmentType: 'consultation',
      status: 'waiting',
      doctorName: 'Dr Mitesh Jain',
      isVisitingDoctor: true,
      notes: '[BILLED: INV-2026-001]',
      createdAt: now,
      updatedAt: now,
    ),
    AppointmentModel(
      id: 'appt-2',
      patientName: 'Rajesh K',
      patientNumber: 'DEN-2005',
      department: 'dental',
      appointmentDate: now,
      appointmentTime: '11:15',
      appointmentType: 'consultation',
      status: 'scheduled',
      doctorName: 'Dr Nimisha',
      createdAt: now,
      updatedAt: now,
    ),
  ];

  final List<EyeSurgeryModel> testSurgeries = [
    EyeSurgeryModel(
      id: 'surg-1',
      patientId: 'patient-101',
      patientName: 'Ramesh Patel with Long Surname',
      patientNumber: 'EYE-SURG-101',
      preOpDate: now,
      surgeryDate: now,
      surgeryTime: '12:00',
      surgeryType: 'cataract',
      eyeSide: 'left',
      assignedStaffId: 'staff-1',
      status: 'pre_op',
      createdAt: now,
      updatedAt: now,
    ),
  ];

  final userProfile = ProfileModel(
    id: 'staff-1',
    fullName: 'Staff Member',
    email: 'staff@mkes.com',
    role: 'staff',
    department: 'all',
    isActive: true,
    createdAt: now,
  );

  final viewports = <double>[
    360.0,
    375.0,
    390.0,
    430.0,
    768.0,
    1024.0,
    1440.0,
  ];

  group('Staff Tasks Screen Responsive Layout across 7 Viewports', () {
    for (final width in viewports) {
      testWidgets('renders cleanly without overflow at width $width px',
          (tester) async {
        tester.view.devicePixelRatio = 1.0;
        tester.view.physicalSize = Size(width, 850);
        addTearDown(tester.view.resetPhysicalSize);
        addTearDown(tester.view.resetDevicePixelRatio);

        final container = ProviderContainer(overrides: [
          supabaseProvider.overrideWithValue(fakeSupabase),
          currentUserProvider.overrideWithValue(testUser),
          currentUserRoleProvider.overrideWith((ref) async => 'staff'),
          staffTasksProvider('staff-1')
              .overrideWith((ref) => _FixedStaffTasksNotifier(testTasks)),
        ]);
        addTearDown(container.dispose);

        await tester.pumpWidget(
          UncontrolledProviderScope(
            container: container,
            child: const MaterialApp(
              home: Scaffold(body: StaffTasksScreen()),
            ),
          ),
        );
        await tester.pumpAndSettle();

        // 1. Verify no RenderFlex overflow exceptions occurred
        expect(tester.takeException(), isNull);

        // 2. Verify Header title is rendered and shortcut row is removed
        expect(find.text('My Shift Tasks'), findsOneWidget);
        expect(find.byTooltip('Refresh tasks'), findsOneWidget);
        expect(find.widgetWithText(OutlinedButton, 'Inventory'), findsNothing);
        expect(find.widgetWithText(OutlinedButton, 'Vendors'), findsNothing);
        expect(
          find.widgetWithText(OutlinedButton, 'Purchase Orders'),
          findsNothing,
        );
        expect(find.widgetWithText(OutlinedButton, 'PO'), findsNothing);
        expect(find.widgetWithText(OutlinedButton, 'History'), findsNothing);

        // 3. Verify Date banner and pending badge are visible
        expect(find.textContaining('Operational Tasks'), findsOneWidget);
        expect(find.textContaining('pending'), findsWidgets);

        // 4. Verify Date selector buttons are rendered and visible
        expect(find.byKey(const Key('staff_tasks_prev_date_button')),
            findsOneWidget);
        expect(find.byKey(const Key('staff_tasks_date_picker_button')),
            findsOneWidget);
        expect(find.byKey(const Key('staff_tasks_next_date_button')),
            findsOneWidget);
        expect(
            find.byKey(const Key('staff_tasks_today_button')), findsOneWidget);

        // Date text is clearly visible within the date picker button
        final datePickerFinder =
            find.byKey(const Key('staff_tasks_date_picker_button'));
        final dateTextFinder =
            find.descendant(of: datePickerFinder, matching: find.byType(Text));
        expect(dateTextFinder, findsOneWidget);
        final dateText = tester.widget<Text>(dateTextFinder);
        expect(dateText.data, contains('Today'));

        // 5. Verify task titles are rendered
        expect(
            find.text('Sterilize instruments for Eye Clinic'), findsOneWidget);
        expect(find.text('Restock Dental consumables and PPE'), findsOneWidget);
        expect(find.text('Eye Surgery Prep — Ramesh Patel'), findsOneWidget);
      });
    }
  });

  group('Staff Schedule Screen Responsive Layout across 6 Viewports', () {
    for (final width in viewports) {
      testWidgets('renders cleanly without overflow at width $width px',
          (tester) async {
        tester.view.devicePixelRatio = 1.0;
        tester.view.physicalSize = Size(width, 950);
        addTearDown(tester.view.resetPhysicalSize);
        addTearDown(tester.view.resetDevicePixelRatio);

        final container = ProviderContainer(overrides: [
          supabaseProvider.overrideWithValue(fakeSupabase),
          currentUserProvider.overrideWithValue(testUser),
          currentUserRoleProvider.overrideWith((ref) async => 'staff'),
          currentProfileProvider.overrideWith((ref) async => userProfile),
          appointmentRepositoryProvider
              .overrideWithValue(_FakeAppointmentRepository(testAppointments)),
          eyeSurgeryRepositoryProvider
              .overrideWithValue(_FakeEyeSurgeryRepository(testSurgeries)),
          departmentsProvider
              .overrideWith((ref) => _FixedDepartmentsNotifier([])),
          attendanceRepositoryProvider
              .overrideWithValue(_FakeAttendanceRepository()),
        ]);
        addTearDown(container.dispose);

        await tester.pumpWidget(
          UncontrolledProviderScope(
            container: container,
            child: const MaterialApp(
              home: Scaffold(body: StaffScheduleScreen()),
            ),
          ),
        );
        await tester.pumpAndSettle();

        // 1. Verify no RenderFlex overflow exceptions occurred
        expect(tester.takeException(), isNull);

        // 2. Verify title and Book Appointment button are rendered
        expect(find.text('My Schedule'), findsOneWidget);
        expect(find.text('Book Appointment'), findsOneWidget);

        // 3. Verify Today's Schedule header and department dropdown
        expect(find.text("Today's Schedule"), findsOneWidget);
        expect(find.byKey(const Key('staff_schedule_department_dropdown')),
            findsOneWidget);

        // 4. Verify patient appointment cards are rendered with doctor names
        expect(find.textContaining('Sunita Sharma'), findsOneWidget);
        expect(find.text('Dr Mitesh Jain'), findsOneWidget);
        expect(find.textContaining('Rajesh K'), findsOneWidget);
        expect(find.text('Dr Nimisha'), findsOneWidget);

        // 5. Verify surgery card is rendered
        expect(find.textContaining('Ramesh Patel'), findsOneWidget);
        expect(find.text('View Surgery Details'), findsOneWidget);

        // 6. Verify touch targets on action buttons are at least 38px in height
        final billButtons = find.widgetWithText(FilledButton, 'Bill Patient');
        if (billButtons.evaluate().isNotEmpty) {
          final buttonSize = tester.getSize(billButtons.first);
          expect(buttonSize.height, greaterThanOrEqualTo(38.0));
        }

        final viewSurgeryButtons =
            find.widgetWithText(OutlinedButton, 'View Surgery Details');
        if (viewSurgeryButtons.evaluate().isNotEmpty) {
          final surgeryBtnSize = tester.getSize(viewSurgeryButtons.first);
          expect(surgeryBtnSize.height, greaterThanOrEqualTo(38.0));
        }
      });
    }
  });

  group('Staff Tasks Screen Date Selector Navigation and No-Truncation Tests', () {
    testWidgets('Previous, Next, and Today date controls are functional and date text is not truncated',
        (tester) async {
      tester.view.devicePixelRatio = 1.0;
      tester.view.physicalSize = const Size(360.0, 850.0);
      addTearDown(tester.view.resetPhysicalSize);
      addTearDown(tester.view.resetDevicePixelRatio);

      final container = ProviderContainer(overrides: [
        supabaseProvider.overrideWithValue(fakeSupabase),
        currentUserProvider.overrideWithValue(testUser),
        currentUserRoleProvider.overrideWith((ref) async => 'staff'),
        staffTasksProvider('staff-1')
            .overrideWith((ref) => _FixedStaffTasksNotifier(testTasks)),
      ]);
      addTearDown(container.dispose);

      await tester.pumpWidget(
        UncontrolledProviderScope(
          container: container,
          child: const MaterialApp(
            home: Scaffold(body: StaffTasksScreen()),
          ),
        ),
      );
      await tester.pumpAndSettle();

      final datePickerFinder =
          find.byKey(const Key('staff_tasks_date_picker_button'));
      final prevFinder =
          find.byKey(const Key('staff_tasks_prev_date_button'));
      final nextFinder =
          find.byKey(const Key('staff_tasks_next_date_button'));
      final todayFinder =
          find.byKey(const Key('staff_tasks_today_button'));

      expect(prevFinder, findsOneWidget);
      expect(nextFinder, findsOneWidget);
      expect(todayFinder, findsOneWidget);
      expect(datePickerFinder, findsOneWidget);

      // Verify date text contains "Today" and does not contain ellipsis "..."
      Text dateText = tester.widget<Text>(find.descendant(
          of: datePickerFinder, matching: find.byType(Text)));
      expect(dateText.data, contains('Today'));
      expect(dateText.data, isNot(contains('...')));

      // Tap previous day
      await tester.tap(prevFinder);
      await tester.pumpAndSettle();

      dateText = tester.widget<Text>(find.descendant(
          of: datePickerFinder, matching: find.byType(Text)));
      expect(dateText.data, isNot(contains('Today')));
      expect(dateText.data, isNot(contains('...')));

      // Tap Today button to jump back to today
      await tester.tap(todayFinder);
      await tester.pumpAndSettle();

      dateText = tester.widget<Text>(find.descendant(
          of: datePickerFinder, matching: find.byType(Text)));
      expect(dateText.data, contains('Today'));
      expect(dateText.data, isNot(contains('...')));

      // Tap next day
      await tester.tap(nextFinder);
      await tester.pumpAndSettle();

      dateText = tester.widget<Text>(find.descendant(
          of: datePickerFinder, matching: find.byType(Text)));
      expect(dateText.data, isNot(contains('Today')));
      expect(dateText.data, isNot(contains('...')));
    });
  });
}
