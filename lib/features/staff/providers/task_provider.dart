import 'package:flutter_riverpod/flutter_riverpod.dart';

import '../models/task_item.dart';
import '../repositories/task_repository.dart';

final staffTasksProvider = StateNotifierProvider.family<StaffTasksNotifier, AsyncValue<List<TaskItem>>, String>((ref, staffId) {
  final repo = ref.watch(taskRepositoryProvider);
  return StaffTasksNotifier(repo, staffId);
});

class StaffTasksNotifier extends StateNotifier<AsyncValue<List<TaskItem>>> {
  final TaskRepository _repository;
  final String _staffId;

  StaffTasksNotifier(this._repository, this._staffId) : super(const AsyncValue.loading()) {
    fetchTasks();
  }

  Future<void> fetchTasks() async {
    state = const AsyncValue.loading();
    try {
      final tasks = await _repository.fetchStaffTasks(_staffId);
      
      // Auto-detect overdue tasks (that are not yet marked as overdue in DB)
      // For Sprint 2 we do it mostly in UI logic, but here we can just pass them as they are.
      state = AsyncValue.data(tasks);
    } catch (e, st) {
      state = AsyncValue.error(e, st);
    }
  }

  Future<void> completeTask(String taskId, String oldStatus) async {
    await _repository.updateTaskStatus(
      taskId,
      'completed',
      _staffId,
      oldStatus,
      note: 'Task marked as completed by staff member',
    );
    await fetchTasks();
  }
}

final adminTasksProvider = StateNotifierProvider<AdminTasksNotifier, AsyncValue<List<TaskItem>>>((ref) {
  final repo = ref.watch(taskRepositoryProvider);
  return AdminTasksNotifier(repo);
});

class AdminTasksNotifier extends StateNotifier<AsyncValue<List<TaskItem>>> {
  final TaskRepository _repository;

  AdminTasksNotifier(this._repository) : super(const AsyncValue.loading()) {
    fetchTasks();
  }

  Future<void> fetchTasks() async {
    state = const AsyncValue.loading();
    try {
      final tasks = await _repository.fetchAllTasks();
      state = AsyncValue.data(tasks);
    } catch (e, st) {
      state = AsyncValue.error(e, st);
    }
  }

  Future<void> createTask({
    required String title,
    String? description,
    required String assignedTo,
    required String adminId,
    DateTime? dueDate,
    String priority = 'medium',
  }) async {
    await _repository.createTask(
      title: title,
      description: description,
      assignedTo: assignedTo,
      assignedBy: adminId,
      dueDate: dueDate,
      priority: priority,
    );
    await fetchTasks();
  }
}
