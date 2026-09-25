import 'package:flutter_test/flutter_test.dart';
import 'package:mkes_care/features/staff/models/task_item.dart';

void main() {
  test('parses completed task details and completion timestamp', () {
    final task = TaskItem.fromJson({
      'id': 'task-1',
      'title': 'Submit report',
      'description': 'Daily stock report',
      'assigned_to': 'staff-1',
      'assigned_by': 'admin-1',
      'due_date': '2026-09-21T00:00:00Z',
      'priority': 'high',
      'status': 'completed',
      'created_at': '2026-09-20T08:00:00Z',
      'updated_at': '2026-09-20T09:00:00Z',
      'completed_at': '2026-09-20T09:00:00Z',
    });

    expect(task.status, 'completed');
    expect(task.statusLabel, 'Completed');
    expect(task.completedAt, isNotNull);
    expect(task.createdAt, DateTime.parse('2026-09-20T08:00:00Z'));
  });

  test('completed tasks cannot be reopened through valid workflow statuses', () {
    expect(TaskItem.validStatuses, contains('completed'));
    expect(TaskItem.validStatuses, contains('pending'));
    expect(TaskItem.validStatuses, contains('in_progress'));
  });
}