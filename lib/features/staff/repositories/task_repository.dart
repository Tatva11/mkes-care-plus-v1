import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:supabase_flutter/supabase_flutter.dart';

import '../../../core/providers/supabase_provider.dart';
import '../models/task_item.dart';

final taskRepositoryProvider = Provider<TaskRepository>((ref) {
  return TaskRepository(ref.watch(supabaseProvider));
});

class TaskRepository {
  final SupabaseClient _supabase;

  TaskRepository(this._supabase);

  Future<List<TaskItem>> fetchStaffTasks(String staffId) async {
    final response = await _supabase
        .from('tasks')
        .select()
        .eq('assigned_to', staffId)
        .order('due_date', ascending: true);

    return (response as List).map((json) => TaskItem.fromJson(json)).toList();
  }

  Future<List<TaskItem>> fetchAllTasks() async {
    final response = await _supabase
        .from('tasks')
        .select()
        .order('created_at', ascending: false);

    return (response as List).map((json) => TaskItem.fromJson(json)).toList();
  }

  Future<void> createTask({
    required String title,
    String? description,
    required String assignedTo,
    required String assignedBy,
    DateTime? dueDate,
    String priority = 'medium',
  }) async {
    final response = await _supabase
        .from('tasks')
        .insert({
          'title': title,
          'description': description,
          'assigned_to': assignedTo,
          'assigned_by': assignedBy,
          'due_date': dueDate?.toIso8601String(),
          'priority': priority,
          'status': 'pending',
        })
        .select()
        .single();

    // Add history entry
    await _supabase.from('task_history').insert({
      'task_id': response['id'],
      'changed_by': assignedBy,
      'old_status': 'created',
      'new_status': 'pending',
      'note': 'Task created and assigned',
    });
  }

  Future<void> updateTaskStatus(
      String taskId, String newStatus, String changedBy, String oldStatus,
      {String? note}) async {
    final Map<String, dynamic> updates = {
      'status': newStatus,
      'updated_at': DateTime.now().toIso8601String(),
    };
    if (newStatus == 'completed') {
      updates['completed_at'] = DateTime.now().toIso8601String();
    } else if (oldStatus == 'completed') {
      // Reopening task
      updates['completed_at'] = null;
    }

    await _supabase.from('tasks').update(updates).eq('id', taskId);

    await _supabase.from('task_history').insert({
      'task_id': taskId,
      'changed_by': changedBy,
      'old_status': oldStatus,
      'new_status': newStatus,
      'note': note,
    });
  }
}
