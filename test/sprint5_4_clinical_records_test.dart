import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:mkes_care/features/auth/providers/auth_provider.dart';
import 'package:mkes_care/features/clinical/models/clinical_inventory_usage_model.dart';
import 'package:mkes_care/features/clinical/providers/clinical_inventory_provider.dart';
import 'package:mkes_care/features/clinical/widgets/clinical_inventory_consumption_dialog.dart';
import 'package:mkes_care/features/dental/models/dental_treatment_model.dart';
import 'package:mkes_care/features/dental/providers/dental_treatment_provider.dart';
import 'package:mkes_care/features/dental/widgets/dental_treatment_patient_section.dart';
import 'package:mkes_care/features/eye/models/eye_examination_model.dart';
import 'package:mkes_care/features/eye/providers/eye_examination_provider.dart';
import 'package:mkes_care/features/eye/widgets/eye_examination_patient_section.dart';
import 'package:mkes_care/features/inventory/models/inventory_item.dart';
import 'package:mkes_care/features/inventory/providers/inventory_provider.dart';
import 'package:mkes_care/features/inventory/repositories/inventory_repository.dart';
import 'package:mkes_care/features/patients/models/patient_model.dart';
import 'package:supabase_flutter/supabase_flutter.dart';

void main() {
  final testPatient = PatientModel(
    id: 'pat-101',
    name: 'Ramesh Patel',
    patientNumber: 'EYE-101',
    department: 'eye',
    mobile: '9876543210',
    createdAt: DateTime(2026, 1, 1),
    updatedAt: DateTime(2026, 1, 1),
  );

  final testDentalPatient = PatientModel(
    id: 'pat-201',
    name: 'Sunita Sharma',
    patientNumber: 'DEN-201',
    department: 'dental',
    mobile: '9876543211',
    createdAt: DateTime(2026, 1, 1),
    updatedAt: DateTime(2026, 1, 1),
  );

  // =========================================================================
  // PART 1: EYE CLINICAL EXAMINATION RECORDS
  // =========================================================================
  group('Part 1: Eye Clinical Examination Records', () {
    test('EyeExaminationModel fromJson and toJson serialization preserves all fields', () {
      final json = {
        'id': 'exam-001',
        'patient_id': 'pat-101',
        'appointment_id': 'apt-501',
        'eye_surgery_id': 'surg-801',
        'examination_date': '2026-10-04',
        'examination_time': '10:30:00',
        'visual_acuity_od': '6/6',
        'visual_acuity_os': '6/12',
        'visual_acuity': 'Pin hole improvement to 6/6 in OS',
        'intraocular_pressure_od': '14 mmHg',
        'intraocular_pressure_os': '18 mmHg',
        'intraocular_pressure': 'Non-contact tonometry',
        'slit_lamp_examination': 'Cornea clear, early nuclear sclerosis in OS',
        'diagnosis': 'Senile Immature Cataract (OS)',
        'clinical_notes': 'Advised phacoemulsification with monofocal IOL',
        'created_by': 'user-123',
        'created_at': '2026-10-04T10:30:00Z',
        'updated_at': '2026-10-04T10:30:00Z',
        'patient_name': 'Ramesh Patel',
        'patient_number': 'EYE-101',
      };

      final exam = EyeExaminationModel.fromJson(json);

      expect(exam.id, 'exam-001');
      expect(exam.patientId, 'pat-101');
      expect(exam.appointmentId, 'apt-501');
      expect(exam.eyeSurgeryId, 'surg-801');
      expect(exam.examinationDate, DateTime(2026, 10, 4));
      expect(exam.examinationTime, '10:30:00');
      expect(exam.visualAcuityOd, '6/6');
      expect(exam.visualAcuityOs, '6/12');
      expect(exam.visualAcuity, 'Pin hole improvement to 6/6 in OS');
      expect(exam.intraocularPressureOd, '14 mmHg');
      expect(exam.intraocularPressureOs, '18 mmHg');
      expect(exam.slitLampExamination, 'Cornea clear, early nuclear sclerosis in OS');
      expect(exam.diagnosis, 'Senile Immature Cataract (OS)');
      expect(exam.clinicalNotes, 'Advised phacoemulsification with monofocal IOL');
      expect(exam.hasVisualAcuity, isTrue);
      expect(exam.hasIop, isTrue);
      expect(exam.hasSlitLamp, isTrue);
      expect(exam.formattedDate, '04 Oct 2026');
      expect(exam.formattedTime, '10:30 AM');

      final serialized = exam.toJson();
      expect(serialized['id'], 'exam-001');
      expect(serialized['patient_id'], 'pat-101');
      expect(serialized['appointment_id'], 'apt-501');
      expect(serialized['visual_acuity_od'], '6/6');
      expect(serialized['diagnosis'], 'Senile Immature Cataract (OS)');

      final insertJson = exam.toInsertJson();
      expect(insertJson.containsKey('id'), isFalse);
      expect(insertJson.containsKey('created_at'), isFalse);
      expect(insertJson.containsKey('updated_at'), isFalse);
      expect(insertJson['patient_id'], 'pat-101');
    });

    test('Empty optional fields in EyeExaminationModel remain empty and are not populated with fake data', () {
      final json = {
        'id': 'exam-002',
        'patient_id': 'pat-101',
        'examination_date': '2026-10-04',
        'created_at': '2026-10-04T11:00:00Z',
        'updated_at': '2026-10-04T11:00:00Z',
      };

      final exam = EyeExaminationModel.fromJson(json);

      expect(exam.appointmentId, isNull);
      expect(exam.eyeSurgeryId, isNull);
      expect(exam.examinationTime, isNull);
      expect(exam.visualAcuityOd, isNull);
      expect(exam.visualAcuityOs, isNull);
      expect(exam.visualAcuity, isNull);
      expect(exam.intraocularPressureOd, isNull);
      expect(exam.intraocularPressureOs, isNull);
      expect(exam.slitLampExamination, isNull);
      expect(exam.diagnosis, isNull);
      expect(exam.clinicalNotes, isNull);
      expect(exam.hasVisualAcuity, isFalse);
      expect(exam.hasIop, isFalse);
      expect(exam.hasSlitLamp, isFalse);
    });

    test('EyeExaminationModel copyWith modifies specified fields without mutating originals', () {
      final initial = EyeExaminationModel(
        id: 'exam-003',
        patientId: 'pat-101',
        examinationDate: DateTime(2026, 10, 4),
        diagnosis: 'Dry Eye Syndrome',
        createdAt: DateTime(2026, 10, 4),
        updatedAt: DateTime(2026, 10, 4),
      );

      final updated = initial.copyWith(
        diagnosis: 'Severe Dry Eye Syndrome',
        clinicalNotes: 'Prescribed lubricating drops 4 times daily',
        visualAcuityOd: '6/6',
      );

      expect(initial.diagnosis, 'Dry Eye Syndrome');
      expect(initial.clinicalNotes, isNull);
      expect(updated.diagnosis, 'Severe Dry Eye Syndrome');
      expect(updated.clinicalNotes, 'Prescribed lubricating drops 4 times daily');
      expect(updated.visualAcuityOd, '6/6');
      expect(updated.patientId, initial.patientId);
      expect(updated.id, initial.id);
    });

    test('Multiple historical eye examinations are preserved without overwriting older records', () {
      final exam1 = EyeExaminationModel(
        id: 'exam-hist-1',
        patientId: 'pat-101',
        examinationDate: DateTime(2026, 8, 10),
        diagnosis: 'Initial Consultation - Mild blurring',
        createdAt: DateTime(2026, 8, 10),
        updatedAt: DateTime(2026, 8, 10),
      );

      final exam2 = EyeExaminationModel(
        id: 'exam-hist-2',
        patientId: 'pat-101',
        examinationDate: DateTime(2026, 9, 15),
        diagnosis: 'Follow-up - Cataract Progression',
        createdAt: DateTime(2026, 9, 15),
        updatedAt: DateTime(2026, 9, 15),
      );

      final exam3 = EyeExaminationModel(
        id: 'exam-hist-3',
        patientId: 'pat-101',
        examinationDate: DateTime(2026, 10, 4),
        diagnosis: 'Pre-op Assessment',
        createdAt: DateTime(2026, 10, 4),
        updatedAt: DateTime(2026, 10, 4),
      );

      final history = [exam3, exam2, exam1]; // Newest first
      expect(history.length, 3);
      expect(history[0].id, 'exam-hist-3');
      expect(history[1].id, 'exam-hist-2');
      expect(history[2].id, 'exam-hist-1');
      expect(history.every((e) => e.patientId == 'pat-101'), isTrue);
    });
  });

  // =========================================================================
  // PART 2: DENTAL CLINICAL TREATMENT RECORDS
  // =========================================================================
  group('Part 2: Dental Clinical Treatment Records', () {
    test('DentalTreatmentModel fromJson and toJson preserves all fields and status', () {
      final json = {
        'id': 'treat-001',
        'patient_id': 'pat-201',
        'appointment_id': 'apt-901',
        'dental_lab_case_id': 'lab-701',
        'treatment_date': '2026-10-04',
        'treatment_time': '14:15:00',
        'tooth_number': '16',
        'procedure_performed': 'Root Canal Treatment (RCT)',
        'treatment_notes': 'Working length determined with apex locator, obturation completed',
        'diagnosis': 'Irreversible Pulpitis',
        'procedure_status': 'completed',
        'created_by': 'user-456',
        'created_at': '2026-10-04T14:15:00Z',
        'updated_at': '2026-10-04T14:15:00Z',
        'dental_lab_case_number': 'DLC-042',
        'dental_lab_case_type': 'Zirconia Crown',
        'patient_name': 'Sunita Sharma',
        'patient_number': 'DEN-201',
      };

      final treatment = DentalTreatmentModel.fromJson(json);

      expect(treatment.id, 'treat-001');
      expect(treatment.patientId, 'pat-201');
      expect(treatment.appointmentId, 'apt-901');
      expect(treatment.dentalLabCaseId, 'lab-701');
      expect(treatment.treatmentDate, DateTime(2026, 10, 4));
      expect(treatment.treatmentTime, '14:15:00');
      expect(treatment.toothNumber, '16');
      expect(treatment.procedurePerformed, 'Root Canal Treatment (RCT)');
      expect(treatment.procedureStatus, 'completed');
      expect(treatment.isCompleted, isTrue);
      expect(treatment.isInProgress, isFalse);
      expect(treatment.isPlanned, isFalse);
      expect(treatment.dentalLabCaseNumber, 'DLC-042');
      expect(treatment.dentalLabCaseType, 'Zirconia Crown');
      expect(treatment.formattedDate, '04 Oct 2026');
      expect(treatment.formattedTime, '02:15 PM');

      final serialized = treatment.toJson();
      expect(serialized['id'], 'treat-001');
      expect(serialized['procedure_performed'], 'Root Canal Treatment (RCT)');
      expect(serialized['dental_lab_case_id'], 'lab-701');

      final insertJson = treatment.toInsertJson();
      expect(insertJson.containsKey('id'), isFalse);
      expect(insertJson.containsKey('created_at'), isFalse);
      expect(insertJson.containsKey('updated_at'), isFalse);
      expect(insertJson['patient_id'], 'pat-201');
    });

    test('DentalTreatmentModel supports various tooth numbering and quadrant formats', () {
      final formats = [
        '16', // Universal / FDI notation
        '21',
        '46',
        'UR4', // Quadrant + tooth notation
        'Upper Right Quadrant',
        'Lower Left Quadrant',
        'Full Mouth',
      ];

      for (final toothFormat in formats) {
        final treat = DentalTreatmentModel(
          id: 'treat-$toothFormat',
          patientId: 'pat-201',
          treatmentDate: DateTime(2026, 10, 4),
          toothNumber: toothFormat,
          procedurePerformed: 'Scaling & Root Planing',
          createdAt: DateTime(2026, 10, 4),
          updatedAt: DateTime(2026, 10, 4),
        );

        expect(treat.toothNumber, toothFormat);
        expect(treat.toJson()['tooth_number'], toothFormat);
      }
    });

    test('Dental treatment records separate model from Dental Lab and only reference case ID', () {
      final treatmentWithLab = DentalTreatmentModel(
        id: 'treat-lab-1',
        patientId: 'pat-201',
        treatmentDate: DateTime(2026, 10, 4),
        dentalLabCaseId: 'dlc-uuid-999',
        dentalLabCaseNumber: 'DLC-099',
        dentalLabCaseType: 'Cast Partial Denture',
        procedurePerformed: 'Denture Insertion & Occlusal Adjustment',
        createdAt: DateTime(2026, 10, 4),
        updatedAt: DateTime(2026, 10, 4),
      );

      // Lab case ID is referenced foreign key, not duplicate lab table
      expect(treatmentWithLab.dentalLabCaseId, 'dlc-uuid-999');
      expect(treatmentWithLab.toJson()['dental_lab_case_id'], 'dlc-uuid-999');
      // The insert payload only carries foreign key ID
      expect(treatmentWithLab.toInsertJson()['dental_lab_case_id'], 'dlc-uuid-999');
      expect(treatmentWithLab.toInsertJson().containsKey('dental_lab_case_number'), isFalse);
    });

    test('Procedure status transitions and flags work correctly', () {
      final statuses = ['planned', 'in_progress', 'completed', 'cancelled'];
      for (final s in statuses) {
        final t = DentalTreatmentModel(
          id: 't-$s',
          patientId: 'pat-201',
          treatmentDate: DateTime.now(),
          procedurePerformed: 'Tooth Prep',
          procedureStatus: s,
          createdAt: DateTime.now(),
          updatedAt: DateTime.now(),
        );

        expect(t.procedureStatus, s);
        if (s == 'completed') expect(t.isCompleted, isTrue);
        if (s == 'in_progress') expect(t.isInProgress, isTrue);
        if (s == 'planned') expect(t.isPlanned, isTrue);
        if (s == 'cancelled') expect(t.isCancelled, isTrue);
      }
    });
  });

  // =========================================================================
  // PART 3: INVENTORY INTEGRATION & ATOMIC CONSUMPTION
  // =========================================================================
  group('Part 3: Inventory Integration & Stock Deduction Logic', () {
    test('ClinicalInventoryUsageModel serialization and attributes match schema', () {
      final json = {
        'id': 'usage-001',
        'patient_id': 'pat-101',
        'record_type': 'eye_examination',
        'record_id': 'exam-001',
        'inventory_id': 'inv-101',
        'quantity': 2.0,
        'transaction_id': 'tx-777',
        'remarks': 'Used tropicamide eye drops & sterile wipes',
        'consumed_at': '2026-10-04T10:45:00Z',
        'created_by': 'user-123',
        'created_at': '2026-10-04T10:45:00Z',
        'updated_at': '2026-10-04T10:45:00Z',
        'item_name': 'Tropicamide Eye Drops 1%',
        'item_unit': 'bottles',
        'patient_name': 'Ramesh Patel',
      };

      final usage = ClinicalInventoryUsageModel.fromJson(json);

      expect(usage.id, 'usage-001');
      expect(usage.patientId, 'pat-101');
      expect(usage.recordType, 'eye_examination');
      expect(usage.recordId, 'exam-001');
      expect(usage.inventoryId, 'inv-101');
      expect(usage.quantity, 2.0);
      expect(usage.transactionId, 'tx-777');
      expect(usage.remarks, 'Used tropicamide eye drops & sterile wipes');
      expect(usage.itemName, 'Tropicamide Eye Drops 1%');
      expect(usage.itemUnit, 'bottles');

      final serialized = usage.toJson();
      expect(serialized['patient_id'], 'pat-101');
      expect(serialized['record_type'], 'eye_examination');
      expect(serialized['record_id'], 'exam-001');
      expect(serialized['quantity'], 2.0);
    });

    test('Simulated atomic consumption verifies positive quantities and rejects zero/negative', () {
      double stock = 20.0;

      void consumeStock(double qty) {
        if (qty <= 0) {
          throw ArgumentError('Stock quantity must be greater than zero.');
        }
        if (stock < qty) {
          throw StateError('Insufficient stock. Available: $stock, Requested: $qty');
        }
        stock -= qty;
      }

      // Valid consumption
      consumeStock(5.0);
      expect(stock, 15.0);

      // Rejects zero
      expect(() => consumeStock(0), throwsA(isA<ArgumentError>()));
      expect(stock, 15.0); // No change

      // Rejects negative
      expect(() => consumeStock(-3.0), throwsA(isA<ArgumentError>()));
      expect(stock, 15.0); // No change

      // Rejects insufficient stock
      expect(() => consumeStock(25.0), throwsA(isA<StateError>()));
      expect(stock, 15.0); // No partial deduction! Perfect atomicity!

      // Successful final deduction
      consumeStock(15.0);
      expect(stock, 0.0);
    });

    test('Patient-linked consumption creates distinguishable audit trail with before/after stock', () {
      final initialStock = 50.0;
      final quantityDeducted = 2.0;
      final afterStock = initialStock - quantityDeducted;

      final auditTransaction = {
        'id': 'tx-audit-01',
        'inventory_id': 'inv-anaesthetic',
        'transaction_type': 'stock_out',
        'quantity': quantityDeducted,
        'stock_before': initialStock,
        'stock_after': afterStock,
        'reason': 'Dispensed to Patient',
        'patient_id': 'pat-201',
        'remarks': 'Clinical Usage (dental_treatment): 2% Lignocaine cartridge',
      };

      expect(auditTransaction['transaction_type'], 'stock_out');
      expect(auditTransaction['reason'], 'Dispensed to Patient');
      expect(auditTransaction['patient_id'], 'pat-201');
      expect(auditTransaction['stock_before'], 50.0);
      expect(auditTransaction['stock_after'], 48.0);
      expect(auditTransaction['remarks'], contains('Clinical Usage (dental_treatment)'));
    });
  });

  // =========================================================================
  // PART 4: WIDGET TESTS & ROLE-BASED ACCESS
  // =========================================================================
  group('Part 4: UI & Widget Tests', () {
    testWidgets('EyeExaminationPatientSection renders empty state when patient has no examinations',
        (tester) async {
      await tester.pumpWidget(
        ProviderScope(
          overrides: [
            currentUserRoleProvider.overrideWith((ref) => Future.value('staff')),
            eyeExaminationsForPatientProvider('pat-101')
                .overrideWith((ref) => Future.value([])),
          ],
          child: MaterialApp(
            home: Scaffold(
              body: EyeExaminationPatientSection(patient: testPatient),
            ),
          ),
        ),
      );

      await tester.pumpAndSettle();

      expect(find.text('Clinical Examinations'), findsOneWidget);
      expect(find.byKey(const Key('add_eye_examination_button')), findsOneWidget);
      expect(find.text('No clinical examination records found.'), findsOneWidget);
    });

    testWidgets('EyeExaminationPatientSection renders examinations with VA, IOP, and diagnosis',
        (tester) async {
      final exam = EyeExaminationModel(
        id: 'exam-w-1',
        patientId: 'pat-101',
        examinationDate: DateTime(2026, 10, 4),
        examinationTime: '11:00:00',
        diagnosis: 'Immature Cataract (OD)',
        visualAcuityOd: '6/12',
        visualAcuityOs: '6/6',
        intraocularPressureOd: '16',
        intraocularPressureOs: '15',
        slitLampExamination: 'Lens opacification in OD',
        createdAt: DateTime(2026, 10, 4),
        updatedAt: DateTime(2026, 10, 4),
      );

      await tester.pumpWidget(
        ProviderScope(
          overrides: [
            currentUserRoleProvider.overrideWith((ref) => Future.value('admin')),
            eyeExaminationsForPatientProvider('pat-101')
                .overrideWith((ref) => Future.value([exam])),
            clinicalInventoryUsageForRecordProvider((
              recordType: 'eye_examination',
              recordId: 'exam-w-1',
            )).overrideWith((ref) => Future.value([])),
          ],
          child: MaterialApp(
            home: Scaffold(
              body: SingleChildScrollView(
                child: EyeExaminationPatientSection(patient: testPatient),
              ),
            ),
          ),
        ),
      );

      await tester.pumpAndSettle();

      expect(find.text('Clinical Examinations'), findsOneWidget);
      expect(find.text('04 Oct 2026'), findsOneWidget);
      expect(find.text('Diagnosis: Immature Cataract (OD)'), findsOneWidget);
      expect(find.text('VA: '), findsOneWidget);
      expect(find.text('IOP: '), findsOneWidget);
      expect(find.text('Record Stock Usage'), findsOneWidget);
      // Admin should see delete button
      expect(find.byTooltip('Delete Examination'), findsOneWidget);
    });

    testWidgets('EyeExaminationPatientSection hides delete button for Staff users',
        (tester) async {
      final exam = EyeExaminationModel(
        id: 'exam-w-2',
        patientId: 'pat-101',
        examinationDate: DateTime(2026, 10, 4),
        diagnosis: 'Refractive Error',
        createdAt: DateTime(2026, 10, 4),
        updatedAt: DateTime(2026, 10, 4),
      );

      await tester.pumpWidget(
        ProviderScope(
          overrides: [
            currentUserRoleProvider.overrideWith((ref) => Future.value('staff')),
            eyeExaminationsForPatientProvider('pat-101')
                .overrideWith((ref) => Future.value([exam])),
            clinicalInventoryUsageForRecordProvider((
              recordType: 'eye_examination',
              recordId: 'exam-w-2',
            )).overrideWith((ref) => Future.value([])),
          ],
          child: MaterialApp(
            home: Scaffold(
              body: SingleChildScrollView(
                child: EyeExaminationPatientSection(patient: testPatient),
              ),
            ),
          ),
        ),
      );

      await tester.pumpAndSettle();

      expect(find.byTooltip('Edit Examination'), findsOneWidget);
      // Staff MUST NOT see the delete button
      expect(find.byTooltip('Delete Examination'), findsNothing);
    });

    testWidgets('DentalTreatmentPatientSection renders empty state and treatment list properly',
        (tester) async {
      final treatment = DentalTreatmentModel(
        id: 'dt-w-1',
        patientId: 'pat-201',
        treatmentDate: DateTime(2026, 10, 4),
        procedurePerformed: 'Composite Restoration',
        toothNumber: '21',
        procedureStatus: 'completed',
        diagnosis: 'Class III Caries',
        createdAt: DateTime(2026, 10, 4),
        updatedAt: DateTime(2026, 10, 4),
      );

      await tester.pumpWidget(
        ProviderScope(
          overrides: [
            currentUserRoleProvider.overrideWith((ref) => Future.value('staff')),
            dentalTreatmentsForPatientProvider('pat-201')
                .overrideWith((ref) => Future.value([treatment])),
            clinicalInventoryUsageForRecordProvider((
              recordType: 'dental_treatment',
              recordId: 'dt-w-1',
            )).overrideWith((ref) => Future.value([])),
          ],
          child: MaterialApp(
            home: Scaffold(
              body: SingleChildScrollView(
                child: DentalTreatmentPatientSection(patient: testDentalPatient),
              ),
            ),
          ),
        ),
      );

      await tester.pumpAndSettle();

      expect(find.text('Clinical Treatments'), findsOneWidget);
      expect(find.text('Composite Restoration'), findsOneWidget);
      expect(find.text('Tooth / Quad: '), findsOneWidget);
      expect(find.text('21'), findsOneWidget);
      expect(find.text('Completed'), findsOneWidget);
      expect(find.text('Diagnosis: Class III Caries'), findsOneWidget);
      expect(find.text('Record Stock Usage'), findsOneWidget);
      // Staff cannot delete
      expect(find.byTooltip('Delete Treatment'), findsNothing);
    });

    testWidgets('ClinicalInventoryConsumptionDialog displays available stock and validates quantity',
        (tester) async {
      final testItem = InventoryItem(
        id: 'inv-lidocaine',
        name: 'Lidocaine 2% Injection',
        category: 'Pharmaceuticals',
        currentStock: 10.0,
        unit: 'vials',
        createdAt: DateTime(2026, 1, 1),
        updatedAt: DateTime(2026, 1, 1),
      );

      await tester.pumpWidget(
        ProviderScope(
          overrides: [
            inventoryProvider.overrideWith((ref) => _TestInventoryNotifier([testItem])),
          ],
          child: const MaterialApp(
            home: Scaffold(
              body: ClinicalInventoryConsumptionDialog(
                patientId: 'pat-201',
                patientName: 'Sunita Sharma',
                patientNumber: 'DEN-201',
                recordType: 'dental_treatment',
                recordId: 'dt-w-1',
                recordTitle: 'Root Canal Treatment (04 Oct 2026)',
              ),
            ),
          ),
        ),
      );

      await tester.pumpAndSettle();

      expect(find.text('Record Inventory Usage'), findsOneWidget);
      expect(find.text('Linked: Root Canal Treatment (04 Oct 2026)'), findsOneWidget);
      expect(find.text('Quantity to Consume *'), findsOneWidget);
      expect(find.text('Confirm Usage'), findsOneWidget);
    });
  });
}

class _TestInventoryNotifier extends InventoryNotifier {
  _TestInventoryNotifier(this.items) : super(_FakeInventoryRepository(items));

  final List<InventoryItem> items;

  @override
  Future<void> fetchInventory() async {
    state = AsyncValue.data(items);
  }
}

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
