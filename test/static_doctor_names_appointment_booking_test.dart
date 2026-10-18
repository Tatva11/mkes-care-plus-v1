import 'package:flutter_test/flutter_test.dart';
import 'package:mkes_care/features/appointments/models/appointment_model.dart';
import 'package:mkes_care/features/appointments/models/department_doctor_config.dart';

void main() {
  TestWidgetsFlutterBinding.ensureInitialized();

  setUp(() {
    DepartmentDoctorConfig.reset();
  });

  tearDown(() {
    DepartmentDoctorConfig.reset();
  });

  group('Static Doctor Lists — Roster Configuration', () {
    test('Eye Department strictly offers Dr Mitesh Jain and Dr Varun', () {
      final eyeDoctors = DepartmentDoctorConfig.getDoctorsForDepartment('eye');

      expect(eyeDoctors.length, equals(2));
      expect(
        eyeDoctors.map((d) => d.fullName).toList(),
        equals(['Dr Mitesh Jain', 'Dr Varun']),
      );
      expect(eyeDoctors.every((d) => d.department == 'eye'), isTrue);
      // Static display doctors do not pretend to be authenticated users
      expect(eyeDoctors.every((d) => d.id.isEmpty), isTrue);
      expect(eyeDoctors.every((d) => !d.hasValidDatabaseId), isTrue);
    });

    test('Dental Department strictly offers Dr Nimisha and Dr Vikas', () {
      final dentalDoctors =
          DepartmentDoctorConfig.getDoctorsForDepartment('dental');

      expect(dentalDoctors.length, equals(2));
      expect(
        dentalDoctors.map((d) => d.fullName).toList(),
        equals(['Dr Nimisha', 'Dr Vikas']),
      );
      expect(dentalDoctors.every((d) => d.department == 'dental'), isTrue);
      // Static display doctors do not pretend to be authenticated users
      expect(dentalDoctors.every((d) => d.id.isEmpty), isTrue);
      expect(dentalDoctors.every((d) => !d.hasValidDatabaseId), isTrue);
    });
  });

  group('Department Switching & Doctor Selection Clearing', () {
    test('Eye doctors are valid for Eye and invalid for Dental', () {
      expect(
        DepartmentDoctorConfig.isValidDoctorNameForDepartment(
            'Dr Mitesh Jain', 'eye'),
        isTrue,
      );
      expect(
        DepartmentDoctorConfig.isValidDoctorNameForDepartment(
            'Dr Varun', 'eye'),
        isTrue,
      );
      expect(
        DepartmentDoctorConfig.isValidDoctorNameForDepartment(
            'Dr Mitesh Jain', 'dental'),
        isFalse,
      );
      expect(
        DepartmentDoctorConfig.isValidDoctorNameForDepartment(
            'Dr Varun', 'dental'),
        isFalse,
      );
    });

    test('Dental doctors are valid for Dental and invalid for Eye', () {
      expect(
        DepartmentDoctorConfig.isValidDoctorNameForDepartment(
            'Dr Nimisha', 'dental'),
        isTrue,
      );
      expect(
        DepartmentDoctorConfig.isValidDoctorNameForDepartment(
            'Dr Vikas', 'dental'),
        isTrue,
      );
      expect(
        DepartmentDoctorConfig.isValidDoctorNameForDepartment(
            'Dr Nimisha', 'eye'),
        isFalse,
      );
      expect(
        DepartmentDoctorConfig.isValidDoctorNameForDepartment(
            'Dr Vikas', 'eye'),
        isFalse,
      );
    });

    test('Unassigned / General Queue is always valid across all departments',
        () {
      expect(
        DepartmentDoctorConfig.isValidDoctorNameForDepartment(null, 'eye'),
        isTrue,
      );
      expect(
        DepartmentDoctorConfig.isValidDoctorNameForDepartment(null, 'dental'),
        isTrue,
      );
      expect(
        DepartmentDoctorConfig.isValidDoctorNameForDepartment('', 'eye'),
        isTrue,
      );
      expect(
        DepartmentDoctorConfig.isValidDoctorNameForDepartment('', 'dental'),
        isTrue,
      );
    });

    test('Switching department from Eye to Dental clears Eye doctor selection',
        () {
      String currentDept = 'eye';
      String? selectedDoctorName = 'Dr Mitesh Jain';

      expect(
        DepartmentDoctorConfig.isValidDoctorNameForDepartment(
            selectedDoctorName, currentDept),
        isTrue,
      );

      // User changes department to Dental
      currentDept = 'dental';
      if (!DepartmentDoctorConfig.isValidDoctorNameForDepartment(
          selectedDoctorName, currentDept)) {
        selectedDoctorName = null;
      }

      expect(selectedDoctorName, isNull);
    });

    test('Switching department from Dental to Eye clears Dental doctor selection',
        () {
      String currentDept = 'dental';
      String? selectedDoctorName = 'Dr Vikas';

      expect(
        DepartmentDoctorConfig.isValidDoctorNameForDepartment(
            selectedDoctorName, currentDept),
        isTrue,
      );

      // User changes department to Eye
      currentDept = 'eye';
      if (!DepartmentDoctorConfig.isValidDoctorNameForDepartment(
          selectedDoctorName, currentDept)) {
        selectedDoctorName = null;
      }

      expect(selectedDoctorName, isNull);
    });
  });

  group('Safe Persistence — No Fabricated Slugs or UUID Violations', () {
    test(
        'Booking with static doctor sets doctor_id to null and persists name safely in notes',
        () {
      final now = DateTime.now();
      final appt = AppointmentModel(
        id: 'new-appt-1',
        patientId: 'pat-101',
        department: 'eye',
        doctorId: null,
        doctorName: 'Dr Mitesh Jain',
        appointmentDate: now,
        appointmentTime: '10:00:00',
        appointmentType: 'regular',
        status: 'scheduled',
        notes: 'Follow up cataract check',
        createdAt: now,
        updatedAt: now,
      );

      final insertPayload = appt.toInsertJson();

      // STRICT REQUIREMENT: No non-UUID sent to doctor_id
      expect(insertPayload.containsKey('doctor_id'), isFalse);
      expect(insertPayload['doctor_id'], isNull);

      // Notes safely contains the static doctor tag and user notes
      expect(insertPayload['notes'], contains('Doctor: Dr Mitesh Jain'));
      expect(insertPayload['notes'], contains('Follow up cataract check'));
    });

    test(
        'Fabricated slugs like doc-eye-mitesh are never passed to database UUID column',
        () {
      final now = DateTime.now();
      final appt = AppointmentModel(
        id: 'legacy-appt',
        patientId: 'pat-102',
        department: 'eye',
        doctorId: 'doc-eye-mitesh', // legacy fabricated slug
        doctorName: 'Dr Mitesh Jain',
        appointmentDate: now,
        appointmentTime: '11:00:00',
        appointmentType: 'regular',
        status: 'scheduled',
        createdAt: now,
        updatedAt: now,
      );

      final insertPayload = appt.toInsertJson();

      // Filtered out to avoid PostgreSQL 22P02 invalid input syntax for type uuid
      expect(insertPayload.containsKey('doctor_id'), isFalse);
      expect(insertPayload['doctor_id'], isNull);
      expect(insertPayload['notes'], contains('Doctor: Dr Mitesh Jain'));
    });

    test('Valid PostgreSQL UUID is preserved for existing doctor accounts', () {
      const genuineUuid = '550e8400-e29b-41d4-a716-446655440001';
      final now = DateTime.now();
      final appt = AppointmentModel(
        id: 'existing-appt',
        patientId: 'pat-103',
        department: 'eye',
        doctorId: genuineUuid,
        doctorName: 'Dr Varun',
        appointmentDate: now,
        appointmentTime: '14:00:00',
        appointmentType: 'regular',
        status: 'scheduled',
        createdAt: now,
        updatedAt: now,
      );

      final insertPayload = appt.toInsertJson();
      expect(insertPayload['doctor_id'], equals(genuineUuid));
    });
  });

  group('Deserialization & Compatibility — View and Edit Existing Appointments',
      () {
    test('fromJson restores static doctor name from encoded notes', () {
      final json = {
        'id': 'appt-uuid-1',
        'patient_id': 'pat-uuid-1',
        'department': 'eye',
        'doctor_id': null,
        'appointment_date': '2026-10-20',
        'appointment_time': '09:30:00',
        'appointment_type': 'regular',
        'status': 'scheduled',
        'notes': 'Doctor: Dr Varun\nPatient requested early slot',
        'created_at': '2026-10-17T10:00:00Z',
        'updated_at': '2026-10-17T10:00:00Z',
      };

      final appt = AppointmentModel.fromJson(json);

      expect(appt.doctorName, equals('Dr Varun'));
      expect(appt.doctorId, isNull);
      // Clean display notes
      final cleanNotes =
          AppointmentModel.stripDoctorNameFromNotes(appt.notes);
      expect(cleanNotes, equals('Patient requested early slot'));
    });

    test(
        'fromJson supports joined profiles.full_name for legacy appointments with doctor accounts',
        () {
      final json = {
        'id': 'appt-legacy-1',
        'patient_id': 'pat-uuid-2',
        'department': 'dental',
        'doctor_id': '550e8400-e29b-41d4-a716-446655440003',
        'appointment_date': '2026-10-20',
        'appointment_time': '10:00:00',
        'appointment_type': 'regular',
        'status': 'scheduled',
        'notes': 'Routine root canal consult',
        'created_at': '2026-10-17T10:00:00Z',
        'updated_at': '2026-10-17T10:00:00Z',
        'profiles': {
          'id': '550e8400-e29b-41d4-a716-446655440003',
          'full_name': 'Dr Nimisha',
          'designation': 'General Dentistry',
        },
      };

      final appt = AppointmentModel.fromJson(json);

      expect(appt.doctorName, equals('Dr Nimisha'));
      expect(appt.doctorId, equals('550e8400-e29b-41d4-a716-446655440003'));
      expect(appt.notes, equals('Routine root canal consult'));
    });

    test(
        'Updating appointment with a static doctor formats notes and leaves doctor_id null',
        () {
      final userNotes = 'Patient has blurry vision in left eye';
      final formatted = AppointmentModel.formatNotesWithDoctor(
          userNotes, 'Dr Mitesh Jain');

      expect(formatted, equals('Doctor: Dr Mitesh Jain\n$userNotes'));

      // If user clears doctor selection, formatting removes doctor prefix
      final unassigned =
          AppointmentModel.formatNotesWithDoctor(formatted, null);
      expect(unassigned, equals(userNotes));
    });
  });
}
