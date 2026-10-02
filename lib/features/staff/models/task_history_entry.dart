class TaskHistoryEntry {
  final String id;
  final String taskId;
  final String changedBy;
  final String oldStatus;
  final String newStatus;
  final String? note;
  final DateTime createdAt;

  TaskHistoryEntry({
    required this.id,
    required this.taskId,
    required this.changedBy,
    required this.oldStatus,
    required this.newStatus,
    this.note,
    required this.createdAt,
  });

  factory TaskHistoryEntry.fromJson(Map<String, dynamic> json) {
    return TaskHistoryEntry(
      id: json['id'] as String,
      taskId: json['task_id'] as String,
      changedBy: json['changed_by'] as String,
      oldStatus: json['old_status'] as String,
      newStatus: json['new_status'] as String,
      note: json['note'] as String?,
      createdAt: DateTime.parse(json['created_at'] as String),
    );
  }
}
