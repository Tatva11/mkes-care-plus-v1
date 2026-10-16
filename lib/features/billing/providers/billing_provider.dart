import 'package:flutter_riverpod/flutter_riverpod.dart';

import '../models/billing_invoice_model.dart';
import '../models/billing_item_model.dart';
import '../models/billing_metrics_model.dart';
import '../models/billing_payment_model.dart';
import '../models/billing_service_model.dart';
import '../repositories/billing_repository.dart';

import '../models/billing_reports_model.dart';

/// Provider for active department-specific billing services.
final departmentBillingServicesProvider =
    FutureProvider.autoDispose.family<List<BillingServiceModel>, String>((ref, department) async {
  final repository = ref.watch(billingRepositoryProvider);
  return repository.fetchServices(department: department, activeOnly: true);
});

/// Date range filter presets for billing.
enum BillingDatePreset {
  allTime,
  today,
  thisWeek,
  thisMonth,
  thisYear,
  custom,
}

/// Filter parameters for invoice listing and metrics calculation.
class BillingFilter {
  final String department;
  final String status;
  final String searchQuery;
  final BillingDatePreset datePreset;
  final DateTime? customStartDate;
  final DateTime? customEndDate;

  const BillingFilter({
    this.department = 'all',
    this.status = 'all',
    this.searchQuery = '',
    this.datePreset = BillingDatePreset.allTime,
    this.customStartDate,
    this.customEndDate,
  });

  DateTime? get effectiveStartDate {
    final now = DateTime.now();
    switch (datePreset) {
      case BillingDatePreset.today:
        return DateTime(now.year, now.month, now.day, 0, 0, 0);
      case BillingDatePreset.thisWeek:
        final startOfWeek = now.subtract(Duration(days: now.weekday - 1));
        return DateTime(startOfWeek.year, startOfWeek.month, startOfWeek.day, 0, 0, 0);
      case BillingDatePreset.thisMonth:
        return DateTime(now.year, now.month, 1, 0, 0, 0);
      case BillingDatePreset.thisYear:
        return DateTime(now.year, 1, 1, 0, 0, 0);
      case BillingDatePreset.custom:
        return customStartDate;
      case BillingDatePreset.allTime:
        return null;
    }
  }

  DateTime? get effectiveEndDate {
    final now = DateTime.now();
    switch (datePreset) {
      case BillingDatePreset.today:
        return DateTime(now.year, now.month, now.day, 23, 59, 59, 999);
      case BillingDatePreset.thisWeek:
        final startOfWeek = now.subtract(Duration(days: now.weekday - 1));
        final endOfWeek = startOfWeek.add(const Duration(days: 6));
        return DateTime(endOfWeek.year, endOfWeek.month, endOfWeek.day, 23, 59, 59, 999);
      case BillingDatePreset.thisMonth:
        final nextMonth = DateTime(now.year, now.month + 1, 1);
        final endOfMonth = nextMonth.subtract(const Duration(milliseconds: 1));
        return endOfMonth;
      case BillingDatePreset.thisYear:
        return DateTime(now.year, 12, 31, 23, 59, 59, 999);
      case BillingDatePreset.custom:
        if (customEndDate != null) {
          return DateTime(customEndDate!.year, customEndDate!.month, customEndDate!.day, 23, 59, 59, 999);
        }
        return null;
      case BillingDatePreset.allTime:
        return null;
    }
  }

  BillingFilter copyWith({
    String? department,
    String? status,
    String? searchQuery,
    BillingDatePreset? datePreset,
    DateTime? customStartDate,
    DateTime? customEndDate,
    bool clearCustomDates = false,
  }) {
    return BillingFilter(
      department: department ?? this.department,
      status: status ?? this.status,
      searchQuery: searchQuery ?? this.searchQuery,
      datePreset: datePreset ?? this.datePreset,
      customStartDate: clearCustomDates ? null : (customStartDate ?? this.customStartDate),
      customEndDate: clearCustomDates ? null : (customEndDate ?? this.customEndDate),
    );
  }

  @override
  bool operator ==(Object other) =>
      identical(this, other) ||
      other is BillingFilter &&
          runtimeType == other.runtimeType &&
          department == other.department &&
          status == other.status &&
          searchQuery == other.searchQuery &&
          datePreset == other.datePreset &&
          customStartDate == other.customStartDate &&
          customEndDate == other.customEndDate;

  @override
  int get hashCode => Object.hash(
        department,
        status,
        searchQuery,
        datePreset,
        customStartDate,
        customEndDate,
      );
}

/// Independent Admin Billing Filter (opens fresh with default filters and does not pollute Staff).
final adminBillingFilterProvider = StateProvider.autoDispose<BillingFilter>((ref) {
  return const BillingFilter();
});

/// Independent Staff Billing Filter (opens fresh with default filters and does not pollute Admin).
final staffBillingFilterProvider = StateProvider.autoDispose<BillingFilter>((ref) {
  return const BillingFilter();
});

/// Admin Invoices list provider responding to admin filter.
final adminBillingInvoicesProvider = FutureProvider.autoDispose<List<BillingInvoiceModel>>((ref) async {
  final repository = ref.watch(billingRepositoryProvider);
  final filter = ref.watch(adminBillingFilterProvider);

  return repository.fetchInvoices(
    department: filter.department == 'all' ? null : filter.department,
    paymentStatus: filter.status == 'all' ? null : filter.status,
    searchQuery: filter.searchQuery,
    startDate: filter.effectiveStartDate,
    endDate: filter.effectiveEndDate,
  );
});

/// Staff Invoices list provider responding to staff filter.
final staffBillingInvoicesProvider = FutureProvider.autoDispose<List<BillingInvoiceModel>>((ref) async {
  final repository = ref.watch(billingRepositoryProvider);
  final filter = ref.watch(staffBillingFilterProvider);

  return repository.fetchInvoices(
    department: filter.department == 'all' ? null : filter.department,
    paymentStatus: filter.status == 'all' ? null : filter.status,
    searchQuery: filter.searchQuery,
    startDate: filter.effectiveStartDate,
    endDate: filter.effectiveEndDate,
  );
});

/// Admin Financial metrics provider (visible only on Admin portal).
final adminBillingMetricsProvider = Provider.autoDispose<BillingMetricsModel>((ref) {
  final invoicesAsync = ref.watch(adminBillingInvoicesProvider);
  return invoicesAsync.maybeWhen(
    data: (invoices) => BillingMetricsModel.fromInvoices(invoices),
    orElse: () => BillingMetricsModel.zero,
  );
});

/// Legacy compatibility fallback providers
final billingFilterProvider = StateProvider<BillingFilter>((ref) {
  return const BillingFilter();
});

final billingInvoicesProvider = FutureProvider<List<BillingInvoiceModel>>((ref) async {
  final repository = ref.watch(billingRepositoryProvider);
  final filter = ref.watch(billingFilterProvider);

  return repository.fetchInvoices(
    department: filter.department == 'all' ? null : filter.department,
    paymentStatus: filter.status == 'all' ? null : filter.status,
    searchQuery: filter.searchQuery,
    startDate: filter.effectiveStartDate,
    endDate: filter.effectiveEndDate,
  );
});

final billingMetricsProvider = Provider<BillingMetricsModel>((ref) {
  final invoicesAsync = ref.watch(billingInvoicesProvider);
  return invoicesAsync.maybeWhen(
    data: (invoices) => BillingMetricsModel.fromInvoices(invoices),
    orElse: () => BillingMetricsModel.zero,
  );
});

// ============================================================================
// REPORTS & ANALYTICS STATE & PROVIDERS
// ============================================================================

class ReportsFilter {
  final String department;
  final String status;
  final BillingDatePreset datePreset;
  final DateTime? customStartDate;
  final DateTime? customEndDate;
  final ReportAggregationMode aggregationMode;

  const ReportsFilter({
    this.department = 'all',
    this.status = 'all',
    this.datePreset = BillingDatePreset.thisMonth,
    this.customStartDate,
    this.customEndDate,
    this.aggregationMode = ReportAggregationMode.daily,
  });

  DateTime? get effectiveStartDate {
    final now = DateTime.now();
    switch (datePreset) {
      case BillingDatePreset.today:
        return DateTime(now.year, now.month, now.day, 0, 0, 0);
      case BillingDatePreset.thisWeek:
        final startOfWeek = now.subtract(Duration(days: now.weekday - 1));
        return DateTime(startOfWeek.year, startOfWeek.month, startOfWeek.day, 0, 0, 0);
      case BillingDatePreset.thisMonth:
        return DateTime(now.year, now.month, 1, 0, 0, 0);
      case BillingDatePreset.thisYear:
        return DateTime(now.year, 1, 1, 0, 0, 0);
      case BillingDatePreset.custom:
        return customStartDate;
      case BillingDatePreset.allTime:
        return null;
    }
  }

  DateTime? get effectiveEndDate {
    final now = DateTime.now();
    switch (datePreset) {
      case BillingDatePreset.today:
        return DateTime(now.year, now.month, now.day, 23, 59, 59, 999);
      case BillingDatePreset.thisWeek:
        final startOfWeek = now.subtract(Duration(days: now.weekday - 1));
        final endOfWeek = startOfWeek.add(const Duration(days: 6));
        return DateTime(endOfWeek.year, endOfWeek.month, endOfWeek.day, 23, 59, 59, 999);
      case BillingDatePreset.thisMonth:
        final nextMonth = DateTime(now.year, now.month + 1, 1);
        final endOfMonth = nextMonth.subtract(const Duration(milliseconds: 1));
        return endOfMonth;
      case BillingDatePreset.thisYear:
        return DateTime(now.year, 12, 31, 23, 59, 59, 999);
      case BillingDatePreset.custom:
        if (customEndDate != null) {
          return DateTime(customEndDate!.year, customEndDate!.month, customEndDate!.day, 23, 59, 59, 999);
        }
        return null;
      case BillingDatePreset.allTime:
        return null;
    }
  }

  ReportsFilter copyWith({
    String? department,
    String? status,
    BillingDatePreset? datePreset,
    DateTime? customStartDate,
    DateTime? customEndDate,
    ReportAggregationMode? aggregationMode,
    bool clearCustomDates = false,
  }) {
    return ReportsFilter(
      department: department ?? this.department,
      status: status ?? this.status,
      datePreset: datePreset ?? this.datePreset,
      customStartDate: clearCustomDates ? null : (customStartDate ?? this.customStartDate),
      customEndDate: clearCustomDates ? null : (customEndDate ?? this.customEndDate),
      aggregationMode: aggregationMode ?? this.aggregationMode,
    );
  }
}

final reportsFilterProvider = StateProvider.autoDispose<ReportsFilter>((ref) {
  return const ReportsFilter();
});

final billingReportsDataProvider = FutureProvider.autoDispose<BillingReportsData>((ref) async {
  final repository = ref.watch(billingRepositoryProvider);
  final filter = ref.watch(reportsFilterProvider);

  final invoices = await repository.fetchInvoicesForReports(
    department: filter.department == 'all' ? null : filter.department,
    paymentStatus: filter.status == 'all' ? null : filter.status,
    startDate: filter.effectiveStartDate,
    endDate: filter.effectiveEndDate,
  );

  return BillingReportsData.fromInvoices(
    invoices: invoices,
    aggregationMode: filter.aggregationMode,
  );
});

/// Specific invoice details provider (with items and payments).
final invoiceDetailsProvider =
    FutureProvider.autoDispose.family<BillingInvoiceModel, String>((ref, invoiceId) async {
  final repository = ref.watch(billingRepositoryProvider);
  return repository.fetchInvoiceById(invoiceId);
});

/// State notifier for creating an invoice.
class CreateInvoiceState {
  final bool isLoading;
  final BillingInvoiceModel? createdInvoice;
  final String? errorMessage;

  const CreateInvoiceState({
    this.isLoading = false,
    this.createdInvoice,
    this.errorMessage,
  });

  CreateInvoiceState copyWith({
    bool? isLoading,
    BillingInvoiceModel? createdInvoice,
    String? errorMessage,
    bool clearError = false,
  }) {
    return CreateInvoiceState(
      isLoading: isLoading ?? this.isLoading,
      createdInvoice: createdInvoice ?? this.createdInvoice,
      errorMessage: clearError ? null : (errorMessage ?? this.errorMessage),
    );
  }
}

class CreateInvoiceNotifier extends StateNotifier<CreateInvoiceState> {
  final BillingRepository _repository;
  final Ref _ref;

  CreateInvoiceNotifier(this._repository, this._ref)
      : super(const CreateInvoiceState());

  Future<BillingInvoiceModel?> createInvoice({
    required String patientId,
    required String department,
    double discount = 0.0,
    required List<BillingItemModel> items,
    BillingPaymentModel? payment,
    DateTime? invoiceDate,
    String? notes,
    String? eyeSurgeryId,
  }) async {
    state = state.copyWith(isLoading: true, clearError: true);

    try {
      final invoice = await _repository.createInvoice(
        patientId: patientId,
        department: department,
        discount: discount,
        items: items,
        payment: payment,
        invoiceDate: invoiceDate,
        notes: notes,
        eyeSurgeryId: eyeSurgeryId,
      );

      state = CreateInvoiceState(isLoading: false, createdInvoice: invoice);
      // Invalidate invoice lists so any open tables automatically refresh
      _ref.invalidate(billingInvoicesProvider);
      return invoice;
    } catch (e) {
      final message = e.toString().replaceFirst('Exception: ', '').replaceFirst('PostgrestException: ', '');
      state = CreateInvoiceState(isLoading: false, errorMessage: message);
      rethrow;
    }
  }

  void reset() {
    state = const CreateInvoiceState();
  }
}

final createInvoiceNotifierProvider =
    StateNotifierProvider.autoDispose<CreateInvoiceNotifier, CreateInvoiceState>((ref) {
  return CreateInvoiceNotifier(ref.watch(billingRepositoryProvider), ref);
});

/// State notifier for recording additional payments on existing invoices.
class RecordPaymentState {
  final bool isLoading;
  final BillingPaymentModel? payment;
  final String? errorMessage;

  const RecordPaymentState({
    this.isLoading = false,
    this.payment,
    this.errorMessage,
  });

  RecordPaymentState copyWith({
    bool? isLoading,
    BillingPaymentModel? payment,
    String? errorMessage,
    bool clearError = false,
  }) {
    return RecordPaymentState(
      isLoading: isLoading ?? this.isLoading,
      payment: payment ?? this.payment,
      errorMessage: clearError ? null : (errorMessage ?? this.errorMessage),
    );
  }
}

class RecordPaymentNotifier extends StateNotifier<RecordPaymentState> {
  final BillingRepository _repository;
  final Ref _ref;

  RecordPaymentNotifier(this._repository, this._ref)
      : super(const RecordPaymentState());

  Future<BillingPaymentModel?> recordPayment({
    required String billingId,
    required double amount,
    required String paymentMode,
    String? paymentReference,
    DateTime? paidAt,
    String? notes,
  }) async {
    state = state.copyWith(isLoading: true, clearError: true);
    try {
      final payment = await _repository.recordPayment(
        billingId: billingId,
        amount: amount,
        paymentMode: paymentMode,
        paymentReference: paymentReference,
        paidAt: paidAt,
        notes: notes,
      );

      state = RecordPaymentState(isLoading: false, payment: payment);
      // Invalidate invoices list and invoice details to immediately reflect updated totals & status
      _ref.invalidate(billingInvoicesProvider);
      _ref.invalidate(invoiceDetailsProvider(billingId));
      return payment;
    } catch (e) {
      final message = e.toString().replaceFirst('Exception: ', '').replaceFirst('PostgrestException: ', '');
      state = RecordPaymentState(isLoading: false, errorMessage: message);
      rethrow;
    }
  }

  void reset() {
    state = const RecordPaymentState();
  }
}

final recordPaymentNotifierProvider =
    StateNotifierProvider.autoDispose<RecordPaymentNotifier, RecordPaymentState>((ref) {
  return RecordPaymentNotifier(ref.watch(billingRepositoryProvider), ref);
});

/// Provider for outstanding unpaid invoices for a given patient ID.
final patientOutstandingInvoicesProvider =
    FutureProvider.autoDispose.family<List<BillingInvoiceModel>, String>((ref, patientId) async {
  if (patientId.trim().isEmpty) return const [];
  final repo = ref.watch(billingRepositoryProvider);
  return repo.fetchPatientOutstandingInvoices(patientId);
});

