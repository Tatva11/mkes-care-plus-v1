import 'package:intl/intl.dart';

import '../../../core/utils/date_boundaries.dart';
import '../models/task_item.dart';

/// Authoritative filter and sorting logic for operational staff tasks.
///
/// Rules:
/// 1. Operational task list contains strictly:
///    - Tasks scheduled for today that are not completed or cancelled.
///    - Tasks from previous dates that remain incomplete (overdue carry-forward).
/// 2. Excludes:
///    - Completed tasks.
///    - Cancelled tasks.
///    - Future tasks before their scheduled/due date.
///    - Undated tasks (dueDate == null).
/// 3. Avoids duplicate entries.
/// 4. Overdue carry-forward tasks preserve their original due date.
/// 5. Overdue tasks are sorted by original due date ascending, then priority.
/// 6. Today's tasks are sorted by priority descending, then due time.
class TaskOperationalFilter {
  TaskOperationalFilter._();

  /// Filters tasks to only uncompleted tasks relevant to today:
  /// (today's incomplete tasks + previous-day incomplete carry-forward tasks).
  static List<TaskItem> filterOperationalTasks(
    List<TaskItem> tasks, {
    DateTime? referenceDate,
  }) {
    final now = referenceDate ?? DateTime.now();
    final startOfTomorrow = DateBoundaries.startOfTomorrow(now);

    final seenIds = <String>{};
    final operational = <TaskItem>[];

    for (final task in tasks) {
      // Undated tasks are not automatically included
      if (task.dueDate == null) continue;

      final status = task.status.toLowerCase().trim();
      // Exclude completed and cancelled tasks
      if (status == 'completed' || status == 'cancelled') continue;

      final dueLocal = task.dueDate!.toLocal();

      // Surgeries appear strictly as static schedule entries on their scheduled date.
      // Do not carry past surgery schedule entries forward as overdue tasks.
      if (task.isSurgeryTask) {
        if (!DateBoundaries.isToday(task.dueDate!, now)) {
          continue;
        }
      } else {
        // Exclude future tasks before their scheduled/due date
        if (!dueLocal.isBefore(startOfTomorrow)) continue;
      }

      // Avoid duplicates
      if (seenIds.add(task.id)) {
        operational.add(task);
      }
    }

    // Sort overdue tasks by original due date ascending, then priority.
    // Sort today's tasks by priority descending, then due time.
    operational.sort((a, b) {
      final aOverdue = isOverdueCarryForward(a, now);
      final bOverdue = isOverdueCarryForward(b, now);

      if (aOverdue && !bOverdue) return -1;
      if (!aOverdue && bOverdue) return 1;

      if (aOverdue && bOverdue) {
        final dateComp = a.dueDate!.compareTo(b.dueDate!);
        if (dateComp != 0) return dateComp;
        return _priorityWeight(b.priority)
            .compareTo(_priorityWeight(a.priority));
      }

      // Both today: sort by priority desc, then due time
      final pComp =
          _priorityWeight(b.priority).compareTo(_priorityWeight(a.priority));
      if (pComp != 0) return pComp;
      return a.dueDate!.compareTo(b.dueDate!);
    });

    return operational;
  }

  /// Whether [task] is an overdue carry-forward task from a previous calendar day.
  /// Scheduled surgeries are static schedule entries and must NEVER be treated as overdue carry-forward tasks.
  static bool isOverdueCarryForward(TaskItem task, [DateTime? referenceDate]) {
    if (task.isSurgeryTask) return false;
    if (task.dueDate == null) return false;
    final status = task.status.toLowerCase().trim();
    if (status == 'completed' || status == 'cancelled') return false;
    final now = referenceDate ?? DateTime.now();
    return task.dueDate!.toLocal().isBefore(DateBoundaries.startOfDay(now));
  }

  /// Formats the original due date indicator message, e.g. "Due on 16 Oct 2026".
  static String formatDueDateMessage(DateTime dueDate) {
    return 'Due on ${DateFormat('d MMM yyyy').format(dueDate)}';
  }

  static int _priorityWeight(String priority) {
    switch (priority.toLowerCase().trim()) {
      case 'critical':
        return 4;
      case 'high':
        return 3;
      case 'medium':
        return 2;
      case 'low':
      default:
        return 1;
    }
  }
}
