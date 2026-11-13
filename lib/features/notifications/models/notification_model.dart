import 'package:flutter/material.dart';

import '../../../core/theme/app_colors.dart';

class NotificationModel {
  final String id;
  final String userId;
  final String title;
  final String message;
  final String type;
  final bool isRead;
  final String? relatedId;
  final DateTime createdAt;

  const NotificationModel({
    required this.id,
    required this.userId,
    required this.title,
    required this.message,
    required this.type,
    required this.isRead,
    this.relatedId,
    required this.createdAt,
  });

  NotificationModel copyWith({
    String? id,
    String? userId,
    String? title,
    String? message,
    String? type,
    bool? isRead,
    String? relatedId,
    DateTime? createdAt,
  }) {
    return NotificationModel(
      id: id ?? this.id,
      userId: userId ?? this.userId,
      title: title ?? this.title,
      message: message ?? this.message,
      type: type ?? this.type,
      isRead: isRead ?? this.isRead,
      relatedId: relatedId ?? this.relatedId,
      createdAt: createdAt ?? this.createdAt,
    );
  }

  factory NotificationModel.fromJson(Map<String, dynamic> json) {
    return NotificationModel(
      id: json['id']?.toString() ?? '',
      userId: json['user_id']?.toString() ?? '',
      title: json['title']?.toString() ?? '',
      message: json['message']?.toString() ?? '',
      type: json['type']?.toString() ?? 'info',
      isRead: json['is_read'] as bool? ?? false,
      relatedId: json['related_id']?.toString(),
      createdAt: json['created_at'] != null
          ? DateTime.tryParse(json['created_at'].toString()) ?? DateTime.now()
          : DateTime.now(),
    );
  }

  Map<String, dynamic> toJson() => {
        'id': id,
        'user_id': userId,
        'title': title,
        'message': message,
        'type': type,
        'is_read': isRead,
        'related_id': relatedId,
        'created_at': createdAt.toIso8601String(),
      };

  IconData get icon {
    switch (type) {
      case 'whatsapp_reply':
        return Icons.chat_bubble_outline;
      case 'appointment_rescheduled':
        return Icons.edit_calendar_outlined;
      case 'lab_ready':
        return Icons.biotech_outlined;
      case 'attendance_exception':
        return Icons.person_off_outlined;
      case 'inventory_alert':
        return Icons.inventory_2_outlined;
      case 'duty_assignment':
      case 'shift_change':
        return Icons.event_available_outlined;
      case 'leave_request':
        return Icons.event_busy_outlined;
      case 'leave_approved':
        return Icons.check_circle_outline;
      case 'leave_rejected':
        return Icons.cancel_outlined;
      case 'task_assigned':
      case 'eye_surgery_assigned':
        return Icons.assignment_ind_outlined;
      case 'task_updated':
        return Icons.edit_note_outlined;
      case 'task_completed':
        return Icons.task_alt_outlined;
      case 'task_overdue':
        return Icons.warning_amber_outlined;
      case 'appointment':
        return Icons.calendar_today_outlined;
      case 'low_stock':
        return Icons.warning_amber_rounded;
      case 'expiry':
        return Icons.event_busy_outlined;
      case 'system':
        return Icons.info_outline;
      case 'eye_surgery':
        return Icons.visibility_outlined;
      default:
        return Icons.notifications_none;
    }
  }

  Color get iconColor {
    switch (type) {
      case 'whatsapp_reply':
        return Colors.green;
      case 'appointment_rescheduled':
        return Colors.orange;
      case 'lab_ready':
        return Colors.purple;
      case 'attendance_exception':
        return Colors.redAccent;
      case 'inventory_alert':
        return AppColors.error;
      case 'duty_assignment':
      case 'shift_change':
        return AppColors.primary;
      case 'leave_request':
        return AppColors.secondary;
      case 'leave_approved':
        return AppColors.primaryContainer;
      case 'leave_rejected':
        return AppColors.error;
      case 'task_assigned':
      case 'eye_surgery_assigned':
        return AppColors.primary;
      case 'task_updated':
        return AppColors.secondary;
      case 'task_completed':
        return AppColors.primaryContainer;
      case 'task_overdue':
        return AppColors.error;
      case 'appointment':
        return AppColors.tertiary;
      case 'low_stock':
        return AppColors.error;
      case 'expiry':
        return const Color(0xFFE65100);
      case 'system':
        return AppColors.onSurfaceVariant;
      case 'eye_surgery':
        return AppColors.primary;
      default:
        return AppColors.primary;
    }
  }

  /// Relative time string for display.
  String get relativeTime {
    final diff = DateTime.now().difference(createdAt);
    if (diff.inMinutes < 1) return 'Just now';
    if (diff.inMinutes < 60) return '${diff.inMinutes}m ago';
    if (diff.inHours < 24) return '${diff.inHours}h ago';
    if (diff.inDays < 7) return '${diff.inDays}d ago';
    return '${createdAt.day}/${createdAt.month}/${createdAt.year}';
  }
}
