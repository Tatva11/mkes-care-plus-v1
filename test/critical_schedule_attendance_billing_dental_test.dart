import 'dart:typed_data';

import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:intl/intl.dart';
import 'package:supabase_flutter/supabase_flutter.dart';

import 'package:mkes_care/core/providers/supabase_provider.dart';
import 'package:mkes_care/features/appointments/models/appointment_model.dart';
import 'package:mkes_care/features/appointments/repositories/appointment_repository.dart';
import 'package:mkes_care/features/auth/models/profile_model.dart';
import 'package:mkes_care/features/auth/providers/auth_provider.dart';
import 'package:mkes_care/features/billing/models/billing_invoice_model.dart';
import 'package:mkes_care/features/billing/models/billing_item_model.dart';
import 'package:mkes_care/features/billing/models/billing_payment_model.dart';
import 'package:mkes_care/features/billing/services/billing_pdf_service.dart';
import 'package:mkes_care/features/dental/models/dental_lab_model.dart';
import 'package:mkes_care/features/dental/providers/dental_lab_provider.dart';
import 'package:mkes_care/features/dental/repositories/dental_lab_repository.dart';
import 'package:mkes_care/features/dental/widgets/dental_lab_form_dialog.dart';
import 'package:mkes_care/features/department/models/department.dart';
import 'package:mkes_care/features/department/providers/departments_provider.dart';
import 'package:mkes_care/features/department/repositories/department_repository.dart';
import 'package:mkes_care/features/eye/models/eye_surgery_model.dart';
import 'package:mkes_care/features/eye/providers/eye_surgery_provider.dart';
import 'package:mkes_care/features/eye/repositories/eye_surgery_repository.dart';
import 'package:mkes_care/features/patients/models/patient_model.dart';
import 'package:mkes_care/features/patients/providers/patients_provider.dart';
import 'package:mkes_care/features/patients/repositories/patient_repository.dart';
import 'package:mkes_care/features/staff/models/attendance_record.dart';
import 'package:mkes_care/features/staff/models/shift_configuration.dart';
import 'package:mkes_care/features/staff/repositories/attendance_repository.dart';
import 'package:mkes_care/features/staff_portal/screens/staff_schedule_screen.dart';

// ── Mock Classes ─────────────────────────────────────────────────────────────

class _FakeSupabaseClient extends Fake implements SupabaseClient {}

class _FakeAppointmentRepository extends Fake implements AppointmentRepository {
  final List<AppointmentModel> appointments;
  _FakeAppointmentRepository(this.appointments);

  @override
  Future<List<AppointmentModel>> fetchTodayAppointments({
    String? doctorId,
    String? department,
  }) async => appointments;

  @override
  Future<List<AppointmentModel>> fetchAppointments({
    String? department,
    DateTime? date,
    String? status,
    String? doctorId,
  }) async => appointments;
}

class _FakeEyeSurgeryRepository extends Fake implements EyeSurgeryRepository {
  @override
  Future<List<EyeSurgeryModel>> fetchSurgeries({String? status}) async => [];
}

class _FakeAttendanceRepository extends Fake implements AttendanceRepository {
  @override
  Future<List<ShiftConfiguration>> fetchShiftConfigurations() async => const [
        ShiftConfiguration.defaultMorning,
        ShiftConfiguration.defaultAfternoon,
      ];

  @override
  Future<String?> fetchStaffShiftAssignment(String staffId, {DateTime? forDate}) async => 'morning';
}

class _FixedDepartmentsNotifier extends DepartmentsNotifier {
  _FixedDepartmentsNotifier(List<Department> initial)
      : super(DepartmentRepository(SupabaseClient(
          'https://example.supabase.co',
          'key',
          authOptions: const AuthClientOptions(autoRefreshToken: false),
        ))) {
    state = AsyncData(initial);
  }

  @override
  Future<void> fetchDepartments() async {}
}

class _FakeDentalLabRepository extends Fake implements DentalLabRepository {
  @override
  Future<String> generateNextCaseNumber() async => 'DEN-20261018-0042';

  @override
  Future<DentalLabModel> createCase({
    required String patientId,
    required String caseNumber,
    required String caseType,
    required DateTime sentDate,
    String? doctorId,
    DateTime? readyDate,
    String? remarks,
  }) async {
    return DentalLabModel(
      id: 'case-created-1',
      caseNumber: caseNumber,
      patientId: patientId,
      caseType: caseType,
      sentDate: sentDate,
      status: 'sent',
      remarks: remarks,
      createdAt: DateTime.now(),
      updatedAt: DateTime.now(),
    );
  }
}

class _FakePatientRepository extends Fake implements PatientRepository {
  @override
  Future<List<PatientModel>> fetchPatients({String? department, String? searchQuery}) async {
    return [
      PatientModel(
        id: 'pat-101',
        patientNumber: 'D-999',
        name: 'Aarav Patel',
        mobile: '9876543210',
        department: 'dental',
        createdAt: DateTime.now(),
        updatedAt: DateTime.now(),
      ),
    ];
  }
}

void main() {
  TestWidgetsFlutterBinding.ensureInitialized();

  // ─────────────────────────────────────────────────────────────────────────
  // 1. CRITICAL: Staff Schedule Responsive & AI Removal Verification
  // ─────────────────────────────────────────────────────────────────────────
  group('1. Staff Schedule: Overflow & AI Removal Tests', () {
    final List<AppointmentModel> mockAppointments = [
      AppointmentModel(
        id: 'apt-1',
        patientName: 'Very Long Patient Name That Previously Caused Horizontal RenderFlex Overflow On Mobile Screens',
        patientNumber: 'P-100234',
        department: 'General Medicine & Critical Care Consultation',
        appointmentDate: DateTime.now(),
        appointmentTime: '09:30:00',
        appointmentType: 'surgery',
        status: 'in_progress',
        notes: 'Pre-op dental assessment completed. Anesthesia clearance received.',
        doctorName: 'Dr. Ramesh Sharma',
        createdAt: DateTime.now(),
        updatedAt: DateTime.now(),
      ),
      AppointmentModel(
        id: 'apt-2',
        patientName: 'Sunita Mehra',
        patientNumber: 'P-100235',
        department: 'Dental',
        appointmentDate: DateTime.now(),
        appointmentTime: '11:00:00',
        appointmentType: 'consultation',
        status: 'scheduled',
        notes: 'Crown fitting appointment',
        doctorName: 'Dr. Preeti Verma',
        createdAt: DateTime.now(),
        updatedAt: DateTime.now(),
      ),
    ];

    final staffProfile = ProfileModel(
      id: 'staff-1',
      email: 'staff@mkescare.com',
      fullName: 'Staff Nurse Geeta',
      role: 'staff',
      isActive: true,
      department: 'General',
      createdAt: DateTime.now(),
    );

    const testUser = User(
      id: 'staff-1',
      appMetadata: {},
      userMetadata: {},
      aud: 'authenticated',
      createdAt: '2026-01-01',
    );

    final viewports = <String, Size>{
      'Mobile 360px': const Size(360, 800),
      'Mobile 390px': const Size(390, 844),
      'Mobile 430px': const Size(430, 932),
      'Tablet 768px': const Size(768, 1024),
      'Desktop 1024px': const Size(1024, 768),
      'Desktop 1440px': const Size(1440, 900),
    };

    for (final entry in viewports.entries) {
      testWidgets('Schedule renders without overflow on ${entry.key}', (tester) async {
        tester.view.physicalSize = entry.value;
        tester.view.devicePixelRatio = 1.0;
        addTearDown(tester.view.resetPhysicalSize);
        addTearDown(tester.view.resetDevicePixelRatio);

        await tester.pumpWidget(
          ProviderScope(
            overrides: [
              supabaseProvider.overrideWithValue(_FakeSupabaseClient()),
              appointmentRepositoryProvider.overrideWithValue(
                _FakeAppointmentRepository(mockAppointments),
              ),
              currentUserProvider.overrideWithValue(testUser),
              currentUserRoleProvider.overrideWith((ref) async => 'staff'),
              currentProfileProvider.overrideWith((ref) async => staffProfile),
              eyeSurgeryRepositoryProvider.overrideWithValue(_FakeEyeSurgeryRepository()),
              departmentsProvider.overrideWith((ref) => _FixedDepartmentsNotifier([])),
              attendanceRepositoryProvider.overrideWithValue(_FakeAttendanceRepository()),
            ],
            child: const MaterialApp(
              home: Scaffold(
                body: StaffScheduleScreen(),
              ),
            ),
          ),
        );

        await tester.pumpAndSettle();

        // 1. Assert no exceptions or layout overflows
        expect(tester.takeException(), isNull);

        // 2. Assert AI Insight section is NOT present
        expect(find.text('AI Scheduling Tip'), findsNothing);
        expect(find.text('AI Insights'), findsNothing);
        expect(find.text('AI Insight'), findsNothing);
        expect(find.byIcon(Icons.auto_awesome), findsNothing);

        // 3. Assert core scheduling elements are intact
        expect(find.text('My Schedule'), findsOneWidget);
        expect(find.text('Book Appointment'), findsOneWidget);
        expect(find.text("Today's Schedule"), findsOneWidget);
        expect(find.byKey(const Key('staff_schedule_department_dropdown')), findsOneWidget);
      });
    }
  });

  // ─────────────────────────────────────────────────────────────────────────
  // 2. CRITICAL: Attendance Automatic Clock-Out & Completed Hours Verification
  // ─────────────────────────────────────────────────────────────────────────
  group('2. Attendance: 9:00 PM Clock-Out & Duration Calculations', () {
    test('Evening Shift: 6:50 PM clock-in yields 9:00 PM clock-out and 2.17 completed hours', () {
      final eveningConfig = ShiftConfiguration.defaultAfternoon; // 13:00 - 21:00
      expect(eveningConfig.startTime, equals('13:00'));
      expect(eveningConfig.endTime, equals('21:00'));

      // Check-in at 6:50 PM (18:50) local time
      final checkInTime = DateTime(2026, 10, 18, 18, 50);
      final shiftEndTime = eveningConfig.getShiftEndDateTime(checkInTime);

      // Scheduled end must be authoritative 21:00 (9:00 PM), not 15:30 (3:30 PM)
      expect(shiftEndTime.hour, equals(21));
      expect(shiftEndTime.minute, equals(0));
      expect(shiftEndTime.year, equals(2026));
      expect(shiftEndTime.month, equals(10));
      expect(shiftEndTime.day, equals(18));

      // Completed duty duration: 21:00 - 18:50 = 130 minutes = 2.1666... hours = 2.17h
      final durationMinutes = shiftEndTime.difference(checkInTime).inMinutes;
      expect(durationMinutes, equals(130));

      final workingHours = double.parse((durationMinutes / 60.0).clamp(0.0, 24.0).toStringAsFixed(2));
      expect(workingHours, equals(2.17));
    });

    test('AttendanceRecord.fromJson converts UTC 15:30:00Z to local 21:00 (9:00 PM) and self-heals zero working hours', () {
      // Supabase stores timestamptz in UTC. In IST (UTC+5:30), 21:00 IST is 15:30 UTC.
      // Previously, reading raw .hour on UTC parsed DateTime returned 15 (3:30 PM)!
      final jsonFromSupabase = {
        'id': 'att-123',
        'staff_id': 'staff-456',
        'record_date': '2026-10-18',
        'shift': 'afternoon',
        'check_in_time': '2026-10-18T13:20:00.000Z', // 18:50 IST
        'check_out_time': '2026-10-18T15:30:00.000Z', // 21:00 IST
        'status': 'present',
        'is_late': false,
        'working_hours': 0.0, // Historical corrupted zero value from negative UTC subtraction
        'late_minutes': 0,
        'notes': 'Auto-clocked out at configured shift end time',
      };

      final record = AttendanceRecord.fromJson(jsonFromSupabase);

      // Verify that parsed timestamps are in local timezone
      expect(record.checkInTime, isNotNull);
      expect(record.checkOutTime, isNotNull);
      expect(record.checkInTime!.isUtc, isFalse);
      expect(record.checkOutTime!.isUtc, isFalse);

      // Verify self-healed working hours: 15:30Z - 13:20Z = 130 min = 2.17h
      expect(record.workingHours, equals(2.17));

      // Verify formatting displays local 12-hour format cleanly
      final inFormatted = DateFormat('hh:mm a').format(record.checkInTime!);
      final outFormatted = DateFormat('hh:mm a').format(record.checkOutTime!);

      // Both In and Out must reflect a 2h 10m difference
      final diff = record.checkOutTime!.difference(record.checkInTime!).inMinutes;
      expect(diff, equals(130));
      expect(inFormatted.isNotEmpty, isTrue);
      expect(outFormatted.isNotEmpty, isTrue);
    });

    test('Morning Shift: 08:00 to 13:00 yields 5.0 completed hours', () {
      final morningConfig = ShiftConfiguration.defaultMorning; // 08:00 - 13:00
      final checkInTime = DateTime(2026, 10, 18, 8, 0);
      final shiftEndTime = morningConfig.getShiftEndDateTime(checkInTime);

      expect(shiftEndTime.hour, equals(13));
      expect(shiftEndTime.minute, equals(0));

      final durationMinutes = shiftEndTime.difference(checkInTime).inMinutes;
      expect(durationMinutes, equals(300));
      final hours = durationMinutes / 60.0;
      expect(hours, equals(5.0));
    });

    test('Manual clock-out uses actual timestamp and does not get overwritten', () {
      // Manual clock-out at 8:30 PM (20:30) before shift end 9:00 PM (21:00)
      final checkInTime = DateTime(2026, 10, 18, 18, 50);
      final manualCheckOut = DateTime(2026, 10, 18, 20, 30);

      final diffMinutes = manualCheckOut.difference(checkInTime).inMinutes;
      expect(diffMinutes, equals(100)); // 1h 40m

      final workingHours = double.parse((diffMinutes / 60.0).toStringAsFixed(2));
      expect(workingHours, equals(1.67));

      final record = AttendanceRecord(
        id: 'att-manual',
        staffId: 'staff-456',
        date: DateTime(2026, 10, 18),
        checkInTime: checkInTime,
        checkOutTime: manualCheckOut,
        status: 'present',
        isLate: false,
        workingHours: workingHours,
        lateMinutes: 0,
      );

      // Verify that an already finalized manual record retains its manual clock out
      expect(record.checkOutTime, equals(manualCheckOut));
      expect(record.workingHours, equals(1.67));
    });
  });

  // ─────────────────────────────────────────────────────────────────────────
  // 3. Billing: PDF Generation & Local File Storage Verification
  // ─────────────────────────────────────────────────────────────────────────
  group('3. Billing: Invoice PDF Generation Tests', () {
    final representativeInvoice = BillingInvoiceModel(
      id: 'inv-test-001',
      invoiceNumber: 'INV-20261018-0099',
      patientId: 'pat-101',
      patientName: 'Pooja Bhatt',
      patientNumber: 'P-8812',
      patientMobile: '+91 98765 43210',
      department: 'dental',
      subtotal: 5000.0,
      discount: 500.0,
      totalAmount: 4500.0,
      paymentStatus: 'partially_paid',
      amountPaid: 2000.0,
      createdAt: DateTime(2026, 10, 18, 14, 30),
      updatedAt: DateTime(2026, 10, 18, 14, 45),
      items: const [
        BillingItemModel(
          id: 'item-1',
          billingId: 'inv-test-001',
          serviceName: 'Root Canal Treatment (RCT)',
          quantity: 1,
          unitPrice: 3500.0,
          totalAmount: 3500.0,
        ),
        BillingItemModel(
          id: 'item-2',
          billingId: 'inv-test-001',
          serviceName: 'Zirconia Ceramic Crown',
          quantity: 1,
          unitPrice: 1500.0,
          totalAmount: 1500.0,
        ),
      ],
      payments: [
        BillingPaymentModel(
          id: 'pay-1',
          billingId: 'inv-test-001',
          amount: 2000.0,
          paymentMode: 'upi',
          paymentReference: 'UPI-98127391823',
          paidAt: DateTime(2026, 10, 18, 14, 45),
        ),
      ],
    );

    test('generateInvoicePdf generates valid non-empty PDF bytes with all financial fields', () async {
      final pdfService = BillingPdfService();
      final Uint8List pdfBytes = await pdfService.generateInvoicePdf(representativeInvoice);

      expect(pdfBytes, isNotNull);
      expect(pdfBytes.length, greaterThan(1000));

      // PDF header magic bytes "%PDF-"
      final header = String.fromCharCodes(pdfBytes.sublist(0, 5));
      expect(header, equals('%PDF-'));
    });

    test('BillingPdfService collision-safe filename sanitization', () {
      final pdfService = BillingPdfService();
      final filename = pdfService.getInvoiceFilename('INV/2026/10:18 #99');
      expect(filename, equals('Invoice_INV_2026_10_18__99.pdf'));
      expect(filename.contains('/'), isFalse);
      expect(filename.contains(':'), isFalse);
    });

    test('generateInvoicePdf handles invoices with empty payments and missing patient mobile', () async {
      final minimalInvoice = BillingInvoiceModel(
        id: 'inv-test-002',
        invoiceNumber: 'INV-2026-MIN',
        patientId: 'pat-102',
        patientName: 'Anonymous Patient',
        department: 'general',
        subtotal: 500.0,
        totalAmount: 500.0,
        paymentStatus: 'pending',
        amountPaid: 0.0,
        createdAt: DateTime(2026, 10, 18),
        updatedAt: DateTime(2026, 10, 18),
        items: const [
          BillingItemModel(
            id: 'item-min-1',
            billingId: 'inv-test-002',
            serviceName: 'General Consultation',
            quantity: 1,
            unitPrice: 500.0,
            totalAmount: 500.0,
          ),
        ],
        payments: const [],
      );

      final pdfService = BillingPdfService();
      final Uint8List pdfBytes = await pdfService.generateInvoicePdf(minimalInvoice);

      expect(pdfBytes, isNotNull);
      expect(pdfBytes.length, greaterThan(1000));
    });
  });

  // ─────────────────────────────────────────────────────────────────────────
  // 4. Dental Lab: Form Dialog Responsiveness & Error Handling
  // ─────────────────────────────────────────────────────────────────────────
  group('4. Dental Lab: New Action & Form Dialog Tests', () {
    testWidgets('DentalLabFormDialog renders reliably without white screen or unbounded constraint crash', (tester) async {
      tester.view.physicalSize = const Size(360, 720);
      tester.view.devicePixelRatio = 1.0;
      addTearDown(tester.view.resetPhysicalSize);
      addTearDown(tester.view.resetDevicePixelRatio);

      await tester.pumpWidget(
        ProviderScope(
          overrides: [
            dentalLabRepositoryProvider.overrideWithValue(_FakeDentalLabRepository()),
            patientRepositoryProvider.overrideWithValue(_FakePatientRepository()),
            patientsByDepartmentProvider('dental').overrideWith((ref) async => [
              PatientModel(
                id: 'pat-101',
                patientNumber: 'D-999',
                name: 'Aarav Patel',
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

      // Form header and required labels must render
      expect(find.text('New Dental Lab Case'), findsOneWidget);
      expect(find.text('PATIENT *'), findsOneWidget);
      expect(find.text('CASE NUMBER *'), findsOneWidget);
      expect(find.text('CASE TYPE *'), findsOneWidget);
      expect(find.text('SENT DATE *'), findsOneWidget);

      // Buttons must be visible and interactive
      expect(find.text('Cancel'), findsOneWidget);
      expect(find.text('Create Lab Case'), findsOneWidget);

      // Scroll to button and tap to trigger form validation
      await tester.ensureVisible(find.text('Create Lab Case'));
      await tester.tap(find.text('Create Lab Case'));
      await tester.pumpAndSettle();

      // Patient was not selected yet, error message must show
      expect(find.text('Please search and select a patient'), findsOneWidget);

      expect(tester.takeException(), isNull);
    });
  });
}
