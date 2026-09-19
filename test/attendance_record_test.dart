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
  });
}
