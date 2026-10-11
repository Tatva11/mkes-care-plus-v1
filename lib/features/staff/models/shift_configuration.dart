import 'package:flutter/material.dart';

class ShiftConfiguration {
  final String name; // 'morning' | 'afternoon'
  final String startTime; // 'HH:mm', e.g. '08:00'
  final String endTime; // 'HH:mm', e.g. '13:00'
  final int gracePeriodMinutes;
  final DateTime? updatedAt;

  /// Backward-compatible alias for [name].
  String get shift => name;

  const ShiftConfiguration({
    String? shift,
    String? name,
    required this.startTime,
    required this.endTime,
    this.gracePeriodMinutes = 15,
    this.updatedAt,
  }) : name = name ?? shift ?? 'morning';

  static const ShiftConfiguration defaultMorning = ShiftConfiguration(
    shift: 'morning',
    name: 'morning',
    startTime: '08:00',
    endTime: '13:00',
    gracePeriodMinutes: 15,
  );

  static const ShiftConfiguration defaultAfternoon = ShiftConfiguration(
    shift: 'afternoon',
    name: 'afternoon',
    startTime: '13:00',
    endTime: '21:00',
    gracePeriodMinutes: 15,
  );

  /// Primary Evening shift alias (same as defaultAfternoon)
  static const ShiftConfiguration defaultEvening = defaultAfternoon;

  /// Backward compatibility alias for legacy tests/code
  static const ShiftConfiguration defaultNight = ShiftConfiguration(
    shift: 'night',
    name: 'night',
    startTime: '23:00',
    endTime: '07:00',
    gracePeriodMinutes: 15,
  );

  String get displayName {
    switch (name.toLowerCase()) {
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

  factory ShiftConfiguration.fromJson(Map<String, dynamic> json) {
    final rawName = (json['name'] as String?)?.toLowerCase() ??
        (json['shift'] as String?)?.toLowerCase() ??
        'morning';
    final normalized = (rawName == 'night' || rawName == 'evening') ? 'afternoon' : rawName;

    return ShiftConfiguration(
      shift: normalized,
      name: normalized,
      startTime: json['start_time'] as String? ??
          (normalized == 'afternoon' ? '13:00' : '08:00'),
      endTime: json['end_time'] as String? ??
          (normalized == 'afternoon' ? '21:00' : '13:00'),
      gracePeriodMinutes: json['grace_period_minutes'] as int? ?? 15,
      updatedAt: json['updated_at'] != null
          ? DateTime.tryParse(json['updated_at'] as String)
          : null,
    );
  }

  /// Maps strictly to Supabase `shift_configurations` table schema:
  /// (name, start_time, end_time, grace_period_minutes, updated_at).
  /// Note: The table has column 'name', NOT 'shift'.
  Map<String, dynamic> toJson() {
    return {
      'name': name.toLowerCase(),
      'start_time': startTime,
      'end_time': endTime,
      'grace_period_minutes': gracePeriodMinutes,
      'updated_at': DateTime.now().toUtc().toIso8601String(),
    };
  }

  TimeOfDay get startHourMinute => _parseTime(startTime);
  TimeOfDay get endHourMinute => _parseTime(endTime);

  static TimeOfDay _parseTime(String timeStr) {
    final parts = timeStr.trim().split(':');
    if (parts.length >= 2) {
      final hour = int.tryParse(parts[0]) ?? 0;
      final minute = int.tryParse(parts[1]) ?? 0;
      return TimeOfDay(hour: hour, minute: minute);
    }
    return const TimeOfDay(hour: 0, minute: 0);
  }

  static int _timeToMinutes(String timeStr) {
    final tod = _parseTime(timeStr);
    return tod.hour * 60 + tod.minute;
  }

  /// Whether current [time] is strictly within the shift duration.
  bool isTimeWithinShift(DateTime time) {
    final start = _timeToMinutes(startTime);
    final end = _timeToMinutes(endTime);
    final current = time.hour * 60 + time.minute;

    if (start <= end) {
      // Day shift (e.g. 07:00 to 15:00)
      return current >= start && current <= end;
    } else {
      // Overnight shift crossing midnight (e.g. 23:00 to 07:00)
      return current >= start || current <= end;
    }
  }

  /// Shift check-in eligibility:
  /// Staff can clock in starting up to 30 minutes before shift starts,
  /// and throughout the shift duration.
  bool isEligibleForCheckIn(DateTime time) {
    final start = _timeToMinutes(startTime);
    final end = _timeToMinutes(endTime);
    final current = time.hour * 60 + time.minute;
    final earlyStart = (start - 30 + 1440) % 1440;

    if (start <= end) {
      if (earlyStart <= start) {
        return current >= earlyStart && current <= end;
      } else {
        // In case earlyStart crosses midnight backwards (e.g. 00:15 -> 23:45)
        return current >= earlyStart || current <= end;
      }
    } else {
      // Overnight shift crossing midnight
      return current >= earlyStart || current <= end;
    }
  }

  /// Computes the logical shift date (YYYY-MM-DD format as DateTime).
  /// For shifts crossing midnight (e.g. 23:00 to 07:00):
  /// times between 00:00 and shift end belong to the date the shift started.
  DateTime getLogicalShiftDate(DateTime time) {
    final start = _timeToMinutes(startTime);
    final end = _timeToMinutes(endTime);
    final current = time.hour * 60 + time.minute;

    if (start > end && current <= end) {
      // Overnight shift, after midnight
      return DateTime(time.year, time.month, time.day).subtract(const Duration(days: 1));
    }
    return DateTime(time.year, time.month, time.day);
  }

  String getLogicalShiftDateStr(DateTime time) {
    final d = getLogicalShiftDate(time);
    return '${d.year.toString().padLeft(4, '0')}-'
        '${d.month.toString().padLeft(2, '0')}-'
        '${d.day.toString().padLeft(2, '0')}';
  }

  /// Calculates late minutes. If check-in is after start time + grace period,
  /// returns number of minutes past start time.
  int calculateLateMinutes(DateTime time) {
    final start = _timeToMinutes(startTime);
    final end = _timeToMinutes(endTime);
    final current = time.hour * 60 + time.minute;

    if (start <= end) {
      // Day shift
      if (current > start + gracePeriodMinutes) {
        return current - start;
      }
      return 0;
    } else {
      // Overnight shift
      if (current >= start) {
        if (current > start + gracePeriodMinutes) {
          return current - start;
        }
        return 0;
      } else if (current <= end) {
        // Checked in after midnight for an overnight shift
        final diff = (1440 - start) + current;
        if (diff > gracePeriodMinutes) {
          return diff;
        }
        return 0;
      }
      return 0;
    }
  }

  /// Returns the exact [DateTime] when the shift ends for a session that began at [sessionCheckIn].
  DateTime getShiftEndDateTime(DateTime sessionCheckIn) {
    final start = _timeToMinutes(startTime);
    final end = _timeToMinutes(endTime);
    final logicalDate = getLogicalShiftDate(sessionCheckIn);
    final endTod = _parseTime(endTime);

    if (start <= end) {
      // Day shift: ends on the same date
      return DateTime(logicalDate.year, logicalDate.month, logicalDate.day, endTod.hour, endTod.minute);
    } else {
      // Overnight shift: ends on next date
      final nextDay = logicalDate.add(const Duration(days: 1));
      return DateTime(nextDay.year, nextDay.month, nextDay.day, endTod.hour, endTod.minute);
    }
  }

  /// Checks if [currentTime] is past the configured shift end time for a shift that started on [shiftDate].
  bool isTimePastShiftEnd(DateTime currentTime, {DateTime? shiftDate}) {
    final sessionDate = shiftDate ?? getLogicalShiftDate(currentTime);
    final endDateTime = getShiftEndDateTime(sessionDate);
    return currentTime.isAfter(endDateTime);
  }

  String get formattedTiming {
    return '${_formatTime12(startTime)} – ${_formatTime12(endTime)}';
  }

  String get formattedStart => _formatTime12(startTime);
  String get formattedEnd => _formatTime12(endTime);

  static String _formatTime12(String timeStr) {
    final tod = _parseTime(timeStr);
    final period = tod.hour >= 12 ? 'PM' : 'AM';
    final hour12 = tod.hour == 0
        ? 12
        : tod.hour > 12
            ? tod.hour - 12
            : tod.hour;
    final minStr = tod.minute.toString().padLeft(2, '0');
    final hrStr = hour12.toString().padLeft(2, '0');
    return '$hrStr:$minStr $period';
  }

  ShiftConfiguration copyWith({
    String? shift,
    String? name,
    String? startTime,
    String? endTime,
    int? gracePeriodMinutes,
    DateTime? updatedAt,
  }) {
    return ShiftConfiguration(
      shift: shift ?? this.shift,
      name: name ?? this.name,
      startTime: startTime ?? this.startTime,
      endTime: endTime ?? this.endTime,
      gracePeriodMinutes: gracePeriodMinutes ?? this.gracePeriodMinutes,
      updatedAt: updatedAt ?? this.updatedAt,
    );
  }
}
