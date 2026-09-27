import 'package:flutter_test/flutter_test.dart';
import 'package:mkes_care/features/patients/models/patient_attendance.dart';

void main() {
  group('PatientAttendance.fromJson', () {
    test('parses attendance with staff name and timestamp', () {
      final record = PatientAttendance.fromJson({
        'id': 'attendance-uuid-1',
        // patient_id is now UUID (Phase 2 migration converted from TEXT)
        'patient_id': '11111111-1111-1111-1111-111111111111',
        'staff_id': 'aaaaaaaa-aaaa-aaaa-aaaa-aaaaaaaaaaaa',
        'profiles': {'full_name': 'Amit Staff', 'role': 'staff'},
        'attendance_date': '2026-09-26',
        'attended_at': '2026-09-26T10:32:00Z',
        'status': 'attended',
      });

      expect(record.id, 'attendance-uuid-1');
      expect(record.patientId, '11111111-1111-1111-1111-111111111111');
      expect(record.staffId, 'aaaaaaaa-aaaa-aaaa-aaaa-aaaaaaaaaaaa');
      expect(record.staffName, 'Amit Staff');
      expect(record.status, 'attended');
      expect(record.attendedAt, DateTime.parse('2026-09-26T10:32:00Z'));
    });

    test('parses attendance with nested patient join data (admin fetch)', () {
      final record = PatientAttendance.fromJson({
        'id': 'attendance-uuid-2',
        'patient_id': '22222222-2222-2222-2222-222222222222',
        'staff_id': 'bbbbbbbb-bbbb-bbbb-bbbb-bbbbbbbbbbbb',
        'profiles': {'full_name': 'Priya Nurse'},
        'patients': {
          'name': 'Ramesh Kumar',
          'patient_number': 'E-001',
          'department': 'Eye',
        },
        'attendance_date': '2026-09-26',
        'attended_at': '2026-09-26T09:15:00Z',
        'status': 'attended',
      });

      expect(record.patientName, 'Ramesh Kumar');
      expect(record.patientNumber, 'E-001');
      expect(record.patientDepartment, 'Eye');
      expect(record.staffName, 'Priya Nurse');
    });

    test('handles missing profiles join gracefully (null staffName)', () {
      final record = PatientAttendance.fromJson({
        'id': 'attendance-uuid-3',
        'patient_id': '33333333-3333-3333-3333-333333333333',
        'staff_id': 'cccccccc-cccc-cccc-cccc-cccccccccccc',
        // profiles join absent (e.g. select without join)
        'attendance_date': '2026-09-26',
        'attended_at': '2026-09-26T14:00:00Z',
        'status': 'attended',
      });

      expect(record.staffName, isNull);
      expect(record.patientName, isNull);
      expect(record.patientNumber, isNull);
    });

    test('normalises status to lowercase', () {
      final record = PatientAttendance.fromJson({
        'id': 'attendance-uuid-4',
        'patient_id': '44444444-4444-4444-4444-444444444444',
        'staff_id': 'dddddddd-dddd-dddd-dddd-dddddddddddd',
        'attendance_date': '2026-09-26',
        'attended_at': '2026-09-26T11:00:00Z',
        'status': 'ATTENDED',
      });

      expect(record.status, 'attended');
    });
  });
}
