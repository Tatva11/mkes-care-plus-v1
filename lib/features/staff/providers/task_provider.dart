import 'package:flutter/foundation.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:supabase_flutter/supabase_flutter.dart';

import '../../../core/providers/supabase_provider.dart';
import '../models/task_item.dart';
import '../repositories/task_repository.dart';

final staffTasksProvider = StateNotifierProvider.family<StaffTasksNotifier, AsyncValue<List<TaskItem>>, String>((ref, staffId) {
  final repo = ref.watch(taskRepositoryProvider);
  final supabase = ref.watch(supabaseProvider);
  return StaffTasksNotifier(repo, supabase, staffId);
});

class StaffTasksNotifier extends StateNotifier<AsyncValue<List<TaskItem>>> {
  final TaskRepository _repository;
  final SupabaseClient _supabase;
  final String _staffId;
  RealtimeChannel? _realtimeChannel;

  StaffTasksNotifier(
    this._repository,
    this._supabase,
    this._staffId, {
    bool enableRealtime = true,
  }) : super(const AsyncValue.loading()) {
    fetchTasks();
    if (enableRealtime) {
      _setupRealtime();
    }
  }

  void _setupRealtime() {
    try {
      _realtimeChannel = _supabase
          .channel('public:tasks:$_staffId')
          .onPostgresChanges(
            event: PostgresChangeEvent.all,
            schema: 'public',
            table: 'tasks',
            callback: (payload) {
              fetchTasks(silent: true);
            },
          )
          .subscribe();
    } catch (e) {
      debugPrint('StaffTasksNotifier: realtime subscription error: $e');
    }
  }

  @override
  void dispose() {
    _realtimeChannel?.unsubscribe();
    super.dispose();
  }

  Future<void> fetchTasks({bool silent = false}) async {
    if (!silent) {
      state = const AsyncValue.loading();
    }
    try {
      final tasks = await _repository.fetchStaffTasks(_staffId);
      state = AsyncValue.data(tasks);
    } catch (e, st) {
      if (!silent) {
        state = AsyncValue.error(e, st);
      }
    }
  }

  Future<void> updateStatus(String taskId, String newStatus, String oldStatus, {String? note}) async {
    await _repository.updateTaskStatus(taskId, newStatus, _staffId, oldStatus, note: note);
    await fetchTasks();
  }
}

final adminTasksProvider = StateNotifierProvider<AdminTasksNotifier, AsyncValue<List<TaskItem>>>((ref) {
  final repo = ref.watch(taskRepositoryProvider);
  final supabase = ref.watch(supabaseProvider);
  return AdminTasksNotifier(repo, supabase);
});

class AdminTasksNotifier extends StateNotifier<AsyncValue<List<TaskItem>>> {
  final TaskRepository _repository;
  final SupabaseClient _supabase;
  RealtimeChannel? _realtimeChannel;

  AdminTasksNotifier(this._repository, this._supabase) : super(const AsyncValue.loading()) {
    fetchTasks();
    _setupRealtime();
  }

  void _setupRealtime() {
    try {
      _realtimeChannel = _supabase
          .channel('public:admin_tasks')
          .onPostgresChanges(
            event: PostgresChangeEvent.all,
            schema: 'public',
            table: 'tasks',
            callback: (payload) {
              fetchTasks(silent: true);
            },
          )
          .subscribe();
    } catch (e) {
      debugPrint('AdminTasksNotifier: realtime subscription error: $e');
    }
  }

  @override
  void dispose() {
    _realtimeChannel?.unsubscribe();
    super.dispose();
  }

  Future<void> fetchTasks({bool silent = false}) async {
    if (!silent) {
      state = const AsyncValue.loading();
    }
    try {
      final tasks = await _repository.fetchAllTasks();
      state = AsyncValue.data(tasks);
    } catch (e, st) {
      if (!silent) {
        state = AsyncValue.error(e, st);
      }
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
  }) async {
    await _repository.updateTask(
      taskId: taskId,
      adminId: adminId,
      title: title,
      description: description,
      assignedTo: assignedTo,
      dueDate: dueDate,
      priority: priority,
      status: status,
      note: note,
    );
    await fetchTasks();
  }
}
