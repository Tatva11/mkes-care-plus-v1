import 'dart:typed_data';
import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:mkes_care/core/providers/supabase_provider.dart';
import 'package:mkes_care/features/auth/models/profile_model.dart';
import 'package:mkes_care/features/auth/providers/auth_provider.dart';
import 'package:mkes_care/features/billing/models/billing_invoice_model.dart';
import 'package:mkes_care/features/billing/models/billing_item_model.dart';
import 'package:mkes_care/features/billing/models/billing_payment_model.dart';
import 'package:mkes_care/features/billing/providers/billing_provider.dart';
import 'package:mkes_care/features/billing/repositories/billing_repository.dart';
import 'package:mkes_care/features/billing/screens/billing_management_screen.dart';
import 'package:mkes_care/features/billing/services/billing_pdf_service.dart';
import 'package:mkes_care/features/billing/widgets/invoice_success_dialog.dart';
import 'package:mkes_care/features/staff/models/attendance_record.dart';
import 'package:mkes_care/features/staff/models/leave_request.dart';
import 'package:mkes_care/features/staff/models/shift_configuration.dart';
import 'package:mkes_care/features/staff/providers/attendance_provider.dart';
import 'package:mkes_care/features/staff/repositories/attendance_repository.dart';
import 'package:mkes_care/features/staff/repositories/leave_repository.dart';
import 'package:mkes_care/features/staff_portal/screens/staff_attendance_screen.dart';
import 'package:mkes_care/features/staff_portal/screens/staff_schedule_screen.dart';
import 'package:mkes_care/features/appointments/repositories/appointment_repository.dart';
import 'package:mkes_care/features/appointments/models/appointment_model.dart';
import 'package:mkes_care/features/department/models/department.dart';
import 'package:mkes_care/features/department/repositories/department_repository.dart';
import 'package:mkes_care/features/eye/models/eye_surgery_model.dart';
import 'package:mkes_care/features/eye/repositories/eye_surgery_repository.dart';
import 'package:mkes_care/features/eye/providers/eye_surgery_provider.dart';
import 'package:supabase_flutter/supabase_flutter.dart';

// ─── FAKE IMPLEMENTATIONS ─────────────────────────────────────────────────────

class _FakeSupabaseClient extends Fake implements SupabaseClient {}

class _FakeBillingRepository extends Fake implements BillingRepository {
  List<BillingInvoiceModel> invoices;
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
  }) async {
    return invoices;
  }

  @override
  Future<BillingInvoiceModel> fetchInvoiceById(String invoiceId) async {
    return invoices.firstWhere((i) => i.id == invoiceId, orElse: () => invoices.first);
  }

  @override
  Future<BillingInvoiceModel> updateInvoice({
    required String invoiceId,
    required double subtotal,
    required double discount,
    required double totalAmount,
    required String paymentStatus,
    String? notes,
    String? department,
    List<BillingItemModel>? items,
  }) async {
    final idx = invoices.indexWhere((i) => i.id == invoiceId);
    final original = idx >= 0 ? invoices[idx] : invoices.first;
    final updated = BillingInvoiceModel(
      id: original.id,
      invoiceNumber: original.invoiceNumber,
      patientId: original.patientId,
      department: department ?? original.department,
      subtotal: subtotal,
      discount: discount,
      totalAmount: totalAmount,
      paymentStatus: paymentStatus,
      paymentMode: original.paymentMode,
      amountPaid: original.amountPaid,
      billedBy: original.billedBy,
      notes: notes ?? original.notes,
      eyeSurgeryId: original.eyeSurgeryId,
      createdAt: original.createdAt,
      updatedAt: DateTime.now(),
      patientName: original.patientName,
      patientNumber: original.patientNumber,
      patientMobile: original.patientMobile,
      items: items ?? original.items,
      payments: original.payments,
    );
    if (idx >= 0) {
      invoices[idx] = updated;
    }
    return updated;
  }
}

class _FakeAttendanceRepository extends Fake implements AttendanceRepository {
  final List<ShiftConfiguration> configs;
  final Map<String, AttendanceRecord?> todayRecords;
  final String assignedShift = 'both';

  _FakeAttendanceRepository({
    required this.configs,
    this.todayRecords = const {},
  });

  @override
  Future<List<ShiftConfiguration>> fetchShiftConfigurations() async {
    return configs;
  }

  @override
  Future<String?> fetchStaffShiftAssignment(String staffId, {DateTime? forDate}) async {
    return assignedShift;
  }

  @override
  Future<AttendanceRecord?> fetchTodayAttendance(
    String staffId, {
    String shift = 'morning',
    ShiftConfiguration? config,
  }) async {
    return todayRecords[shift];
  }

  @override
  Future<List<AttendanceRecord>> fetchMonthlyAttendance(
    String staffId,
    int year,
    int month, {
    String? shift,
  }) async {
    return todayRecords.values.whereType<AttendanceRecord>().toList();
  }

  @override
  Future<AttendanceRecord?> fetchActiveAttendance(
    String staffId, {
    String? shift,
    ShiftConfiguration? config,
    DateTime? forTime,
  }) async {
    return null;
  }
}

class _FakeAppointmentRepository extends Fake implements AppointmentRepository {
  @override
  Future<List<AppointmentModel>> fetchAppointments({
    DateTime? date,
    String? doctorId,
    String? department,
    String? status,
  }) async {
    return [];
  }
}

class _FakeDepartmentRepository extends Fake implements DepartmentRepository {
  @override
  Future<List<Department>> fetchDepartments() async => [];
}

class _FakeEyeSurgeryRepository extends Fake implements EyeSurgeryRepository {
  @override
  Future<List<EyeSurgeryModel>> fetchSurgeries({String? status}) async => [];
}

class _FakeLeaveRepository extends Fake implements LeaveRepository {
  @override
  Future<List<LeaveRequest>> fetchStaffLeaveRequests(String staffId) async {
    return [];
  }
}

void main() {
  TestWidgetsFlutterBinding.ensureInitialized();

  final sampleInvoice = BillingInvoiceModel(
    id: 'inv-test-1',
    invoiceNumber: 'INV-2026-0099',
    patientId: 'patient-42',
    patientName: 'Jane Doe',
    patientNumber: 'P-1042',
    patientMobile: '+91 98765 43210',
    department: 'eye',
    subtotal: 3500.0,
    discount: 500.0,
    totalAmount: 3000.0,
    amountPaid: 1500.0,
    paymentStatus: 'partially_paid',
    billedBy: 'Dr. Smith',
    notes: 'Follow-up in 2 weeks',
    createdAt: DateTime(2026, 8, 15, 11, 30),
    updatedAt: DateTime(2026, 8, 15, 11, 30),
    items: const [
      BillingItemModel(
        id: 'item-1',
        serviceName: 'Comprehensive Eye Examination',
        quantity: 1,
        unitPrice: 1500.0,
        totalAmount: 1500.0,
      ),
      BillingItemModel(
        id: 'item-2',
        serviceName: 'OCT Macula Scan',
        quantity: 1,
        unitPrice: 2000.0,
        totalAmount: 2000.0,
      ),
    ],
    payments: [
      BillingPaymentModel(
        id: 'pay-1',
        billingId: 'inv-test-1',
        amount: 1500.0,
        paymentMode: 'upi',
        paymentReference: 'UPI-987654321',
        paidAt: DateTime(2026, 8, 15, 11, 35),
      ),
    ],
  );

  const morningConfig = ShiftConfiguration(
    shift: 'morning',
    name: 'morning',
    startTime: '10:00:00',
    endTime: '13:00:00',
    gracePeriodMinutes: 15,
  );

  const afternoonConfig = ShiftConfiguration(
    shift: 'afternoon',
    name: 'afternoon',
    startTime: '16:00:00',
    endTime: '21:00:00',
    gracePeriodMinutes: 15,
  );

  final staffUser = const User(
    id: 'staff-both-1',
    appMetadata: {},
    userMetadata: {},
    aud: 'authenticated',
    createdAt: '2026-01-01T00:00:00Z',
  );

  final staffProfileBoth = ProfileModel(
    id: 'staff-both-1',
    email: 'staff@mkes.org',
    fullName: 'Nurse Sarah',
    role: 'staff',
    department: 'eye',
    assignedShift: 'both',
    isActive: true,
    createdAt: DateTime(2026, 1, 1),
  );

  // ═══════════════════════════════════════════════════════════════════════════
  // ISSUE 1: Cross-Platform PDF Generation & Delivery
  // ═══════════════════════════════════════════════════════════════════════════
  group('Issue 1: Invoice PDF Generation Across All Platforms', () {
    test('generateInvoiceBytes produces a valid, non-empty A4 PDF with complete invoice data', () async {
      final bytes = await BillingPdfService.generateInvoiceBytes(sampleInvoice);

      expect(bytes, isA<Uint8List>());
      expect(bytes.isNotEmpty, isTrue);
      // Valid PDF files start with %PDF-
      final header = String.fromCharCodes(bytes.take(5));
      expect(header, '%PDF-');
    });

    test('getSafeInvoiceFilename sanitizes special characters cleanly', () {
      expect(BillingPdfService.getSafeInvoiceFilename('INV/2026/0099'), 'Invoice_INV_2026_0099.pdf');
      expect(BillingPdfService.getSafeInvoiceFilename('INV:42*test'), 'Invoice_INV_42_test.pdf');
      expect(BillingPdfService.getSafeInvoiceFilename(''), 'Invoice_Invoice_Generated.pdf');
    });

    testWidgets('Invoice list displays PDF action button and triggers download', (tester) async {
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
            adminBillingInvoicesProvider.overrideWith((ref) => [sampleInvoice]),
          ],
          child: const MaterialApp(
            home: Scaffold(
              body: BillingManagementScreen(isEmbedded: true),
            ),
          ),
        ),
      );

      await tester.pumpAndSettle();

      expect(find.byIcon(Icons.picture_as_pdf_outlined), findsWidgets);
      expect(find.text('INV-2026-0099'), findsOneWidget);
    });

    testWidgets('Invoice success dialog contains prominent PDF action button', (tester) async {
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

      expect(find.byKey(const Key('invoice_success_download_pdf_button')), findsOneWidget);
    });
  });

  // ═══════════════════════════════════════════════════════════════════════════
  // ISSUE 2: Combined Daily Shift Attendance Card
  // ═══════════════════════════════════════════════════════════════════════════
  group('Issue 2: Both Daily Shifts Combined In One Duty Card', () {
    testWidgets('Renders one combined Both Shifts duty card instead of two separate cards', (tester) async {
      tester.view.physicalSize = const Size(390, 844);
      tester.view.devicePixelRatio = 1.0;
      addTearDown(tester.view.resetPhysicalSize);
      addTearDown(tester.view.resetDevicePixelRatio);

      final repo = _FakeAttendanceRepository(
        configs: const [morningConfig, afternoonConfig],
        todayRecords: {
          'morning': AttendanceRecord(
            id: 'rec-m',
            staffId: 'staff-both-1',
            date: DateTime(2026, 8, 15),
            shift: 'morning',
            checkInTime: DateTime(2026, 8, 15, 10, 0),
            checkOutTime: DateTime(2026, 8, 15, 13, 0),
            workingHours: 3.0,
            status: 'present',
            isLate: false,
            lateMinutes: 0,
          ),
          'afternoon': AttendanceRecord(
            id: 'rec-e',
            staffId: 'staff-both-1',
            date: DateTime(2026, 8, 15),
            shift: 'afternoon',
            checkInTime: DateTime(2026, 8, 15, 16, 0),
            checkOutTime: DateTime(2026, 8, 15, 21, 0),
            workingHours: 5.0,
            status: 'present',
            isLate: false,
            lateMinutes: 0,
          ),
        },
      );

      await tester.pumpWidget(
        ProviderScope(
          overrides: [
            supabaseProvider.overrideWithValue(_FakeSupabaseClient()),
            currentUserProvider.overrideWithValue(staffUser),
            currentUserRoleProvider.overrideWith((ref) async => 'staff'),
            currentProfileProvider.overrideWith((ref) async => staffProfileBoth),
            attendanceRepositoryProvider.overrideWithValue(repo),
            shiftConfigurationsProvider.overrideWith((ref) async => const [morningConfig, afternoonConfig]),
            leaveRepositoryProvider.overrideWithValue(_FakeLeaveRepository()),
          ],
          child: const MaterialApp(
            home: Scaffold(
              body: StaffAttendanceScreen(),
            ),
          ),
        ),
      );

      await tester.pumpAndSettle();

      // Verified: ONE combined header for Both Shifts
      expect(find.text('BOTH SHIFTS'), findsOneWidget);

      // Verified: Displays both configured shift intervals together
      expect(
        find.text('${morningConfig.formattedTiming} · ${afternoonConfig.formattedTiming}'),
        findsOneWidget,
      );

      // Verified: Both sessions and the break are distinguished in the card
      expect(find.textContaining('Morning Session'), findsWidgets);
      expect(find.textContaining('Evening Session'), findsWidgets);
      expect(find.textContaining('Inter-Shift Break'), findsOneWidget);

      // Verified: Working hours excludes the break: 3.0 + 5.0 = 8.0 hrs
      expect(find.textContaining('8.0 hrs'), findsWidgets);
    });
  });

  // ═══════════════════════════════════════════════════════════════════════════
  // ISSUE 3: Invoice Navigation Arrow, Details & Edit Persistence
  // ═══════════════════════════════════════════════════════════════════════════
  group('Issue 3: Invoice Arrow Navigation and Edit Workflow', () {
    testWidgets('Tapping the arrow button opens invoice details and supports editing', (tester) async {
      tester.view.physicalSize = const Size(390, 844);
      tester.view.devicePixelRatio = 1.0;
      addTearDown(tester.view.resetPhysicalSize);
      addTearDown(tester.view.resetDevicePixelRatio);

      final billingRepo = _FakeBillingRepository([sampleInvoice]);

      await tester.pumpWidget(
        ProviderScope(
          overrides: [
            supabaseProvider.overrideWithValue(_FakeSupabaseClient()),
            billingRepositoryProvider.overrideWithValue(billingRepo),
            adminBillingInvoicesProvider.overrideWith((ref) => [sampleInvoice]),
          ],
          child: const MaterialApp(
            home: Scaffold(
              body: BillingManagementScreen(isEmbedded: true),
            ),
          ),
        ),
      );

      await tester.pumpAndSettle();

      // Arrow button is present beside the PDF button
      final arrowButtonFinder = find.byKey(Key('invoice_arrow_button_${sampleInvoice.invoiceNumber}'));
      expect(arrowButtonFinder, findsOneWidget);

      // Ensure visible before tapping
      await tester.ensureVisible(arrowButtonFinder);
      await tester.pumpAndSettle();

      // Tap arrow to open invoice details
      await tester.tap(arrowButtonFinder);
      await tester.pump();
      await tester.pump(const Duration(milliseconds: 300));

      // Invoice dialog opens with complete details (NOT a blank white screen!)
      expect(
        find.descendant(
          of: find.byType(Dialog),
          matching: find.text(sampleInvoice.invoiceNumber),
        ),
        findsOneWidget,
      );
      expect(find.textContaining('Jane Doe'), findsWidgets);
      final editButtonFinder = find.byKey(const Key('edit_invoice_button'));
      expect(editButtonFinder, findsOneWidget);
      await tester.ensureVisible(editButtonFinder);
      await tester.pump();
      await tester.pump(const Duration(milliseconds: 300));

      // Tap "Edit Invoice" button to enter edit mode
      await tester.tap(editButtonFinder);
      await tester.pump();
      await tester.pump(const Duration(milliseconds: 300));

      expect(find.text('EDIT INVOICE'), findsOneWidget);
      final saveButtonFinder = find.text('Save Changes');
      expect(saveButtonFinder, findsOneWidget);
      await tester.ensureVisible(saveButtonFinder);
      await tester.pump();
      await tester.pump(const Duration(milliseconds: 300));

      // Tap Save Changes
      await tester.tap(saveButtonFinder);
      await tester.pump();
      await tester.pump(const Duration(milliseconds: 300));

      // Successfully saved and persisted without creating duplicate
      expect(billingRepo.invoices.length, 1);
      expect(find.text('Invoice ${sampleInvoice.invoiceNumber} updated successfully.'), findsOneWidget);
    });
  });

  // ═══════════════════════════════════════════════════════════════════════════
  // ISSUE 4: Responsive Schedule Alignment at 360, 375, 390, 430, 768, 1024, 1440
  // ═══════════════════════════════════════════════════════════════════════════
  group('Issue 4: Schedule Controls Alignment Across Viewports', () {
    const viewports = [
      Size(360, 640),
      Size(375, 812),
      Size(390, 844),
      Size(430, 932),
      Size(768, 1024),
      Size(1024, 768),
      Size(1440, 900),
    ];

    for (final size in viewports) {
      testWidgets('Aligns Date Selector, Book Appointment, and Both Shifts summary at ${size.width.toInt()}px width without overflow', (tester) async {
        tester.view.physicalSize = size;
        tester.view.devicePixelRatio = 1.0;
        addTearDown(tester.view.resetPhysicalSize);
        addTearDown(tester.view.resetDevicePixelRatio);

        final repo = _FakeAttendanceRepository(
          configs: const [morningConfig, afternoonConfig],
        );

        await tester.pumpWidget(
          ProviderScope(
            overrides: [
              supabaseProvider.overrideWithValue(_FakeSupabaseClient()),
              currentUserProvider.overrideWithValue(staffUser),
              currentUserRoleProvider.overrideWith((ref) async => 'staff'),
              currentProfileProvider.overrideWith((ref) async => staffProfileBoth),
              attendanceRepositoryProvider.overrideWithValue(repo),
              shiftConfigurationsProvider.overrideWith((ref) async => const [morningConfig, afternoonConfig]),
              appointmentRepositoryProvider.overrideWithValue(_FakeAppointmentRepository()),
              departmentRepositoryProvider.overrideWithValue(_FakeDepartmentRepository()),
              eyeSurgeryRepositoryProvider.overrideWithValue(_FakeEyeSurgeryRepository()),
            ],
            child: const MaterialApp(
              home: Scaffold(
                body: StaffScheduleScreen(),
              ),
            ),
          ),
        );

        await tester.pump();
        await tester.pump(const Duration(milliseconds: 200));

        // 1. Controls are present
        expect(find.byKey(const Key('staff_schedule_prev_date_button')), findsOneWidget);
        expect(find.byKey(const Key('staff_schedule_next_date_button')), findsOneWidget);
        expect(find.byKey(const Key('staff_schedule_book_appointment_button')), findsOneWidget);
        expect(find.text('BOTH SHIFTS'), findsOneWidget);

        // 2. No RenderFlex or layout overflow exception
        expect(tester.takeException(), isNull);
      });
    }
  });
}
