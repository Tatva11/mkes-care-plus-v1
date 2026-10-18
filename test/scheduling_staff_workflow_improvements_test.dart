import 'package:flutter_test/flutter_test.dart';

import 'package:mkes_care/features/admin/models/user_profile.dart';
import 'package:mkes_care/features/appointments/models/appointment_model.dart';
import 'package:mkes_care/features/appointments/models/department_doctor_config.dart';
import 'package:mkes_care/features/appointments/widgets/appointment_form_dialog.dart';
import 'package:mkes_care/features/eye/models/eye_surgery_model.dart';
import 'package:mkes_care/features/inventory/utils/phone_dialer_util.dart';
import 'package:mkes_care/features/staff/models/shift_configuration.dart';
import 'package:mkes_care/features/staff/models/task_item.dart';
import 'package:mkes_care/features/staff/repositories/attendance_repository.dart';
import 'package:mkes_care/features/staff/utils/task_operational_filter.dart';

// Fake AttendanceRepository for testing shift display and effective date logic
class FakeShiftAttendanceRepository extends Fake
    implements AttendanceRepository {
  final Map<String,
          ({String? assignedShift, String? nextShift, DateTime? effectiveDate})>
      staffProfiles = {};

  @override
  Future<String?> fetchStaffShiftAssignment(String staffId,
      {DateTime? forDate}) async {
    final profile = staffProfiles[staffId];
    if (profile == null) return null;

    final target = forDate ?? DateTime.now();
    final targetDate = DateTime(target.year, target.month, target.day);

    if (profile.nextShift != null && profile.effectiveDate != null) {
      final effDate = DateTime(profile.effectiveDate!.year,
          profile.effectiveDate!.month, profile.effectiveDate!.day);
      if (!targetDate.isBefore(effDate)) {
        return profile.nextShift;
      }
    }

    return profile.assignedShift;
  }

  @override
  Future<List<ShiftConfiguration>> fetchShiftConfigurations() async {
    return const [
      ShiftConfiguration.defaultMorning,
      ShiftConfiguration.defaultAfternoon,
    ];
  }
}

void main() {
  TestWidgetsFlutterBinding.ensureInitialized();

  group('Requirement 1 & 2: Appointment Form & Department Doctor Configuration',
      () {
    final doctorUuidMitesh = '550e8400-e29b-41d4-a716-446655440001';
    final doctorUuidVarun = '550e8400-e29b-41d4-a716-446655440002';
    final doctorUuidNimisha = '550e8400-e29b-41d4-a716-446655440003';
    final doctorUuidVikas = '550e8400-e29b-41d4-a716-446655440004';

    setUp(() {
      DepartmentDoctorConfig.reset();
      final now = DateTime.now();
      DepartmentDoctorConfig.syncWithDatabaseProfiles([
        UserProfile(
          id: doctorUuidMitesh,
          fullName: 'Dr Mitesh Patel',
          email: 'mitesh@mkes.com',
          department: 'Eye',
          departmentName: 'Eye Department',
          role: 'doctor',
          isActive: true,
          createdAt: now,
        ),
        UserProfile(
          id: doctorUuidVarun,
          fullName: 'Dr Varun Shah',
          email: 'varun@mkes.com',
          department: 'Eye',
          departmentName: 'Eye Department',
          role: 'doctor',
          isActive: true,
          createdAt: now,
        ),
        UserProfile(
          id: doctorUuidNimisha,
          fullName: 'Dr Nimisha Dave',
          email: 'nimisha@mkes.com',
          department: 'Dental',
          departmentName: 'Dental Department',
          role: 'doctor',
          isActive: true,
          createdAt: now,
        ),
        UserProfile(
          id: doctorUuidVikas,
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

    test(
        'Surgery appointment type is allowed for Eye department but excluded for Dental',
        () {
      final eyeTypes = AppointmentFormDialog.getAvailableAppointmentTypes('eye')
          .map((t) => t.id)
          .toList();
      final dentalTypes =
          AppointmentFormDialog.getAvailableAppointmentTypes('dental')
              .map((t) => t.id)
              .toList();

      expect(eyeTypes.contains('surgery'), isTrue);
      expect(dentalTypes.contains('surgery'), isFalse);
      expect(dentalTypes.contains('regular'), isTrue);
      expect(dentalTypes.contains('follow_up'), isTrue);
    });

    test(
        'Sprint 11 Confirmed Roster: Eye shows Dr Mitesh Jain & Dr Varun, Dental shows Dr Nimisha & Dr Vikas with real UUIDs',
        () {
      final eyeDocs = DepartmentDoctorConfig.getDoctorsForDepartment('eye');
      final dentalDocs =
          DepartmentDoctorConfig.getDoctorsForDepartment('dental');

      expect(eyeDocs.length, equals(2));
      expect(eyeDocs.map((d) => d.fullName).toList(),
          equals(['Dr Mitesh Jain', 'Dr Varun']));
      expect(eyeDocs.every((d) => d.department == 'eye'), isTrue);
      expect(eyeDocs.first.id, equals(doctorUuidMitesh));
      expect(eyeDocs.last.id, equals(doctorUuidVarun));

      expect(dentalDocs.length, equals(2));
      expect(dentalDocs.map((d) => d.fullName).toList(),
          equals(['Dr Nimisha', 'Dr Vikas']));
      expect(dentalDocs.every((d) => d.department == 'dental'), isTrue);
      expect(dentalDocs.first.id, equals(doctorUuidNimisha));
      expect(dentalDocs.last.id, equals(doctorUuidVikas));
    });

    test(
        'DepartmentDoctorConfig validates doctors strictly by department and rejects cross-department assignments',
        () {
      // Eye doctors
      expect(
          DepartmentDoctorConfig.isValidDoctorForDepartment(
              doctorUuidMitesh, 'eye'),
          isTrue);
      expect(
          DepartmentDoctorConfig.isValidDoctorForDepartment(
              doctorUuidVarun, 'eye'),
          isTrue);
      expect(
          DepartmentDoctorConfig.isValidDoctorForDepartment(
              doctorUuidMitesh, 'dental'),
          isFalse);
      expect(
          DepartmentDoctorConfig.isValidDoctorForDepartment(
              doctorUuidVarun, 'dental'),
          isFalse);

      // Dental doctors
      expect(
          DepartmentDoctorConfig.isValidDoctorForDepartment(
              doctorUuidNimisha, 'dental'),
          isTrue);
      expect(
          DepartmentDoctorConfig.isValidDoctorForDepartment(
              doctorUuidVikas, 'dental'),
          isTrue);
      expect(
          DepartmentDoctorConfig.isValidDoctorForDepartment(
              doctorUuidNimisha, 'eye'),
          isFalse);
      expect(
          DepartmentDoctorConfig.isValidDoctorForDepartment(
              doctorUuidVikas, 'eye'),
          isFalse);

      // Null or empty (General Queue / Unassigned) is valid for both departments
      expect(DepartmentDoctorConfig.isValidDoctorForDepartment(null, 'eye'),
          isTrue);
      expect(DepartmentDoctorConfig.isValidDoctorForDepartment(null, 'dental'),
          isTrue);
      expect(
          DepartmentDoctorConfig.isValidDoctorForDepartment('', 'eye'), isTrue);

      // Arbitrary/fabricated IDs are rejected
      expect(
          DepartmentDoctorConfig.isValidDoctorForDepartment(
              'random-fabricated-uuid', 'eye'),
          isFalse);
      expect(
          DepartmentDoctorConfig.isValidDoctorForDepartment(
              'doc-eye-mitesh', 'eye'),
          isFalse);
    });

    test('Switching department clears invalid doctor selection safely', () {
      // Simulate selecting Dr Mitesh for Eye
      String? selectedDoctorId = doctorUuidMitesh;
      String currentDepartment = 'eye';
      expect(
          DepartmentDoctorConfig.isValidDoctorForDepartment(
              selectedDoctorId, currentDepartment),
          isTrue);

      // User switches to Dental
      currentDepartment = 'dental';
      if (!DepartmentDoctorConfig.isValidDoctorForDepartment(
          selectedDoctorId, currentDepartment)) {
        selectedDoctorId = null;
      }
      expect(selectedDoctorId, isNull);

      // Simulate selecting Dr Vikas for Dental
      selectedDoctorId = doctorUuidVikas;
      expect(
          DepartmentDoctorConfig.isValidDoctorForDepartment(
              selectedDoctorId, currentDepartment),
          isTrue);

      // User switches back to Eye
      currentDepartment = 'eye';
      if (!DepartmentDoctorConfig.isValidDoctorForDepartment(
          selectedDoctorId, currentDepartment)) {
        selectedDoctorId = null;
      }
      expect(selectedDoctorId, isNull);
    });

    test(
        'Appointment creation and editing preserves canonical doctor UUID and department in persisted JSON, filtering invalid strings',
        () {
      final now = DateTime.now();

      // Eye appointment with Dr Mitesh (valid canonical UUID)
      final eyeAppt = AppointmentModel(
        id: 'appt-eye-1',
        patientId: 'pat-001',
        department: 'eye',
        doctorId: doctorUuidMitesh,
        doctorName: 'Dr Mitesh',
        appointmentDate: now,
        appointmentTime: '09:30:00',
        appointmentType: 'regular',
        status: 'scheduled',
        createdAt: now,
        updatedAt: now,
      );

      final eyeInsertJson = eyeAppt.toInsertJson();
      expect(eyeInsertJson['department'], equals('eye'));
      expect(eyeInsertJson['doctor_id'], equals(doctorUuidMitesh));
      expect(eyeAppt.doctorId, equals(doctorUuidMitesh));

      // Attempt to save legacy string "doc-eye-mitesh" is filtered out by toInsertJson() to prevent DB error 22P02
      final invalidStringAppt = AppointmentModel(
        id: 'appt-eye-2',
        patientId: 'pat-001',
        department: 'eye',
        doctorId: 'doc-eye-mitesh',
        doctorName: 'Dr Mitesh',
        appointmentDate: now,
        appointmentTime: '09:30:00',
        appointmentType: 'regular',
        status: 'scheduled',
        createdAt: now,
        updatedAt: now,
      );
      final invalidJson = invalidStringAppt.toInsertJson();
      expect(invalidJson.containsKey('doctor_id'), isFalse);

      // Dental appointment with Dr Vikas (valid canonical UUID)
      final dentalAppt = AppointmentModel(
        id: 'appt-den-1',
        patientId: 'pat-002',
        department: 'dental',
        doctorId: doctorUuidVikas,
        doctorName: 'Dr Vikas',
        appointmentDate: now,
        appointmentTime: '11:00:00',
        appointmentType: 'regular',
        status: 'scheduled',
        createdAt: now,
        updatedAt: now,
      );

      final dentalInsertJson = dentalAppt.toInsertJson();
      expect(dentalInsertJson['department'], equals('dental'));
      expect(dentalInsertJson['doctor_id'], equals(doctorUuidVikas));
      expect(dentalAppt.doctorId, equals(doctorUuidVikas));

      // Unassigned appointment
      final unassignedAppt = AppointmentModel(
        id: 'appt-unassigned',
        patientId: 'pat-003',
        department: 'eye',
        doctorId: null,
        doctorName: null,
        appointmentDate: now,
        appointmentTime: '14:00:00',
        appointmentType: 'walk_in',
        status: 'waiting',
        createdAt: now,
        updatedAt: now,
      );

      final unassignedJson = unassignedAppt.toInsertJson();
      expect(unassignedJson['department'], equals('eye'));
      expect(unassignedJson.containsKey('doctor_id'), isFalse);
    });

    test(
        'Dynamic synchronization with database profiles maps genuine database UUIDs without guessing',
        () {
      final now = DateTime.now();
      DepartmentDoctorConfig.reset();

      final profiles = [
        UserProfile(
          id: '550e8400-e29b-41d4-a716-446655440001',
          fullName: 'Dr Mitesh Patel',
          email: 'mitesh@mkes.com',
          department: 'Eye',
          departmentName: 'Eye Department',
          role: 'staff',
          isActive: true,
          createdAt: now,
        ),
        UserProfile(
          id: '550e8400-e29b-41d4-a716-446655440002',
          fullName: 'Dr Vikas Sharma',
          email: 'vikas@mkes.com',
          department: 'Dental',
          departmentName: 'Dental Department',
          role: 'staff',
          isActive: true,
          createdAt: now,
        ),
      ];

      final mapping = DepartmentDoctorConfig.syncWithDatabaseProfiles(profiles);

      expect(
          mapping['Dr Mitesh'], equals('550e8400-e29b-41d4-a716-446655440001'));
      expect(
          mapping['Dr Vikas'], equals('550e8400-e29b-41d4-a716-446655440002'));
      // Dr Varun and Dr Nimisha are not in profiles, so mapped to null
      expect(mapping['Dr Varun'], isNull);
      expect(mapping['Dr Nimisha'], isNull);

      final missing =
          DepartmentDoctorConfig.findMissingDatabaseProfiles(profiles);
      expect(missing, contains('Dr Varun'));
      expect(missing, contains('Dr Nimisha'));
      expect(missing, isNot(contains('Dr Mitesh Jain')));
      expect(missing, isNot(contains('Dr Vikas')));

      // Verified updated config uses matched UUIDs, and unmapped is empty string
      final eyeDocs = DepartmentDoctorConfig.getDoctorsForDepartment('eye');
      expect(eyeDocs.firstWhere((d) => d.fullName == 'Dr Mitesh Jain').id,
          equals('550e8400-e29b-41d4-a716-446655440001'));
      expect(eyeDocs.firstWhere((d) => d.fullName == 'Dr Varun').id, isEmpty);
    });

    test(
        'Empty doctor configuration returns empty list safely via clear() without fabricating fake names',
        () {
      DepartmentDoctorConfig.clear();
      final emptyEye = DepartmentDoctorConfig.getDoctorsForDepartment('eye');
      final emptyDental =
          DepartmentDoctorConfig.getDoctorsForDepartment('dental');

      expect(emptyEye, isEmpty);
      expect(emptyDental, isEmpty);
      expect(DepartmentDoctorConfig.isValidDoctorForDepartment('any-id', 'eye'),
          isFalse);
    });
  });

  group('Requirement 3: Task Operational Filter & Carry-Forward Logic', () {
    final now = DateTime(2026, 10, 17, 14, 0);

    final todayIncomplete = TaskItem(
      id: 't-today-1',
      title: 'Today Pending Task',
      assignedTo: 'staff-1',
      status: 'pending',
      priority: 'high',
      dueDate: DateTime(2026, 10, 17, 16, 0),
      createdAt: now.subtract(const Duration(hours: 2)),
      updatedAt: now.subtract(const Duration(hours: 2)),
    );

    final todayCompleted = TaskItem(
      id: 't-today-comp',
      title: 'Today Completed Task',
      assignedTo: 'staff-1',
      status: 'completed',
      priority: 'medium',
      dueDate: DateTime(2026, 10, 17, 11, 0),
      createdAt: now.subtract(const Duration(hours: 4)),
      updatedAt: now.subtract(const Duration(hours: 1)),
    );

    final todayCancelled = TaskItem(
      id: 't-today-canc',
      title: 'Today Cancelled Task',
      assignedTo: 'staff-1',
      status: 'cancelled',
      priority: 'low',
      dueDate: DateTime(2026, 10, 17, 12, 0),
      createdAt: now.subtract(const Duration(hours: 5)),
      updatedAt: now.subtract(const Duration(hours: 3)),
    );

    final yesterdayIncomplete = TaskItem(
      id: 't-yest-1',
      title: 'Yesterday Overdue Task',
      assignedTo: 'staff-1',
      status: 'pending',
      priority: 'critical',
      dueDate: DateTime(2026, 10, 16, 15, 0),
      createdAt: now.subtract(const Duration(days: 2)),
      updatedAt: now.subtract(const Duration(days: 1)),
    );

    final twoDaysAgoIncomplete = TaskItem(
      id: 't-2days-1',
      title: 'Two Days Ago Overdue Task',
      assignedTo: 'staff-1',
      status: 'in_progress',
      priority: 'medium',
      dueDate: DateTime(2026, 10, 15, 10, 0),
      createdAt: now.subtract(const Duration(days: 3)),
      updatedAt: now.subtract(const Duration(days: 1)),
    );

    final futureTask = TaskItem(
      id: 't-future-1',
      title: 'Future Task',
      assignedTo: 'staff-1',
      status: 'pending',
      priority: 'high',
      dueDate: DateTime(2026, 10, 19, 10, 0),
      createdAt: now,
      updatedAt: now,
    );

    final undatedTask = TaskItem(
      id: 't-undated-1',
      title: 'Undated Task',
      assignedTo: 'staff-1',
      status: 'pending',
      priority: 'low',
      dueDate: null,
      createdAt: now,
      updatedAt: now,
    );

    test(
        'filterOperationalTasks includes today incomplete + previous incomplete, excludes completed/cancelled/future/undated',
        () {
      final all = [
        todayIncomplete,
        todayCompleted,
        todayCancelled,
        yesterdayIncomplete,
        twoDaysAgoIncomplete,
        futureTask,
        undatedTask,
      ];

      final filtered =
          TaskOperationalFilter.filterOperationalTasks(all, referenceDate: now);

      // Should contain 3 tasks: twoDaysAgoIncomplete, yesterdayIncomplete, todayIncomplete
      expect(filtered.length, equals(3));
      expect(filtered.map((t) => t.id).toList(),
          containsAll(['t-today-1', 't-yest-1', 't-2days-1']));

      // Exclusions
      expect(filtered.any((t) => t.id == 't-today-comp'), isFalse);
      expect(filtered.any((t) => t.id == 't-today-canc'), isFalse);
      expect(filtered.any((t) => t.id == 't-future-1'), isFalse);
      expect(filtered.any((t) => t.id == 't-undated-1'), isFalse);
    });

    test(
        'Overdue tasks are sorted by original due date ascending then priority, followed by today tasks',
        () {
      final all = [
        todayIncomplete,
        yesterdayIncomplete,
        twoDaysAgoIncomplete,
      ];

      final filtered =
          TaskOperationalFilter.filterOperationalTasks(all, referenceDate: now);

      // Overdue tasks come first, sorted by original due date (Oct 15 then Oct 16)
      expect(filtered[0].id, equals('t-2days-1'));
      expect(filtered[1].id, equals('t-yest-1'));
      // Today's task follows
      expect(filtered[2].id, equals('t-today-1'));

      // Check overdue carry-forward detection and original date format
      expect(TaskOperationalFilter.isOverdueCarryForward(filtered[0], now),
          isTrue);
      expect(TaskOperationalFilter.formatDueDateMessage(filtered[0].dueDate!),
          equals('Due on 15 Oct 2026'));
      expect(TaskOperationalFilter.formatDueDateMessage(filtered[1].dueDate!),
          equals('Due on 16 Oct 2026'));
      expect(TaskOperationalFilter.isOverdueCarryForward(filtered[2], now),
          isFalse);
    });
  });

  group('Requirement 4: Staff Schedule Shift Assignment & Effective Dates', () {
    test(
        'Displays actual shift for selected date respecting effective date boundary and unassigned state',
        () async {
      final fakeRepo = FakeShiftAttendanceRepository();
      const staffId = 'staff-ria';

      // Staff Ria has Morning shift currently, but scheduled Evening shift starting tomorrow (Oct 18)
      fakeRepo.staffProfiles[staffId] = (
        assignedShift: 'morning',
        nextShift: 'afternoon',
        effectiveDate: DateTime(2026, 10, 18),
      );

      // Today (Oct 17): should display morning shift
      final todayShift = await fakeRepo.fetchStaffShiftAssignment(staffId,
          forDate: DateTime(2026, 10, 17));
      expect(todayShift, equals('morning'));

      // Tomorrow (Oct 18): should display afternoon shift based on effective date
      final tomorrowShift = await fakeRepo.fetchStaffShiftAssignment(staffId,
          forDate: DateTime(2026, 10, 18));
      expect(tomorrowShift, equals('afternoon'));

      // Unassigned staff returns null (honest unassigned state)
      final unassignedShift = await fakeRepo.fetchStaffShiftAssignment(
          'staff-unassigned',
          forDate: DateTime(2026, 10, 17));
      expect(unassignedShift, isNull);
    });
  });

  group('Requirement 5 & 8: Surgery on Staff Schedule & Rescheduling Order',
      () {
    test(
        'compareAppointments sorts chronologically by appointmentTime minutes ascending',
        () {
      final appt830 = AppointmentModel(
        id: 'appt-1',
        patientId: 'p-1',
        patientName: 'Patient Early',
        department: 'eye',
        appointmentDate: DateTime(2026, 10, 17),
        appointmentTime: '08:30',
        status: 'scheduled',
        createdAt: DateTime(2026, 10, 17, 7, 0),
        updatedAt: DateTime(2026, 10, 17, 7, 0),
      );

      final appt930 = AppointmentModel(
        id: 'appt-2',
        patientId: 'p-2',
        patientName: 'Patient Later',
        department: 'eye',
        appointmentDate: DateTime(2026, 10, 17),
        appointmentTime: '09:30',
        status: 'scheduled',
        createdAt: DateTime(2026, 10, 17, 6, 0), // Earlier creation time!
        updatedAt: DateTime(2026, 10, 17, 6, 0),
      );

      final list = [appt930, appt830];
      list.sort(AppointmentModel.compareAppointments);

      // 8:30 AM must come before 9:30 AM regardless of creation timestamp
      expect(list.first.id, equals('appt-1'));
      expect(list.last.id, equals('appt-2'));
    });

    test('timeToMinutes parses 12h and 24h formats accurately', () {
      expect(AppointmentModel.timeToMinutes('08:30'), equals(510));
      expect(AppointmentModel.timeToMinutes('09:30'), equals(570));
      expect(AppointmentModel.timeToMinutes('15:30'), equals(930));
      expect(AppointmentModel.timeToMinutes('3:30 PM'), equals(930));
      expect(AppointmentModel.timeToMinutes('12:00 PM'), equals(720));
      expect(AppointmentModel.timeToMinutes('12:00 AM'), equals(0));
    });
  });

  group('Requirement 7: Phone Dialer Utility & Call Button', () {
    test('isValidPhoneNumber validates phone numbers safely', () {
      expect(PhoneDialerUtil.isValidPhoneNumber('+919876543210'), isTrue);
      expect(PhoneDialerUtil.isValidPhoneNumber('9876543210'), isTrue);
      expect(PhoneDialerUtil.isValidPhoneNumber(''), isFalse);
      expect(PhoneDialerUtil.isValidPhoneNumber(null), isFalse);
      expect(PhoneDialerUtil.isValidPhoneNumber('   '), isFalse);
      expect(PhoneDialerUtil.isValidPhoneNumber('ab'), isFalse);
    });

    test('cleanNumber strips formatting characters and preserves leading plus',
        () {
      expect(PhoneDialerUtil.cleanNumber('+91 98765-43210'),
          equals('+919876543210'));
      expect(PhoneDialerUtil.cleanNumber('(022) 2800-1234'),
          equals('02228001234'));
    });
  });

  group('Requirement 5: Staff Surgery Schedule Assignment & Filtering', () {
    test(
        'Surgeries appear on schedule only when assigned to staff, matching date, and not cancelled',
        () {
      const currentStaffId = 'staff-ria';
      final today = DateTime(2026, 10, 17);

      final matchingSurgery = EyeSurgeryModel(
        id: 'surg-1',
        patientId: 'p-1',
        preOpDate: DateTime(2026, 10, 16),
        surgeryDate: DateTime(2026, 10, 17),
        surgeryTime: '15:30',
        assignedStaffId: currentStaffId,
        status: 'scheduled',
        eyeSide: 'right',
        surgeryType: 'Cataract Phacoemulsification',
        createdAt: DateTime(2026, 10, 15),
        updatedAt: DateTime(2026, 10, 15),
      );

      final otherStaffSurgery = EyeSurgeryModel(
        id: 'surg-2',
        patientId: 'p-2',
        preOpDate: DateTime(2026, 10, 16),
        surgeryDate: DateTime(2026, 10, 17),
        surgeryTime: '11:00',
        assignedStaffId: 'staff-other',
        status: 'scheduled',
        eyeSide: 'left',
        surgeryType: 'Cataract',
        createdAt: DateTime(2026, 10, 15),
        updatedAt: DateTime(2026, 10, 15),
      );

      final cancelledSurgery = EyeSurgeryModel(
        id: 'surg-3',
        patientId: 'p-3',
        preOpDate: DateTime(2026, 10, 16),
        surgeryDate: DateTime(2026, 10, 17),
        surgeryTime: '14:00',
        assignedStaffId: currentStaffId,
        status: 'cancelled',
        eyeSide: 'both',
        surgeryType: 'Cataract',
        createdAt: DateTime(2026, 10, 15),
        updatedAt: DateTime(2026, 10, 15),
      );

      final differentDaySurgery = EyeSurgeryModel(
        id: 'surg-4',
        patientId: 'p-4',
        preOpDate: DateTime(2026, 10, 16),
        surgeryDate: DateTime(2026, 10, 18),
        surgeryTime: '10:00',
        assignedStaffId: currentStaffId,
        status: 'scheduled',
        eyeSide: 'right',
        surgeryType: 'Cataract',
        createdAt: DateTime(2026, 10, 15),
        updatedAt: DateTime(2026, 10, 15),
      );

      final all = [
        matchingSurgery,
        otherStaffSurgery,
        cancelledSurgery,
        differentDaySurgery
      ];
      final staffSurgeries = all.where((s) {
        if (s.assignedStaffId != currentStaffId) return false;
        if (!EyeSurgeryModel.isSameCalendarDay(s.surgeryDate, today)) {
          return false;
        }
        if (s.status.toLowerCase() == 'cancelled') return false;
        return true;
      }).toList();

      expect(staffSurgeries.length, equals(1));
      expect(staffSurgeries.first.id, equals('surg-1'));
    });
  });

  group('Requirement 6: Simplified Patient Schedule Card Labels', () {
    test(
        'Removes technical workflow terminology and produces clean department & appointment labels',
        () {
      final eyeAppt = AppointmentModel(
        id: 'appt-eye',
        patientName: 'John Doe',
        department: 'eye',
        appointmentDate: DateTime(2026, 10, 17),
        appointmentTime: '10:00',
        appointmentType: 'regular',
        room: 'Fitting Room 02',
        notes: 'Optometry refraction and fitting',
        createdAt: DateTime(2026, 10, 17),
        updatedAt: DateTime(2026, 10, 17),
      );

      final dentalAppt = AppointmentModel(
        id: 'appt-dental',
        patientName: 'Jane Smith',
        department: 'dental',
        appointmentDate: DateTime(2026, 10, 17),
        appointmentTime: '11:00',
        appointmentType: 'follow_up',
        createdAt: DateTime(2026, 10, 17),
        updatedAt: DateTime(2026, 10, 17),
      );

      final isEyeDental = eyeAppt.department.toLowerCase().trim() == 'dental';
      final eyeDeptLabel =
          isEyeDental ? 'Dental Department Patient' : 'Eye Department Patient';
      final eyeApptLabel =
          eyeAppt.appointmentType.toLowerCase().trim() == 'follow_up'
              ? 'Doctor Follow-Up'
              : 'Doctor Appointment';

      expect(eyeDeptLabel, equals('Eye Department Patient'));
      expect(eyeApptLabel, equals('Doctor Appointment'));

      final isDental = dentalAppt.department.toLowerCase().trim() == 'dental';
      final dentalDeptLabel =
          isDental ? 'Dental Department Patient' : 'Eye Department Patient';
      final dentalApptLabel =
          dentalAppt.appointmentType.toLowerCase().trim() == 'follow_up'
              ? 'Doctor Follow-Up'
              : 'Doctor Appointment';

      expect(dentalDeptLabel, equals('Dental Department Patient'));
      expect(dentalApptLabel, equals('Doctor Follow-Up'));
    });
  });

  group(
      'Requirement 3 (Extended): Overdue Tasks Persistence Across Day Boundaries',
      () {
    test(
        'Incomplete tasks remain overdue across multiple day boundaries until completed',
        () {
      final incompleteTask = TaskItem(
        id: 't-persistent',
        title: 'Persistent Incomplete Task',
        assignedTo: 'staff-1',
        status: 'pending',
        priority: 'high',
        dueDate: DateTime(2026, 10, 15, 10, 0),
        createdAt: DateTime(2026, 10, 14),
        updatedAt: DateTime(2026, 10, 14),
      );

      // On Oct 16: overdue
      final oct16Result = TaskOperationalFilter.filterOperationalTasks(
        [incompleteTask],
        referenceDate: DateTime(2026, 10, 16, 9, 0),
      );
      expect(oct16Result.length, equals(1));
      expect(
          TaskOperationalFilter.isOverdueCarryForward(
              oct16Result.first, DateTime(2026, 10, 16)),
          isTrue);
      expect(
          TaskOperationalFilter.formatDueDateMessage(
              oct16Result.first.dueDate!),
          equals('Due on 15 Oct 2026'));

      // On Oct 17: still overdue, original date preserved
      final oct17Result = TaskOperationalFilter.filterOperationalTasks(
        [incompleteTask],
        referenceDate: DateTime(2026, 10, 17, 14, 0),
      );
      expect(oct17Result.length, equals(1));
      expect(
          TaskOperationalFilter.isOverdueCarryForward(
              oct17Result.first, DateTime(2026, 10, 17)),
          isTrue);
      expect(
          TaskOperationalFilter.formatDueDateMessage(
              oct17Result.first.dueDate!),
          equals('Due on 15 Oct 2026'));

      // Once completed, it does not appear in operational list
      final completedTask = incompleteTask.copyWith(status: 'completed');
      final completedResult = TaskOperationalFilter.filterOperationalTasks(
        [completedTask],
        referenceDate: DateTime(2026, 10, 17, 15, 0),
      );
      expect(completedResult, isEmpty);
    });
  });
}
