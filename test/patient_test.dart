import 'package:flutter_test/flutter_test.dart';
import 'package:mkes_care/features/patients/models/patient.dart';

void main() {
  test('normalizes allowed department values to database casing', () {
    expect(Patient.normalizeDepartment('Eye'), 'Eye');
    expect(Patient.normalizeDepartment(' dental '), 'Dental');
    expect(Patient.normalizeDepartment('OPTICAL'), 'Optical');
    expect(Patient.normalizeDepartment('administration'), 'Administration');
    expect(Patient.normalizeDepartment('Unknown'), isNull);
  });

  test('parses nullable patient fields and department relation', () {
    final patient = Patient.fromJson({
      'id': 'patient-1',
      'patient_number': 'P-1001',
      'name': 'Rahul Shah',
      'mobile': '9820000000',
      'dob': null,
      'address': null,
      'department': 'Dental',
      'created_at': '2026-09-21T08:00:00Z',
      'updated_at': '2026-09-21T08:00:00Z',
    });

    expect(patient.patientNumber, 'P-1001');
    expect(patient.fullName, 'Rahul Shah');
    expect(patient.departmentName, 'Dental');
    expect(patient.dateOfBirth, isNull);
  });
}