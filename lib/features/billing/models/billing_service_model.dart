class BillingServiceModel {
  final String id;
  final String department;
  final String name;
  final double price;
  final bool isActive;
  final DateTime? createdAt;
  final DateTime? updatedAt;

  const BillingServiceModel({
    required this.id,
    required this.department,
    required this.name,
    required this.price,
    this.isActive = true,
    this.createdAt,
    this.updatedAt,
  });

  factory BillingServiceModel.fromJson(Map<String, dynamic> json) {
    return BillingServiceModel(
      id: json['id'] as String,
      department: (json['department'] as String? ?? 'eye').toLowerCase(),
      name: json['name'] as String? ?? '',
      price: (json['price'] as num?)?.toDouble() ?? 0.0,
      isActive: json['is_active'] as bool? ?? true,
      createdAt: json['created_at'] != null
          ? DateTime.tryParse(json['created_at'] as String)
          : null,
      updatedAt: json['updated_at'] != null
          ? DateTime.tryParse(json['updated_at'] as String)
          : null,
    );
  }

  Map<String, dynamic> toJson() {
    return {
      'id': id,
      'department': department,
      'name': name,
      'price': price,
      'is_active': isActive,
      'created_at': createdAt?.toIso8601String(),
      'updated_at': updatedAt?.toIso8601String(),
    };
  }

  BillingServiceModel copyWith({
    String? id,
    String? department,
    String? name,
    double? price,
    bool? isActive,
    DateTime? createdAt,
    DateTime? updatedAt,
  }) {
    return BillingServiceModel(
      id: id ?? this.id,
      department: department ?? this.department,
      name: name ?? this.name,
      price: price ?? this.price,
      isActive: isActive ?? this.isActive,
      createdAt: createdAt ?? this.createdAt,
      updatedAt: updatedAt ?? this.updatedAt,
    );
  }
}
