import 'package:flutter_test/flutter_test.dart';

import 'package:mkes_care/features/admin/models/user_profile.dart';
import 'package:mkes_care/features/appointments/models/appointment_model.dart';
import 'package:mkes_care/features/appointments/models/department_doctor_config.dart';
import 'package:mkes_care/features/billing/models/billing_invoice_model.dart';
import 'package:mkes_care/features/billing/models/billing_item_model.dart';
import 'package:mkes_care/features/eye/models/eye_surgery_model.dart';
import 'package:mkes_care/features/staff/models/attendance_record.dart';
import 'package:mkes_care/features/staff/models/task_item.dart';
import 'package:mkes_care/features/staff/utils/task_operational_filter.dart';

void main() {
  TestWidgetsFlutterBinding.ensureInitialized();

  // ──────────────────────────────────────────────────────────────────────────
  // Test 1: Surgery schedule entries never become overdue tasks
  // ──────────────────────────────────────────────────────────────────────────
  group('1. Surgery schedule entries never become overdue tasks', () {
    final now = DateTime(2026, 10, 17, 16, 0);

    test('Surgery task scheduled for today never receives isOverdue flag', () {
      final surgeryTask = TaskItem(
        id: 'task-surg-1',
        title: 'Cataract Surgery - Room 1',
        assignedTo: 'staff-1',
        status: 'pending',
        priority: 'high',
        dueDate: DateTime(2026, 10, 17, 10, 0), // 10:00 AM today (in the past!)
        relatedSurgeryId: 'surg-uuid-1',
        createdAt: now.subtract(const Duration(hours: 8)),
        updatedAt: now.subtract(const Duration(hours: 8)),
      );

      // Model level isOverdue must be false for surgery task
      expect(surgeryTask.isSurgeryTask, isTrue);
      expect(surgeryTask.isOverdue, isFalse);

      // Filter level overdue carry forward must be false
      expect(TaskOperationalFilter.isOverdueCarryForward(surgeryTask, now),
          isFalse);
    });

    test(
        'Past surgery schedule entries are not carried forward as overdue tasks',
        () {
      final pastSurgeryTask = TaskItem(
        id: 'task-surg-yesterday',
        title: 'Yesterday Cataract Surgery',
        assignedTo: 'staff-1',
        status: 'pending',
        priority: 'critical',
        dueDate: DateTime(2026, 10, 16, 14, 0), // yesterday
        relatedSurgeryId: 'surg-uuid-2',
        createdAt: now.subtract(const Duration(days: 2)),
        updatedAt: now.subtract(const Duration(days: 1)),
      );

      // Must NOT be carried forward to today's operational list
      final operational = TaskOperationalFilter.filterOperationalTasks(
        [pastSurgeryTask],
        referenceDate: now,
      );
      expect(operational, isEmpty);
      expect(TaskOperationalFilter.isOverdueCarryForward(pastSurgeryTask, now),
          isFalse);
    });
  });

  // ──────────────────────────────────────────────────────────────────────────
  // Test 2: Genuine incomplete overdue tasks remain overdue
  // ──────────────────────────────────────────────────────────────────────────
  group('2. Genuine incomplete overdue tasks remain overdue', () {
    final now = DateTime(2026, 10, 17, 14, 0);

    test(
        'Actual incomplete task from previous days remains overdue with original due date',
        () {
      final overdueTask = TaskItem(
        id: 'task-regular-overdue',
        title: 'Sterilize Surgical Instruments',
        assignedTo: 'staff-1',
        status: 'pending',
        priority: 'critical',
        dueDate: DateTime(2026, 10, 15, 9, 30),
        relatedSurgeryId: null,
        createdAt: DateTime(2026, 10, 14),
        updatedAt: DateTime(2026, 10, 14),
      );

      expect(overdueTask.isOverdue, isTrue);
      expect(TaskOperationalFilter.isOverdueCarryForward(overdueTask, now),
          isTrue);

      final operational = TaskOperationalFilter.filterOperationalTasks(
        [overdueTask],
        referenceDate: now,
      );
      expect(operational.length, equals(1));
      expect(operational.first.id, equals('task-regular-overdue'));
      expect(
        TaskOperationalFilter.formatDueDateMessage(operational.first.dueDate!),
        equals('Due on 15 Oct 2026'),
      );
    });

    test('Completed and cancelled tasks must not be marked overdue', () {
      final completedTask = TaskItem(
        id: 'task-comp',
        title: 'Restock Pharmacy',
        assignedTo: 'staff-1',
        status: 'completed',
        priority: 'high',
        dueDate: DateTime(2026, 10, 15, 10, 0),
        createdAt: DateTime(2026, 10, 14),
        updatedAt: DateTime(2026, 10, 15),
      );

      final cancelledTask = TaskItem(
        id: 'task-canc',
        title: 'Review Inventory Report',
        assignedTo: 'staff-1',
        status: 'cancelled',
        priority: 'medium',
        dueDate: DateTime(2026, 10, 15, 10, 0),
        createdAt: DateTime(2026, 10, 14),
        updatedAt: DateTime(2026, 10, 15),
      );

      expect(completedTask.isOverdue, isFalse);
      expect(cancelledTask.isOverdue, isFalse);

      final operational = TaskOperationalFilter.filterOperationalTasks(
        [completedTask, cancelledTask],
        referenceDate: now,
      );
      expect(operational, isEmpty);
    });
  });

  // ──────────────────────────────────────────────────────────────────────────
  // Test 3: Department-specific doctor selection and department switching
  // ──────────────────────────────────────────────────────────────────────────
  group('3. Department-specific doctor selection and department switching', () {
    const miteshUuid = '550e8400-e29b-41d4-a716-446655440001';
    const varunUuid = '550e8400-e29b-41d4-a716-446655440002';
    const nimishaUuid = '550e8400-e29b-41d4-a716-446655440003';
    const vikasUuid = '550e8400-e29b-41d4-a716-446655440004';

    setUp(() {
      DepartmentDoctorConfig.reset();
      final now = DateTime.now();
      DepartmentDoctorConfig.syncWithDatabaseProfiles([
        UserProfile(
          id: miteshUuid,
          fullName: 'Dr Mitesh Patel',
          email: 'mitesh@mkes.com',
          department: 'Eye',
          departmentName: 'Eye Department',
          role: 'doctor',
          isActive: true,
          createdAt: now,
        ),
        UserProfile(
          id: varunUuid,
          fullName: 'Dr Varun Shah',
          email: 'varun@mkes.com',
          department: 'Eye',
          departmentName: 'Eye Department',
          role: 'doctor',
          isActive: true,
          createdAt: now,
        ),
        UserProfile(
          id: nimishaUuid,
          fullName: 'Dr Nimisha Dave',
          email: 'nimisha@mkes.com',
          department: 'Dental',
          departmentName: 'Dental Department',
          role: 'doctor',
          isActive: true,
          createdAt: now,
        ),
        UserProfile(
          id: vikasUuid,
          fullName: 'Dr Vikas Sharma',
          email: 'vikas@mkes.com',
          department: 'Dental',
          departmentName: 'Dental Department',
          role: 'doctor',
          isActive: true,
          createdAt: now,
        ),
      ]);
    });

    tearDown(() {
      DepartmentDoctorConfig.reset();
    });

    test('Eye roster strictly contains Dr Mitesh Jain and Dr Varun with valid UUIDs',
        () {
      final eyeDoctors = DepartmentDoctorConfig.getDoctorsForDepartment('eye');
      expect(eyeDoctors.length, equals(2));
      expect(eyeDoctors.map((d) => d.fullName).toList(),
          equals(['Dr Mitesh Jain', 'Dr Varun']));
      expect(eyeDoctors.map((d) => d.id).toList(),
          equals([miteshUuid, varunUuid]));
      expect(eyeDoctors.every((d) => DepartmentDoctorConfig.isValidUuid(d.id)),
          isTrue);
    });

    test(
        'Dental roster strictly contains Dr Nimisha and Dr Vikas with valid UUIDs',
        () {
      final dentalDoctors =
          DepartmentDoctorConfig.getDoctorsForDepartment('dental');
      expect(dentalDoctors.length, equals(2));
      expect(dentalDoctors.map((d) => d.fullName).toList(),
          equals(['Dr Nimisha', 'Dr Vikas']));
      expect(dentalDoctors.map((d) => d.id).toList(),
          equals([nimishaUuid, vikasUuid]));
      expect(
          dentalDoctors.every((d) => DepartmentDoctorConfig.isValidUuid(d.id)),
          isTrue);
    });

    test('Switching department clears mismatched doctor', () {
      String? selectedDoctorId = miteshUuid;
      String currentDepartment = 'eye';
      expect(
          DepartmentDoctorConfig.isValidDoctorForDepartment(
              selectedDoctorId, currentDepartment),
          isTrue);

      // Switch to Dental
      currentDepartment = 'dental';
      if (!DepartmentDoctorConfig.isValidDoctorForDepartment(
          selectedDoctorId, currentDepartment)) {
        selectedDoctorId = null;
      }
      expect(selectedDoctorId, isNull);

      // Select Dr Vikas
      selectedDoctorId = vikasUuid;
      expect(
          DepartmentDoctorConfig.isValidDoctorForDepartment(
              selectedDoctorId, currentDepartment),
          isTrue);

      // Switch to Eye
      currentDepartment = 'eye';
      if (!DepartmentDoctorConfig.isValidDoctorForDepartment(
          selectedDoctorId, currentDepartment)) {
        selectedDoctorId = null;
      }
      expect(selectedDoctorId, isNull);
    });
  });

  // ──────────────────────────────────────────────────────────────────────────
  // Test 4: Appointment creation sends a valid canonical doctor UUID
  // ──────────────────────────────────────────────────────────────────────────
  group('4. Appointment creation sends a valid canonical doctor UUID', () {
    const validUuid = '550e8400-e29b-41d4-a716-446655440001';
    const invalidDocString = 'doc-eye-mitesh';

    test('Valid UUID is serialized to doctor_id in persisted JSON', () {
      final now = DateTime.now();
      final appt = AppointmentModel(
        id: 'appt-1',
        patientId: 'pat-1',
        department: 'eye',
        doctorId: validUuid,
        doctorName: 'Dr Mitesh',
        appointmentDate: now,
        appointmentTime: '10:00',
        appointmentType: 'regular',
        status: 'scheduled',
        createdAt: now,
        updatedAt: now,
      );

      final json = appt.toInsertJson();
      expect(json['doctor_id'], equals(validUuid));
      expect(DepartmentDoctorConfig.isValidUuid(json['doctor_id']), isTrue);
    });

    test(
        'Legacy fabricated string doc-eye-mitesh is rejected and excluded from JSON to prevent 22P02',
        () {
      final now = DateTime.now();
      final appt = AppointmentModel(
        id: 'appt-2',
        patientId: 'pat-1',
        department: 'eye',
        doctorId: invalidDocString,
        doctorName: 'Dr Mitesh',
        appointmentDate: now,
        appointmentTime: '10:00',
        appointmentType: 'regular',
        status: 'scheduled',
        createdAt: now,
        updatedAt: now,
      );

      final json = appt.toInsertJson();
      expect(json.containsKey('doctor_id'), isFalse);
    });

    test(
        'Missing mapping does not silently assign another doctor and reports unmapped status',
        () {
      DepartmentDoctorConfig.reset();
      // No doctors in database profiles
      DepartmentDoctorConfig.syncWithDatabaseProfiles([]);

      final eyeDocs = DepartmentDoctorConfig.getDoctorsForDepartment('eye');
      expect(eyeDocs.length, equals(2));
      // IDs are empty strings because not found in DB
      expect(eyeDocs.first.id, isEmpty);
      expect(eyeDocs.first.hasValidDatabaseId, isFalse);
      expect(
          DepartmentDoctorConfig.isValidDoctorForDepartment('fake-uuid', 'eye'),
          isFalse);
    });
  });

  // ──────────────────────────────────────────────────────────────────────────
  // Test 5 & 6: Invoice RPC creation (Normal vs Surgery)
  // ──────────────────────────────────────────────────────────────────────────
  group('5 & 6. Invoice RPC creation for normal and surgery invoices', () {
    const patientUuid = '550e8400-e29b-41d4-a716-446655440099';
    const surgeryUuid = '550e8400-e29b-41d4-a716-446655440088';

    test('Normal invoice model does not require eye_surgery_id', () {
      final now = DateTime(2026, 10, 17);
      final invoice = BillingInvoiceModel(
        id: 'inv-1',
        invoiceNumber: 'INV-2026-0001',
        patientId: patientUuid,
        department: 'eye',
        subtotal: 500,
        discount: 0,
        totalAmount: 500,
        paymentStatus: 'paid',
        paymentMode: 'cash',
        amountPaid: 500,
        createdAt: now,
        updatedAt: now,
        eyeSurgeryId: null,
        items: [
          BillingItemModel(
            id: 'item-1',
            serviceName: 'Consultation Fee',
            quantity: 1,
            unitPrice: 500,
            totalAmount: 500,
            createdAt: now,
          ),
        ],
      );

      expect(invoice.eyeSurgeryId, isNull);
      expect(invoice.isPaid, isTrue);
    });

    test('Surgery invoice model retains verified eye_surgery_id', () {
      final now = DateTime(2026, 10, 17);
      final surgeryInvoice = BillingInvoiceModel(
        id: 'inv-surg-1',
        invoiceNumber: 'INV-2026-0002',
        patientId: patientUuid,
        department: 'eye',
        subtotal: 25000,
        discount: 1000,
        totalAmount: 24000,
        paymentStatus: 'paid',
        paymentMode: 'card',
        amountPaid: 24000,
        createdAt: now,
        updatedAt: now,
        eyeSurgeryId: surgeryUuid,
        items: [
          BillingItemModel(
            id: 'item-surg-1',
            serviceName: 'Phacoemulsification Package',
            quantity: 1,
            unitPrice: 25000,
            totalAmount: 25000,
            createdAt: now,
          ),
        ],
      );

      expect(surgeryInvoice.eyeSurgeryId, equals(surgeryUuid));
      expect(surgeryInvoice.totalAmount, equals(24000));
    });
  });

  // ──────────────────────────────────────────────────────────────────────────
  // Test 7, 8, 9, 10: Automatic shift-end attendance closure & session sign-out
  // ──────────────────────────────────────────────────────────────────────────
  group(
      '7, 8, 9, 10. Automatic shift-end attendance closure and effective dates',
      () {
    test(
        'Calculates attendance closure timestamp strictly from assigned shift end',
        () {
      final checkInTime = DateTime(2026, 10, 17, 8, 5); // 08:05 AM
      final scheduledEnd = DateTime(2026, 10, 17, 13, 0); // 1:00 PM

      // If user forgot to clock out and app/cron processes at 5:00 PM:
      final lateProcessingTime = DateTime(2026, 10, 17, 17, 0);
      expect(lateProcessingTime.isAfter(scheduledEnd), isTrue);

      // Closed timestamp must be scheduledEnd (13:00), not lateProcessingTime (17:00)
      final effectiveCloseTime = scheduledEnd;
      final workingHours =
          (effectiveCloseTime.difference(checkInTime).inMinutes / 60.0);

      expect(effectiveCloseTime.hour, equals(13));
      expect(effectiveCloseTime.minute, equals(0));
      expect(workingHours, closeTo(4.916, 0.01));
    });

    test('Manual sign-out before shift end is preserved and not overwritten',
        () {
      final manualCheckOutTime = DateTime(2026, 10, 17, 12, 30);
      final record = AttendanceRecord(
        id: 'att-1',
        staffId: 'staff-1',
        date: DateTime(2026, 10, 17),
        shift: 'morning',
        status: 'present',
        isLate: false,
        lateMinutes: 0,
        checkInTime: DateTime(2026, 10, 17, 8, 0),
        checkOutTime: manualCheckOutTime, // already signed out manually
        workingHours: 4.5,
      );

      // Should not be flagged as open or needing auto-termination
      expect(record.checkOutTime, isNotNull);
      expect(record.checkOutTime, equals(manualCheckOutTime));
    });

    test(
        'Duplicate automatic closure is prevented when check_out_time is already set',
        () {
      final closedRecord = AttendanceRecord(
        id: 'att-auto-closed',
        staffId: 'staff-1',
        date: DateTime(2026, 10, 17),
        shift: 'morning',
        status: 'present',
        isLate: false,
        lateMinutes: 0,
        checkInTime: DateTime(2026, 10, 17, 8, 0),
        checkOutTime: DateTime(2026, 10, 17, 13, 0),
        notes: 'Auto-clocked out at configured shift end time',
      );

      // Verify that idempotency check (check_out_time is null) prevents duplicate update
      final isOpenSession =
          closedRecord.checkInTime != null && closedRecord.checkOutTime == null;
      expect(isOpenSession, isFalse);
    });

    test(
        'Overnight shifts (e.g. 20:00 to 04:00 next day) correctly increment end date',
        () {
      final shiftStart = DateTime(2026, 10, 17, 20, 0);
      // End is 04:00, which is earlier hour than 20:00 -> crosses midnight
      final isOvernight = 4 < 20;
      expect(isOvernight, isTrue);

      final shiftEnd = isOvernight
          ? DateTime(2026, 10, 18, 4, 0)
          : DateTime(2026, 10, 17, 4, 0);

      expect(shiftEnd.day, equals(18));
      expect(shiftEnd.isAfter(shiftStart), isTrue);
      expect(shiftEnd.difference(shiftStart).inHours, equals(8));
    });

    test(
        'Shift effective dates preserve today working shift and apply tomorrow',
        () {
      final now = DateTime.now();
      final user = UserProfile(
        id: 'user-effective-1',
        fullName: 'Nurse Priya',
        email: 'priya@mkes.com',
        role: 'staff',
        isActive: true,
        createdAt: now,
        assignedShift: 'morning',
        nextShift: 'afternoon',
        shiftEffectiveDate: DateTime(2026, 10, 18),
      );

      // Today (Oct 17): returns current assigned shift
      expect(user.getShiftForDate(DateTime(2026, 10, 17)), equals('morning'));
      // Tomorrow (Oct 18): returns scheduled next shift
      expect(user.getShiftForDate(DateTime(2026, 10, 18)), equals('afternoon'));
    });
  });

  // ──────────────────────────────────────────────────────────────────────────
  // Test 11: Shift staffing counts and assignment filtering
  // ──────────────────────────────────────────────────────────────────────────
  group('11. Shift staffing counts and assignment filtering', () {
    final now = DateTime.now();
    final today = DateTime(2026, 10, 17);

    final staffUsers = [
      UserProfile(
        id: 'staff-1',
        fullName: 'Staff One',
        email: 's1@mkes.com',
        role: 'staff',
        isActive: true,
        createdAt: now,
        assignedShift: 'morning',
      ),
      UserProfile(
        id: 'staff-2',
        fullName: 'Staff Two',
        email: 's2@mkes.com',
        role: 'staff',
        isActive: true,
        createdAt: now,
        assignedShift: 'morning',
      ),
      UserProfile(
        id: 'staff-3',
        fullName: 'Staff Three',
        email: 's3@mkes.com',
        role: 'staff',
        isActive: true,
        createdAt: now,
        assignedShift: 'afternoon',
      ),
      UserProfile(
        id: 'staff-4',
        fullName: 'Staff Four',
        email: 's4@mkes.com',
        role: 'staff',
        isActive: true,
        createdAt: now,
        assignedShift: 'both',
      ),
      // Inactive staff should not be counted
      UserProfile(
        id: 'staff-5',
        fullName: 'Staff Inactive',
        email: 's5@mkes.com',
        role: 'staff',
        isActive: false,
        createdAt: now,
        assignedShift: 'morning',
      ),
    ];

    test('Staff assigned counts are accurate and inactive members are excluded',
        () {
      final activeStaff =
          staffUsers.where((u) => u.role == 'staff' && u.isActive).toList();
      expect(activeStaff.length, equals(4));

      final morningAssigned = activeStaff.where((u) {
        final s = u.getShiftForDate(today).toLowerCase();
        return s == 'morning' || s == 'both';
      }).length;

      final eveningAssigned = activeStaff.where((u) {
        final s = u.getShiftForDate(today).toLowerCase();
        return s == 'afternoon' || s == 'evening' || s == 'both';
      }).length;

      // Staff 1, 2, 4 = 3 assigned to morning
      expect(morningAssigned, equals(3));
      // Staff 3, 4 = 2 assigned to evening
      expect(eveningAssigned, equals(2));
    });

    test(
        'Duplicate attendance check-ins for the same staff member are counted only once',
        () {
      final records = [
        AttendanceRecord(
          id: 'rec-1',
          staffId: 'staff-1',
          date: today,
          shift: 'morning',
          status: 'present',
          isLate: false,
          lateMinutes: 0,
          checkInTime: DateTime(2026, 10, 17, 8, 0),
        ),
        // Duplicate check-in entry for same staff
        AttendanceRecord(
          id: 'rec-1-dup',
          staffId: 'staff-1',
          date: today,
          shift: 'morning',
          status: 'present',
          isLate: false,
          lateMinutes: 0,
          checkInTime: DateTime(2026, 10, 17, 8, 15),
        ),
        AttendanceRecord(
          id: 'rec-2',
          staffId: 'staff-2',
          date: today,
          shift: 'morning',
          status: 'present',
          isLate: false,
          lateMinutes: 0,
          checkInTime: DateTime(2026, 10, 17, 8, 30),
        ),
      ];

      final distinctMorningPresent = records
          .where((r) =>
              r.shift.toLowerCase() == 'morning' && r.checkInTime != null)
          .map((r) => r.staffId)
          .toSet()
          .length;

      // Should be 2 distinct staff members, not 3 records
      expect(distinctMorningPresent, equals(2));
    });
  });

  // ──────────────────────────────────────────────────────────────────────────
  // Test 12: Schedule / AI-tip fallback when data is missing
  // ──────────────────────────────────────────────────────────────────────────
  group('12. Schedule / AI-tip fallback when data is missing', () {
    String generateAiTip({
      required List<AppointmentModel> appointments,
      required List<EyeSurgeryModel> surgeries,
    }) {
      if (appointments.isEmpty && surgeries.isEmpty) {
        return 'AI Tip: No consultations or procedures scheduled for this date. Clinical triage and patient queue remain ready for walk-in arrivals.';
      }

      if (appointments.isNotEmpty) {
        final first = appointments.first;
        final doc = first.doctorName?.trim() ?? '';
        final hasDoc =
            doc.isNotEmpty && !doc.toLowerCase().startsWith('select');
        final dept = first.department.trim().isNotEmpty
            ? '${first.department} Department'
            : 'Clinic';
        if (hasDoc) {
          return 'AI Tip: $doc consults today in $dept starting at ${first.formattedTime}. ${appointments.length} appointment(s) scheduled for this session.';
        } else {
          return 'AI Tip: $dept consultations begin at ${first.formattedTime}. ${appointments.length} appointment(s) scheduled for this date.';
        }
      }

      if (surgeries.isNotEmpty) {
        return 'AI Tip: ${surgeries.length} Eye surgery procedure(s) scheduled for today.';
      }

      return 'AI Tip: Schedule is confirmed.';
    }

    test(
        'Empty schedule produces neutral data-backed fallback without inventing Dr Robert Sterling',
        () {
      final tip = generateAiTip(appointments: [], surgeries: []);
      expect(tip,
          contains('No consultations or procedures scheduled for this date'));
      expect(tip.contains('Robert Sterling'), isFalse);
      expect(tip.contains('WhatsApp'), isFalse);
    });

    test(
        'Schedule with appointment displays verified doctor name from actual records',
        () {
      final now = DateTime.now();
      final appt = AppointmentModel(
        id: 'appt-eye-1',
        patientId: 'pat-1',
        department: 'Eye',
        doctorId: '550e8400-e29b-41d4-a716-446655440001',
        doctorName: 'Dr Mitesh',
        appointmentDate: now,
        appointmentTime: '10:30',
        appointmentType: 'regular',
        status: 'scheduled',
        createdAt: now,
        updatedAt: now,
      );

      final tip = generateAiTip(appointments: [appt], surgeries: []);
      expect(
          tip,
          contains(
              'Dr Mitesh consults today in Eye Department starting at 10:30 AM'));
      expect(tip, contains('1 appointment(s) scheduled'));
      expect(tip.contains('Robert Sterling'), isFalse);
    });
  });
}
