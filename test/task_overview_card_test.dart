import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:flutter_test/flutter_test.dart';

import 'package:mkes_care/features/admin/widgets/task_overview_card.dart';
import 'package:mkes_care/features/staff/models/task_item.dart';
import 'package:mkes_care/features/staff/providers/task_provider.dart';

class TestAdminTasksNotifier extends StateNotifier<AsyncValue<List<TaskItem>>>
    implements AdminTasksNotifier {
  TestAdminTasksNotifier(super.initial);

  @override
  Future<void> fetchTasks({bool silent = false}) async {}

  @override
  Future<void> createTask({
    required String title,
    String? description,
    required String assignedTo,
    required String adminId,
    DateTime? dueDate,
    String priority = 'medium',
  }) async {}

  @override
  Future<void> updateTask({
    required String taskId,
    required String adminId,
    required String title,
    String? description,
    required String assignedTo,
    DateTime? dueDate,
    required String priority,
    required String status,
    String? note,
  }) async {}
}

void main() {
  TestWidgetsFlutterBinding.ensureInitialized();

  final now = DateTime.now();
  final todayEnd = DateTime(now.year, now.month, now.day, 23, 50);

  final todayCompletedTask = TaskItem(
    id: 't-1',
    title: 'Sterilize instruments',
    assignedTo: 'staff-1',
    status: 'completed',
    priority: 'high',
    dueDate: todayEnd,
    createdAt: now.subtract(const Duration(hours: 4)),
    updatedAt: now.subtract(const Duration(hours: 2)),
    completedAt: now.subtract(const Duration(hours: 2)),
  );

  final todayInProgressTask = TaskItem(
    id: 't-2',
    title: 'Prepare surgical tray',
    assignedTo: 'staff-2',
    status: 'in_progress',
    priority: 'medium',
    dueDate: todayEnd.subtract(const Duration(hours: 2)), // Later today
    createdAt: now.subtract(const Duration(hours: 2)),
    updatedAt: now.subtract(const Duration(hours: 1)),
  );

  final todayPendingTask = TaskItem(
    id: 't-3',
    title: 'Audit consumable stock',
    assignedTo: 'staff-3',
    status: 'pending',
    priority: 'low',
    dueDate: todayEnd.subtract(const Duration(hours: 1)), // Later today
    createdAt: now.subtract(const Duration(hours: 1)),
    updatedAt: now.subtract(const Duration(hours: 1)),
  );

  final yesterdayTask = TaskItem(
    id: 't-4',
    title: 'Past yesterday task',
    assignedTo: 'staff-1',
    status: 'pending',
    priority: 'critical',
    dueDate: now.subtract(
        const Duration(days: 1)), // Yesterday! Must NOT be in today's count
    createdAt: now.subtract(const Duration(days: 2)),
    updatedAt: now.subtract(const Duration(days: 2)),
  );

  final futureTask = TaskItem(
    id: 't-5',
    title: 'Future task',
    assignedTo: 'staff-2',
    status: 'pending',
    priority: 'low',
    dueDate: now
        .add(const Duration(days: 2)), // Future! Must NOT be in today's count
    createdAt: now.subtract(const Duration(hours: 1)),
    updatedAt: now.subtract(const Duration(hours: 1)),
  );

  final taskWithoutDueDate = TaskItem(
    id: 't-6',
    title: 'Clean storage shelves',
    assignedTo: 'staff-2',
    status: 'pending',
    priority: 'low',
    dueDate: null, // No due date: must NOT automatically be included
    createdAt: now.subtract(const Duration(days: 1)),
    updatedAt: now.subtract(const Duration(days: 1)),
  );

  group('TaskOverviewCard Tests', () {
    testWidgets(
        'Displays operational tasks (today incomplete + overdue carry-forward) and excludes completed/future/null',
        (tester) async {
      final allTasks = [
        todayCompletedTask,
        todayInProgressTask,
        todayPendingTask,
        yesterdayTask,
        futureTask,
        taskWithoutDueDate,
      ];

      await tester.pumpWidget(
        ProviderScope(
          overrides: [
            adminTasksProvider.overrideWith(
              (ref) => TestAdminTasksNotifier(AsyncValue.data(allTasks)),
            ),
          ],
          child: const MaterialApp(
            home: Scaffold(
              body: SingleChildScrollView(
                child: TaskOverviewCard(),
              ),
            ),
          ),
        ),
      );

      await tester.pumpAndSettle();

      // Today's Tasks title & count: 3 (todayInProgressTask, todayPendingTask, yesterdayTask). Completed, future, and null are excluded!
      expect(find.text("Today's Tasks"), findsOneWidget);
      expect(find.text('3'), findsOneWidget);

      // In Progress: 1 (todayInProgressTask)
      expect(find.text('In Progress: 1'), findsOneWidget);

      // Overdue: 1 (yesterdayTask carry-forward)
      expect(find.text('Overdue: 1'), findsOneWidget);

      // Subtitle indicates overdue from previous days
      expect(find.text('1 overdue from previous days'), findsOneWidget);
    });

    testWidgets('Displays graceful empty state when no pending tasks for today',
        (tester) async {
      await tester.pumpWidget(
        ProviderScope(
          overrides: [
            adminTasksProvider.overrideWith(
              (ref) => TestAdminTasksNotifier(const AsyncValue.data([])),
            ),
          ],
          child: const MaterialApp(
            home: Scaffold(
              body: SingleChildScrollView(
                child: TaskOverviewCard(),
              ),
            ),
          ),
        ),
      );

      await tester.pumpAndSettle();

      expect(find.text('No pending tasks for today'), findsOneWidget);
      expect(find.text('All staff tasks are up to date for today.'),
          findsOneWidget);
    });

    testWidgets('Handles error state with retry button', (tester) async {
      await tester.pumpWidget(
        ProviderScope(
          overrides: [
            adminTasksProvider.overrideWith(
              (ref) => TestAdminTasksNotifier(
                AsyncValue.error(
                  Exception('Network error connecting to tasks backend'),
                  StackTrace.empty,
                ),
              ),
            ),
          ],
          child: const MaterialApp(
            home: Scaffold(
              body: SingleChildScrollView(
                child: TaskOverviewCard(),
              ),
            ),
          ),
        ),
      );

      await tester.pumpAndSettle();

      expect(find.text('Unable to load task metrics'), findsOneWidget);
      expect(find.text('Retry'), findsOneWidget);
    });

    testWidgets('Navigation action invokes onNavigateToTasks callback',
        (tester) async {
      var navigated = false;

      await tester.pumpWidget(
        ProviderScope(
          overrides: [
            adminTasksProvider.overrideWith(
              (ref) =>
                  TestAdminTasksNotifier(AsyncValue.data([todayCompletedTask])),
            ),
          ],
          child: MaterialApp(
            home: Scaffold(
              body: SingleChildScrollView(
                child: TaskOverviewCard(
                  onNavigateToTasks: () => navigated = true,
                ),
              ),
            ),
          ),
        ),
      );

      await tester.pumpAndSettle();

      final viewAllBtn = find.text('View All Tasks');
      expect(viewAllBtn, findsOneWidget);

      await tester.tap(viewAllBtn);
      await tester.pumpAndSettle();

      expect(navigated, isTrue);
    });

    testWidgets('Renders cleanly on a small screen (360x640) without overflow',
        (tester) async {
      tester.view.physicalSize = const Size(360, 640);
      tester.view.devicePixelRatio = 1.0;
      addTearDown(tester.view.resetPhysicalSize);
      addTearDown(tester.view.resetDevicePixelRatio);

      final sampleTasks = [
        todayCompletedTask,
        todayInProgressTask,
        todayPendingTask,
      ];

      await tester.pumpWidget(
        ProviderScope(
          overrides: [
            adminTasksProvider.overrideWith(
              (ref) => TestAdminTasksNotifier(AsyncValue.data(sampleTasks)),
            ),
          ],
          child: const MaterialApp(
            home: Scaffold(
              body: SingleChildScrollView(
                child: TaskOverviewCard(),
              ),
            ),
          ),
        ),
      );

      await tester.pumpAndSettle();

      expect(tester.takeException(), isNull);
    });
  });
}
