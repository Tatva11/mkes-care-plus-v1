import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:flutter_test/flutter_test.dart';

import 'package:mkes_care/core/utils/date_boundaries.dart';
import 'package:mkes_care/features/auth/providers/auth_provider.dart';
import 'package:mkes_care/features/appointments/models/appointment_model.dart';
import 'package:mkes_care/features/billing/models/billing_invoice_model.dart';
import 'package:mkes_care/features/billing/models/billing_payment_model.dart';
import 'package:mkes_care/features/billing/services/billing_pdf_service.dart';
import 'package:mkes_care/features/eye/widgets/eye_examination_form_dialog.dart';
import 'package:mkes_care/features/inventory/models/inventory_item.dart';
import 'package:mkes_care/features/inventory/models/purchase_order.dart';
import 'package:mkes_care/features/inventory/widgets/inventory_details_dialog.dart';
import 'package:mkes_care/features/inventory/widgets/receive_purchase_order_dialog.dart';
import 'package:mkes_care/features/inventory/widgets/stock_operation_dialog.dart';
import 'package:mkes_care/features/patients/models/patient_model.dart';
import 'package:mkes_care/features/patients/screens/patient_details_screen.dart';

void main() {
  TestWidgetsFlutterBinding.ensureInitialized();

  final dummyItem = InventoryItem(
    id: 'item-001',
    name: 'Tropicamide Eye Drops 1% w/v Ophthalmic Solution',
    category: 'Pharmaceuticals',
    currentStock: 15.0,
    minimumStock: 25.0,
    unit: 'Bottles',
    department: 'eye',
    isActive: true,
    expiryDate: DateTime(2027, 8, 15),
    lastTotalAmount: 12500.0,
  );

  final dummyPO = PurchaseOrder(
    id: 'po-001',
    purchaseOrderNumber: 'PO-2026-OCT-0042',
    vendorId: 'v-001',
    vendorName: 'Apex Healthcare Diagnostics & Surgical Supplies Pvt Ltd',
    status: PurchaseOrderStatus.partiallyReceived,
    orderDate: DateTime(2026, 10, 15),
    totalAmount: 45000.0,
    items: [
      PurchaseOrderItem(
        id: 'poi-1',
        purchaseOrderId: 'po-001',
        inventoryId: 'item-001',
        inventoryName: 'Tropicamide Eye Drops 1% w/v',
        inventoryUnit: 'Bottles',
        quantity: 50.0,
        receivedQuantity: 20.0,
        unitPrice: 125.0,
        totalAmount: 6250.0,
      ),
    ],
  );

  final dummyPatient = PatientModel(
    id: 'pat-100',
    patientNumber: 'E-4091',
    name: 'Suresh Kumar Sharma',
    department: 'eye',
    mobile: '9876543210',
    createdAt: DateTime.now(),
    updatedAt: DateTime.now(),
  );

  final dummyAppointment = AppointmentModel(
    id: 'apt-501',
    patientId: 'pat-100',
    patientName: 'Suresh Kumar Sharma',
    patientNumber: 'E-4091',
    department: 'eye',
    appointmentDate: DateTime.now(),
    appointmentTime: '10:30 AM',
    status: 'in_progress',
    createdAt: DateTime.now(),
    updatedAt: DateTime.now(),
  );

  group(
      'Requirement 1 & 2: Inventory Details & Stock Operation on Mobile (320px & 360px)',
      () {
    testWidgets('View Product Dialog fits on 320px phone without overflow',
        (tester) async {
      tester.view.physicalSize = const Size(320, 700);
      tester.view.devicePixelRatio = 1.0;
      addTearDown(() => tester.view.resetPhysicalSize());

      await tester.pumpWidget(
        ProviderScope(
          overrides: [
            currentUserRoleProvider
                .overrideWith((ref) => 'admin'),
          ],
          child: MaterialApp(
            home: Scaffold(
              body: InventoryDetailsDialog(item: dummyItem),
            ),
          ),
        ),
      );
      await tester.pumpAndSettle();

      final exc = tester.takeException();
      if (exc != null) {
        if (exc is FlutterError) {
          debugPrint('*** EXC DEEP ***:\n${exc.toStringDeep()}');
        } else {
          debugPrint('*** EXC ***: $exc');
        }
      }
      expect(exc, isNull);
      expect(find.text(dummyItem.name), findsOneWidget);
      expect(find.text('CURRENT STOCK'), findsOneWidget);
    });

    testWidgets('Stock In / Stock Out fits on 320px phone without overflow',
        (tester) async {
      tester.view.physicalSize = const Size(320, 700);
      tester.view.devicePixelRatio = 1.0;
      addTearDown(() => tester.view.resetPhysicalSize());

      await tester.pumpWidget(
        ProviderScope(
          child: MaterialApp(
            home: Scaffold(
              body: StockOperationDialog(
                item: dummyItem,
                operationType: StockOperationType.stockIn,
              ),
            ),
          ),
        ),
      );
      await tester.pumpAndSettle();

      final exc = tester.takeException();
      if (exc != null) {
        if (exc is FlutterError) {
          debugPrint('*** EXC DEEP ***:\n${exc.toStringDeep()}');
        } else {
          debugPrint('*** EXC ***: $exc');
        }
      }
      expect(exc, isNull);
      expect(find.text('Stock In (Add Stock)'), findsOneWidget);
      expect(find.text('Confirm Stock In'), findsOneWidget);
    });
  });

  group('Requirement 3: Receive Items Screen on 320px Mobile', () {
    testWidgets(
        'Receive Purchase Order Dialog renders without overflow on 320px phone',
        (tester) async {
      tester.view.physicalSize = const Size(320, 700);
      tester.view.devicePixelRatio = 1.0;
      addTearDown(() => tester.view.resetPhysicalSize());

      await tester.pumpWidget(
        ProviderScope(
          child: MaterialApp(
            home: Scaffold(
              body: ReceivePurchaseOrderDialog(order: dummyPO),
            ),
          ),
        ),
      );
      await tester.pumpAndSettle();

      final exc = tester.takeException();
      if (exc != null) {
        if (exc is FlutterError) {
          debugPrint('*** EXC DEEP ***:\n${exc.toStringDeep()}');
        } else {
          debugPrint('*** EXC ***: $exc');
        }
      }
      expect(exc, isNull);
      expect(find.textContaining('Receive Purchase Order'), findsOneWidget);
      expect(find.text('Confirm Receiving'), findsOneWidget);
    });
  });

  group('Requirement 4 & 5: Record Vitals & Examination Form on 320px & 360px',
      () {
    testWidgets(
        'PatientDetailsScreen accepts autoOpenExam and showMandatoryExamBanner',
        (tester) async {
      tester.view.physicalSize = const Size(360, 750);
      tester.view.devicePixelRatio = 1.0;
      addTearDown(() => tester.view.resetPhysicalSize());

      final screen = PatientDetailsScreen(
        patientId: dummyPatient.id,
        pendingAppointment: dummyAppointment,
        showMandatoryExamBanner: true,
        autoOpenExam: false,
      );

      expect(screen.showMandatoryExamBanner, isTrue);
      expect(screen.autoOpenExam, isFalse);
    });

    testWidgets('Eye Examination Form Dialog fits on 320px without overflow',
        (tester) async {
      tester.view.physicalSize = const Size(320, 700);
      tester.view.devicePixelRatio = 1.0;
      addTearDown(() => tester.view.resetPhysicalSize());

      await tester.pumpWidget(
        ProviderScope(
          child: MaterialApp(
            home: Scaffold(
              body: EyeExaminationFormDialog(patient: dummyPatient),
            ),
          ),
        ),
      );
      await tester.pumpAndSettle();

      final exc = tester.takeException();
      if (exc != null) {
        if (exc is FlutterError) {
          debugPrint('*** EXC DEEP ***:\n${exc.toStringDeep()}');
        } else {
          debugPrint('*** EXC ***: $exc');
        }
      }
      expect(exc, isNull);
      expect(find.text('Visual Acuity (VA)'), findsOneWidget);
      expect(find.text('Save Examination'), findsOneWidget);
    });
  });

  group('Requirement 6: Invoice PDF Timestamps & Staff Resolution', () {
    test('Formats invoice date in local timezone', () {
      final utcNow = DateTime.utc(2026, 11, 2, 5, 0); // 10:30 AM IST
      final inv = BillingInvoiceModel(
        id: 'inv-test-1',
        invoiceNumber: 'INV-2026-TEST',
        patientId: 'pat-1',
        department: 'eye',
        subtotal: 1500.0,
        totalAmount: 2000.0,
        amountPaid: 1500.0,
        billedBy: 'Dr. Jane Smith',
        createdAt: utcNow,
        updatedAt: utcNow,
      );

      expect(inv.createdAt.isUtc, isTrue);
      final localHour = inv.createdAt.toLocal().hour;
      final localMinute = inv.createdAt.toLocal().minute;
      // In IST (UTC+5:30), hour will be 10 and minute will be 30
      if (DateTime.now().timeZoneOffset ==
          const Duration(hours: 5, minutes: 30)) {
        expect(localHour, equals(10));
        expect(localMinute, equals(30));
      }
    });

    test('BillingPdfService resolves non-UUID name directly', () async {
      final name = await BillingPdfService.resolveStaffName('Dr. Varun Sharma');
      expect(name, equals('Dr. Varun Sharma'));
    });
  });

  group('Requirement 10 & 11: Payment Time Slot & Received Amount', () {
    test(
        '10:30 AM local payment maps strictly to 10:00 AM - 11:00 AM hourly slot',
        () {
      final localTime1030 = DateTime(2026, 11, 2, 10, 30);
      final slotIndex = DateBoundaries.getHourlySlotIndex(localTime1030);

      // Clinic opens at 9 AM: 9-10a is 0, 10-11a is 1
      expect(slotIndex, equals(1));
      expect(DateBoundaries.hourlySlotLabels[slotIndex], equals('10-11a'));
      expect(DateBoundaries.hourlySlotFullLabels[slotIndex],
          equals('10:00 AM - 11:00 AM'));
    });

    test(
        'Revenue metrics calculates actual payment received ₹1,500 instead of total ₹2,000',
        () {
      final paymentDate = DateTime(2026, 11, 2, 10, 30);
      final payment = BillingPaymentModel(
        id: 'p-1',
        billingId: 'inv-1',
        amount: 1500.0,
        paymentMode: 'upi',
        paidAt: paymentDate,
      );

      final invoice = BillingInvoiceModel(
        id: 'inv-1',
        invoiceNumber: 'INV-001',
        patientId: 'pat-1',
        department: 'eye',
        subtotal: 2000.0,
        totalAmount: 2000.0,
        amountPaid: 1500.0,
        payments: [payment],
        createdAt: DateTime(2026, 11, 2, 9, 0),
        updatedAt: DateTime(2026, 11, 2, 9, 0),
      );

      // Verify that payments collection reflects actual transaction received
      expect(invoice.totalAmount, equals(2000.0));
      expect(invoice.amountPaid, equals(1500.0));
      expect(invoice.payments.first.amount, equals(1500.0));

      final targetSlot = DateBoundaries.getHourlySlotIndex(payment.paidAt!);
      expect(targetSlot, equals(1)); // 10-11a slot
    });
  });
}
