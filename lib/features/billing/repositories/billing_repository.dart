import 'package:flutter/foundation.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:supabase_flutter/supabase_flutter.dart';

import '../../../core/providers/supabase_provider.dart';
import '../models/billing_invoice_model.dart';
import '../models/billing_item_model.dart';
import '../models/billing_payment_model.dart';
import '../models/billing_service_model.dart';

final billingRepositoryProvider = Provider<BillingRepository>((ref) {
  return BillingRepository(ref.watch(supabaseProvider));
});

class BillingRepository {
  final SupabaseClient _supabase;

  BillingRepository(this._supabase);

  /// Fetch active services for a department ('eye' or 'dental').
  Future<List<BillingServiceModel>> fetchServices({
    required String department,
    bool activeOnly = true,
  }) async {
    final normDept = department.trim().toLowerCase();
    if (normDept != 'eye' && normDept != 'dental') {
      throw ArgumentError.value(department, 'department', 'Must be eye or dental.');
    }

    var query = _supabase
        .from('billing_services')
        .select()
        .eq('department', normDept);

    if (activeOnly) {
      query = query.eq('is_active', true);
    }

    final response = await query.order('name', ascending: true);
    final list = (response as List)
        .map((json) => BillingServiceModel.fromJson(json as Map<String, dynamic>))
        .toList();

    debugPrint('BillingRepository.fetchServices department=$normDept returned=${list.length}');
    return list;
  }

  /// Create a new invoice atomically using the create_billing_invoice RPC.
  Future<BillingInvoiceModel> createInvoice({
    required String patientId,
    required String department,
    double discount = 0.0,
    required List<BillingItemModel> items,
    BillingPaymentModel? payment,
    DateTime? invoiceDate,
    String? notes,
  }) async {
    final normDept = department.trim().toLowerCase();
    if (normDept != 'eye' && normDept != 'dental') {
      throw ArgumentError.value(department, 'department', 'Must be eye or dental.');
    }
    if (items.isEmpty) {
      throw ArgumentError('Invoice must contain at least one line item.');
    }

    final params = <String, dynamic>{
      'p_patient_id': patientId,
      'p_department': normDept,
      'p_discount': discount,
      'p_items': items.map((e) => e.toRpcJson()).toList(),
      if (payment != null && payment.amount > 0)
        'p_payment': payment.toRpcJson()
      else
        'p_payment': null,
      if (invoiceDate != null)
        'p_invoice_date': invoiceDate.toIso8601String().split('T').first,
      if (notes != null && notes.trim().isNotEmpty)
        'p_notes': notes.trim(),
    };

    debugPrint('BillingRepository.createInvoice calling create_billing_invoice RPC: $params');

    final response = await _supabase.rpc(
      'create_billing_invoice',
      params: params,
    );

    debugPrint('BillingRepository.createInvoice RPC response: $response');
    final invoiceJson = response as Map<String, dynamic>;
    return BillingInvoiceModel.fromJson(invoiceJson);
  }

  /// Fetch list of invoices with optional department, patient, status, date range, and search filtering.
  Future<List<BillingInvoiceModel>> fetchInvoices({
    String? department,
    String? patientId,
    String? paymentStatus,
    String? searchQuery,
    DateTime? startDate,
    DateTime? endDate,
    int limit = 200,
  }) async {
    var query = _supabase.from('billing').select('''
      id,
      invoice_number,
      patient_id,
      department,
      subtotal,
      discount,
      total_amount,
      payment_status,
      payment_mode,
      amount_paid,
      billed_by,
      notes,
      created_at,
      updated_at,
      patients:patient_id (
        id,
        name,
        patient_number,
        mobile
      )
    ''');

    if (department != null && department.isNotEmpty && department != 'all') {
      query = query.eq('department', department.toLowerCase());
    }

    if (patientId != null && patientId.isNotEmpty) {
      query = query.eq('patient_id', patientId);
    }

    if (paymentStatus != null && paymentStatus.isNotEmpty && paymentStatus != 'all') {
      query = query.eq('payment_status', paymentStatus.toLowerCase());
    }

    if (startDate != null) {
      query = query.gte('created_at', startDate.toIso8601String());
    }

    if (endDate != null) {
      query = query.lte('created_at', endDate.toIso8601String());
    }

    final normalizedSearch = searchQuery?.trim();
    if (normalizedSearch != null && normalizedSearch.isNotEmpty) {
      query = query.or(
        'invoice_number.ilike.%$normalizedSearch%,payment_status.ilike.%$normalizedSearch%',
      );
    }

    final response = await query.order('created_at', ascending: false).limit(limit);

    final list = (response as List)
        .map((json) => BillingInvoiceModel.fromJson(json as Map<String, dynamic>))
        .toList();

    debugPrint('BillingRepository.fetchInvoices returned ${list.length} records');
    return list;
  }

  /// Record an additional payment against an existing invoice using the record_billing_payment RPC.
  Future<BillingPaymentModel> recordPayment({
    required String billingId,
    required double amount,
    required String paymentMode,
    String? paymentReference,
    DateTime? paidAt,
    String? notes,
  }) async {
    final normMode = paymentMode.trim().toLowerCase();
    if (!['cash', 'upi', 'bank_transfer', 'other'].contains(normMode)) {
      throw ArgumentError.value(paymentMode, 'paymentMode', 'Invalid payment mode.');
    }
    if (amount <= 0) {
      throw ArgumentError.value(amount, 'amount', 'Payment amount must be greater than zero.');
    }

    final params = <String, dynamic>{
      'p_billing_id': billingId,
      'p_amount': amount,
      'p_payment_mode': normMode,
      if (paymentReference != null && paymentReference.trim().isNotEmpty)
        'p_payment_reference': paymentReference.trim()
      else
        'p_payment_reference': null,
      if (paidAt != null)
        'p_paid_at': paidAt.toIso8601String()
      else
        'p_paid_at': DateTime.now().toIso8601String(),
      if (notes != null && notes.trim().isNotEmpty)
        'p_notes': notes.trim()
      else
        'p_notes': null,
    };

    debugPrint('BillingRepository.recordPayment calling record_billing_payment RPC: $params');

    final response = await _supabase.rpc(
      'record_billing_payment',
      params: params,
    );

    debugPrint('BillingRepository.recordPayment RPC response: $response');
    final paymentJson = response as Map<String, dynamic>;
    return BillingPaymentModel.fromJson(paymentJson);
  }

  /// Fetch full invoice details with line items and payments.
  Future<BillingInvoiceModel> fetchInvoiceById(String invoiceId) async {
    final response = await _supabase.from('billing').select('''
      id,
      invoice_number,
      patient_id,
      department,
      subtotal,
      discount,
      total_amount,
      payment_status,
      payment_mode,
      amount_paid,
      billed_by,
      notes,
      created_at,
      updated_at,
      patients:patient_id (
        id,
        name,
        patient_number,
        mobile
      ),
      billing_items (
        id,
        billing_id,
        service_id,
        service_name,
        quantity,
        unit_price,
        total_amount,
        is_custom,
        created_at
      ),
      billing_payments (
        id,
        billing_id,
        amount,
        payment_mode,
        payment_reference,
        paid_at,
        recorded_by,
        notes,
        created_at
      )
    ''').eq('id', invoiceId).single();

    return BillingInvoiceModel.fromJson(response);
  }

  /// Fetch invoices for reports with complete line items and payment transactions.
  Future<List<BillingInvoiceModel>> fetchInvoicesForReports({
    String? department,
    DateTime? startDate,
    DateTime? endDate,
    String? paymentStatus,
  }) async {
    var query = _supabase.from('billing').select('''
      id,
      invoice_number,
      patient_id,
      department,
      subtotal,
      discount,
      total_amount,
      payment_status,
      payment_mode,
      amount_paid,
      billed_by,
      notes,
      created_at,
      updated_at,
      patients:patient_id (
        id,
        name,
        patient_number,
        mobile
      ),
      billing_items (
        id,
        billing_id,
        service_id,
        service_name,
        quantity,
        unit_price,
        total_amount,
        is_custom,
        created_at
      ),
      billing_payments (
        id,
        billing_id,
        amount,
        payment_mode,
        payment_reference,
        paid_at,
        recorded_by,
        notes,
        created_at
      )
    ''');

    if (department != null && department.isNotEmpty && department != 'all') {
      query = query.eq('department', department.toLowerCase());
    }

    if (paymentStatus != null && paymentStatus.isNotEmpty && paymentStatus != 'all') {
      query = query.eq('payment_status', paymentStatus.toLowerCase());
    }

    if (startDate != null) {
      query = query.gte('created_at', startDate.toIso8601String());
    }

    if (endDate != null) {
      query = query.lte('created_at', endDate.toIso8601String());
    }

    final response = await query.order('created_at', ascending: false);

    final list = (response as List)
        .map((json) => BillingInvoiceModel.fromJson(json as Map<String, dynamic>))
        .toList();

    debugPrint('BillingRepository.fetchInvoicesForReports returned ${list.length} records');
    return list;
  }
}
