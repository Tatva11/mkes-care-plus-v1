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
import 'package:mkes_care/features/dental/models/dental_lab_model.dart';
import 'package:mkes_care/features/dental/models/dental_treatment_model.dart';
import 'package:mkes_care/features/dental/providers/dental_lab_provider.dart';
import 'package:mkes_care/features/dental/providers/dental_treatment_provider.dart';
import 'package:mkes_care/features/dental/repositories/dental_lab_repository.dart';
import 'package:mkes_care/features/dental/repositories/dental_treatment_repository.dart';
import 'package:mkes_care/features/eye/models/eye_examination_model.dart';
import 'package:mkes_care/features/eye/models/eye_surgery_model.dart';
import 'package:mkes_care/features/eye/providers/eye_examination_provider.dart';
import 'package:mkes_care/features/eye/providers/eye_surgery_provider.dart';
import 'package:mkes_care/features/eye/repositories/eye_examination_repository.dart';
import 'package:mkes_care/features/eye/repositories/eye_surgery_repository.dart';
import 'package:mkes_care/features/patients/models/patient_attendance.dart';
import 'package:mkes_care/features/patients/models/patient_model.dart';
import 'package:mkes_care/features/patients/providers/patient_attendance_provider.dart';
import 'package:mkes_care/features/patients/providers/patients_provider.dart';
import 'package:mkes_care/features/patients/repositories/patient_repository.dart';
import 'package:mkes_care/features/patients/screens/patient_details_screen.dart';
import 'package:mkes_care/features/staff/models/shift_configuration.dart';
import 'package:mkes_care/features/staff/repositories/attendance_repository.dart';
import 'package:mkes_care/features/staff_portal/screens/staff_schedule_screen.dart';

// ── Fakes ────────────────────────────────────────────────────────────────────

class _FakeSupabaseClient extends Fake implements SupabaseClient {}

class _FakeAppointmentRepository extends Fake implements AppointmentRepository {
  List<AppointmentModel> appointments;
  _FakeAppointmentRepository(this.appointments);

  @override
  Future<List<AppointmentModel>> fetchTodayAppointments({
    String? doctorId,
    String? department,
  }) async =>
      appointments;

  @override
  Future<List<AppointmentModel>> fetchAppointments({
    String? department,
    DateTime? date,
    String? status,
    String? doctorId,
  }) async =>
      appointments;

  @override
  Future<void> updateStatus(String appointmentId, String newStatus) async {
    appointments = appointments.map((a) {
      if (a.id == appointmentId) {
        return a.copyWith(status: newStatus);
      }
      return a;
    }).toList();
  }

  @override
  Future<AppointmentModel> updateAppointment(
    String appointmentId,
    Map<String, dynamic> updates,
  ) async {
    final idx = appointments.indexWhere((a) => a.id == appointmentId);
    if (idx != -1) {
      final updated = appointments[idx].copyWith(
        notes: updates['notes'] ?? appointments[idx].notes,
        status: updates['status'] ?? appointments[idx].status,
      );
      appointments[idx] = updated;
      return updated;
    }
    throw Exception('Not found');
  }

  @override
  Future<List<AppointmentModel>> fetchPatientAppointments({
    required String patientId,
    String? department,
  }) async =>
      appointments.where((a) => a.patientId == patientId).toList();
}

class _FakeEyeExaminationRepository extends Fake
    implements EyeExaminationRepository {
  final List<EyeExaminationModel> exams;
  _FakeEyeExaminationRepository(this.exams);

  Future<List<EyeExaminationModel>> fetchExaminationsForPatient(
          String patientId) async =>
      exams.where((e) => e.patientId == patientId).toList();

  @override
  Future<EyeExaminationModel> createExamination(
      EyeExaminationModel record) async {
    exams.add(record);
    return record;
  }
}

class _FakeDentalTreatmentRepository extends Fake
    implements DentalTreatmentRepository {
  final List<DentalTreatmentModel> treatments;
  _FakeDentalTreatmentRepository(this.treatments);

  Future<List<DentalTreatmentModel>> fetchTreatmentsForPatient(
          String patientId) async =>
      treatments.where((t) => t.patientId == patientId).toList();

  @override
  Future<DentalTreatmentModel> createTreatment(
      DentalTreatmentModel record) async {
    treatments.add(record);
    return record;
  }
}

class _FakeDentalLabRepository extends Fake implements DentalLabRepository {
  @override
  Future<List<DentalLabModel>> fetchCases({
    String? status,
    String? patientId,
    String? searchQuery,
  }) async =>
      [];
}

class _FakeEyeSurgeryRepository extends Fake implements EyeSurgeryRepository {
  @override
  Future<List<EyeSurgeryModel>> fetchSurgeries({String? status}) async => [];
  @override
  Future<List<EyeSurgeryModel>> fetchSurgeriesForPatient(
          String patientId) async =>
      [];
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

class _FakePatientRepository extends Fake implements PatientRepository {
  final Map<String, PatientModel> patients;
  _FakePatientRepository(this.patients);

  Future<PatientModel?> fetchPatientById(String id) async => patients[id];

  Future<List<PatientAttendance>> fetchPatientAttendanceHistory(
          String patientId) async =>
      [];
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

void main() {
  TestWidgetsFlutterBinding.ensureInitialized();

  final fixedDate = DateTime.now();

  const testUser = User(
    id: 'staff-1',
    appMetadata: {},
    userMetadata: {},
    aud: 'authenticated',
    createdAt: '2026-01-01',
  );

  final staffProfile = ProfileModel(
    id: 'staff-1',
    email: 'staff@mkescare.com',
    fullName: 'Staff Nurse Geeta',
    role: 'staff',
    isActive: true,
    department: 'General',
    createdAt: fixedDate,
  );

  final mockPatientEye = PatientModel(
    id: 'pat-eye-001',
    patientNumber: 'P-1001',
    name: 'Ramesh Patel',
    mobile: '+91 98765 43210',
    department: 'eye',
    createdAt: fixedDate,
    updatedAt: fixedDate,
  );

  final mockPatientDental = PatientModel(
    id: 'pat-dent-002',
    patientNumber: 'P-1002',
    name: 'Priya Sharma',
    mobile: '+91 98765 43211',
    department: 'dental',
    createdAt: fixedDate,
    updatedAt: fixedDate,
  );

  group('1. AppointmentModel Clinical Exam Properties', () {
    test('hasClinicalExam returns false when notes are empty or null', () {
      final apt = AppointmentModel(
        id: 'apt-1',
        appointmentDate: fixedDate,
        appointmentTime: '09:00',
        appointmentType: 'regular',
        status: 'scheduled',
        createdAt: fixedDate,
        updatedAt: fixedDate,
        notes: null,
      );
      expect(apt.hasClinicalExam, isFalse);
      expect(apt.examinationReference, isNull);
    });

    test('hasClinicalExam returns true and parses reference for [EXAMINED: ...]', () {
      final apt = AppointmentModel(
        id: 'apt-2',
        appointmentDate: fixedDate,
        appointmentTime: '09:30',
        appointmentType: 'regular',
        status: 'waiting',
        createdAt: fixedDate,
        updatedAt: fixedDate,
        notes: 'Routine visit | [EXAMINED: EXAM-EYE-999]',
      );
      expect(apt.hasClinicalExam, isTrue);
      expect(apt.examinationReference, equals('EXAM-EYE-999'));
    });

    test('hasClinicalExam returns true for [EXAM_RECORDED] and [CLINICAL_EXAM]', () {
      final apt1 = AppointmentModel(
        id: 'apt-3',
        appointmentDate: fixedDate,
        appointmentTime: '10:00',
        appointmentType: 'regular',
        status: 'waiting',
        createdAt: fixedDate,
        updatedAt: fixedDate,
        notes: '[EXAM_RECORDED: DENT-TRT-55]',
      );
      expect(apt1.hasClinicalExam, isTrue);
      expect(apt1.examinationReference, equals('DENT-TRT-55'));

      final apt2 = AppointmentModel(
        id: 'apt-4',
        appointmentDate: fixedDate,
        appointmentTime: '10:30',
        appointmentType: 'regular',
        status: 'waiting',
        createdAt: fixedDate,
        updatedAt: fixedDate,
        notes: '[CLINICAL_EXAM]',
      );
      expect(apt2.hasClinicalExam, isTrue);
    });
  });

  group('2. Staff Schedule Screen: Action Button State Machine', () {
    Widget buildScheduleWithAppointments(List<AppointmentModel> appointments) {
      final fakeAptRepo = _FakeAppointmentRepository(appointments);
      final fakeDepartments = [
        const Department(id: 'eye', name: 'Eye Clinic', isActive: true),
        const Department(id: 'dental', name: 'Dental Clinic', isActive: true),
      ];

      return ProviderScope(
        overrides: [
          supabaseProvider.overrideWithValue(_FakeSupabaseClient()),
          appointmentRepositoryProvider.overrideWithValue(fakeAptRepo),
          currentUserProvider.overrideWithValue(testUser),
          currentUserRoleProvider.overrideWith((ref) async => 'staff'),
          currentProfileProvider.overrideWith((ref) async => staffProfile),
          eyeSurgeryRepositoryProvider.overrideWithValue(_FakeEyeSurgeryRepository()),
          attendanceRepositoryProvider.overrideWithValue(_FakeAttendanceRepository()),
          departmentsProvider.overrideWith((ref) => _FixedDepartmentsNotifier(fakeDepartments)),
        ],
        child: const MaterialApp(
          home: Scaffold(
            body: StaffScheduleScreen(),
          ),
        ),
      );
    }

    testWidgets('Unmarked patient shows "Mark Present" button, NO Billing or Record Exam', (tester) async {
      tester.view.physicalSize = const Size(1024, 768);
      tester.view.devicePixelRatio = 1.0;
      addTearDown(tester.view.resetPhysicalSize);

      final unconfirmedApt = AppointmentModel(
        id: 'apt-unconfirmed',
        patientId: 'pat-eye-001',
        patientName: 'Ramesh Patel',
        patientNumber: 'P-1001',
        department: 'eye',
        appointmentDate: fixedDate,
        appointmentTime: '10:00',
        appointmentType: 'regular',
        status: 'confirmed',
        createdAt: fixedDate,
        updatedAt: fixedDate,
      );

      await tester.pumpWidget(buildScheduleWithAppointments([unconfirmedApt]));
      await tester.pump();

      // Must show "Mark Present"
      expect(find.text('Mark Present'), findsOneWidget);
      // Must NOT show "Bill Patient"
      expect(find.text('Bill Patient'), findsNothing);
      // Must NOT show "No-Charge Visit"
      expect(find.text('No-Charge Visit'), findsNothing);
      // Must NOT show "Record Vitals & Exam"
      expect(find.text('Record Vitals & Exam'), findsNothing);
    });

    testWidgets('Patient marked present WITHOUT exam shows "Record Vitals & Exam", GATES Billing', (tester) async {
      tester.view.physicalSize = const Size(1024, 768);
      tester.view.devicePixelRatio = 1.0;
      addTearDown(tester.view.resetPhysicalSize);

      final presentUnexaminedApt = AppointmentModel(
        id: 'apt-present-no-exam',
        patientId: 'pat-eye-001',
        patientName: 'Ramesh Patel',
        patientNumber: 'P-1001',
        department: 'eye',
        appointmentDate: fixedDate,
        appointmentTime: '10:00',
        appointmentType: 'regular',
        status: 'waiting', // Present
        createdAt: fixedDate,
        updatedAt: fixedDate,
      );

      await tester.pumpWidget(buildScheduleWithAppointments([presentUnexaminedApt]));
      await tester.pump();

      // Must NOT show "Mark Present"
      expect(find.text('Mark Present'), findsNothing);
      // Must show "Record Vitals & Exam"
      expect(find.text('Record Vitals & Exam'), findsOneWidget);
      // STRICT REQUIREMENT: Must NOT show "Bill Patient" before examination
      expect(find.text('Bill Patient'), findsNothing);
      // STRICT REQUIREMENT: Must NOT show "No-Charge Visit" before examination
      expect(find.text('No-Charge Visit'), findsNothing);
    });

    testWidgets('Patient with Exam recorded reveals "Exam Recorded", "Bill Patient", and "No-Charge Visit"', (tester) async {
      tester.view.physicalSize = const Size(1024, 768);
      tester.view.devicePixelRatio = 1.0;
      addTearDown(tester.view.resetPhysicalSize);

      final examinedApt = AppointmentModel(
        id: 'apt-examined',
        patientId: 'pat-eye-001',
        patientName: 'Ramesh Patel',
        patientNumber: 'P-1001',
        department: 'eye',
        appointmentDate: fixedDate,
        appointmentTime: '10:00',
        appointmentType: 'regular',
        status: 'waiting', // Present
        notes: '[EXAMINED: EXAM-001]',
        createdAt: fixedDate,
        updatedAt: fixedDate,
      );

      await tester.pumpWidget(buildScheduleWithAppointments([examinedApt]));
      await tester.pump();

      // Shows "Exam Recorded" indicator
      expect(find.text('Exam Recorded'), findsOneWidget);
      // Now reveals "Bill Patient"
      expect(find.text('Bill Patient'), findsOneWidget);
      // Now reveals "No-Charge Visit"
      expect(find.text('No-Charge Visit'), findsOneWidget);
      // Does not show "Record Vitals & Exam"
      expect(find.text('Record Vitals & Exam'), findsNothing);
    });

    testWidgets('Billed patient displays Billed reference badge', (tester) async {
      tester.view.physicalSize = const Size(1024, 768);
      tester.view.devicePixelRatio = 1.0;
      addTearDown(tester.view.resetPhysicalSize);

      final billedApt = AppointmentModel(
        id: 'apt-billed',
        patientId: 'pat-eye-001',
        patientName: 'Ramesh Patel',
        patientNumber: 'P-1001',
        department: 'eye',
        appointmentDate: fixedDate,
        appointmentTime: '10:00',
        appointmentType: 'regular',
        status: 'waiting',
        notes: '[EXAMINED: EXAM-001] | [BILLED: INV-2026-001]',
        createdAt: fixedDate,
        updatedAt: fixedDate,
      );

      await tester.pumpWidget(buildScheduleWithAppointments([billedApt]));
      await tester.pump();

      expect(find.text('Exam Recorded'), findsOneWidget);
      expect(find.text('Billed (INV-2026-001)'), findsOneWidget);
      expect(find.text('Bill Patient'), findsNothing);
    });
  });

  group('3. Patient Details Screen: Active Visit Banner & Flow', () {
    Widget buildPatientDetailsWidget({
      required PatientModel patient,
      AppointmentModel? pendingAppointment,
    }) {
      final fakePatientRepo = _FakePatientRepository({patient.id: patient});
      final fakeEyeExamRepo = _FakeEyeExaminationRepository([]);
      final fakeDentRepo = _FakeDentalTreatmentRepository([]);

      return ProviderScope(
        overrides: [
          supabaseProvider.overrideWithValue(_FakeSupabaseClient()),
          patientRepositoryProvider.overrideWithValue(fakePatientRepo),
          patientDetailsProvider(patient.id).overrideWith((ref) async => patient),
          eyeExaminationRepositoryProvider.overrideWithValue(fakeEyeExamRepo),
          dentalTreatmentRepositoryProvider.overrideWithValue(fakeDentRepo),
          eyeSurgeryRepositoryProvider.overrideWithValue(_FakeEyeSurgeryRepository()),
          dentalLabRepositoryProvider.overrideWithValue(_FakeDentalLabRepository()),
          currentUserRoleProvider.overrideWith((ref) async => 'staff'),
          patientAttendanceHistoryProvider(patient.id)
              .overrideWith((ref) async => []),
          eyeExaminationsForPatientProvider(patient.id)
              .overrideWith((ref) async => []),
          dentalTreatmentsForPatientProvider(patient.id)
              .overrideWith((ref) async => []),
          patientDentalLabCasesProvider(patient.id)
              .overrideWith((ref) => []),
          eyeSurgeriesForPatientProvider(patient.id)
              .overrideWith((ref) async => []),
        ],
        child: MaterialApp(
          home: PatientDetailsScreen(
            patientId: patient.id,
            pendingAppointment: pendingAppointment,
          ),
        ),
      );
    }

    testWidgets('Renders Mandatory Clinical Examination banner for unexamined active visit', (tester) async {
      tester.view.physicalSize = const Size(1024, 768);
      tester.view.devicePixelRatio = 1.0;
      addTearDown(tester.view.resetPhysicalSize);

      final pendingApt = AppointmentModel(
        id: 'apt-active-eye',
        patientId: mockPatientEye.id,
        patientName: mockPatientEye.name,
        patientNumber: mockPatientEye.patientNumber,
        department: 'eye',
        appointmentDate: fixedDate,
        appointmentTime: '11:00',
        appointmentType: 'regular',
        status: 'waiting',
        createdAt: fixedDate,
        updatedAt: fixedDate,
      );

      await tester.pumpWidget(buildPatientDetailsWidget(
        patient: mockPatientEye,
        pendingAppointment: pendingApt,
      ));
      await tester.pumpAndSettle();

      // Check banner title
      expect(find.text('Mandatory Clinical Examination'), findsOneWidget);
      // Check banner instructions
      expect(
        find.textContaining('vitals, visual acuity, and clinical examination'),
        findsOneWidget,
      );
      // Check action button on banner
      expect(find.byKey(const Key('record_exam_from_banner_button')), findsOneWidget);
      expect(find.text('Record Vitals & Exam'), findsOneWidget);
      // "Proceed to Billing" must NOT be shown yet
      expect(find.byKey(const Key('proceed_to_billing_button')), findsNothing);
    });

    testWidgets('Renders Proceed to Billing banner for already examined active visit', (tester) async {
      tester.view.physicalSize = const Size(1024, 768);
      tester.view.devicePixelRatio = 1.0;
      addTearDown(tester.view.resetPhysicalSize);

      final examinedPendingApt = AppointmentModel(
        id: 'apt-active-examined',
        patientId: mockPatientEye.id,
        patientName: mockPatientEye.name,
        patientNumber: mockPatientEye.patientNumber,
        department: 'eye',
        appointmentDate: fixedDate,
        appointmentTime: '11:00',
        appointmentType: 'regular',
        status: 'waiting',
        notes: '[EXAMINED: EXAM-444]',
        createdAt: fixedDate,
        updatedAt: fixedDate,
      );

      await tester.pumpWidget(buildPatientDetailsWidget(
        patient: mockPatientEye,
        pendingAppointment: examinedPendingApt,
      ));
      await tester.pumpAndSettle();

      // Check banner title
      expect(find.text('Clinical Examination Recorded'), findsOneWidget);
      // Check banner action button
      expect(find.byKey(const Key('proceed_to_billing_button')), findsOneWidget);
      expect(find.text('Proceed to Billing'), findsOneWidget);
    });

    testWidgets('Renders Dental Record Treatment on active visit banner for dental patient', (tester) async {
      tester.view.physicalSize = const Size(1024, 768);
      tester.view.devicePixelRatio = 1.0;
      addTearDown(tester.view.resetPhysicalSize);

      final dentalPendingApt = AppointmentModel(
        id: 'apt-active-dental',
        patientId: mockPatientDental.id,
        patientName: mockPatientDental.name,
        patientNumber: mockPatientDental.patientNumber,
        department: 'dental',
        appointmentDate: fixedDate,
        appointmentTime: '14:00',
        appointmentType: 'regular',
        status: 'waiting',
        createdAt: fixedDate,
        updatedAt: fixedDate,
      );

      await tester.pumpWidget(buildPatientDetailsWidget(
        patient: mockPatientDental,
        pendingAppointment: dentalPendingApt,
      ));
      await tester.pumpAndSettle();

      expect(find.text('Mandatory Clinical Examination'), findsOneWidget);
      expect(
        find.textContaining('dental diagnosis and treatment details'),
        findsOneWidget,
      );
      expect(find.byKey(const Key('record_exam_from_banner_button')), findsOneWidget);
      expect(
        find.descendant(
          of: find.byKey(const Key('record_exam_from_banner_button')),
          matching: find.text('Record Treatment'),
        ),
        findsOneWidget,
      );
    });

    testWidgets('Does NOT render active visit banner when pendingAppointment is null', (tester) async {
      tester.view.physicalSize = const Size(1024, 768);
      tester.view.devicePixelRatio = 1.0;
      addTearDown(tester.view.resetPhysicalSize);

      await tester.pumpWidget(buildPatientDetailsWidget(
        patient: mockPatientEye,
        pendingAppointment: null,
      ));
      await tester.pumpAndSettle();

      expect(find.text('Mandatory Clinical Examination'), findsNothing);
      expect(find.text('Clinical Examination Recorded'), findsNothing);
      expect(find.byKey(const Key('record_exam_from_banner_button')), findsNothing);
      expect(find.byKey(const Key('proceed_to_billing_button')), findsNothing);
    });
  });
}
