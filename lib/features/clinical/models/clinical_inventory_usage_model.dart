import 'package:intl/intl.dart';

/// Represents an item consumed during a clinical procedure/examination
/// tracked in `public.clinical_inventory_usage`.
class ClinicalInventoryUsageModel {
  const ClinicalInventoryUsageModel({
    required this.id,
    required this.patientId,
    required this.recordType,
    required this.recordId,
    required this.inventoryId,
    required this.quantity,
    this.transactionId,
    this.remarks,
    required this.consumedAt,
    this.createdBy,
    required this.createdAt,
    required this.updatedAt,
    this.itemName,
    this.itemUnit,
    this.currentStock,
    this.patientName,
    this.patientNumber,
    this.createdByName,
  });

  final String id;
  final String patientId;
  final String recordType; // 'eye_examination' | 'dental_treatment' | 'eye_surgery' | 'other'
  final String recordId;
  final String inventoryId;
  final double quantity;
  final String? transactionId;
  final String? remarks;
  final DateTime consumedAt;
  final String? createdBy;
  final DateTime createdAt;
  final DateTime updatedAt;

  // Joined presentation data
  final String? itemName;
  final String? itemUnit;
  final double? currentStock;
  final String? patientName;
  final String? patientNumber;
  final String? createdByName;

  String get formattedConsumedAt =>
      DateFormat('dd MMM yyyy, hh:mm a').format(consumedAt);

  factory ClinicalInventoryUsageModel.fromJson(Map<String, dynamic> json) {
    final inventoryMap = _asStringMap(json['inventory']);
    final patientMap = _asStringMap(json['patients']);
    final profileMap = _asStringMap(json['profiles']);

    return ClinicalInventoryUsageModel(
      id: _stringValue(json['id']) ?? '',
      patientId: _stringValue(json['patient_id']) ?? '',
      recordType: _stringValue(json['record_type']) ?? 'other',
      recordId: _stringValue(json['record_id']) ?? '',
      inventoryId: _stringValue(json['inventory_id']) ?? '',
      quantity: _asDouble(json['quantity']),
      transactionId: _stringValue(json['transaction_id']),
      remarks: _stringValue(json['remarks']),
      consumedAt: _parseTimestamp(json['consumed_at']) ?? DateTime.now(),
      createdBy: _stringValue(json['created_by']),
      createdAt: _parseTimestamp(json['created_at']) ?? DateTime.now(),
      updatedAt: _parseTimestamp(json['updated_at']) ?? DateTime.now(),
      itemName: _stringValue(inventoryMap?['name']) ??
          _stringValue(json['item_name']) ??
          'Inventory Item',
      itemUnit: _stringValue(inventoryMap?['unit']) ??
          _stringValue(json['item_unit']) ??
          'units',
      currentStock: _asOptionalDouble(inventoryMap?['quantity']),
      patientName: _stringValue(patientMap?['name']) ??
          _stringValue(json['patient_name']),
      patientNumber: _stringValue(patientMap?['patient_number']) ??
          _stringValue(json['patient_number']),
      createdByName: _stringValue(profileMap?['full_name']) ??
          _stringValue(json['created_by_name']),
    );
  }

  factory ClinicalInventoryUsageModel.fromMap(Map<String, dynamic> map) =>
      ClinicalInventoryUsageModel.fromJson(map);

  Map<String, dynamic> toJson() => {
        'id': id,
        'patient_id': patientId,
        'record_type': recordType,
        'record_id': recordId,
        'inventory_id': inventoryId,
        'quantity': quantity,
        'transaction_id': transactionId,
        'remarks': remarks,
        'consumed_at': consumedAt.toIso8601String(),
        'created_by': createdBy,
        'created_at': createdAt.toIso8601String(),
        'updated_at': updatedAt.toIso8601String(),
      };

  static String? _stringValue(Object? value) {
    if (value is! String) return null;
    final trimmed = value.trim();
    return trimmed.isEmpty ? null : trimmed;
  }

  static double _asDouble(Object? value) {
    if (value is num) return value.toDouble();
    if (value is String) return double.tryParse(value) ?? 0.0;
    return 0.0;
  }

  static double? _asOptionalDouble(Object? value) {
    if (value is num) return value.toDouble();
    if (value is String) return double.tryParse(value);
    return null;
  }

  static DateTime? _parseTimestamp(Object? value) {
    if (value is DateTime) return value;
    if (value is String) return DateTime.tryParse(value);
    return null;
  }

  static Map<String, dynamic>? _asStringMap(Object? value) {
    if (value is! Map) return null;
    return {
      for (final entry in value.entries)
        if (entry.key is String) entry.key as String: entry.value,
    };
  }
}
