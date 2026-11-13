import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:flutter_test/flutter_test.dart';

import 'package:mkes_care/features/auth/providers/auth_provider.dart';
import 'package:mkes_care/features/billing/models/billing_invoice_model.dart';
import 'package:mkes_care/features/eye/models/eye_surgery_insurance_model.dart';
import 'package:mkes_care/features/eye/models/eye_surgery_item_model.dart';
import 'package:mkes_care/features/eye/models/eye_surgery_model.dart';
import 'package:mkes_care/features/eye/providers/eye_surgery_provider.dart';
import 'package:mkes_care/features/eye/screens/eye_surgery_screen.dart';
import 'package:mkes_care/features/eye/widgets/eye_surgery_detail_dialog.dart';
import 'package:mkes_care/features/eye/widgets/eye_surgery_patient_section.dart';
import 'package:mkes_care/features/vendors/models/vendor.dart';
import 'package:mkes_care/features/vendors/repositories/vendor_repository.dart';
import 'package:mkes_care/features/vendors/widgets/vendor_details_dialog.dart';

class _FakeVendorRepo implements VendorRepository {
  final List<Vendor> _vendors;
  _FakeVendorRepo(this._vendors);

  @override
  Future<List<Vendor>> getVendors({String? searchQuery, bool? activeOnly}) async {
    return _vendors;
  }

  @override
  Future<Vendor> getVendor(String id) async => _vendors.firstWhere((v) => v.id == id);

  @override
  Future<Vendor> createVendor(Vendor vendor) async {
    _vendors.add(vendor);
    return vendor;
  }

  @override
  Future<Vendor> updateVendor(Vendor vendor) async => vendor;

  @override
  Future<Vendor> toggleVendorStatus(String id, bool isActive) async {
    return _vendors.firstWhere((v) => v.id == id);
  }

  @override
  Future<void> deleteVendor(String id) async {}
}

class _FakeItemsNotifier extends EyeSurgeryItemsNotifier {
  final List<EyeSurgeryItemModel> _items;
  _FakeItemsNotifier(this._items);

  @override
  Future<List<EyeSurgeryItemModel>> build(String arg) async => _items;
}

class _FakeInsuranceNotifier extends EyeSurgeryInsuranceNotifier {
  final EyeSurgeryInsuranceModel? _insurance;
  _FakeInsuranceNotifier(this._insurance);

  @override
  Future<EyeSurgeryInsuranceModel?> build(String arg) async => _insurance;
}

class _FakeSurgeryListNotifier extends EyeSurgeryListNotifier {
  final List<EyeSurgeryModel> _surgeries;
  _FakeSurgeryListNotifier(this._surgeries);

  @override
  Future<List<EyeSurgeryModel>> build() async => _surgeries;
}

void main() {
  TestWidgetsFlutterBinding.ensureInitialized();

  group('UI Alignment and Responsiveness Verification', () {
    testWidgets('VendorDetailsDialog aligns phone and fields cleanly on narrow 320px mobile',
        (tester) async {
      tester.view.devicePixelRatio = 1.0;
      tester.view.physicalSize = const Size(320, 640);
      addTearDown(() {
        tester.view.resetPhysicalSize();
        tester.view.resetDevicePixelRatio();
      });

      final testVendor = Vendor(
        id: 'v-101',
        name: 'Metro Surgical & Optical Devices Global Solutions Pvt Ltd',
        contactPerson: 'Dr. Ramesh Chandra Agrawal',
        phone: '+91 98765 43210 / +91 91234 56789',
        email: 'ramesh.agrawal@metrosurgicaldevices.co.in',
        address: 'Plot 42, Industrial Area Phase 2, Near Metro Station, New Delhi',
        productsSupplied: const ['Intraocular Lenses', 'Surgical Knives', 'Sutures'],
        lastOrderDate: DateTime(2026, 10, 1),
        lastDeliveryDate: DateTime(2026, 10, 5),
        lastQuantity: 1500.0,
        remarks: 'Primary accredited supplier for advanced ophthalmic microsurgery equipment',
        isActive: true,
      );

      final fakeRepo = _FakeVendorRepo([testVendor]);

      await tester.pumpWidget(
        ProviderScope(
          overrides: [
            vendorRepositoryProvider.overrideWithValue(fakeRepo),
            currentUserRoleProvider.overrideWith((ref) => Future.value('admin')),
          ],
          child: MaterialApp(
            home: Scaffold(
              body: VendorDetailsDialog(vendor: testVendor),
            ),
          ),
        ),
      );

      await tester.pumpAndSettle();

      // Check header and phone display
      expect(find.text('Metro Surgical & Optical Devices Global Solutions Pvt Ltd'), findsOneWidget);
      expect(find.text('Dr. Ramesh Chandra Agrawal'), findsOneWidget);
      expect(find.text('+91 98765 43210 / +91 91234 56789'), findsOneWidget);

      // Verify no overflow exception occurred during render
      expect(tester.takeException(), isNull);
    });

    testWidgets('EyeSurgeryScreen date selector does not overflow on 320px screen when navigating to previous date',
        (tester) async {
      tester.view.devicePixelRatio = 1.0;
      tester.view.physicalSize = const Size(320, 640);
      addTearDown(() {
        tester.view.resetPhysicalSize();
        tester.view.resetDevicePixelRatio();
      });

      await tester.pumpWidget(
        ProviderScope(
          overrides: [
            currentUserRoleProvider.overrideWith((ref) => Future.value('admin')),
            eyeSurgeryListProvider.overrideWith(() => _FakeSurgeryListNotifier([])),
          ],
          child: const MaterialApp(
            home: Scaffold(
              body: EyeSurgeryScreen(),
            ),
          ),
        ),
      );

      await tester.pumpAndSettle();

      // Find left chevron to navigate back to a previous date
      final leftArrowFinder = find.byIcon(Icons.chevron_left);
      expect(leftArrowFinder, findsOneWidget);

      await tester.tap(leftArrowFinder);
      await tester.pumpAndSettle();

      // The "Today" button should now be visible and rendered
      final todayButtonFinder = find.text('Today');
      expect(todayButtonFinder, findsOneWidget);

      // Verify NO RenderFlex overflow exception
      expect(tester.takeException(), isNull);

      // Tap Today to navigate back
      await tester.tap(todayButtonFinder);
      await tester.pumpAndSettle();

      expect(tester.takeException(), isNull);
    });

    testWidgets('EyeSurgeryDetailDialog header and tabs do not overflow on 320px mobile',
        (tester) async {
      tester.view.devicePixelRatio = 1.0;
      tester.view.physicalSize = const Size(320, 640);
      addTearDown(() {
        tester.view.resetPhysicalSize();
        tester.view.resetDevicePixelRatio();
      });

      final surgery = EyeSurgeryModel(
        id: 'surg-999',
        patientId: 'pat-888',
        patientName: 'Shri Ramachandra Narayana Murthy',
        patientNumber: 'E-0842',
        surgeryType: 'other',
        customSurgeryType: 'Extracapsular Cataract Extraction with Foldable Hydrophobic IOL',
        eyeSide: 'both',
        surgeryDate: DateTime(2026, 11, 4),
        surgeryTime: '10:30 AM',
        preOpDate: DateTime(2026, 11, 3),
        status: 'in_surgery',
        assignedStaffName: 'Dr. Anita Desai',
        preOpChecklist: {
          'consent_signed': true,
          'vitals_checked': true,
          'pupil_dilated': true,
          'antibiotic_given': true,
        },
        createdAt: DateTime(2026, 11, 1),
        updatedAt: DateTime(2026, 11, 4),
      );

      await tester.pumpWidget(
        ProviderScope(
          overrides: [
            currentUserRoleProvider.overrideWith((ref) => Future.value('admin')),
            eyeSurgeryListProvider.overrideWith(() => _FakeSurgeryListNotifier([surgery])),
            eyeSurgeryInvoiceProvider(surgery.id).overrideWith((ref) async => null),
            eyeSurgeryInsuranceProvider.overrideWith(() => _FakeInsuranceNotifier(null)),
            eyeSurgeryItemsProvider.overrideWith(() => _FakeItemsNotifier([])),
          ],
          child: MaterialApp(
            home: Scaffold(
              body: EyeSurgeryDetailDialog(surgery: surgery),
            ),
          ),
        ),
      );

      await tester.pumpAndSettle();

      // Header components rendered
      expect(find.text('Extracapsular Cataract Extraction with Foldable Hydrophobic IOL'), findsOneWidget);
      expect(find.text('IN SURGERY'), findsOneWidget);
      expect(find.text('SCHEDULE & CLINICAL OVERVIEW'), findsOneWidget);

      // Verify no overflow exception
      expect(tester.takeException(), isNull);
    });

    testWidgets('EyeSurgeryDetailDialog Billing Tab Invoice Banner renders without overflow on 320px mobile',
        (tester) async {
      tester.view.devicePixelRatio = 1.0;
      tester.view.physicalSize = const Size(320, 640);
      addTearDown(() {
        tester.view.resetPhysicalSize();
        tester.view.resetDevicePixelRatio();
      });

      final surgery = EyeSurgeryModel(
        id: 'surg-billing-test',
        patientId: 'pat-777',
        patientName: 'Devendra Joshi',
        patientNumber: 'E-0123',
        surgeryType: 'cataract_phaco',
        eyeSide: 'right',
        surgeryDate: DateTime(2026, 11, 4),
        preOpDate: DateTime(2026, 11, 3),
        status: 'billing',
        createdAt: DateTime(2026, 11, 1),
        updatedAt: DateTime(2026, 11, 4),
      );

      final dummyInvoice = BillingInvoiceModel(
        id: 'inv-1',
        invoiceNumber: '104/26-27',
        patientId: surgery.patientId,
        department: 'eye',
        subtotal: 35000,
        discount: 2000,
        totalAmount: 33000,
        amountPaid: 15000,
        paymentStatus: 'partially_paid',
        eyeSurgeryId: surgery.id,
        createdAt: DateTime(2026, 11, 4, 11, 30),
        updatedAt: DateTime(2026, 11, 4, 11, 30),
      );

      await tester.pumpWidget(
        ProviderScope(
          overrides: [
            currentUserRoleProvider.overrideWith((ref) => Future.value('admin')),
            eyeSurgeryListProvider.overrideWith(() => _FakeSurgeryListNotifier([surgery])),
            eyeSurgeryInvoiceProvider(surgery.id).overrideWith((ref) async => dummyInvoice),
            eyeSurgeryInsuranceProvider.overrideWith(() => _FakeInsuranceNotifier(null)),
            eyeSurgeryItemsProvider.overrideWith(() => _FakeItemsNotifier([])),
          ],
          child: MaterialApp(
            home: Scaffold(
              body: EyeSurgeryDetailDialog(
                surgery: surgery,
                initialTabIndex: 1, // Open directly to Surgery Billing tab
              ),
            ),
          ),
        ),
      );

      await tester.pumpAndSettle();

      // Verify Invoice Header Banner content
      expect(find.text('Invoice #104/26-27'), findsOneWidget);
      expect(find.text('PARTIALLY PAID'), findsOneWidget);
      expect(find.text('Record Payment'), findsOneWidget);

      // Verify no overflow
      expect(tester.takeException(), isNull);
    });

    testWidgets('EyeSurgeryPatientSection renders tiles with ellipsis without overflow on 320px mobile',
        (tester) async {
      tester.view.devicePixelRatio = 1.0;
      tester.view.physicalSize = const Size(320, 640);
      addTearDown(() {
        tester.view.resetPhysicalSize();
        tester.view.resetDevicePixelRatio();
      });

      final testSurgeries = [
        EyeSurgeryModel(
          id: 'surg-patient-sec-1',
          patientId: 'pat-999',
          surgeryType: 'other',
          customSurgeryType: 'Cataract - Phacoemulsification',
          eyeSide: 'left',
          surgeryDate: DateTime(2026, 11, 4),
          surgeryTime: '11:00 AM',
          preOpDate: DateTime(2026, 11, 3),
          status: 'scheduled',
          assignedStaffName: 'Dr. Vikramaditya Singhania Senior Surgeon',
          createdAt: DateTime(2026, 11, 1),
          updatedAt: DateTime(2026, 11, 4),
        ),
      ];

      await tester.pumpWidget(
        ProviderScope(
          overrides: [
            eyeSurgeriesForPatientProvider('pat-999').overrideWith((ref) async => testSurgeries),
          ],
          child: const MaterialApp(
            home: Scaffold(
              body: SingleChildScrollView(
                child: EyeSurgeryPatientSection(patientId: 'pat-999'),
              ),
            ),
          ),
        ),
      );

      await tester.pumpAndSettle();

      expect(find.text('OPERATIONS / SURGERY HISTORY'), findsOneWidget);
      expect(find.text('Cataract - Phacoemulsification'), findsOneWidget);

      expect(tester.takeException(), isNull);
    });
  });
}
