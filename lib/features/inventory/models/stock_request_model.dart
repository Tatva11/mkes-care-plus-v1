import 'package:flutter/material.dart';
import 'package:intl/intl.dart';

/// Represents a staff stock request and admin approval/fulfillment record.
@immutable
class StockRequestModel {
  static const validStatuses = [
    'pending',
    'approved',
    'rejected',
    'fulfilled',
    'cancelled',
    'transferred',
  ];

  final String id;
  final String requestNumber;
  final String departmentId;
  final String departmentName;
  final String inventoryId;
  final String itemName;
  final String? itemSku;
  final String itemUnit;
  final double? centralStock;
  final double requestedQuantity;
  final double? approvedQuantity;
  final double fulfilledQuantity;
  final String status;
  final String requestedBy;
  final String? requestedByName;
  final String? reviewedBy;
  final String? reviewedByName;
  final String? fulfilledBy;
  final String? fulfilledByName;
  final String? requestNotes;
  final String? rejectionReason;
  final DateTime createdAt;
  final DateTime? reviewedAt;
  final DateTime? fulfilledAt;
  final DateTime updatedAt;

  const StockRequestModel({
    required this.id,
    required this.requestNumber,
    required this.departmentId,
    required this.departmentName,
    required this.inventoryId,
    required this.itemName,
    this.itemSku,
    required this.itemUnit,
    this.centralStock,
    required this.requestedQuantity,
    this.approvedQuantity,
    this.fulfilledQuantity = 0.0,
    this.status = 'pending',
    required this.requestedBy,
    this.requestedByName,
    this.reviewedBy,
    this.reviewedByName,
    this.fulfilledBy,
    this.fulfilledByName,
    this.requestNotes,
    this.rejectionReason,
    required this.createdAt,
    this.reviewedAt,
    this.fulfilledAt,
    required this.updatedAt,
  });

  bool get isPending => status.toLowerCase() == 'pending';
  bool get isApproved => status.toLowerCase() == 'approved';
  bool get isRejected => status.toLowerCase() == 'rejected';
  bool get isFulfilled => status.toLowerCase() == 'fulfilled';
  bool get isCancelled => status.toLowerCase() == 'cancelled';
  bool get isTransferred => status.toLowerCase() == 'transferred';

  /// Whether stock has been physically moved (either fulfilled or directly transferred).
  bool get isStockMoved => isFulfilled || isTransferred;

  String get formattedRequestedQuantity =>
      requestedQuantity % 1 == 0 ? requestedQuantity.toInt().toString() : requestedQuantity.toStringAsFixed(1);

  String? get formattedApprovedQuantity => approvedQuantity != null
      ? (approvedQuantity! % 1 == 0 ? approvedQuantity!.toInt().toString() : approvedQuantity!.toStringAsFixed(1))
      : null;

  String get formattedFulfilledQuantity =>
      fulfilledQuantity % 1 == 0 ? fulfilledQuantity.toInt().toString() : fulfilledQuantity.toStringAsFixed(1);

  String get formattedCreatedAt =>
      DateFormat('dd MMM yyyy, h:mm a').format(createdAt.toLocal());

  String? get formattedReviewedAt => reviewedAt != null
      ? DateFormat('dd MMM yyyy, h:mm a').format(reviewedAt!.toLocal())
      : null;

  String? get formattedFulfilledAt => fulfilledAt != null
      ? DateFormat('dd MMM yyyy, h:mm a').format(fulfilledAt!.toLocal())
      : null;

  String get statusLabel {
    switch (status.toLowerCase()) {
      case 'pending':
        return 'Pending Review';
      case 'approved':
        return 'Approved';
      case 'rejected':
        return 'Rejected';
      case 'fulfilled':
        return 'Fulfilled';
      case 'cancelled':
        return 'Cancelled';
      case 'transferred':
        return 'Transferred';
      default:
        return status.toUpperCase();
    }
  }

  factory StockRequestModel.fromJson(Map<String, dynamic> json) {
    final dept = json['departments'] as Map<String, dynamic>?;
    final inv = json['inventory'] as Map<String, dynamic>?;
    final reqProfile = json['requester'] as Map<String, dynamic>?;
    final revProfile = json['reviewer'] as Map<String, dynamic>?;
    final fulProfile = json['fulfiller'] as Map<String, dynamic>?;

    final rawStatus = (json['status'] ?? 'pending').toString().toLowerCase();
    final safeStatus = validStatuses.contains(rawStatus) ? rawStatus : 'pending';

    return StockRequestModel(
      id: (json['id'] ?? '').toString(),
      requestNumber: (json['request_number'] ?? 'REQ-0000').toString(),
      departmentId: (json['department_id'] ?? dept?['id'] ?? '').toString(),
      departmentName: (json['department_name'] ?? dept?['name'] ?? 'Department').toString(),
      inventoryId: (json['inventory_id'] ?? inv?['id'] ?? '').toString(),
      itemName: (json['item_name'] ?? inv?['name'] ?? 'Inventory Item').toString(),
      itemSku: (json['item_sku'] ?? inv?['sku']) as String?,
      itemUnit: (json['item_unit'] ?? inv?['unit'] ?? 'units').toString(),
      centralStock: (json['central_stock'] as num?)?.toDouble() ?? (inv?['quantity'] as num?)?.toDouble(),
      requestedQuantity: (json['requested_quantity'] as num?)?.toDouble() ?? 0.0,
      approvedQuantity: (json['approved_quantity'] as num?)?.toDouble(),
      fulfilledQuantity: (json['fulfilled_quantity'] as num?)?.toDouble() ?? 0.0,
      status: safeStatus,
      requestedBy: (json['requested_by'] ?? '').toString(),
      requestedByName: (json['requested_by_name'] ?? reqProfile?['full_name']) as String?,
      reviewedBy: json['reviewed_by'] as String?,
      reviewedByName: (json['reviewed_by_name'] ?? revProfile?['full_name']) as String?,
      fulfilledBy: json['fulfilled_by'] as String?,
      fulfilledByName: (json['fulfilled_by_name'] ?? fulProfile?['full_name']) as String?,
      requestNotes: json['request_notes'] as String?,
      rejectionReason: json['rejection_reason'] as String?,
      createdAt: json['created_at'] != null
          ? DateTime.tryParse(json['created_at'].toString()) ?? DateTime.now()
          : DateTime.now(),
      reviewedAt: json['reviewed_at'] != null ? DateTime.tryParse(json['reviewed_at'].toString()) : null,
      fulfilledAt: json['fulfilled_at'] != null ? DateTime.tryParse(json['fulfilled_at'].toString()) : null,
      updatedAt: json['updated_at'] != null
          ? DateTime.tryParse(json['updated_at'].toString()) ?? DateTime.now()
          : DateTime.now(),
    );
  }

  Map<String, dynamic> toJson() => {
    'id': id,
    'request_number': requestNumber,
    'department_id': departmentId,
    'department_name': departmentName,
    'inventory_id': inventoryId,
    'item_name': itemName,
    'item_sku': itemSku,
    'item_unit': itemUnit,
    'central_stock': centralStock,
    'requested_quantity': requestedQuantity,
    'approved_quantity': approvedQuantity,
    'fulfilled_quantity': fulfilledQuantity,
    'status': status,
    'requested_by': requestedBy,
    'requested_by_name': requestedByName,
    'reviewed_by': reviewedBy,
    'reviewed_by_name': reviewedByName,
    'fulfilled_by': fulfilledBy,
    'fulfilled_by_name': fulfilledByName,
    'request_notes': requestNotes,
    'rejection_reason': rejectionReason,
    'created_at': createdAt.toIso8601String(),
    'reviewed_at': reviewedAt?.toIso8601String(),
    'fulfilled_at': fulfilledAt?.toIso8601String(),
    'updated_at': updatedAt.toIso8601String(),
  };
}
