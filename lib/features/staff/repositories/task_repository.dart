import 'package:flutter/foundation.dart';
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
        .select('*, profiles!tasks_assigned_to_fkey(full_name)')
        .eq('assigned_to', staffId)
        .order('due_date', ascending: true);
        
    return (response as List).map((json) => TaskItem.fromJson(json)).toList();
  }

  Future<List<TaskItem>> fetchAllTasks() async {
    final response = await _supabase
        .from('tasks')
        .select('*, profiles!tasks_assigned_to_fkey(full_name)')
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

  static bool _isValidUuid(String? value) {
    if (value == null) return false;
    return RegExp(
      r'^[0-9a-fA-F]{8}-[0-9a-fA-F]{4}-[0-9a-fA-F]{4}-[0-9a-fA-F]{4}-[0-9a-fA-F]{12}$',
    ).hasMatch(value);
  }

  Future<void> createTask({
    required String title,
    String? description,
    required String assignedTo,
    required String assignedBy,
    DateTime? dueDate,
    String priority = 'medium',
  }) async {
    final cleanPriority = priority.toLowerCase();
    if (!TaskItem.validPriorities.contains(cleanPriority)) {
      throw ArgumentError('Invalid task priority: $priority');
    }

    final response = await _supabase.from('tasks').insert({
      'title': title.trim(),
      'description': description?.trim().isEmpty == true ? null : description?.trim(),
      'assigned_to': assignedTo,
      'assigned_by': assignedBy,
      'due_date': dueDate?.toIso8601String(),
      'priority': cleanPriority,
      'status': 'pending',
    }).select().single();
    
    final taskId = response['id'] as String?;
    final validTaskId = _isValidUuid(taskId) ? taskId : null;

    // Add history entry
    await _supabase.from('task_history').insert({
      'task_id': taskId,
      'changed_by': assignedBy,
      'old_status': 'created',
      'new_status': 'pending',
      'note': 'Task created and assigned',
    });

    // Notify assigned staff
    try {
      debugPrint('[TaskRepository] Creating notification for assigned staff user_id=$assignedTo for taskId=$taskId');
      await _notifyUser(
        userId: assignedTo,
        title: 'New Task Assigned',
        message: 'You have been assigned task "$title" (${cleanPriority.toUpperCase()} priority).',
        type: 'task_assigned',
        relatedId: validTaskId,
      );
    } catch (e) {
      debugPrint('[TaskRepository] FAILED to notify staff on task assignment: $e');
    }
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
    final cleanTitle = title.trim();
    if (cleanTitle.isEmpty) {
      throw ArgumentError('Task title cannot be empty.');
    }
    if (assignedTo.trim().isEmpty) {
      throw ArgumentError('Task must be assigned to a staff member.');
    }
    final cleanPriority = priority.toLowerCase();
    if (!TaskItem.validPriorities.contains(cleanPriority)) {
      throw ArgumentError('Invalid task priority: $priority');
    }
    final cleanStatus = status.toLowerCase();
    if (!TaskItem.validStatuses.contains(cleanStatus)) {
      throw ArgumentError('Invalid task status: $status');
    }

    // 1. Fetch current task state for history & reassignment detection
    final current = await _supabase
        .from('tasks')
        .select('assigned_to, status, title')
        .eq('id', taskId)
        .single();

    final oldAssignedTo = current['assigned_to'] as String?;
    final oldStatus = (current['status'] as String? ?? 'pending').toLowerCase();
    final oldTitle = current['title'] as String? ?? '';

    final Map<String, dynamic> updates = {
      'title': cleanTitle,
      'description': description?.trim().isEmpty == true ? null : description?.trim(),
      'assigned_to': assignedTo,
      'due_date': dueDate?.toIso8601String(),
      'priority': cleanPriority,
      'status': cleanStatus,
      'updated_at': DateTime.now().toIso8601String(),
    };

    if (cleanStatus == 'completed' && oldStatus != 'completed') {
      updates['completed_at'] = DateTime.now().toIso8601String();
    } else if (cleanStatus != 'completed' && oldStatus == 'completed') {
      updates['completed_at'] = null;
    }

    await _supabase.from('tasks').update(updates).eq('id', taskId);

    // 2. Add history entry
    final isReassigned = oldAssignedTo != null && oldAssignedTo != assignedTo;
    final isStatusChanged = oldStatus != cleanStatus;

    String historyNote = note?.trim() ?? '';
    if (historyNote.isEmpty) {
      final changeParts = <String>[];
      if (oldTitle != cleanTitle) changeParts.add('title updated');
      if (isReassigned) changeParts.add('reassigned');
      if (isStatusChanged) changeParts.add('status changed to $cleanStatus');
      historyNote = changeParts.isNotEmpty
          ? changeParts.join(', ')
          : 'Task details updated by admin';
    }

    await _supabase.from('task_history').insert({
      'task_id': taskId,
      'changed_by': adminId,
      'old_status': oldStatus,
      'new_status': cleanStatus,
      'note': historyNote,
    });

    // 3. Dispatch notifications
    try {
      final validTaskId = _isValidUuid(taskId) ? taskId : null;
      if (isReassigned) {
        debugPrint('[TaskRepository] Reassigning task $taskId from $oldAssignedTo to $assignedTo');
        // Notify newly assigned staff
        await _notifyUser(
          userId: assignedTo,
          title: 'New Task Assigned',
          message: 'You have been assigned task "$cleanTitle" (${cleanPriority.toUpperCase()} priority).',
          type: 'task_assigned',
          relatedId: validTaskId,
        );

        // Notify old assigned staff
        await _notifyUser(
          userId: oldAssignedTo,
          title: 'Task Reassigned',
          message: 'Task "$oldTitle" has been reassigned to another staff member.',
          type: 'task_updated',
          relatedId: validTaskId,
        );
        debugPrint('[TaskRepository] Task reassignment notifications sent successfully');
      } else {
        debugPrint('[TaskRepository] Sending task update notification to $assignedTo');
        // Notify assigned staff about updates
        await _notifyUser(
          userId: assignedTo,
          title: 'Task Updated',
          message: 'Task "$cleanTitle" has been updated by admin.',
          type: 'task_updated',
          relatedId: validTaskId,
        );
        debugPrint('[TaskRepository] Task update notification sent successfully');
      }
    } catch (e) {
      debugPrint('[TaskRepository] FAILED to dispatch update notification: $e');
    }
  }

  Future<void> updateTaskStatus(String taskId, String newStatus, String changedBy, String oldStatus, {String? note}) async {
    final cleanStatus = newStatus.toLowerCase();
    if (!TaskItem.validStatuses.contains(cleanStatus)) {
      throw ArgumentError('Invalid task status: $newStatus');
    }

    final Map<String, dynamic> updates = {
      'status': cleanStatus,
      'updated_at': DateTime.now().toIso8601String(),
    };
    if (cleanStatus == 'completed') {
      updates['completed_at'] = DateTime.now().toIso8601String();
    } else if (oldStatus.toLowerCase() == 'completed') {
      // Reopening task
      updates['completed_at'] = null; 
    }

    await _supabase.from('tasks').update(updates).eq('id', taskId);

    await _supabase.from('task_history').insert({
      'task_id': taskId,
      'changed_by': changedBy,
      'old_status': oldStatus,
      'new_status': cleanStatus,
      'note': note,
    });

    // Notify assigner on completion
    if (cleanStatus == 'completed') {
      try {
        final taskData = await _supabase
            .from('tasks')
            .select('assigned_by, title')
            .eq('id', taskId)
            .single();
        final assignerId = taskData['assigned_by'] as String?;
        final title = (taskData['title'] as String?) ?? 'Task';
        final validTaskId = _isValidUuid(taskId) ? taskId : null;

        debugPrint('[TaskRepository] Task completed: id=$taskId, assignerId=$assignerId, completedBy=$changedBy');

        bool rpcSuccess = false;
        try {
          await _supabase.rpc('notify_all_admins', params: {
            'p_title': 'Task Completed',
            'p_message': 'Task "$title" has been completed.',
            'p_type': 'task_completed',
            'p_related_id': validTaskId,
          });
          rpcSuccess = true;
          debugPrint('[TaskRepository] notify_all_admins RPC succeeded for completed task');
        } catch (rpcErr) {
          debugPrint('[TaskRepository] notify_all_admins RPC failed: $rpcErr');
        }

        // If RPC failed or assigner is not reached, ensure direct notification to assigner
        if (!rpcSuccess) {
          if (assignerId != null && assignerId != changedBy) {
            try {
              await _notifyUser(
                userId: assignerId,
                title: 'Task Completed',
                message: 'Task "$title" has been completed.',
                type: 'task_completed',
                relatedId: validTaskId,
              );
              debugPrint('[TaskRepository] Direct notification sent to assigner $assignerId');
            } catch (assignerErr) {
              debugPrint('[TaskRepository] Direct notification to assigner failed: $assignerErr');
            }
          }

          // Fallback: Also try notifying active admins directly
          try {
            final admins = await _supabase
                .from('profiles')
                .select('id')
                .eq('role', 'admin')
                .eq('is_active', true);
            for (final admin in (admins as List)) {
              final adminId = admin['id'] as String;
              if (adminId == assignerId || adminId == changedBy) continue;
              await _notifyUser(
                userId: adminId,
                title: 'Task Completed',
                message: 'Task "$title" has been completed.',
                type: 'task_completed',
                relatedId: validTaskId,
              );
            }
          } catch (adminErr) {
            debugPrint('[TaskRepository] Fallback admin notification failed: $adminErr');
          }
        }
      } catch (e) {
        debugPrint('[TaskRepository] FAILED in task completion notification flow: $e');
      }
    }
  }

  /// Internal helper to send a notification to a specific user,
  /// trying the SECURITY DEFINER RPC `notify_user` first, then direct insert.
  Future<void> _notifyUser({
    required String userId,
    required String title,
    required String message,
    required String type,
    String? relatedId,
  }) async {
    final validRelatedId = _isValidUuid(relatedId) ? relatedId : null;
    try {
      await _supabase.rpc('notify_user', params: {
        'p_user_id': userId,
        'p_title': title,
        'p_message': message,
        'p_type': type,
        'p_related_id': validRelatedId,
      });
      debugPrint('[TaskRepository SUCCESS] notify_user RPC sent notification to user $userId');
      return;
    } catch (rpcErr) {
      debugPrint('[TaskRepository] notify_user RPC unavailable ($rpcErr). Falling back to direct insert.');
    }

    await _supabase.from('notifications').insert({
      'user_id': userId,
      'title': title,
      'message': message,
      'type': type,
      if (validRelatedId != null) 'related_id': validRelatedId,
    });
    debugPrint('[TaskRepository SUCCESS] Direct notification inserted for user $userId');
  }
}
