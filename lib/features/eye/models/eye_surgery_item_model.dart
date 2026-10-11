class EyeSurgeryItemModel {
  const EyeSurgeryItemModel({
    required this.id,
    required this.surgeryId,
    required this.inventoryItemId,
    required this.inventoryItemName,
    required this.currentStock,
    required this.unit,
    required this.plannedQuantity,
    required this.actualQuantity,
    required this.source,
    this.consumedAt,
  });

  final String id;
  final String surgeryId;
  final String inventoryItemId;
  final String inventoryItemName;
  final double currentStock;
  final String unit;
  final double plannedQuantity;
  final double actualQuantity;
  final String source;
  final DateTime? consumedAt;

  double get requiredQuantity => plannedQuantity > 0 ? plannedQuantity : actualQuantity;

  factory EyeSurgeryItemModel.fromJson(Map<String, dynamic> json) {
    final inventory = _stringMap(json['inventory']);
    return EyeSurgeryItemModel(
      id: _string(json['id']) ?? '',
      surgeryId: _string(json['eye_surgery_id']) ?? '',
      inventoryItemId: _string(json['inventory_item_id']) ?? '',
      inventoryItemName: _string(inventory?['name']) ?? 'Inventory item',
      currentStock: _number(inventory?['quantity']),
      unit: _string(inventory?['unit']) ?? 'units',
      plannedQuantity: _number(json['planned_quantity']),
      actualQuantity: _number(json['actual_quantity']),
      source: _string(json['source']) ?? 'manual',
      consumedAt: _date(json['consumed_at']),
    );
  }

  Map<String, dynamic> toJson() => {
        'id': id,
        'eye_surgery_id': surgeryId,
        'inventory_item_id': inventoryItemId,
        'planned_quantity': plannedQuantity,
        'actual_quantity': actualQuantity,
        'source': source,
        'consumed_at': consumedAt?.toIso8601String(),
      };

  EyeSurgeryItemModel copyWith({
    String? id,
    String? surgeryId,
    String? inventoryItemId,
    String? inventoryItemName,
    double? currentStock,
    String? unit,
    double? plannedQuantity,
    double? actualQuantity,
    String? source,
    DateTime? consumedAt,
  }) {
    return EyeSurgeryItemModel(
      id: id ?? this.id,
      surgeryId: surgeryId ?? this.surgeryId,
      inventoryItemId: inventoryItemId ?? this.inventoryItemId,
      inventoryItemName: inventoryItemName ?? this.inventoryItemName,
      currentStock: currentStock ?? this.currentStock,
      unit: unit ?? this.unit,
      plannedQuantity: plannedQuantity ?? this.plannedQuantity,
      actualQuantity: actualQuantity ?? this.actualQuantity,
      source: source ?? this.source,
      consumedAt: consumedAt ?? this.consumedAt,
    );
  }
}

class EyeSurgeryItemTemplateModel {
  const EyeSurgeryItemTemplateModel({
    required this.id,
    required this.surgeryType,
    required this.inventoryItemId,
    required this.inventoryItemName,
    required this.currentStock,
    required this.unit,
    required this.defaultQuantity,
    required this.isActive,
  });

  final String id;
  final String surgeryType;
  final String inventoryItemId;
  final String inventoryItemName;
  final double currentStock;
  final String unit;
  final double defaultQuantity;
  final bool isActive;

  factory EyeSurgeryItemTemplateModel.fromJson(Map<String, dynamic> json) {
    final inventory = _stringMap(json['inventory']);
    return EyeSurgeryItemTemplateModel(
      id: _string(json['id']) ?? '',
      surgeryType: _string(json['surgery_type']) ?? '',
      inventoryItemId: _string(json['inventory_item_id']) ?? '',
      inventoryItemName: _string(inventory?['name']) ?? 'Inventory item',
      currentStock: _number(inventory?['quantity']),
      unit: _string(inventory?['unit']) ?? 'units',
      defaultQuantity: _number(json['default_quantity']),
      isActive: json['is_active'] is bool ? json['is_active'] as bool : true,
    );
  }
}

String? _string(Object? value) => value is String ? value : null;

double _number(Object? value) => value is num ? value.toDouble() : 0;

DateTime? _date(Object? value) =>
    value is String ? DateTime.tryParse(value) : null;

Map<String, dynamic>? _stringMap(Object? value) {
  if (value is! Map) return null;
  return {
    for (final entry in value.entries)
      if (entry.key is String) entry.key as String: entry.value,
  };
}
