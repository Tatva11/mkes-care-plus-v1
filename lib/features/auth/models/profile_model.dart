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
    required this.createdAt,
  });

  factory ProfileModel.fromJson(Map<String, dynamic> json) {
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
}
