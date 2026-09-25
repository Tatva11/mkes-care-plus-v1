import 'package:flutter_test/flutter_test.dart';
import 'package:mkes_care/features/patients/models/patient_attendance.dart';

void main() {
  test('parses patient attendance with staff identity and timestamp', () {
    final record = PatientAttendance.fromJson({
      'id': 'attendance-1',
      'patient_id': 'P-4092',
      'staff_id': 'staff-1',
      'profiles': {'full_name': 'Amit Staff', 'role': 'staff'},
      'attendance_date': '2026-09-21',
      'attended_at': '2026-09-21T10:32:00Z',
      'status': 'attended',
    });

    expect(record.patientId, 'P-4092');
    expect(record.staffId, 'staff-1');
    expect(record.staffName, 'Amit Staff');
    expect(record.status, 'attended');
    expect(record.attendedAt, DateTime.parse('2026-09-21T10:32:00Z'));
  });
}
