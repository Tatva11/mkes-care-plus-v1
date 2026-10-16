class EyeSurgeryModel {
  EyeSurgeryModel({
    required this.id,
    required this.patientId,
    required this.surgeryType,
    this.surgeryTypeCategory = 'Other',
    this.customSurgeryType,
    required this.eyeSide,
    this.assignedStaffId,
    this.assignedStaffName,
    required this.preOpDate,
    required this.surgeryDate,
    String? surgeryTime,
    this.inventoryConsumedAt,
    required this.status,
    this.preOpChecklist = const {},
    this.iolDetails,
    this.remarks,
    required this.createdAt,
    required this.updatedAt,
    this.patientName,
    this.patientNumber,
    this.followUpAppointmentId,
    this.dischargedAt,
  }) : surgeryTime = _stringValue(surgeryTime);

  final String id;
  final String patientId;
  final String surgeryType;
  final String surgeryTypeCategory;
  final String? customSurgeryType;
  final String eyeSide;
  final String? assignedStaffId;
  final String? assignedStaffName;
  final DateTime preOpDate;
  final DateTime surgeryDate;
  final String? surgeryTime;
  final DateTime? inventoryConsumedAt;
  final String status;
  final Map<String, bool> preOpChecklist;
  final String? iolDetails;
  final String? remarks;
  final DateTime createdAt;
  final DateTime updatedAt;
  final String? patientName;
  final String? patientNumber;
  final String? followUpAppointmentId;
  final DateTime? dischargedAt;

  static const eyeSides = ['left', 'right', 'both'];
  static const surgeryTypeOptions = [
    'Cataract Surgery',
    'LASIK / Refractive Surgery',
    'Glaucoma Surgery',
    'Retinal Surgery',
    'Corneal Surgery',
    'Other',
  ];
  static const statuses = [
    'scheduled',
    'pre_op',
    'in_surgery',
    'post_op',
    'billing',
    'discharged',
    'cancelled',
    'missed',
  ];

  static const checklistItems = <String, String>{
    'identity_verified': 'Patient identity verified',
    'consent_confirmed': 'Consent confirmed',
    'correct_eye_confirmed': 'Correct eye confirmed',
    'pre_op_exam_completed': 'Pre-op examination completed',
    'investigations_reviewed': 'Required investigations reviewed',
    'allergies_checked': 'Allergies checked',
    'assigned_staff_confirmed': 'Assigned staff confirmed',
    'procedure_confirmed': 'Procedure confirmed',
  };

  static const _nextStatus = <String, String>{
    'scheduled': 'pre_op',
    'pre_op': 'in_surgery',
    'in_surgery': 'post_op',
    'post_op': 'billing',
    'billing': 'discharged',
  };

  static bool isValidStatus(String status) => statuses.contains(status);

  String get displaySurgeryType =>
      surgeryTypeCategory == 'Other' && customSurgeryType != null
          ? customSurgeryType!
          : surgeryType;

  bool get isPreOpChecklistComplete => checklistItems.keys.every(
        (key) => preOpChecklist[key] == true,
      );

  /// Whether the surgery has reached the Billing stage or Discharged stage,
  /// making Billing & Insurance accessible.
  bool get canAccessBilling => status == 'billing' || status == 'discharged';

  /// Whether the surgery is in final discharged status.
  bool get isDischarged => status == 'discharged';

  bool isMissedAt([DateTime? referenceTime]) {
    if (status != 'scheduled' && status != 'pre_op' && status != 'missed') {
      return false;
    }
    final now = referenceTime ?? DateTime.now();
    if (surgeryTime == null || surgeryTime!.trim().isEmpty) {
      return status == 'missed';
    }
    final parsed = parseTimeString(surgeryTime!);
    if (parsed == null) {
      return status == 'missed';
    }
    final scheduledDateTime = DateTime(
      surgeryDate.year,
      surgeryDate.month,
      surgeryDate.day,
      parsed.hour,
      parsed.minute,
    );
    return scheduledDateTime.isBefore(now);
  }

  bool get isMissed => isMissedAt();

  bool isDischargedVisible([DateTime? onDate]) {
    if (status != 'discharged') return true;
    final dischargeTime = (dischargedAt ?? updatedAt).toLocal();
    final checkDate = (onDate ?? DateTime.now()).toLocal();
    final dischargeCalendarDay = DateTime(
      dischargeTime.year,
      dischargeTime.month,
      dischargeTime.day,
    );
    final currentCalendarDay = DateTime(
      checkDate.year,
      checkDate.month,
      checkDate.day,
    );
    return !dischargeCalendarDay.isBefore(currentCalendarDay);
  }

  static ({int hour, int minute})? parseTimeString(String timeStr) {
    try {
      final trimmed = timeStr.trim();
      final match = RegExp(r'^(\d{1,2}):(\d{2})(?::\d{2})?\s*(AM|PM)?$', caseSensitive: false).firstMatch(trimmed);
      if (match != null) {
        var hour = int.parse(match.group(1)!);
        final minute = int.parse(match.group(2)!);
        final period = match.group(3)?.toUpperCase();
        if (period == 'PM' && hour < 12) hour += 12;
        if (period == 'AM' && hour == 12) hour = 0;
        return (hour: hour, minute: minute);
      }
    } catch (_) {}
    return null;
  }

  static const Object _kUnspecified = Object();

  EyeSurgeryModel copyWith({
    String? id,
    String? patientId,
    String? surgeryType,
    String? surgeryTypeCategory,
    String? customSurgeryType,
    String? eyeSide,
    String? assignedStaffId,
    String? assignedStaffName,
    DateTime? preOpDate,
    DateTime? surgeryDate,
    Object? surgeryTime = _kUnspecified,
    DateTime? inventoryConsumedAt,
    String? status,
    Map<String, bool>? preOpChecklist,
    String? iolDetails,
    String? remarks,
    DateTime? createdAt,
    DateTime? updatedAt,
    String? patientName,
    String? patientNumber,
    String? followUpAppointmentId,
    DateTime? dischargedAt,
  }) {
    return EyeSurgeryModel(
      id: id ?? this.id,
      patientId: patientId ?? this.patientId,
      surgeryType: surgeryType ?? this.surgeryType,
      surgeryTypeCategory: surgeryTypeCategory ?? this.surgeryTypeCategory,
      customSurgeryType: customSurgeryType ?? this.customSurgeryType,
      eyeSide: eyeSide ?? this.eyeSide,
      assignedStaffId: assignedStaffId ?? this.assignedStaffId,
      assignedStaffName: assignedStaffName ?? this.assignedStaffName,
      preOpDate: preOpDate ?? this.preOpDate,
      surgeryDate: surgeryDate ?? this.surgeryDate,
      surgeryTime: identical(surgeryTime, _kUnspecified)
          ? this.surgeryTime
          : _stringValue(surgeryTime),
      inventoryConsumedAt: inventoryConsumedAt ?? this.inventoryConsumedAt,
      status: status ?? this.status,
      preOpChecklist: preOpChecklist ?? this.preOpChecklist,
      iolDetails: iolDetails ?? this.iolDetails,
      remarks: remarks ?? this.remarks,
      createdAt: createdAt ?? this.createdAt,
      updatedAt: updatedAt ?? this.updatedAt,
      patientName: patientName ?? this.patientName,
      patientNumber: patientNumber ?? this.patientNumber,
      followUpAppointmentId:
          followUpAppointmentId ?? this.followUpAppointmentId,
      dischargedAt: dischargedAt ?? this.dischargedAt,
    );
  }

  static bool canTransition(String from, String to) {
    if (!isValidStatus(from) || !isValidStatus(to) || from == to) return false;
    if (_nextStatus[from] == to) return true;
    if (from == 'post_op' && to == 'discharged') return true;
    return to == 'cancelled' &&
        const {'scheduled', 'pre_op', 'in_surgery', 'post_op', 'billing'}.contains(from);
  }

  static String? validateStatusTransition({
    required EyeSurgeryModel surgery,
    required String nextStatus,
  }) {
    if (!canTransition(surgery.status, nextStatus)) {
      return 'Invalid Eye Surgery status transition: ${surgery.status} -> $nextStatus';
    }
    if (surgery.status == 'scheduled' && nextStatus == 'pre_op') {
      if (surgery.assignedStaffId == null ||
          surgery.assignedStaffId!.trim().isEmpty) {
        return 'An Admin must assign staff to this surgery before starting Pre-op.';
      }
    }
    if (nextStatus == 'in_surgery' && !surgery.isPreOpChecklistComplete) {
      return 'Complete the pre-op checklist before entering surgery.';
    }
    return null;
  }

  static String? validateFields({
    required String patientId,
    required String surgeryType,
    required String surgeryTypeCategory,
    String? customSurgeryType,
    required String eyeSide,
    required DateTime? preOpDate,
    required DateTime? surgeryDate,
    String? surgeryTime,
    required String status,
  }) {
    if (patientId.trim().isEmpty) return 'Patient selection is required.';
    if (surgeryType.trim().isEmpty) return 'Surgery type is required.';
    if (!surgeryTypeOptions.contains(surgeryTypeCategory)) {
      return 'Select a valid surgery type.';
    }
    if (surgeryTypeCategory == 'Other' &&
        (customSurgeryType == null || customSurgeryType.trim().isEmpty)) {
      return 'Enter the custom surgery type.';
    }
    if (!eyeSides.contains(eyeSide)) return 'Select a valid eye side.';
    if (surgeryDate == null) return 'Surgery date is required.';
    if (preOpDate != null && !_sameCalendarDate(preOpDate, surgeryDate)) {
      return 'Pre-op date must match surgery date.';
    }
    if (surgeryTime == null || surgeryTime.trim().isEmpty) {
      return 'Surgery time is required.';
    }
    if (!isValidStatus(status)) return 'Select a valid surgery status.';
    return null;
  }

  factory EyeSurgeryModel.fromJson(Map<String, dynamic> json) {
    final patient = _asStringMap(json['patients']);
    final assignedStaff =
        _asStringMap(json['assigned_staff']) ?? _asStringMap(json['profiles']);
    final createdAt = _parseTimestamp(json['created_at']) ?? DateTime.now();
    final surgeryDate = _parseDate(json['surgery_date']);

    return EyeSurgeryModel(
      id: _stringValue(json['id']) ?? '',
      patientId: _stringValue(json['patient_id']) ?? '',
      surgeryType: _stringValue(json['surgery_type']) ?? '',
      surgeryTypeCategory:
          _stringValue(json['surgery_type_category']) ?? 'Other',
      customSurgeryType: _stringValue(json['custom_surgery_type']),
      eyeSide: _stringValue(json['eye_side']) ?? '',
      assignedStaffId: _stringValue(json['assigned_staff_id']) ??
          _stringValue(json['surgeon_id']),
      assignedStaffName: _stringValue(assignedStaff?['full_name']),
      preOpDate: _parseOptionalDate(json['pre_op_date']) ?? surgeryDate,
      surgeryDate: surgeryDate,
      surgeryTime: _stringValue(json['surgery_time']),
      inventoryConsumedAt: _parseTimestamp(json['inventory_consumed_at']),
      status: _stringValue(json['status']) ?? 'scheduled',
      preOpChecklist: _boolMap(json['pre_op_checklist']),
      iolDetails: _stringValue(json['iol_details']),
      remarks: _stringValue(json['remarks']),
      createdAt: createdAt,
      updatedAt: _parseTimestamp(json['updated_at']) ?? createdAt,
      patientName:
          _stringValue(patient?['name']) ?? _stringValue(json['patient_name']),
      patientNumber: _stringValue(patient?['patient_number']) ??
          _stringValue(json['patient_number']),
      followUpAppointmentId: _stringValue(json['follow_up_appointment_id']),
      dischargedAt: _parseTimestamp(json['discharged_at']),
    );
  }

  factory EyeSurgeryModel.fromMap(Map<String, dynamic> map) =>
      EyeSurgeryModel.fromJson(map);

  Map<String, dynamic> toMap() => toJson();

  Map<String, dynamic> toJson() => {
        'id': id,
        'patient_id': patientId,
        'surgery_type': surgeryType,
        'surgery_type_category': surgeryTypeCategory,
        'custom_surgery_type': customSurgeryType,
        'eye_side': eyeSide,
        'assigned_staff_id': assignedStaffId,
        'pre_op_date': _dateOnly(preOpDate),
        'surgery_date': _dateOnly(surgeryDate),
        'surgery_time': surgeryTime == null || surgeryTime!.trim().isEmpty
            ? null
            : surgeryTime!.trim(),
        'inventory_consumed_at': inventoryConsumedAt?.toIso8601String(),
        'status': status,
        'pre_op_checklist': preOpChecklist,
        'iol_details': iolDetails,
        'remarks': remarks,
        'created_at': createdAt.toIso8601String(),
        'updated_at': updatedAt.toIso8601String(),
        if (followUpAppointmentId != null)
          'follow_up_appointment_id': followUpAppointmentId,
        if (dischargedAt != null)
          'discharged_at': dischargedAt!.toIso8601String(),
      };

  Map<String, dynamic> toInsertJson() {
    final json = toJson()
      ..remove('id')
      ..remove('created_at')
      ..remove('updated_at');
    return json;
  }

  static String _dateOnly(DateTime date) =>
      '${date.year.toString().padLeft(4, '0')}-'
      '${date.month.toString().padLeft(2, '0')}-'
      '${date.day.toString().padLeft(2, '0')}';

  static bool isSameCalendarDay(DateTime first, DateTime second) =>
      first.year == second.year &&
      first.month == second.month &&
      first.day == second.day;

  static bool _sameCalendarDate(DateTime first, DateTime second) =>
      isSameCalendarDay(first, second);

  static String? _stringValue(Object? value) {
    if (value is! String) return null;
    final trimmed = value.trim();
    return trimmed.isEmpty ? null : trimmed;
  }

  static DateTime _parseDate(Object? value) {
    final parsed = _parseOptionalDate(value);
    if (parsed == null) {
      throw const FormatException(
          'Eye surgery record has an invalid surgery_date.');
    }
    return parsed;
  }

  static DateTime? _parseOptionalDate(Object? value) {
    if (value is DateTime) return value;
    if (value is String) return DateTime.tryParse(value);
    return null;
  }

  static DateTime? _parseTimestamp(Object? value) => _parseOptionalDate(value);

  static Map<String, dynamic>? _asStringMap(Object? value) {
    if (value is! Map) return null;
    return {
      for (final entry in value.entries)
        if (entry.key is String) entry.key as String: entry.value,
    };
  }

  static Map<String, bool> _boolMap(Object? value) {
    final map = _asStringMap(value);
    if (map == null) return const {};
    return {
      for (final entry in map.entries)
        if (entry.value is bool) entry.key: entry.value as bool,
    };
  }
}

class EyeSurgeryStaffCandidate {
  final String id;
  final String fullName;
  final String? department;
  final String role;
  final bool isActive;

  const EyeSurgeryStaffCandidate({
    required this.id,
    required this.fullName,
    this.department,
    this.role = 'staff',
    this.isActive = true,
  });

  factory EyeSurgeryStaffCandidate.fromJson(Map<String, dynamic> json) {
    return EyeSurgeryStaffCandidate(
      id: (json['id'] as String?)?.trim().toLowerCase() ?? '',
      fullName: (json['full_name'] as String?)?.trim() ?? 'Staff',
      department: json['department'] as String?,
      role: (json['role'] as String?) ?? 'staff',
      isActive: json['is_active'] as bool? ?? true,
    );
  }
}

List<EyeSurgeryStaffCandidate> uniqueEyeSurgeryStaffCandidates(
  Iterable<EyeSurgeryStaffCandidate> candidates,
) {
  final unique = <String, EyeSurgeryStaffCandidate>{};
  for (final candidate in candidates) {
    final normalizedId = candidate.id.trim().toLowerCase();
    final role = candidate.role.trim().toLowerCase();
    // NEVER show Admin accounts in Assigned Staff. Only active staff.
    if (normalizedId.isEmpty || role == 'admin' || !candidate.isActive) continue;
    unique.putIfAbsent(
      normalizedId,
      () => EyeSurgeryStaffCandidate(
        id: normalizedId,
        fullName: candidate.fullName.trim(),
        department: candidate.department,
        role: candidate.role,
        isActive: candidate.isActive,
      ),
    );
  }
  return unique.values.toList();
}
