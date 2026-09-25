class PatientAttendance {
  final String id;
  final String patientId;
  final String staffId;
  final String? staffName;
  final DateTime attendanceDate;
  final DateTime attendedAt;
  final String status;

  const PatientAttendance({
    required this.id,
    required this.patientId,
    required this.staffId,
    this.staffName,
    required this.attendanceDate,
    required this.attendedAt,
    required this.status,
  });

  factory PatientAttendance.fromJson(Map<String, dynamic> json) {
    final profile = json['profiles'];
    return PatientAttendance(
      id: json['id'] as String,
      patientId: json['patient_id'] as String,
      staffId: json['staff_id'] as String,
      staffName: profile is Map<String, dynamic> ? profile['full_name'] as String? : null,
      attendanceDate: DateTime.parse(json['attendance_date'] as String),
      attendedAt: DateTime.parse(json['attended_at'] as String),
      status: (json['status'] as String? ?? 'attended').toLowerCase(),
    );
  }
}
