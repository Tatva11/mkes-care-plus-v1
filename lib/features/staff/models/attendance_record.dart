class AttendanceRecord {
  final String id;
  final String staffId;
  final DateTime date;
  final DateTime? checkInTime;
  final DateTime? checkOutTime;
  final String status;
  final bool isLate;
  final double? workingHours;
  final int lateMinutes;
  final String? notes;
  final String? staffName;

  AttendanceRecord({
    required this.id,
    required this.staffId,
    required this.date,
    this.checkInTime,
    this.checkOutTime,
    required this.status,
    required this.isLate,
    this.workingHours,
    required this.lateMinutes,
    this.notes,
    this.staffName,
  });

  factory AttendanceRecord.fromJson(Map<String, dynamic> json) {
    final profile = json['profiles'] is Map ? json['profiles'] as Map<String, dynamic> : null;
    return AttendanceRecord(
      id: json['id'] as String,
      staffId: json['staff_id'] as String,
      date: DateTime.parse(json['record_date'] as String),
      checkInTime: json['check_in_time'] != null ? DateTime.parse(json['check_in_time'] as String) : null,
      checkOutTime: json['check_out_time'] != null ? DateTime.parse(json['check_out_time'] as String) : null,
      status: json['status'] as String,
      isLate: json['is_late'] as bool? ?? false,
      workingHours: json['working_hours'] != null ? (json['working_hours'] as num).toDouble() : null,
      lateMinutes: json['late_minutes'] as int? ?? 0,
      notes: json['notes'] as String?,
      staffName: profile?['full_name'] as String? ?? json['staff_name'] as String?,
    );
  }

  Map<String, dynamic> toJson() {
    return {
      'id': id,
      'staff_id': staffId,
      'record_date': date.toIso8601String().split('T').first,
      'check_in_time': checkInTime?.toIso8601String(),
      'check_out_time': checkOutTime?.toIso8601String(),
      'status': status,
      'is_late': isLate,
      'working_hours': workingHours,
      'late_minutes': lateMinutes,
      'notes': notes,
    };
  }

  String get statusLabel {
    switch (status.toLowerCase()) {
      case 'present':
        return 'Present';
      case 'late':
        return 'Late';
      case 'absent':
        return 'Absent';
      case 'leave':
        return 'Leave';
      case 'holiday':
        return 'Holiday';
      default:
        return status;
    }
  }

  bool get isClockedIn => checkInTime != null && checkOutTime == null;

  bool get isCompleted => checkInTime != null && checkOutTime != null;
}
