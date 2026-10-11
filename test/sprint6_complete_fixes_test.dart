import 'package:flutter_test/flutter_test.dart';
import 'package:mkes_care/features/admin/models/user_profile.dart';
import 'package:mkes_care/features/auth/models/profile_model.dart';
import 'package:mkes_care/features/eye/models/eye_surgery_item_model.dart';
import 'package:mkes_care/features/eye/models/eye_surgery_model.dart';
import 'package:mkes_care/features/staff/models/attendance_record.dart';
import 'package:mkes_care/features/staff/models/leave_request.dart';
import 'package:mkes_care/features/staff/models/shift_configuration.dart';
import 'package:mkes_care/features/staff/repositories/leave_repository.dart';

void main() {
  group('Requirement 1 & 2: Shift Configuration Schema & Morning/Afternoon/Both Duty Model', () {
    test('ShiftConfiguration serialization uses column "name" matching DB schema without "shift" column', () {
      const morning = ShiftConfiguration.defaultMorning;
      expect(morning.name, 'morning');
      expect(morning.shift, 'morning');
      expect(morning.startTime, '08:00');
      expect(morning.endTime, '13:00');
      expect(morning.gracePeriodMinutes, 15);

      final morningJson = morning.toJson();
      // Crucial: Must serialize to 'name', not 'shift', to avoid PostgrestException PGRST204
      expect(morningJson.containsKey('name'), isTrue);
      expect(morningJson.containsKey('shift'), isFalse);
      expect(morningJson['name'], 'morning');
      expect(morningJson['start_time'], '08:00');
      expect(morningJson['end_time'], '13:00');

      const afternoon = ShiftConfiguration.defaultAfternoon;
      expect(afternoon.name, 'afternoon');
      expect(afternoon.shift, 'afternoon');
      expect(afternoon.startTime, '13:00');
      expect(afternoon.endTime, '21:00');

      final afternoonJson = afternoon.toJson();
      expect(afternoonJson['name'], 'afternoon');
      expect(afternoonJson.containsKey('shift'), isFalse);
    });

    test('ShiftConfiguration.fromJson parses both name and backward-compatible shift keys', () {
      final fromDb = ShiftConfiguration.fromJson({
        'name': 'afternoon',
        'start_time': '13:30',
        'end_time': '21:30',
        'grace_period_minutes': 20,
      });
      expect(fromDb.name, 'afternoon');
      expect(fromDb.shift, 'afternoon');
      expect(fromDb.startTime, '13:30');
      expect(fromDb.endTime, '21:30');
      expect(fromDb.gracePeriodMinutes, 20);

      final legacy = ShiftConfiguration.fromJson({
        'shift': 'morning',
        'start_time': '08:00',
        'end_time': '13:00',
      });
      expect(legacy.name, 'morning');
      expect(legacy.shift, 'morning');
    });

    test('UserProfile and ProfileModel support morning, afternoon, and both assignments', () {
      final userMorning = UserProfile.fromJson({
        'id': 'u-1',
        'full_name': 'Morning Nurse',
        'email': 'nurse1@clinic.com',
        'role': 'staff',
        'is_active': true,
        'created_at': DateTime.now().toIso8601String(),
        'assigned_shift': 'morning',
      });
      expect(userMorning.isMorningShift, isTrue);
      expect(userMorning.isAfternoonShift, isFalse);
      expect(userMorning.isBothShifts, isFalse);
      expect(userMorning.shiftDisplayName, 'Morning Shift');

      final userAfternoon = UserProfile.fromJson({
        'id': 'u-2',
        'full_name': 'Afternoon Tech',
        'email': 'tech@clinic.com',
        'role': 'staff',
        'is_active': true,
        'created_at': DateTime.now().toIso8601String(),
        'assigned_shift': 'afternoon',
      });
      expect(userAfternoon.isMorningShift, isFalse);
      expect(userAfternoon.isAfternoonShift, isTrue);
      expect(userAfternoon.isBothShifts, isFalse);
      expect(userAfternoon.shiftDisplayName, 'Evening Shift');

      final userBoth = UserProfile.fromJson({
        'id': 'u-3',
        'full_name': 'Full-Day Officer',
        'email': 'officer@clinic.com',
        'role': 'staff',
        'is_active': true,
        'created_at': DateTime.now().toIso8601String(),
        'assigned_shift': 'both',
      });
      expect(userBoth.isMorningShift, isFalse);
      expect(userBoth.isAfternoonShift, isFalse);
      expect(userBoth.isBothShifts, isTrue);
      expect(userBoth.shiftDisplayName, 'Both (Morning & Evening)');
      expect(userBoth.toJson()['assigned_shift'], 'both');

      final profileBoth = ProfileModel.fromJson({
        'id': 'u-3',
        'full_name': 'Full-Day Officer',
        'email': 'officer@clinic.com',
        'role': 'staff',
        'is_active': true,
        'created_at': DateTime.now().toIso8601String(),
        'assigned_shift': 'both',
      });
      expect(profileBoth.assignedShift, 'both');
    });
  });

  group('Requirement 4 & 5: Staff Attendance & Partial-Day Leave Management', () {
    test('LeaveRequest model correctly handles duty periods and shift coverage', () {
      final fullDayLeave = LeaveRequest(
        id: 'lv-1',
        staffId: 'st-1',
        startDate: DateTime(2026, 10, 12),
        endDate: DateTime(2026, 10, 12),
        leaveDays: 1.0,
        status: 'approved',
        reason: 'Personal',
        createdAt: DateTime.now(),
        dutyPeriod: 'full_day',
      );
      expect(fullDayLeave.isFullDay, isTrue);
      expect(fullDayLeave.isMorningOnly, isFalse);
      expect(fullDayLeave.isAfternoonOnly, isFalse);
      expect(fullDayLeave.coversShift('morning'), isTrue);
      expect(fullDayLeave.coversShift('afternoon'), isTrue);

      final morningLeave = LeaveRequest(
        id: 'lv-2',
        staffId: 'st-1',
        startDate: DateTime(2026, 10, 12),
        endDate: DateTime(2026, 10, 12),
        leaveDays: 0.5,
        status: 'approved',
        reason: 'Medical checkup',
        createdAt: DateTime.now(),
        dutyPeriod: 'morning',
      );
      expect(morningLeave.isMorningOnly, isTrue);
      expect(morningLeave.dutyPeriodDisplayName, 'Morning Duty Only');
      expect(morningLeave.coversShift('morning'), isTrue);
      expect(morningLeave.coversShift('afternoon'), isFalse);

      final afternoonLeave = LeaveRequest(
        id: 'lv-3',
        staffId: 'st-1',
        startDate: DateTime(2026, 10, 12),
        endDate: DateTime(2026, 10, 12),
        leaveDays: 0.5,
        status: 'approved',
        reason: 'Family event',
        createdAt: DateTime.now(),
        dutyPeriod: 'afternoon',
      );
      expect(afternoonLeave.isAfternoonOnly, isTrue);
      expect(afternoonLeave.dutyPeriodDisplayName, 'Evening Duty Only');
      expect(afternoonLeave.coversShift('morning'), isFalse);
      expect(afternoonLeave.coversShift('afternoon'), isTrue);

      // JSON serialization
      final json = morningLeave.toJson();
      expect(json['duty_period'], 'morning');
      expect(json['leave_days'], 0.5);

      final deserialized = LeaveRequest.fromJson(json);
      expect(deserialized.dutyPeriod, 'morning');
      expect(deserialized.leaveDays, 0.5);
    });

    test('LeaveRepository calculateLeaveDays computes 0.5 days for partial-day leaves and excludes Sundays', () {
      // Monday 2026-10-12 (Single working day)
      final monday = DateTime(2026, 10, 12);
      expect(LeaveRepository.calculateLeaveDays(monday, monday, dutyPeriod: 'full_day'), 1.0);
      expect(LeaveRepository.calculateLeaveDays(monday, monday, dutyPeriod: 'morning'), 0.5);
      expect(LeaveRepository.calculateLeaveDays(monday, monday, dutyPeriod: 'afternoon'), 0.5);

      // Sunday 2026-10-18 (Sunday should be 0 days)
      final sunday = DateTime(2026, 10, 18);
      expect(LeaveRepository.calculateLeaveDays(sunday, sunday, dutyPeriod: 'full_day'), 0.0);
      expect(LeaveRepository.calculateLeaveDays(sunday, sunday, dutyPeriod: 'morning'), 0.0);

      // Friday to Monday (Fri, Sat, Sun, Mon) = 3 working days
      final friday = DateTime(2026, 10, 16);
      final nextMonday = DateTime(2026, 10, 19);
      expect(LeaveRepository.calculateLeaveDays(friday, nextMonday, dutyPeriod: 'full_day'), 3.0);
      expect(LeaveRepository.calculateLeaveDays(friday, nextMonday, dutyPeriod: 'morning'), 1.5);
    });

    test('AttendanceRecord supports morning and afternoon shifts with independent session state', () {
      final morningRecord = AttendanceRecord(
        id: 'att-1',
        staffId: 'st-1',
        date: DateTime(2026, 10, 12),
        shift: 'morning',
        status: 'present',
        isLate: false,
        lateMinutes: 0,
        checkInTime: DateTime(2026, 10, 12, 8, 0),
        checkOutTime: DateTime(2026, 10, 12, 13, 0),
        workingHours: 5.0,
      );
      expect(morningRecord.shift, 'morning');
      expect(morningRecord.shiftDisplayName, 'Morning Shift');
      expect(morningRecord.shiftTimingDisplay, '08:00 AM – 01:00 PM');
      expect(morningRecord.isCompleted, isTrue);

      final afternoonRecord = AttendanceRecord(
        id: 'att-2',
        staffId: 'st-1',
        date: DateTime(2026, 10, 12),
        shift: 'afternoon',
        status: 'present',
        isLate: true,
        checkInTime: DateTime(2026, 10, 12, 13, 15),
        lateMinutes: 15,
      );
      expect(afternoonRecord.shift, 'afternoon');
      expect(afternoonRecord.shiftDisplayName, 'Evening Shift');
      expect(afternoonRecord.shiftTimingDisplay, '01:00 PM – 09:00 PM');
      expect(afternoonRecord.isClockedIn, isTrue);
      expect(afternoonRecord.isCompleted, isFalse);
    });
  });

  group('Requirement 6 & 7: Eye Surgery Inventory Simplification & Immediate Stock Deduction', () {
    test('EyeSurgeryItemModel exposes unified requiredQuantity getter', () {
      const item = EyeSurgeryItemModel(
        id: 'esi-1',
        surgeryId: 'surg-1',
        inventoryItemId: 'inv-item-1',
        inventoryItemName: 'Intraocular Lens 20D',
        currentStock: 10,
        unit: 'pcs',
        plannedQuantity: 2,
        actualQuantity: 2,
        source: 'manual',
      );

      // Single authoritative requiredQuantity field
      expect(item.requiredQuantity, 2);

      final json = item.toJson();
      expect(json['planned_quantity'], 2);

      final deserialized = EyeSurgeryItemModel.fromJson(json);
      expect(deserialized.requiredQuantity, 2);
    });

    test('EyeSurgeryStaffCandidate filters out Admin accounts and inactive staff while preserving Department', () {
      final candidates = uniqueEyeSurgeryStaffCandidates(const [
        EyeSurgeryStaffCandidate(
          id: 'adm-01',
          fullName: 'Hospital Admin',
          role: 'admin',
          isActive: true,
          department: 'Eye Care',
        ),
        EyeSurgeryStaffCandidate(
          id: 'staff-inact',
          fullName: 'Dr. Retired',
          role: 'staff',
          isActive: false,
          department: 'Eye Care',
        ),
        EyeSurgeryStaffCandidate(
          id: 'doc-01',
          fullName: 'Dr. Arvind Sharma',
          role: 'staff',
          isActive: true,
          department: 'Eye Care',
        ),
        EyeSurgeryStaffCandidate(
          id: 'nurse-01',
          fullName: 'Nurse Priya',
          role: 'staff',
          isActive: true,
          department: 'Eye Care',
        ),
      ]);

      expect(candidates.length, 2);
      expect(candidates.map((c) => c.fullName).toList(), ['Dr. Arvind Sharma', 'Nurse Priya']);
      expect(candidates.first.department, 'Eye Care');
    });
  });
}
