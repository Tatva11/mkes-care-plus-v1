class Patient {
  static const allowedDepartments = [
    'Eye',
    'Dental',
    'Optical',
    'Administration',
  ];

  static String? normalizeDepartment(String? value) {
    final trimmed = value?.trim();
    if (trimmed == null || trimmed.isEmpty) return null;

    for (final allowed in allowedDepartments) {
      if (allowed.toLowerCase() == trimmed.toLowerCase()) return allowed;
    }
    return null;
  }

  final String id;
  final String patientNumber;
  final String fullName;
  final String? mobile;
  final DateTime? dateOfBirth;
  final String? address;
  final String? departmentName;
  final String? reference;
  final DateTime? visitDate;
  final DateTime createdAt;
  final DateTime updatedAt;

  const Patient({
    required this.id,
    required this.patientNumber,
    required this.fullName,
    this.mobile,
    this.dateOfBirth,
    this.address,
    this.departmentName,
    this.reference,
    this.visitDate,
    required this.createdAt,
    required this.updatedAt,
  });

  factory Patient.fromJson(Map<String, dynamic> json) {
    final department = json['department'];
    return Patient(
      id: json['id'] as String,
      patientNumber: json['patient_number'] as String,
      fullName: json['name'] as String,
      mobile: json['mobile'] as String?,
      dateOfBirth:
          json['dob'] == null ? null : DateTime.parse(json['dob'] as String),
      address: json['address'] as String?,
      departmentName: json['department'] as String? ??
          (department is Map<String, dynamic>
              ? department['name'] as String?
              : null),
      reference: json['reference'] as String?,
      visitDate: json['visit_date'] == null
          ? null
          : DateTime.parse(json['visit_date'] as String),
      createdAt: DateTime.parse(json['created_at'] as String),
      updatedAt: DateTime.parse(json['updated_at'] as String),
    );
  }

  String get registrationNumber => patientNumber;
}
