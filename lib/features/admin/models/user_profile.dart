class UserProfile {
  final String id;
  final String fullName;
  final String email;
  final String? phoneNumber;
  final String? departmentId;
  final String? departmentName;
  final String? department;
  final String? designation;
  final String role;
  final bool isActive;
  final double? salary;
  final DateTime? joiningDate;
  final DateTime createdAt;

  final String assignedShift; // 'morning' | 'afternoon' | 'evening' | 'both'
  final String? nextShift; // Scheduled future shift: 'morning' | 'afternoon' | 'evening' | 'both'
  final DateTime? shiftEffectiveDate; // Date from which nextShift takes effect

  UserProfile({
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
    required this.createdAt,
    this.assignedShift = 'morning',
    this.nextShift,
    this.shiftEffectiveDate,
  });

  factory UserProfile.fromJson(Map<String, dynamic> json) {
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

    final rawShift = (json['assigned_shift'] as String?)?.toLowerCase() ?? 'morning';
    final rawNextShift = (json['next_shift'] as String?)?.toLowerCase();

    return UserProfile(
      id: json['id']?.toString() ?? '',
      fullName: json['full_name']?.toString() ?? '',
      email: json['email']?.toString() ?? '',
      phoneNumber: json['phone_number'] as String?,
      departmentId: json['department_id'] as String?,
      departmentName:
          (json['department'] as Map<String, dynamic>?)?['name'] as String?,
      department: null,
      designation: json['designation'] as String?,
      role: json['role']?.toString() ?? 'staff',
      isActive: json['is_active'] as bool? ?? true,
      salary:
          json['salary'] != null ? (json['salary'] as num).toDouble() : null,
      joiningDate: parseCalendarDate(json['joining_date']),
      createdAt: json['created_at'] != null
          ? (DateTime.tryParse(json['created_at'].toString()) ?? DateTime.now())
          : DateTime.now(),
      assignedShift: rawShift,
      nextShift: rawNextShift,
      shiftEffectiveDate: parseCalendarDate(json['shift_effective_date']),
    );
  }

  Map<String, dynamic> toJson() {
    return {
      'id': id,
      'full_name': fullName,
      'email': email,
      'phone_number': phoneNumber,
      'department_id': departmentId,
      'designation': designation,
      'role': role,
      'is_active': isActive,
      'salary': salary,
      'joining_date': joiningDate?.toIso8601String(),
      'created_at': createdAt.toIso8601String(),
      'assigned_shift': assignedShift,
      if (nextShift != null) 'next_shift': nextShift,
      if (shiftEffectiveDate != null)
        'shift_effective_date':
            '${shiftEffectiveDate!.year.toString().padLeft(4, '0')}-${shiftEffectiveDate!.month.toString().padLeft(2, '0')}-${shiftEffectiveDate!.day.toString().padLeft(2, '0')}',
    };
  }

  UserProfile copyWith({
    String? id,
    String? fullName,
    String? email,
    String? phoneNumber,
    String? departmentId,
    String? departmentName,
    String? department,
    String? designation,
    String? role,
    bool? isActive,
    double? salary,
    DateTime? joiningDate,
    DateTime? createdAt,
    String? assignedShift,
    String? nextShift,
    DateTime? shiftEffectiveDate,
  }) {
    return UserProfile(
      id: id ?? this.id,
      fullName: fullName ?? this.fullName,
      email: email ?? this.email,
      phoneNumber: phoneNumber ?? this.phoneNumber,
      departmentId: departmentId ?? this.departmentId,
      departmentName: departmentName ?? this.departmentName,
      department: department ?? this.department,
      designation: designation ?? this.designation,
      role: role ?? this.role,
      isActive: isActive ?? this.isActive,
      salary: salary ?? this.salary,
      joiningDate: joiningDate ?? this.joiningDate,
      createdAt: createdAt ?? this.createdAt,
      assignedShift: assignedShift ?? this.assignedShift,
      nextShift: nextShift ?? this.nextShift,
      shiftEffectiveDate: shiftEffectiveDate ?? this.shiftEffectiveDate,
    );
  }

  bool get isMorningShift => assignedShift.toLowerCase() == 'morning';
  bool get isAfternoonShift =>
      assignedShift.toLowerCase() == 'afternoon' ||
      assignedShift.toLowerCase() == 'evening' ||
      assignedShift.toLowerCase() == 'night';
  bool get isEveningShift => isAfternoonShift;
  bool get isBothShifts => assignedShift.toLowerCase() == 'both';

  /// Returns true if a future shift assignment is scheduled to take effect.
  bool get hasScheduledShift => nextShift != null && shiftEffectiveDate != null;

  /// Returns the effective shift for a specific date (calendar date comparison).
  /// If [date] is on or after [shiftEffectiveDate], returns [nextShift].
  /// Otherwise, returns [assignedShift] (today and historical dates remain unchanged).
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
    return assignedShift;
  }

  /// Formatted user-facing display label for any shift identifier.
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

  /// Current working shift display name (or for a specific date).
  String get shiftDisplayName => formatShiftLabel(assignedShift);

  /// Scheduled future shift display name.
  String? get scheduledShiftDisplayName =>
      nextShift != null ? formatShiftLabel(nextShift!) : null;

  /// Effective shift display name for a given calendar date.
  String shiftDisplayNameForDate(DateTime date) =>
      formatShiftLabel(getShiftForDate(date));
}
