import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:mkes_care/features/auth/providers/auth_provider.dart';
import 'package:mkes_care/features/billing/models/billing_invoice_model.dart';
import 'package:mkes_care/features/eye/models/eye_surgery_insurance_model.dart';
import 'package:mkes_care/features/eye/models/eye_surgery_item_model.dart';
import 'package:mkes_care/features/eye/models/eye_surgery_model.dart';
import 'package:mkes_care/features/eye/providers/eye_surgery_provider.dart';
import 'package:mkes_care/features/eye/screens/eye_surgery_screen.dart';
import 'package:mkes_care/features/eye/widgets/eye_surgery_detail_dialog.dart';
import 'package:mkes_care/features/eye/widgets/eye_surgery_discharge_dialog.dart';

class _FakeInsuranceNotifier extends EyeSurgeryInsuranceNotifier {
  final EyeSurgeryInsuranceModel? _model;
  _FakeInsuranceNotifier(this._model);

  @override
  Future<EyeSurgeryInsuranceModel?> build(String arg) async => _model;
}

class _FakeSurgeryListNotifier extends EyeSurgeryListNotifier {
  final List<EyeSurgeryModel> _surgeries;
  _FakeSurgeryListNotifier(this._surgeries);

  @override
  Future<List<EyeSurgeryModel>> build() async => _surgeries;
}

class _FakeItemsNotifier extends EyeSurgeryItemsNotifier {
  final List<EyeSurgeryItemModel> _items;
  _FakeItemsNotifier(this._items);

  @override
  Future<List<EyeSurgeryItemModel>> build(String arg) async => _items;
}

EyeSurgeryModel _createSampleSurgery({
  String id = 'surg-001',
  String patientId = 'pat-100',
  String status = 'billing',
}) {
  return EyeSurgeryModel(
    id: id,
    patientId: patientId,
    patientName: 'John Doe',
    patientNumber: 'P-100',
    surgeryType: 'cataract',
    eyeSide: 'right',
    preOpDate: DateTime.now(),
    surgeryDate: DateTime.now(),
    status: status,
    assignedStaffId: 'staff-1',
    assignedStaffName: 'Dr. Jane Smith',
    preOpChecklist: {
      for (final key in EyeSurgeryModel.checklistItems.keys) key: true,
    },
    createdAt: DateTime.now(),
    updatedAt: DateTime.now(),
  );
}

void main() {
  group('1. Eye Surgery Workflow & Stage Transitions', () {
    test('Workflow includes Billing stage between Post-op and Discharged', () {
      expect(EyeSurgeryModel.statuses, contains('billing'));
      expect(
        EyeSurgeryModel.statuses,
        equals([
          'scheduled',
          'pre_op',
          'in_surgery',
          'post_op',
          'billing',
          'discharged',
          'cancelled',
          'missed',
        ]),
      );
    });

    test('Validates forward transition order: scheduled -> pre_op -> in_surgery -> post_op -> billing -> discharged', () {
      expect(EyeSurgeryModel.canTransition('scheduled', 'pre_op'), isTrue);
      expect(EyeSurgeryModel.canTransition('pre_op', 'in_surgery'), isTrue);
      expect(EyeSurgeryModel.canTransition('in_surgery', 'post_op'), isTrue);
      expect(EyeSurgeryModel.canTransition('post_op', 'billing'), isTrue);
      expect(EyeSurgeryModel.canTransition('billing', 'discharged'), isTrue);
    });

    test('Allows post_op -> billing as standard, and supports backwards compatibility to discharged', () {
      expect(EyeSurgeryModel.canTransition('post_op', 'billing'), isTrue);
      expect(EyeSurgeryModel.canTransition('post_op', 'discharged'), isTrue);
    });

    test('Rejects backward transitions', () {
      expect(EyeSurgeryModel.canTransition('billing', 'post_op'), isFalse);
      expect(EyeSurgeryModel.canTransition('billing', 'in_surgery'), isFalse);
      expect(EyeSurgeryModel.canTransition('discharged', 'billing'), isFalse);
    });

    test('Allows cancellation from active billing stage but not after discharge', () {
      expect(EyeSurgeryModel.canTransition('billing', 'cancelled'), isTrue);
      expect(EyeSurgeryModel.canTransition('discharged', 'cancelled'), isFalse);
    });
  });

  group('2. Surgery Billing & Invoice Model Integration', () {
    test('BillingInvoiceModel links directly to eyeSurgeryId', () {
      final invoice = BillingInvoiceModel(
        id: 'inv-surg-1',
        invoiceNumber: 'INV-SURG-001',
        patientId: 'pat-100',
        department: 'eye',
        subtotal: 50000.0,
        totalAmount: 50000.0,
        amountPaid: 20000.0,
        paymentStatus: 'partially_paid',
        eyeSurgeryId: 'surg-001',
        createdAt: DateTime(2026, 10, 16),
        updatedAt: DateTime(2026, 10, 16),
      );

      expect(invoice.eyeSurgeryId, equals('surg-001'));
      expect(invoice.remainingAmount, equals(30000.0));
      expect(invoice.isPartiallyPaid, isTrue);
      expect(invoice.isPaid, isFalse);

      final json = invoice.toJson();
      expect(json['eye_surgery_id'], equals('surg-001'));

      final fromJson = BillingInvoiceModel.fromJson(json);
      expect(fromJson.eyeSurgeryId, equals('surg-001'));
      expect(fromJson.totalAmount, equals(50000.0));
      expect(fromJson.amountPaid, equals(20000.0));
    });

    test('Multiple surgeries for the same patient have distinct surgery-linked invoices', () {
      final inv1 = BillingInvoiceModel(
        id: 'inv-1',
        invoiceNumber: 'INV-1',
        patientId: 'pat-100',
        department: 'eye',
        subtotal: 45000.0,
        totalAmount: 45000.0,
        eyeSurgeryId: 'surg-right-eye',
        createdAt: DateTime.now(),
        updatedAt: DateTime.now(),
      );

      final inv2 = BillingInvoiceModel(
        id: 'inv-2',
        invoiceNumber: 'INV-2',
        patientId: 'pat-100',
        department: 'eye',
        subtotal: 55000.0,
        totalAmount: 55000.0,
        eyeSurgeryId: 'surg-left-eye',
        createdAt: DateTime.now(),
        updatedAt: DateTime.now(),
      );

      expect(inv1.eyeSurgeryId, isNot(equals(inv2.eyeSurgeryId)));
      expect(inv1.patientId, equals(inv2.patientId));
      expect(inv1.totalAmount, equals(45000.0));
      expect(inv2.totalAmount, equals(55000.0));
    });
  });

  group('3. Eye Surgery Insurance Models & Claim Status Serialization', () {
    test('Serializes and deserializes EyeSurgeryInsuranceModel with all fields', () {
      final model = EyeSurgeryInsuranceModel(
        id: 'ins-001',
        eyeSurgeryId: 'surg-001',
        patientId: 'pat-100',
        insuranceProvider: 'Star Health',
        arrangement: EyeSurgeryInsuranceArrangement.cashless,
        policyNumber: 'POL-12345',
        memberId: 'MEM-99',
        claimNumber: 'CLM-7788',
        coverageDetails: 'Cataract package up to 40,000',
        estimatedAmount: 40000.0,
        approvedAmount: 35000.0,
        amountReceived: 20000.0,
        claimSubmissionDate: DateTime(2026, 10, 10),
        claimStatus: EyeSurgeryClaimStatus.approved,
        notes: 'Pre-auth approved',
        createdAt: DateTime(2026, 10, 10),
        updatedAt: DateTime(2026, 10, 11),
      );

      expect(model.isCashless, isTrue);
      expect(model.isReimbursement, isFalse);
      expect(model.isApproved, isTrue);
      expect(model.claimStatus.label, equals('Approved'));

      final json = model.toJson();
      expect(json['arrangement'], equals('cashless'));
      expect(json['claim_status'], equals('approved'));
      expect(json['approved_amount'], equals(35000.0));

      final restored = EyeSurgeryInsuranceModel.fromJson(json);
      expect(restored.insuranceProvider, equals('Star Health'));
      expect(restored.policyNumber, equals('POL-12345'));
      expect(restored.approvedAmount, equals(35000.0));
      expect(restored.isApproved, isTrue);
    });

    test('Support all required claim statuses distinctly', () {
      final statuses = [
        EyeSurgeryClaimStatus.notSubmitted,
        EyeSurgeryClaimStatus.submitted,
        EyeSurgeryClaimStatus.underReview,
        EyeSurgeryClaimStatus.approved,
        EyeSurgeryClaimStatus.partiallyApproved,
        EyeSurgeryClaimStatus.rejected,
        EyeSurgeryClaimStatus.settled,
      ];

      for (final s in statuses) {
        expect(EyeSurgeryClaimStatus.fromString(s.value), equals(s));
      }
    });

    test('Keep claim status separate from payment status (Approved does not mean paid)', () {
      final approvedInsurance = EyeSurgeryInsuranceModel(
        id: 'ins-002',
        eyeSurgeryId: 'surg-001',
        patientId: 'pat-100',
        insuranceProvider: 'HDFC ERGO',
        arrangement: EyeSurgeryInsuranceArrangement.cashless,
        approvedAmount: 40000.0,
        amountReceived: 0.0, // Approved, but zero received!
        claimStatus: EyeSurgeryClaimStatus.approved,
        createdAt: DateTime.now(),
        updatedAt: DateTime.now(),
      );

      expect(approvedInsurance.isApproved, isTrue);
      expect(approvedInsurance.amountReceived, equals(0.0));
      expect(approvedInsurance.totalClinicPaymentsReceived, equals(0.0));
    });
  });

  group('4. Exact Patient Payment and Insurance Financial Rules', () {
    test('Section 4 Prompt Example: Bill ₹50,000, Approved ₹35,000, Insurer paid ₹20,000', () {
      // Prompt specification:
      // "Example: If the surgery bill is ₹50,000 and the final approved insurance coverage is ₹35,000,
      // the patient's share is ₹15,000, assuming no other adjustments.
      // If the insurer has paid only ₹20,000 directly to the clinic, the remaining ₹15,000 from
      // the insurer must be shown as an insurer outstanding amount, while the patient's ₹15,000 share
      // is tracked separately. Do not add the insurer's pending ₹15,000 to the patient's balance."

      final insurance = EyeSurgeryInsuranceModel(
        id: 'ins-ex',
        eyeSurgeryId: 'surg-ex',
        patientId: 'pat-ex',
        insuranceProvider: 'National Insurance',
        arrangement: EyeSurgeryInsuranceArrangement.cashless,
        estimatedAmount: 45000.0,
        approvedAmount: 35000.0,
        amountReceived: 20000.0,
        claimStatus: EyeSurgeryClaimStatus.partiallyApproved,
        createdAt: DateTime.now(),
        updatedAt: DateTime.now(),
        payments: [
          EyeSurgeryInsurancePaymentModel(
            id: 'pay-ins-1',
            insuranceId: 'ins-ex',
            eyeSurgeryId: 'surg-ex',
            amount: 20000.0,
            paymentDate: DateTime.now(),
            paymentDestination: 'clinic',
            paymentReference: 'NEFT-12345',
          ),
        ],
      );

      final summary = EyeSurgeryFinancialSummary.calculate(
        surgeryBill: 50000.0,
        insurance: insurance,
        patientPayments: 0.0,
      );

      // Verify the 8 separate amounts:
      // 1. Total surgery bill
      expect(summary.totalSurgeryBill, equals(50000.0));
      // 2. Estimated insurance coverage
      expect(summary.estimatedInsuranceCoverage, equals(45000.0));
      // 3. Approved insurance coverage
      expect(summary.approvedInsuranceCoverage, equals(35000.0));
      // 4. Insurance amount actually received by the clinic
      expect(summary.insuranceAmountReceivedByClinic, equals(20000.0));
      // 5. Insurance amount still pending (insurer outstanding)
      expect(summary.insuranceAmountPending, equals(15000.0));
      // 6. Patient's payable share
      expect(summary.patientPayableShare, equals(15000.0));
      // 7. Patient payments received
      expect(summary.patientPaymentsReceived, equals(0.0));
      // 8. Remaining patient balance
      expect(summary.remainingPatientBalance, equals(15000.0));

      // CRITICAL: Insurer pending ₹15,000 is NOT added to patient balance!
      expect(summary.remainingPatientBalance, isNot(equals(30000.0)));
      expect(summary.remainingPatientBalance, equals(15000.0));
    });

    test('Cashless: When patient makes a partial payment against their share', () {
      final insurance = EyeSurgeryInsuranceModel(
        id: 'ins-ex2',
        eyeSurgeryId: 'surg-ex2',
        patientId: 'pat-ex2',
        insuranceProvider: 'Care Health',
        arrangement: EyeSurgeryInsuranceArrangement.cashless,
        approvedAmount: 30000.0,
        amountReceived: 30000.0, // Insurer settled their share in full
        claimStatus: EyeSurgeryClaimStatus.approved,
        createdAt: DateTime.now(),
        updatedAt: DateTime.now(),
      );

      // Bill is ₹40,000. Insurer approved & paid ₹30,000. Patient share is ₹10,000.
      // Patient pays ₹6,000.
      final summary = EyeSurgeryFinancialSummary.calculate(
        surgeryBill: 40000.0,
        insurance: insurance,
        patientPayments: 6000.0,
      );

      expect(summary.patientPayableShare, equals(10000.0));
      expect(summary.patientPaymentsReceived, equals(6000.0));
      expect(summary.remainingPatientBalance, equals(4000.0));
      expect(summary.insuranceAmountPending, equals(0.0));
    });

    test('Cashless: Rejected claim shifts entire payable share to patient', () {
      final insurance = EyeSurgeryInsuranceModel(
        id: 'ins-rej',
        eyeSurgeryId: 'surg-rej',
        patientId: 'pat-rej',
        insuranceProvider: 'Universal Sompo',
        arrangement: EyeSurgeryInsuranceArrangement.cashless,
        estimatedAmount: 30000.0,
        approvedAmount: 0.0,
        claimStatus: EyeSurgeryClaimStatus.rejected,
        rejectionReason: 'Pre-existing condition excluded',
        createdAt: DateTime.now(),
        updatedAt: DateTime.now(),
      );

      final summary = EyeSurgeryFinancialSummary.calculate(
        surgeryBill: 45000.0,
        insurance: insurance,
        patientPayments: 5000.0,
      );

      expect(summary.patientPayableShare, equals(45000.0));
      expect(summary.remainingPatientBalance, equals(40000.0));
      expect(summary.insuranceAmountPending, equals(0.0));
      expect(summary.approvedInsuranceCoverage, equals(0.0));
    });

    test('Reimbursement: Patient pays clinic in full; patient-directed reimbursement is tracked separately', () {
      // In Reimbursement:
      // "Do not count an insurance reimbursement as money received by the clinic unless
      // the payment was actually received by the clinic. Where the patient pays the clinic first
      // and later receives reimbursement personally, track the claim outcome without falsely recording
      // that reimbursement as a payment to the clinic."

      final insurance = EyeSurgeryInsuranceModel(
        id: 'ins-reimb',
        eyeSurgeryId: 'surg-reimb',
        patientId: 'pat-reimb',
        insuranceProvider: 'Religare',
        arrangement: EyeSurgeryInsuranceArrangement.reimbursement,
        estimatedAmount: 30000.0,
        approvedAmount: 28000.0,
        claimStatus: EyeSurgeryClaimStatus.settled,
        createdAt: DateTime.now(),
        updatedAt: DateTime.now(),
        payments: [
          EyeSurgeryInsurancePaymentModel(
            id: 'pay-reimb-1',
            insuranceId: 'ins-reimb',
            eyeSurgeryId: 'surg-reimb',
            amount: 28000.0,
            paymentDate: DateTime.now(),
            paymentDestination: 'patient', // Paid directly to patient!
            paymentReference: 'CLAIM-SETTLED-DIRECT',
          ),
        ],
      );

      final summary = EyeSurgeryFinancialSummary.calculate(
        surgeryBill: 35000.0,
        insurance: insurance,
        patientPayments: 35000.0, // Patient paid clinic ₹35,000
      );

      expect(summary.patientPayableShare, equals(35000.0));
      expect(summary.patientPaymentsReceived, equals(35000.0));
      expect(summary.remainingPatientBalance, equals(0.0));
      // Clinic received NO money from insurer directly:
      expect(summary.insuranceAmountReceivedByClinic, equals(0.0));
      expect(summary.insuranceAmountPending, equals(0.0));
      // Patient reimbursement is recorded cleanly:
      expect(summary.patientReimbursementReceived, equals(28000.0));
    });

    test('Multiple insurer payments against single claim are summed properly by destination', () {
      final payments = [
        EyeSurgeryInsurancePaymentModel(
          insuranceId: 'ins-1',
          eyeSurgeryId: 'surg-1',
          amount: 15000.0,
          paymentDate: DateTime(2026, 10, 1),
          paymentDestination: 'clinic',
        ),
        EyeSurgeryInsurancePaymentModel(
          insuranceId: 'ins-1',
          eyeSurgeryId: 'surg-1',
          amount: 10000.0,
          paymentDate: DateTime(2026, 10, 5),
          paymentDestination: 'clinic',
        ),
        EyeSurgeryInsurancePaymentModel(
          insuranceId: 'ins-1',
          eyeSurgeryId: 'surg-1',
          amount: 5000.0,
          paymentDate: DateTime(2026, 10, 7),
          paymentDestination: 'patient',
        ),
      ];

      final ins = EyeSurgeryInsuranceModel(
        id: 'ins-1',
        eyeSurgeryId: 'surg-1',
        patientId: 'pat-1',
        insuranceProvider: 'SBI General',
        arrangement: EyeSurgeryInsuranceArrangement.cashless,
        approvedAmount: 30000.0,
        claimStatus: EyeSurgeryClaimStatus.approved,
        createdAt: DateTime.now(),
        updatedAt: DateTime.now(),
        payments: payments,
      );

      expect(ins.totalClinicPaymentsReceived, equals(25000.0));
      expect(ins.totalPatientReimbursementsReceived, equals(5000.0));
    });
  });

  group('5. Discharge Rules Verification', () {
    testWidgets('EyeSurgeryDischargeDialog shows patient balance and insurer pending amounts separately',
        (tester) async {
      tester.view.devicePixelRatio = 1;
      tester.view.physicalSize = const Size(800, 900);
      addTearDown(tester.view.resetPhysicalSize);
      addTearDown(tester.view.resetDevicePixelRatio);

      final surgery = _createSampleSurgery(status: 'billing');

      final insurance = EyeSurgeryInsuranceModel(
        id: 'ins-dlg',
        eyeSurgeryId: surgery.id,
        patientId: surgery.patientId,
        insuranceProvider: 'Star Health',
        arrangement: EyeSurgeryInsuranceArrangement.cashless,
        estimatedAmount: 40000.0,
        approvedAmount: 30000.0,
        amountReceived: 18000.0,
        claimStatus: EyeSurgeryClaimStatus.approved,
        createdAt: DateTime.now(),
        updatedAt: DateTime.now(),
      );

      final invoice = BillingInvoiceModel(
        id: 'inv-dlg',
        invoiceNumber: 'INV-SURG-DISCHARGE',
        patientId: surgery.patientId,
        department: 'eye',
        subtotal: 50000.0,
        totalAmount: 50000.0,
        amountPaid: 15000.0,
        paymentStatus: 'partially_paid',
        eyeSurgeryId: surgery.id,
        createdAt: DateTime.now(),
        updatedAt: DateTime.now(),
      );

      final container = ProviderContainer(
        overrides: [
          eyeSurgeryInvoiceProvider(surgery.id).overrideWith(
            (ref) async => invoice,
          ),
          eyeSurgeryInsuranceProvider.overrideWith(
            () => _FakeInsuranceNotifier(insurance),
          ),
        ],
      );
      addTearDown(container.dispose);

      await tester.pumpWidget(
        UncontrolledProviderScope(
          container: container,
          child: MaterialApp(
            home: Scaffold(
              body: EyeSurgeryDischargeDialog(surgery: surgery),
            ),
          ),
        ),
      );
      await tester.pumpAndSettle();

      // Check dialog elements
      expect(find.text('Confirm Patient Discharge'), findsOneWidget);
      expect(find.text('SURGERY BILLING STATUS'), findsOneWidget);
      expect(find.text('INSURANCE STATUS (EYE SURGERY)'), findsOneWidget);
      expect(find.text('Remaining Patient Balance'), findsOneWidget);
      expect(find.text('Pending from Insurer (Separate from Patient)'), findsOneWidget);

      // Verify that discharge button exists (pending insurance does NOT block discharge)
      expect(find.text('Confirm Discharge'), findsOneWidget);
    });
  });

  group('6. Workflow Visibility & Premature Billing Prevention (Requirement 1)', () {
    test('canAccessBilling model getter enforces billing/discharged only', () {
      final scheduled = _createSampleSurgery(status: 'scheduled');
      final preOp = _createSampleSurgery(status: 'pre_op');
      final inSurgery = _createSampleSurgery(status: 'in_surgery');
      final postOp = _createSampleSurgery(status: 'post_op');
      final billing = _createSampleSurgery(status: 'billing');
      final discharged = _createSampleSurgery(status: 'discharged');

      expect(scheduled.canAccessBilling, isFalse);
      expect(preOp.canAccessBilling, isFalse);
      expect(inSurgery.canAccessBilling, isFalse);
      expect(postOp.canAccessBilling, isFalse);
      expect(billing.canAccessBilling, isTrue);
      expect(discharged.canAccessBilling, isTrue);
    });

    testWidgets('Scheduled surgery dialog does not expose Billing and Insurance tabs', (tester) async {
      tester.view.devicePixelRatio = 1;
      tester.view.physicalSize = const Size(800, 900);
      addTearDown(tester.view.resetPhysicalSize);
      addTearDown(tester.view.resetDevicePixelRatio);

      final surgery = _createSampleSurgery(status: 'scheduled');
      final container = ProviderContainer(
        overrides: [
          currentUserRoleProvider.overrideWith((ref) => Future.value('admin')),
          eyeSurgeryListProvider.overrideWith(() => _FakeSurgeryListNotifier([surgery])),
          eyeSurgeryInvoiceProvider(surgery.id).overrideWith((ref) async => null),
          eyeSurgeryInsuranceProvider.overrideWith(() => _FakeInsuranceNotifier(null)),
          eyeSurgeryItemsProvider.overrideWith(() => _FakeItemsNotifier([])),
        ],
      );
      addTearDown(container.dispose);

      await tester.pumpWidget(
        UncontrolledProviderScope(
          container: container,
          child: MaterialApp(
            home: Scaffold(
              body: EyeSurgeryDetailDialog(surgery: surgery),
            ),
          ),
        ),
      );
      await tester.pumpAndSettle();

      expect(find.text('Surgery Billing'), findsNothing);
      expect(find.text('Insurance'), findsNothing);
      expect(find.text('Balances & History'), findsNothing);
      expect(find.text('SCHEDULE & CLINICAL OVERVIEW'), findsOneWidget);
    });

    testWidgets('Post-op surgery dialog does not expose premature billing tabs', (tester) async {
      tester.view.devicePixelRatio = 1;
      tester.view.physicalSize = const Size(800, 900);
      addTearDown(tester.view.resetPhysicalSize);
      addTearDown(tester.view.resetDevicePixelRatio);

      final surgery = _createSampleSurgery(status: 'post_op');
      final container = ProviderContainer(
        overrides: [
          currentUserRoleProvider.overrideWith((ref) => Future.value('admin')),
          eyeSurgeryListProvider.overrideWith(() => _FakeSurgeryListNotifier([surgery])),
          eyeSurgeryInvoiceProvider(surgery.id).overrideWith((ref) async => null),
          eyeSurgeryInsuranceProvider.overrideWith(() => _FakeInsuranceNotifier(null)),
          eyeSurgeryItemsProvider.overrideWith(() => _FakeItemsNotifier([])),
        ],
      );
      addTearDown(container.dispose);

      await tester.pumpWidget(
        UncontrolledProviderScope(
          container: container,
          child: MaterialApp(
            home: Scaffold(
              body: EyeSurgeryDetailDialog(surgery: surgery),
            ),
          ),
        ),
      );
      await tester.pumpAndSettle();

      expect(find.text('Surgery Billing'), findsNothing);
      expect(find.text('Insurance'), findsNothing);
    });

    testWidgets('Scheduled surgery card in EyeSurgeryScreen hides Billing & Insurance action', (tester) async {
      tester.view.devicePixelRatio = 1;
      tester.view.physicalSize = const Size(800, 900);
      addTearDown(tester.view.resetPhysicalSize);
      addTearDown(tester.view.resetDevicePixelRatio);

      final scheduledSurgery = _createSampleSurgery(
        id: 'surg-sched',
        status: 'scheduled',
      );

      final container = ProviderContainer(
        overrides: [
          currentUserRoleProvider.overrideWith((ref) => Future.value('admin')),
          eyeSurgeryListProvider.overrideWith(() => _FakeSurgeryListNotifier([scheduledSurgery])),
          eyeSurgeryInvoiceProvider(scheduledSurgery.id).overrideWith((ref) async => null),
          eyeSurgeryInsuranceProvider.overrideWith(() => _FakeInsuranceNotifier(null)),
          eyeSurgeryItemsProvider.overrideWith(() => _FakeItemsNotifier([])),
        ],
      );
      addTearDown(container.dispose);

      await tester.pumpWidget(
        UncontrolledProviderScope(
          container: container,
          child: const MaterialApp(
            home: Scaffold(
              body: EyeSurgeryScreen(),
            ),
          ),
        ),
      );
      await tester.pumpAndSettle();

      expect(find.text('Billing & Insurance'), findsNothing);
      expect(find.textContaining('Pre-op Checklist'), findsOneWidget);

      await tester.tap(find.byIcon(Icons.more_vert));
      await tester.pumpAndSettle();

      expect(find.text('Billing & Insurance'), findsNothing);
      expect(find.text('Surgery details'), findsOneWidget);
    });
  });

  group('7. Discharged Surgery: Exactly Two Actions (Requirement 5 & 6)', () {
    testWidgets('Discharged surgery card in EyeSurgeryScreen shows exactly two actions', (tester) async {
      tester.view.devicePixelRatio = 1;
      tester.view.physicalSize = const Size(800, 900);
      addTearDown(tester.view.resetPhysicalSize);
      addTearDown(tester.view.resetDevicePixelRatio);

      final discharged = _createSampleSurgery(
        id: 'surg-disch',
        status: 'discharged',
      );

      final container = ProviderContainer(
        overrides: [
          currentUserRoleProvider.overrideWith((ref) => Future.value('admin')),
          eyeSurgeryListProvider.overrideWith(() => _FakeSurgeryListNotifier([discharged])),
          eyeSurgeryInvoiceProvider(discharged.id).overrideWith((ref) async => null),
          eyeSurgeryInsuranceProvider.overrideWith(() => _FakeInsuranceNotifier(null)),
          eyeSurgeryItemsProvider.overrideWith(() => _FakeItemsNotifier([])),
        ],
      );
      addTearDown(container.dispose);

      await tester.pumpWidget(
        UncontrolledProviderScope(
          container: container,
          child: const MaterialApp(
            home: Scaffold(
              body: EyeSurgeryScreen(),
            ),
          ),
        ),
      );
      await tester.pumpAndSettle();

      expect(find.text('Schedule Follow-up Appointment'), findsOneWidget);
      expect(find.text('Billing & Insurance'), findsOneWidget);
      expect(find.textContaining('Pre-op Checklist'), findsNothing);
      expect(find.text('Assign Staff'), findsNothing);
      expect(find.text('Reassign Staff'), findsNothing);

      await tester.tap(find.byIcon(Icons.more_vert));
      await tester.pumpAndSettle();

      expect(find.text('Schedule follow-up appointment'), findsOneWidget);
      expect(find.text('Billing & Insurance'), findsNWidgets(2));
      expect(find.text('Surgery details'), findsNothing);
      expect(find.text('Edit surgery'), findsNothing);
      expect(find.text('Assign staff'), findsNothing);
      expect(find.text('Pre-op checklist'), findsNothing);
    });

    testWidgets('Discharged surgery dialog hides Pre-op Checklist & Staff Assign, shows two actions', (tester) async {
      tester.view.devicePixelRatio = 1;
      tester.view.physicalSize = const Size(800, 900);
      addTearDown(tester.view.resetPhysicalSize);
      addTearDown(tester.view.resetDevicePixelRatio);

      final discharged = _createSampleSurgery(
        id: 'surg-disch-dlg',
        status: 'discharged',
      );

      final container = ProviderContainer(
        overrides: [
          currentUserRoleProvider.overrideWith((ref) => Future.value('admin')),
          eyeSurgeryListProvider.overrideWith(() => _FakeSurgeryListNotifier([discharged])),
          eyeSurgeryInvoiceProvider(discharged.id).overrideWith((ref) async => null),
          eyeSurgeryInsuranceProvider.overrideWith(() => _FakeInsuranceNotifier(null)),
          eyeSurgeryItemsProvider.overrideWith(() => _FakeItemsNotifier([])),
        ],
      );
      addTearDown(container.dispose);

      await tester.pumpWidget(
        UncontrolledProviderScope(
          container: container,
          child: MaterialApp(
            home: Scaffold(
              body: EyeSurgeryDetailDialog(surgery: discharged),
            ),
          ),
        ),
      );
      await tester.pumpAndSettle();

      expect(find.text('DISCHARGED SURGERY ACTIONS'), findsOneWidget);
      expect(find.text('Schedule Follow-up Appointment'), findsOneWidget);
      expect(find.textContaining('PRE-OP CHECKLIST'), findsNothing);
      expect(find.text('Assign Staff'), findsNothing);
    });

    test('Defensive check: assignStaff rejects discharged surgery with StateError', () async {
      final discharged = _createSampleSurgery(
        id: 'surg-disch-err',
        status: 'discharged',
      );

      final notifier = _FakeSurgeryListNotifier([discharged]);
      final container = ProviderContainer(
        overrides: [
          eyeSurgeryListProvider.overrideWith(() => notifier),
        ],
      );
      addTearDown(container.dispose);
      await container.read(eyeSurgeryListProvider.future);

      expect(
        () => container.read(eyeSurgeryListProvider.notifier).assignStaff(
              discharged.id,
              'staff-99',
            ),
        throwsA(isA<StateError>()),
      );
    });
  });

  group('8. Layout Overflow Prevention & Billing Interface (Requirements 2 & 3)', () {
    testWidgets('Small screen (360x640) renders empty billing tab without 93-pixel overflow', (tester) async {
      tester.view.devicePixelRatio = 1;
      tester.view.physicalSize = const Size(360, 640);
      addTearDown(tester.view.resetPhysicalSize);
      addTearDown(tester.view.resetDevicePixelRatio);

      final surgery = _createSampleSurgery(status: 'billing');
      final container = ProviderContainer(
        overrides: [
          currentUserRoleProvider.overrideWith((ref) => Future.value('admin')),
          eyeSurgeryListProvider.overrideWith(() => _FakeSurgeryListNotifier([surgery])),
          eyeSurgeryInvoiceProvider(surgery.id).overrideWith((ref) async => null),
          eyeSurgeryInsuranceProvider.overrideWith(() => _FakeInsuranceNotifier(null)),
          eyeSurgeryItemsProvider.overrideWith(() => _FakeItemsNotifier([])),
        ],
      );
      addTearDown(container.dispose);

      await tester.pumpWidget(
        UncontrolledProviderScope(
          container: container,
          child: MaterialApp(
            home: Scaffold(
              body: EyeSurgeryDetailDialog(surgery: surgery, initialTabIndex: 1),
            ),
          ),
        ),
      );
      await tester.pumpAndSettle();

      expect(tester.takeException(), isNull);
      expect(find.text('No Invoice Linked to This Surgery'), findsOneWidget);
      expect(find.text('Create Surgery Invoice'), findsOneWidget);

      await tester.ensureVisible(find.text('Insurance'));
      await tester.tap(find.text('Insurance'));
      await tester.pumpAndSettle();

      expect(tester.takeException(), isNull);
      expect(find.text('No Insurance Configured for this Eye Surgery'), findsOneWidget);
      expect(find.text('Configure Surgery Insurance'), findsOneWidget);
    });

    testWidgets('Error state in billing tab provides retry button and does not overflow', (tester) async {
      tester.view.devicePixelRatio = 1;
      tester.view.physicalSize = const Size(360, 640);
      addTearDown(tester.view.resetPhysicalSize);
      addTearDown(tester.view.resetDevicePixelRatio);

      final surgery = _createSampleSurgery(status: 'billing');
      final container = ProviderContainer(
        overrides: [
          currentUserRoleProvider.overrideWith((ref) => Future.value('admin')),
          eyeSurgeryListProvider.overrideWith(() => _FakeSurgeryListNotifier([surgery])),
          eyeSurgeryInvoiceProvider(surgery.id).overrideWith((ref) async => throw Exception('Network timeout')),
          eyeSurgeryInsuranceProvider.overrideWith(() => _FakeInsuranceNotifier(null)),
          eyeSurgeryItemsProvider.overrideWith(() => _FakeItemsNotifier([])),
        ],
      );
      addTearDown(container.dispose);

      await tester.pumpWidget(
        UncontrolledProviderScope(
          container: container,
          child: MaterialApp(
            home: Scaffold(
              body: EyeSurgeryDetailDialog(surgery: surgery, initialTabIndex: 1),
            ),
          ),
        ),
      );
      await tester.pumpAndSettle();

      expect(tester.takeException(), isNull);
      expect(find.text('Unable to load invoice'), findsOneWidget);
      expect(find.text('Retry'), findsOneWidget);
    });
  });
}
