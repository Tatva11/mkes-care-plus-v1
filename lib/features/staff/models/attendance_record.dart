import 'package:intl/intl.dart';

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
        ? DateTime.tryParse(json['check_in_time'].toString())?.toLocal()
        : null;

    final checkOutParsed = json['check_out_time'] != null
        ? DateTime.tryParse(json['check_out_time'].toString())?.toLocal()
        : null;

    double? workingHoursParsed = json['working_hours'] != null
        ? (json['working_hours'] as num).toDouble()
        : null;

    if ((workingHoursParsed == null || workingHoursParsed <= 0.0) &&
        checkInParsed != null &&
        checkOutParsed != null) {
      if (checkOutParsed.isAfter(checkInParsed)) {
        final diffMinutes = checkOutParsed.difference(checkInParsed).inMinutes;
        if (diffMinutes > 0) {
          workingHoursParsed =
              double.parse((diffMinutes / 60.0).clamp(0.0, 24.0).toStringAsFixed(2));
        }
      } else {
        // Handle timezone anomaly where check_in was recorded with wall-clock time as UTC
        // e.g. 18:50 was saved as 18:50Z instead of 13:20Z, while 21:00 local was converted to 15:30Z.
        final rawCheckIn = json['check_in_time']?.toString() ?? '';
        final wallIn = DateTime.tryParse(rawCheckIn);
        if (wallIn != null) {
          final inTotalMin = wallIn.hour * 60 + wallIn.minute;
          final outTotalMin = checkOutParsed.hour * 60 + checkOutParsed.minute;
          if (outTotalMin > inTotalMin) {
            final diff = outTotalMin - inTotalMin;
            workingHoursParsed =
                double.parse((diff / 60.0).clamp(0.0, 24.0).toStringAsFixed(2));
          }
        }
      }
    }

    return AttendanceRecord(
      id: json['id']?.toString() ?? '',
      staffId: json['staff_id']?.toString() ?? '',
      date: dateParsed,
      checkInTime: checkInParsed,
      checkOutTime: checkOutParsed,
      status: json['status']?.toString() ?? 'present',
      isLate: json['is_late'] == true,
      workingHours: workingHoursParsed,
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

  /// Formatted duration in standard human-readable format e.g. "2h 10m" or "5h" or "45m"
  String get formattedWorkingDuration {
    if (workingHours == null || workingHours! <= 0.0) return '—';
    final totalMinutes = (workingHours! * 60).round();
    final hours = totalMinutes ~/ 60;
    final minutes = totalMinutes % 60;
    if (hours == 0) return '${minutes}m';
    if (minutes == 0) return '${hours}h';
    return '${hours}h ${minutes}m';
  }

  /// Always displays check-in time converted to local clinic time
  String get formattedCheckInTime {
    if (checkInTime == null) return '—';
    return DateFormat('hh:mm a').format(checkInTime!.toLocal());
  }

  /// Always displays clock-out time converted to local clinic time
  String get formattedCheckOutTime {
    if (checkOutTime == null) return '—';
    return DateFormat('hh:mm a').format(checkOutTime!.toLocal());
  }
}

/// Represents one consolidated daily attendance summary for a staff member.
/// When assigned both morning and evening duties, consolidates both shift sessions
/// into one daily record, summing actual working durations and excluding breaks.
class DailyAttendanceSummary {
  final DateTime date;
  final String staffId;
  final List<AttendanceRecord> sessions;
  final String? staffName;

  DailyAttendanceSummary({
    required this.date,
    required this.staffId,
    required this.sessions,
    this.staffName,
  });

  bool get hasMultipleSessions => sessions.length > 1;

  AttendanceRecord? get morningSession =>
      sessions.where((s) => s.isMorningShift).firstOrNull;

  AttendanceRecord? get eveningSession =>
      sessions.where((s) => s.isEveningShift).firstOrNull;

  /// Total working hours calculated by summing actual shift session durations.
  /// The break between morning and evening shifts is strictly excluded.
  double get totalWorkingHours {
    double total = 0.0;
    for (final s in sessions) {
      if (s.workingHours != null && s.workingHours! > 0) {
        total += s.workingHours!;
      }
    }
    return double.parse(total.toStringAsFixed(2));
  }

  /// Formatted duration in human-readable format e.g. "7h 10m" or "5h"
  String get formattedTotalDuration {
    final totalHours = totalWorkingHours;
    if (totalHours <= 0.0) return '—';
    final totalMinutes = (totalHours * 60).round();
    final hours = totalMinutes ~/ 60;
    final minutes = totalMinutes % 60;
    if (hours == 0) return '${minutes}m';
    if (minutes == 0) return '${hours}h';
    return '${hours}h ${minutes}m';
  }

  String get dailyStatus {
    if (sessions.any((s) => s.status.toLowerCase() == 'present')) return 'present';
    if (sessions.any((s) => s.status.toLowerCase() == 'late')) return 'late';
    if (sessions.any((s) => s.status.toLowerCase() == 'leave')) return 'leave';
    if (sessions.any((s) => s.status.toLowerCase() == 'holiday')) return 'holiday';
    if (sessions.any((s) => s.status.toLowerCase() == 'absent')) return 'absent';
    return sessions.firstOrNull?.status ?? 'present';
  }

  String get statusLabel {
    switch (dailyStatus.toLowerCase()) {
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
        return dailyStatus;
    }
  }

  bool get isLate => sessions.any((s) => s.isLate);

  int get totalLateMinutes =>
      sessions.fold(0, (sum, s) => sum + s.lateMinutes);

  String get shiftDisplayName {
    if (hasMultipleSessions) {
      return 'Both Duties (M+E)';
    }
    return sessions.firstOrNull?.shiftDisplayName ?? 'Morning Shift';
  }
}

extension AttendanceGrouping on List<AttendanceRecord> {
  /// Consolidates flat shift records into distinct daily summaries per date.
  List<DailyAttendanceSummary> groupIntoDailySummaries() {
    final Map<String, List<AttendanceRecord>> map = {};
    for (final r in this) {
      final key =
          '${r.date.year}-${r.date.month.toString().padLeft(2, '0')}-${r.date.day.toString().padLeft(2, '0')}';
      map.putIfAbsent(key, () => []).add(r);
    }

    final List<DailyAttendanceSummary> result = [];
    for (final entry in map.entries) {
      final dateRecords = entry.value;
      // Sort morning first, then evening
      dateRecords.sort((a, b) => a.isMorningShift ? -1 : 1);
      result.add(DailyAttendanceSummary(
        date: dateRecords.first.date,
        staffId: dateRecords.first.staffId,
        sessions: dateRecords,
        staffName: dateRecords.first.staffName,
      ));
    }
    result.sort((a, b) => b.date.compareTo(a.date));
    return result;
  }
}
