import 'package:flutter/foundation.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:supabase_flutter/supabase_flutter.dart';

import '../../../core/providers/supabase_provider.dart';
import '../models/inventory_item.dart';
import '../models/inventory_transaction.dart';

/// Provider for [InventoryRepository].
final inventoryRepositoryProvider = Provider<InventoryRepository>((ref) {
  return InventoryRepository(ref.watch(supabaseProvider));
});

/// Supabase repository managing CRUD and stock operations for inventory items.
class InventoryRepository {
  final SupabaseClient _supabase;

  InventoryRepository(this._supabase);

  /// Fetches inventory items with optional category, search query, and department filters.
  Future<List<InventoryItem>> getInventoryItems({
    String? category,
    String? department,
    String? searchQuery,
    bool? activeOnly,
  }) async {
    try {
      var query = _supabase.from('inventory').select('*, vendors(id, name, phone)');

      if (category != null && category.isNotEmpty && category != 'All') {
        query = query.eq('category', category);
      }

      if (department != null && department.isNotEmpty && department != 'All') {
        query = query.eq('department', department.toLowerCase());
      }

      if (activeOnly == true) {
        query = query.eq('is_active', true);
      }

      final normalizedQuery = searchQuery?.trim();
      if (normalizedQuery != null && normalizedQuery.isNotEmpty) {
        query = query.or(
          'name.ilike.%$normalizedQuery%,category.ilike.%$normalizedQuery%,sku.ilike.%$normalizedQuery%',
        );
      }

      final response = await query.order('name', ascending: true);

      final items = (response as List)
          .map((json) => InventoryItem.fromJson(json as Map<String, dynamic>))
          .toList();

      debugPrint('InventoryRepository.getInventoryItems count=${items.length}');
      return items;
    } on PostgrestException catch (e) {
      debugPrint('InventoryRepository PostgrestException: ${e.message}');
      throw Exception('Database error loading inventory: ${e.message}');
    } catch (e) {
      debugPrint('InventoryRepository getInventoryItems error: $e');
      rethrow;
    }
  }

  /// Fetches a single inventory item by [id].
  Future<InventoryItem> getInventoryItem(String id) async {
    try {
      final response = await _supabase
          .from('inventory')
          .select('*, vendors(id, name, phone)')
          .eq('id', id)
          .single();

      return InventoryItem.fromJson(response);
    } on PostgrestException catch (e) {
      debugPrint('InventoryRepository.getInventoryItem PostgrestException: ${e.message}');
      throw Exception('Database error fetching inventory item: ${e.message}');
    } catch (e) {
      debugPrint('InventoryRepository.getInventoryItem error: $e');
      rethrow;
    }
  }

  /// Creates a new inventory item and returns the persisted record.
  Future<InventoryItem> createInventoryItem(InventoryItem item) async {
    try {
      final insertData = item.toJson(includeId: item.id.isNotEmpty);
      insertData['created_at'] = DateTime.now().toUtc().toIso8601String();
      insertData['updated_at'] = DateTime.now().toUtc().toIso8601String();

      final response = await _supabase
          .from('inventory')
          .insert(insertData)
          .select('*, vendors(id, name, phone)')
          .single();

      final created = InventoryItem.fromJson(response);
      debugPrint('InventoryRepository.createInventoryItem created id=${created.id}');
      return created;
    } on PostgrestException catch (e) {
      debugPrint('InventoryRepository.createInventoryItem PostgrestException: ${e.message}');
      throw Exception('Database error creating item: ${e.message}');
    } catch (e) {
      debugPrint('InventoryRepository.createInventoryItem error: $e');
      rethrow;
    }
  }

  /// Updates an existing inventory item in the database.
  Future<InventoryItem> updateInventoryItem(InventoryItem item) async {
    try {
      final updateData = item.toJson(includeId: false);
      updateData['updated_at'] = DateTime.now().toUtc().toIso8601String();

      final response = await _supabase
          .from('inventory')
          .update(updateData)
          .eq('id', item.id)
          .select('*, vendors(id, name, phone)')
          .single();

      final updated = InventoryItem.fromJson(response);
      debugPrint('InventoryRepository.updateInventoryItem updated id=${updated.id}');
      return updated;
    } on PostgrestException catch (e) {
      debugPrint('InventoryRepository.updateInventoryItem PostgrestException: ${e.message}');
      throw Exception('Database error updating item: ${e.message}');
    } catch (e) {
      debugPrint('InventoryRepository.updateInventoryItem error: $e');
      rethrow;
    }
  }

  /// Deletes an inventory item from the database.
  Future<void> deleteInventoryItem(String id) async {
    try {
      await _supabase.from('inventory').delete().eq('id', id);
      debugPrint('InventoryRepository.deleteInventoryItem deleted id=$id');
    } on PostgrestException catch (e) {
      debugPrint('InventoryRepository.deleteInventoryItem PostgrestException: ${e.message}');
      throw Exception('Database error deleting item: ${e.message}');
    } catch (e) {
      debugPrint('InventoryRepository.deleteInventoryItem error: $e');
      rethrow;
    }
  }

  /// Executes an atomic stock operation (Stock In or Stock Out) using the Supabase RPC.
  /// Locks the row, validates sufficient stock, updates quantity, validates patient, and records an audit transaction.
  Future<InventoryTransaction> performStockOperation({
    required String itemId,
    required String transactionType, // 'stock_in' | 'stock_out'
    required double quantity,
    String? reason,
    String? remarks,
    String? patientId,
    double? totalAmount,
    String? vendorId,
  }) async {
    if (quantity <= 0) {
      throw ArgumentError('Stock quantity must be greater than zero.');
    }
    if (transactionType != 'stock_in' && transactionType != 'stock_out') {
      throw ArgumentError('Transaction type must be stock_in or stock_out.');
    }

    try {
      final params = <String, dynamic>{
        'p_inventory_id': itemId,
        'p_transaction_type': transactionType,
        'p_quantity': quantity,
        'p_reason': (reason != null && reason.trim().isNotEmpty) ? reason.trim() : null,
        'p_remarks': (remarks != null && remarks.trim().isNotEmpty) ? remarks.trim() : null,
        'p_patient_id': (patientId != null && patientId.trim().isNotEmpty) ? patientId.trim() : null,
      };
      if (totalAmount != null) {
        params['p_total_amount'] = totalAmount;
      }
      if (vendorId != null && vendorId.trim().isNotEmpty) {
        params['p_vendor_id'] = vendorId.trim();
      }

      final response = await _supabase.rpc(
        'perform_stock_operation',
        params: params,
      );

      debugPrint('InventoryRepository.performStockOperation response: $response');

      if (response is Map<String, dynamic>) {
        final txJson = response['transaction'] as Map<String, dynamic>?;
        if (txJson != null) {
          return InventoryTransaction.fromJson(txJson);
        }
      }

      // Fallback record if RPC returns a different JSON format
      return InventoryTransaction(
        id: '',
        inventoryItemId: itemId,
        transactionType: transactionType,
        quantity: quantity,
        reason: reason,
        remarks: remarks,
        patientId: patientId,
        vendorId: vendorId,
        totalAmount: totalAmount,
        unitPrice: (quantity > 0 && totalAmount != null) ? totalAmount / quantity : null,
        createdAt: DateTime.now(),
      );
    } on PostgrestException catch (e) {
      debugPrint('InventoryRepository.performStockOperation PostgrestException: ${e.message}');
      // Return clean, user-readable error message
      throw Exception(e.message);
    } catch (e) {
      debugPrint('InventoryRepository.performStockOperation error: $e');
      rethrow;
    }
  }

  /// Fetches transaction history for a specific inventory item, ordered newest first.
  Future<List<InventoryTransaction>> getTransactionHistory(
    String inventoryItemId, {
    String? transactionType,
  }) async {
    try {
      var query = _supabase
          .from('inventory_transactions')
          .select('*, profiles!performed_by(full_name), patients(name, patient_number), vendors(id, name, phone)')
          .eq('inventory_id', inventoryItemId);

      if (transactionType != null &&
          transactionType.isNotEmpty &&
          transactionType != 'All') {
        query = query.eq('transaction_type', transactionType.toLowerCase());
      }

      final response = await query.order('created_at', ascending: false);

      final transactions = (response as List)
          .map((json) => InventoryTransaction.fromJson(json as Map<String, dynamic>))
          .toList();

      debugPrint(
        'InventoryRepository.getTransactionHistory count=${transactions.length} for item=$inventoryItemId',
      );
      return transactions;
    } on PostgrestException catch (e) {
      debugPrint('InventoryRepository.getTransactionHistory PostgrestException: ${e.message}');
      throw Exception('Database error loading transactions: ${e.message}');
    } catch (e) {
      debugPrint('InventoryRepository.getTransactionHistory error: $e');
      rethrow;
    }
  }

  /// Fetches all stock transactions across all items with optional filters (for admin audit log).
  Future<List<InventoryTransaction>> getAllTransactions({
    String? transactionType,
    int limit = 100,
  }) async {
    try {
      var query = _supabase
          .from('inventory_transactions')
          .select('*, profiles!performed_by(full_name), patients(name, patient_number), vendors(id, name, phone)');

      if (transactionType != null &&
          transactionType.isNotEmpty &&
          transactionType != 'All') {
        query = query.eq('transaction_type', transactionType.toLowerCase());
      }

      final response =
          await query.order('created_at', ascending: false).limit(limit);

      return (response as List)
          .map((json) => InventoryTransaction.fromJson(json as Map<String, dynamic>))
          .toList();
    } on PostgrestException catch (e) {
      debugPrint('InventoryRepository.getAllTransactions PostgrestException: ${e.message}');
      throw Exception('Database error loading transactions: ${e.message}');
    } catch (e) {
      debugPrint('InventoryRepository.getAllTransactions error: $e');
      rethrow;
    }
  }
}
