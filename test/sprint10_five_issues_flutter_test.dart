import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:mkes_care/core/providers/supabase_provider.dart';
import 'package:mkes_care/features/billing/models/billing_invoice_model.dart';
import 'package:mkes_care/features/billing/providers/billing_provider.dart';
import 'package:mkes_care/features/billing/repositories/billing_repository.dart';
import 'package:mkes_care/features/billing/screens/billing_management_screen.dart';
import 'package:mkes_care/features/patients/models/patient_model.dart';
import 'package:mkes_care/features/patients/repositories/patient_repository.dart';
import 'package:mkes_care/features/whatsapp/models/whatsapp_appointment_request.dart';
import 'package:mkes_care/features/whatsapp/providers/whatsapp_appointment_provider.dart';
import 'package:mkes_care/features/whatsapp/widgets/whatsapp_requests_view.dart';
import 'package:supabase_flutter/supabase_flutter.dart';

class _FakeSupabaseClient extends Fake implements SupabaseClient {}

class _FakeBillingRepository extends Fake implements BillingRepository {
  final List<BillingInvoiceModel> invoices;
  _FakeBillingRepository(this.invoices);

  @override
  Future<List<BillingInvoiceModel>> fetchInvoices({
    String? department,
    String? patientId,
    String? paymentStatus,
    String? searchQuery,
    DateTime? startDate,
    DateTime? endDate,
    int limit = 200,
  }) async {
    return invoices;
  }
}

class _FakePatientRepository extends Fake implements PatientRepository {
  bool shouldThrowNotFound = false;
  bool shouldThrowPermissionDenied = false;

  @override
  Future<PatientModel> updatePatient(PatientModel patient) async {
    if (shouldThrowNotFound) {
      throw Exception('Patient record not found (ID: ${patient.id}). It may have been deleted.');
    }
    if (shouldThrowPermissionDenied) {
      throw Exception(
        'Permission denied: You do not have authorization to update patient details. Only clinic administrators can edit patient records.',
      );
    }
    return patient.copyWith(name: 'Confirmed Updated Name');
  }
}

class _FakeWhatsAppRequestsNotifier
    extends StateNotifier<AsyncValue<List<WhatsAppAppointmentRequest>>>
    implements WhatsAppRequestsNotifier {
  _FakeWhatsAppRequestsNotifier(super.initial);

  @override
  String get currentDeptFilter => 'all';

  @override
  String get currentStatusFilter => 'pending_review';

  @override
  Future<void> silentRefresh() async {}

  @override
  Future<void> loadRequests({String? status, String? department}) async {}

  @override
  Future<Map<String, dynamic>> approveRequest({
    required String requestId,
    String? doctorId,
    String? doctorName,
  }) async {
    return {'success': true};
  }

  @override
  Future<Map<String, dynamic>> rejectRequest({
    required String requestId,
    required String reason,
  }) async {
    return {'success': true};
  }
}

void main() {
  TestWidgetsFlutterBinding.ensureInitialized();

  final sampleInvoice = BillingInvoiceModel(
    id: 'inv-test-1',
    invoiceNumber: 'INV-2026-0099',
    patientId: 'patient-42',
    patientName: 'Jane Doe',
    patientNumber: 'P-1042',
    patientMobile: '+91 98765 43210',
    department: 'eye',
    subtotal: 3500.0,
    discount: 500.0,
    totalAmount: 3000.0,
    amountPaid: 1500.0,
    paymentStatus: 'partially_paid',
    billedBy: 'Dr. Smith',
    createdAt: DateTime(2026, 8, 15, 11, 30),
    updatedAt: DateTime(2026, 8, 15, 11, 30),
  );

  final samplePatient = PatientModel(
    id: 'pat-100',
    patientNumber: 'EYE-100',
    name: 'Ramesh Patel',
    mobile: '9876543210',
    department: 'eye',
    visitDate: DateTime(2026, 10, 25),
    createdAt: DateTime(2026, 10, 25),
    updatedAt: DateTime(2026, 10, 25),
  );

  final sampleRequest = WhatsAppAppointmentRequest(
    id: 'req-1',
    patientName: 'Anita Sharma',
    patientPhone: '+919876543210',
    department: 'eye',
    requestedDate: DateTime(2026, 10, 28),
    requestedTime: '10:30',
    durationMinutes: 30,
    status: 'pending_review',
    createdAt: DateTime(2026, 10, 25),
    updatedAt: DateTime(2026, 10, 25),
  );

  group('Issue 1: Responsive UI & Overflows Verification', () {
    testWidgets('BillingManagementScreen renders on narrow 360px mobile without RenderFlex overflow', (tester) async {
      tester.view.physicalSize = const Size(360, 640);
      tester.view.devicePixelRatio = 1.0;
      addTearDown(tester.view.resetPhysicalSize);
      addTearDown(tester.view.resetDevicePixelRatio);

      final billingRepo = _FakeBillingRepository([sampleInvoice]);

      final errors = <FlutterErrorDetails>[];
      final oldOnError = FlutterError.onError;
      FlutterError.onError = (details) {
        errors.add(details);
      };

      await tester.pumpWidget(
        ProviderScope(
          overrides: [
            supabaseProvider.overrideWithValue(_FakeSupabaseClient()),
            billingRepositoryProvider.overrideWithValue(billingRepo),
            adminBillingInvoicesProvider.overrideWith((ref) => [sampleInvoice]),
          ],
          child: const MaterialApp(
            home: Scaffold(
              body: BillingManagementScreen(isEmbedded: true),
            ),
          ),
        ),
      );

      await tester.pumpAndSettle();
      FlutterError.onError = oldOnError;

      if (errors.isNotEmpty) {
        for (final e in errors) {
          debugPrint('CAPTURED LAYOUT ERROR:');
          debugPrint(e.toString());
        }
      }

      expect(errors, isEmpty);
      final err = tester.takeException();
      expect(err, isNull);
      expect(find.text(sampleInvoice.invoiceNumber), findsOneWidget);
      expect(find.byKey(Key('invoice_arrow_button_${sampleInvoice.invoiceNumber}')), findsOneWidget);
    });

    testWidgets('BillingManagementScreen renders on wide 1280px desktop without overflow', (tester) async {
      tester.view.physicalSize = const Size(1280, 800);
      tester.view.devicePixelRatio = 1.0;
      addTearDown(tester.view.resetPhysicalSize);
      addTearDown(tester.view.resetDevicePixelRatio);

      final billingRepo = _FakeBillingRepository([sampleInvoice]);

      final errors = <FlutterErrorDetails>[];
      final oldOnError = FlutterError.onError;
      FlutterError.onError = (details) {
        errors.add(details);
      };

      await tester.pumpWidget(
        ProviderScope(
          overrides: [
            supabaseProvider.overrideWithValue(_FakeSupabaseClient()),
            billingRepositoryProvider.overrideWithValue(billingRepo),
            adminBillingInvoicesProvider.overrideWith((ref) => [sampleInvoice]),
          ],
          child: const MaterialApp(
            home: Scaffold(
              body: BillingManagementScreen(isEmbedded: true),
            ),
          ),
        ),
      );

      await tester.pumpAndSettle();
      FlutterError.onError = oldOnError;

      if (errors.isNotEmpty) {
        for (final e in errors) {
          debugPrint('CAPTURED DESKTOP ERROR:');
          debugPrint(e.toString());
        }
      }

      expect(errors, isEmpty);
      final err = tester.takeException();
      expect(err, isNull);
      expect(find.text(sampleInvoice.invoiceNumber), findsOneWidget);
      expect(find.byKey(Key('desktop_invoice_arrow_button_${sampleInvoice.invoiceNumber}')), findsOneWidget);
    });

    testWidgets('WhatsAppRequestsView renders empty state without bottom overflow at 360x600', (tester) async {
      tester.view.physicalSize = const Size(360, 600);
      tester.view.devicePixelRatio = 1.0;
      addTearDown(tester.view.resetPhysicalSize);
      addTearDown(tester.view.resetDevicePixelRatio);

      await tester.pumpWidget(
        ProviderScope(
          overrides: [
            supabaseProvider.overrideWithValue(_FakeSupabaseClient()),
            whatsappRequestsProvider.overrideWith(
              (ref) => _FakeWhatsAppRequestsNotifier(const AsyncValue.data([])),
            ),
          ],
          child: const MaterialApp(
            home: Scaffold(
              body: WhatsAppRequestsView(),
            ),
          ),
        ),
      );

      await tester.pumpAndSettle();

      expect(tester.takeException(), isNull);
      expect(find.text('No WhatsApp requests found'), findsOneWidget);
      expect(find.text('Shared Inbox'), findsOneWidget);
    });

    testWidgets('WhatsAppRequestsView renders request card without overflow at 360px mobile width', (tester) async {
      tester.view.physicalSize = const Size(360, 640);
      tester.view.devicePixelRatio = 1.0;
      addTearDown(tester.view.resetPhysicalSize);
      addTearDown(tester.view.resetDevicePixelRatio);

      final errors = <FlutterErrorDetails>[];
      final oldOnError = FlutterError.onError;
      FlutterError.onError = (details) {
        errors.add(details);
      };

      await tester.pumpWidget(
        ProviderScope(
          overrides: [
            supabaseProvider.overrideWithValue(_FakeSupabaseClient()),
            whatsappRequestsProvider.overrideWith(
              (ref) => _FakeWhatsAppRequestsNotifier(AsyncValue.data([sampleRequest])),
            ),
          ],
          child: const MaterialApp(
            home: Scaffold(
              body: WhatsAppRequestsView(),
            ),
          ),
        ),
      );

      await tester.pumpAndSettle();
      FlutterError.onError = oldOnError;

      if (errors.isNotEmpty) {
        for (final e in errors) {
          debugPrint('CAPTURED WHATSAPP REQUEST CARD ERROR:');
          debugPrint(e.toString());
        }
      }

      expect(errors, isEmpty);
      final err = tester.takeException();
      expect(err, isNull);
      expect(find.text(sampleRequest.patientName), findsOneWidget);
      expect(find.text('Approve & Book'), findsOneWidget);
      expect(find.text('Reject'), findsOneWidget);
    });
  });

  group('Issue 2: Patient Update Error Handling Verification', () {
    test('Throws clear Exception when record is not found', () async {
      final repo = _FakePatientRepository()..shouldThrowNotFound = true;
      expect(
        () => repo.updatePatient(samplePatient),
        throwsA(predicate((e) => e.toString().contains('Patient record not found'))),
      );
    });

    test('Throws clear Permission denied Exception when RLS authorization fails', () async {
      final repo = _FakePatientRepository()..shouldThrowPermissionDenied = true;
      expect(
        () => repo.updatePatient(samplePatient),
        throwsA(predicate((e) => e.toString().contains('Permission denied'))),
      );
    });

    test('Returns confirmed updated patient on success', () async {
      final repo = _FakePatientRepository();
      final updated = await repo.updatePatient(samplePatient);
      expect(updated.name, 'Confirmed Updated Name');
    });
  });
}
