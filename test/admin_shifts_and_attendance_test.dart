import 'package:flutter_test/flutter_test.dart';
import 'package:mkes_care/features/admin/models/user_profile.dart';
import 'package:mkes_care/features/staff/models/attendance_record.dart';
import 'package:mkes_care/features/staff/models/shift_configuration.dart';
import 'package:mkes_care/features/staff/repositories/attendance_repository.dart';

void main() {
  group('CHANGE 1: ShiftConfiguration & Timings Logic', () {
    test('Default Morning Shift timing and eligibility', () {
      const config = ShiftConfiguration.defaultMorning;
      expect(config.shift, 'morning');
      expect(config.name, 'morning');
      expect(config.displayName, 'Morning Shift');
      expect(config.startTime, '08:00');
      expect(config.endTime, '13:00');
      expect(config.gracePeriodMinutes, 15);
      expect(config.formattedTiming, '08:00 AM – 01:00 PM');

      // 07:45 AM (within 30 min check-in window)
      final earlyTime = DateTime(2026, 10, 10, 7, 45);
      expect(config.isEligibleForCheckIn(earlyTime), isTrue);
      expect(config.isTimeWithinShift(earlyTime), isFalse);

      // 08:10 AM (on-time within grace period)
      final onTime = DateTime(2026, 10, 10, 8, 10);
      expect(config.isEligibleForCheckIn(onTime), isTrue);
      expect(config.isTimeWithinShift(onTime), isTrue);
      expect(config.calculateLateMinutes(onTime), equals(0));

      // 08:25 AM (late by 25 minutes from 08:00 start)
      final lateTime = DateTime(2026, 10, 10, 8, 25);
      expect(config.calculateLateMinutes(lateTime), equals(25));

      // 18:00 PM (outside shift hours)
      final outsideTime = DateTime(2026, 10, 10, 18, 0);
      expect(config.isEligibleForCheckIn(outsideTime), isFalse);
      expect(config.isTimeWithinShift(outsideTime), isFalse);
    });

    test('Default Afternoon Shift timing and eligibility', () {
      const afternoonConfig = ShiftConfiguration.defaultAfternoon;
      expect(afternoonConfig.shift, 'afternoon');
      expect(afternoonConfig.name, 'afternoon');
      expect(afternoonConfig.displayName, 'Evening Shift');
      expect(afternoonConfig.startTime, '13:00');
      expect(afternoonConfig.endTime, '21:00');
      expect(afternoonConfig.formattedTiming, '01:00 PM – 09:00 PM');

      final beforeShift = DateTime(2026, 10, 10, 12, 45);
      expect(afternoonConfig.isEligibleForCheckIn(beforeShift), isTrue);

      final onTime = DateTime(2026, 10, 10, 13, 10);
      expect(afternoonConfig.isTimeWithinShift(onTime), isTrue);
      expect(afternoonConfig.calculateLateMinutes(onTime), equals(0));

      final lateTime = DateTime(2026, 10, 10, 13, 30);
      expect(afternoonConfig.calculateLateMinutes(lateTime), equals(30));
    });

    test('Overnight Night Shift handles crossing midnight correctly', () {
      const nightConfig = ShiftConfiguration.defaultNight;
      expect(nightConfig.shift, 'night');
      expect(nightConfig.name, 'night');
      expect(nightConfig.displayName, 'Night Shift');
      expect(nightConfig.startTime, '23:00');
      expect(nightConfig.endTime, '07:00');
      expect(nightConfig.formattedTiming, '11:00 PM – 07:00 AM');

      // 22:45 PM (eligible for check-in 15 min before 23:00)
      final beforeMidnight = DateTime(2026, 10, 10, 22, 45);
      expect(nightConfig.isEligibleForCheckIn(beforeMidnight), isTrue);

      // 23:10 PM (within shift, on-time)
      final nightOnTime = DateTime(2026, 10, 10, 23, 10);
      expect(nightConfig.isTimeWithinShift(nightOnTime), isTrue);
      expect(nightConfig.calculateLateMinutes(nightOnTime), equals(0));
      expect(nightConfig.getLogicalShiftDateStr(nightOnTime), '2026-10-10');

      // 02:30 AM (after midnight, belongs to shift that started previous evening)
      final afterMidnight = DateTime(2026, 10, 11, 2, 30);
      expect(nightConfig.isTimeWithinShift(afterMidnight), isTrue);
      expect(nightConfig.isEligibleForCheckIn(afterMidnight), isTrue);
      // Logical date should be 2026-10-10 (the date the shift started)
      expect(nightConfig.getLogicalShiftDateStr(afterMidnight), '2026-10-10');

      // 14:00 PM (daytime, outside night shift)
      final daytime = DateTime(2026, 10, 11, 14, 0);
      expect(nightConfig.isTimeWithinShift(daytime), isFalse);
      expect(nightConfig.isEligibleForCheckIn(daytime), isFalse);
    });

    test('Custom shift configuration updates start/end times and calculates late', () {
      final custom = const ShiftConfiguration(
        shift: 'morning',
        name: 'Early Morning Shift',
        startTime: '06:00',
        endTime: '14:00',
        gracePeriodMinutes: 10,
      );

      expect(custom.formattedTiming, '06:00 AM – 02:00 PM');
      final t1 = DateTime(2026, 10, 10, 6, 5);
      expect(custom.calculateLateMinutes(t1), equals(0)); // within 10 min grace

      final t2 = DateTime(2026, 10, 10, 6, 15);
      expect(custom.calculateLateMinutes(t2), equals(15)); // 15 min late
    });
  });

  group('CHANGE 1: UserProfile & Shift Assignment', () {
    test('UserProfile deserializes assignedShift and preserves defaults', () {
      final json = {
        'id': 'user-123',
        'full_name': 'Alice Staff',
        'email': 'alice@clinic.com',
        'role': 'staff',
        'is_active': true,
        'created_at': DateTime.now().toIso8601String(),
        'assigned_shift': 'night',
      };

      final profile = UserProfile.fromJson(json);
      expect(profile.assignedShift, 'night');

      final serialized = profile.toJson();
      expect(serialized['assigned_shift'], 'night');

      final modified = profile.copyWith(assignedShift: 'morning');
      expect(modified.assignedShift, 'morning');
    });

    test('UserProfile defaults assignedShift to morning when unspecified', () {
      final json = {
        'id': 'user-456',
        'full_name': 'Bob Staff',
        'email': 'bob@clinic.com',
        'role': 'staff',
        'is_active': true,
        'created_at': DateTime.now().toIso8601String(),
      };

      final profile = UserProfile.fromJson(json);
      expect(profile.assignedShift, 'morning');
    });
  });

  group('CHANGE 1: Attendance Record Isolation & History Preservation', () {
    test('Attendance records preserve their recorded shift without overwriting', () {
      final morningRecord = AttendanceRecord(
        id: 'rec-morning-1',
        staffId: 'staff-1',
        date: DateTime(2026, 10, 10),
        checkInTime: DateTime(2026, 10, 10, 7, 5),
        checkOutTime: DateTime(2026, 10, 10, 15, 0),
        status: 'present',
        isLate: false,
        lateMinutes: 0,
        workingHours: 7.9,
        shift: 'morning',
      );

      final nightRecord = AttendanceRecord(
        id: 'rec-night-1',
        staffId: 'staff-1',
        date: DateTime(2026, 10, 10),
        checkInTime: DateTime(2026, 10, 10, 23, 2),
        checkOutTime: DateTime(2026, 10, 11, 7, 0),
        status: 'present',
        isLate: false,
        lateMinutes: 0,
        workingHours: 8.0,
        shift: 'night',
      );

      expect(morningRecord.shift, equals('morning'));
      expect(nightRecord.shift, equals('night'));
      expect(morningRecord.isCompleted, isTrue);
      expect(nightRecord.isCompleted, isTrue);

      // Verify separate keys for shift date
      final morningDateStr = ManualAttendanceSource.getShiftDateStr(
        morningRecord.checkInTime!,
        'morning',
        config: ShiftConfiguration.defaultMorning,
      );
      final nightDateStr = ManualAttendanceSource.getShiftDateStr(
        nightRecord.checkInTime!,
        'night',
        config: ShiftConfiguration.defaultNight,
      );
      expect(morningDateStr, equals('2026-10-10'));
      expect(nightDateStr, equals('2026-10-10'));
    });
  });
}
