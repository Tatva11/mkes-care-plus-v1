import 'package:flutter_riverpod/flutter_riverpod.dart';

import '../../billing/models/billing_reports_model.dart';
import '../models/appointment_reports_model.dart';
import '../models/clinical_reports_model.dart';
import '../models/inventory_reports_model.dart';
import '../models/overview_reports_model.dart';
import '../models/patient_reports_model.dart';
import '../models/reports_filter_model.dart';
import '../models/staff_reports_model.dart';
import '../repositories/reports_repository.dart';

/// Filter state provider for Admin Reports.
/// Kept autoDispose and isolated so it never leaks to Staff or other billing filter states.
final adminReportsFilterProvider =
    StateProvider.autoDispose<AdminReportsFilter>((ref) {
  return const AdminReportsFilter();
});

/// Active section provider for switching between dashboard views.
final adminReportsSectionProvider =
    StateProvider.autoDispose<ReportsSection>((ref) {
  return ReportsSection.overview;
});

/// Async provider for Overview analytics snapshot
final overviewReportsProvider =
    FutureProvider.autoDispose<OverviewReportsData>((ref) async {
  final repo = ref.watch(reportsRepositoryProvider);
  final filter = ref.watch(adminReportsFilterProvider);
  return repo.fetchOverviewData(filter);
});

/// Async provider for Patient analytics
final patientReportsProvider =
    FutureProvider.autoDispose<PatientReportsData>((ref) async {
  final repo = ref.watch(reportsRepositoryProvider);
  final filter = ref.watch(adminReportsFilterProvider);
  return repo.fetchPatientReports(filter);
});

/// Async provider for Appointment analytics
final appointmentReportsProvider =
    FutureProvider.autoDispose<AppointmentReportsData>((ref) async {
  final repo = ref.watch(reportsRepositoryProvider);
  final filter = ref.watch(adminReportsFilterProvider);
  return repo.fetchAppointmentReports(filter);
});

/// Async provider for Staff & Attendance analytics
final staffReportsProvider =
    FutureProvider.autoDispose<StaffReportsData>((ref) async {
  final repo = ref.watch(reportsRepositoryProvider);
  final filter = ref.watch(adminReportsFilterProvider);
  return repo.fetchStaffReports(filter);
});

/// Async provider for Clinical / Procedure analytics
final clinicalReportsProvider =
    FutureProvider.autoDispose<ClinicalReportsData>((ref) async {
  final repo = ref.watch(reportsRepositoryProvider);
  final filter = ref.watch(adminReportsFilterProvider);
  return repo.fetchClinicalReports(filter);
});

/// Async provider for Financial & Sales analytics (reusing Sprint 7 billing data)
final financialReportsProvider =
    FutureProvider.autoDispose<BillingReportsData>((ref) async {
  final repo = ref.watch(reportsRepositoryProvider);
  final filter = ref.watch(adminReportsFilterProvider);
  return repo.fetchFinancialReports(filter);
});

/// Async provider for Inventory & Stock analytics (Sprint 8 Phase 8.2)
final inventoryReportsProvider =
    FutureProvider.autoDispose<InventoryReportsData>((ref) async {
  final repo = ref.watch(reportsRepositoryProvider);
  final filter = ref.watch(adminReportsFilterProvider);
  return repo.fetchInventoryReports(filter);
});
