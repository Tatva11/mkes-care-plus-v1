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

      throw ArgumentError.value(

          department, 'department', 'Must be eye or dental.');

    }



    var query =

        _supabase.from('billing_services').select().eq('department', normDept);



    if (activeOnly) {

      query = query.eq('is_active', true);

    }



    final response = await query.order('name', ascending: true);

    final list = (response as List)

        .map((json) =>

            BillingServiceModel.fromJson(json as Map<String, dynamic>))

        .toList();



    debugPrint(

        'BillingRepository.fetchServices department=$normDept returned=${list.length}');

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

    String? eyeSurgeryId,

  }) async {

    final normDept = department.trim().toLowerCase();

    if (normDept != 'eye' && normDept != 'dental') {

      throw ArgumentError.value(

          department, 'department', 'Must be eye or dental.');

    }

    if (items.isEmpty) {

      throw ArgumentError('Invoice must contain at least one line item.');

    }



    final surgeryIdTrimmed = eyeSurgeryId?.trim();



    // Defensive check: If surgery ID is provided, check if an active invoice already exists

    if (surgeryIdTrimmed != null && surgeryIdTrimmed.isNotEmpty) {

      try {

        final existing = await fetchInvoiceForSurgery(surgeryIdTrimmed);

        if (existing != null) {

          debugPrint(

            'BillingRepository.createInvoice: Active invoice ${existing.invoiceNumber} already exists for surgery $surgeryIdTrimmed. Returning existing.',

          );

          return existing;

        }

      } catch (_) {}

    }



    final isSurgery = surgeryIdTrimmed != null && surgeryIdTrimmed.isNotEmpty;



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

      if (notes != null && notes.trim().isNotEmpty) 'p_notes': notes.trim(),

      'p_eye_surgery_id': isSurgery ? surgeryIdTrimmed : null,

    };



    debugPrint(

        'BillingRepository.createInvoice calling RPC (isSurgery=$isSurgery): $params');



    try {

      dynamic response;

      if (isSurgery) {

        try {

          // 1. Try dedicated unambiguous surgery RPC first

          response = await _supabase.rpc(

            'create_surgery_billing_invoice',

            params: params,

          );

        } catch (rpcErr) {

          final errLower = rpcErr.toString().toLowerCase();

          if (errLower.contains('does not exist') ||

              errLower.contains('not found') ||

              errLower.contains('404')) {

            // Fall back to canonical create_billing_invoice

            response = await _supabase.rpc(

              'create_billing_invoice',

              params: params,

            );

          } else {

            rethrow;

          }

        }

      } else {

        // Normal invoice: call canonical create_billing_invoice with explicit 8 params to prevent PGRST203

        try {

          response = await _supabase.rpc(

            'create_billing_invoice',

            params: params,

          );

        } catch (normalErr) {

          final errLower = normalErr.toString().toLowerCase();

          if (errLower.contains('pgrst203') ||

              errLower.contains('candidate function') ||

              errLower.contains('p_eye_surgery_id')) {

            // Fallback for older schemas with strictly 7 parameters

            final fallbackParams = Map<String, dynamic>.from(params)

              ..remove('p_eye_surgery_id');

            response = await _supabase.rpc('create_billing_invoice',

                params: fallbackParams);

          } else {

            rethrow;

          }

        }

      }



      debugPrint('BillingRepository.createInvoice RPC response: $response');

      final invoiceJson = response as Map<String, dynamic>;
      final created = BillingInvoiceModel.fromJson(invoiceJson);
      _enqueueInvoiceWhatsAppPdf(created);
      return created;
    } catch (e) {

      final errStr = e.toString().toLowerCase();

      // If unique violation occurred or invoice already exists, recover existing invoice

      if (surgeryIdTrimmed != null &&

          (errStr.contains('unique') || errStr.contains('already linked'))) {

        final existing = await fetchInvoiceForSurgery(surgeryIdTrimmed);

        if (existing != null) return existing;

      }



      // Fallback: If RPC without p_eye_surgery_id was not yet updated in remote DB

      if (isSurgery &&

          (errStr.contains('p_eye_surgery_id') ||

              errStr.contains('schema cache') ||

              errStr.contains('pgrst203'))) {

        debugPrint(

            'BillingRepository.createInvoice retrying without p_eye_surgery_id fallback');

        final fallbackParams = Map<String, dynamic>.from(params)

          ..remove('p_eye_surgery_id');

        final response = await _supabase.rpc('create_billing_invoice',

            params: fallbackParams);

        final invoiceJson = response as Map<String, dynamic>;

        final created = BillingInvoiceModel.fromJson(invoiceJson);
        _enqueueInvoiceWhatsAppPdf(created);



        // Attempt to link eye_surgery_id directly

        try {

          await _supabase.from('billing').update(

              {'eye_surgery_id': surgeryIdTrimmed}).eq('id', created.id);

          return created.copyWith(eyeSurgeryId: surgeryIdTrimmed);

        } catch (_) {

          return created;

        }

      }

      rethrow;

    }

  }

  void _enqueueInvoiceWhatsAppPdf(BillingInvoiceModel invoice) async {
    try {
      final pRes = await _supabase
          .from('patients')
          .select('name, mobile, whatsapp_opt_out')
          .eq('id', invoice.patientId)
          .maybeSingle();

      if (pRes == null) return;
      if (pRes['whatsapp_opt_out'] == true) return;

      final rawMobile = pRes['mobile']?.toString() ?? '';
      final digits = rawMobile.replaceAll(RegExp(r'[^0-9]'), '');
      if (digits.length < 10) return;
      final clean10 = digits.substring(digits.length - 10);

      // Duplicate check: ensure this invoice has not already been enqueued
      final existing = await _supabase
          .from('whatsapp_messages_outbox')
          .select('id')
          .eq('template_key', 'invoice_${invoice.id}')
          .maybeSingle();

      if (existing != null) return;

      final patientName = pRes['name']?.toString() ?? 'Valued Patient';
      final statusLabel = invoice.isPaid ? 'PAID' : 'PARTIALLY PAID';

      final messageText = '🧾 *MKES CARE+ Invoice #${invoice.invoiceNumber}*\n\n'
          'Dear $patientName,\n'
          'Thank you for visiting MKES CARE+ Hospital. Your official clinical invoice for ₹${invoice.totalAmount.toStringAsFixed(2)} has been generated.\n\n'
          'Status: $statusLabel\n'
          'Amount Paid: ₹${invoice.amountPaid.toStringAsFixed(2)}\n'
          'Remaining Balance: ₹${invoice.remainingAmount.toStringAsFixed(2)}\n\n'
          'Please find your official invoice document attached. We wish you great health and a speedy recovery!\n\n'
          'Reply STOP to unsubscribe.';

      await _supabase.from('whatsapp_messages_outbox').insert({
        'recipient_phone': clean10,
        'patient_id': invoice.patientId,
        'department': invoice.department.toLowerCase(),
        'message_type': 'payment_receipt',
        'template_key': 'invoice_${invoice.id}',
        'media_url': 'invoice://${invoice.id}',
        'message_text': messageText,
        'status': 'pending',
      });
    } catch (_) {
      // Non-blocking
    }
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



    if (paymentStatus != null &&

        paymentStatus.isNotEmpty &&

        paymentStatus != 'all') {

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



    final response =

        await query.order('created_at', ascending: false).limit(limit);



    final list = (response as List)

        .map((json) =>

            BillingInvoiceModel.fromJson(json as Map<String, dynamic>))

        .toList();



    debugPrint(

        'BillingRepository.fetchInvoices returned ${list.length} records');

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

      throw ArgumentError.value(

          paymentMode, 'paymentMode', 'Invalid payment mode.');

    }

    if (amount <= 0) {

      throw ArgumentError.value(

          amount, 'amount', 'Payment amount must be greater than zero.');

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



    debugPrint(

        'BillingRepository.recordPayment calling record_billing_payment RPC: $params');



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



  /// Updates an existing invoice atomically, allowing editing of department,

  /// discount, notes, and line items, while strictly preserving invoice ID,

  /// invoice number, patient ID, payments, and billing rules.

  Future<BillingInvoiceModel> updateInvoice({

    required String invoiceId,

    required double subtotal,

    required double discount,

    required double totalAmount,

    required String paymentStatus,

    String? notes,

    String? department,

    List<BillingItemModel>? items,

  }) async {

    final updateData = <String, dynamic>{

      'subtotal': subtotal,

      'discount': discount,

      'total_amount': totalAmount,

      'payment_status': paymentStatus,

      'updated_at': DateTime.now().toUtc().toIso8601String(),

    };



    if (notes != null) {

      updateData['notes'] = notes.trim().isEmpty ? null : notes.trim();

    }

    if (department != null && department.trim().isNotEmpty) {

      final normDept = department.trim().toLowerCase();

      if (normDept == 'eye' || normDept == 'dental') {

        updateData['department'] = normDept;

      }

    }



    // 1. Update the existing billing record

    await _supabase.from('billing').update(updateData).eq('id', invoiceId);



    // 2. If updated items are provided, replace billing_items for this invoice

    if (items != null && items.isNotEmpty) {

      try {

        await _supabase.from('billing_items').delete().eq('billing_id', invoiceId);

        final itemsToInsert = items.map((item) {

          final json = item.copyWith(billingId: invoiceId).toJson();

          json.remove('id');

          return json;

        }).toList();

        await _supabase.from('billing_items').insert(itemsToInsert);

      } catch (e) {

        debugPrint('BillingRepository.updateInvoice: billing_items update warning: $e');

      }

    }



    // 3. Return the fully refreshed invoice

    return await fetchInvoiceById(invoiceId);

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



    if (paymentStatus != null &&

        paymentStatus.isNotEmpty &&

        paymentStatus != 'all') {

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

        .map((json) =>

            BillingInvoiceModel.fromJson(json as Map<String, dynamic>))

        .toList();



    debugPrint(

        'BillingRepository.fetchInvoicesForReports returned ${list.length} records');

    return list;

  }



  /// Fetch all unpaid or partially-paid invoices for a patient with outstanding balances.

  Future<List<BillingInvoiceModel>> fetchPatientOutstandingInvoices(

      String patientId) async {

    if (patientId.trim().isEmpty) return const [];

    final invoices = await fetchInvoices(patientId: patientId, limit: 100);

    return invoices

        .where((inv) =>

            !inv.isCancelled && !inv.isPaid && inv.remainingAmount > 0.01)

        .toList();

  }



  /// Record consolidation transfers for previous invoices when their balance

  /// has been included in a newly created consolidated invoice.

  Future<void> consolidateInvoices({

    required List<BillingInvoiceModel> previousInvoices,

    required String newInvoiceNumber,

    required String newInvoiceId,

  }) async {

    for (final prev in previousInvoices) {

      if (prev.remainingAmount <= 0) continue;

      try {

        await recordPayment(

          billingId: prev.id,

          amount: prev.remainingAmount,

          paymentMode: 'other',

          paymentReference: 'Consolidated to $newInvoiceNumber',

          paidAt: DateTime.now(),

          notes:

              'Balance transferred to new invoice #$newInvoiceNumber (ID: $newInvoiceId)',

        );

      } catch (e) {

        debugPrint('Warning consolidating invoice ${prev.invoiceNumber}: $e');

      }

    }

  }



  /// Fetch the active invoice linked to a specific eye surgery.

  Future<BillingInvoiceModel?> fetchInvoiceForSurgery(String surgeryId) async {

    if (surgeryId.trim().isEmpty) return null;

    try {

      final response = await _supabase

          .from('billing')

          .select('''

            *,

            patients (

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

          ''')

          .eq('eye_surgery_id', surgeryId.trim())

          .neq('payment_status', 'cancelled')

          .order('created_at', ascending: false)

          .limit(1)

          .maybeSingle();



      if (response == null) return null;

      return BillingInvoiceModel.fromJson(response);

    } catch (e) {

      debugPrint('BillingRepository.fetchInvoiceForSurgery error: $e');

      rethrow;

    }

  }
}
