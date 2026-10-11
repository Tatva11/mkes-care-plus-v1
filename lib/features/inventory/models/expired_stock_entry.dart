import 'package:flutter/material.dart';
import 'package:intl/intl.dart';

/// Domain model representing an expired batch or expired inventory item lot.
@immutable
class ExpiredStockEntry {
  const ExpiredStockEntry({
    required this.inventoryId,
    required this.itemName,
    required this.unit,
    this.batchId,
    this.batchNumber,
    required this.expiredQuantity,
    required this.totalAvailableStock,
    required this.expiryDate,
  });

  final String inventoryId;
  final String itemName;
  final String unit;
  final String? batchId;
  final String? batchNumber;
  final double expiredQuantity;
  final double totalAvailableStock;
  final DateTime expiryDate;

  String get formattedExpiryDate => DateFormat('dd/MM/yyyy').format(expiryDate);

  String get formattedExpiredQuantity =>
      expiredQuantity % 1 == 0 ? expiredQuantity.toInt().toString() : expiredQuantity.toStringAsFixed(2);

  String get formattedTotalStock =>
      totalAvailableStock % 1 == 0 ? totalAvailableStock.toInt().toString() : totalAvailableStock.toStringAsFixed(2);

  /// Number of days elapsed since the expiry date.
  int get daysExpired {
    final now = DateTime.now();
    final today = DateTime(now.year, now.month, now.day);
    final exp = DateTime(expiryDate.year, expiryDate.month, expiryDate.day);
    final diff = today.difference(exp).inDays;
    return diff < 0 ? 0 : diff;
  }

  String get expiryStatusDescription {
    final days = daysExpired;
    if (days == 0) return 'Expired today';
    if (days == 1) return 'Expired yesterday (1 day ago)';
    return 'Expired $days days ago';
  }
}
