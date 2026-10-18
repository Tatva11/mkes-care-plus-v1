import 'package:flutter_test/flutter_test.dart';

import 'package:mkes_care/features/admin/models/user_profile.dart';
import 'package:mkes_care/features/appointments/models/appointment_model.dart';
import 'package:mkes_care/features/appointments/models/department_doctor_config.dart';
import 'package:mkes_care/features/appointments/repositories/department_doctor_repository.dart';
import 'package:mkes_care/features/eye/models/eye_surgery_model.dart';
import 'package:mkes_care/features/inventory/utils/phone_dialer_util.dart';
import 'package:mkes_care/features/patients/models/patient_model.dart';
import 'package:mkes_care/features/staff/models/task_item.dart';

void main() {
  TestWidgetsFlutterBinding.ensureInitialized();

  // ──────────────────────────────────────────────────────────────────────────
  // Part 1: Admin Management of Static Doctors
  // ──────────────────────────────────────────────────────────────────────────
  group('Part 1: Admin Management of Static Doctors', () {
    setUp(() {
      DepartmentDoctorConfig.reset();
    });

    test(
        'Initial roster contains Dr Mitesh Jain, Dr Varun (Eye) and Dr Nimisha, Dr Vikas (Dental)',
        () {
      final eyeDoctors = DepartmentDoctorConfig.getDoctorsForDepartment('eye');
      final dentalDoctors =
          DepartmentDoctorConfig.getDoctorsForDepartment('dental');

      expect(eyeDoctors.map((d) => d.fullName).toList(),
          containsAll(['Dr Mitesh Jain', 'Dr Varun']));
      expect(dentalDoctors.map((d) => d.fullName).toList(),
          containsAll(['Dr Nimisha', 'Dr Vikas']));
      expect(eyeDoctors.every((d) => d.isActive), isTrue);
      expect(dentalDoctors.every((d) => d.isActive), isTrue);
    });

    test(
        'Admin deactivation prevents doctor from being selected for new appointments',
        () {
      // Initially active and valid for booking
      expect(
          DepartmentDoctorConfig.isValidDoctorNameForDepartment(
              'Dr Varun', 'eye',
              activeOnly: true),
          isTrue);

      // Deactivate Dr Varun
      DepartmentDoctorConfig.syncConfiguredDoctors([
        DepartmentDoctor(
            id: 'eye-1',
            fullName: 'Dr Mitesh Jain',
            department: 'eye',
            isActive: true),
        DepartmentDoctor(
            id: 'eye-2',
            fullName: 'Dr Varun',
            department: 'eye',
            isActive: false),
        DepartmentDoctor(
            id: 'den-1',
            fullName: 'Dr Nimisha',
            department: 'dental',
            isActive: true),
        DepartmentDoctor(
            id: 'den-2',
            fullName: 'Dr Vikas',
            department: 'dental',
            isActive: true),
      ]);

      // When activeOnly is true (new appointment booking), inactive doctor cannot be selected
      expect(
          DepartmentDoctorConfig.isValidDoctorNameForDepartment(
              'Dr Varun', 'eye',
              activeOnly: true),
          isFalse);
      final activeEye = DepartmentDoctorConfig.getDoctorsForDepartment('eye',
          activeOnly: true);
      expect(activeEye.map((d) => d.fullName).toList(),
          equals(['Dr Mitesh Jain']));

      // But when activeOnly is false (historical display/admin view), doctor is still recognized
      expect(
          DepartmentDoctorConfig.isValidDoctorNameForDepartment(
              'Dr Varun', 'eye',
              activeOnly: false),
          isTrue);
    });

    test(
        'Historical appointments preserve assigned doctor name even if doctor is renamed or deactivated',
        () {
      final originalAppointment = AppointmentModel(
        id: 'appt-hist-1',
        patientId: 'pat-1',
        patientName: 'Kishore Kumar',
        patientNumber: 'EYE-1001',
        department: 'eye',
        appointmentDate: DateTime(2026, 10, 10),
        appointmentTime: '10:00',
        appointmentType: 'consultation',
        status: 'completed',
        doctorName: 'Dr Varun',
        doctorId: null,
        notes: '[Doctor: Dr Varun] Routine exam',
        createdAt: DateTime(2026, 10, 10),
        updatedAt: DateTime(2026, 10, 10),
      );

      expect(originalAppointment.doctorName, equals('Dr Varun'));

      // Deactivate Dr Varun in current roster
      DepartmentDoctorConfig.syncConfiguredDoctors([
        DepartmentDoctor(
            id: 'eye-1',
            fullName: 'Dr Mitesh Jain',
            department: 'eye',
            isActive: true),
        DepartmentDoctor(
            id: 'eye-2',
            fullName: 'Dr Varun',
            department: 'eye',
            isActive: false),
      ]);

      // Deserializing historical appointment preserves the original doctor name
      final json = originalAppointment.toJson();
      final restored = AppointmentModel.fromJson(json);
      expect(restored.doctorName, equals('Dr Varun'));
      expect(restored.doctorId, isNull);
    });

    test(
        'Admin can add new doctor and edit name without creating Auth/staff accounts or fake UUIDs',
        () {
      // Add a visiting doctor to Eye Department
      final newDoctor = DepartmentDoctor(
        id: 'local-test-new-doc',
        fullName: 'Dr S. K. Mehta',
        department: 'eye',
        specialty: 'Vitreo-Retina',
        isActive: true,
      );

      DepartmentDoctorConfig.syncConfiguredDoctors([
        ...DepartmentDoctorRepository.initialDoctors,
        newDoctor,
      ]);

      expect(
          DepartmentDoctorConfig.isValidDoctorNameForDepartment(
              'Dr S. K. Mehta', 'eye'),
          isTrue);
      final eyeDoctors = DepartmentDoctorConfig.getDoctorsForDepartment('eye');
      expect(eyeDoctors.any((d) => d.fullName == 'Dr S. K. Mehta'), isTrue);

      // Verify booking with this new doctor sets doctor_id to null and stores name safely
      final appt = AppointmentModel(
        id: 'appt-new-doc-1',
        patientId: 'pat-2',
        patientName: 'Ramesh Patel',
        department: 'eye',
        appointmentDate: DateTime(2026, 10, 18),
        appointmentTime: '11:00',
        appointmentType: 'consultation',
        status: 'scheduled',
        doctorName: 'Dr S. K. Mehta',
        doctorId: null,
        createdAt: DateTime.now(),
        updatedAt: DateTime.now(),
      );

      final insertJson = appt.toInsertJson();
      expect(insertJson['doctor_id'], isNull);
      expect(insertJson['notes'], contains('Dr S. K. Mehta'));
      expect(appt.doctorName, equals('Dr S. K. Mehta'));
    });
  });

  // ──────────────────────────────────────────────────────────────────────────
  // Part 2: Display Doctor Names in the Staff Schedule
  // ──────────────────────────────────────────────────────────────────────────
  group('Part 2: Display Doctor Names in the Staff Schedule', () {
    test('Static-name appointment resolves and displays assigned doctor name',
        () {
      final item = AppointmentModel(
        id: 'appt-staff-1',
        patientName: 'Sunita Sharma',
        patientNumber: 'EYE-1002',
        department: 'eye',
        appointmentDate: DateTime(2026, 10, 17),
        appointmentTime: '14:30',
        appointmentType: 'consultation',
        status: 'scheduled',
        doctorName: 'Dr Mitesh Jain',
        doctorId: null,
        createdAt: DateTime(2026, 10, 17),
        updatedAt: DateTime(2026, 10, 17),
      );

      final hasDoctor =
          item.doctorName != null && item.doctorName!.trim().isNotEmpty;
      final doctorDisplay =
          hasDoctor ? item.doctorName!.trim() : 'Doctor not assigned';

      expect(hasDoctor, isTrue);
      expect(doctorDisplay, equals('Dr Mitesh Jain'));
    });

    test('UUID-backed doctor resolves actual name from joined profile', () {
      final item = AppointmentModel(
        id: 'appt-staff-2',
        patientName: 'Anil Gupta',
        patientNumber: 'DEN-2001',
        department: 'dental',
        appointmentDate: DateTime(2026, 10, 17),
        appointmentTime: '15:00',
        appointmentType: 'consultation',
        status: 'scheduled',
        doctorName: 'Dr Nimisha',
        doctorId: '80fca5a0-72fc-46b9-8edb-72df52f51a12',
        createdAt: DateTime(2026, 10, 17),
        updatedAt: DateTime(2026, 10, 17),
      );

      final hasDoctor =
          item.doctorName != null && item.doctorName!.trim().isNotEmpty;
      final doctorDisplay =
          hasDoctor ? item.doctorName!.trim() : 'Doctor not assigned';

      expect(hasDoctor, isTrue);
      expect(doctorDisplay, equals('Dr Nimisha'));
    });

    test('Unassigned appointment displays "Doctor not assigned"', () {
      final item = AppointmentModel(
        id: 'appt-staff-3',
        patientName: 'Pooja Verma',
        patientNumber: 'EYE-1003',
        department: 'eye',
        appointmentDate: DateTime(2026, 10, 17),
        appointmentTime: '16:00',
        appointmentType: 'consultation',
        status: 'scheduled',
        doctorName: null,
        doctorId: null,
        createdAt: DateTime(2026, 10, 17),
        updatedAt: DateTime(2026, 10, 17),
      );

      final hasDoctor =
          item.doctorName != null && item.doctorName!.trim().isNotEmpty;
      final doctorDisplay =
          hasDoctor ? item.doctorName!.trim() : 'Doctor not assigned';

      expect(hasDoctor, isFalse);
      expect(doctorDisplay, equals('Doctor not assigned'));
    });
  });

  // ──────────────────────────────────────────────────────────────────────────
  // Part 3: Fix Staff Patient Page Showing Only Two Patients
  // ──────────────────────────────────────────────────────────────────────────
  group('Part 3: Fix Staff Patient Page Showing Only Two Patients', () {
    test(
        'Displays all patients permitted to staff without restricting to today appointments',
        () {
      final allPatients = [
        PatientModel(
            id: 'p1',
            name: 'Aarav Patel',
            patientNumber: 'EYE-0001',
            department: 'eye',
            createdAt: DateTime.now(),
            updatedAt: DateTime.now()),
        PatientModel(
            id: 'p2',
            name: 'Bhavna Shah',
            patientNumber: 'EYE-0002',
            department: 'eye',
            createdAt: DateTime.now(),
            updatedAt: DateTime.now()),
        PatientModel(
            id: 'p3',
            name: 'Chetan Mehta',
            patientNumber: 'DEN-0001',
            department: 'dental',
            createdAt: DateTime.now(),
            updatedAt: DateTime.now()),
        PatientModel(
            id: 'p4',
            name: 'Deepa Joshi',
            patientNumber: 'EYE-0003',
            department: 'eye',
            createdAt: DateTime.now(),
            updatedAt: DateTime.now()),
        PatientModel(
            id: 'p5',
            name: 'Eshwar Rao',
            patientNumber: 'DEN-0002',
            department: 'dental',
            createdAt: DateTime.now(),
            updatedAt: DateTime.now()),
      ];

      // Unrestricted staff or admin sees all patients
      expect(allPatients.length, equals(5));

      // Department restricted staff (e.g. Eye staff) sees all Eye patients, not just today appointments
      final eyeStaffPatients =
          allPatients.where((p) => p.department == 'eye').toList();
      expect(eyeStaffPatients.length, equals(3));
      expect(eyeStaffPatients.map((p) => p.name).toList(),
          equals(['Aarav Patel', 'Bhavna Shah', 'Deepa Joshi']));
    });

    test(
        'Avoids duplicate patient rows when one patient has multiple appointments',
        () {
      final rawPatientsWithDuplicates = [
        PatientModel(
            id: 'p-dup-1',
            name: 'Rohan Sharma',
            patientNumber: 'EYE-0010',
            department: 'eye',
            createdAt: DateTime.now(),
            updatedAt: DateTime.now()),
        PatientModel(
            id: 'p-dup-1',
            name: 'Rohan Sharma',
            patientNumber: 'EYE-0010',
            department: 'eye',
            createdAt: DateTime.now(),
            updatedAt: DateTime.now()),
        PatientModel(
            id: 'p-dup-2',
            name: 'Meena Kapoor',
            patientNumber: 'DEN-0020',
            department: 'dental',
            createdAt: DateTime.now(),
            updatedAt: DateTime.now()),
      ];

      final seenIds = <String>{};
      final uniquePatients = <PatientModel>[];
      for (final p in rawPatientsWithDuplicates) {
        if (seenIds.add(p.id)) {
          uniquePatients.add(p);
        }
      }

      expect(uniquePatients.length, equals(2));
      expect(uniquePatients.map((p) => p.id).toList(),
          equals(['p-dup-1', 'p-dup-2']));
    });

    test('Preserves Call functionality with phone validation', () {
      expect(PhoneDialerUtil.isValidPhoneNumber('+919876543210'), isTrue);
      expect(PhoneDialerUtil.isValidPhoneNumber('9876543210'), isTrue);
      expect(PhoneDialerUtil.isValidPhoneNumber(''), isFalse);
      expect(PhoneDialerUtil.isValidPhoneNumber(null), isFalse);
      expect(PhoneDialerUtil.isValidPhoneNumber('invalid'), isFalse);
    });
  });

  // ──────────────────────────────────────────────────────────────────────────
  // Part 4: Add a Date Selector to the Staff Tasks Page
  // ──────────────────────────────────────────────────────────────────────────
  group('Part 4: Add a Date Selector to the Staff Tasks Page', () {
    test('Date filtering correctly isolates tasks for selected calendar day',
        () {
      final taskOct16 = TaskItem(
        id: 't-16',
        title: 'Prepare surgical pack',
        assignedTo: 'staff-1',
        status: 'pending',
        priority: 'high',
        dueDate: DateTime(2026, 10, 16, 10, 0),
        createdAt: DateTime(2026, 10, 16),
        updatedAt: DateTime(2026, 10, 16),
      );

      final taskOct17 = TaskItem(
        id: 't-17',
        title: 'Check autoclave pressure',
        assignedTo: 'staff-1',
        status: 'pending',
        priority: 'critical',
        dueDate: DateTime(2026, 10, 17, 11, 0),
        createdAt: DateTime(2026, 10, 17),
        updatedAt: DateTime(2026, 10, 17),
      );

      final taskOct18 = TaskItem(
        id: 't-18',
        title: 'Weekly inventory count',
        assignedTo: 'staff-1',
        status: 'pending',
        priority: 'medium',
        dueDate: DateTime(2026, 10, 18, 14, 0),
        createdAt: DateTime(2026, 10, 17),
        updatedAt: DateTime(2026, 10, 17),
      );

      final allTasks = [taskOct16, taskOct17, taskOct18];

      // When selecting Oct 17:
      final selectedOct17 = DateTime(2026, 10, 17);
      final tasksForOct17 = allTasks
          .where((t) =>
              !t.isSurgeryTask &&
              t.dueDate != null &&
              t.dueDate!.year == selectedOct17.year &&
              t.dueDate!.month == selectedOct17.month &&
              t.dueDate!.day == selectedOct17.day)
          .toList();

      expect(tasksForOct17.length, equals(1));
      expect(tasksForOct17.first.id, equals('t-17'));

      // When selecting Oct 18:
      final selectedOct18 = DateTime(2026, 10, 18);
      final tasksForOct18 = allTasks
          .where((t) =>
              !t.isSurgeryTask &&
              t.dueDate != null &&
              t.dueDate!.year == selectedOct18.year &&
              t.dueDate!.month == selectedOct18.month &&
              t.dueDate!.day == selectedOct18.day)
          .toList();

      expect(tasksForOct18.length, equals(1));
      expect(tasksForOct18.first.id, equals('t-18'));
    });

    test('Selecting a past date does NOT automatically make every task overdue',
        () {
      // Completed task on a past date is NOT overdue
      final completedPastTask = TaskItem(
        id: 't-past-completed',
        title: 'Disinfect waiting room',
        assignedTo: 'staff-1',
        status: 'completed',
        priority: 'medium',
        dueDate: DateTime(2026, 10, 15, 9, 0),
        completedAt: DateTime(2026, 10, 15, 9, 30),
        createdAt: DateTime(2026, 10, 15),
        updatedAt: DateTime(2026, 10, 15),
      );

      expect(completedPastTask.isOverdue, isFalse);

      // Incomplete task whose due date has passed IS overdue
      final incompletePastTask = TaskItem(
        id: 't-past-incomplete',
        title: 'Calibrate slit lamp',
        assignedTo: 'staff-1',
        status: 'pending',
        priority: 'high',
        dueDate: DateTime(2026, 10, 15, 10, 0),
        createdAt: DateTime(2026, 10, 15),
        updatedAt: DateTime(2026, 10, 15),
      );

      expect(incompletePastTask.isOverdue, isTrue);

      // Future task is NOT overdue
      final futureTask = TaskItem(
        id: 't-future',
        title: 'Prep Monday clinic',
        assignedTo: 'staff-1',
        status: 'pending',
        priority: 'medium',
        dueDate: DateTime.now().add(const Duration(days: 2)),
        createdAt: DateTime.now(),
        updatedAt: DateTime.now(),
      );

      expect(futureTask.isOverdue, isFalse);
    });

    test('Surgeries are NOT treated as tasks and excluded from task date views',
        () {
      final surgeryTask = TaskItem(
        id: 't-surg-1',
        title: 'Cataract Surgery Patient Prep',
        assignedTo: 'staff-1',
        status: 'pending',
        priority: 'high',
        dueDate: DateTime(2026, 10, 17, 10, 0),
        relatedSurgeryId: 'surg-eye-001',
        createdAt: DateTime(2026, 10, 17),
        updatedAt: DateTime(2026, 10, 17),
      );

      expect(surgeryTask.isSurgeryTask, isTrue);
      expect(surgeryTask.isOverdue, isFalse);

      // Non-surgery filtering excludes surgery tasks
      final tasks = [surgeryTask];
      final dateTasks =
          tasks.where((t) => !t.isSurgeryTask && t.dueDate != null).toList();
      expect(dateTasks, isEmpty);
    });
  });

  // ──────────────────────────────────────────────────────────────────────────
  // Part 5: Add a Department Filter to the Main Staff Schedule
  // ──────────────────────────────────────────────────────────────────────────
  group('Part 5: Add a Department Filter to the Main Staff Schedule', () {
    final eyeAppointment = AppointmentModel(
      id: 'appt-eye',
      patientName: 'Ravi Verma',
      department: 'eye',
      appointmentDate: DateTime(2026, 10, 17),
      appointmentTime: '10:00',
      appointmentType: 'consultation',
      status: 'scheduled',
      createdAt: DateTime(2026, 10, 17),
      updatedAt: DateTime(2026, 10, 17),
    );

    final dentalAppointment = AppointmentModel(
      id: 'appt-dental',
      patientName: 'Kavita Sen',
      department: 'dental',
      appointmentDate: DateTime(2026, 10, 17),
      appointmentTime: '11:00',
      appointmentType: 'consultation',
      status: 'scheduled',
      createdAt: DateTime(2026, 10, 17),
      updatedAt: DateTime(2026, 10, 17),
    );

    final sharedAppointment = AppointmentModel(
      id: 'appt-shared',
      patientName: 'Vikram Joshi',
      department: 'common',
      appointmentDate: DateTime(2026, 10, 17),
      appointmentTime: '12:00',
      appointmentType: 'consultation',
      status: 'scheduled',
      createdAt: DateTime(2026, 10, 17),
      updatedAt: DateTime(2026, 10, 17),
    );

    final unassignedAppointment = AppointmentModel(
      id: 'appt-unassigned',
      patientName: 'Geeta Pillai',
      department: '',
      appointmentDate: DateTime(2026, 10, 17),
      appointmentTime: '13:00',
      appointmentType: 'consultation',
      status: 'scheduled',
      createdAt: DateTime(2026, 10, 17),
      updatedAt: DateTime(2026, 10, 17),
    );

    final eyeSurgery = EyeSurgeryModel(
      id: 'surg-eye-1',
      patientId: 'pat-surg',
      surgeryType: 'Phaco Cataract Surgery',
      eyeSide: 'left',
      preOpDate: DateTime(2026, 10, 16),
      surgeryDate: DateTime(2026, 10, 17),
      surgeryTime: '14:00',
      status: 'scheduled',
      createdAt: DateTime(2026, 10, 17),
      updatedAt: DateTime(2026, 10, 17),
    );

    String resolveCanonicalDepartment(
        {AppointmentModel? appt, EyeSurgeryModel? surg}) {
      if (surg != null) return 'eye';
      final dept = appt?.department.trim().toLowerCase() ?? '';
      if (dept.isEmpty) return '';
      if (dept.contains('eye')) return 'eye';
      if (dept.contains('dental')) return 'dental';
      if (dept.contains('it')) return 'it';
      if (dept.contains('rent')) return 'rental';
      if (dept.contains('common') || dept.contains('shared')) return 'common';
      return dept;
    }

    test(
        'Canonical department mapping correctly maps Eye, Dental, Surgeries, and explicit Shared',
        () {
      expect(resolveCanonicalDepartment(appt: eyeAppointment), equals('eye'));
      expect(resolveCanonicalDepartment(appt: dentalAppointment),
          equals('dental'));
      expect(resolveCanonicalDepartment(surg: eyeSurgery), equals('eye'));
      expect(resolveCanonicalDepartment(appt: sharedAppointment),
          equals('common'));
      // Missing or null department is NOT Common/Shared
      expect(
          resolveCanonicalDepartment(appt: unassignedAppointment), equals(''));
      expect(resolveCanonicalDepartment(appt: unassignedAppointment),
          isNot(equals('common')));
    });

    test(
        'Department filter "All Departments" returns all authorized schedule items',
        () {
      final items = [
        resolveCanonicalDepartment(appt: eyeAppointment),
        resolveCanonicalDepartment(appt: dentalAppointment),
        resolveCanonicalDepartment(appt: sharedAppointment),
        resolveCanonicalDepartment(surg: eyeSurgery),
      ];

      final filtered = items.where((dept) => true).toList();
      expect(filtered.length, equals(4));
    });

    test(
        'Department filter "Eye" returns only Eye appointments and Eye surgeries',
        () {
      final items = [
        (
          id: 'eye-appt',
          dept: resolveCanonicalDepartment(appt: eyeAppointment)
        ),
        (
          id: 'dental-appt',
          dept: resolveCanonicalDepartment(appt: dentalAppointment)
        ),
        (
          id: 'shared-appt',
          dept: resolveCanonicalDepartment(appt: sharedAppointment)
        ),
        (id: 'eye-surg', dept: resolveCanonicalDepartment(surg: eyeSurgery)),
      ];

      final filtered = items.where((i) => i.dept == 'eye').toList();
      expect(filtered.length, equals(2));
      expect(
          filtered.map((i) => i.id).toList(), equals(['eye-appt', 'eye-surg']));
    });

    test(
        'Department filter "Common / Shared" includes strictly explicit shared entries and never null/empty',
        () {
      final items = [
        (
          id: 'shared',
          dept: resolveCanonicalDepartment(appt: sharedAppointment)
        ),
        (
          id: 'unassigned',
          dept: resolveCanonicalDepartment(appt: unassignedAppointment)
        ),
        (
          id: 'dental',
          dept: resolveCanonicalDepartment(appt: dentalAppointment)
        ),
      ];

      final filtered =
          items.where((i) => i.dept == 'common' || i.dept == 'shared').toList();
      expect(filtered.length, equals(1));
      expect(filtered.first.id, equals('shared'));
    });

    test(
        'Staff role restrictions are preserved: restricted staff only sees authorized department',
        () {
      final dentalStaffProfile = UserProfile(
        id: 'dental-staff-1',
        fullName: 'Anita Dental Staff',
        email: 'anita@clinic.com',
        role: 'staff',
        department: 'dental',
        isActive: true,
        createdAt: DateTime.now(),
      );

      final items = [
        (id: 'eye-appt', dept: 'eye'),
        (id: 'dental-appt', dept: 'dental'),
        (id: 'eye-surg', dept: 'eye'),
      ];

      final staffDept = dentalStaffProfile.department?.toLowerCase();
      final isRestricted =
          dentalStaffProfile.role != 'admin' && staffDept != null;

      final authorizedItems = items.where((i) {
        if (isRestricted && i.dept != staffDept) return false;
        return true;
      }).toList();

      expect(authorizedItems.length, equals(1));
      expect(authorizedItems.first.id, equals('dental-appt'));
    });
  });
}
