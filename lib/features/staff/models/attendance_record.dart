class AttendanceRecord {
  final String id;
  final String staffId;
  final DateTime date;
  DateTime get recordDate => date;
  final DateTime? checkInTime;
  final DateTime? checkOutTime;
  final String status;
  final bool isLate;
  final double? workingHours;
  final int lateMinutes;
  final String? notes;
  final String? staffName;
  final String shift; // 'morning' | 'night'

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
    this.shift = 'morning',
  });

  factory AttendanceRecord.fromJson(Map<String, dynamic> json) {
    final profile = json['profiles'] is Map ? json['profiles'] as Map<String, dynamic> : null;
    final rawDate = json['record_date'] ?? json['date'];
    final dateParsed = rawDate != null
        ? (DateTime.tryParse(rawDate.toString()) ?? DateTime.now())
        : DateTime.now();

    final checkInParsed = json['check_in_time'] != null
        ? DateTime.tryParse(json['check_in_time'].toString())
        : null;

    final checkOutParsed = json['check_out_time'] != null
        ? DateTime.tryParse(json['check_out_time'].toString())
        : null;

    return AttendanceRecord(
      id: json['id']?.toString() ?? '',
      staffId: json['staff_id']?.toString() ?? '',
      date: dateParsed,
      checkInTime: checkInParsed,
      checkOutTime: checkOutParsed,
      status: json['status']?.toString() ?? 'present',
      isLate: json['is_late'] == true,
      workingHours: json['working_hours'] != null
          ? (json['working_hours'] as num).toDouble()
          : null,
      lateMinutes: (json['late_minutes'] as num?)?.toInt() ?? 0,
      notes: json['notes']?.toString(),
      staffName: profile?['full_name']?.toString() ?? json['staff_name']?.toString(),
      shift: json['shift']?.toString().toLowerCase() ?? 'morning',
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
      'shift': shift,
    };
  }

  bool get isMorningShift => shift.toLowerCase() == 'morning';
  bool get isAfternoonShift =>
      shift.toLowerCase() == 'afternoon' ||
      shift.toLowerCase() == 'evening' ||
      shift.toLowerCase() == 'night';
  bool get isEveningShift => isAfternoonShift;
  bool get isNightShift => shift.toLowerCase() == 'night';

  String get shiftDisplayName {
    switch (shift.toLowerCase()) {
      case 'evening':
      case 'afternoon':
        return 'Evening Shift';
      case 'night':
        return 'Night Shift';
      case 'morning':
      default:
        return 'Morning Shift';
    }
  }

  String get shiftTimingDisplay {
    switch (shift.toLowerCase()) {
      case 'evening':
      case 'afternoon':
        return '01:00 PM – 09:00 PM';
      case 'night':
        return '11:00 PM – 07:00 AM';
      case 'morning':
      default:
        return '08:00 AM – 01:00 PM';
    }
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
