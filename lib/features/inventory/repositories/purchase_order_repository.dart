import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:supabase_flutter/supabase_flutter.dart';

import '../../../core/providers/supabase_provider.dart';
import '../models/purchase_order.dart';

/// Provider for [PurchaseOrderRepository].
final purchaseOrderRepositoryProvider = Provider<PurchaseOrderRepository>((ref) {
  try {
    return PurchaseOrderRepository(ref.watch(supabaseProvider));
  } catch (_) {
    return PurchaseOrderRepository(null);
  }
});

/// Supabase repository managing CRUD, status transitions, and atomic receiving for Purchase Orders.
class PurchaseOrderRepository {
  final SupabaseClient? _supabase;

  PurchaseOrderRepository([this._supabase]);

  static const String _poSelectWithProfiles =
      '*, vendors(name, phone), created_by_profile:profiles!purchase_orders_created_by_fkey(full_name), ordered_by_profile:profiles!purchase_orders_ordered_by_fkey(full_name), purchase_order_items(*, inventory(name, unit, sku))';

  static const String _poSelectWithCreatedByOnly =
      '*, vendors(name, phone), created_by_profile:profiles!purchase_orders_created_by_fkey(full_name), purchase_order_items(*, inventory(name, unit, sku))';

  static const String _poSelectWithoutProfiles =
      '*, vendors(name, phone), purchase_order_items(*, inventory(name, unit, sku))';

  /// Fetches purchase orders with optional filtering by status, vendor, and search query.
  Future<List<PurchaseOrder>> getPurchaseOrders({
    String? status,
    String? vendorId,
    String? searchQuery,
  }) async {
    final client = _supabase;
    if (client == null) return const [];

    try {
      dynamic response;
      try {
        var query = client.from('purchase_orders').select(_poSelectWithProfiles);

        if (status != null && status.isNotEmpty && status.toLowerCase() != 'all') {
          query = query.eq('status', status.toLowerCase().replaceAll(' ', '_'));
        }

        if (vendorId != null && vendorId.isNotEmpty && vendorId.toLowerCase() != 'all') {
          query = query.eq('vendor_id', vendorId);
        }

        response = await query.order('created_at', ascending: false);
      } catch (_) {
        try {
          var query = client.from('purchase_orders').select(_poSelectWithCreatedByOnly);

          if (status != null && status.isNotEmpty && status.toLowerCase() != 'all') {
            query = query.eq('status', status.toLowerCase().replaceAll(' ', '_'));
          }

          if (vendorId != null && vendorId.isNotEmpty && vendorId.toLowerCase() != 'all') {
            query = query.eq('vendor_id', vendorId);
          }

          response = await query.order('created_at', ascending: false);
        } catch (_) {
          var query = client.from('purchase_orders').select(_poSelectWithoutProfiles);

          if (status != null && status.isNotEmpty && status.toLowerCase() != 'all') {
            query = query.eq('status', status.toLowerCase().replaceAll(' ', '_'));
          }

          if (vendorId != null && vendorId.isNotEmpty && vendorId.toLowerCase() != 'all') {
            query = query.eq('vendor_id', vendorId);
          }

          response = await query.order('created_at', ascending: false);
        }
      }

      var list = (response as List<dynamic>)
          .map((json) => PurchaseOrder.fromJson(json as Map<String, dynamic>))
          .toList();

      list = await _enrichWithProfiles(client, list);

      if (searchQuery != null && searchQuery.trim().isNotEmpty) {
        final q = searchQuery.trim().toLowerCase();
        return list.where((po) {
          final numberMatch = po.purchaseOrderNumber.toLowerCase().contains(q);
          final vendorMatch = po.vendorName?.toLowerCase().contains(q) ?? false;
          final notesMatch = po.notes?.toLowerCase().contains(q) ?? false;
          final itemsMatch = po.items.any(
            (i) => i.inventoryName.toLowerCase().contains(q),
          );
          return numberMatch || vendorMatch || notesMatch || itemsMatch;
        }).toList();
      }

      return list;
    } catch (e) {
      throw Exception('Failed to fetch purchase orders: $e');
    }
  }

  /// Fetches a single purchase order by ID with all related items and vendor info.
  Future<PurchaseOrder> getPurchaseOrder(String id) async {
    final client = _supabase;
    if (client == null) throw Exception('Supabase client not initialized');

    try {
      dynamic response;
      try {
        response = await client
            .from('purchase_orders')
            .select(_poSelectWithProfiles)
            .eq('id', id)
            .single();
      } catch (_) {
        try {
          response = await client
              .from('purchase_orders')
              .select(_poSelectWithCreatedByOnly)
              .eq('id', id)
              .single();
        } catch (_) {
          response = await client
              .from('purchase_orders')
              .select(_poSelectWithoutProfiles)
              .eq('id', id)
              .single();
        }
      }

      final po = PurchaseOrder.fromJson(response as Map<String, dynamic>);
      final enriched = await _enrichWithProfiles(client, [po]);
      return enriched.first;
    } catch (e) {
      throw Exception('Failed to fetch purchase order $id: $e');
    }
  }

  Future<List<PurchaseOrder>> _enrichWithProfiles(
    SupabaseClient client,
    List<PurchaseOrder> orders,
  ) async {
    final needsEnrichment = orders.any((po) =>
        ((po.createdByName == null || po.createdByName!.trim().isEmpty || _isUuid(po.createdByName)) &&
            po.createdBy != null &&
            po.createdBy!.trim().isNotEmpty) ||
        ((po.orderedByName == null || po.orderedByName!.trim().isEmpty || _isUuid(po.orderedByName)) &&
            po.orderedBy != null &&
            po.orderedBy!.trim().isNotEmpty));

    if (!needsEnrichment) return orders;

    try {
      final rows = await client.from('profiles').select('id, full_name');
      final nameMap = <String, String>{};
      for (final r in (rows as List<dynamic>)) {
        final id = r['id'] as String?;
        final name = r['full_name'] as String?;
        if (id != null && name != null && name.trim().isNotEmpty) {
          nameMap[id] = name.trim();
        }
      }

      if (nameMap.isEmpty) return orders;

      return orders.map((po) {
        String? newCreated = po.createdByName;
        if (newCreated == null || newCreated.trim().isEmpty || _isUuid(newCreated)) {
          if (po.createdBy != null && nameMap.containsKey(po.createdBy)) {
            newCreated = nameMap[po.createdBy];
          }
        }

        String? newOrdered = po.orderedByName;
        if (newOrdered == null || newOrdered.trim().isEmpty || _isUuid(newOrdered)) {
          if (po.orderedBy != null && nameMap.containsKey(po.orderedBy)) {
            newOrdered = nameMap[po.orderedBy];
          }
        }

        if (newCreated != po.createdByName || newOrdered != po.orderedByName) {
          return po.copyWith(
            createdByName: newCreated,
            orderedByName: newOrdered,
          );
        }
        return po;
      }).toList();
    } catch (_) {
      return orders;
    }
  }

  static bool _isUuid(String? str) {
    if (str == null || str.trim().isEmpty) return false;
    return RegExp(
      r'^[0-9a-fA-F]{8}-[0-9a-fA-F]{4}-[0-9a-fA-F]{4}-[0-9a-fA-F]{4}-[0-9a-fA-F]{12}$',
    ).hasMatch(str.trim());
  }

  /// Creates a new purchase order along with its line items.
  Future<PurchaseOrder> createPurchaseOrder(
    PurchaseOrder order,
    List<PurchaseOrderItem> items,
  ) async {
    final client = _supabase;
    if (client == null) throw Exception('Supabase client not initialized');

    if (!order.hasValidDates) {
      throw Exception('Expected delivery date cannot be before the order date.');
    }

    try {
      final currentUserId = client.auth.currentUser?.id;

      // Calculate totals
      final total = items.fold(0.0, (sum, i) => sum + i.totalAmount);
      final poData = order.toJson(includeId: false);
      poData['subtotal'] = total;
      poData['total_amount'] = total;
      if (currentUserId != null) {
        poData['created_by'] = currentUserId;
      }
      if (order.status == PurchaseOrderStatus.ordered) {
        if (currentUserId != null) {
          poData['ordered_by'] = currentUserId;
        }
        poData['ordered_at'] = DateTime.now().toUtc().toIso8601String();
      }

      // Concurrency-safe daily PO number generation: PO-DDMMYYYY-0001
      String poNum = order.purchaseOrderNumber.trim();
      if (poNum.isEmpty || poNum == 'AUTO' || poNum.startsWith('TEMP-')) {
        try {
          final res = await client.rpc('generate_po_number');
          if (res != null && res.toString().isNotEmpty) {
            poNum = res.toString();
          }
        } catch (_) {
          // If RPC is not available in DB, generate compliant PO-DDMMYYYY-0001 using actual creation date
          final today = DateTime.now();
          final dayStr = today.day.toString().padLeft(2, '0');
          final monthStr = today.month.toString().padLeft(2, '0');
          final dateStr = '$dayStr$monthStr${today.year}';
          final prefix = 'PO-$dateStr-';

          int nextSeq = 1;
          try {
            final existing = await client
                .from('purchase_orders')
                .select('purchase_order_number')
                .ilike('purchase_order_number', '$prefix%')
                .order('purchase_order_number', ascending: false)
                .limit(1);

            if (existing.isNotEmpty) {
              final last = existing.first['purchase_order_number'] as String?;
              if (last != null) {
                final parts = last.split('-');
                if (parts.length >= 3) {
                  final parsed = int.tryParse(parts[2]);
                  if (parsed != null) nextSeq = parsed + 1;
                }
              }
            }
          } catch (_) {}

          poNum = '$prefix${nextSeq.toString().padLeft(4, '0')}';
        }
      }

      poData['purchase_order_number'] = poNum;

      final createdPoJson = await client
          .from('purchase_orders')
          .insert(poData)
          .select()
          .single();

      final createdPoId = createdPoJson['id'] as String;

      // Insert line items
      if (items.isNotEmpty) {
        final itemsData = items.map((item) {
          final itemJson = item.toJson(includeId: false);
          itemJson['purchase_order_id'] = createdPoId;
          return itemJson;
        }).toList();

        await client.from('purchase_order_items').insert(itemsData);
      }

      return getPurchaseOrder(createdPoId);
    } catch (e) {
      throw Exception('Failed to create purchase order: $e');
    }
  }

  /// Updates an existing draft or ordered purchase order and replaces its items.
  /// Preserves the original purchase order number (strictly immutable).
  Future<PurchaseOrder> updatePurchaseOrder(
    PurchaseOrder order,
    List<PurchaseOrderItem> items,
  ) async {
    final client = _supabase;
    if (client == null) throw Exception('Supabase client not initialized');

    if (!order.hasValidDates) {
      throw Exception('Expected delivery date cannot be before the order date.');
    }

    try {
      final total = items.fold(0.0, (sum, i) => sum + i.totalAmount);
      final updateData = order.toJson(includeId: false);
      updateData['subtotal'] = total;
      updateData['total_amount'] = total;
      updateData['updated_at'] = DateTime.now().toUtc().toIso8601String();

      // If transition to ordered, record order placement audit
      if (order.status == PurchaseOrderStatus.ordered) {
        final currentUserId = client.auth.currentUser?.id;
        if (currentUserId != null && (updateData['ordered_by'] == null || updateData['ordered_by'] == '')) {
          updateData['ordered_by'] = currentUserId;
        }
        if (updateData['ordered_at'] == null) {
          updateData['ordered_at'] = DateTime.now().toUtc().toIso8601String();
        }
      }

      // Ensure purchase_order_number is NEVER modified on update (guarantees immutability)
      updateData.remove('purchase_order_number');

      await client
          .from('purchase_orders')
          .update(updateData)
          .eq('id', order.id);

      // Re-synchronize line items
      await client
          .from('purchase_order_items')
          .delete()
          .eq('purchase_order_id', order.id);

      if (items.isNotEmpty) {
        final itemsData = items.map((item) {
          final itemJson = item.toJson(includeId: false);
          itemJson['purchase_order_id'] = order.id;
          return itemJson;
        }).toList();

        await client.from('purchase_order_items').insert(itemsData);
      }

      return getPurchaseOrder(order.id);
    } catch (e) {
      throw Exception('Failed to update purchase order ${order.id}: $e');
    }
  }

  /// Updates the status of a purchase order (e.g. from draft to ordered).
  Future<void> updateStatus(String id, PurchaseOrderStatus status) async {
    final client = _supabase;
    if (client == null) throw Exception('Supabase client not initialized');

    try {
      final updateData = <String, dynamic>{
        'status': status.dbValue,
        'updated_at': DateTime.now().toUtc().toIso8601String(),
      };
      if (status == PurchaseOrderStatus.ordered) {
        final currentUserId = client.auth.currentUser?.id;
        if (currentUserId != null) {
          updateData['ordered_by'] = currentUserId;
        }
        updateData['ordered_at'] = DateTime.now().toUtc().toIso8601String();
      }
      await client.from('purchase_orders').update(updateData).eq('id', id);
    } catch (e) {
      throw Exception('Failed to update status for purchase order $id: $e');
    }
  }

  /// Cancels an existing purchase order (only valid if draft or ordered).
  Future<void> cancelPurchaseOrder(String id) async {
    final client = _supabase;
    if (client == null) throw Exception('Supabase client not initialized');

    try {
      final po = await getPurchaseOrder(id);
      if (!po.canCancel) {
        throw Exception(
          'Cannot cancel purchase order with status "${po.status.label}".',
        );
      }

      await client.from('purchase_orders').update({
        'status': PurchaseOrderStatus.cancelled.dbValue,
        'updated_at': DateTime.now().toUtc().toIso8601String(),
      }).eq('id', id);
    } catch (e) {
      throw Exception('Failed to cancel purchase order: $e');
    }
  }

  /// Atomically receives quantities for items in a purchase order via database RPC.
  Future<Map<String, dynamic>> receivePurchaseOrder({
    required String purchaseOrderId,
    required List<Map<String, dynamic>> items,
  }) async {
    final client = _supabase;
    if (client == null) throw Exception('Supabase client not initialized');

    try {
      final response = await client.rpc(
        'receive_purchase_order',
        params: {
          'p_purchase_order_id': purchaseOrderId,
          'p_items': items,
        },
      );

      return response as Map<String, dynamic>;
    } catch (e) {
      throw Exception('Failed to receive purchase order: $e');
    }
  }

  /// Fetches all purchase orders associated with a vendor for Vendor Purchase History.
  Future<List<PurchaseOrder>> getVendorPurchaseOrders(String vendorId) async {
    if (_supabase == null) return const [];
    try {
      return getPurchaseOrders(vendorId: vendorId);
    } catch (e) {
      throw Exception('Failed to fetch purchase orders for vendor $vendorId: $e');
    }
  }

  /// Fetches purchase orders associated with a specific inventory item.
  Future<List<PurchaseOrder>> getInventoryPurchaseOrders(String inventoryId) async {
    if (_supabase == null) return const [];
    try {
      final all = await getPurchaseOrders();
      return all.where((po) => po.items.any((i) => i.inventoryId == inventoryId)).toList();
    } catch (e) {
      throw Exception('Failed to fetch purchase orders for item $inventoryId: $e');
    }
  }
}
