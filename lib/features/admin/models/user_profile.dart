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
  });

  factory UserProfile.fromJson(Map<String, dynamic> json) {
    return UserProfile(
      id: json['id'] as String,
      fullName: json['full_name'] as String,
      email: json['email'] as String,
      phoneNumber: json['phone_number'] as String?,
      departmentId: json['department_id'] as String?,
      departmentName:
          (json['department'] as Map<String, dynamic>?)?['name'] as String? ??
              json['department_name'] as String?,
      department: json['legacy_department'] as String? ??
          (json['department'] is String ? json['department'] as String : null),
      designation: json['designation'] as String?,
      role: json['role'] as String,
      isActive: json['is_active'] as bool,
      salary:
          json['salary'] != null ? (json['salary'] as num).toDouble() : null,
      joiningDate: json['joining_date'] != null
          ? DateTime.parse(json['joining_date'] as String)
          : null,
      createdAt: DateTime.parse(json['created_at'] as String),
    );
  }

  Map<String, dynamic> toJson() {
    return {
      'id': id,
      'full_name': fullName,
      'email': email,
      'phone_number': phoneNumber,
      'department_id': departmentId,
      'department_name': departmentName,
      'department': department,
      'designation': designation,
      'role': role,
      'is_active': isActive,
      'salary': salary,
      'joining_date': joiningDate?.toIso8601String(),
      'created_at': createdAt.toIso8601String(),
    };
  }
}
