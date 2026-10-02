class TaskItem {
  static const List<String> validStatuses = [
    'pending',
    'in_progress',
    'completed',
    'overdue',
    'cancelled',
  ];

  static const List<String> validPriorities = [
    'low',
    'medium',
    'high',
    'critical',
  ];

  final String id;
  final String title;
  final String? description;
  final String assignedTo;
  final String? assignedBy;
  final String? staffName;
  final DateTime? dueDate;
  final String priority; // 'low', 'medium', 'high', 'critical'
  final String status; // 'pending', 'in_progress', 'completed', 'overdue', 'cancelled'
  final DateTime createdAt;
  final DateTime updatedAt;
  final DateTime? completedAt;

  TaskItem({
    required this.id,
    required this.title,
    this.description,
    required this.assignedTo,
    this.assignedBy,
    this.staffName,
    this.dueDate,
    required this.priority,
    required this.status,
    required this.createdAt,
    required this.updatedAt,
    this.completedAt,
  });

  TaskItem copyWith({
    String? id,
    String? title,
    String? description,
    String? assignedTo,
    String? assignedBy,
    String? staffName,
    DateTime? dueDate,
    String? priority,
    String? status,
    DateTime? createdAt,
    DateTime? updatedAt,
    DateTime? completedAt,
  }) {
    return TaskItem(
      id: id ?? this.id,
      title: title ?? this.title,
      description: description ?? this.description,
      assignedTo: assignedTo ?? this.assignedTo,
      assignedBy: assignedBy ?? this.assignedBy,
      staffName: staffName ?? this.staffName,
      dueDate: dueDate ?? this.dueDate,
      priority: priority ?? this.priority,
      status: status ?? this.status,
      createdAt: createdAt ?? this.createdAt,
      updatedAt: updatedAt ?? this.updatedAt,
      completedAt: completedAt ?? this.completedAt,
    );
  }

  factory TaskItem.fromJson(Map<String, dynamic> json) {
    final profiles = json['profiles'];
    final staffName = profiles is Map<String, dynamic>
        ? (profiles['full_name'] as String?)
        : null;

    return TaskItem(
      id: json['id'] as String,
      title: json['title'] as String,
      description: json['description'] as String?,
      assignedTo: json['assigned_to'] as String,
      assignedBy: json['assigned_by'] as String?,
      staffName: staffName,
      dueDate: json['due_date'] != null ? DateTime.parse(json['due_date'] as String) : null,
      priority: (json['priority'] as String? ?? 'medium').toLowerCase(),
      status: (json['status'] as String? ?? 'pending').toLowerCase(),
      createdAt: DateTime.parse(json['created_at'] as String),
      updatedAt: DateTime.parse(json['updated_at'] as String),
      completedAt: json['completed_at'] != null ? DateTime.parse(json['completed_at'] as String) : null,
    );
  }

  bool get isOverdue {
    if (status == 'completed' || status == 'cancelled') return false;
    if (dueDate == null) return false;
    return dueDate!.isBefore(DateTime.now());
  }

  String get statusLabel {
    switch (status.toLowerCase()) {
      case 'in_progress':
        return 'In Progress';
      case 'completed':
        return 'Completed';
      case 'overdue':
        return 'Overdue';
      case 'cancelled':
        return 'Cancelled';
      default:
        return 'Pending';
    }
  }

  Map<String, dynamic> toJson() {
    return {
      'id': id,
      'title': title,
      'description': description,
      'assigned_to': assignedTo,
      'assigned_by': assignedBy,
      'due_date': dueDate?.toIso8601String(),
      'priority': priority,
      'status': status,
    };
  }
}
