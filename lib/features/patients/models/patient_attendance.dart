/// Represents one patient-attendance record from the `patient_attendance` table.
///
/// Optional joined fields ([staffName], [patientName], [patientNumber],
/// [patientDepartment]) are populated only when the query uses the
/// appropriate select string with FK-named joins.
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
    final profileRaw = json['profiles'];
    final Map? profile = profileRaw is List && profileRaw.isNotEmpty
        ? (profileRaw.first is Map ? profileRaw.first as Map : null)
        : (profileRaw is Map ? profileRaw : null);

    final patientRaw = json['patients'];
    final Map? patient = patientRaw is List && patientRaw.isNotEmpty
        ? (patientRaw.first is Map ? patientRaw.first as Map : null)
        : (patientRaw is Map ? patientRaw : null);

    return PatientAttendance(
      id: json['id'] as String,
      patientId: json['patient_id'] as String,
      staffId: json['staff_id'] as String,
      staffName: profile != null ? profile['full_name'] as String? : null,
      attendanceDate: DateTime.parse(json['attendance_date'] as String),
      attendedAt: DateTime.parse(json['attended_at'] as String),
      status: (json['status'] as String? ?? 'attended').toLowerCase(),
      patientName: patient != null ? patient['name'] as String? : null,
      patientNumber:
          patient != null ? patient['patient_number'] as String? : null,
      patientDepartment:
          patient != null ? patient['department'] as String? : null,
    );
  }
}

