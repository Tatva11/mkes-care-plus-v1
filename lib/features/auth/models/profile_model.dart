/// Represents a user's clinic profile, linked 1-to-1 with a Supabase Auth user.
class ProfileModel {
  final String id;
  final String fullName;
  final String email;
  final String? phoneNumber;
  final String? departmentId;
  final String? departmentName;
  final String? department;
  final String? designation;
  final String role; // 'admin' | 'staff'
  final bool isActive;
  final double? salary;
  final DateTime? joiningDate;
  final String? assignedShift;
  final String? nextShift;
  final DateTime? shiftEffectiveDate;
  final DateTime createdAt;

  const ProfileModel({
    required this.id,
    required this.fullName,
    required this.email,
    this.phoneNumber,
    this.departmentId,
    this.departmentName,
    this.department,
    this.designation,
    required this.role,
    required this.isActive,
    this.salary,
    this.joiningDate,
    this.assignedShift,
    this.nextShift,
    this.shiftEffectiveDate,
    required this.createdAt,
  });

  factory ProfileModel.fromJson(Map<String, dynamic> json) {
    DateTime? parseCalendarDate(dynamic value) {
      if (value == null) return null;
      if (value is DateTime) return DateTime(value.year, value.month, value.day);
      final str = value.toString().trim();
      if (str.isEmpty) return null;
      final match = RegExp(r'^(\d{4})-(\d{2})-(\d{2})').firstMatch(str);
      if (match != null) {
        return DateTime(
          int.parse(match.group(1)!),
          int.parse(match.group(2)!),
          int.parse(match.group(3)!),
        );
      }
      final parsed = DateTime.tryParse(str);
      if (parsed != null) {
        final local = parsed.toLocal();
        return DateTime(local.year, local.month, local.day);
      }
      return null;
    }

    return ProfileModel(
      id: json['id'] as String,
      fullName: json['full_name'] as String,
      email: json['email'] as String,
      phoneNumber: json['phone_number'] as String?,
      departmentId: json['department_id'] as String?,
      departmentName:
          (json['department'] as Map<String, dynamic>?)?['name'] as String?,
      department: null,
      designation: json['designation'] as String?,
      role: json['role'] as String,
      isActive: json['is_active'] as bool? ?? true,
      salary: json['salary'] != null ? (json['salary'] as num).toDouble() : null,
      joiningDate: parseCalendarDate(json['joining_date']),
      assignedShift: (json['assigned_shift'] as String?)?.toLowerCase() == 'night'
          ? 'afternoon'
          : (json['assigned_shift'] as String?)?.toLowerCase(),
      nextShift: (json['next_shift'] as String?)?.toLowerCase(),
      shiftEffectiveDate: parseCalendarDate(json['shift_effective_date']),
      createdAt: DateTime.parse(json['created_at'] as String),
    );
  }

  /// Returns the user's initials (up to 2 characters) for avatar display.
  String get initials {
    final parts = fullName.trim().split(RegExp(r'\s+'));
    if (parts.isEmpty) return '?';
    if (parts.length == 1) return parts.first[0].toUpperCase();
    return (parts.first[0] + parts.last[0]).toUpperCase();
  }

  /// Returns a user-friendly display label for the role.
  String get roleDisplayName {
    switch (role) {
      case 'admin':
        return 'Administrator';
      case 'staff':
        return 'Staff Member';
      default:
        return role;
    }
  }

  bool get isMorningShift => (assignedShift ?? 'morning').toLowerCase() == 'morning';
  bool get isAfternoonShift =>
      (assignedShift ?? '').toLowerCase() == 'afternoon' ||
      (assignedShift ?? '').toLowerCase() == 'evening' ||
      (assignedShift ?? '').toLowerCase() == 'night';
  bool get isEveningShift => isAfternoonShift;
  bool get isBothShifts => (assignedShift ?? '').toLowerCase() == 'both';

  bool get hasScheduledShift => nextShift != null && shiftEffectiveDate != null;

  String getShiftForDate(DateTime date) {
    if (nextShift != null && shiftEffectiveDate != null) {
      final targetOnly = DateTime(date.year, date.month, date.day);
      final effOnly = DateTime(
        shiftEffectiveDate!.year,
        shiftEffectiveDate!.month,
        shiftEffectiveDate!.day,
      );
      if (!targetOnly.isBefore(effOnly)) {
        return nextShift!;
      }
    }
    return assignedShift ?? 'morning';
  }

  static String formatShiftLabel(String? shift, {bool includeSuffix = false}) {
    if (shift == null) return includeSuffix ? 'Morning Shift' : 'Morning';
    switch (shift.toLowerCase()) {
      case 'evening':
      case 'afternoon':
      case 'night':
        return includeSuffix ? 'Evening Shift' : 'Evening';
      case 'both':
        return includeSuffix ? 'Both (Morning & Evening)' : 'Morning & Evening';
      case 'morning':
      default:
        return includeSuffix ? 'Morning Shift' : 'Morning';
    }
  }

  String get shiftDisplayName => formatShiftLabel(assignedShift ?? 'morning');

  String? get scheduledShiftDisplayName =>
      nextShift != null ? formatShiftLabel(nextShift!) : null;

  String shiftDisplayNameForDate(DateTime date) =>
      formatShiftLabel(getShiftForDate(date));

  Map<String, dynamic> toJson() {
    return {
      'id': id,
      'email': email,
      'full_name': fullName,
      'phone_number': phoneNumber,
      'department': department,
      'designation': designation,
      'role': role,
      'is_active': isActive,
      'salary': salary,
      'joining_date': joiningDate != null
          ? '${joiningDate!.year.toString().padLeft(4, '0')}-${joiningDate!.month.toString().padLeft(2, '0')}-${joiningDate!.day.toString().padLeft(2, '0')}'
          : null,
      'assigned_shift': assignedShift,
      'next_shift': nextShift,
      'shift_effective_date': shiftEffectiveDate != null
          ? '${shiftEffectiveDate!.year.toString().padLeft(4, '0')}-${shiftEffectiveDate!.month.toString().padLeft(2, '0')}-${shiftEffectiveDate!.day.toString().padLeft(2, '0')}'
          : null,
      'created_at': createdAt.toIso8601String(),
    };
  }
}
