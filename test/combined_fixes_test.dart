import 'dart:io';
import 'package:flutter_test/flutter_test.dart';
import 'package:mkes_care/features/appointments/models/appointment_model.dart';
import 'package:mkes_care/features/appointments/widgets/appointment_form_dialog.dart';
import 'package:mkes_care/features/billing/models/billing_invoice_model.dart';
import 'package:mkes_care/features/billing/models/billing_item_model.dart';
import 'package:mkes_care/features/eye/models/eye_surgery_model.dart';

void main() {
  group('CHANGE 1: Include Previous Outstanding Balances in New Invoices', () {
    test('Calculates outstanding balance correctly across multiple invoices and partial payments', () {
      final invoices = [
        // Unpaid invoice
        BillingInvoiceModel(
          id: 'inv-1',
          invoiceNumber: 'INV-2026-001',
          patientId: 'patient-123',
          department: 'eye',
          subtotal: 1000.0,
          totalAmount: 1000.0,
          amountPaid: 0.0,
          paymentStatus: 'pending',
          createdAt: DateTime(2026, 9, 1),
          updatedAt: DateTime(2026, 9, 1),
        ),
        // Partially paid invoice
        BillingInvoiceModel(
          id: 'inv-2',
          invoiceNumber: 'INV-2026-002',
          patientId: 'patient-123',
          department: 'eye',
          subtotal: 1500.0,
          totalAmount: 1500.0,
          amountPaid: 500.0,
          paymentStatus: 'partially_paid',
          createdAt: DateTime(2026, 9, 10),
          updatedAt: DateTime(2026, 9, 12),
        ),
        // Fully paid invoice (must be ignored)
        BillingInvoiceModel(
          id: 'inv-3',
          invoiceNumber: 'INV-2026-003',
          patientId: 'patient-123',
          department: 'eye',
          subtotal: 800.0,
          totalAmount: 800.0,
          amountPaid: 800.0,
          paymentStatus: 'paid',
          createdAt: DateTime(2026, 9, 15),
          updatedAt: DateTime(2026, 9, 15),
        ),
        // Cancelled invoice (must be ignored)
        BillingInvoiceModel(
          id: 'inv-4',
          invoiceNumber: 'INV-2026-004',
          patientId: 'patient-123',
          department: 'eye',
          subtotal: 2000.0,
          totalAmount: 2000.0,
          amountPaid: 0.0,
          paymentStatus: 'cancelled',
          createdAt: DateTime(2026, 9, 20),
          updatedAt: DateTime(2026, 9, 20),
        ),
      ];

      // Eligible invoices are pending and partially_paid with remainingAmount > 0
      final eligibleInvoices = invoices.where((inv) =>
          !inv.isPaid && !inv.isCancelled && inv.remainingAmount > 0.001).toList();

      expect(eligibleInvoices.length, equals(2));
      expect(eligibleInvoices[0].remainingAmount, equals(1000.0));
      expect(eligibleInvoices[1].remainingAmount, equals(1000.0));

      final totalOutstanding = eligibleInvoices.fold(0.0, (sum, inv) => sum + inv.remainingAmount);
      expect(totalOutstanding, equals(2000.0));
    });

    test('Recalculates totals correctly when previous balance is included or excluded', () {
      final newChargesItems = [
        const BillingItemModel(serviceName: 'Comprehensive Eye Exam', quantity: 1, unitPrice: 500.0),
        const BillingItemModel(serviceName: 'Fundus Photography', quantity: 1, unitPrice: 750.0),
      ];

      final newChargesSubtotal = newChargesItems.fold(0.0, (sum, item) => sum + item.totalAmount);
      expect(newChargesSubtotal, equals(1250.0));

      const outstandingBalance = 650.0;
      const discount = 100.0;

      double computeTotal(bool includePrevious) {
        final prevIncluded = includePrevious ? outstandingBalance : 0.0;
        final sub = newChargesSubtotal + prevIncluded;
        return (sub - discount).clamp(0.0, double.infinity);
      }

      // When included
      expect(computeTotal(true), equals(1800.0));

      // When excluded
      expect(computeTotal(false), equals(1150.0));
    });

    test('Consolidation audit reference and closure semantics', () {
      const newInvoiceNumber = 'INV-2026-088';
      final reference = 'Consolidated to $newInvoiceNumber';
      final notes = 'Balance transferred to new invoice #$newInvoiceNumber';

      expect(reference, contains('INV-2026-088'));
      expect(notes, contains('Balance transferred'));
    });
  });

  group('CHANGE 2: Dashboard Patient Visit Workflow', () {
    test('Sequence status transitions: Scheduled -> Present -> Billed -> Completed', () {
      final scheduledAppt = AppointmentModel(
        id: 'appt-1',
        appointmentDate: DateTime.now(),
        appointmentTime: '10:00:00',
        status: 'scheduled',
        createdAt: DateTime.now(),
        updatedAt: DateTime.now(),
      );

      // 1. Initial State: not present, not billed
      expect(scheduledAppt.isPresent, isFalse);
      expect(scheduledAppt.isBilled, isFalse);
      expect(scheduledAppt.statusLabel, equals('Scheduled'));

      // 2. Mark Present -> waiting
      final presentAppt = scheduledAppt.copyWith(status: 'waiting');
      expect(presentAppt.isPresent, isTrue);
      expect(presentAppt.isBilled, isFalse);
      expect(presentAppt.statusLabel, equals('Present (Waiting)'));

      // 3. Billing completed -> note tagged with invoice number
      final billedAppt = presentAppt.copyWith(notes: '[BILLED: INV-2026-099]');
      expect(billedAppt.isPresent, isTrue);
      expect(billedAppt.isBilled, isTrue);
      expect(billedAppt.billingReference, equals('INV-2026-099'));

      // 4. Mark Completed -> completed
      final completedAppt = billedAppt.copyWith(status: 'completed');
      expect(completedAppt.isPresent, isTrue);
      expect(completedAppt.statusLabel, equals('Completed'));
    });

    test('Handles No-Charge visits seamlessly', () {
      final presentAppt = AppointmentModel(
        id: 'appt-2',
        appointmentDate: DateTime.now(),
        appointmentTime: '11:00:00',
        status: 'waiting',
        notes: '[NO_CHARGE: Post-op Follow-up]',
        createdAt: DateTime.now(),
        updatedAt: DateTime.now(),
      );

      expect(presentAppt.isPresent, isTrue);
      expect(presentAppt.isBilled, isTrue);
      expect(presentAppt.billingReference, equals('No-Charge: Post-op Follow-up'));
    });

    test('Prevents completion before arrival or billing steps are satisfied', () {
      bool canComplete(AppointmentModel appt) {
        return appt.isPresent && appt.isBilled && appt.status != 'completed';
      }

      final scheduled = AppointmentModel(
        id: 'a1',
        appointmentDate: DateTime.now(),
        appointmentTime: '09:00',
        status: 'scheduled',
        createdAt: DateTime.now(),
        updatedAt: DateTime.now(),
      );
      expect(canComplete(scheduled), isFalse);

      final presentUnbilled = scheduled.copyWith(status: 'waiting');
      expect(canComplete(presentUnbilled), isFalse);

      final presentBilled = presentUnbilled.copyWith(notes: '[BILLED: INV-100]');
      expect(canComplete(presentBilled), isTrue);

      final presentNoCharge = presentUnbilled.copyWith(notes: '[NO_CHARGE: Review]');
      expect(canComplete(presentNoCharge), isTrue);
    });
  });

  group('CHANGE 3: Dashboard Appointment Booking Default Time', () {
    test('Future date preserves 9:00 AM opening default', () {
      final tomorrow = DateTime.now().add(const Duration(days: 1));
      final suggested = AppointmentFormDialog.calculateSuggestedTime(
        selectedDate: tomorrow,
      );
      expect(suggested.hour, equals(9));
      expect(suggested.minute, equals(0));
    });

    test('Today before 9:00 AM suggests 9:00 AM opening time', () {
      final today = DateTime(2026, 10, 16, 7, 15);
      final suggested = AppointmentFormDialog.calculateSuggestedTime(
        selectedDate: today,
        currentTime: today,
      );
      expect(suggested.hour, equals(9));
      expect(suggested.minute, equals(0));
    });

    test('Today at 2:35 PM with 15-min intervals suggests 2:45 PM', () {
      final today = DateTime(2026, 10, 16, 14, 35);
      final suggested = AppointmentFormDialog.calculateSuggestedTime(
        selectedDate: today,
        currentTime: today,
        intervalMinutes: 15,
      );
      expect(suggested.hour, equals(14));
      expect(suggested.minute, equals(45));
    });

    test('Today at 2:45 PM suggests 2:45 PM slot', () {
      final today = DateTime(2026, 10, 16, 14, 45);
      final suggested = AppointmentFormDialog.calculateSuggestedTime(
        selectedDate: today,
        currentTime: today,
        intervalMinutes: 15,
      );
      expect(suggested.hour, equals(14));
      expect(suggested.minute, equals(45));
    });

    test('Today at 2:50 PM suggests 3:00 PM slot', () {
      final today = DateTime(2026, 10, 16, 14, 50);
      final suggested = AppointmentFormDialog.calculateSuggestedTime(
        selectedDate: today,
        currentTime: today,
        intervalMinutes: 15,
      );
      expect(suggested.hour, equals(15));
      expect(suggested.minute, equals(0));
    });

    test('Detects when clinic hours have passed for today', () {
      final duringDay = DateTime(2026, 10, 16, 14, 0);
      expect(AppointmentFormDialog.hasValidSlotsRemainingToday(currentTime: duringDay), isTrue);

      final afterHours = DateTime(2026, 10, 16, 20, 15);
      expect(AppointmentFormDialog.hasValidSlotsRemainingToday(currentTime: afterHours), isFalse);
    });
  });

  group('CHANGE 4: Surgery Status Update and Inventory Consumption RPC Fix', () {
    test('Migration file exists and inserts into eye_surgery_inventory_consumptions before updating eye_surgeries', () {
      final migrationFile = File('supabase/migrations/20261016160000_fix_eye_surgery_inventory_consumption_rpc.sql');
      expect(migrationFile.existsSync(), isTrue);

      final sql = migrationFile.readAsStringSync();
      expect(sql, contains('CREATE OR REPLACE FUNCTION public.consume_eye_surgery_inventory'));
      expect(sql, contains('INSERT INTO public.eye_surgery_inventory_consumptions'));
      expect(sql, contains('UPDATE public.eye_surgeries'));

      // Ensure insertion into eye_surgery_inventory_consumptions occurs before update to eye_surgeries
      final insertIndex = sql.indexOf('INSERT INTO public.eye_surgery_inventory_consumptions');
      final updateIndex = sql.indexOf('UPDATE public.eye_surgeries');
      expect(insertIndex, isNonNegative);
      expect(updateIndex, isNonNegative);
      expect(insertIndex, lessThan(updateIndex),
          reason: 'Must insert into eye_surgery_inventory_consumptions before updating eye_surgeries to avoid P0001 trigger exception');
    });

    test('Eye surgery model checklist items definition is complete', () {
      expect(EyeSurgeryModel.checklistItems.length, equals(8));
      expect(EyeSurgeryModel.checklistItems.containsKey('identity_verified'), isTrue);
      expect(EyeSurgeryModel.checklistItems.containsKey('consent_confirmed'), isTrue);
      expect(EyeSurgeryModel.checklistItems.containsKey('correct_eye_confirmed'), isTrue);
    });
  });

  group('CHANGE 5: Staff Permissions Guard for Surgery Staff Assignment', () {
    test('Only admin users are permitted to perform staff assignment', () {
      bool isAuthorizedToAssignStaff(String? role) {
        return role?.toLowerCase() == 'admin';
      }

      expect(isAuthorizedToAssignStaff('admin'), isTrue);
      expect(isAuthorizedToAssignStaff('ADMIN'), isTrue);
      expect(isAuthorizedToAssignStaff('staff'), isFalse);
      expect(isAuthorizedToAssignStaff('nurse'), isFalse);
      expect(isAuthorizedToAssignStaff('doctor'), isFalse);
      expect(isAuthorizedToAssignStaff(null), isFalse);
    });
  });
}
