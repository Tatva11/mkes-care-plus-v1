import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:supabase_flutter/supabase_flutter.dart';

import 'package:mkes_care/core/providers/supabase_provider.dart';
import 'package:mkes_care/features/appointments/models/appointment_model.dart';
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
import 'package:mkes_care/features/patients/models/patient_model.dart';
import 'package:mkes_care/features/patients/providers/patient_attendance_provider.dart';
import 'package:mkes_care/features/patients/providers/patients_provider.dart';
import 'package:mkes_care/features/patients/repositories/patient_repository.dart';
import 'package:mkes_care/features/patients/screens/patient_details_screen.dart';
import 'package:mkes_care/features/patients/widgets/patient_form_dialog.dart';

class _FakeSupabaseClient extends Fake implements SupabaseClient {}

class _FakePatientRepo extends Fake implements PatientRepository {
  PatientModel? patient;
  _FakePatientRepo(this.patient);

  @override
  Future<PatientModel> getPatient(String id) async {
    if (patient != null && patient!.id == id) {
      return patient!;
    }
    throw Exception('Patient record not found (ID: $id). It may have been removed or access is restricted.');
  }

  @override
  Future<PatientModel> updatePatient(PatientModel updated) async {
    patient = updated;
    return updated;
  }
}

class _FakeDeptRepo extends Fake implements DepartmentRepository {
  @override
  Future<List<Department>> fetchDepartments() async => [
        const Department(id: 'eye-dept', name: 'Eye Clinic', isActive: true),
        const Department(id: 'dental-dept', name: 'Dental Clinic', isActive: true),
      ];
}

class _FakeEyeExamRepo extends Fake implements EyeExaminationRepository {
  @override
  Future<List<EyeExaminationModel>> fetchExaminations({
    String? patientId,
    String? appointmentId,
  }) async => [];
}

class _FakeDentalTreatmentRepo extends Fake implements DentalTreatmentRepository {
  @override
  Future<List<DentalTreatmentModel>> fetchTreatments({
    String? patientId,
    String? appointmentId,
    String? dentalLabCaseId,
  }) async => [];
}

void main() {
  final fixedDate = DateTime(2026, 11, 2);

  final testPatient = PatientModel(
    id: 'pat-12345',
    patientNumber: 'E-1001',
    name: 'Suresh Kumar',
    mobile: '9876543210',
    department: 'eye',
    dob: DateTime(1985, 6, 15),
    address: '42 MG Road, Mumbai',
    reference: 'Walk-in',
    createdAt: fixedDate,
    updatedAt: fixedDate,
  );

  final pendingApt = AppointmentModel(
    id: 'apt-777',
    patientId: testPatient.id,
    patientName: testPatient.name,
    patientNumber: testPatient.patientNumber,
    department: 'eye',
    appointmentDate: fixedDate,
    appointmentTime: '10:00',
    appointmentType: 'regular',
    status: 'waiting',
    createdAt: fixedDate,
    updatedAt: fixedDate,
  );

  group('1. Patient Phone Normalization & Validation', () {
    test('Phone normalization preserves country code and strips extraneous characters', () {
      expect(PatientDetailsScreen.normalizePhoneNumber('+91 98765-43210'), '+919876543210');
      expect(PatientDetailsScreen.normalizePhoneNumber('  +91 98200 12345  '), '+919820012345');
      expect(PatientDetailsScreen.normalizePhoneNumber('9876543210'), '9876543210');
      expect(PatientDetailsScreen.normalizePhoneNumber('(022) 2414-5555'), '02224145555');
      expect(PatientDetailsScreen.normalizePhoneNumber(''), '');
      expect(PatientDetailsScreen.normalizePhoneNumber('abc'), '');
    });
  });

  group('2. Register New Patient Dialog Header & Mobile Layout', () {
    for (final width in [320.0, 360.0, 375.0, 412.0, 768.0]) {
      testWidgets('Complete "Register New Patient" heading visible at $width px', (tester) async {
        tester.view.physicalSize = Size(width, 700);
        tester.view.devicePixelRatio = 1.0;
        addTearDown(tester.view.resetPhysicalSize);

        await tester.pumpWidget(
          ProviderScope(
            overrides: [
              supabaseProvider.overrideWithValue(_FakeSupabaseClient()),
              departmentsProvider.overrideWith((ref) => DepartmentsNotifier(_FakeDeptRepo())),
            ],
            child: const MaterialApp(
              home: Scaffold(
                body: PatientFormDialog(
                  initialDepartment: 'eye',
                ),
              ),
            ),
          ),
        );
        await tester.pumpAndSettle();

        expect(find.text('Register New Patient'), findsOneWidget);
        expect(find.byIcon(Icons.close), findsOneWidget);
        expect(tester.takeException(), isNull);
      });
    }

    testWidgets('Edit Patient dialog displays patient number in heading', (tester) async {
      tester.view.physicalSize = const Size(360, 700);
      tester.view.devicePixelRatio = 1.0;
      addTearDown(tester.view.resetPhysicalSize);

      await tester.pumpWidget(
        ProviderScope(
          overrides: [
            supabaseProvider.overrideWithValue(_FakeSupabaseClient()),
            departmentsProvider.overrideWith((ref) => DepartmentsNotifier(_FakeDeptRepo())),
          ],
          child: MaterialApp(
            home: Scaffold(
              body: PatientFormDialog(
                patient: testPatient,
              ),
            ),
          ),
        ),
      );
      await tester.pumpAndSettle();

      expect(find.text('Edit Patient (${testPatient.patientNumber})'), findsOneWidget);
      expect(find.text('Save Changes'), findsOneWidget);
      expect(tester.takeException(), isNull);
    });
  });

  group('3. Schedule Page Navigation — Hide Mandatory Exam Banner', () {
    Widget buildDetailsScreen({
      required bool showMandatoryBanner,
      AppointmentModel? appointment,
    }) {
      return ProviderScope(
        overrides: [
          supabaseProvider.overrideWithValue(_FakeSupabaseClient()),
          patientRepositoryProvider.overrideWithValue(_FakePatientRepo(testPatient)),
          patientDetailsProvider(testPatient.id).overrideWith((ref) async => testPatient),
          eyeExaminationRepositoryProvider.overrideWithValue(_FakeEyeExamRepo()),
          dentalTreatmentRepositoryProvider.overrideWithValue(_FakeDentalTreatmentRepo()),
          eyeSurgeryRepositoryProvider.overrideWithValue(_FakeEyeSurgeryRepo()),
          dentalLabRepositoryProvider.overrideWithValue(_FakeDentalLabRepo()),
          currentUserRoleProvider.overrideWith((ref) async => 'staff'),
          patientAttendanceHistoryProvider(testPatient.id).overrideWith((ref) async => []),
          eyeExaminationsForPatientProvider(testPatient.id).overrideWith((ref) async => []),
          dentalTreatmentsForPatientProvider(testPatient.id).overrideWith((ref) async => []),
          patientDentalLabCasesProvider(testPatient.id).overrideWith((ref) => []),
          eyeSurgeriesForPatientProvider(testPatient.id).overrideWith((ref) async => []),
        ],
        child: MaterialApp(
          home: PatientDetailsScreen(
            patientId: testPatient.id,
            pendingAppointment: appointment,
            showMandatoryExamBanner: showMandatoryBanner,
          ),
        ),
      );
    }

    testWidgets('When navigating from Schedule (showMandatoryExamBanner: false), banner is HIDDEN', (tester) async {
      tester.view.physicalSize = const Size(390, 800);
      tester.view.devicePixelRatio = 1.0;
      addTearDown(tester.view.resetPhysicalSize);

      await tester.pumpWidget(buildDetailsScreen(
        showMandatoryBanner: false,
        appointment: pendingApt,
      ));
      await tester.pumpAndSettle();

      // "Mandatory Clinical Examination" banner must NOT be shown
      expect(find.text('Mandatory Clinical Examination'), findsNothing);
      // But clinical sections and call buttons must be accessible
      expect(find.text('Patient Details'), findsOneWidget);
      expect(find.text('Suresh Kumar'), findsOneWidget);
      expect(find.text('Call'), findsWidgets);
      expect(find.text('Clinical Examinations'), findsOneWidget);
    });

    testWidgets('When showMandatoryExamBanner: true, banner IS shown for active appointment', (tester) async {
      tester.view.physicalSize = const Size(390, 800);
      tester.view.devicePixelRatio = 1.0;
      addTearDown(tester.view.resetPhysicalSize);

      await tester.pumpWidget(buildDetailsScreen(
        showMandatoryBanner: true,
        appointment: pendingApt,
      ));
      await tester.pumpAndSettle();

      expect(find.text('Mandatory Clinical Examination'), findsOneWidget);
    });
  });
}

class _FakeEyeSurgeryRepo extends Fake implements EyeSurgeryRepository {
  @override
  Future<List<EyeSurgeryModel>> fetchSurgeriesForPatient(String patientId) async => [];
}

class _FakeDentalLabRepo extends Fake implements DentalLabRepository {
  @override
  Future<List<DentalLabModel>> fetchCases({
    String? status,
    String? patientId,
    String? searchQuery,
  }) async => [];
}
