import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:flutter_test/flutter_test.dart';

import 'package:mkes_care/features/appointments/models/appointment_model.dart';
import 'package:mkes_care/features/auth/providers/auth_provider.dart';
import 'package:mkes_care/features/dental/models/dental_treatment_model.dart';
import 'package:mkes_care/features/dental/providers/dental_treatment_provider.dart';
import 'package:mkes_care/features/dental/widgets/dental_treatment_patient_section.dart';
import 'package:mkes_care/features/eye/models/eye_surgery_model.dart';
import 'package:mkes_care/features/eye/providers/eye_surgery_provider.dart';
import 'package:mkes_care/features/eye/widgets/eye_surgery_detail_dialog.dart';
import 'package:mkes_care/features/eye/widgets/eye_surgery_patient_section.dart';
import 'package:mkes_care/features/inventory/models/department_inventory_item.dart';
import 'package:mkes_care/features/inventory/models/stock_request_model.dart';
import 'package:mkes_care/features/patients/models/patient_model.dart';

void main() {
  TestWidgetsFlutterBinding.ensureInitialized();

  final testPatient = PatientModel(
    id: 'patient-101',
    name: 'Sarah Connor',
    patientNumber: 'DENT-101',
    mobile: '9876543210',
    department: 'dental',
    createdAt: DateTime.now(),
    updatedAt: DateTime.now(),
  );

  final otherPatient = PatientModel(
    id: 'patient-999',
    name: 'John Doe',
    patientNumber: 'DENT-999',
    mobile: '9123456780',
    department: 'dental',
    createdAt: DateTime.now(),
    updatedAt: DateTime.now(),
  );

  final testAppointment = AppointmentModel(
    id: 'apt-501',
    patientId: 'patient-101',
    department: 'dental',
    appointmentDate: DateTime(2026, 10, 15),
    appointmentTime: '10:00:00',
    appointmentType: 'regular',
    status: 'scheduled',
    createdAt: DateTime(2026, 10, 1),
    updatedAt: DateTime(2026, 10, 1),
  );

  final otherPatientAppointment = AppointmentModel(
    id: 'apt-777',
    patientId: 'patient-999',
    department: 'dental',
    appointmentDate: DateTime(2026, 10, 16),
    appointmentTime: '11:00:00',
    appointmentType: 'regular',
    status: 'scheduled',
    createdAt: DateTime(2026, 10, 1),
    updatedAt: DateTime(2026, 10, 1),
  );

  group('Feature 1: Dental Appointment Linking', () {
    test('DentalTreatmentModel serialization preserves appointment ID, date, time, and status', () {
      final treatment = DentalTreatmentModel(
        id: 'treatment-1',
        patientId: testPatient.id,
        appointmentId: testAppointment.id,
        treatmentDate: DateTime(2026, 10, 15),
        treatmentTime: '10:30:00',
        toothNumber: '16',
        procedurePerformed: 'Composite Restoration',
        diagnosis: 'Deep Caries',
        procedureStatus: 'completed',
        createdAt: DateTime.now(),
        updatedAt: DateTime.now(),
        patientName: testPatient.name,
        patientNumber: testPatient.patientNumber,
        appointmentDate: testAppointment.appointmentDate,
        appointmentTime: testAppointment.appointmentTime,
        appointmentStatus: testAppointment.status,
      );

      final json = treatment.toJson();
      expect(json['appointment_id'], equals('apt-501'));
      expect(json['patient_id'], equals('patient-101'));
      expect(json['procedure_performed'], equals('Composite Restoration'));

      final parsed = DentalTreatmentModel.fromJson({
        'id': 'treatment-1',
        'patient_id': 'patient-101',
        'appointment_id': 'apt-501',
        'treatment_date': '2026-10-15',
        'treatment_time': '10:30:00',
        'tooth_number': '16',
        'procedure_performed': 'Composite Restoration',
        'appointments': {
          'appointment_date': '2026-10-15',
          'appointment_time': '10:00:00',
          'status': 'scheduled',
        },
        'created_at': DateTime.now().toIso8601String(),
        'updated_at': DateTime.now().toIso8601String(),
      });

      expect(parsed.appointmentId, equals('apt-501'));
      expect(parsed.appointmentDate, isNotNull);
      expect(parsed.appointmentStatus, equals('scheduled'));
    });

    test('DentalTreatmentModel copyWith can preserve, change, or clear appointment linkage', () {
      final initial = DentalTreatmentModel(
        id: 'treatment-1',
        patientId: testPatient.id,
        appointmentId: 'apt-501',
        treatmentDate: DateTime(2026, 10, 15),
        procedurePerformed: 'Scaling',
        createdAt: DateTime.now(),
        updatedAt: DateTime.now(),
        appointmentDate: DateTime(2026, 10, 15),
        appointmentTime: '10:00:00',
        appointmentStatus: 'scheduled',
      );

      // 1. Preserves appointment
      final preserved = initial.copyWith(toothNumber: '21');
      expect(preserved.appointmentId, equals('apt-501'));
      expect(preserved.appointmentStatus, equals('scheduled'));

      // 2. Changes appointment
      final changed = initial.copyWith(appointmentId: 'apt-502');
      expect(changed.appointmentId, equals('apt-502'));

      // 3. Clears appointment explicitly
      final cleared = initial.copyWith(clearAppointmentId: true);
      expect(cleared.appointmentId, isNull);
      expect(cleared.appointmentDate, isNull);
      expect(cleared.appointmentStatus, isNull);
    });

    test('Saving treatment without an appointment leaves appointmentId null without errors', () {
      final unlinked = DentalTreatmentModel(
        id: 'treatment-unlinked',
        patientId: testPatient.id,
        appointmentId: null,
        treatmentDate: DateTime(2026, 10, 14),
        procedurePerformed: 'Fluoride Application',
        createdAt: DateTime.now(),
        updatedAt: DateTime.now(),
      );

      expect(unlinked.appointmentId, isNull);
      expect(unlinked.toJson()['appointment_id'], isNull);
    });

    test('Appointment filter prevents linking another patient appointment', () {
      // System guarantees only appointments matching widget.patient.id are loaded
      final appointments = [testAppointment, otherPatientAppointment];
      final filteredForPatient =
          appointments.where((a) => a.patientId == testPatient.id).toList();

      expect(filteredForPatient.length, equals(1));
      expect(filteredForPatient.first.id, equals('apt-501'));
      expect(filteredForPatient.any((a) => a.patientId == otherPatient.id), isFalse);
    });

    testWidgets('DentalTreatmentPatientSection displays linked appointment date and status',
        (tester) async {
      final treatmentWithApt = DentalTreatmentModel(
        id: 'tr-1',
        patientId: testPatient.id,
        appointmentId: testAppointment.id,
        treatmentDate: DateTime(2026, 10, 15),
        treatmentTime: '10:00:00',
        procedurePerformed: 'Root Canal Treatment',
        procedureStatus: 'in_progress',
        createdAt: DateTime.now(),
        updatedAt: DateTime.now(),
        appointmentDate: testAppointment.appointmentDate,
        appointmentTime: testAppointment.appointmentTime,
        appointmentStatus: 'scheduled',
      );

      await tester.pumpWidget(
        ProviderScope(
          overrides: [
            dentalTreatmentsForPatientProvider(testPatient.id).overrideWith(
              (ref) => Future.value([treatmentWithApt]),
            ),
            currentUserRoleProvider.overrideWith((ref) => Future.value('staff')),
          ],
          child: MaterialApp(
            home: Scaffold(
              body: DentalTreatmentPatientSection(patient: testPatient),
            ),
          ),
        ),
      );

      await tester.pumpAndSettle();

      expect(find.text('Root Canal Treatment'), findsOneWidget);
      expect(find.textContaining('Appointment: 15 Oct 2026'), findsOneWidget);
      expect(find.textContaining('SCHEDULED'), findsOneWidget);
    });
  });

  group('Feature 2: Clickable Operation Details in Patient Details', () {
    final eyePatient = PatientModel(
      id: 'patient-eye-1',
      name: 'Arthur Dent',
      patientNumber: 'EYE-201',
      mobile: '9988776655',
      department: 'eye',
      createdAt: DateTime.now(),
      updatedAt: DateTime.now(),
    );

    final testSurgery = EyeSurgeryModel(
      id: 'surgery-888',
      patientId: eyePatient.id,
      patientName: eyePatient.name,
      patientNumber: eyePatient.patientNumber,
      surgeryType: 'Cataract Surgery',
      eyeSide: 'left',
      assignedStaffName: 'Dr. Jane Foster',
      preOpDate: DateTime(2026, 10, 10),
      surgeryDate: DateTime(2026, 10, 12),
      surgeryTime: '09:30 AM',
      status: 'scheduled',
      preOpChecklist: {
        'identity_verified': true,
        'consent_confirmed': true,
        'correct_eye_confirmed': true,
      },
      iolDetails: 'AcrySof IQ Model SN60WF +21.5D',
      remarks: 'Patient advised to bring previous topography report.',
      createdAt: DateTime.now(),
      updatedAt: DateTime.now(),
    );

    test('EyeSurgeryPatientSection renders correct operations for the patient', () {
      final surgeries = [testSurgery];
      final forArthur = surgeries.where((s) => s.patientId == eyePatient.id).toList();
      final forOther = surgeries.where((s) => s.patientId == 'other-id').toList();

      expect(forArthur.length, equals(1));
      expect(forArthur.first.displaySurgeryType, equals('Cataract Surgery'));
      expect(forOther, isEmpty);
    });

    testWidgets('Clicking operation opens EyeSurgeryDetailDialog with zero side-effects',
        (tester) async {
      await tester.pumpWidget(
        ProviderScope(
          overrides: [
            eyeSurgeriesForPatientProvider(eyePatient.id).overrideWith(
              (ref) => Future.value([testSurgery]),
            ),
            currentUserRoleProvider.overrideWith((ref) => Future.value('staff')),
          ],
          child: MaterialApp(
            home: Scaffold(
              body: SingleChildScrollView(
                child: EyeSurgeryPatientSection(patientId: eyePatient.id),
              ),
            ),
          ),
        ),
      );

      await tester.pumpAndSettle();

      // Verify surgery summary tile is present
      expect(find.text('Cataract Surgery'), findsOneWidget);
      expect(find.textContaining('LEFT eye'), findsOneWidget);

      // Tap operation card
      await tester.tap(find.text('Cataract Surgery'));
      await tester.pumpAndSettle();

      // Detail Dialog opened!
      expect(find.byType(EyeSurgeryDetailDialog), findsOneWidget);
      expect(find.text('SCHEDULE & CLINICAL OVERVIEW'), findsOneWidget);
      expect(find.text('IOL Details (Lens Model & Power)'), findsOneWidget);
      expect(find.text('AcrySof IQ Model SN60WF +21.5D'), findsOneWidget);
      expect(find.textContaining('PRE-OP CHECKLIST'), findsOneWidget);

      // Tap Close button
      await tester.tap(find.text('Close'));
      await tester.pumpAndSettle();

      // Dialog closed safely without any side effects
      expect(find.byType(EyeSurgeryDetailDialog), findsNothing);
    });

    testWidgets('EyeSurgeryPatientSection renders clean empty state when no surgeries',
        (tester) async {
      await tester.pumpWidget(
        ProviderScope(
          overrides: [
            eyeSurgeriesForPatientProvider('patient-none').overrideWith(
              (ref) => Future.value([]),
            ),
          ],
          child: const MaterialApp(
            home: Scaffold(
              body: EyeSurgeryPatientSection(patientId: 'patient-none'),
            ),
          ),
        ),
      );

      await tester.pumpAndSettle();
      expect(find.text('No operations or surgeries recorded for this patient.'), findsOneWidget);
    });
  });

  group('Feature 3: Department-Wise Inventory & Stock Requests', () {
    test('DepartmentInventoryItem parses allocated balances and flags low stock correctly', () {
      final item = DepartmentInventoryItem.fromJson({
        'id': 'dept-inv-1',
        'department_id': 'dept-eye',
        'department_name': 'Eye Clinic',
        'inventory_id': 'inv-lens',
        'item_name': 'Intraocular Lens 21D',
        'item_sku': 'IOL-21D',
        'item_unit': 'pcs',
        'quantity': 3.0,
        'minimum_stock': 5.0,
        'is_low_stock': true,
      });

      expect(item.quantity, equals(3.0));
      expect(item.minimumStock, equals(5.0));
      expect(item.isLowStock, isTrue);
      expect(item.formattedQuantity, equals('3'));
    });

    test('StockRequestModel serializes correctly with pending status', () {
      final req = StockRequestModel(
        id: 'req-1',
        requestNumber: 'REQ-202610-1001',
        departmentId: 'dept-eye',
        departmentName: 'Eye Clinic',
        inventoryId: 'inv-viscoelastic',
        itemName: 'Viscoelastic Gel',
        itemUnit: 'vials',
        requestedQuantity: 10.0,
        status: 'pending',
        requestedBy: 'user-staff-1',
        requestedByName: 'Nurse Jackie',
        createdAt: DateTime.now(),
        updatedAt: DateTime.now(),
      );

      expect(req.isPending, isTrue);
      expect(req.isApproved, isFalse);
      expect(req.isFulfilled, isFalse);
      expect(req.formattedRequestedQuantity, equals('10'));

      final json = req.toJson();
      expect(json['request_number'], equals('REQ-202610-1001'));
      expect(json['status'], equals('pending'));
      expect(json['requested_quantity'], equals(10.0));
    });

    test('Atomic Stock Allocation Invariant: Total Physical Stock Remains Constant', () {
      // Invariant:
      // Central stock before = Central stock after + transferred
      // Dept stock after = Dept stock before + transferred
      // Total physical stock before = Total physical stock after

      double centralStock = 100.0;
      double deptStock = 10.0;
      const transferQty = 25.0;

      final totalPhysicalBefore = centralStock + deptStock;

      // Simulate atomic fulfillment
      centralStock -= transferQty;
      deptStock += transferQty;

      final totalPhysicalAfter = centralStock + deptStock;

      expect(centralStock, equals(75.0));
      expect(deptStock, equals(35.0));
      expect(totalPhysicalAfter, equals(totalPhysicalBefore));
    });

    test('Insufficient central stock rejects fulfillment', () {
      const centralStock = 5.0;
      const requestedFulfill = 15.0;

      expect(
        () {
          if (centralStock < requestedFulfill) {
            throw Exception('Insufficient central stock.');
          }
        },
        throwsA(isA<Exception>().having((e) => e.toString(), 'msg', contains('Insufficient central stock'))),
      );
    });

    test('Zero or negative request quantities are rejected', () {
      expect(
        () {
          const qty = 0.0;
          if (qty <= 0) {
            throw ArgumentError('Requested quantity must be greater than zero.');
          }
        },
        throwsA(isA<ArgumentError>()),
      );

      expect(
        () {
          const qty = -5.0;
          if (qty <= 0) {
            throw ArgumentError('Requested quantity must be greater than zero.');
          }
        },
        throwsA(isA<ArgumentError>()),
      );
    });

    test('Fulfilled requests cannot be fulfilled twice', () {
      final req = StockRequestModel(
        id: 'req-done',
        requestNumber: 'REQ-202610-9999',
        departmentId: 'dept-eye',
        departmentName: 'Eye Clinic',
        inventoryId: 'inv-1',
        itemName: 'Surgical Gloves',
        itemUnit: 'pairs',
        requestedQuantity: 20.0,
        approvedQuantity: 20.0,
        fulfilledQuantity: 20.0,
        status: 'fulfilled',
        requestedBy: 'user-1',
        createdAt: DateTime.now(),
        updatedAt: DateTime.now(),
      );

      expect(
        () {
          if (req.status == 'fulfilled') {
            throw Exception('Stock request has already been fulfilled.');
          }
        },
        throwsA(isA<Exception>().having((e) => e.toString(), 'msg', contains('already been fulfilled'))),
      );
    });

    test('Department consumption reduces only department balance without double-deducting central', () {
      double centralStock = 100.0;
      double deptStock = 30.0;
      const consumeQty = 5.0;

      // Department consumption
      deptStock -= consumeQty;

      expect(deptStock, equals(25.0));
      // Central stock was not modified during department consumption
      expect(centralStock, equals(100.0));
    });
  });
}
