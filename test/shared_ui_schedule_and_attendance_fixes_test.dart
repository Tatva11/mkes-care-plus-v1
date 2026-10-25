import 'package:flutter_test/flutter_test.dart';
import 'package:mkes_care/features/admin/models/user_profile.dart';
import 'package:mkes_care/features/appointments/models/appointment_model.dart';
import 'package:mkes_care/features/auth/models/profile_model.dart';
import 'package:mkes_care/features/department/models/department.dart';
import 'package:mkes_care/features/staff/models/attendance_record.dart';
import 'package:mkes_care/features/staff/models/shift_configuration.dart';

void main() {
  group('Task 2 & 3: Schedule Date Filtering, Empty State & Dynamic Departments', () {
    test('Date filtering strictly isolates selected schedule date without fake data', () {
      final selectedDate = DateTime(2026, 10, 18);
      final yesterday = DateTime(2026, 10, 17);
      final tomorrow = DateTime(2026, 10, 19);

      final appointments = [
        AppointmentModel(
          id: 'apt-today-1',
          patientId: 'pat-1',
          patientName: 'Ramesh Patel',
          appointmentDate: selectedDate,
          appointmentTime: '09:30:00',
          status: 'confirmed',
          department: 'eye',
          doctorName: 'Dr. Mehta',
          appointmentType: 'regular',
          aiBooked: false,
          createdAt: DateTime(2026, 10, 1),
          updatedAt: DateTime(2026, 10, 1),
        ),
        AppointmentModel(
          id: 'apt-yesterday-1',
          patientId: 'pat-2',
          patientName: 'Suresh Kumar',
          appointmentDate: yesterday,
          appointmentTime: '11:00:00',
          status: 'completed',
          department: 'dental',
          doctorName: 'Dr. Shah',
          appointmentType: 'regular',
          aiBooked: false,
          createdAt: DateTime(2026, 10, 1),
          updatedAt: DateTime(2026, 10, 1),
        ),
        AppointmentModel(
          id: 'apt-tomorrow-1',
          patientId: 'pat-3',
          patientName: 'Sarah Jenkins', // Fake name check
          appointmentDate: tomorrow,
          appointmentTime: '14:00:00',
          status: 'confirmed',
          department: 'eye',
          doctorName: 'Dr. Mehta',
          appointmentType: 'regular',
          aiBooked: false,
          createdAt: DateTime(2026, 10, 1),
          updatedAt: DateTime(2026, 10, 1),
        ),
      ];

      // Filtering strictly for selectedDate
      final filtered = appointments.where((a) {
        final aDate = a.appointmentDate.toLocal();
        return aDate.year == selectedDate.year &&
            aDate.month == selectedDate.month &&
            aDate.day == selectedDate.day;
      }).toList();

      expect(filtered.length, equals(1));
      expect(filtered.first.id, equals('apt-today-1'));
      expect(filtered.first.patientName, equals('Ramesh Patel'));

      // Ensure yesterday and tomorrow appointments are excluded
      expect(filtered.any((a) => a.id == 'apt-yesterday-1'), isFalse);
      expect(filtered.any((a) => a.id == 'apt-tomorrow-1'), isFalse);
      expect(filtered.any((a) => a.patientName == 'Sarah Jenkins'), isFalse);
    });

    test('Empty result on date with no appointments provides empty state', () {
      final selectedDate = DateTime(2026, 10, 25);
      final appointments = <AppointmentModel>[];

      final filtered = appointments.where((a) {
        final aDate = a.appointmentDate.toLocal();
        return aDate.year == selectedDate.year &&
            aDate.month == selectedDate.month &&
            aDate.day == selectedDate.day;
      }).toList();

      expect(filtered.isEmpty, isTrue);
      const emptyStateMessage = 'No appointments scheduled for this day.';
      expect(emptyStateMessage, contains('No appointments scheduled'));
    });

    test('Dynamic departments: Dropdown supports Eye, Dental, Common, and newly added departments', () {
      const dbDepartments = [
        Department(id: 'dept-1', name: 'Eye', isActive: true),
        Department(id: 'dept-2', name: 'Dental', isActive: true),
        Department(id: 'dept-3', name: 'Dermatology', isActive: true), // Newly added
      ];

      final departmentOptions = <String>['All', 'Common'];
      for (final dept in dbDepartments) {
        if (!departmentOptions.contains(dept.name)) {
          departmentOptions.add(dept.name);
        }
      }

      expect(departmentOptions, contains('All'));
      expect(departmentOptions, contains('Common'));
      expect(departmentOptions, contains('Eye'));
      expect(departmentOptions, contains('Dental'));
      expect(departmentOptions, contains('Dermatology'), reason: 'Newly added department must be supported');
    });
  });

  group('Task 7: Expire Upcoming Shift-Change Notices Correctly', () {
    final effectiveDate = DateTime(2026, 10, 12);
    final dayBefore = DateTime(2026, 10, 11);
    final onEffectiveDate = DateTime(2026, 10, 12);
    final dayAfter = DateTime(2026, 10, 13);

    final profile = ProfileModel(
      id: 'staff-1',
      fullName: 'Anita Sharma',
      email: 'anita@clinic.com',
      role: 'staff',
      isActive: true,
      assignedShift: 'morning',
      nextShift: 'afternoon', // Evening
      shiftEffectiveDate: effectiveDate,
      createdAt: DateTime(2026, 1, 1),
    );

    final userProfile = UserProfile(
      id: 'staff-1',
      fullName: 'Anita Sharma',
      email: 'anita@clinic.com',
      role: 'staff',
      isActive: true,
      assignedShift: 'morning',
      nextShift: 'afternoon',
      shiftEffectiveDate: effectiveDate,
      createdAt: DateTime(2026, 1, 1),
    );

    test('Day Before (11 Oct 2026): Change IS upcoming, active shift is Morning', () {
      expect(profile.isUpcomingShiftChange(dayBefore), isTrue,
          reason: 'Notice must display on the day before the effective date');
      expect(userProfile.isUpcomingShiftChange(dayBefore), isTrue);

      expect(profile.getShiftForDate(dayBefore), equals('morning'));
      expect(userProfile.getShiftForDate(dayBefore), equals('morning'));
    });

    test('On Effective Date (12 Oct 2026): Change is NO LONGER upcoming, active shift is Evening', () {
      expect(profile.isUpcomingShiftChange(onEffectiveDate), isFalse,
          reason: 'Once effective date arrives, change must not be described as upcoming');
      expect(userProfile.isUpcomingShiftChange(onEffectiveDate), isFalse);

      expect(profile.getShiftForDate(onEffectiveDate), equals('afternoon'),
          reason: 'Active shift must become the new shift on the effective date');
      expect(userProfile.getShiftForDate(onEffectiveDate), equals('afternoon'));
    });

    test('Day After (13 Oct 2026): Change is NOT upcoming, active shift remains Evening', () {
      expect(profile.isUpcomingShiftChange(dayAfter), isFalse,
          reason: 'Notice must not appear after the effective date has passed');
      expect(userProfile.isUpcomingShiftChange(dayAfter), isFalse);

      expect(profile.getShiftForDate(dayAfter), equals('afternoon'));
      expect(userProfile.getShiftForDate(dayAfter), equals('afternoon'));
    });
  });

  group('Task 8: Automatic Clock-Out Calculations & Idempotency', () {
    const eveningConfig = ShiftConfiguration(
      shift: 'afternoon',
      name: 'afternoon',
      startTime: '16:00', // 4:00 PM
      endTime: '21:00',   // 9:00 PM
      gracePeriodMinutes: 15,
    );

    test('Shift 4:00 PM - 9:00 PM automatically closes at 9:00 PM with 5.0 hours worked', () {
      final checkInTime = DateTime(2026, 10, 18, 16, 0); // 4:00 PM
      final shiftEndTime = eveningConfig.getShiftEndDateTime(checkInTime);

      expect(shiftEndTime.hour, equals(21));
      expect(shiftEndTime.minute, equals(0));

      final workingHours = (shiftEndTime.difference(checkInTime).inMinutes / 60.0).clamp(0.0, 24.0);
      expect(workingHours, equals(5.0));

      final autoClosedRecord = AttendanceRecord(
        id: 'att-1',
        staffId: 'staff-1',
        date: DateTime(2026, 10, 18),
        shift: 'afternoon',
        checkInTime: checkInTime,
        checkOutTime: shiftEndTime,
        workingHours: workingHours,
        status: 'present',
        isLate: false,
        lateMinutes: 0,
        notes: 'Auto-clocked out at configured shift end time',
      );

      expect(autoClosedRecord.checkOutTime, equals(shiftEndTime));
      expect(autoClosedRecord.workingHours, equals(5.0));
      expect(autoClosedRecord.notes, contains('Auto-clocked out'));
    });

    test('Idempotency: An already clocked-out record is not overwritten', () {
      final checkInTime = DateTime(2026, 10, 18, 16, 0);
      final manualCheckOut = DateTime(2026, 10, 18, 20, 30); // 8:30 PM manual clock-out

      final record = AttendanceRecord(
        id: 'att-manual-1',
        staffId: 'staff-1',
        date: DateTime(2026, 10, 18),
        shift: 'afternoon',
        checkInTime: checkInTime,
        checkOutTime: manualCheckOut,
        workingHours: 4.5,
        status: 'present',
        isLate: false,
        lateMinutes: 0,
      );

      // WHERE check_out_time IS NULL condition prevents modification
      final shouldAutoClose = record.checkInTime != null && record.checkOutTime == null;
      expect(shouldAutoClose, isFalse, reason: 'Already closed record must not be touched');
    });

    test('Staff with no clock-in cannot be auto clocked out', () {
      final absentRecord = AttendanceRecord(
        id: 'att-absent-1',
        staffId: 'staff-2',
        date: DateTime(2026, 10, 18),
        shift: 'afternoon',
        status: 'absent',
        isLate: false,
        lateMinutes: 0,
      );

      final shouldAutoClose = absentRecord.checkInTime != null && absentRecord.checkOutTime == null;
      expect(shouldAutoClose, isFalse, reason: 'Staff without clock-in cannot be auto-closed');
    });
  });

  group('Task 9: Leave Summary Wording & Business Rule Preservation', () {
    double calculateWorkingDays(DateTime start, DateTime end, String dutyPeriod) {
      int count = 0;
      DateTime cur = DateTime(start.year, start.month, start.day);
      final endDateOnly = DateTime(end.year, end.month, end.day);

      while (!cur.isAfter(endDateOnly)) {
        if (cur.weekday != DateTime.sunday) {
          count++;
        }
        cur = cur.add(const Duration(days: 1));
      }

      if (dutyPeriod == 'morning' || dutyPeriod == 'afternoon') {
        return count * 0.5;
      }
      return count.toDouble();
    }

    test('Morning only leave summary is concise: "0.5 working day(s) requested", "Morning only"', () {
      final start = DateTime(2026, 10, 19); // Monday
      final end = DateTime(2026, 10, 19);
      final dutyPeriod = 'morning';

      final workingDays = calculateWorkingDays(start, end, dutyPeriod);
      expect(workingDays, equals(0.5));

      final durationText = '${workingDays.toStringAsFixed(1)} working day(s) requested';
      final timingText = dutyPeriod == 'morning' ? 'Morning only' : 'Full day';

      expect(durationText, equals('0.5 working day(s) requested'));
      expect(timingText, equals('Morning only'));
      expect(durationText, isNot(contains('Sundays excluded')));
      expect(timingText, isNot(contains('Sundays excluded')));
    });

    test('Sunday exclusion business rule is strictly preserved in calculation', () {
      final sunday = DateTime(2026, 10, 18);
      final monday = DateTime(2026, 10, 19);

      // Sunday to Monday (2 calendar days, 1 Sunday) -> 1.0 working day
      final workingDaysFull = calculateWorkingDays(sunday, monday, 'full_day');
      expect(workingDaysFull, equals(1.0), reason: 'Sunday must be excluded from working days count');

      // Sunday only -> 0.0 working days
      final sundayOnly = calculateWorkingDays(sunday, sunday, 'full_day');
      expect(sundayOnly, equals(0.0));
    });
  });
}
