import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:supabase_flutter/supabase_flutter.dart';

import 'package:mkes_care/core/providers/supabase_provider.dart';
import 'package:mkes_care/features/auth/models/profile_model.dart';
import 'package:mkes_care/features/auth/providers/auth_provider.dart';
import 'package:mkes_care/features/dental/models/dental_treatment_model.dart';
import 'package:mkes_care/features/dental/providers/dental_treatment_provider.dart';
import 'package:mkes_care/features/dental/repositories/dental_treatment_repository.dart';
import 'package:mkes_care/features/eye/models/eye_examination_model.dart';
import 'package:mkes_care/features/eye/providers/eye_examination_provider.dart';
import 'package:mkes_care/features/eye/repositories/eye_examination_repository.dart';
import 'package:mkes_care/features/patients/models/patient_attendance.dart';
import 'package:mkes_care/features/patients/models/patient_model.dart';
import 'package:mkes_care/features/patients/repositories/patient_attendance_repository.dart';
import 'package:mkes_care/features/patients/repositories/patient_repository.dart';
import 'package:mkes_care/features/patients/screens/patient_details_screen.dart';
import 'package:mkes_care/features/patients/screens/patient_list_screen.dart';
import 'package:mkes_care/features/staff_portal/screens/staff_patients_screen.dart';
import 'package:mkes_care/features/notifications/providers/notifications_provider.dart';

class _FakeGoTrueClient extends Fake implements GoTrueClient {
  @override
  User? get currentUser => const User(
        id: 'admin-uuid',
        appMetadata: {},
        userMetadata: {},
        aud: 'authenticated',
        createdAt: '2026-01-01',
      );
}

class _FakeSupabaseClient extends Fake implements SupabaseClient {
  @override
  GoTrueClient get auth => _FakeGoTrueClient();
}

class _FakePatientRepo extends Fake implements PatientRepository {
  final List<PatientModel> allPatients;
  _FakePatientRepo(this.allPatients);

  @override
  Future<List<PatientModel>> fetchPatients({
    String? department,
    String? searchQuery,
    int limit = 50,
    int offset = 0,
  }) async {
    final filtered = allPatients.where((p) {
      if (department != null &&
          department.isNotEmpty &&
          department != 'all' &&
          p.department != department) {
        return false;
      }
      if (searchQuery != null && searchQuery.isNotEmpty) {
        final q = searchQuery.toLowerCase();
        final matchesName = p.name.toLowerCase().contains(q);
        final matchesNum = p.patientNumber.toLowerCase().contains(q);
        final matchesMob = (p.mobile ?? '').contains(q);
        return matchesName || matchesNum || matchesMob;
      }
      return true;
    }).toList();
    if (offset >= filtered.length) return [];
    return filtered.skip(offset).take(limit).toList();
  }

  @override
  Future<List<PatientModel>> fetchTodayRegisteredPatients({
    String? department,
  }) async {
    return allPatients.where((p) {
      if (department != null &&
          department.isNotEmpty &&
          department != 'all' &&
          p.department != department) {
        return false;
      }
      return true;
    }).toList();
  }

  @override
  Future<PatientModel> getPatient(String id) async {
    final found = allPatients.firstWhere(
      (p) => p.id == id,
      orElse: () => throw Exception('Patient record not found (ID: $id)'),
    );
    return found;
  }
}

class _FakePatientAttendanceRepo extends Fake implements PatientAttendanceRepository {
  @override
  Future<List<PatientAttendance>> fetchForPatient(String patientId) async => [];
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
  TestWidgetsFlutterBinding.ensureInitialized();

  // Actual sample records generated from Copy of Pt database.xlsx
  final sampleDentalPatient = PatientModel(
    id: '8a37edf4-0ece-55f3-9e58-2b184dfdf450',
    patientNumber: 'D-0001',
    name: 'Mrs.Nirmala Solanki',
    dob: DateTime(1986, 1, 1), // Age 40 -> 2026 - 40 = 1986
    address: 'Byculla',
    mobile: '9323217280',
    department: 'dental',
    reference: 'Self',
    visitDate: DateTime(2026, 11, 5),
    registrationDate: DateTime(2026, 11, 5),
    createdAt: DateTime(2026, 11, 5),
    updatedAt: DateTime(2026, 11, 5),
  );

  final sampleEyePatient = PatientModel(
    id: '8cbfa6cf-0648-5226-8025-f716616ddfa5',
    patientNumber: 'E-0001',
    name: 'Mrs Manjula Jain',
    dob: DateTime(1968, 1, 1), // Age 58 -> 2026 - 58 = 1968
    address: 'C602, Vardhman Estate',
    mobile: '9892971209',
    department: 'eye',
    reference: 'home',
    visitDate: DateTime(2026, 11, 5),
    registrationDate: DateTime(2026, 11, 5),
    createdAt: DateTime(2026, 11, 5),
    updatedAt: DateTime(2026, 11, 5),
  );

  final sampleEyePatientWithNotes = PatientModel(
    id: 'b1a2c3d4-e5f6-7a8b-9c0d-1e2f3a4b5c6d',
    patientNumber: 'E-0003',
    name: 'Baby Vidhi Mistry',
    dob: DateTime(2020, 1, 1), // Age 6 -> 2026 - 6 = 2020
    address: '1/64, Harhar bldg, Sane Guruji Marg, Lalbaug',
    mobile: '9167712557',
    department: 'eye',
    reference: 'Self | Email: rajeshmistry@gmail.com | Alt: 9324183683',
    visitDate: DateTime(2026, 11, 5),
    registrationDate: DateTime(2026, 11, 5),
    createdAt: DateTime(2026, 11, 5),
    updatedAt: DateTime(2026, 11, 5),
  );

  final sampleAdminProfile = ProfileModel(
    id: 'admin-uuid',
    fullName: 'Admin User',
    email: 'admin@mkes.com',
    role: 'admin',
    isActive: true,
    createdAt: DateTime(2026, 1, 1),
  );

  final testPatients = [
    sampleDentalPatient,
    sampleEyePatient,
    sampleEyePatientWithNotes,
  ];

  group('MKES CARE+ Imported Excel Patient Database Integration Tests', () {
    testWidgets('1. PatientModel parses Excel-imported JSON preserving all attributes', (tester) async {
      final json = {
        'id': '8a37edf4-0ece-55f3-9e58-2b184dfdf450',
        'patient_number': 'D-0001',
        'name': 'Mrs.Nirmala Solanki',
        'dob': '1986-01-01',
        'address': 'Byculla',
        'mobile': '9323217280',
        'department': 'dental',
        'reference': 'Self',
        'visit_date': '2026-11-05',
        'registration_date': '2026-11-05',
        'created_at': '2026-11-05T00:00:00Z',
        'updated_at': '2026-11-05T00:00:00Z',
        'whatsapp_opt_out': false,
        'age': 40.0,
        'gender': 'Female',
      };

      final p = PatientModel.fromJson(json);
      expect(p.patientNumber, equals('D-0001'));
      expect(p.name, equals('Mrs.Nirmala Solanki'));
      expect(p.mobile, equals('9323217280'));
      expect(p.department, equals('dental'));
      expect(p.address, equals('Byculla'));
      expect(p.dob, equals(DateTime(1986, 1, 1)));
      expect(p.reference, equals('Self'));
    });

    testWidgets('2. PatientListScreen displays imported patient records and handles search and filters', (tester) async {
      tester.view.physicalSize = const Size(1280, 900);
      tester.view.devicePixelRatio = 1.0;
      addTearDown(() => tester.view.resetPhysicalSize());

      final fakeRepo = _FakePatientRepo(testPatients);

      await tester.pumpWidget(
        ProviderScope(
          overrides: [
            supabaseProvider.overrideWithValue(_FakeSupabaseClient()),
            patientRepositoryProvider.overrideWithValue(fakeRepo),
            currentUserProvider.overrideWith((ref) => const User(
              id: 'admin-uuid',
              appMetadata: {},
              userMetadata: {},
              aud: 'authenticated',
              createdAt: '2026-01-01',
            )),
            currentProfileProvider.overrideWith((ref) => Future.value(sampleAdminProfile)),
            currentUserRoleProvider.overrideWith((ref) => Future.value('admin')),
            unreadNotificationCountProvider.overrideWith((ref) => 0),
          ],
          child: const MaterialApp(
            home: Scaffold(
              body: PatientListScreen(),
            ),
          ),
        ),
      );

      await tester.pumpAndSettle();

      // On initial load, Eye department is selected by default
      expect(find.text('E-0001'), findsWidgets);
      expect(find.text('Mrs Manjula Jain'), findsWidgets);
      expect(find.text('58'), findsWidgets);

      // Switch department filter to Dental
      await tester.tap(find.text('Dental'));
      await tester.pumpAndSettle();

      // Verify Dental patient records
      expect(find.text('D-0001'), findsWidgets);
      expect(find.text('Mrs.Nirmala Solanki'), findsWidgets);
      expect(find.text('40'), findsWidgets);

      // Test search filter
      await tester.enterText(find.byType(TextField).first, 'Solanki');
      await tester.pumpAndSettle();

      expect(find.text('Mrs.Nirmala Solanki'), findsWidgets);
      expect(find.text('Mrs Manjula Jain'), findsNothing);
    });

    testWidgets('3. PatientDetailsScreen renders complete patient information including DOB, Age, Address, and Contacts', (tester) async {
      final fakeRepo = _FakePatientRepo(testPatients);

      await tester.pumpWidget(
        ProviderScope(
          overrides: [
            supabaseProvider.overrideWithValue(_FakeSupabaseClient()),
            patientRepositoryProvider.overrideWithValue(fakeRepo),
            patientAttendanceRepositoryProvider.overrideWithValue(_FakePatientAttendanceRepo()),
            eyeExaminationRepositoryProvider.overrideWithValue(_FakeEyeExamRepo()),
            dentalTreatmentRepositoryProvider.overrideWithValue(_FakeDentalTreatmentRepo()),
            currentUserProvider.overrideWith((ref) => const User(
              id: 'admin-uuid',
              appMetadata: {},
              userMetadata: {},
              aud: 'authenticated',
              createdAt: '2026-01-01',
            )),
            currentProfileProvider.overrideWith((ref) => Future.value(sampleAdminProfile)),
            currentUserRoleProvider.overrideWith((ref) => Future.value('admin')),
            unreadNotificationCountProvider.overrideWith((ref) => 0),
          ],
          child: MaterialApp(
            home: Scaffold(
              body: PatientDetailsScreen(patientId: sampleEyePatientWithNotes.id),
            ),
          ),
        ),
      );

      await tester.pumpAndSettle();

      // Verify Header
      expect(find.text('Baby Vidhi Mistry'), findsWidgets);
      expect(find.text('E-0003'), findsWidgets);
      expect(find.textContaining('Eye'), findsWidgets);

      // Verify Personal Information card
      expect(find.text('PATIENT INFORMATION'), findsOneWidget);
      expect(find.text('9167712557'), findsWidgets);
      expect(find.text('1/64, Harhar bldg, Sane Guruji Marg, Lalbaug'), findsOneWidget);
      expect(find.textContaining('rajeshmistry@gmail.com'), findsOneWidget);
      expect(find.textContaining('9324183683'), findsOneWidget);

      // Verify Date of Birth with Age is calculated and formatted
      expect(find.textContaining('(6 yrs)'), findsOneWidget);
    });

    testWidgets('4. StaffPatientsScreen displays real patient directory and adapts cleanly on narrow mobile (320px)', (tester) async {
      final fakeRepo = _FakePatientRepo(testPatients);

      tester.view.physicalSize = const Size(320 * 2, 700 * 2);
      tester.view.devicePixelRatio = 2.0;
      addTearDown(() => tester.view.resetPhysicalSize());

      await tester.pumpWidget(
        ProviderScope(
          overrides: [
            supabaseProvider.overrideWithValue(_FakeSupabaseClient()),
            patientRepositoryProvider.overrideWithValue(fakeRepo),
            currentUserProvider.overrideWith((ref) => const User(
              id: 'admin-uuid',
              appMetadata: {},
              userMetadata: {},
              aud: 'authenticated',
              createdAt: '2026-01-01',
            )),
            currentProfileProvider.overrideWith((ref) => Future.value(sampleAdminProfile)),
            currentUserRoleProvider.overrideWith((ref) => Future.value('admin')),
            unreadNotificationCountProvider.overrideWith((ref) => 0),
          ],
          child: const MaterialApp(
            home: Scaffold(
              body: StaffPatientsScreen(),
            ),
          ),
        ),
      );

      await tester.pumpAndSettle();

      expect(find.text('Patient Directory'), findsOneWidget);
      expect(find.text('Mrs.Nirmala Solanki'), findsWidgets);
      expect(find.text('Mrs Manjula Jain'), findsWidgets);
      expect(tester.takeException(), isNull);
    });
  });
}
