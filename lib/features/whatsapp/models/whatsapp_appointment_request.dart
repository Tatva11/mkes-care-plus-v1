class WhatsAppAppointmentRequest {
  final String id;
  final String patientPhone;
  final String patientName;
  final String? patientId;
  final String department; // 'eye' | 'dental'
  final String? doctorId;
  final String? doctorName;
  final DateTime requestedDate;
  final String requestedTime; // e.g. "10:30:00"
  final int durationMinutes;
  final String status; // 'pending_review' | 'approved' | 'rejected' | 'expired'
  final String? promotedAppointmentId;
  final String? reviewedBy;
  final DateTime? reviewedAt;
  final String? staffRemarks;
  final DateTime createdAt;
  final DateTime updatedAt;

  const WhatsAppAppointmentRequest({
    required this.id,
    required this.patientPhone,
    required this.patientName,
    this.patientId,
    required this.department,
    this.doctorId,
    this.doctorName,
    required this.requestedDate,
    required this.requestedTime,
    this.durationMinutes = 15,
    this.status = 'pending_review',
    this.promotedAppointmentId,
    this.reviewedBy,
    this.reviewedAt,
    this.staffRemarks,
    required this.createdAt,
    required this.updatedAt,
  });

  bool get isPending => status == 'pending_review';
  bool get isApproved => status == 'approved';
  bool get isRejected => status == 'rejected';

  factory WhatsAppAppointmentRequest.fromJson(Map<String, dynamic> json) {
    return WhatsAppAppointmentRequest(
      id: json['id'] as String,
      patientPhone: json['patient_phone'] as String? ?? '',
      patientName: json['patient_name'] as String? ?? 'Patient',
      patientId: json['patient_id'] as String?,
      department: (json['department'] as String? ?? 'dental').toLowerCase().trim(),
      doctorId: json['doctor_id'] as String?,
      doctorName: json['doctor_name'] as String?,
      requestedDate: json['requested_date'] != null
          ? DateTime.parse(json['requested_date'] as String)
          : DateTime.now(),
      requestedTime: json['requested_time'] as String? ?? '09:00:00',
      durationMinutes: json['duration_minutes'] as int? ?? 15,
      status: json['status'] as String? ?? 'pending_review',
      promotedAppointmentId: json['promoted_appointment_id'] as String?,
      reviewedBy: json['reviewed_by'] as String?,
      reviewedAt: json['reviewed_at'] != null
          ? DateTime.parse(json['reviewed_at'] as String)
          : null,
      staffRemarks: json['staff_remarks'] as String?,
      createdAt: json['created_at'] != null
          ? DateTime.parse(json['created_at'] as String)
          : DateTime.now(),
      updatedAt: json['updated_at'] != null
          ? DateTime.parse(json['updated_at'] as String)
          : DateTime.now(),
    );
  }

  Map<String, dynamic> toJson() {
    return {
      'id': id,
      'patient_phone': patientPhone,
      'patient_name': patientName,
      'patient_id': patientId,
      'department': department,
      'doctor_id': doctorId,
      'doctor_name': doctorName,
      'requested_date': requestedDate.toIso8601String().split('T').first,
      'requested_time': requestedTime,
      'duration_minutes': durationMinutes,
      'status': status,
      'promoted_appointment_id': promotedAppointmentId,
      'reviewed_by': reviewedBy,
      'reviewed_at': reviewedAt?.toIso8601String(),
      'staff_remarks': staffRemarks,
      'created_at': createdAt.toIso8601String(),
      'updated_at': updatedAt.toIso8601String(),
    };
  }

  WhatsAppAppointmentRequest copyWith({
    String? id,
    String? patientPhone,
    String? patientName,
    String? patientId,
    String? department,
    String? doctorId,
    String? doctorName,
    DateTime? requestedDate,
    String? requestedTime,
    int? durationMinutes,
    String? status,
    String? promotedAppointmentId,
    String? reviewedBy,
    DateTime? reviewedAt,
    String? staffRemarks,
    DateTime? createdAt,
    DateTime? updatedAt,
  }) {
    return WhatsAppAppointmentRequest(
      id: id ?? this.id,
      patientPhone: patientPhone ?? this.patientPhone,
      patientName: patientName ?? this.patientName,
      patientId: patientId ?? this.patientId,
      department: department ?? this.department,
      doctorId: doctorId ?? this.doctorId,
      doctorName: doctorName ?? this.doctorName,
      requestedDate: requestedDate ?? this.requestedDate,
      requestedTime: requestedTime ?? this.requestedTime,
      durationMinutes: durationMinutes ?? this.durationMinutes,
      status: status ?? this.status,
      promotedAppointmentId: promotedAppointmentId ?? this.promotedAppointmentId,
      reviewedBy: reviewedBy ?? this.reviewedBy,
      reviewedAt: reviewedAt ?? this.reviewedAt,
      staffRemarks: staffRemarks ?? this.staffRemarks,
      createdAt: createdAt ?? this.createdAt,
      updatedAt: updatedAt ?? this.updatedAt,
    );
  }
}
