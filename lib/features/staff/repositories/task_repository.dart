import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:supabase_flutter/supabase_flutter.dart';

import '../../../core/providers/supabase_provider.dart';
import '../models/task_item.dart';
import '../models/task_history_entry.dart';

final taskRepositoryProvider = Provider<TaskRepository>((ref) {
  return TaskRepository(ref.watch(supabaseProvider));
});

class TaskRepository {
  final SupabaseClient _supabase;

  TaskRepository(this._supabase);

  Future<List<TaskItem>> fetchStaffTasks(String staffId) async {
    final response = await _supabase
        .from('tasks')
        .select('*, profiles!tasks_assigned_to_fkey!inner(full_name, role)')
        .eq('assigned_to', staffId)
        .order('due_date', ascending: true);

    return (response as List).map((json) => TaskItem.fromJson(json)).toList();
  }

  Future<List<TaskItem>> fetchAllTasks() async {
    final response = await _supabase
        .from('tasks')
        .select('*, profiles!tasks_assigned_to_fkey!inner(full_name, role)')
        .eq('profiles.role', 'staff')
        .order('created_at', ascending: false);

    return (response as List).map((json) => TaskItem.fromJson(json)).toList();
  }

  Future<List<TaskHistoryEntry>> fetchTaskHistory(String taskId) async {
    final response = await _supabase
        .from('task_history')
        .select()
        .eq('task_id', taskId)
        .order('created_at', ascending: false);
        
    return (response as List).map((json) => TaskHistoryEntry.fromJson(json)).toList();
  }

  Future<void> createTask({
    required String title,
    String? description,
    required String assignedTo,
    required String assignedBy,
    DateTime? dueDate,
    String priority = 'medium',
  }) async {
    final trimmedTitle = title.trim();
    if (trimmedTitle.isEmpty) {
      throw ArgumentError('Task title is required.');
    }
    if (assignedTo.trim().isEmpty) {
      throw ArgumentError('A staff member must be selected.');
    }

    final normalizedPriority = priority.toLowerCase();
    if (!['low', 'medium', 'high', 'critical'].contains(normalizedPriority)) {
      throw ArgumentError('Invalid task priority.');
    }

    final response = await _supabase.from('tasks').insert({
      'title': trimmedTitle,
      'description': description?.trim().isEmpty == true ? null : description?.trim(),
      'assigned_to': assignedTo,
      'assigned_by': assignedBy,
      'due_date': dueDate?.toIso8601String().split('T').first,
      'priority': normalizedPriority,
      'status': 'pending',
    }).select().single();

    await _supabase.from('task_history').insert({
      'task_id': response['id'],
      'changed_by': assignedBy,
      'old_status': 'created',
      'new_status': 'pending',
      'note': 'Task created and assigned',
    });
  }

  Future<void> updateTaskStatus(String taskId, String newStatus, String changedBy, String oldStatus, {String? note}) async {
    final normalizedStatus = newStatus.toLowerCase();
    if (!TaskItem.validStatuses.contains(normalizedStatus)) {
      throw ArgumentError('Unsupported task status: $newStatus');
    }

    final currentTask = await _supabase
        .from('tasks')
        .select('status, assigned_to')
        .eq('id', taskId)
        .single();

    final currentStatus = (currentTask['status'] as String? ?? 'pending').toLowerCase();
    final assignedTo = currentTask['assigned_to'] as String?;

    if (assignedTo != null && assignedTo != changedBy) {
      throw Exception('You are not allowed to update this task.');
    }

    if (currentStatus == 'completed' && normalizedStatus != 'completed') {
      throw Exception('Completed tasks cannot be reopened.');
    }

    final Map<String, dynamic> updates = {
      'status': normalizedStatus,
      'updated_at': DateTime.now().toIso8601String(),
    };
    if (normalizedStatus == 'completed') {
      updates['completed_at'] = DateTime.now().toIso8601String();
    } else {
      updates['completed_at'] = null;
    }

    await _supabase.from('tasks').update(updates).eq('id', taskId);

    await _supabase.from('task_history').insert({
      'task_id': taskId,
      'changed_by': changedBy,
      'old_status': oldStatus,
      'new_status': normalizedStatus,
      'note': note,
    });
  }
}
