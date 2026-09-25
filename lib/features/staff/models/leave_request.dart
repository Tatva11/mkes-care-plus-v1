class LeaveRequest {
  final String id;
  final String staffId;
  final String? staffName;
  final DateTime startDate;
  final DateTime endDate;
  final double leaveDays;
  final String reason;
  final String status;
  final String? approvedBy;
  final DateTime? approvedAt;
  final String? rejectionReason;
  final DateTime createdAt;

  LeaveRequest({
    required this.id,
    required this.staffId,
    this.staffName,
    required this.startDate,
    required this.endDate,
    required this.leaveDays,
    required this.reason,
    required this.status,
    this.approvedBy,
    this.approvedAt,
    this.rejectionReason,
    required this.createdAt,
  });

  static const List<String> validStatuses = ['pending', 'approved', 'rejected', 'cancelled'];

  static void validateSubmission({
    required DateTime? startDate,
    required DateTime? endDate,
    required String reason,
  }) {
    if (startDate == null) {
      throw ArgumentError('Start date is required.');
    }
    if (endDate == null) {
      throw ArgumentError('End date is required.');
    }
    if (endDate.isBefore(startDate)) {
      throw ArgumentError('End date cannot be before the start date.');
    }

    final trimmedReason = reason.trim();
    if (trimmedReason.isEmpty) {
      throw ArgumentError('Reason is required.');
    }
  }

  factory LeaveRequest.fromJson(Map<String, dynamic> json) {
    final profiles = json['profiles'];
    final staffName = profiles is Map<String, dynamic>
        ? (profiles['full_name'] as String?)
        : null;

    return LeaveRequest(
      id: json['id'] as String,
      staffId: json['staff_id'] as String,
      staffName: staffName,
      startDate: DateTime.parse(json['start_date'] as String),
      endDate: DateTime.parse(json['end_date'] as String),
      leaveDays: (json['leave_days'] as num).toDouble(),
      reason: json['reason'] as String,
      status: (json['status'] as String? ?? 'pending').toLowerCase(),
      approvedBy: json['approved_by'] as String?,
      approvedAt: json['approved_at'] != null ? DateTime.parse(json['approved_at'] as String) : null,
      rejectionReason: json['rejection_reason'] as String?,
      createdAt: DateTime.parse(json['created_at'] as String),
    );
  }

  Map<String, dynamic> toJson() {
    return {
      'id': id,
      'staff_id': staffId,
      'start_date': startDate.toIso8601String().split('T').first,
      'end_date': endDate.toIso8601String().split('T').first,
      'leave_days': leaveDays,
      'reason': reason,
      'status': status,
      'approved_by': approvedBy,
      'approved_at': approvedAt?.toIso8601String(),
      'rejection_reason': rejectionReason,
    };
  }

  String get statusLabel {
    switch (status.toLowerCase()) {
      case 'approved':
        return 'Approved';
      case 'rejected':
        return 'Rejected';
      case 'cancelled':
        return 'Cancelled';
      default:
        return 'Pending';
    }
  }
}
