import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:flutter_test/flutter_test.dart';

import 'package:mkes_care/features/admin/widgets/vendor_purchase_order_summary_card.dart';
import 'package:mkes_care/features/inventory/models/purchase_order.dart';
import 'package:mkes_care/features/inventory/providers/purchase_order_provider.dart';
import 'package:mkes_care/features/vendors/models/vendor.dart';
import 'package:mkes_care/features/vendors/providers/vendor_provider.dart';

class TestVendorNotifier extends StateNotifier<AsyncValue<List<Vendor>>>
    implements VendorNotifier {
  TestVendorNotifier(super.initial);

  @override
  Future<void> fetchVendors() async {}

  @override
  Future<void> refresh() async {}

  @override
  Future<Vendor> createVendor(Vendor vendor) async => vendor;

  @override
  Future<Vendor> updateVendor(Vendor vendor) async => vendor;

  @override
  Future<void> deleteVendor(String id) async {}

  @override
  Future<Vendor> toggleStatus(String id, bool isActive) async =>
      Vendor(id: id, name: '', isActive: isActive);
}

class TestPurchaseOrdersNotifier
    extends StateNotifier<AsyncValue<List<PurchaseOrder>>>
    implements PurchaseOrdersNotifier {
  TestPurchaseOrdersNotifier(super.initial);

  @override
  Future<void> fetchOrders() async {}

  @override
  Future<PurchaseOrder> createOrder(
          PurchaseOrder order, List<PurchaseOrderItem> items) async =>
      order;

  @override
  Future<PurchaseOrder> updateOrder(
          PurchaseOrder order, List<PurchaseOrderItem> items) async =>
      order;

  @override
  Future<void> updateStatus(String id, PurchaseOrderStatus status) async {}

  @override
  Future<void> cancelOrder(String id) async {}

  @override
  Future<Map<String, dynamic>> receiveOrder({
    required String purchaseOrderId,
    required List<Map<String, dynamic>> items,
  }) async =>
      {};
}

void main() {
  TestWidgetsFlutterBinding.ensureInitialized();

  final vendor1 = Vendor(
    id: 'v-1',
    name: 'Alcon India Healthcare',
    contactPerson: 'Sunil Rao',
    phone: '+91 9876543210',
    isActive: true,
  );

  final vendor2 = Vendor(
    id: 'v-2',
    name: 'Bausch & Lomb Surgical',
    contactPerson: 'Meera Nair',
    phone: '+91 9876543211',
    isActive: true,
  );

  final now = DateTime.now();

  // 1. Order placed today
  final todayPlacedPO = PurchaseOrder(
    id: 'po-1',
    purchaseOrderNumber: 'PO-2026-TODAY-1',
    vendorId: 'v-1',
    vendorName: 'Alcon India Healthcare',
    orderDate: now,
    status: PurchaseOrderStatus.ordered,
    totalAmount: 15000,
  );

  // 2. Order placed 5 days ago, but delivery is due TODAY
  final todayDeliveryPO = PurchaseOrder(
    id: 'po-2',
    purchaseOrderNumber: 'PO-2026-DUE-TODAY',
    vendorId: 'v-2',
    vendorName: 'Bausch & Lomb Surgical',
    orderDate: now.subtract(const Duration(days: 5)),
    expectedDeliveryDate: now,
    status: PurchaseOrderStatus.ordered,
    totalAmount: 32000,
  );

  // 3. Historical order from 10 days ago (no activity today)
  final historicalPO = PurchaseOrder(
    id: 'po-3',
    purchaseOrderNumber: 'PO-2026-HISTORICAL',
    vendorId: 'v-1',
    vendorName: 'Alcon India Healthcare',
    orderDate: now.subtract(const Duration(days: 10)),
    expectedDeliveryDate: now.subtract(const Duration(days: 6)),
    status: PurchaseOrderStatus.received,
    totalAmount: 8500,
  );

  group('VendorPurchaseOrderSummaryCard Tests', () {
    testWidgets(
        'Displays strictly today\'s procurement metrics and omits historical static counts',
        (tester) async {
      final vendors = [vendor1, vendor2];
      final orders = [todayPlacedPO, todayDeliveryPO, historicalPO];

      await tester.pumpWidget(
        ProviderScope(
          overrides: [
            vendorsProvider.overrideWith(
              (ref) => TestVendorNotifier(AsyncValue.data(vendors)),
            ),
            purchaseOrdersProvider.overrideWith(
              (ref) => TestPurchaseOrdersNotifier(AsyncValue.data(orders)),
            ),
          ],
          child: const MaterialApp(
            home: Scaffold(
              body: SingleChildScrollView(
                child: VendorPurchaseOrderSummaryCard(),
              ),
            ),
          ),
        ),
      );

      await tester.pumpAndSettle();

      // Today's metrics:
      expect(find.text('Orders Placed Today'), findsOneWidget);
      expect(find.text('1'), findsWidgets); // 1 order placed today

      expect(find.text('Deliveries Due Today'), findsOneWidget);

      // Verify that historical static counts like 'Total Vendors' or all-time POs are NOT displayed
      expect(find.text('Total Vendors'), findsNothing);

      // Verify today's activity section is rendered
      expect(find.text("Today's Procurement Activity"), findsOneWidget);
      expect(find.text('PO-2026-TODAY-1'), findsOneWidget);
      expect(find.text('PO-2026-DUE-TODAY'), findsOneWidget);
      expect(find.text('PO-2026-HISTORICAL'), findsNothing);
    });

    testWidgets(
        'Displays graceful empty state when no procurement activity is today',
        (tester) async {
      await tester.pumpWidget(
        ProviderScope(
          overrides: [
            vendorsProvider.overrideWith(
              (ref) => TestVendorNotifier(const AsyncValue.data([])),
            ),
            purchaseOrdersProvider.overrideWith(
              (ref) => TestPurchaseOrdersNotifier(const AsyncValue.data([])),
            ),
          ],
          child: const MaterialApp(
            home: Scaffold(
              body: SingleChildScrollView(
                child: VendorPurchaseOrderSummaryCard(),
              ),
            ),
          ),
        ),
      );

      await tester.pumpAndSettle();

      expect(find.text('No procurement activity scheduled for today'),
          findsOneWidget);
      expect(find.text('Manage Vendors'), findsOneWidget);
      expect(find.text('New Purchase Order'), findsOneWidget);
    });

    testWidgets('Handles error state with retry button', (tester) async {
      await tester.pumpWidget(
        ProviderScope(
          overrides: [
            vendorsProvider.overrideWith(
              (ref) => TestVendorNotifier(const AsyncValue.data([])),
            ),
            purchaseOrdersProvider.overrideWith(
              (ref) => TestPurchaseOrdersNotifier(
                AsyncValue.error(
                  Exception('Network error connecting to procurement database'),
                  StackTrace.empty,
                ),
              ),
            ),
          ],
          child: const MaterialApp(
            home: Scaffold(
              body: SingleChildScrollView(
                child: VendorPurchaseOrderSummaryCard(),
              ),
            ),
          ),
        ),
      );

      await tester.pumpAndSettle();

      expect(find.text('Unable to load procurement data'), findsOneWidget);
      expect(find.text('Retry'), findsOneWidget);
    });

    testWidgets('Navigation callbacks fire on action buttons', (tester) async {
      var vendorsOpened = false;
      var ordersOpened = false;

      await tester.pumpWidget(
        ProviderScope(
          overrides: [
            vendorsProvider.overrideWith(
              (ref) => TestVendorNotifier(AsyncValue.data([vendor1])),
            ),
            purchaseOrdersProvider.overrideWith(
              (ref) =>
                  TestPurchaseOrdersNotifier(AsyncValue.data([todayPlacedPO])),
            ),
          ],
          child: MaterialApp(
            home: Scaffold(
              body: SingleChildScrollView(
                child: VendorPurchaseOrderSummaryCard(
                  onNavigateToVendors: () => vendorsOpened = true,
                  onNavigateToOrders: () => ordersOpened = true,
                ),
              ),
            ),
          ),
        ),
      );

      await tester.pumpAndSettle();

      final vendorsBtn = find.text('Vendors');
      expect(vendorsBtn, findsOneWidget);
      await tester.tap(vendorsBtn);
      await tester.pumpAndSettle();
      expect(vendorsOpened, isTrue);

      final allPOsBtn = find.text('All POs');
      expect(allPOsBtn, findsOneWidget);
      await tester.tap(allPOsBtn);
      await tester.pumpAndSettle();
      expect(ordersOpened, isTrue);
    });

    testWidgets('Renders cleanly on a small screen (360x640) without overflow',
        (tester) async {
      tester.view.physicalSize = const Size(360, 640);
      tester.view.devicePixelRatio = 1.0;
      addTearDown(tester.view.resetPhysicalSize);
      addTearDown(tester.view.resetDevicePixelRatio);

      await tester.pumpWidget(
        ProviderScope(
          overrides: [
            vendorsProvider.overrideWith(
              (ref) => TestVendorNotifier(AsyncValue.data([vendor1, vendor2])),
            ),
            purchaseOrdersProvider.overrideWith(
              (ref) => TestPurchaseOrdersNotifier(
                  AsyncValue.data([todayPlacedPO, todayDeliveryPO])),
            ),
          ],
          child: const MaterialApp(
            home: Scaffold(
              body: SingleChildScrollView(
                child: VendorPurchaseOrderSummaryCard(),
              ),
            ),
          ),
        ),
      );

      await tester.pumpAndSettle();
      expect(tester.takeException(), isNull);
    });
  });
}
