import 'package:flutter_test/flutter_test.dart';
import 'package:mkes_care/features/staff/models/attendance_record.dart';

void main() {
  group('AttendanceRecord', () {
    test('returns a display label for attendance statuses', () {
      final present = AttendanceRecord(
        id: '1',
        staffId: 'staff-1',
        date: DateTime(2026, 9, 19),
        status: 'present',
        isLate: false,
        lateMinutes: 0,
      );

      final late = AttendanceRecord(
        id: '2',
        staffId: 'staff-1',
        date: DateTime(2026, 9, 19),
        status: 'late',
        isLate: true,
        lateMinutes: 10,
      );

      expect(present.statusLabel, 'Present');
      expect(late.statusLabel, 'Late');
      expect(present.isClockedIn, false);
      expect(late.isClockedIn, false);
    });

    test('supports morning and night shifts with timing display', () {
      final morningRecord = AttendanceRecord(
        id: '1',
        staffId: 'staff-1',
        date: DateTime(2026, 10, 5),
        status: 'present',
        isLate: false,
        lateMinutes: 0,
        shift: 'morning',
      );

      final nightRecord = AttendanceRecord(
        id: '2',
        staffId: 'staff-1',
        date: DateTime(2026, 10, 5),
        status: 'present',
        isLate: false,
        lateMinutes: 0,
        shift: 'night',
      );

      expect(morningRecord.shift, 'morning');
      expect(morningRecord.shiftDisplayName, 'Morning Shift');
      expect(morningRecord.shiftTimingDisplay, '08:00 AM – 01:00 PM');

      final afternoonRecord = AttendanceRecord(
        id: '3',
        staffId: 'staff-1',
        date: DateTime(2026, 10, 5),
        status: 'present',
        isLate: false,
        lateMinutes: 0,
        shift: 'afternoon',
      );
      expect(afternoonRecord.shift, 'afternoon');
      expect(afternoonRecord.shiftDisplayName, 'Evening Shift');
      expect(afternoonRecord.shiftTimingDisplay, '01:00 PM – 09:00 PM');

      expect(nightRecord.shift, 'night');
      expect(nightRecord.shiftDisplayName, 'Night Shift');
      expect(nightRecord.shiftTimingDisplay, '11:00 PM – 07:00 AM');

      // Test JSON serialization & deserialization
      final json = nightRecord.toJson();
      expect(json['shift'], 'night');

      final reconstructed = AttendanceRecord.fromJson(json);
      expect(reconstructed.shift, 'night');
      expect(reconstructed.shiftDisplayName, 'Night Shift');
      expect(reconstructed.shiftTimingDisplay, '11:00 PM – 07:00 AM');
    });

    test('defaults to morning shift when shift is null or unspecified', () {
      final unassigned = AttendanceRecord(
        id: '3',
        staffId: 'staff-2',
        date: DateTime(2026, 10, 5),
        status: 'present',
        isLate: false,
        lateMinutes: 0,
      );

      expect(unassigned.shift, 'morning');
      expect(unassigned.shiftDisplayName, 'Morning Shift');
    });
  });
}
