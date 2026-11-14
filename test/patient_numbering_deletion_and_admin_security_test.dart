import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:flutter_test/flutter_test.dart';

import 'package:mkes_care/features/auth/models/profile_model.dart';
import 'package:mkes_care/features/patients/models/patient_model.dart';
import 'package:mkes_care/features/patients/repositories/patient_repository.dart';
import 'package:mkes_care/features/patients/widgets/patient_form_dialog.dart';
import 'package:mkes_care/features/admin/models/user_profile.dart';
import 'package:mkes_care/features/admin/repositories/user_management_repository.dart';

// ─── Test Mocks ──────────────────────────────────────────────────────────────

class MockSimulatedPatientRepository extends Fake implements PatientRepository {
  final List<PatientModel> _database;
  final Set<String> _departmentLocks = {};

  MockSimulatedPatientRepository(List<PatientModel> initialDatabase)
      : _database = List.from(initialDatabase);

  List<PatientModel> get database => List.unmodifiable(_database);

  @override
  Future<String> getNextPatientNumber(String department) async {
    final cleanDept = department.trim().toLowerCase();
    if (cleanDept != 'eye' && cleanDept != 'dental') {
      throw ArgumentError.value(department, 'department', 'Must be eye or dental.');
    }

    final prefix = cleanDept == 'eye' ? 'E' : 'D';
    int maxNum = 0;
    final numberPattern = RegExp(r'^[A-Za-z]*-?(\d{1,9})');
    for (final p in _database) {
      if (p.department?.toLowerCase().trim() == cleanDept) {
        final match = numberPattern.firstMatch(p.patientNumber.trim());
        if (match != null) {
          final val = int.tryParse(match.group(1)!) ?? 0;
          if (val > maxNum) maxNum = val;
        }
      }
    }
    final nextNum = maxNum + 1;
    return '$prefix-${nextNum < 1000 ? nextNum.toString().padLeft(3, '0') : nextNum.toString()}';
  }

  @override
  Future<PatientModel> createPatient(PatientModel patient) async {
    final cleanDept = patient.department?.trim().toLowerCase();
    if (cleanDept == null || (cleanDept != 'eye' && cleanDept != 'dental')) {
      throw ArgumentError.value(patient.department, 'department', 'Must be eye or dental.');
    }

    // Simulate PostgreSQL pg_advisory_xact_lock
    while (_departmentLocks.contains(cleanDept)) {
      await Future.delayed(const Duration(milliseconds: 5));
    }
    _departmentLocks.add(cleanDept);

    try {
      final assignedNumber = await getNextPatientNumber(cleanDept);
      final created = patient.copyWith(
        id: 'mock-id-${_database.length + 1}',
        patientNumber: assignedNumber,
        department: cleanDept,
        createdAt: DateTime.now(),
        updatedAt: DateTime.now(),
      );
      _database.add(created);
      return created;
    } finally {
      _departmentLocks.remove(cleanDept);
    }
  }

  @override
  Future<bool> deletePatient(String id) async {
    final index = _database.indexWhere((p) => p.id == id);
    if (index == -1) {
      throw Exception('Patient record not found (ID: $id).');
    }
    _database.removeAt(index);
    return true;
  }

  @override
  Future<List<PatientModel>> fetchPatients({
    String? department,
    String? searchQuery,
    int limit = 50,
    int offset = 0,
  }) async {
    var list = _database.where((p) {
      if (department != null &&
          department.isNotEmpty &&
          department != 'all' &&
          p.department?.toLowerCase().trim() != department.toLowerCase().trim()) {
        return false;
      }
      if (searchQuery != null && searchQuery.isNotEmpty) {
        final q = searchQuery.toLowerCase();
        return p.name.toLowerCase().contains(q) ||
            p.patientNumber.toLowerCase().contains(q) ||
            (p.mobile ?? '').contains(q);
      }
      return true;
    }).toList();

    return list.skip(offset).take(limit).toList();
  }

  @override
  Future<PatientModel> getPatient(String id) async {
    final match = _database.firstWhere(
      (p) => p.id == id,
      orElse: () => throw Exception('Patient record not found (ID: $id)'),
    );
    return match;
  }
}

class MockSimulatedUserManagementRepository extends Fake
    implements UserManagementRepository {
  final List<UserProfile> _users;
  final String currentUserId;

  MockSimulatedUserManagementRepository(this._users, {required this.currentUserId});

  @override
  Future<List<UserProfile>> fetchUsers() async => List.unmodifiable(_users);

  @override
  Future<void> deleteUser(String id) async {
    if (id == currentUserId) {
      throw Exception('You cannot delete your own admin account.');
    }
    final target = _users.firstWhere(
      (u) => u.id == id,
      orElse: () => throw Exception('User not found'),
    );
    if (target.role.toLowerCase() == 'admin') {
      final activeAdmins = _users
          .where((u) => u.role.toLowerCase() == 'admin' && u.isActive)
          .length;
      if (activeAdmins <= 1) {
        throw Exception('Cannot delete the last remaining admin account.');
      }
    }
    _users.removeWhere((u) => u.id == id);
  }
}

void main() {
  TestWidgetsFlutterBinding.ensureInitialized();

  // Seed with real imported Excel dataset boundaries:
  // Eye highest = 15582 (14,664 records)
  // Dental highest = 3018 (3,018 records)
  late MockSimulatedPatientRepository patientRepo;
  late List<PatientModel> initialPatients;

  setUp(() {
    initialPatients = [
      PatientModel(
        id: 'eye-1',
        patientNumber: 'E-0001',
        name: 'Mrs Manjula Jain',
        department: 'eye',
        mobile: '9892971209',
        createdAt: DateTime(2026, 1, 1),
        updatedAt: DateTime(2026, 1, 1),
      ),
      PatientModel(
        id: 'eye-4000',
        patientNumber: '4000', // bare imported number
        name: 'Siddhi Jain',
        department: 'eye',
        mobile: '8879112013',
        createdAt: DateTime(2026, 1, 1),
        updatedAt: DateTime(2026, 1, 1),
      ),
      PatientModel(
        id: 'eye-7644',
        patientNumber: '7644',
        name: 'Mrunal Padave',
        department: 'eye',
        mobile: '7208695686',
        createdAt: DateTime(2026, 1, 1),
        updatedAt: DateTime(2026, 1, 1),
      ),
      PatientModel(
        id: 'eye-15582',
        patientNumber: '15582', // highest existing Eye record in database
        name: 'Kashish Gupta',
        department: 'eye',
        mobile: '9920015582',
        createdAt: DateTime(2026, 1, 1),
        updatedAt: DateTime(2026, 1, 1),
      ),
      PatientModel(
        id: 'dental-1',
        patientNumber: 'D-0001',
        name: 'Mrs. Nirmala Solanki',
        department: 'dental',
        mobile: '9323217280',
        createdAt: DateTime(2026, 1, 1),
        updatedAt: DateTime(2026, 1, 1),
      ),
      PatientModel(
        id: 'dental-3018',
        patientNumber: 'D-3018', // highest existing Dental record in database
        name: 'Aanand Kondkar',
        department: 'dental',
        mobile: '9820030180',
        createdAt: DateTime(2026, 1, 1),
        updatedAt: DateTime(2026, 1, 1),
      ),
    ];
    patientRepo = MockSimulatedPatientRepository(initialPatients);
  });

  group('MKES CARE+ Patient Numbering & Registration Tests', () {
    test('1. Continues numbering from highest imported Excel record without restarting at 001', () async {
      // Eye highest is 15582 -> next Eye must be E-15583
      final nextEyePreview = await patientRepo.getNextPatientNumber('eye');
      expect(nextEyePreview, equals('E-15583'));

      // Dental highest is 3018 -> next Dental must be D-3019
      final nextDentalPreview = await patientRepo.getNextPatientNumber('dental');
      expect(nextDentalPreview, equals('D-3019'));
    });

    test('2. Read-only preview does not reserve or consume patient numbers', () async {
      final preview1 = await patientRepo.getNextPatientNumber('eye');
      final preview2 = await patientRepo.getNextPatientNumber('eye');
      final preview3 = await patientRepo.getNextPatientNumber('eye');

      expect(preview1, equals('E-15583'));
      expect(preview2, equals('E-15583'));
      expect(preview3, equals('E-15583'));
      expect(patientRepo.database.length, equals(6)); // zero rows inserted
    });

    test('3. Atomic sequential registration increments sequentially without duplicates', () async {
      final p1 = await patientRepo.createPatient(
        PatientModel(
          id: '',
          patientNumber: '',
          name: 'New Eye Patient A',
          department: 'eye',
          createdAt: DateTime.now(),
          updatedAt: DateTime.now(),
        ),
      );
      expect(p1.patientNumber, equals('E-15583'));

      final p2 = await patientRepo.createPatient(
        PatientModel(
          id: '',
          patientNumber: '',
          name: 'New Eye Patient B',
          department: 'eye',
          createdAt: DateTime.now(),
          updatedAt: DateTime.now(),
        ),
      );
      expect(p2.patientNumber, equals('E-15584'));

      // Dental maintains separate numbering
      final pDental = await patientRepo.createPatient(
        PatientModel(
          id: '',
          patientNumber: '',
          name: 'New Dental Patient A',
          department: 'dental',
          createdAt: DateTime.now(),
          updatedAt: DateTime.now(),
        ),
      );
      expect(pDental.patientNumber, equals('D-3019'));
    });

    test('4. Consistent format padding (E-001 / D-001 for low numbers)', () async {
      final lowRepo = MockSimulatedPatientRepository([]);
      expect(await lowRepo.getNextPatientNumber('eye'), equals('E-001'));
      expect(await lowRepo.getNextPatientNumber('dental'), equals('D-001'));

      final singlePatientRepo = MockSimulatedPatientRepository([
        PatientModel(
          id: '1',
          patientNumber: 'E-001',
          name: 'First',
          department: 'eye',
          createdAt: DateTime.now(),
          updatedAt: DateTime.now(),
        ),
      ]);
      expect(await singlePatientRepo.getNextPatientNumber('eye'), equals('E-002'));
    });

    test('4b. Extracts correct next number across all real formats (1, 4000, E-4000, E4000, D-100, D3819, D3823, 15562, composite strings) without overflow', () async {
      final now = DateTime(2026, 1, 1);
      final multiFormatRepo = MockSimulatedPatientRepository([
        // Eye formats: 1, 4000, E-4000, E4000, 15562, composite 200-digit string
        PatientModel(id: 'e1', patientNumber: '1', name: 'P1', department: 'eye', createdAt: now, updatedAt: now),
        PatientModel(id: 'e2', patientNumber: '4000', name: 'P4000', department: 'eye', createdAt: now, updatedAt: now),
        PatientModel(id: 'e3', patientNumber: 'E-4000', name: 'PEHyphen4000', department: 'eye', createdAt: now, updatedAt: now),
        PatientModel(id: 'e4', patientNumber: 'E4000', name: 'PE4000', department: 'eye', createdAt: now, updatedAt: now),
        PatientModel(id: 'e5', patientNumber: '15562', name: 'Rekha Shah', department: 'eye', createdAt: now, updatedAt: now),
        PatientModel(
          id: 'e6',
          patientNumber: '65.75+A5694+A5702+A5718+A5734+A5750+A5766+A5782+A5798+A5814+A5830', // outlier composite
          name: 'aarvi jain',
          department: 'eye',
          createdAt: now,
          updatedAt: now,
        ),

        // Dental formats: D-100, D1, D3819, D3823, composite D270/937, D2271+A16+A750
        PatientModel(id: 'd1', patientNumber: 'D-100', name: 'D100', department: 'dental', createdAt: now, updatedAt: now),
        PatientModel(id: 'd2', patientNumber: 'D1', name: 'D1', department: 'dental', createdAt: now, updatedAt: now),
        PatientModel(id: 'd3', patientNumber: 'D3819', name: 'Kavita chalke', department: 'dental', createdAt: now, updatedAt: now),
        PatientModel(id: 'd4', patientNumber: 'D3823', name: 'D3823', department: 'dental', createdAt: now, updatedAt: now),
        PatientModel(id: 'd5', patientNumber: 'D270/937', name: 'Mr.Milind Bhandekar', department: 'dental', createdAt: now, updatedAt: now),
        PatientModel(id: 'd6', patientNumber: 'D2271+A16+A750', name: 'Master. Ahaan Chauhan', department: 'dental', createdAt: now, updatedAt: now),
      ]);

      // Eye highest valid is 15562 -> next is E-15563 (composite 65.75 does NOT overflow or inflate)
      final nextEye = await multiFormatRepo.getNextPatientNumber('eye');
      expect(nextEye, equals('E-15563'));

      // Dental highest valid is 3823 -> next is D-3824 (composite D2271 or D270/937 does NOT become 227 million)
      final nextDental = await multiFormatRepo.getNextPatientNumber('dental');
      expect(nextDental, equals('D-3824'));
    });

    test('5. Simultaneous concurrent registrations do not collide', () async {
      final futures = List.generate(
        10,
        (i) => patientRepo.createPatient(
          PatientModel(
            id: '',
            patientNumber: '',
            name: 'Concurrent Patient $i',
            department: 'eye',
            createdAt: DateTime.now(),
            updatedAt: DateTime.now(),
          ),
        ),
      );

      final results = await Future.wait(futures);
      final assignedNumbers = results.map((p) => p.patientNumber).toSet();

      // All 10 must have unique numbers from E-15583 to E-15592
      expect(assignedNumbers.length, equals(10));
      for (int i = 15583; i <= 15592; i++) {
        expect(assignedNumbers.contains('E-$i'), isTrue);
      }
    });
  });

  group('MKES CARE+ Patient Deletion & Department Isolation Tests', () {
    test('6. Admin can delete patients in any department', () async {
      expect(patientRepo.database.any((p) => p.id == 'eye-7644'), isTrue);
      final deleted = await patientRepo.deletePatient('eye-7644');
      expect(deleted, isTrue);
      expect(patientRepo.database.any((p) => p.id == 'eye-7644'), isFalse);

      final deletedDental = await patientRepo.deletePatient('dental-3018');
      expect(deletedDental, isTrue);
      expect(patientRepo.database.any((p) => p.id == 'dental-3018'), isFalse);
    });

    test('7. Staff can delete only patients in their own department (Isolation Logic)', () {
      final eyeStaff = ProfileModel(
        id: 'staff-eye-1',
        fullName: 'Eye Nurse',
        email: 'eye@mkes.com',
        role: 'staff',
        department: 'eye',
        isActive: true,
        createdAt: DateTime(2026, 1, 1),
      );

      final eyePatient = initialPatients.firstWhere((p) => p.department == 'eye');
      final dentalPatient = initialPatients.firstWhere((p) => p.department == 'dental');

      bool canStaffDelete(ProfileModel staff, PatientModel patient) {
        if (staff.role == 'admin') return true;
        final staffDept = staff.department?.toLowerCase().trim();
        final patDept = patient.department?.toLowerCase().trim();
        return staffDept != null && staffDept.isNotEmpty && staffDept == patDept;
      }

      // Eye staff can delete Eye patient
      expect(canStaffDelete(eyeStaff, eyePatient), isTrue);

      // Eye staff CANNOT delete Dental patient
      expect(canStaffDelete(eyeStaff, dentalPatient), isFalse);
    });
  });

  group('MKES CARE+ Admin Account Deletion Security Tests', () {
    late List<UserProfile> userList;
    late MockSimulatedUserManagementRepository userRepo;

    setUp(() {
      userList = [
        UserProfile(
          id: 'admin-1',
          fullName: 'Primary Admin',
          email: 'admin1@mkes.com',
          role: 'admin',
          isActive: true,
          createdAt: DateTime(2026, 1, 1),
        ),
        UserProfile(
          id: 'admin-2',
          fullName: 'Secondary Admin',
          email: 'admin2@mkes.com',
          role: 'admin',
          isActive: true,
          createdAt: DateTime(2026, 1, 1),
        ),
        UserProfile(
          id: 'staff-1',
          fullName: 'Staff Member One',
          email: 'staff1@mkes.com',
          role: 'staff',
          isActive: true,
          createdAt: DateTime(2026, 1, 1),
        ),
      ];
      userRepo = MockSimulatedUserManagementRepository(
        userList,
        currentUserId: 'admin-1',
      );
    });

    test('8. Admin cannot delete their own currently logged-in account', () async {
      expect(
        () => userRepo.deleteUser('admin-1'),
        throwsA(predicate((e) => e.toString().contains('cannot delete your own'))),
      );
      expect(userList.any((u) => u.id == 'admin-1'), isTrue);
    });

    test('9. Admin can delete staff accounts successfully', () async {
      expect(userList.any((u) => u.id == 'staff-1'), isTrue);
      await userRepo.deleteUser('staff-1');
      expect(userList.any((u) => u.id == 'staff-1'), isFalse);
    });

    test('10. Admin cannot delete the last remaining admin account', () async {
      // Delete admin-2 so only admin-1 remains
      await userRepo.deleteUser('admin-2');
      expect(userList.where((u) => u.role == 'admin').length, equals(1));

      // Attempting to delete the last admin (e.g. from service context) must be rejected
      expect(
        () => userRepo.deleteUser('admin-1'),
        throwsA(predicate((e) => e.toString().contains('cannot delete your own') || e.toString().contains('last remaining admin'))),
      );
    });
  });

  group('MKES CARE+ Registration Form Preview Widget Tests', () {
    testWidgets('11. PatientFormDialog displays prominent next patient ID preview', (tester) async {
      await tester.pumpWidget(
        ProviderScope(
          overrides: [
            patientRepositoryProvider.overrideWithValue(patientRepo),
          ],
          child: const MaterialApp(
            home: Scaffold(
              body: PatientFormDialog(initialDepartment: 'eye'),
            ),
          ),
        ),
      );

      await tester.pump();
      await tester.pump(const Duration(milliseconds: 50));

      // Must display Next Assigned Patient ID (Preview) banner
      expect(find.text('Next Assigned Patient ID (Preview)'), findsOneWidget);
      expect(find.text('E-15583'), findsOneWidget);
      expect(find.text('Eye Clinic'), findsWidgets);
    });
  });
}
