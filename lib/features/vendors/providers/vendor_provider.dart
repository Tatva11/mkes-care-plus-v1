import 'package:flutter_riverpod/flutter_riverpod.dart';

import '../models/vendor.dart';
import '../repositories/vendor_repository.dart';

/// Notifier managing the full list of vendors in MKES CARE+.
class VendorNotifier extends StateNotifier<AsyncValue<List<Vendor>>> {
  final VendorRepository? _repository;

  VendorNotifier([this._repository]) : super(const AsyncValue.data([])) {
    if (_repository != null) {
      fetchVendors();
    }
  }

  /// Fetches all vendors from the repository.
  Future<void> fetchVendors() async {
    if (_repository == null) return;
    state = const AsyncValue.loading();
    try {
      final vendors = await _repository.getVendors();
      state = AsyncValue.data(vendors);
    } catch (e, st) {
      state = AsyncValue.error(e, st);
    }
  }

  /// Refreshes the vendor list while preserving state.
  Future<void> refresh() async {
    await fetchVendors();
  }

  /// Creates a new vendor and refreshes state.
  Future<Vendor> createVendor(Vendor vendor) async {
    if (_repository == null) return vendor;
    final created = await _repository.createVendor(vendor);
    await fetchVendors();
    return created;
  }

  /// Updates an existing vendor and refreshes state.
  Future<Vendor> updateVendor(Vendor vendor) async {
    if (_repository == null) return vendor;
    final updated = await _repository.updateVendor(vendor);
    await fetchVendors();
    return updated;
  }

  /// Deletes a vendor by ID and refreshes state.
  Future<void> deleteVendor(String id) async {
    if (_repository == null) return;
    await _repository.deleteVendor(id);
    await fetchVendors();
  }

  /// Toggles a vendor's active status and refreshes state.
  Future<Vendor> toggleStatus(String id, bool isActive) async {
    if (_repository == null) return Vendor(id: id, name: '', isActive: isActive);
    final updated = await _repository.toggleVendorStatus(id, isActive);
    await fetchVendors();
    return updated;
  }
}

/// Provider managing the list of vendors.
final vendorsProvider =
    StateNotifierProvider<VendorNotifier, AsyncValue<List<Vendor>>>((ref) {
  try {
    final repository = ref.watch(vendorRepositoryProvider);
    return VendorNotifier(repository);
  } catch (_) {
    return VendorNotifier();
  }
});

/// State provider for vendor search query.
final vendorSearchQueryProvider = StateProvider<String>((ref) => '');

/// State provider for vendor status filter ('All', 'Active', 'Inactive').
final vendorStatusFilterProvider = StateProvider<String>((ref) => 'All');

/// Computed provider returning the filtered and searched vendor list.
final filteredVendorsProvider = Provider<List<Vendor>>((ref) {
  final vendorsState = ref.watch(vendorsProvider);
  final vendors = vendorsState.value ?? [];

  final query = ref.watch(vendorSearchQueryProvider).trim().toLowerCase();
  final status = ref.watch(vendorStatusFilterProvider);

  return vendors.where((vendor) {
    // 1. Status Filter
    if (status == 'Active' && !vendor.isActive) {
      return false;
    }
    if (status == 'Inactive' && vendor.isActive) {
      return false;
    }

    // 2. Search Query (Vendor name, contact person, phone, email, products)
    if (query.isNotEmpty) {
      final nameMatches = vendor.name.toLowerCase().contains(query);
      final contactMatches =
          (vendor.contactPerson?.toLowerCase() ?? '').contains(query);
      final phoneMatches = (vendor.phone?.toLowerCase() ?? '').contains(query);
      final emailMatches = (vendor.email?.toLowerCase() ?? '').contains(query);
      final productsMatches = vendor.productsSupplied
          .any((p) => p.toLowerCase().contains(query));

      if (!nameMatches &&
          !contactMatches &&
          !phoneMatches &&
          !emailMatches &&
          !productsMatches) {
        return false;
      }
    }

    return true;
  }).toList();
});

/// Provider for inspecting a single vendor by ID.
final vendorDetailsProvider =
    FutureProvider.family<Vendor, String>((ref, id) async {
  final repository = ref.watch(vendorRepositoryProvider);
  return repository.getVendor(id);
});

/// Provider for count of active vendors.
final activeVendorsCountProvider = Provider<int>((ref) {
  final vendors = ref.watch(vendorsProvider).value ?? [];
  return vendors.where((v) => v.isActive).length;
});

/// Provider for total count of vendors.
final totalVendorsCountProvider = Provider<int>((ref) {
  final vendors = ref.watch(vendorsProvider).value ?? [];
  return vendors.length;
});
