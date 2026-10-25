class PatientModel {
  final String id;
  final String patientNumber;
  final String name;
  final DateTime? dob;
  final String? address;
  final String? mobile;
  final String? department;
  final String? reference;
  final DateTime? visitDate;
  final DateTime createdAt;
  final DateTime updatedAt;
  final bool whatsappOptOut;

  const PatientModel({
    required this.id,
    required this.patientNumber,
    required this.name,
    this.dob,
    this.address,
    this.mobile,
    this.department,
    this.reference,
    this.visitDate,
    required this.createdAt,
    required this.updatedAt,
    this.whatsappOptOut = false,
  });

  factory PatientModel.fromJson(Map<String, dynamic> json) {
    return PatientModel(
      id: json['id'] as String,
      patientNumber: json['patient_number'] as String? ?? '',
      name: json['name'] as String? ?? '',
      dob: json['dob'] != null ? DateTime.tryParse(json['dob'] as String) : null,
      address: json['address'] as String?,
      mobile: json['mobile'] as String?,
      department: json['department'] as String?,
      reference: json['reference'] as String?,
      visitDate: json['visit_date'] != null
          ? DateTime.tryParse(json['visit_date'] as String)
          : null,
      createdAt: json['created_at'] != null
          ? DateTime.parse(json['created_at'] as String)
          : DateTime.now(),
      updatedAt: json['updated_at'] != null
          ? DateTime.parse(json['updated_at'] as String)
          : DateTime.now(),
      whatsappOptOut: json['whatsapp_opt_out'] as bool? ?? false,
    );
  }

  Map<String, dynamic> toJson() {
    return {
      'id': id,
      'patient_number': patientNumber,
      'name': name,
      'dob': dob?.toIso8601String().split('T').first,
      'address': address,
      'mobile': mobile,
      'department': department,
      'reference': reference,
      'visit_date': visitDate?.toIso8601String().split('T').first,
      'created_at': createdAt.toIso8601String(),
      'updated_at': updatedAt.toIso8601String(),
      'whatsapp_opt_out': whatsappOptOut,
    };
  }

  Map<String, dynamic> toInsertJson() {
    final map = <String, dynamic>{
      'patient_number': patientNumber,
      'name': name,
      'whatsapp_opt_out': whatsappOptOut,
    };
    if (dob != null) map['dob'] = dob?.toIso8601String().split('T').first;
    if (address != null && address!.isNotEmpty) map['address'] = address;
    if (mobile != null && mobile!.isNotEmpty) map['mobile'] = mobile;
    if (department != null && department!.isNotEmpty) {
      map['department'] = department!.toLowerCase();
    }
    if (reference != null && reference!.isNotEmpty) {
      map['reference'] = reference;
    }
    if (visitDate != null) {
      map['visit_date'] = visitDate?.toIso8601String().split('T').first;
    }
    return map;
  }

  PatientModel copyWith({
    String? id,
    String? patientNumber,
    String? name,
    DateTime? dob,
    String? address,
    String? mobile,
    String? department,
    String? reference,
    DateTime? visitDate,
    DateTime? createdAt,
    DateTime? updatedAt,
    bool? whatsappOptOut,
  }) {
    return PatientModel(
      id: id ?? this.id,
      patientNumber: patientNumber ?? this.patientNumber,
      name: name ?? this.name,
      dob: dob ?? this.dob,
      address: address ?? this.address,
      mobile: mobile ?? this.mobile,
      department: department ?? this.department,
      reference: reference ?? this.reference,
      visitDate: visitDate ?? this.visitDate,
      createdAt: createdAt ?? this.createdAt,
      updatedAt: updatedAt ?? this.updatedAt,
      whatsappOptOut: whatsappOptOut ?? this.whatsappOptOut,
    );
  }
}
