import 'package:flutter_test/flutter_test.dart';
import 'package:mkes_care/features/notifications/models/notification_model.dart';
import 'package:mkes_care/features/staff/models/leave_request.dart';
import 'package:mkes_care/features/staff/models/salary_deduction_config.dart';
import 'package:mkes_care/features/staff/models/task_item.dart';
import 'package:mkes_care/features/staff/repositories/leave_repository.dart';

void main() {
  group('Sprint 5 — Leave Management & Salary Deduction', () {
    test('calculateLeaveDays excludes Sundays correctly', () {
      // Monday 2026-09-21 to Sunday 2026-09-27: 7 days total, 1 Sunday -> 6 leave days
      final start = DateTime(2026, 9, 21); // Monday
      final end = DateTime(2026, 9, 27); // Sunday
      final days = LeaveRepository.calculateLeaveDays(start, end);
      expect(days, equals(6.0));
    });

    test('calculateLeaveDays for a single Sunday returns 0', () {
      final sunday = DateTime(2026, 9, 27);
      final days = LeaveRepository.calculateLeaveDays(sunday, sunday);
      expect(days, equals(0.0));
    });

    test('calculateLeaveDays for a single weekday returns 1', () {
      final monday = DateTime(2026, 9, 21);
      final days = LeaveRepository.calculateLeaveDays(monday, monday);
      expect(days, equals(1.0));
    });

    test('SalaryDeductionConfig computes correct deduction amount', () {
      // Monthly salary: 30,000 -> daily rate 1,000
      const config = SalaryDeductionConfig(dailyRate: 1000.0);
      expect(config.calculateDeduction(0), equals(0.0));
      expect(config.calculateDeduction(3.0), equals(3000.0));
      expect(config.calculateDeduction(0.5), equals(500.0));
    });

    test('LeaveRequest parses from JSON with profile join', () {
      final json = {
        'id': 'leave-123',
        'staff_id': 'staff-456',
        'profiles': {'full_name': 'Jane Doe'},
        'start_date': '2026-10-01',
        'end_date': '2026-10-03',
        'leave_days': 3.0,
        'reason': 'Medical emergency',
        'status': 'pending',
        'created_at': '2026-09-28T09:00:00Z',
      };

      final req = LeaveRequest.fromJson(json);
      expect(req.id, equals('leave-123'));
      expect(req.staffId, equals('staff-456'));
      expect(req.staffName, equals('Jane Doe'));
      expect(req.leaveDays, equals(3.0));
      expect(req.status, equals('pending'));
      expect(req.reason, equals('Medical emergency'));
    });
  });

  group('Sprint 5 — Notifications', () {
    test('NotificationModel relativeTime formats properly', () {
      final now = DateTime.now();
      final justNow = NotificationModel(
        id: '1',
        userId: 'u1',
        title: 'Test',
        message: 'Hello',
        type: 'info',
        isRead: false,
        createdAt: now.subtract(const Duration(seconds: 10)),
      );
      expect(justNow.relativeTime, equals('Just now'));

      final minsAgo = NotificationModel(
        id: '2',
        userId: 'u1',
        title: 'Test',
        message: 'Hello',
        type: 'task_assigned',
        isRead: true,
        createdAt: now.subtract(const Duration(minutes: 15)),
      );
      expect(minsAgo.relativeTime, equals('15m ago'));

      final hoursAgo = NotificationModel(
        id: '3',
        userId: 'u1',
        title: 'Test',
        message: 'Hello',
        type: 'leave_approved',
        isRead: false,
        createdAt: now.subtract(const Duration(hours: 4)),
      );
      expect(hoursAgo.relativeTime, equals('4h ago'));
    });

    test('NotificationModel returns correct icons and colors for types', () {
      final leaveApproved = NotificationModel(
        id: '1',
        userId: 'u1',
        title: 'Approved',
        message: 'Your leave was approved',
        type: 'leave_approved',
        isRead: false,
        createdAt: DateTime.now(),
      );
      expect(leaveApproved.type, equals('leave_approved'));
      expect(leaveApproved.icon, isNotNull);
      expect(leaveApproved.iconColor, isNotNull);

      final taskUpdated = NotificationModel(
        id: '2',
        userId: 'u1',
        title: 'Task Updated',
        message: 'Your task was updated',
        type: 'task_updated',
        isRead: false,
        createdAt: DateTime.now(),
      );
      expect(taskUpdated.type, equals('task_updated'));
      expect(taskUpdated.icon, isNotNull);

      final taskCompleted = NotificationModel(
        id: '3',
        userId: 'u1',
        title: 'Task Completed',
        message: 'Task was completed',
        type: 'task_completed',
        isRead: false,
        createdAt: DateTime.now(),
      );
      expect(taskCompleted.type, equals('task_completed'));
      expect(taskCompleted.icon, isNotNull);
    });

    test('NotificationModel copyWith toggles isRead correctly', () {
      final notif = NotificationModel(
        id: '1',
        userId: 'u1',
        title: 'Title',
        message: 'Message',
        type: 'info',
        isRead: false,
        createdAt: DateTime.now(),
      );

      final readNotif = notif.copyWith(isRead: true);
      expect(readNotif.isRead, isTrue);
      expect(readNotif.id, equals(notif.id));
    });
  });

  group('Sprint 5 — Task Editing & Priorities', () {
    test('TaskItem supports all valid priorities and statuses', () {
      expect(TaskItem.validPriorities, containsAll(['low', 'medium', 'high', 'critical']));
      expect(TaskItem.validStatuses, containsAll(['pending', 'in_progress', 'completed', 'overdue', 'cancelled']));
    });

    test('TaskItem copyWith modifies fields without mutating originals', () {
      final original = TaskItem(
        id: 't-1',
        title: 'Initial Title',
        description: 'Initial Desc',
        assignedTo: 'staff-1',
        priority: 'low',
        status: 'pending',
        createdAt: DateTime(2026, 9, 20),
        updatedAt: DateTime(2026, 9, 20),
      );

      final updated = original.copyWith(
        title: 'Updated Title',
        assignedTo: 'staff-2',
        priority: 'critical',
        status: 'in_progress',
        dueDate: DateTime(2026, 9, 29),
      );

      expect(original.title, equals('Initial Title'));
      expect(original.assignedTo, equals('staff-1'));
      expect(original.priority, equals('low'));

      expect(updated.title, equals('Updated Title'));
      expect(updated.assignedTo, equals('staff-2'));
      expect(updated.priority, equals('critical'));
      expect(updated.status, equals('in_progress'));
      expect(updated.dueDate, isNotNull);
    });
  });
}
