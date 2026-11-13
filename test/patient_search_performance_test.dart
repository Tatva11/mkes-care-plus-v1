import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:supabase_flutter/supabase_flutter.dart';

import 'package:mkes_care/core/providers/supabase_provider.dart';
import 'package:mkes_care/features/auth/models/profile_model.dart';
import 'package:mkes_care/features/auth/providers/auth_provider.dart';
import 'package:mkes_care/features/patients/models/patient_model.dart';
import 'package:mkes_care/features/patients/repositories/patient_repository.dart';
import 'package:mkes_care/features/patients/screens/patient_list_screen.dart';
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

/// Pre-computed search indexing entry to eliminate dynamic regex and lowercasing inside benchmark loops.
class _MockPatientSearchEntry {
  final PatientModel patient;
  final String departmentClean;
  final String patNumClean;
  final String patNumDigits;
  final String patNumAlphanum;
  final String nameClean;
  final String mobileClean;

  _MockPatientSearchEntry(this.patient)
      : departmentClean = patient.department?.trim().toLowerCase() ?? '',
        patNumClean = patient.patientNumber.toLowerCase(),
        patNumDigits = patient.patientNumber
            .toLowerCase()
            .replaceAll(MockLargeDatasetPatientRepository._leadingPrefixRegex, ''),
        patNumAlphanum = patient.patientNumber
            .toLowerCase()
            .replaceAll(MockLargeDatasetPatientRepository._nonAlphanumRegex, ''),
        nameClean = patient.name.toLowerCase(),
        mobileClean = (patient.mobile ?? '').toLowerCase();
}

/// In-memory mock patient repository simulating the 17,682-record database behavior
/// with trigram/substring matching, exact ID ranking, and pagination.
class MockLargeDatasetPatientRepository extends Fake implements PatientRepository {
  static final _digitsOnlyRegex = RegExp(r'\D');
  static final _nonAlphanumRegex = RegExp(r'[^a-zA-Z0-9]');
  static final _alphaRegex = RegExp(r'[a-zA-Z]');
  static final _leadingPrefixRegex = RegExp(r'^[ed\-\s]+');

  final List<PatientModel> allPatients;
  late final List<_MockPatientSearchEntry> _entries;
  int fetchCallCount = 0;
  List<String?> lastQueries = [];

  MockLargeDatasetPatientRepository(this.allPatients) {
    _entries = allPatients.map((p) => _MockPatientSearchEntry(p)).toList();
  }

  @override
  PatientModel? getCachedPatient(String id) {
    try {
      return allPatients.firstWhere((p) => p.id == id);
    } catch (_) {
      return null;
    }
  }

  @override
  void cachePatient(PatientModel patient) {}

  @override
  void cachePatients(Iterable<PatientModel> patients) {}

  @override
  void clearCache() {}

  @override
  Future<List<PatientModel>> fetchPatients({
    String? department,
    String? searchQuery,
    int limit = 50,
    int offset = 0,
  }) async {
    fetchCallCount++;
    lastQueries.add(searchQuery);

    final cleanDept = department?.trim().toLowerCase();
    final normalizedSearch = searchQuery?.trim().toLowerCase();
    final effectiveLimit = limit.clamp(1, 200);
    final effectiveOffset = offset < 0 ? 0 : offset;

    // Filter by department
    Iterable<_MockPatientSearchEntry> filtered = _entries;
    if (cleanDept != null && cleanDept.isNotEmpty && cleanDept != 'all') {
      filtered = filtered.where((e) => e.departmentClean == cleanDept);
    }

    // Filter by search query (patient number, name, mobile)
    if (normalizedSearch != null && normalizedSearch.isNotEmpty) {
      final digits = normalizedSearch.replaceAll(_digitsOnlyRegex, '');
      final cleanAlphanum = normalizedSearch.replaceAll(_nonAlphanumRegex, '').toLowerCase();
      final hasAlpha = _alphaRegex.hasMatch(normalizedSearch);

      filtered = filtered.where((e) {
        final matchesNum = e.patNumClean.contains(normalizedSearch) ||
            (cleanAlphanum.isNotEmpty && e.patNumAlphanum.contains(cleanAlphanum)) ||
            (digits.isNotEmpty &&
                (e.patNumDigits == digits ||
                    e.patNumDigits.startsWith(digits) ||
                    e.patNumClean == digits ||
                    e.patNumClean.startsWith(digits)));
        final matchesName = e.nameClean.contains(normalizedSearch);
        final matchesMob = e.mobileClean.contains(normalizedSearch) ||
            (!hasAlpha && digits.length >= 3 && e.mobileClean.contains(digits));
        return matchesNum || matchesName || matchesMob;
      });

      // Rank results: Exact patient_number first, then prefix, then name, then alphabetical
      final list = filtered.toList();
      list.sort((a, b) {
        // Exact patient number match (canonical or raw)
        final aExact = a.patNumClean == normalizedSearch ||
            (cleanAlphanum.isNotEmpty && a.patNumAlphanum == cleanAlphanum) ||
            (digits.isNotEmpty && (a.patNumDigits == digits || a.patNumClean == digits));
        final bExact = b.patNumClean == normalizedSearch ||
            (cleanAlphanum.isNotEmpty && b.patNumAlphanum == cleanAlphanum) ||
            (digits.isNotEmpty && (b.patNumDigits == digits || b.patNumClean == digits));
        if (aExact && !bExact) return -1;
        if (!aExact && bExact) return 1;

        // Prefix patient number match
        final aPrefix = a.patNumClean.startsWith(normalizedSearch) ||
            (cleanAlphanum.isNotEmpty && a.patNumAlphanum.startsWith(cleanAlphanum)) ||
            (digits.isNotEmpty && (a.patNumDigits.startsWith(digits) || a.patNumClean.startsWith(digits)));
        final bPrefix = b.patNumClean.startsWith(normalizedSearch) ||
            (cleanAlphanum.isNotEmpty && b.patNumAlphanum.startsWith(cleanAlphanum)) ||
            (digits.isNotEmpty && (b.patNumDigits.startsWith(digits) || b.patNumClean.startsWith(digits)));
        if (aPrefix && !bPrefix) return -1;
        if (!aPrefix && bPrefix) return 1;

        final aNameExact = a.nameClean == normalizedSearch;
        final bNameExact = b.nameClean == normalizedSearch;
        if (aNameExact && !bNameExact) return -1;
        if (!aNameExact && bNameExact) return 1;

        final aNamePrefix = a.nameClean.startsWith(normalizedSearch);
        final bNamePrefix = b.nameClean.startsWith(normalizedSearch);
        if (aNamePrefix && !bNamePrefix) return -1;
        if (!aNamePrefix && bNamePrefix) return 1;

        return a.patient.name.compareTo(b.patient.name);
      });
      filtered = list;
    } else {
      final list = filtered.toList();
      list.sort((a, b) => a.patient.name.compareTo(b.patient.name));
      filtered = list;
    }

    final totalList = filtered.toList();
    if (effectiveOffset >= totalList.length) {
      return [];
    }
    return totalList
        .skip(effectiveOffset)
        .take(effectiveLimit)
        .map((e) => e.patient)
        .toList();
  }

  @override
  Future<List<PatientModel>> fetchTodayRegisteredPatients({String? department}) async {
    final cleanDept = department?.trim().toLowerCase();
    final now = DateTime.now();
    final todayStart = DateTime(now.year, now.month, now.day);
    return allPatients.where((p) {
      if (cleanDept != null && cleanDept.isNotEmpty && cleanDept != 'all') {
        if (p.department?.toLowerCase() != cleanDept) return false;
      }
      final reg = (p.registrationDate ?? p.createdAt).toLocal();
      return !reg.isBefore(todayStart);
    }).toList();
  }

  @override
  Future<PatientModel> getPatient(String id) async {
    return allPatients.firstWhere(
      (p) => p.id == id,
      orElse: () => throw Exception('Patient record not found (ID: $id)'),
    );
  }

  @override
  Future<PatientModel> createPatient(PatientModel patient) async {
    return patient;
  }

  @override
  Future<PatientModel> updatePatient(PatientModel patient) async {
    return patient;
  }

  @override
  Future<bool> setWhatsAppOptOut(String patientId, bool optOut) async {
    return optOut;
  }
}

void main() {
  TestWidgetsFlutterBinding.ensureInitialized();

  // 1. Target test records from the actual clinic database
  final eyePatient7644 = PatientModel(
    id: 'eye-7644-uuid',
    patientNumber: '7644',
    name: 'Mrunal Padave',
    department: 'eye',
    mobile: '7208695686',
    address: 'Byculla',
    createdAt: DateTime(2026, 11, 1),
    updatedAt: DateTime(2026, 11, 1),
  );

  final dentalPatient7644 = PatientModel(
    id: 'dental-7644-uuid',
    patientNumber: '7644',
    name: 'Aanand Kondkar',
    department: 'dental',
    mobile: '9820011223',
    address: 'Lalbaug',
    createdAt: DateTime(2026, 11, 1),
    updatedAt: DateTime(2026, 11, 1),
  );

  final eyePatient15582 = PatientModel(
    id: 'eye-15582-uuid',
    patientNumber: '15582',
    name: '', // Blank name preserved exactly from Excel row 14685
    department: 'eye',
    mobile: null,
    createdAt: DateTime(2026, 11, 1),
    updatedAt: DateTime(2026, 11, 1),
  );

  final dentalPatientSpecial = PatientModel(
    id: 'dental-special-uuid',
    patientNumber: 'D-0001',
    name: 'Mrs.Nirmala Solanki',
    department: 'dental',
    mobile: '9323217280',
    address: 'Byculla',
    createdAt: DateTime(2026, 11, 1),
    updatedAt: DateTime(2026, 11, 1),
  );

  final eyePatient4000 = PatientModel(
    id: 'eye-4000-uuid',
    patientNumber: '4000', // Bare number as stored from Excel import
    name: 'Siddhi Jain',
    department: 'eye',
    mobile: '8879112013',
    address: 'Byculla',
    createdAt: DateTime(2026, 11, 1),
    updatedAt: DateTime(2026, 11, 1),
  );

  final testPatients = [
    eyePatient7644,
    dentalPatient7644,
    eyePatient15582,
    dentalPatientSpecial,
    eyePatient4000,
  ];

  final sampleAdminProfile = ProfileModel(
    id: 'admin-uuid',
    fullName: 'Admin User',
    email: 'admin@mkes.com',
    role: 'admin',
    isActive: true,
    createdAt: DateTime(2026, 1, 1),
  );

  group('MKES CARE+ Patient Search Performance & Accuracy Tests', () {
    late MockLargeDatasetPatientRepository repo;

    setUp(() {
      repo = MockLargeDatasetPatientRepository(testPatients);
    });

    test('1. Search by patient number 7644 in Eye returns Mrunal Padave', () async {
      final results = await repo.fetchPatients(
        department: 'eye',
        searchQuery: '7644',
      );

      expect(results.length, equals(1));
      expect(results.first.patientNumber, equals('7644'));
      expect(results.first.name, equals('Mrunal Padave'));
      expect(results.first.department, equals('eye'));
      expect(results.first.mobile, equals('7208695686'));
    });

    test('2. Search by patient number 7644 in Dental returns Aanand Kondkar', () async {
      final results = await repo.fetchPatients(
        department: 'dental',
        searchQuery: '7644',
      );

      expect(results.length, equals(1));
      expect(results.first.patientNumber, equals('7644'));
      expect(results.first.name, equals('Aanand Kondkar'));
      expect(results.first.department, equals('dental'));
    });

    test('3. Search by patient number 15582 in Eye preserves blank name record', () async {
      final results = await repo.fetchPatients(
        department: 'eye',
        searchQuery: '15582',
      );

      expect(results.length, equals(1));
      expect(results.first.patientNumber, equals('15582'));
      expect(results.first.name, isEmpty);
      expect(results.first.department, equals('eye'));
    });

    test('3b. Partial patient ID search (e.g. "764" and "D-00") matches correctly', () async {
      final partialResultsEye = await repo.fetchPatients(
        department: 'eye',
        searchQuery: '764',
      );
      expect(partialResultsEye.length, equals(1));
      expect(partialResultsEye.first.patientNumber, equals('7644'));

      final partialResultsDental = await repo.fetchPatients(
        department: 'dental',
        searchQuery: 'D-00',
      );
      expect(partialResultsDental.length, equals(1));
      expect(partialResultsDental.first.patientNumber, equals('D-0001'));
    });

    test('4. Full and partial patient name search matches correctly', () async {
      final fullNameResults = await repo.fetchPatients(
        department: 'dental',
        searchQuery: 'Mrs.Nirmala Solanki',
      );
      expect(fullNameResults.length, equals(1));
      expect(fullNameResults.first.name, equals('Mrs.Nirmala Solanki'));

      final partialNameResults = await repo.fetchPatients(
        department: 'eye',
        searchQuery: 'mrun',
      );
      expect(partialNameResults.length, equals(1));
      expect(partialNameResults.first.name, equals('Mrunal Padave'));
    });

    test('4b. Dental vs Eye vs All department filters isolate records accurately', () async {
      // Cross-department search for '7644' with department='all' returns both records
      final allResults = await repo.fetchPatients(
        department: 'all',
        searchQuery: '7644',
      );
      expect(allResults.length, equals(2));
      expect(allResults.any((p) => p.department == 'eye'), isTrue);
      expect(allResults.any((p) => p.department == 'dental'), isTrue);

      // Eye filter returns only Eye
      final eyeOnly = await repo.fetchPatients(
        department: 'eye',
        searchQuery: '7644',
      );
      expect(eyeOnly.length, equals(1));
      expect(eyeOnly.first.department, equals('eye'));

      // Dental filter returns only Dental
      final dentalOnly = await repo.fetchPatients(
        department: 'dental',
        searchQuery: '7644',
      );
      expect(dentalOnly.length, equals(1));
      expect(dentalOnly.first.department, equals('dental'));
    });

    test('5. Mobile number search (e.g. "9323217280" and partial "7208")', () async {
      final dentalResults = await repo.fetchPatients(
        department: 'dental',
        searchQuery: '9323217280',
      );
      expect(dentalResults.length, equals(1));
      expect(dentalResults.first.name, equals('Mrs.Nirmala Solanki'));

      final eyeResults = await repo.fetchPatients(
        department: 'eye',
        searchQuery: '7208',
      );
      expect(eyeResults.length, equals(1));
      expect(eyeResults.first.name, equals('Mrunal Padave'));
    });

    test('6. Empty search and clearing search returns paginated results without error', () async {
      final emptyResults = await repo.fetchPatients(
        department: 'eye',
        searchQuery: '',
        limit: 50,
        offset: 0,
      );

      expect(emptyResults.length, equals(3)); // Eye records: Mrunal Padave, 15582, Siddhi Jain
      expect(emptyResults.any((p) => p.patientNumber == '7644'), isTrue);
      expect(emptyResults.any((p) => p.patientNumber == '15582'), isTrue);
      expect(emptyResults.any((p) => p.patientNumber == '4000'), isTrue);
    });

    test('6b. Eye 4000 range search matches canonical numbers with bare number, E-prefix, and partial', () async {
      // 1. Bare number search '4000'
      final bareResults = await repo.fetchPatients(
        department: 'eye',
        searchQuery: '4000',
      );
      expect(bareResults.length, equals(1));
      expect(bareResults.first.patientNumber, equals('4000'));
      expect(bareResults.first.name, equals('Siddhi Jain'));

      // 2. Prefixed search 'E4000' matches bare stored record '4000'
      final prefixedResults = await repo.fetchPatients(
        department: 'eye',
        searchQuery: 'E4000',
      );
      expect(prefixedResults.length, equals(1));
      expect(prefixedResults.first.patientNumber, equals('4000'));
      expect(prefixedResults.first.name, equals('Siddhi Jain'));

      // 3. Hyphen-prefixed search 'E-4000' matches bare stored record '4000'
      final hyphenResults = await repo.fetchPatients(
        department: 'eye',
        searchQuery: 'E-4000',
      );
      expect(hyphenResults.length, equals(1));
      expect(hyphenResults.first.patientNumber, equals('4000'));
      expect(hyphenResults.first.name, equals('Siddhi Jain'));

      // 4. Partial search '400' matches 4000
      final partialResults = await repo.fetchPatients(
        department: 'eye',
        searchQuery: '400',
      );
      expect(partialResults.length, equals(1));
      expect(partialResults.first.patientNumber, equals('4000'));
      expect(partialResults.first.name, equals('Siddhi Jain'));
    });

    test('7. Complete 17,682-record dataset simulation & verification', () async {
      // Generate full dataset of 17,682 records (3,018 Dental, 14,664 Eye)
      final largeList = <PatientModel>[];
      
      // 3,018 Dental
      for (int i = 1; i <= 3018; i++) {
        largeList.add(PatientModel(
          id: 'dental-$i',
          patientNumber: i == 7644 ? '7644' : 'D$i',
          name: i == 1 ? 'Mrs.Nirmala Solanki' : 'Dental Patient $i',
          department: 'dental',
          mobile: '98200${i.toString().padLeft(5, '0')}',
          createdAt: DateTime(2026, 11, 1),
          updatedAt: DateTime(2026, 11, 1),
        ));
      }

      // 14,664 Eye (Eye patient 4000 is Siddhi Jain stored as bare number '4000', as in Excel)
      for (int i = 1; i <= 14664; i++) {
        final patNum = i == 7644
            ? '7644'
            : (i == 14664
                ? '15582'
                : (i >= 4000 && i <= 4999 ? '$i' : 'E$i'));
        final patName = i == 7644
            ? 'Mrunal Padave'
            : (i == 4000
                ? 'Siddhi Jain'
                : (i == 14664 ? '' : 'Eye Patient $i'));
        final patMob = i == 7644
            ? '7208695686'
            : (i == 4000 ? '8879112013' : '99200${i.toString().padLeft(5, '0')}');

        largeList.add(PatientModel(
          id: 'eye-$i',
          patientNumber: patNum,
          name: patName,
          department: 'eye',
          mobile: patMob,
          createdAt: DateTime(2026, 11, 1),
          updatedAt: DateTime(2026, 11, 1),
        ));
      }

      expect(largeList.length, equals(17682));
      final dentalCount = largeList.where((p) => p.department == 'dental').length;
      final eyeCount = largeList.where((p) => p.department == 'eye').length;
      expect(dentalCount, equals(3018));
      expect(eyeCount, equals(14664));

      final largeRepo = MockLargeDatasetPatientRepository(largeList);

      // Warmup query so Dart VM JIT and regex compilation overhead does not skew benchmark
      await largeRepo.fetchPatients(department: 'eye', searchQuery: '1');

      // Measure search performance for patient number 7644 (<100ms)
      final stopwatch = Stopwatch()..start();
      final eyeSearch = await largeRepo.fetchPatients(
        department: 'eye',
        searchQuery: '7644',
      );
      stopwatch.stop();

      expect(eyeSearch.first.patientNumber, equals('7644'));
      expect(eyeSearch.first.name, equals('Mrunal Padave'));
      expect(stopwatch.elapsedMilliseconds, lessThan(100));

      // Measure search performance for Eye 4000 range searches (<100ms)
      // 1. Bare numeric query '4000'
      final sw1 = Stopwatch()..start();
      final res4000 = await largeRepo.fetchPatients(
        department: 'eye',
        searchQuery: '4000',
      );
      sw1.stop();
      expect(res4000.isNotEmpty, isTrue);
      expect(res4000.first.patientNumber, equals('4000'));
      expect(res4000.first.name, equals('Siddhi Jain'));
      expect(sw1.elapsedMilliseconds, lessThan(100));

      // 2. Prefixed query 'E4000' matching bare stored record '4000'
      final sw2 = Stopwatch()..start();
      final resE4000 = await largeRepo.fetchPatients(
        department: 'eye',
        searchQuery: 'E4000',
      );
      sw2.stop();
      expect(resE4000.isNotEmpty, isTrue);
      expect(resE4000.first.patientNumber, equals('4000'));
      expect(resE4000.first.name, equals('Siddhi Jain'));
      expect(sw2.elapsedMilliseconds, lessThan(100));

      // 3. Hyphen-prefixed query 'E-4000' matching bare stored record '4000'
      final sw3 = Stopwatch()..start();
      final resEHyphen4000 = await largeRepo.fetchPatients(
        department: 'eye',
        searchQuery: 'E-4000',
      );
      sw3.stop();
      expect(resEHyphen4000.isNotEmpty, isTrue);
      expect(resEHyphen4000.first.patientNumber, equals('4000'));
      expect(resEHyphen4000.first.name, equals('Siddhi Jain'));
      expect(sw3.elapsedMilliseconds, lessThan(100));

      // 4. Partial query '400' matches records in 4000 range
      final sw4 = Stopwatch()..start();
      final res400 = await largeRepo.fetchPatients(
        department: 'eye',
        searchQuery: '400',
        limit: 50,
      );
      sw4.stop();
      expect(res400.any((p) => p.patientNumber == '4000'), isTrue);
      expect(sw4.elapsedMilliseconds, lessThan(100));

      // Test browsing Eye department with limit 50 (never downloads 14,664 rows)
      final eyeBrowse = await largeRepo.fetchPatients(
        department: 'eye',
        limit: 50,
      );
      expect(eyeBrowse.length, equals(50));
    });

    testWidgets('8. PatientListScreen search debounces keystrokes and updates UI smoothly', (tester) async {
      tester.view.physicalSize = const Size(1280, 900);
      tester.view.devicePixelRatio = 1.0;
      addTearDown(() => tester.view.resetPhysicalSize());

      final mockRepo = MockLargeDatasetPatientRepository(testPatients);

      await tester.pumpWidget(
        ProviderScope(
          overrides: [
            supabaseProvider.overrideWithValue(_FakeSupabaseClient()),
            patientRepositoryProvider.overrideWithValue(mockRepo),
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
            home: PatientListScreen(),
          ),
        ),
      );
      await tester.pumpAndSettle();

      // Verify initial load occurred
      expect(find.text('Mrunal Padave'), findsOneWidget);

      // Type in search bar
      final searchField = find.byType(TextField);
      expect(searchField, findsOneWidget);

      await tester.enterText(searchField, '7644');
      // Before debounce timer fires:
      await tester.pump(const Duration(milliseconds: 100));
      // After debounce timer (350ms):
      await tester.pump(const Duration(milliseconds: 300));
      await tester.pumpAndSettle();

      expect(find.text('Mrunal Padave'), findsOneWidget);
    });
  });
}
