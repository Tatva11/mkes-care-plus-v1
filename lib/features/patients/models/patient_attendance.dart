class PatientAttendance {
  final String id;
  final String patientId;
  final String staffId;
  final String? staffName;
  final DateTime attendanceDate;
  final DateTime attendedAt;
  final String status;

  // Optional patient info — populated when the query joins the patients table.
  final String? patientName;
  final String? patientNumber;
  final String? patientDepartment;

  const PatientAttendance({
    required this.id,
    required this.patientId,
    required this.staffId,
    this.staffName,
    required this.attendanceDate,
    required this.attendedAt,
    required this.status,
    this.patientName,
    this.patientNumber,
    this.patientDepartment,
  });

  factory PatientAttendance.fromJson(Map<String, dynamic> json) {
    final profile = json['profiles'];
    final patient = json['patients'];

    return PatientAttendance(
      id: json['id'] as String,
      patientId: json['patient_id'] as String,
      staffId: json['staff_id'] as String,
      staffName: profile is Map<String, dynamic>
          ? profile['full_name'] as String?
          : null,
      attendanceDate: DateTime.parse(json['attendance_date'] as String),
      attendedAt: DateTime.parse(json['attended_at'] as String),
      status: (json['status'] as String? ?? 'attended').toLowerCase(),
      patientName: patient is Map<String, dynamic>
          ? patient['name'] as String?
          : null,
      patientNumber: patient is Map<String, dynamic>
          ? patient['patient_number'] as String?
          : null,
      patientDepartment: patient is Map<String, dynamic>
          ? patient['department'] as String?
          : null,
    );
  }
}
