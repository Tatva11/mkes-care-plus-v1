import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:flutter_test/flutter_test.dart';

import 'package:mkes_care/features/admin/widgets/patient_summary_card.dart';
import 'package:mkes_care/features/appointments/models/appointment_model.dart';
import 'package:mkes_care/features/appointments/widgets/appointment_form_dialog.dart';
import 'package:mkes_care/features/eye/widgets/eye_surgery_form_dialog.dart';
import 'package:mkes_care/features/patients/models/patient_model.dart';
import 'package:mkes_care/features/patients/providers/patients_provider.dart';

class TestPatientsNotifier extends StateNotifier<AsyncValue<List<PatientModel>>>
    implements PatientsNotifier {
  TestPatientsNotifier(super.initial);

  @override
  Future<void> loadPatients({String? department, String? search}) async {}

  @override
  Future<PatientModel> createPatient(PatientModel newPatient) async =>
      newPatient;

  @override
  Future<PatientModel> updatePatient(PatientModel updatedPatient) async =>
      updatedPatient;
}

void main() {
  TestWidgetsFlutterBinding.ensureInitialized();

  final now = DateTime.now();
  final todayPatientEye = PatientModel(
    id: 'pat-001',
    patientNumber: 'EYE-101',
    name: 'Aarav Patel',
    dob: DateTime(1990, 1, 1),
    mobile: '9876543210',
    department: 'eye',
    createdAt: now,
    updatedAt: now,
  );

  final todayPatientDental = PatientModel(
    id: 'pat-002',
    patientNumber: 'DENT-201',
    name: 'Diya Sharma',
    dob: DateTime(1995, 5, 12),
    mobile: '9876543211',
    department: 'dental',
    createdAt: now,
    updatedAt: now,
  );

  final pastPatientEye = PatientModel(
    id: 'pat-003',
    patientNumber: 'EYE-003',
    name: 'Kabir Mehta',
    dob: DateTime(1980, 8, 20),
    mobile: '9876543212',
    department: 'eye',
    createdAt: now.subtract(const Duration(days: 45)),
    updatedAt: now.subtract(const Duration(days: 45)),
  );

  final scheduledAppt = AppointmentModel(
    id: 'appt-001',
    patientId: 'pat-001',
    department: 'eye',
    appointmentDate: now,
    appointmentTime: '10:00:00',
    appointmentType: 'regular',
    status: 'scheduled',
    createdAt: now,
    updatedAt: now,
  );

  group('FEATURE 1: Patient Summary Card Tests', () {
    testWidgets(
        'Displays correct counts, registration metrics, and department split',
        (tester) async {
      await tester.pumpWidget(
        ProviderScope(
          overrides: [
            patientsProvider.overrideWith(
              (ref) => TestPatientsNotifier(
                AsyncValue.data([
                  todayPatientEye,
                  todayPatientDental,
                  pastPatientEye,
                ]),
              ),
            ),
            todayScheduledPatientsProvider.overrideWith(
              (ref) => Future.value([
                ScheduledPatientEntry(
                  patient: todayPatientEye,
                  todayAppointments: [scheduledAppt],
                ),
              ]),
            ),
          ],
          child: const MaterialApp(
            home: Scaffold(
              body: SingleChildScrollView(
                child: PatientSummaryCard(),
              ),
            ),
          ),
        ),
      );

      await tester.pumpAndSettle();

      // Today's Scheduled Patients
      expect(find.text('Scheduled Today'), findsOneWidget);
      expect(find.text('1'), findsWidgets); // 1 scheduled patient

      // New Registrations Today
      expect(find.text('New Registrations'), findsOneWidget);
      expect(find.text('2'), findsWidgets); // 2 registered today

      // Department distribution for today's appointments
      expect(find.text('Eye Clinic: 1'), findsOneWidget);
      expect(find.text('Dental Clinic: 0'), findsOneWidget);
    });

    testWidgets(
        'Displays graceful empty state when there are zero patients and zero appointments',
        (tester) async {
      await tester.pumpWidget(
        ProviderScope(
          overrides: [
            patientsProvider.overrideWith(
              (ref) => TestPatientsNotifier(const AsyncValue.data([])),
            ),
            todayScheduledPatientsProvider
                .overrideWith((ref) => Future.value([])),
          ],
          child: const MaterialApp(
            home: Scaffold(
              body: SingleChildScrollView(
                child: PatientSummaryCard(),
              ),
            ),
          ),
        ),
      );

      await tester.pumpAndSettle();

      expect(
          find.text('No patient activity scheduled for today'), findsOneWidget);
    });

    testWidgets('Handles provider error state gracefully with retry button',
        (tester) async {
      await tester.pumpWidget(
        ProviderScope(
          overrides: [
            patientsProvider.overrideWith(
              (ref) => TestPatientsNotifier(
                AsyncValue.error(
                  Exception('Failed to load clinic patients'),
                  StackTrace.empty,
                ),
              ),
            ),
            todayScheduledPatientsProvider.overrideWith(
              (ref) => Future.value([]),
            ),
          ],
          child: const MaterialApp(
            home: Scaffold(
              body: SingleChildScrollView(
                child: PatientSummaryCard(),
              ),
            ),
          ),
        ),
      );

      await tester.pumpAndSettle();

      expect(find.text('Unable to load patient data'), findsOneWidget);
      expect(find.text('Retry'), findsOneWidget);
    });

    testWidgets('Navigation action triggers navigation to PatientListScreen',
        (tester) async {
      var navigated = false;
      await tester.pumpWidget(
        ProviderScope(
          overrides: [
            patientsProvider.overrideWith(
              (ref) => TestPatientsNotifier(
                AsyncValue.data([todayPatientEye]),
              ),
            ),
            todayScheduledPatientsProvider.overrideWith(
              (ref) => Future.value([
                ScheduledPatientEntry(
                  patient: todayPatientEye,
                  todayAppointments: [scheduledAppt],
                ),
              ]),
            ),
          ],
          child: MaterialApp(
            home: Scaffold(
              body: SingleChildScrollView(
                child: PatientSummaryCard(
                  onNavigateToPatients: () => navigated = true,
                ),
              ),
            ),
          ),
        ),
      );

      await tester.pumpAndSettle();

      final manageBtn = find.text('Manage Patients');
      expect(manageBtn, findsOneWidget);

      await tester.tap(manageBtn);
      await tester.pumpAndSettle();

      expect(navigated, isTrue);
    });

    testWidgets('Renders cleanly on a small screen (360x640) without overflow',
        (tester) async {
      tester.view.physicalSize = const Size(360, 640);
      tester.view.devicePixelRatio = 1.0;
      addTearDown(tester.view.resetPhysicalSize);
      addTearDown(tester.view.resetDevicePixelRatio);

      await tester.pumpWidget(
        ProviderScope(
          overrides: [
            patientsProvider.overrideWith(
              (ref) => TestPatientsNotifier(
                AsyncValue.data([todayPatientEye, todayPatientDental]),
              ),
            ),
            todayScheduledPatientsProvider.overrideWith(
              (ref) => Future.value([
                ScheduledPatientEntry(
                  patient: todayPatientEye,
                  todayAppointments: [scheduledAppt],
                ),
              ]),
            ),
          ],
          child: const MaterialApp(
            home: Scaffold(
              body: SingleChildScrollView(
                child: PatientSummaryCard(),
              ),
            ),
          ),
        ),
      );

      await tester.pumpAndSettle();
      expect(tester.takeException(), isNull);
    });
  });

  group('FEATURE 2: Surgery Appointment Type & Eye Surgery Integration Tests',
      () {
    test(
        'availableAppointmentTypes contains surgery and preserves existing types',
        () {
      final types = AppointmentFormDialog.availableAppointmentTypes;
      final ids = types.map((t) => t.id).toList();

      expect(ids, contains('regular'));
      expect(ids, contains('walk_in'));
      expect(ids, contains('follow_up'));
      expect(ids, contains('surgery'));

      final surgeryOption = types.firstWhere((t) => t.id == 'surgery');
      expect(surgeryOption.label, equals('Surgery'));
    });

    test(
        'normalizeAppointmentType normalizes surgery and preserves existing values',
        () {
      expect(AppointmentFormDialog.normalizeAppointmentType('surgery'),
          equals('surgery'));
      expect(AppointmentFormDialog.normalizeAppointmentType('Surgery'),
          equals('surgery'));
      expect(AppointmentFormDialog.normalizeAppointmentType('eye surgery'),
          equals('surgery'));
      expect(AppointmentFormDialog.normalizeAppointmentType('eye_surgery'),
          equals('surgery'));
      expect(AppointmentFormDialog.normalizeAppointmentType('regular'),
          equals('regular'));
      expect(AppointmentFormDialog.normalizeAppointmentType('walk_in'),
          equals('walk_in'));
      expect(AppointmentFormDialog.normalizeAppointmentType('walk-in'),
          equals('walk_in'));
      expect(AppointmentFormDialog.normalizeAppointmentType('follow_up'),
          equals('follow_up'));
      expect(AppointmentFormDialog.normalizeAppointmentType('follow-up'),
          equals('follow_up'));
      expect(AppointmentFormDialog.normalizeAppointmentType('unknown'),
          equals('unknown'));
      expect(AppointmentFormDialog.normalizeAppointmentType(null),
          equals('regular'));
    });

    test('AppointmentModel.typeLabel accurately formats surgery as Eye Surgery',
        () {
      final surgeryApt = AppointmentModel(
        id: 'apt-surg-1',
        patientId: 'pat-001',
        department: 'eye',
        appointmentDate: DateTime(2026, 10, 20),
        appointmentTime: '09:00:00',
        appointmentType: 'surgery',
        status: 'scheduled',
        createdAt: DateTime.now(),
        updatedAt: DateTime.now(),
      );

      expect(surgeryApt.typeLabel, equals('Eye Surgery'));

      final followUpApt = AppointmentModel(
        id: 'apt-fu-1',
        patientId: 'pat-001',
        department: 'eye',
        appointmentDate: DateTime(2026, 10, 22),
        appointmentTime: '10:00:00',
        appointmentType: 'follow_up',
        status: 'scheduled',
        createdAt: DateTime.now(),
        updatedAt: DateTime.now(),
      );

      expect(followUpApt.typeLabel, equals('Follow-Up Visit'));
    });

    testWidgets(
        'EyeSurgeryFormDialog receives and applies initial parameters from appointment workflow',
        (tester) async {
      final scheduledDate = DateTime(2026, 11, 15);
      const scheduledTime = TimeOfDay(hour: 11, minute: 45);

      final dialog = EyeSurgeryFormDialog(
        initialPatientNumber: 'EYE-101',
        initialSurgeryDate: scheduledDate,
        initialSurgeryTime: scheduledTime,
        initialRemarks: 'Referred from routine consultation',
      );

      expect(dialog.initialPatientNumber, equals('EYE-101'));
      expect(dialog.initialSurgeryDate, equals(scheduledDate));
      expect(dialog.initialSurgeryTime, equals(scheduledTime));
      expect(
          dialog.initialRemarks, equals('Referred from routine consultation'));
      expect(dialog.existingSurgery, isNull);
    });
  });
}
