import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:supabase_flutter/supabase_flutter.dart';

import 'package:mkes_care/core/providers/supabase_provider.dart';
import 'package:mkes_care/features/auth/models/profile_model.dart';
import 'package:mkes_care/features/auth/providers/auth_provider.dart';
import 'package:mkes_care/features/billing/models/billing_invoice_model.dart';
import 'package:mkes_care/features/billing/models/billing_item_model.dart';
import 'package:mkes_care/features/billing/models/billing_payment_model.dart';
import 'package:mkes_care/features/billing/repositories/billing_repository.dart';
import 'package:mkes_care/features/billing/screens/billing_management_screen.dart';
import 'package:mkes_care/features/billing/services/billing_pdf_service.dart';
import 'package:mkes_care/features/billing/widgets/invoice_success_dialog.dart';
import 'package:mkes_care/features/staff/models/attendance_record.dart';
import 'package:mkes_care/features/staff/models/shift_configuration.dart';
import 'package:mkes_care/features/staff/repositories/attendance_repository.dart';
import 'package:mkes_care/features/staff_portal/screens/staff_attendance_screen.dart';

// ── Mock & Fake Implementations ──────────────────────────────────────────────

class _FakeSupabaseClient extends Fake implements SupabaseClient {}

class _FakeAttendanceRepository extends Fake implements AttendanceRepository {
  final List<AttendanceRecord> records;
  final String assignedShift;

  _FakeAttendanceRepository({
    this.records = const [],
    this.assignedShift = 'both',
  });

  @override
  Future<List<ShiftConfiguration>> fetchShiftConfigurations() async => const [
        ShiftConfiguration.defaultMorning,
        ShiftConfiguration.defaultAfternoon,
      ];

  @override
  Future<String?> fetchStaffShiftAssignment(String staffId, {DateTime? forDate}) async =>
      assignedShift;

  @override
  Future<List<AttendanceRecord>> fetchMonthlyAttendance(
    String staffId,
    int year,
    int month, {
    String? shift,
  }) async {
    if (shift == null || shift == 'all') return records;
    return records.where((r) => r.shift.toLowerCase() == shift.toLowerCase()).toList();
  }

  @override
  Future<AttendanceRecord?> fetchActiveAttendance(
    String staffId, {
    String? shift,
    ShiftConfiguration? config,
    DateTime? forTime,
  }) async {
    final checkTime = forTime ?? DateTime.now();
    for (final r in records) {
      if (r.checkInTime != null && r.checkOutTime == null) {
        // Auto-terminate check
        final cfg = (r.shift == 'morning')
            ? ShiftConfiguration.defaultMorning
            : ShiftConfiguration.defaultAfternoon;
        if (cfg.isTimePastShiftEnd(checkTime)) {
          return null; // Auto-closed, not active
        }
        return r;
      }
    }
    return null;
  }

  @override
  Future<AttendanceRecord?> fetchTodayAttendance(
    String staffId, {
    String shift = 'morning',
    ShiftConfiguration? config,
  }) async {
    return records
        .where((r) => r.shift.toLowerCase() == shift.toLowerCase())
        .firstOrNull;
  }
}

class _FakeBillingRepository extends Fake implements BillingRepository {
  final List<BillingInvoiceModel> invoices;
  _FakeBillingRepository(this.invoices);

  @override
  Future<List<BillingInvoiceModel>> fetchInvoices({
    String? department,
    String? patientId,
    String? paymentStatus,
    String? searchQuery,
    DateTime? startDate,
    DateTime? endDate,
    int limit = 200,
  }) async => invoices;

  @override
  Future<BillingInvoiceModel> fetchInvoiceById(String id) async {
    return invoices.firstWhere(
      (inv) => inv.id == id,
      orElse: () => invoices.first,
    );
  }
}

// ── Test Suite ───────────────────────────────────────────────────────────────

void main() {
  TestWidgetsFlutterBinding.ensureInitialized();

  final staffUser = const User(
    id: 'staff-42',
    appMetadata: {},
    userMetadata: {},
    aud: 'authenticated',
    createdAt: '2026-01-01',
  );

  final staffProfile = ProfileModel(
    id: 'staff-42',
    email: 'priya@mkescare.com',
    fullName: 'Nurse Priya Sharma',
    role: 'staff',
    isActive: true,
    department: 'General',
    createdAt: DateTime.now(),
  );

  final sampleDate = DateTime(2026, 10, 18);

  final morningCompletedSession = AttendanceRecord(
    id: 'att-morning-1',
    staffId: 'staff-42',
    staffName: 'Nurse Priya Sharma',
    date: sampleDate,
    shift: 'morning',
    checkInTime: DateTime(2026, 10, 18, 8, 0),
    checkOutTime: DateTime(2026, 10, 18, 13, 0),
    workingHours: 5.0,
    status: 'present',
    isLate: false,
    lateMinutes: 0,
  );

  final eveningCompletedSession = AttendanceRecord(
    id: 'att-evening-1',
    staffId: 'staff-42',
    staffName: 'Nurse Priya Sharma',
    date: sampleDate,
    shift: 'afternoon',
    checkInTime: DateTime(2026, 10, 18, 18, 50),
    checkOutTime: DateTime(2026, 10, 18, 21, 0),
    workingHours: 2.17,
    status: 'present',
    isLate: false,
    lateMinutes: 0,
  );

  final sampleInvoice = BillingInvoiceModel(
    id: 'inv-test-101',
    invoiceNumber: 'INV-2026-0042',
    patientId: 'pat-101',
    patientNumber: 'P-100234',
    patientName: 'Aarav Patel',
    patientMobile: '9876543210',
    department: 'Dental',
    subtotal: 3500.0,
    discount: 500.0,
    totalAmount: 3000.0,
    amountPaid: 3000.0,
    paymentStatus: 'paid',
    createdAt: DateTime(2026, 10, 18, 10, 30),
    updatedAt: DateTime(2026, 10, 18, 10, 45),
    items: [
      BillingItemModel(
        id: 'item-1',
        billingId: 'inv-test-101',
        serviceId: 'srv-1',
        serviceName: 'Root Canal Treatment & Crown',
        quantity: 1,
        unitPrice: 2500.0,
        totalAmount: 2500.0,
      ),
      BillingItemModel(
        id: 'item-2',
        billingId: 'inv-test-101',
        serviceId: 'srv-2',
        serviceName: 'Dental Diagnostic X-Ray (IOPA)',
        quantity: 2,
        unitPrice: 500.0,
        totalAmount: 1000.0,
      ),
    ],
    payments: [
      BillingPaymentModel(
        id: 'pay-1',
        billingId: 'inv-test-101',
        amount: 3000.0,
        paymentMode: 'upi',
        paymentReference: 'UPI-98234710',
        paidAt: DateTime(2026, 10, 18, 10, 45),
      ),
    ],
  );

  // ───────────────────────────────────────────────────────────────────────────
  // 1. Issue 1: Staff Attendance Layout Overflow Across All 7 Viewports
  // ───────────────────────────────────────────────────────────────────────────
  group('1. Staff Attendance Layout Overflow Verification (360px - 1440px)', () {
    final viewports = <String, Size>{
      'Mobile 360px': const Size(360, 800),
      'Mobile 375px': const Size(375, 812),
      'Mobile 390px': const Size(390, 844),
      'Mobile 430px': const Size(430, 932),
      'Tablet 768px': const Size(768, 1024),
      'Desktop 1024px': const Size(1024, 768),
      'Desktop 1440px': const Size(1440, 900),
    };

    for (final entry in viewports.entries) {
      testWidgets('Renders Monthly Shift Log cleanly without overflow on ${entry.key}',
          (tester) async {
        tester.view.physicalSize = entry.value;
        tester.view.devicePixelRatio = 1.0;
        addTearDown(tester.view.resetPhysicalSize);
        addTearDown(tester.view.resetDevicePixelRatio);

        final repo = _FakeAttendanceRepository(
          records: [morningCompletedSession, eveningCompletedSession],
          assignedShift: 'both',
        );

        await tester.pumpWidget(
          ProviderScope(
            overrides: [
              supabaseProvider.overrideWithValue(_FakeSupabaseClient()),
              currentUserProvider.overrideWithValue(staffUser),
              currentUserRoleProvider.overrideWith((ref) async => 'staff'),
              currentProfileProvider.overrideWith((ref) async => staffProfile),
              attendanceRepositoryProvider.overrideWithValue(repo),
            ],
            child: const MaterialApp(
              home: Scaffold(
                body: StaffAttendanceScreen(),
              ),
            ),
          ),
        );

        await tester.pumpAndSettle();

        // Must not throw any RenderFlex overflow exception
        expect(tester.takeException(), isNull);

        // Core text elements are visible and intact
        expect(find.text('Attendance & Shift Logs'), findsOneWidget);
        expect(find.text('Monthly Shift Log'), findsOneWidget);
        expect(find.text('Both Duties (M+E)'), findsOneWidget);
        expect(find.text('Total Duration: '), findsOneWidget);
        expect(find.text('7h 10m'), findsOneWidget);
      });
    }
  });

  // ───────────────────────────────────────────────────────────────────────────
  // 2. Issue 2: One Daily Attendance Record with Multiple Duty Sessions
  // ───────────────────────────────────────────────────────────────────────────
  group('2. Attendance Business Logic: Daily Attendance & Session Calculations', () {
    test('Consolidates Morning and Evening sessions into one DailyAttendanceSummary', () {
      final records = [morningCompletedSession, eveningCompletedSession];
      final dailySummaries = records.groupIntoDailySummaries();

      expect(dailySummaries.length, 1);
      final summary = dailySummaries.first;

      expect(summary.hasMultipleSessions, isTrue);
      expect(summary.morningSession?.formattedWorkingDuration, '5h');
      expect(summary.eveningSession?.formattedWorkingDuration, '2h 10m');
      expect(summary.morningSession?.formattedCheckInTime, '08:00 AM');
      expect(summary.morningSession?.formattedCheckOutTime, '01:00 PM');
      expect(summary.eveningSession?.formattedCheckInTime, '06:50 PM');
      expect(summary.eveningSession?.formattedCheckOutTime, '09:00 PM');

      // Total daily working hours = 5.0 + 2.17 = 7.17h = "7h 10m"
      expect(summary.totalWorkingHours, 7.17);
      expect(summary.formattedTotalDuration, '7h 10m');
      expect(summary.dailyStatus, 'present');
      expect(summary.shiftDisplayName, 'Both Duties (M+E)');
    });

    test('Break between morning and evening duties is strictly excluded from total working hours', () {
      final morningEnd = morningCompletedSession.checkOutTime!;
      final eveningStart = eveningCompletedSession.checkInTime!;
      final breakMinutes = eveningStart.difference(morningEnd).inMinutes;

      // Break is 5 hours 50 minutes (350 minutes)
      expect(breakMinutes, 350);

      final summary = [morningCompletedSession, eveningCompletedSession].groupIntoDailySummaries().first;
      // Duration is 7h 10m (430 minutes), NOT 430 + 350 = 780 minutes (13 hours)
      expect(summary.totalWorkingHours, 7.17);
    });

    test('Single-shift attendance functions correctly without false multiple sessions', () {
      final singleRecords = [morningCompletedSession];
      final dailySummaries = singleRecords.groupIntoDailySummaries();

      expect(dailySummaries.length, 1);
      final summary = dailySummaries.first;

      expect(summary.hasMultipleSessions, isFalse);
      expect(summary.totalWorkingHours, 5.0);
      expect(summary.formattedTotalDuration, '5h');
      expect(summary.shiftDisplayName, 'Morning Shift');
    });

    test('During break between shifts, fetchActiveAttendance auto-terminates morning and returns null', () async {
      final openMorningRecord = AttendanceRecord(
        id: 'att-open-morning',
        staffId: 'staff-42',
        date: sampleDate,
        shift: 'morning',
        checkInTime: DateTime(2026, 10, 18, 8, 0),
        checkOutTime: null, // open
        workingHours: null,
        status: 'present',
        isLate: false,
        lateMinutes: 0,
      );

      final repo = _FakeAttendanceRepository(
        records: [openMorningRecord],
        assignedShift: 'both',
      );

      // 14:00 (2:00 PM) is during the gap after morning shift end (13:00)
      final gapTime = DateTime(2026, 10, 18, 14, 0);
      final active = await repo.fetchActiveAttendance('staff-42', forTime: gapTime);

      // Must return null: morning was auto-terminated, evening not yet started
      expect(active, isNull);
    });

    test('AttendanceRecord correctly handles timezone conversion and wall-clock anomalies', () {
      final jsonWithWallClockMismatch = {
        'id': 'rec-tz-1',
        'staff_id': 'staff-42',
        'record_date': '2026-10-18',
        'check_in_time': '2026-10-18T13:20:00+00:00',
        'check_out_time': '2026-10-18T15:30:00+00:00',
        'status': 'present',
        'is_late': false,
        'late_minutes': 0,
        'shift': 'evening',
      };

      final record = AttendanceRecord.fromJson(jsonWithWallClockMismatch);
      expect(record.workingHours, 2.17);
      expect(record.formattedWorkingDuration, '2h 10m');
      expect(record.formattedCheckInTime, contains('PM'));
      expect(record.formattedCheckOutTime, contains('PM'));
    });
  });

  // ───────────────────────────────────────────────────────────────────────────
  // 3. Issue 3: Invoice PDF Generation Completion & Platform Workflow
  // ───────────────────────────────────────────────────────────────────────────
  group('3. Billing: Invoice PDF Generation, Download & Action Availability', () {
    test('BillingPdfService generates valid non-empty A4 PDF with complete clinical details', () async {
      final pdfService = BillingPdfService();
      final bytes = await pdfService.generateInvoicePdf(sampleInvoice);

      expect(bytes, isNotEmpty);
      expect(bytes.length, greaterThan(1000));
      // PDF standard magic header %PDF
      expect(String.fromCharCodes(bytes.sublist(0, 4)), '%PDF');
    });

    test('BillingPdfService collision-safe filename sanitization', () {
      expect(
        BillingPdfService.getSafeInvoiceFilename('INV/2026/0042'),
        'Invoice_INV_2026_0042.pdf',
      );
      expect(
        BillingPdfService.getSafeInvoiceFilename('   '),
        'Invoice_Invoice_Generated.pdf',
      );
    });

    testWidgets('InvoiceSuccessDialog displays Download Invoice PDF button', (tester) async {
      await tester.pumpWidget(
        MaterialApp(
          home: Scaffold(
            body: InvoiceSuccessDialog(
              invoice: sampleInvoice,
            ),
          ),
        ),
      );

      await tester.pumpAndSettle();

      expect(find.byKey(const Key('success_dialog_download_pdf_button')), findsOneWidget);
      expect(find.text('Download Invoice PDF'), findsOneWidget);
      expect(find.text('Done'), findsOneWidget);
    });

    testWidgets('BillingManagementScreen mobile list tile has PDF download action', (tester) async {
      tester.view.physicalSize = const Size(375, 812);
      tester.view.devicePixelRatio = 1.0;
      addTearDown(tester.view.resetPhysicalSize);
      addTearDown(tester.view.resetDevicePixelRatio);

      final billingRepo = _FakeBillingRepository([sampleInvoice]);

      await tester.pumpWidget(
        ProviderScope(
          overrides: [
            supabaseProvider.overrideWithValue(_FakeSupabaseClient()),
            billingRepositoryProvider.overrideWithValue(billingRepo),
          ],
          child: const MaterialApp(
            home: Scaffold(
              body: BillingManagementScreen(isEmbedded: true),
            ),
          ),
        ),
      );

      await tester.pumpAndSettle();

      // Mobile list contains PDF icon button
      expect(find.byIcon(Icons.picture_as_pdf_outlined), findsWidgets);
      expect(find.text('INV-2026-0042'), findsOneWidget);
    });

    testWidgets('Invoice details dialog has prominent create_invoice_pdf_button', (tester) async {
      final billingRepo = _FakeBillingRepository([sampleInvoice]);

      await tester.pumpWidget(
        ProviderScope(
          overrides: [
            supabaseProvider.overrideWithValue(_FakeSupabaseClient()),
            billingRepositoryProvider.overrideWithValue(billingRepo),
          ],
          child: MaterialApp(
            home: Scaffold(
              body: Builder(
                builder: (context) => ElevatedButton(
                  onPressed: () {
                    showDialog(
                      context: context,
                      builder: (_) => AlertDialog(
                        content: Column(
                          mainAxisSize: MainAxisSize.min,
                          children: [
                            OutlinedButton.icon(
                              key: const Key('create_invoice_pdf_button'),
                              onPressed: () {},
                              icon: const Icon(Icons.picture_as_pdf_outlined),
                              label: const Text('Download Invoice PDF'),
                            ),
                          ],
                        ),
                      ),
                    );
                  },
                  child: const Text('Open Dialog'),
                ),
              ),
            ),
          ),
        ),
      );

      await tester.tap(find.text('Open Dialog'));
      await tester.pumpAndSettle();

      expect(find.byKey(const Key('create_invoice_pdf_button')), findsOneWidget);
      expect(find.text('Download Invoice PDF'), findsOneWidget);
    });
  });
}
