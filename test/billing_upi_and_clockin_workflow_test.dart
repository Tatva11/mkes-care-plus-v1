import 'dart:io';
import 'package:flutter/material.dart';
import 'package:flutter/services.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';

import 'package:mkes_care/features/billing/models/billing_invoice_model.dart';
import 'package:mkes_care/features/billing/models/billing_payment_model.dart';
import 'package:mkes_care/features/billing/widgets/upi_qr_card.dart';
import 'package:mkes_care/features/billing/widgets/invoice_payment_section.dart';
import 'package:mkes_care/features/staff/widgets/clock_in_required_dialog.dart';
import 'package:mkes_care/features/staff/providers/attendance_provider.dart';
import 'package:mkes_care/features/staff_portal/screens/staff_dashboard_screen.dart';
import 'package:mkes_care/features/staff_portal/widgets/staff_shell.dart';
import 'package:mkes_care/features/auth/providers/auth_provider.dart';

void main() {
  TestWidgetsFlutterBinding.ensureInitialized();

  group('Requirement 1: Record Payment Conditional Visibility & Business Logic', () {
    test('Invoice remainingAmount calculation handles paid, partial, and unpaid correctly', () {
      final now = DateTime.now();
      final fullyPaid = BillingInvoiceModel(
        id: 'inv-1',
        invoiceNumber: 'INV-001',
        patientId: 'p-1',
        subtotal: 1000.0,
        totalAmount: 1000.0,
        amountPaid: 1000.0,
        paymentStatus: 'paid',
        department: 'eye',
        createdAt: now,
        updatedAt: now,
      );
      expect(fullyPaid.remainingAmount, 0.0);
      expect(fullyPaid.remainingAmount > 0.001, isFalse);

      final partiallyPaid = BillingInvoiceModel(
        id: 'inv-2',
        invoiceNumber: 'INV-002',
        patientId: 'p-1',
        subtotal: 1000.0,
        totalAmount: 1000.0,
        amountPaid: 500.0,
        paymentStatus: 'partially_paid',
        department: 'dental',
        createdAt: now,
        updatedAt: now,
      );
      expect(partiallyPaid.remainingAmount, 500.0);
      expect(partiallyPaid.remainingAmount > 0.001, isTrue);

      final unpaid = BillingInvoiceModel(
        id: 'inv-3',
        invoiceNumber: 'INV-003',
        patientId: 'p-1',
        subtotal: 1000.0,
        totalAmount: 1000.0,
        amountPaid: 0.0,
        paymentStatus: 'pending',
        department: 'eye',
        createdAt: now,
        updatedAt: now,
      );
      expect(unpaid.remainingAmount, 1000.0);
      expect(unpaid.remainingAmount > 0.001, isTrue);
    });

    testWidgets('Record Payment action button is hidden when invoice is fully paid and shown when due balance remains', (tester) async {
      final now = DateTime.now();
      final fullyPaid = BillingInvoiceModel(
        id: 'inv-1',
        invoiceNumber: 'INV-001',
        patientId: 'p-1',
        subtotal: 1000.0,
        totalAmount: 1000.0,
        amountPaid: 1000.0,
        paymentStatus: 'paid',
        department: 'eye',
        createdAt: now,
        updatedAt: now,
      );

      final partiallyPaid = BillingInvoiceModel(
        id: 'inv-2',
        invoiceNumber: 'INV-002',
        patientId: 'p-1',
        subtotal: 1000.0,
        totalAmount: 1000.0,
        amountPaid: 500.0,
        paymentStatus: 'partially_paid',
        department: 'dental',
        createdAt: now,
        updatedAt: now,
      );

      await tester.pumpWidget(
        MaterialApp(
          home: Scaffold(
            body: Row(
              children: [
                if (fullyPaid.remainingAmount > 0.001 && !fullyPaid.isCancelled)
                  IconButton(
                    key: Key('record_payment_${fullyPaid.invoiceNumber}'),
                    icon: const Icon(Icons.payments_outlined),
                    onPressed: () {},
                  ),
                if (partiallyPaid.remainingAmount > 0.001 && !partiallyPaid.isCancelled)
                  IconButton(
                    key: Key('record_payment_${partiallyPaid.invoiceNumber}'),
                    icon: const Icon(Icons.payments_outlined),
                    onPressed: () {},
                  ),
              ],
            ),
          ),
        ),
      );

      // Fully paid button must NOT be present
      expect(find.byKey(Key('record_payment_${fullyPaid.invoiceNumber}')), findsNothing);
      // Partially paid button MUST be present
      expect(find.byKey(Key('record_payment_${partiallyPaid.invoiceNumber}')), findsOneWidget);
    });
  });

  group('Requirement 2: UPI QR Code Integration & Clipboard Copy', () {
    testWidgets('UpiPaymentQrCard renders QR image, exact UPI ID, instruction text, and copy button', (tester) async {
      await tester.pumpWidget(
        const MaterialApp(
          home: Scaffold(
            body: UpiPaymentQrCard(
              upiId: '9004706625@fam',
            ),
          ),
        ),
      );

      expect(find.byKey(const Key('upi_qr_image')), findsOneWidget);
      expect(find.byKey(const Key('clinic_upi_id_text')), findsOneWidget);
      expect(find.text('9004706625@fam'), findsOneWidget);
      expect(find.byKey(const Key('copy_upi_id_button')), findsOneWidget);
      expect(
        find.text('Scan this QR code using any UPI application to complete your payment.'),
        findsOneWidget,
      );
    });

    testWidgets('Copy UPI ID button sets clipboard data and shows SnackBar', (tester) async {
      String? copiedData;
      tester.binding.defaultBinaryMessenger.setMockMethodCallHandler(
        SystemChannels.platform,
        (MethodCall methodCall) async {
          if (methodCall.method == 'Clipboard.setData') {
            copiedData = (methodCall.arguments as Map)['text'] as String?;
            return null;
          }
          return null;
        },
      );

      await tester.pumpWidget(
        const MaterialApp(
          home: Scaffold(
            body: UpiPaymentQrCard(upiId: '9004706625@fam'),
          ),
        ),
      );

      await tester.tap(find.byKey(const Key('copy_upi_id_button')));
      await tester.pump();

      expect(copiedData, equals('9004706625@fam'));
      expect(find.text('UPI ID copied to clipboard'), findsOneWidget);
    });

    testWidgets('InvoicePaymentSection displays UpiPaymentQrCard only when UPI mode is active', (tester) async {
      await tester.pumpWidget(
        MaterialApp(
          home: Scaffold(
            body: SingleChildScrollView(
              child: InvoicePaymentSection(
                subtotal: 1000.0,
                discount: 0.0,
                finalTotal: 1000.0,
                onDiscountChanged: (_) {},
                payment: null,
                onPaymentChanged: (_) {},
              ),
            ),
          ),
        ),
      );
      await tester.pumpAndSettle();

      // Default mode is cash; QR card should NOT be shown
      expect(find.byType(UpiPaymentQrCard), findsNothing);

      // Select UPI mode
      await tester.tap(find.text('UPI'));
      await tester.pumpAndSettle();

      // UpiPaymentQrCard must now appear
      expect(find.byType(UpiPaymentQrCard), findsOneWidget);
      expect(find.text('9004706625@fam'), findsOneWidget);
    });
  });

  group('Requirement 3: Fully Paid Checkbox in Payment Form', () {
    testWidgets('InvoicePaymentSection Fully Paid checkbox auto-populates amount and marks status PAID', (tester) async {
      await tester.pumpWidget(
        MaterialApp(
          home: Scaffold(
            body: SingleChildScrollView(
              child: InvoicePaymentSection(
                subtotal: 1200.0,
                discount: 200.0,
                finalTotal: 1000.0,
                onDiscountChanged: (_) {},
                payment: null,
                onPaymentChanged: (_) {},
              ),
            ),
          ),
        ),
      );
      await tester.pumpAndSettle();

      // Initial state: Fully Paid is checked by default for fresh invoice
      expect(find.byKey(const Key('invoice_fully_paid_checkbox')), findsOneWidget);
      expect(find.text('PAID'), findsOneWidget);
      expect(find.text('₹0.00'), findsOneWidget);

      // Uncheck Fully Paid
      await tester.tap(find.byKey(const Key('invoice_fully_paid_checkbox')));
      await tester.pumpAndSettle();

      // Enter partial payment 400
      final amountField = find.byKey(const Key('invoice_amount_paid_field'));
      await tester.enterText(amountField, '400');
      await tester.pumpAndSettle();

      expect(find.text('PARTIALLY PAID'), findsOneWidget);
      expect(find.text('₹600.00'), findsOneWidget);

      // Enter 0 payment
      await tester.enterText(amountField, '0');
      await tester.pumpAndSettle();

      expect(find.text('UNPAID'), findsOneWidget);
      // Both Total and Remaining show ₹1000.00
      expect(find.text('₹1000.00'), findsNWidgets(2));

      // Check Fully Paid again: auto-fills 1000, 0 remaining, status PAID
      await tester.tap(find.byKey(const Key('invoice_fully_paid_checkbox')));
      await tester.pumpAndSettle();

      expect(find.text('PAID'), findsOneWidget);
      expect(find.text('₹0.00'), findsOneWidget);
      expect(find.text('1000'), findsOneWidget);
    });
  });

  group('Requirement 4: Mandatory Staff Clock-In Enforcement', () {
    testWidgets('ClockInRequiredDialog renders message and Clock In Now redirects to attendance tab', (tester) async {
      final container = ProviderContainer(
        overrides: [
          staffClockInStatusProvider.overrideWith((ref) => false),
        ],
      );

      await tester.pumpWidget(
        UncontrolledProviderScope(
          container: container,
          child: MaterialApp(
            home: Scaffold(
              body: Consumer(
                builder: (context, ref, _) => ElevatedButton(
                  onPressed: () {
                    showClockInRequiredDialog(context, ref);
                  },
                  child: const Text('Trigger Operation'),
                ),
              ),
            ),
          ),
        ),
      );

      // Trigger dialog
      await tester.tap(find.text('Trigger Operation'));
      await tester.pumpAndSettle();

      expect(find.text('Clock-In Required'), findsOneWidget);
      expect(
        find.text('You must clock in before performing any clinic operations. Please clock in to continue.'),
        findsOneWidget,
      );
      expect(find.byKey(const Key('clock_in_now_button')), findsOneWidget);

      // Click Clock In Now
      await tester.tap(find.byKey(const Key('clock_in_now_button')));
      await tester.pumpAndSettle();

      // Dialog is dismissed and staffNavProvider is updated to attendance
      expect(find.text('Clock-In Required'), findsNothing);
      expect(container.read(staffNavProvider), equals(StaffNavItem.attendance));
    });

    testWidgets('ClockInRequiredBanner renders when staff is unclocked and hides when clocked in', (tester) async {
      final unclockedContainer = ProviderContainer(
        overrides: [
          staffClockInStatusProvider.overrideWith((ref) => false),
        ],
      );

      await tester.pumpWidget(
        UncontrolledProviderScope(
          container: unclockedContainer,
          child: const MaterialApp(
            home: Scaffold(
              body: ClockInRequiredBanner(),
            ),
          ),
        ),
      );
      await tester.pumpAndSettle();

      expect(find.byKey(const Key('clock_in_required_banner')), findsOneWidget);
      expect(find.byKey(const Key('banner_clock_in_now_button')), findsOneWidget);

      // Now with clocked in provider
      final clockedInContainer = ProviderContainer(
        overrides: [
          staffClockInStatusProvider.overrideWith((ref) => true),
        ],
      );

      await tester.pumpWidget(
        UncontrolledProviderScope(
          container: clockedInContainer,
          child: const MaterialApp(
            home: Scaffold(
              body: ClockInRequiredBanner(),
            ),
          ),
        ),
      );
      await tester.pumpAndSettle();

      expect(find.byKey(const Key('clock_in_required_banner')), findsNothing);
    });

    testWidgets('Admin users are exempt and never blocked by clock-in check', (tester) async {
      final container = ProviderContainer(
        overrides: [
          currentUserRoleProvider.overrideWith((ref) => 'admin'),
        ],
      );

      final isAllowed = await container.read(staffClockInStatusProvider.future);
      expect(isAllowed, isTrue);
    });
  });

  group('Requirement 5: Lifecycle Regression Tests (Error 1 & Error 2)', () {
    testWidgets('Parent widget setState inside onPaymentChanged does not throw markNeedsBuild/setState during build when finalTotal updates', (tester) async {
      double total = 1000.0;
      BillingPaymentModel? receivedPayment;

      await tester.pumpWidget(
        MaterialApp(
          home: Scaffold(
            body: StatefulBuilder(
              builder: (context, setState) {
                return Column(
                  children: [
                    ElevatedButton(
                      key: const Key('change_total_btn'),
                      onPressed: () {
                        setState(() {
                          total = 1500.0;
                        });
                      },
                      child: const Text('Update Total'),
                    ),
                    Expanded(
                      child: SingleChildScrollView(
                        child: InvoicePaymentSection(
                          subtotal: total,
                          discount: 0.0,
                          finalTotal: total,
                          onDiscountChanged: (_) {},
                          payment: receivedPayment,
                          onPaymentChanged: (p) {
                            setState(() {
                              receivedPayment = p;
                            });
                          },
                        ),
                      ),
                    ),
                  ],
                );
              },
            ),
          ),
        ),
      );
      await tester.pumpAndSettle();

      expect(receivedPayment, isNotNull);
      expect(receivedPayment!.amount, 1000.0);

      // Trigger didUpdateWidget by updating total
      await tester.tap(find.byKey(const Key('change_total_btn')));
      // Crucial: pump frame should NOT throw "setState() or markNeedsBuild() called during build"
      await tester.pump();
      await tester.pumpAndSettle();

      expect(receivedPayment!.amount, 1500.0);
      expect(tester.takeException(), isNull);
    });

    testWidgets('Deactivating / popping widget tree does not trigger _dependents.isEmpty assertion', (tester) async {
      bool isVisible = true;

      await tester.pumpWidget(
        MaterialApp(
          home: Scaffold(
            body: StatefulBuilder(
              builder: (context, setState) {
                return Column(
                  children: [
                    ElevatedButton(
                      key: const Key('toggle_visibility_btn'),
                      onPressed: () {
                        setState(() {
                          isVisible = !isVisible;
                        });
                      },
                      child: const Text('Toggle'),
                    ),
                    if (isVisible)
                      Expanded(
                        child: SingleChildScrollView(
                          child: InvoicePaymentSection(
                            subtotal: 500.0,
                            discount: 0.0,
                            finalTotal: 500.0,
                            onDiscountChanged: (_) {},
                            payment: null,
                            onPaymentChanged: (_) {},
                          ),
                        ),
                      ),
                  ],
                );
              },
            ),
          ),
        ),
      );
      await tester.pump();

      // Immediately unmount before multiple post-frame callbacks complete
      await tester.tap(find.byKey(const Key('toggle_visibility_btn')));
      await tester.pump();
      await tester.pumpAndSettle();

      expect(tester.takeException(), isNull);
      expect(find.byType(InvoicePaymentSection), findsNothing);
    });
  });

  group('Requirement 6: Application Branding & Assets Integrity Tests', () {
    test('Web manifest and index.html have official MKES CARE+ branding and no default Flutter text', () {
      final manifestFile = File('web/manifest.json');
      expect(manifestFile.existsSync(), isTrue);
      final manifestContent = manifestFile.readAsStringSync();
      expect(manifestContent.contains('"name": "MKES CARE+"'), isTrue);
      expect(manifestContent.contains('"short_name": "MKES CARE+"'), isTrue);
      expect(manifestContent.contains('A new Flutter project'), isFalse);

      final indexFile = File('web/index.html');
      expect(indexFile.existsSync(), isTrue);
      final indexContent = indexFile.readAsStringSync();
      expect(indexContent.contains('<title>MKES CARE+</title>'), isTrue);
      expect(indexContent.contains('apple-mobile-web-app-title" content="MKES CARE+"'), isTrue);
      expect(indexContent.contains('A new Flutter project'), isFalse);
    });

    test('Android Manifest specifies MKES CARE+ label, ic_launcher, and ic_launcher_round', () {
      final manifestFile = File('android/app/src/main/AndroidManifest.xml');
      expect(manifestFile.existsSync(), isTrue);
      final content = manifestFile.readAsStringSync();
      expect(content.contains('android:label="MKES CARE+"'), isTrue);
      expect(content.contains('android:icon="@mipmap/ic_launcher"'), isTrue);
      expect(content.contains('android:roundIcon="@mipmap/ic_launcher_round"'), isTrue);
    });

    test('All Android launcher mipmap densities and splash screen assets exist', () {
      final densities = ['mdpi', 'hdpi', 'xhdpi', 'xxhdpi', 'xxxhdpi'];
      for (final d in densities) {
        expect(File('android/app/src/main/res/mipmap-$d/ic_launcher.png').existsSync(), isTrue);
        expect(File('android/app/src/main/res/mipmap-$d/ic_launcher_foreground.png').existsSync(), isTrue);
        expect(File('android/app/src/main/res/mipmap-$d/ic_launcher_round.png').existsSync(), isTrue);
      }
      expect(File('android/app/src/main/res/drawable/splash_logo.png').existsSync(), isTrue);
      expect(File('android/app/src/main/res/mipmap-anydpi-v26/ic_launcher.xml').existsSync(), isTrue);
      expect(File('android/app/src/main/res/mipmap-anydpi-v26/ic_launcher_round.xml').existsSync(), isTrue);
    });

    test('UPI QR code assets and pubspec registration exist', () {
      expect(File('assets/images/qr.jpeg').existsSync(), isTrue);
      expect(File('assets/images/qr.png').existsSync(), isTrue);

      final pubspec = File('pubspec.yaml').readAsStringSync();
      expect(pubspec.contains('assets/images/qr.jpeg'), isTrue);
    });
  });
}
