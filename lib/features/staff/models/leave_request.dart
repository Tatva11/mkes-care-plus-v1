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
  final String dutyPeriod; // 'morning' | 'afternoon' | 'full_day'

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
    this.dutyPeriod = 'full_day',
  });

  bool get isMorningOnly => dutyPeriod.toLowerCase() == 'morning';
  bool get isAfternoonOnly =>
      dutyPeriod.toLowerCase() == 'afternoon' ||
      dutyPeriod.toLowerCase() == 'evening';
  bool get isEveningOnly => isAfternoonOnly;
  bool get isFullDay => dutyPeriod.toLowerCase() == 'full_day';

  String get dutyPeriodDisplayName {
    switch (dutyPeriod.toLowerCase()) {
      case 'morning':
        return 'Morning Duty Only';
      case 'evening':
      case 'afternoon':
        return 'Evening Duty Only';
      case 'full_day':
      default:
        return 'Full Day (All Duties)';
    }
  }

  /// Whether this leave request covers the specified [shift].
  bool coversShift(String shift) {
    final s = shift.toLowerCase();
    if (dutyPeriod.toLowerCase() == 'full_day') return true;
    if (dutyPeriod.toLowerCase() == 'morning' && s == 'morning') return true;
    if ((dutyPeriod.toLowerCase() == 'afternoon' || dutyPeriod.toLowerCase() == 'evening') &&
        (s == 'afternoon' || s == 'evening' || s == 'night')) {
      return true;
    }
    return false;
  }

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
      createdAt: json['created_at'] != null
          ? DateTime.parse(json['created_at'] as String)
          : DateTime.now(),
      dutyPeriod: (json['duty_period'] as String?)?.toLowerCase() ?? 'full_day',
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
      'duty_period': dutyPeriod,
      'created_at': createdAt.toIso8601String(),
    };
  }
}
