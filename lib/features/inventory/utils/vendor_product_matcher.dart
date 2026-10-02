import '../../vendors/models/vendor.dart';
import '../models/inventory_item.dart';

/// Determines whether an [InventoryItem] is supplied by a given [Vendor].
///
/// Matches if either:
/// 1. The inventory item has this vendor explicitly assigned via `item.vendorId == vendor.id`.
/// 2. The vendor's `productsSupplied` list contains the item's name (case-insensitive) or item ID.
bool isProductSuppliedByVendor(InventoryItem item, Vendor vendor) {
  // 1. Direct foreign-key association
  if (item.vendorId != null &&
      item.vendorId!.isNotEmpty &&
      item.vendorId == vendor.id) {
    return true;
  }

  // 2. Vendor's products_supplied list (name-based or id-based)
  final lowerItemName = item.name.trim().toLowerCase();
  return vendor.productsSupplied.any((p) {
    final trimmed = p.trim();
    return trimmed.toLowerCase() == lowerItemName || trimmed == item.id;
  });
}
