import 'package:flutter/foundation.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:supabase_flutter/supabase_flutter.dart';

import '../../../core/providers/supabase_provider.dart';
import '../models/department_inventory_item.dart';
import '../models/stock_request_model.dart';

final departmentInventoryRepositoryProvider =
    Provider<DepartmentInventoryRepository>((ref) {
  try {
    return DepartmentInventoryRepository(ref.watch(supabaseProvider));
  } catch (_) {
    return DepartmentInventoryRepository(Supabase.instance.client);
  }
});

class DepartmentInventoryRepository {
  DepartmentInventoryRepository(this._supabase);

  final SupabaseClient _supabase;

  static const String _deptInvView = 'department_inventory_records';
  static const String _stockReqView = 'stock_request_records';

  /// Fetches allocated stock for a specific department or all departments (if admin).
  Future<List<DepartmentInventoryItem>> fetchDepartmentInventory({
    String? departmentId,
    String? searchQuery,
    bool? lowStockOnly,
  }) async {
    try {
      dynamic query;
      try {
        query = _supabase.from(_deptInvView).select();
      } catch (_) {
        query = _supabase.from('department_inventory').select(
              '*, departments(id, name), inventory(id, name, sku, unit, category, brand, is_active)',
            );
      }

      if (departmentId != null &&
          departmentId.isNotEmpty &&
          departmentId != 'all') {
        query = query.eq('department_id', departmentId);
      }

      if (lowStockOnly == true) {
        query = query.eq('is_low_stock', true);
      }

      final normalizedQuery = searchQuery?.trim();
      if (normalizedQuery != null && normalizedQuery.isNotEmpty) {
        query = query.or(
          'item_name.ilike.%$normalizedQuery%,item_sku.ilike.%$normalizedQuery%,item_category.ilike.%$normalizedQuery%',
        );
      }

      final response = await query.order('item_name', ascending: true);
      final items = (response as List<dynamic>)
          .map((json) => DepartmentInventoryItem.fromJson(
              Map<String, dynamic>.from(json as Map)))
          .toList();

      return items;
    } catch (e) {
      debugPrint('DepartmentInventoryRepository.fetchDepartmentInventory error: $e');
      rethrow;
    }
  }

  /// Fetches stock requests with optional department, status, and search filters.
  Future<List<StockRequestModel>> fetchStockRequests({
    String? departmentId,
    String? status,
    String? searchQuery,
  }) async {
    try {
      dynamic query;
      try {
        query = _supabase.from(_stockReqView).select();
      } catch (_) {
        query = _supabase.from('stock_requests').select(
              '*, departments(id, name), inventory(id, name, sku, unit, quantity), requester:profiles!stock_requests_requested_by_fkey(full_name), reviewer:profiles!stock_requests_reviewed_by_fkey(full_name), fulfiller:profiles!stock_requests_fulfilled_by_fkey(full_name)',
            );
      }

      if (departmentId != null &&
          departmentId.isNotEmpty &&
          departmentId != 'all') {
        query = query.eq('department_id', departmentId);
      }

      if (status != null && status.isNotEmpty && status != 'all') {
        query = query.eq('status', status.toLowerCase());
      }

      final normalizedQuery = searchQuery?.trim();
      if (normalizedQuery != null && normalizedQuery.isNotEmpty) {
        query = query.or(
          'request_number.ilike.%$normalizedQuery%,item_name.ilike.%$normalizedQuery%,department_name.ilike.%$normalizedQuery%',
        );
      }

      final response = await query.order('created_at', ascending: false);
      final list = (response as List<dynamic>)
          .map((json) => StockRequestModel.fromJson(
              Map<String, dynamic>.from(json as Map)))
          .toList();

      return list;
    } catch (e) {
      debugPrint('DepartmentInventoryRepository.fetchStockRequests error: $e');
      rethrow;
    }
  }

  /// Submits a stock request and atomically transfers stock from central to department.
  /// This replaces the old submit → approve → fulfill workflow with a single atomic operation.
  Future<Map<String, dynamic>> submitAndTransferStock({
    required String inventoryId,
    required double requestedQuantity,
    required String targetDeptId,
    String? notes,
  }) async {
    if (requestedQuantity <= 0) {
      throw ArgumentError('Requested quantity must be greater than zero.');
    }

    if (targetDeptId.trim().isEmpty) {
      throw ArgumentError('Target department is required.');
    }

    try {
      final response = await _supabase.rpc(
        'submit_and_transfer_stock',
        params: {
          'p_inventory_id': inventoryId,
          'p_requested_quantity': requestedQuantity,
          'p_target_dept_id': targetDeptId.trim(),
          'p_notes': (notes != null && notes.trim().isNotEmpty) ? notes.trim() : null,
        },
      );

      return Map<String, dynamic>.from(response as Map);
    } on PostgrestException catch (e) {
      throw Exception(e.message);
    } catch (e) {
      rethrow;
    }
  }

  /// Records department-level stock consumption (e.g. for clinical procedures).
  Future<Map<String, dynamic>> recordDepartmentConsumption({
    required String departmentId,
    required String inventoryId,
    required double quantity,
    String? patientId,
    String? recordType,
    String? recordId,
    String? remarks,
  }) async {
    if (quantity <= 0) {
      throw ArgumentError('Quantity must be greater than zero.');
    }

    try {
      final response = await _supabase.rpc(
        'record_department_stock_consumption',
        params: {
          'p_department_id': departmentId,
          'p_inventory_id': inventoryId,
          'p_quantity': quantity,
          'p_patient_id': patientId,
          'p_record_type': recordType,
          'p_record_id': recordId,
          'p_remarks': remarks,
        },
      );

      return Map<String, dynamic>.from(response as Map);
    } on PostgrestException catch (e) {
      throw Exception(e.message);
    } catch (e) {
      rethrow;
    }
  }
}
