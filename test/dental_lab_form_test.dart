import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:mkes_care/features/dental/widgets/dental_lab_form_dialog.dart';
import 'package:mkes_care/features/dental/providers/dental_lab_provider.dart';
import 'package:mkes_care/features/dental/repositories/dental_lab_repository.dart';
import 'package:mkes_care/features/patients/models/patient_model.dart';
import 'package:mkes_care/features/patients/providers/patients_provider.dart';
import 'package:mkes_care/features/patients/repositories/patient_repository.dart';

class _FakeDentalLabRepo extends Fake implements DentalLabRepository {
  @override
  Future<String> generateNextCaseNumber() async => 'DEN-20261018-0001';
}

class _FakePatientRepo extends Fake implements PatientRepository {
  @override
  Future<List<PatientModel>> fetchPatients({String? department, String? searchQuery}) async {
    return [
      PatientModel(
        id: 'pat-1',
        patientNumber: 'D101',
        name: 'Rohan Sharma',
        mobile: '9876543210',
        department: 'dental',
        createdAt: DateTime.now(),
        updatedAt: DateTime.now(),
      ),
    ];
  }
}

void main() {
  testWidgets('DentalLabFormDialog renders without white screen or exception', (tester) async {
    tester.view.physicalSize = const Size(360, 700);
    tester.view.devicePixelRatio = 1.0;
    addTearDown(tester.view.resetPhysicalSize);
    addTearDown(tester.view.resetDevicePixelRatio);

    await tester.pumpWidget(
      ProviderScope(
        overrides: [
          dentalLabRepositoryProvider.overrideWithValue(_FakeDentalLabRepo()),
          patientRepositoryProvider.overrideWithValue(_FakePatientRepo()),
          patientsByDepartmentProvider('dental').overrideWith((ref) async => [
            PatientModel(
              id: 'pat-1',
              patientNumber: 'D101',
              name: 'Rohan Sharma',
              mobile: '9876543210',
              department: 'dental',
              createdAt: DateTime.now(),
              updatedAt: DateTime.now(),
            ),
          ]),
        ],
        child: const MaterialApp(
          home: Scaffold(
            body: DentalLabFormDialog(),
          ),
        ),
      ),
    );
    await tester.pumpAndSettle();

    expect(find.text('New Dental Lab Case'), findsOneWidget);
    expect(find.text('CASE NUMBER *'), findsOneWidget);
    expect(tester.takeException(), isNull);
  });
}
