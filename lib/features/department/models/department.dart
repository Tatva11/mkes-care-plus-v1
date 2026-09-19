class Department {
  const Department({
    required this.id,
    required this.name,
    this.description,
    required this.isActive,
  });

  final String id;
  final String name;
  final String? description;
  final bool isActive;

  factory Department.fromJson(Map<String, dynamic> json) {
    return Department(
      id: json['id'] as String,
      name: json['name'] as String,
      description: json['description'] as String?,
      isActive: json['is_active'] as bool? ?? true,
    );
  }
}
