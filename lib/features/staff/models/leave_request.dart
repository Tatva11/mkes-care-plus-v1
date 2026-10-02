class LeaveRequest {
  final String id;
  final String staffId;
  final String? staffName; // Populated when fetched with a profile join
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

  factory LeaveRequest.fromJson(Map<String, dynamic> json) {
    // The join key may be returned as 'profiles' when using
    // .select('*, profiles!leave_requests_staff_id_fkey(full_name)')
    final profileMap = json['profiles'] is Map
        ? json['profiles'] as Map<String, dynamic>
        : null;

    return LeaveRequest(
      id: json['id'] as String,
      staffId: json['staff_id'] as String,
      staffName: profileMap?['full_name'] as String?,
      startDate: DateTime.parse(json['start_date'] as String),
      endDate: DateTime.parse(json['end_date'] as String),
      leaveDays: (json['leave_days'] as num).toDouble(),
      reason: json['reason'] as String,
      status: json['status'] as String,
      approvedBy: json['approved_by'] as String?,
      approvedAt: json['approved_at'] != null
          ? DateTime.parse(json['approved_at'] as String)
          : null,
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
}
