import 'package:flutter/foundation.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:supabase_flutter/supabase_flutter.dart';

import '../../../core/providers/supabase_provider.dart';
import '../models/vendor.dart';

/// Provider for [VendorRepository].
final vendorRepositoryProvider = Provider<VendorRepository>((ref) {
  return VendorRepository(ref.watch(supabaseProvider));
});

/// Supabase repository managing CRUD operations for vendors.
class VendorRepository {
  final SupabaseClient _supabase;

  VendorRepository(this._supabase);

  /// Fetches all vendors with optional search query and activeOnly filter.
  Future<List<Vendor>> getVendors({
    String? searchQuery,
    bool? activeOnly,
  }) async {
    try {
      var query = _supabase.from('vendors').select();

      if (activeOnly == true) {
        query = query.eq('is_active', true);
      }

      final normalizedQuery = searchQuery?.trim();
      if (normalizedQuery != null && normalizedQuery.isNotEmpty) {
        query = query.or(
          'name.ilike.%$normalizedQuery%,contact_person.ilike.%$normalizedQuery%,phone.ilike.%$normalizedQuery%,email.ilike.%$normalizedQuery%',
        );
      }

      final response = await query.order('name', ascending: true);

      final vendors = (response as List)
          .map((json) => Vendor.fromJson(json as Map<String, dynamic>))
          .toList();

      debugPrint('VendorRepository.getVendors count=${vendors.length}');
      return vendors;
    } on PostgrestException catch (e) {
      debugPrint('VendorRepository.getVendors PostgrestException: ${e.message}');
      throw Exception('Database error loading vendors: ${e.message}');
    } catch (e) {
      debugPrint('VendorRepository.getVendors error: $e');
      rethrow;
    }
  }

  /// Fetches a single vendor by ID.
  Future<Vendor> getVendor(String id) async {
    try {
      final response = await _supabase
          .from('vendors')
          .select()
          .eq('id', id)
          .single();

      return Vendor.fromJson(response);
    } on PostgrestException catch (e) {
      debugPrint('VendorRepository.getVendor PostgrestException: ${e.message}');
      throw Exception('Database error loading vendor: ${e.message}');
    } catch (e) {
      debugPrint('VendorRepository.getVendor error: $e');
      rethrow;
    }
  }

  /// Creates a new vendor in the database.
  Future<Vendor> createVendor(Vendor vendor) async {
    if (vendor.name.trim().isEmpty) {
      throw ArgumentError('Vendor name is required.');
    }

    try {
      final payload = vendor.toJson(includeId: false);
      final response = await _supabase
          .from('vendors')
          .insert(payload)
          .select()
          .single();

      debugPrint('VendorRepository.createVendor created id=${response['id']}');
      return Vendor.fromJson(response);
    } on PostgrestException catch (e) {
      debugPrint('VendorRepository.createVendor PostgrestException: ${e.message}');
      throw Exception('Database error creating vendor: ${e.message}');
    } catch (e) {
      debugPrint('VendorRepository.createVendor error: $e');
      rethrow;
    }
  }

  /// Updates an existing vendor in the database.
  Future<Vendor> updateVendor(Vendor vendor) async {
    if (vendor.id.trim().isEmpty) {
      throw ArgumentError('Vendor ID is required for update.');
    }
    if (vendor.name.trim().isEmpty) {
      throw ArgumentError('Vendor name is required.');
    }

    try {
      final payload = vendor.toJson(includeId: false);
      final response = await _supabase
          .from('vendors')
          .update(payload)
          .eq('id', vendor.id)
          .select()
          .single();

      debugPrint('VendorRepository.updateVendor updated id=${vendor.id}');
      return Vendor.fromJson(response);
    } on PostgrestException catch (e) {
      debugPrint('VendorRepository.updateVendor PostgrestException: ${e.message}');
      throw Exception('Database error updating vendor: ${e.message}');
    } catch (e) {
      debugPrint('VendorRepository.updateVendor error: $e');
      rethrow;
    }
  }

  /// Deletes a vendor by ID.
  Future<void> deleteVendor(String id) async {
    if (id.trim().isEmpty) {
      throw ArgumentError('Vendor ID is required for deletion.');
    }

    try {
      await _supabase.from('vendors').delete().eq('id', id);
      debugPrint('VendorRepository.deleteVendor deleted id=$id');
    } on PostgrestException catch (e) {
      debugPrint('VendorRepository.deleteVendor PostgrestException: ${e.message}');
      throw Exception('Database error deleting vendor: ${e.message}');
    } catch (e) {
      debugPrint('VendorRepository.deleteVendor error: $e');
      rethrow;
    }
  }

  /// Toggles a vendor's active/inactive status.
  Future<Vendor> toggleVendorStatus(String id, bool isActive) async {
    try {
      final response = await _supabase
          .from('vendors')
          .update({'is_active': isActive})
          .eq('id', id)
          .select()
          .single();

      return Vendor.fromJson(response);
    } on PostgrestException catch (e) {
      debugPrint('VendorRepository.toggleVendorStatus PostgrestException: ${e.message}');
      throw Exception('Database error toggling vendor status: ${e.message}');
    } catch (e) {
      debugPrint('VendorRepository.toggleVendorStatus error: $e');
      rethrow;
    }
  }
}
