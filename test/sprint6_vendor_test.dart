import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:mkes_care/features/admin/widgets/operations_tab_content.dart';
import 'package:mkes_care/features/auth/providers/auth_provider.dart';
import 'package:mkes_care/features/vendors/models/vendor.dart';
import 'package:mkes_care/features/vendors/providers/vendor_provider.dart';
import 'package:mkes_care/features/vendors/repositories/vendor_repository.dart';
import 'package:mkes_care/features/vendors/screens/vendor_management_screen.dart';
import 'package:mkes_care/features/vendors/widgets/vendor_details_dialog.dart';
import 'package:mkes_care/features/vendors/widgets/vendor_form_dialog.dart';

/// Fake in-memory repository for deterministic testing without live Supabase connection.
class FakeVendorRepository implements VendorRepository {
  final List<Vendor> vendors;
  bool shouldThrow = false;

  FakeVendorRepository([List<Vendor>? initialVendors])
      : vendors = initialVendors != null ? List.from(initialVendors) : [];

  @override
  Future<List<Vendor>> getVendors({String? searchQuery, bool? activeOnly}) async {
    if (shouldThrow) throw Exception('Simulated network error');
    var result = List<Vendor>.from(vendors);

    if (activeOnly == true) {
      result = result.where((v) => v.isActive).toList();
    }

    if (searchQuery != null && searchQuery.trim().isNotEmpty) {
      final q = searchQuery.trim().toLowerCase();
      result = result.where((v) {
        return v.name.toLowerCase().contains(q) ||
            (v.contactPerson?.toLowerCase() ?? '').contains(q) ||
            (v.phone?.toLowerCase() ?? '').contains(q) ||
            (v.email?.toLowerCase() ?? '').contains(q) ||
            v.productsSupplied.any((p) => p.toLowerCase().contains(q));
      }).toList();
    }

    return result;
  }

  @override
  Future<Vendor> getVendor(String id) async {
    if (shouldThrow) throw Exception('Simulated fetch error');
    final match = vendors.firstWhere((v) => v.id == id, orElse: () {
      throw Exception('Vendor not found: $id');
    });
    return match;
  }

  @override
  Future<Vendor> createVendor(Vendor vendor) async {
    if (shouldThrow) throw Exception('Simulated create error');
    if (vendor.name.trim().isEmpty) {
      throw ArgumentError('Vendor name is required.');
    }
    final created = vendor.copyWith(
      id: vendor.id.isNotEmpty ? vendor.id : 'v-${vendors.length + 1}',
      createdAt: DateTime.now(),
      updatedAt: DateTime.now(),
    );
    vendors.add(created);
    return created;
  }

  @override
  Future<Vendor> updateVendor(Vendor vendor) async {
    if (shouldThrow) throw Exception('Simulated update error');
    if (vendor.id.trim().isEmpty) {
      throw ArgumentError('Vendor ID is required for update.');
    }
    if (vendor.name.trim().isEmpty) {
      throw ArgumentError('Vendor name is required.');
    }
    final index = vendors.indexWhere((v) => v.id == vendor.id);
    if (index != -1) {
      final updated = vendor.copyWith(updatedAt: DateTime.now());
      vendors[index] = updated;
      return updated;
    }
    vendors.add(vendor);
    return vendor;
  }

  @override
  Future<void> deleteVendor(String id) async {
    if (shouldThrow) throw Exception('Simulated delete error');
    vendors.removeWhere((v) => v.id == id);
  }

  @override
  Future<Vendor> toggleVendorStatus(String id, bool isActive) async {
    if (shouldThrow) throw Exception('Simulated toggle status error');
    final index = vendors.indexWhere((v) => v.id == id);
    if (index == -1) throw Exception('Vendor not found.');
    final updated = vendors[index].copyWith(
      isActive: isActive,
      updatedAt: DateTime.now(),
    );
    vendors[index] = updated;
    return updated;
  }
}

void main() {
  group('Sprint 6.3 — Vendor Domain Model', () {
    test('deserializes properly from Supabase json row', () {
      final json = {
        'id': 'v-101',
        'name': 'MedPlus Pharma Supplies',
        'contact_person': 'Rajesh Sharma',
        'phone': '+91 9876543210',
        'email': 'rajesh@medplus.in',
        'address': 'Plot 45, Andheri East, Mumbai',
        'products_supplied': ['Amoxicillin', 'Paracetamol', 'Surgical Gauze'],
        'last_order_date': '2026-09-10',
        'last_delivery_date': '2026-09-15',
        'last_quantity': 500.0,
        'remarks': '15% clinic discount applies',
        'is_active': true,
        'created_at': '2026-08-01T10:00:00Z',
        'updated_at': '2026-09-15T12:00:00Z',
      };

      final vendor = Vendor.fromJson(json);

      expect(vendor.id, equals('v-101'));
      expect(vendor.name, equals('MedPlus Pharma Supplies'));
      expect(vendor.contactPerson, equals('Rajesh Sharma'));
      expect(vendor.phone, equals('+91 9876543210'));
      expect(vendor.email, equals('rajesh@medplus.in'));
      expect(vendor.address, equals('Plot 45, Andheri East, Mumbai'));
      expect(vendor.productsSupplied, equals(['Amoxicillin', 'Paracetamol', 'Surgical Gauze']));
      expect(vendor.productsDisplay, equals('Amoxicillin, Paracetamol, Surgical Gauze'));
      expect(vendor.lastOrderDate, equals(DateTime(2026, 9, 10)));
      expect(vendor.lastDeliveryDate, equals(DateTime(2026, 9, 15)));
      expect(vendor.formattedLastOrder, equals('2026-09-10'));
      expect(vendor.formattedLastDelivery, equals('2026-09-15'));
      expect(vendor.lastQuantity, equals(500.0));
      expect(vendor.formattedLastQuantity, equals('500'));
      expect(vendor.remarks, equals('15% clinic discount applies'));
      expect(vendor.isActive, isTrue);
      expect(vendor.statusLabel, equals('Active'));
    });

    test('deserializes PostgreSQL array literal and handles null fields safely', () {
      final json = {
        'id': 'v-102',
        'name': 'ClearVision Optical Ltd',
        'products_supplied': '{"Contact Lenses","Eye Drops","Frames"}',
        'is_active': false,
      };

      final vendor = Vendor.fromJson(json);

      expect(vendor.id, equals('v-102'));
      expect(vendor.name, equals('ClearVision Optical Ltd'));
      expect(vendor.productsSupplied, equals(['Contact Lenses', 'Eye Drops', 'Frames']));
      expect(vendor.contactPerson, isNull);
      expect(vendor.phone, isNull);
      expect(vendor.email, isNull);
      expect(vendor.address, isNull);
      expect(vendor.lastOrderDate, isNull);
      expect(vendor.formattedLastOrder, equals('—'));
      expect(vendor.lastDeliveryDate, isNull);
      expect(vendor.formattedLastDelivery, equals('—'));
      expect(vendor.lastQuantity, isNull);
      expect(vendor.formattedLastQuantity, equals('—'));
      expect(vendor.isActive, isFalse);
      expect(vendor.statusLabel, equals('Inactive'));
    });

    test('serializes to json matching Supabase columns', () {
      final vendor = Vendor(
        id: 'v-103',
        name: 'Apex Dental Wholesalers',
        contactPerson: 'Dr. Mehta',
        phone: '9822001122',
        email: 'sales@apexdental.com',
        address: 'Bandra West, Mumbai',
        productsSupplied: const ['Dental Cement', 'Gloves'],
        lastOrderDate: DateTime(2026, 9, 20),
        lastDeliveryDate: DateTime(2026, 9, 25),
        lastQuantity: 150.5,
        remarks: 'Net 30 payment terms',
        isActive: true,
      );

      final json = vendor.toJson();

      expect(json['id'], equals('v-103'));
      expect(json['name'], equals('Apex Dental Wholesalers'));
      expect(json['contact_person'], equals('Dr. Mehta'));
      expect(json['phone'], equals('9822001122'));
      expect(json['email'], equals('sales@apexdental.com'));
      expect(json['address'], equals('Bandra West, Mumbai'));
      expect(json['products_supplied'], equals(['Dental Cement', 'Gloves']));
      expect(json['last_order_date'], equals('2026-09-20'));
      expect(json['last_delivery_date'], equals('2026-09-25'));
      expect(json['last_quantity'], equals(150.5));
      expect(json['remarks'], equals('Net 30 payment terms'));
      expect(json['is_active'], isTrue);
    });

    test('copyWith produces modified copy without mutating original', () {
      const original = Vendor(
        id: 'v-copy-1',
        name: 'Original Name',
        phone: '1111111111',
        isActive: true,
      );

      final modified = original.copyWith(
        name: 'Updated Name',
        isActive: false,
      );

      expect(original.name, equals('Original Name'));
      expect(original.isActive, isTrue);
      expect(modified.id, equals('v-copy-1'));
      expect(modified.name, equals('Updated Name'));
      expect(modified.phone, equals('1111111111'));
      expect(modified.isActive, isFalse);
    });
  });

  group('Sprint 6.3 — Vendor StateNotifier & Providers', () {
    test('fetches and populates vendors successfully', () async {
      final fakeRepo = FakeVendorRepository([
        const Vendor(
          id: 'v-prov-1',
          name: 'Sun Pharma Ltd',
          isActive: true,
        ),
        const Vendor(
          id: 'v-prov-2',
          name: 'Cipla Distributors',
          isActive: false,
        ),
      ]);

      final container = ProviderContainer(
        overrides: [
          vendorRepositoryProvider.overrideWithValue(fakeRepo),
        ],
      );
      addTearDown(container.dispose);

      final state = container.read(vendorsProvider);
      expect(state.isLoading, isTrue);

      await container.read(vendorsProvider.notifier).fetchVendors();

      final updatedState = container.read(vendorsProvider);
      expect(updatedState.hasValue, isTrue);
      expect(updatedState.value!.length, equals(2));
      expect(container.read(totalVendorsCountProvider), equals(2));
      expect(container.read(activeVendorsCountProvider), equals(1));
    });

    test('creates new vendor and updates state', () async {
      final fakeRepo = FakeVendorRepository([]);
      final container = ProviderContainer(
        overrides: [
          vendorRepositoryProvider.overrideWithValue(fakeRepo),
        ],
      );
      addTearDown(container.dispose);

      final notifier = container.read(vendorsProvider.notifier);
      await notifier.createVendor(const Vendor(
        id: '',
        name: 'New Vendor Inc',
        contactPerson: 'David Brown',
      ));

      final state = container.read(vendorsProvider);
      expect(state.value!.length, equals(1));
      expect(state.value!.first.name, equals('New Vendor Inc'));
      expect(state.value!.first.contactPerson, equals('David Brown'));
    });

    test('updates vendor and updates state', () async {
      final fakeRepo = FakeVendorRepository([
        const Vendor(
          id: 'v-update-1',
          name: 'Old Vendor Name',
          phone: '1234567890',
        ),
      ]);
      final container = ProviderContainer(
        overrides: [
          vendorRepositoryProvider.overrideWithValue(fakeRepo),
        ],
      );
      addTearDown(container.dispose);

      final notifier = container.read(vendorsProvider.notifier);
      await notifier.updateVendor(const Vendor(
        id: 'v-update-1',
        name: 'Renamed Vendor',
        phone: '9998887777',
      ));

      final state = container.read(vendorsProvider);
      expect(state.value!.first.name, equals('Renamed Vendor'));
      expect(state.value!.first.phone, equals('9998887777'));
    });

    test('deletes vendor and updates state', () async {
      final fakeRepo = FakeVendorRepository([
        const Vendor(id: 'v-del-1', name: 'Vendor To Delete'),
      ]);
      final container = ProviderContainer(
        overrides: [
          vendorRepositoryProvider.overrideWithValue(fakeRepo),
        ],
      );
      addTearDown(container.dispose);

      final notifier = container.read(vendorsProvider.notifier);
      await notifier.deleteVendor('v-del-1');

      final state = container.read(vendorsProvider);
      expect(state.value!.isEmpty, isTrue);
    });

    test('toggles vendor active/inactive status', () async {
      final fakeRepo = FakeVendorRepository([
        const Vendor(id: 'v-toggle-1', name: 'Vendor Toggle', isActive: true),
      ]);
      final container = ProviderContainer(
        overrides: [
          vendorRepositoryProvider.overrideWithValue(fakeRepo),
        ],
      );
      addTearDown(container.dispose);

      final notifier = container.read(vendorsProvider.notifier);
      await notifier.toggleStatus('v-toggle-1', false);

      final state = container.read(vendorsProvider);
      expect(state.value!.first.isActive, isFalse);

      await notifier.toggleStatus('v-toggle-1', true);
      expect(container.read(vendorsProvider).value!.first.isActive, isTrue);
    });

    test('filteredVendorsProvider filters by search query and active status', () async {
      final fakeRepo = FakeVendorRepository([
        const Vendor(
          id: 'v-f-1',
          name: 'Apollo Medical Supplies',
          contactPerson: 'Suresh Patel',
          phone: '9876500001',
          email: 'apollo@care.com',
          productsSupplied: ['Gloves', 'Syringes'],
          isActive: true,
        ),
        const Vendor(
          id: 'v-f-2',
          name: 'Bharat Pharma Wholesalers',
          contactPerson: 'Karan Mehra',
          phone: '9876500002',
          email: 'bharat@pharma.com',
          productsSupplied: ['Antibiotics'],
          isActive: false,
        ),
      ]);

      final container = ProviderContainer(
        overrides: [
          vendorRepositoryProvider.overrideWithValue(fakeRepo),
        ],
      );
      addTearDown(container.dispose);

      await container.read(vendorsProvider.notifier).fetchVendors();

      // All vendors initially
      expect(container.read(filteredVendorsProvider).length, equals(2));

      // Filter by Active status
      container.read(vendorStatusFilterProvider.notifier).state = 'Active';
      expect(container.read(filteredVendorsProvider).length, equals(1));
      expect(container.read(filteredVendorsProvider).first.name, equals('Apollo Medical Supplies'));

      // Filter by Inactive status
      container.read(vendorStatusFilterProvider.notifier).state = 'Inactive';
      expect(container.read(filteredVendorsProvider).length, equals(1));
      expect(container.read(filteredVendorsProvider).first.name, equals('Bharat Pharma Wholesalers'));

      // Reset status, search by product
      container.read(vendorStatusFilterProvider.notifier).state = 'All';
      container.read(vendorSearchQueryProvider.notifier).state = 'Antibiotics';
      expect(container.read(filteredVendorsProvider).length, equals(1));
      expect(container.read(filteredVendorsProvider).first.name, equals('Bharat Pharma Wholesalers'));

      // Search by contact person
      container.read(vendorSearchQueryProvider.notifier).state = 'Suresh';
      expect(container.read(filteredVendorsProvider).length, equals(1));
      expect(container.read(filteredVendorsProvider).first.name, equals('Apollo Medical Supplies'));
    });
  });

  group('Sprint 6.3 — UI & Form Validation Tests', () {
    testWidgets('renders empty state when vendor directory has 0 items',
        (tester) async {
      final fakeRepo = FakeVendorRepository([]);

      await tester.pumpWidget(
        ProviderScope(
          overrides: [
            vendorRepositoryProvider.overrideWithValue(fakeRepo),
            currentUserRoleProvider.overrideWith((ref) => Future.value('admin')),
          ],
          child: const MaterialApp(
            home: Scaffold(body: VendorManagementContent()),
          ),
        ),
      );

      await tester.pumpAndSettle();

      expect(find.text('No Vendors Registered Yet'), findsOneWidget);
      expect(find.text('Add First Vendor'), findsOneWidget);
    });

    testWidgets('VendorFormDialog enforces required name and validates email/phone',
        (tester) async {
      final fakeRepo = FakeVendorRepository([]);

      await tester.pumpWidget(
        ProviderScope(
          overrides: [
            vendorRepositoryProvider.overrideWithValue(fakeRepo),
          ],
          child: const MaterialApp(
            home: Scaffold(
              body: VendorFormDialog(),
            ),
          ),
        ),
      );

      await tester.pumpAndSettle();

      expect(find.text('Add New Vendor'), findsOneWidget);

      // Attempt submit without filling vendor name
      await tester.tap(find.text('Create Vendor'));
      await tester.pumpAndSettle();

      expect(find.text('Vendor name is required.'), findsOneWidget);

      // Enter invalid email
      final emailField = find.byType(TextFormField).at(3);
      await tester.enterText(emailField, 'notanemail');
      await tester.tap(find.text('Create Vendor'));
      await tester.pumpAndSettle();

      expect(find.text('Enter a valid email address.'), findsOneWidget);

      // Fix email, enter valid name
      final nameField = find.byType(TextFormField).at(0);
      await tester.enterText(nameField, 'Reliable Healthcare Supplies');
      await tester.enterText(emailField, 'contact@reliable.com');
      await tester.pumpAndSettle();

      await tester.tap(find.text('Create Vendor'));
      await tester.pumpAndSettle();

      expect(fakeRepo.vendors.length, equals(1));
      expect(fakeRepo.vendors.first.name, equals('Reliable Healthcare Supplies'));
      expect(fakeRepo.vendors.first.email, equals('contact@reliable.com'));
    });

    testWidgets('VendorDetailsDialog displays all stored vendor attributes',
        (tester) async {
      final vendor = Vendor(
        id: 'v-details-1',
        name: 'Metro Surgical Devices',
        contactPerson: 'Anjali Sharma',
        phone: '+91 9123456789',
        email: 'metro@surgical.com',
        address: 'Sector 18, Gurugram',
        productsSupplied: const ['Surgical Blades', 'Sutures'],
        lastOrderDate: DateTime(2026, 9, 12),
        lastDeliveryDate: DateTime(2026, 9, 18),
        lastQuantity: 250.0,
        remarks: 'Exclusive supplier for eye department',
        isActive: true,
      );

      final fakeRepo = FakeVendorRepository([vendor]);

      await tester.pumpWidget(
        ProviderScope(
          overrides: [
            vendorRepositoryProvider.overrideWithValue(fakeRepo),
            currentUserRoleProvider.overrideWith((ref) => Future.value('admin')),
          ],
          child: MaterialApp(
            home: Scaffold(
              body: VendorDetailsDialog(vendor: vendor),
            ),
          ),
        ),
      );

      await tester.pumpAndSettle();

      // Header
      expect(find.text('Metro Surgical Devices'), findsOneWidget);
      expect(find.text('Active'), findsOneWidget);

      // Contact info
      expect(find.text('Anjali Sharma'), findsWidgets);
      expect(find.text('+91 9123456789'), findsOneWidget);
      expect(find.text('metro@surgical.com'), findsOneWidget);
      expect(find.text('Sector 18, Gurugram'), findsOneWidget);

      // Operations & supply info
      expect(find.text('2026-09-12'), findsOneWidget);
      expect(find.text('2026-09-18'), findsOneWidget);
      expect(find.text('250'), findsOneWidget);
      expect(find.text('Surgical Blades'), findsOneWidget);
      expect(find.text('Sutures'), findsOneWidget);
      expect(find.text('Exclusive supplier for eye department'), findsOneWidget);

      // Admin actions present
      expect(find.text('Edit Vendor'), findsOneWidget);
      expect(find.text('Deactivate'), findsOneWidget);
    });

    testWidgets('Role-Based: Staff has full vendor management access (Add/Edit/Delete actions)',
        (tester) async {
      const vendor = Vendor(
        id: 'v-role-1',
        name: 'Staff Viewable Vendor',
        contactPerson: 'Nurse Staff Liaison',
        isActive: true,
      );

      final fakeRepo = FakeVendorRepository([vendor]);

      await tester.pumpWidget(
        ProviderScope(
          overrides: [
            vendorRepositoryProvider.overrideWithValue(fakeRepo),
            currentUserRoleProvider.overrideWith((ref) => Future.value('staff')),
          ],
          child: const MaterialApp(
            home: Scaffold(
              body: VendorManagementContent(),
            ),
          ),
        ),
      );

      await tester.pumpAndSettle();

      // Staff sees vendor name and contact
      expect(find.text('Staff Viewable Vendor'), findsOneWidget);
      expect(find.text('Nurse Staff Liaison'), findsOneWidget);

      // Staff DOES see Add Vendor button
      expect(find.text('Add Vendor'), findsOneWidget);

      // Staff DOES see PopupMenu / more_vert action menu on card
      expect(find.byIcon(Icons.more_vert), findsOneWidget);
    });

    testWidgets('OperationsTabContent switches to Vendors tab and displays directory',
        (tester) async {
      const vendor = Vendor(
        id: 'v-tab-1',
        name: 'Precision Instruments Co',
        contactPerson: 'Vijay Kumar',
      );

      final fakeRepo = FakeVendorRepository([vendor]);

      await tester.pumpWidget(
        ProviderScope(
          overrides: [
            vendorRepositoryProvider.overrideWithValue(fakeRepo),
            currentUserRoleProvider.overrideWith((ref) => Future.value('admin')),
          ],
          child: const MaterialApp(
            home: Scaffold(
              body: OperationsTabContent(initialTab: 2),
            ),
          ),
        ),
      );

      await tester.pumpAndSettle();

      // Vendors segment is visible and highlighted
      expect(find.text('Vendors'), findsWidgets);
      expect(find.text('Vendor Directory'), findsOneWidget);
      expect(find.text('Precision Instruments Co'), findsOneWidget);
    });
  });
}
