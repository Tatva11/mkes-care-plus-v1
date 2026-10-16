import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:intl/intl.dart';

import '../../../core/providers/supabase_provider.dart';
import '../../../core/theme/app_colors.dart';
import '../../../core/theme/app_spacing.dart';
import '../../../core/theme/app_typography.dart';
import '../../auth/providers/auth_provider.dart';
import '../models/inventory_reports_model.dart';
import '../models/reports_filter_model.dart';
import '../providers/reports_provider.dart';
import '../services/reports_export_service.dart';
import '../widgets/excel_sync_manager_dialog.dart';
import '../widgets/reports_chart_painters.dart';
import '../widgets/reports_filter_toolbar.dart';
import '../widgets/reports_metric_card.dart';

/// State provider tracking whether an Excel report is actively being generated and downloaded.
final reportsIsExportingProvider = StateProvider.autoDispose<bool>((ref) => false);

/// Central download handler for standalone Excel report exports.
Future<void> _handleDownloadReport(
  BuildContext context,
  WidgetRef ref,
  ReportsSection activeSection,
  AdminReportsFilter filter,
) async {
  if (ref.read(reportsIsExportingProvider)) return;

  final fileName = filter.getReportFileName(activeSection);
  ref.read(reportsIsExportingProvider.notifier).state = true;

  ScaffoldMessenger.of(context).hideCurrentSnackBar();
  ScaffoldMessenger.of(context).showSnackBar(
    SnackBar(
      duration: const Duration(seconds: 2),
      content: Row(
        children: [
          const SizedBox(
            width: 16,
            height: 16,
            child: CircularProgressIndicator(
              strokeWidth: 2,
              color: Colors.white,
            ),
          ),
          const SizedBox(width: 12),
          Expanded(
            child: Text('Generating "$fileName"...'),
          ),
        ],
      ),
    ),
  );

  try {
    dynamic sectionData;
    switch (activeSection) {
      case ReportsSection.overview:
        sectionData = ref.read(overviewReportsProvider).valueOrNull ??
            await ref.read(overviewReportsProvider.future);
        break;
      case ReportsSection.patients:
        sectionData = ref.read(patientReportsProvider).valueOrNull ??
            await ref.read(patientReportsProvider.future);
        break;
      case ReportsSection.appointments:
        sectionData = ref.read(appointmentReportsProvider).valueOrNull ??
            await ref.read(appointmentReportsProvider.future);
        break;
      case ReportsSection.staff:
        sectionData = ref.read(staffReportsProvider).valueOrNull ??
            await ref.read(staffReportsProvider.future);
        break;
      case ReportsSection.clinical:
        sectionData = ref.read(clinicalReportsProvider).valueOrNull ??
            await ref.read(clinicalReportsProvider.future);
        break;
      case ReportsSection.financial:
        sectionData = ref.read(financialReportsProvider).valueOrNull ??
            await ref.read(financialReportsProvider.future);
        break;
      case ReportsSection.inventory:
        sectionData = ref.read(inventoryReportsProvider).valueOrNull ??
            await ref.read(inventoryReportsProvider.future);
        break;
    }

    final supabase = ref.read(supabaseProvider);
    final result = await ReportsExportService.exportReportToExcel(
      section: activeSection,
      filter: filter,
      sectionData: sectionData,
      supabase: supabase,
    );

    if (!context.mounted) return;

    ScaffoldMessenger.of(context).hideCurrentSnackBar();
    if (result.success) {
      ScaffoldMessenger.of(context).showSnackBar(
        SnackBar(
          backgroundColor: AppColors.primary,
          duration: const Duration(seconds: 5),
          content: Row(
            children: [
              const Icon(Icons.check_circle_outline, color: Colors.white, size: 22),
              const SizedBox(width: 12),
              Expanded(
                child: Text(
                  'Downloaded "$fileName" (${result.formattedSize}). Check your device Downloads folder.',
                  style: const TextStyle(color: Colors.white, fontWeight: FontWeight.w500),
                ),
              ),
            ],
          ),
        ),
      );
    } else {
      ScaffoldMessenger.of(context).showSnackBar(
        SnackBar(
          backgroundColor: AppColors.error,
          duration: const Duration(seconds: 5),
          content: Row(
            children: [
              const Icon(Icons.error_outline, color: Colors.white, size: 22),
              const SizedBox(width: 12),
              Expanded(
                child: Text(
                  'Failed to export $fileName: ${result.errorMessage ?? "Unknown error"}',
                  style: const TextStyle(color: Colors.white),
                ),
              ),
            ],
          ),
        ),
      );
    }
  } catch (e) {
    if (context.mounted) {
      ScaffoldMessenger.of(context).hideCurrentSnackBar();
      ScaffoldMessenger.of(context).showSnackBar(
        SnackBar(
          backgroundColor: AppColors.error,
          duration: const Duration(seconds: 5),
          content: Text('Failed to generate $fileName: $e'),
        ),
      );
    }
  } finally {
    ref.read(reportsIsExportingProvider.notifier).state = false;
  }
}

class AdminReportsScreen extends ConsumerWidget {
  const AdminReportsScreen({super.key});

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    final activeSection = ref.watch(adminReportsSectionProvider);
    final filter = ref.watch(adminReportsFilterProvider);
    final isExporting = ref.watch(reportsIsExportingProvider);
    final isDark = Theme.of(context).brightness == Brightness.dark;
    final roleAsync = ref.watch(currentUserRoleProvider);
    final role = roleAsync.valueOrNull?.toLowerCase();

    // 1. Explicit Access Control: Admin only
    if (roleAsync.isLoading) {
      return Scaffold(
        backgroundColor:
            isDark ? AppColors.surfaceContainerLow : AppColors.background,
        body: const Center(
          child: CircularProgressIndicator(color: AppColors.primary),
        ),
      );
    }

    if (role != 'admin') {
      return Scaffold(
        backgroundColor:
            isDark ? AppColors.surfaceContainerLow : AppColors.background,
        appBar: AppBar(
          title: const Text('Reports & Analytics'),
          backgroundColor: isDark
              ? AppColors.surfaceContainerHigh
              : AppColors.surfaceContainerLowest,
          foregroundColor: isDark ? Colors.white : AppColors.onSurface,
        ),
        body: Center(
          child: Padding(
            padding: const EdgeInsets.all(24.0),
            child: Card(
              color: isDark
                  ? AppColors.surfaceContainerHigh
                  : AppColors.surfaceContainerLowest,
              shape: RoundedRectangleBorder(
                borderRadius: BorderRadius.circular(AppSpacing.radiusLg),
                side: BorderSide(
                    color:
                        isDark ? AppColors.outline : AppColors.outlineVariant),
              ),
              elevation: 0,
              child: Padding(
                padding: const EdgeInsets.all(32.0),
                child: Column(
                  mainAxisSize: MainAxisSize.min,
                  children: [
                    Container(
                      padding: const EdgeInsets.all(16),
                      decoration: BoxDecoration(
                        color: AppColors.error.withValues(alpha: 0.1),
                        shape: BoxShape.circle,
                      ),
                      child: const Icon(Icons.lock_person_outlined,
                          size: 48, color: AppColors.error),
                    ),
                    const SizedBox(height: 20),
                    Text(
                      'Access Restricted',
                      style: AppTypography.headlineMd
                          .copyWith(fontWeight: FontWeight.bold),
                    ),
                    const SizedBox(height: 8),
                    Text(
                      'Only administrators have permission to access clinic reports, financial analytics, and inventory valuations.',
                      textAlign: TextAlign.center,
                      style: AppTypography.bodySm
                          .copyWith(color: AppColors.onSurfaceVariant),
                    ),
                    const SizedBox(height: 24),
                    ElevatedButton.icon(
                      onPressed: () => Navigator.of(context).maybePop(),
                      icon: const Icon(Icons.arrow_back),
                      label: const Text('Return to Dashboard'),
                      style: ElevatedButton.styleFrom(
                        backgroundColor: AppColors.primary,
                        foregroundColor: Colors.white,
                      ),
                    ),
                  ],
                ),
              ),
            ),
          ),
        ),
      );
    }

    return Scaffold(
      backgroundColor:
          isDark ? AppColors.surfaceContainerLow : AppColors.background,
      appBar: AppBar(
        title: Column(
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            Text(
              'Reports & Analytics',
              style: AppTypography.headlineMd
                  .copyWith(fontSize: 18, fontWeight: FontWeight.w700),
            ),
            Text(
              'Clinic-wide insights & performance overview',
              style: AppTypography.bodySm.copyWith(
                fontSize: 12,
                color: isDark
                    ? AppColors.outlineVariant
                    : AppColors.onSurfaceVariant,
              ),
            ),
          ],
        ),
        backgroundColor: isDark
            ? AppColors.surfaceContainerHigh
            : AppColors.surfaceContainerLowest,
        foregroundColor: isDark ? Colors.white : AppColors.onSurface,
        elevation: 0.5,
        actions: [
          IconButton(
            tooltip: 'Refresh analytics',
            icon: const Icon(Icons.refresh_rounded),
            onPressed: () {
              ref.invalidate(overviewReportsProvider);
              ref.invalidate(patientReportsProvider);
              ref.invalidate(appointmentReportsProvider);
              ref.invalidate(staffReportsProvider);
              ref.invalidate(clinicalReportsProvider);
              ref.invalidate(financialReportsProvider);
              ref.invalidate(inventoryReportsProvider);
            },
          ),
          IconButton(
            tooltip: 'Master Excel Synchronization',
            icon: const Icon(Icons.cloud_sync_outlined),
            onPressed: () {
              showDialog(
                context: context,
                builder: (context) => const ExcelSyncManagerDialog(),
              );
            },
          ),
          // Repurposed Download button: Downloads standalone Excel (.xlsx) report
          // for the currently active section and filter period
          isExporting
              ? const Padding(
                  padding: EdgeInsets.symmetric(horizontal: 12),
                  child: SizedBox(
                    width: 20,
                    height: 20,
                    child: CircularProgressIndicator(
                      strokeWidth: 2,
                      color: AppColors.primary,
                    ),
                  ),
                )
              : IconButton(
                  key: const Key('reports_download_excel_button'),
                  tooltip: 'Download Excel Report (${filter.getReportFileName(activeSection)})',
                  icon: const Icon(Icons.file_download_outlined),
                  onPressed: () => _handleDownloadReport(
                    context,
                    ref,
                    activeSection,
                    filter,
                  ),
                ),
          const SizedBox(width: 8),
        ],
      ),
      body: SingleChildScrollView(
        padding: const EdgeInsets.all(16),
        child: Column(
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            // Unified Filter Toolbar
            const ReportsFilterToolbar(),
            const SizedBox(height: 20),

            // Active Section Content
            switch (activeSection) {
              ReportsSection.overview => const _OverviewSectionView(),
              ReportsSection.patients => const _PatientReportsView(),
              ReportsSection.appointments => const _AppointmentReportsView(),
              ReportsSection.staff => const _StaffReportsView(),
              ReportsSection.clinical => const _ClinicalReportsView(),
              ReportsSection.financial => const _FinancialReportsView(),
              ReportsSection.inventory => const _InventoryReportsView(),
            },
            const SizedBox(height: 40),
          ],
        ),
      ),
    );
  }
}

// ==========================================
// 1. OVERVIEW SECTION
// ==========================================
class _OverviewSectionView extends ConsumerWidget {
  const _OverviewSectionView();

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    final asyncData = ref.watch(overviewReportsProvider);
    final filter = ref.watch(adminReportsFilterProvider);
    final dept = filter.department.toLowerCase();
    final currency =
        NumberFormat.currency(locale: 'en_IN', symbol: '₹', decimalDigits: 0);

    return asyncData.when(
      loading: () =>
          const _LoadingView(message: 'Loading clinic overview analytics...'),
      error: (err, _) => _ErrorView(message: err.toString()),
      data: (data) {
        return Column(
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            // KPI Grid
            LayoutBuilder(
              builder: (context, constraints) {
                final count = constraints.maxWidth > 1100
                    ? 4
                    : constraints.maxWidth > 650
                        ? 2
                        : 1;
                return GridView.count(
                  crossAxisCount: count,
                  shrinkWrap: true,
                  physics: const NeverScrollableScrollPhysics(),
                  mainAxisSpacing: 16,
                  crossAxisSpacing: 16,
                  childAspectRatio: constraints.maxWidth > 650 ? 1.6 : 2.2,
                  children: [
                    ReportsMetricCard(
                      title: 'Total Patients',
                      value: data.totalPatients.toString(),
                      subtitle:
                          '${data.newPatients} registered in selected period',
                      icon: Icons.people_alt_outlined,
                      iconColor: AppColors.primary,
                    ),
                    ReportsMetricCard(
                      title: 'Total Appointments',
                      value: data.totalAppointments.toString(),
                      subtitle:
                          '${data.completedAppointments} successfully completed',
                      icon: Icons.calendar_month_outlined,
                      iconColor: AppColors.primary,
                    ),
                    ReportsMetricCard(
                      title: 'Procedures & Services',
                      value: data.totalProcedures.toString(),
                      subtitle: dept == 'eye'
                          ? '${data.eyeProcedures} Eye surgeries & procedures'
                          : (dept == 'dental'
                              ? '${data.dentalProcedures} Dental procedures'
                              : 'Eye: ${data.eyeProcedures} • Dental: ${data.dentalProcedures}'),
                      icon: Icons.medical_services_outlined,
                      iconColor: dept == 'dental'
                          ? AppColors.secondary
                          : AppColors.primary,
                    ),
                    ReportsMetricCard(
                      title: 'Total Invoiced Sales',
                      value: currency.format(data.totalSales),
                      subtitle:
                          'Revenue: ${currency.format(data.totalRevenue)}',
                      icon: Icons.account_balance_wallet_outlined,
                      iconColor: AppColors.primary,
                    ),
                    ReportsMetricCard(
                      title: 'Inventory Valuation',
                      value: currency.format(data.totalInventoryValuation),
                      subtitle: dept == 'all'
                          ? '${data.lowStockCount} low stock • ${data.expiredBatchesCount} expired'
                          : '${data.lowStockCount} low stock in ${dept == 'eye' ? 'Eye Clinic' : 'Dental Care'}',
                      icon: Icons.inventory_2_outlined,
                      iconColor: AppColors.primary,
                    ),
                  ],
                );
              },
            ),
            const SizedBox(height: 20),

            // Department Distribution Snapshot
            _CardContainer(
              title: dept == 'eye'
                  ? 'Eye Clinic Distribution Snapshot'
                  : (dept == 'dental'
                      ? 'Dental Care Distribution Snapshot'
                      : 'Department Distribution Snapshot'),
              child: Column(
                children: [
                  if (dept == 'all') ...[
                    DepartmentRatioBar(
                      eyePercentage: data.eyePercentage,
                      dentalPercentage: data.dentalPercentage,
                      eyeCount: data.eyePatients,
                      dentalCount: data.dentalPatients,
                    ),
                    const SizedBox(height: 16),
                    Row(
                      mainAxisAlignment: MainAxisAlignment.spaceAround,
                      children: [
                        _MiniSummary(
                          label: 'Eye Appointments',
                          value: data.eyeAppointments.toString(),
                          color: AppColors.primary,
                        ),
                        _MiniSummary(
                          label: 'Dental Appointments',
                          value: data.dentalAppointments.toString(),
                          color: AppColors.secondary,
                        ),
                        _MiniSummary(
                          label: 'Eye Invoiced',
                          value: currency.format(data.eyeSales),
                          color: AppColors.primary,
                        ),
                        _MiniSummary(
                          label: 'Dental Invoiced',
                          value: currency.format(data.dentalSales),
                          color: AppColors.secondary,
                        ),
                      ],
                    ),
                  ] else if (dept == 'eye') ...[
                    Row(
                      mainAxisAlignment: MainAxisAlignment.spaceAround,
                      children: [
                        _MiniSummary(
                          label: 'Eye Appointments',
                          value: data.eyeAppointments.toString(),
                          color: AppColors.primary,
                        ),
                        _MiniSummary(
                          label: 'Eye Surgeries & Procedures',
                          value: data.eyeProcedures.toString(),
                          color: AppColors.primary,
                        ),
                        _MiniSummary(
                          label: 'Eye Invoiced Sales',
                          value: currency.format(data.eyeSales),
                          color: AppColors.primary,
                        ),
                        _MiniSummary(
                          label: 'Eye Patients',
                          value: data.eyePatients.toString(),
                          color: AppColors.primary,
                        ),
                      ],
                    ),
                  ] else if (dept == 'dental') ...[
                    Row(
                      mainAxisAlignment: MainAxisAlignment.spaceAround,
                      children: [
                        _MiniSummary(
                          label: 'Dental Appointments',
                          value: data.dentalAppointments.toString(),
                          color: AppColors.secondary,
                        ),
                        _MiniSummary(
                          label: 'Dental Procedures',
                          value: data.dentalProcedures.toString(),
                          color: AppColors.secondary,
                        ),
                        _MiniSummary(
                          label: 'Dental Invoiced Sales',
                          value: currency.format(data.dentalSales),
                          color: AppColors.secondary,
                        ),
                        _MiniSummary(
                          label: 'Dental Patients',
                          value: data.dentalPatients.toString(),
                          color: AppColors.secondary,
                        ),
                      ],
                    ),
                  ],
                ],
              ),
            ),
            const SizedBox(height: 20),

            // Trend Chart
            if (data.trendPoints.isNotEmpty)
              _CardContainer(
                title: dept == 'eye'
                    ? 'Eye Clinic Activity & Sales Trend'
                    : (dept == 'dental'
                        ? 'Dental Care Activity & Sales Trend'
                        : 'Clinical Activity & Sales Trend'),
                child: ReportsLineChart(
                  primaryLabel: dept == 'eye'
                      ? 'Eye Surgeries / Procedures'
                      : (dept == 'dental'
                          ? 'Dental Procedures'
                          : 'Procedures Count'),
                  secondaryLabel: 'Invoiced Sales (₹)',
                  primaryColor: dept == 'dental'
                      ? AppColors.secondary
                      : AppColors.primary,
                  secondaryColor: dept == 'dental'
                      ? AppColors.secondaryContainer
                      : AppColors.primaryContainer,
                  data: data.trendPoints.map((p) {
                    return ChartDataPoint(
                      label: p.label,
                      value: p.procedureCount.toDouble(),
                      secondaryValue: p.salesAmount,
                    );
                  }).toList(),
                ),
              )
            else
              const _EmptyStateView(
                  title: 'No activity data available for the selected period.'),
          ],
        );
      },
    );
  }
}

// ==========================================
// 2. PATIENT REPORTS SECTION
// ==========================================
class _PatientReportsView extends ConsumerWidget {
  const _PatientReportsView();

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    final asyncData = ref.watch(patientReportsProvider);
    final filter = ref.watch(adminReportsFilterProvider);
    final dept = filter.department.toLowerCase();
    final isDark = Theme.of(context).brightness == Brightness.dark;

    return asyncData.when(
      loading: () => const _LoadingView(message: 'Loading patient reports...'),
      error: (err, _) => _ErrorView(message: err.toString()),
      data: (data) {
        return Column(
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            // KPI Grid
            LayoutBuilder(
              builder: (context, constraints) {
                final count = constraints.maxWidth > 1100
                    ? 4
                    : constraints.maxWidth > 650
                        ? 2
                        : 1;
                return GridView.count(
                  crossAxisCount: count,
                  shrinkWrap: true,
                  physics: const NeverScrollableScrollPhysics(),
                  mainAxisSpacing: 16,
                  crossAxisSpacing: 16,
                  childAspectRatio: constraints.maxWidth > 650 ? 1.6 : 2.2,
                  children: [
                    ReportsMetricCard(
                      title: 'Total Patients',
                      value: data.totalPatients.toString(),
                      icon: Icons.people_alt_outlined,
                      iconColor: AppColors.primary,
                    ),
                    ReportsMetricCard(
                      title: 'New Patients in Period',
                      value: data.newPatients.toString(),
                      icon: Icons.person_add_alt_1_outlined,
                      iconColor: AppColors.primary,
                    ),
                    ReportsMetricCard(
                      title: 'Returning Patients',
                      value: data.returningPatients.toString(),
                      subtitle: 'Patients with >1 appointment',
                      icon: Icons.repeat_rounded,
                      iconColor: AppColors.tertiary,
                    ),
                    ReportsMetricCard(
                      title: dept == 'eye'
                          ? 'Eye Clinic Patients'
                          : (dept == 'dental'
                              ? 'Dental Care Patients'
                              : 'Department Breakdown'),
                      value: dept == 'eye'
                          ? '${data.eyePatients} Patients'
                          : (dept == 'dental'
                              ? '${data.dentalPatients} Patients'
                              : '${data.eyePatients} Eye / ${data.dentalPatients} Dental'),
                      icon: Icons.pie_chart_outline_rounded,
                      iconColor: dept == 'dental'
                          ? AppColors.secondary
                          : AppColors.primary,
                    ),
                  ],
                );
              },
            ),
            const SizedBox(height: 20),

            // Registration Trends Chart
            _CardContainer(
              title: dept == 'eye'
                  ? 'Eye Clinic Patient Registration Trend'
                  : (dept == 'dental'
                      ? 'Dental Care Patient Registration Trend'
                      : 'Patient Registration Trend'),
              child: data.registrationTrends.isNotEmpty
                  ? ReportsLineChart(
                      primaryLabel: 'Registrations',
                      primaryColor: dept == 'dental'
                          ? AppColors.secondary
                          : AppColors.primary,
                      data: data.registrationTrends.map((p) {
                        return ChartDataPoint(
                          label: p.label,
                          value: p.count.toDouble(),
                        );
                      }).toList(),
                    )
                  : const _EmptyStateView(
                      title: 'No new registrations in this period.'),
            ),
            const SizedBox(height: 20),

            // Department Distribution / Breakdown
            if (dept == 'all')
              _CardContainer(
                title: 'Department Distribution',
                child: Column(
                  children: [
                    ReportsDonutChart(
                      centerTitle: data.totalPatients.toString(),
                      centerSubtitle: 'Total Patients',
                      segments: [
                        DonutSegment(
                          label: 'Eye Clinic',
                          value: data.eyePatients.toDouble(),
                          color: AppColors.primary,
                        ),
                        DonutSegment(
                          label: 'Dental Clinic',
                          value: data.dentalPatients.toDouble(),
                          color: AppColors.secondary,
                        ),
                      ],
                    ),
                    const SizedBox(height: 20),
                    DepartmentRatioBar(
                      eyePercentage: data.eyePercentage,
                      dentalPercentage: data.dentalPercentage,
                      eyeCount: data.eyePatients,
                      dentalCount: data.dentalPatients,
                    ),
                  ],
                ),
              )
            else
              _CardContainer(
                title: dept == 'eye'
                    ? 'Eye Clinic Patient Summary'
                    : 'Dental Care Patient Summary',
                child: Row(
                  mainAxisAlignment: MainAxisAlignment.spaceAround,
                  children: [
                    _MiniSummary(
                      label: dept == 'eye' ? 'Eye Patients' : 'Dental Patients',
                      value: (dept == 'eye'
                              ? data.eyePatients
                              : data.dentalPatients)
                          .toString(),
                      color: dept == 'eye'
                          ? AppColors.primary
                          : AppColors.secondary,
                    ),
                    _MiniSummary(
                      label: 'New Registrations',
                      value: data.newPatients.toString(),
                      color: dept == 'eye'
                          ? AppColors.primary
                          : AppColors.secondary,
                    ),
                    _MiniSummary(
                      label: 'Returning Patients',
                      value: data.returningPatients.toString(),
                      color: dept == 'eye'
                          ? AppColors.primary
                          : AppColors.secondary,
                    ),
                  ],
                ),
              ),
            const SizedBox(height: 20),

            // Recent Registrations Table
            _CardContainer(
              title: dept == 'eye'
                  ? 'Recent Eye Patient Registrations'
                  : (dept == 'dental'
                      ? 'Recent Dental Patient Registrations'
                      : 'Recent Patient Registrations'),
              child: data.recentPatients.isNotEmpty
                  ? SingleChildScrollView(
                      scrollDirection: Axis.horizontal,
                      child: DataTable(
                        headingRowColor: WidgetStateProperty.all(
                          isDark
                              ? AppColors.surfaceContainerHigh
                              : AppColors.surfaceContainerLow,
                        ),
                        columns: const [
                          DataColumn(label: Text('Patient ID')),
                          DataColumn(label: Text('Name')),
                          DataColumn(label: Text('Department')),
                          DataColumn(label: Text('Phone')),
                          DataColumn(label: Text('Registered Date')),
                        ],
                        rows: data.recentPatients.map((p) {
                          return DataRow(cells: [
                            DataCell(Text(
                              p.patientNumber,
                              style:
                                  const TextStyle(fontWeight: FontWeight.w600),
                            )),
                            DataCell(Text(p.name)),
                            DataCell(_DepartmentBadge(
                                department: p.department ?? 'eye')),
                            DataCell(Text(p.mobile ?? '-')),
                            DataCell(Text(DateFormat('dd MMM yyyy, hh:mm a')
                                .format(p.createdAt))),
                          ]);
                        }).toList(),
                      ),
                    )
                  : const _EmptyStateView(
                      title: 'No patient registrations found in this range.'),
            ),
          ],
        );
      },
    );
  }
}

// ==========================================
// 3. APPOINTMENT REPORTS SECTION
// ==========================================
class _AppointmentReportsView extends ConsumerWidget {
  const _AppointmentReportsView();

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    final asyncData = ref.watch(appointmentReportsProvider);
    final isDark = Theme.of(context).brightness == Brightness.dark;

    return asyncData.when(
      loading: () =>
          const _LoadingView(message: 'Loading appointment analytics...'),
      error: (err, _) => _ErrorView(message: err.toString()),
      data: (data) {
        return Column(
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            // KPI Grid
            LayoutBuilder(
              builder: (context, constraints) {
                final count = constraints.maxWidth > 1100
                    ? 4
                    : constraints.maxWidth > 650
                        ? 2
                        : 1;
                return GridView.count(
                  crossAxisCount: count,
                  shrinkWrap: true,
                  physics: const NeverScrollableScrollPhysics(),
                  mainAxisSpacing: 16,
                  crossAxisSpacing: 16,
                  childAspectRatio: constraints.maxWidth > 650 ? 1.6 : 2.2,
                  children: [
                    ReportsMetricCard(
                      title: 'Total Appointments',
                      value: data.totalAppointments.toString(),
                      icon: Icons.calendar_month_outlined,
                      iconColor: AppColors.primary,
                    ),
                    ReportsMetricCard(
                      title: 'Completed Appointments',
                      value: data.completedAppointments.toString(),
                      subtitle:
                          '${data.completionRate.toStringAsFixed(1)}% completion rate',
                      icon: Icons.check_circle_outline_rounded,
                      iconColor: AppColors.primary,
                    ),
                    ReportsMetricCard(
                      title: 'Cancelled / Missed',
                      value: data.cancelledAppointments.toString(),
                      subtitle:
                          '${data.cancellationRate.toStringAsFixed(1)}% cancellation rate',
                      icon: Icons.cancel_outlined,
                      iconColor: AppColors.error,
                    ),
                    ReportsMetricCard(
                      title: 'Scheduled / Waiting',
                      value: (data.scheduledAppointments +
                              data.inTriageAppointments)
                          .toString(),
                      subtitle:
                          '${data.scheduledAppointments} scheduled • ${data.inTriageAppointments} in triage',
                      icon: Icons.hourglass_top_rounded,
                      iconColor: AppColors.secondary,
                    ),
                  ],
                );
              },
            ),
            const SizedBox(height: 20),

            // Appointment Trends
            _CardContainer(
              title: 'Appointment Volume Trends',
              child: data.appointmentTrends.isNotEmpty
                  ? ReportsLineChart(
                      primaryLabel: 'Total',
                      secondaryLabel: 'Completed',
                      primaryColor: AppColors.primary,
                      secondaryColor: AppColors.secondary,
                      data: data.appointmentTrends.map((p) {
                        return ChartDataPoint(
                          label: p.label,
                          value: p.total.toDouble(),
                          secondaryValue: p.completed.toDouble(),
                        );
                      }).toList(),
                    )
                  : const _EmptyStateView(
                      title: 'No appointments recorded in this range.'),
            ),
            const SizedBox(height: 20),

            // Appointment Types & Department Breakdown
            Row(
              children: [
                Expanded(
                  child: _CardContainer(
                    title: 'Appointment Types',
                    child: ReportsDonutChart(
                      centerTitle: data.totalAppointments.toString(),
                      centerSubtitle: 'Total Visits',
                      segments: [
                        DonutSegment(
                          label: 'Regular',
                          value: data.regularAppointments.toDouble(),
                          color: AppColors.primary,
                        ),
                        DonutSegment(
                          label: 'Walk-in',
                          value: data.walkInAppointments.toDouble(),
                          color: AppColors.secondary,
                        ),
                        DonutSegment(
                          label: 'Follow-up',
                          value: data.followUpAppointments.toDouble(),
                          color: AppColors.tertiary,
                        ),
                      ],
                    ),
                  ),
                ),
              ],
            ),
            const SizedBox(height: 20),

            // Doctor / Staff Performance Table
            _CardContainer(
              title: 'Doctor / Clinician Breakdown',
              child: data.doctorStats.isNotEmpty
                  ? SingleChildScrollView(
                      scrollDirection: Axis.horizontal,
                      child: DataTable(
                        headingRowColor: WidgetStateProperty.all(
                          isDark
                              ? AppColors.surfaceContainerHigh
                              : AppColors.surfaceContainerLow,
                        ),
                        columns: const [
                          DataColumn(label: Text('Doctor / Clinician')),
                          DataColumn(label: Text('Department')),
                          DataColumn(label: Text('Total Appointments')),
                          DataColumn(label: Text('Completed')),
                          DataColumn(label: Text('Cancelled')),
                          DataColumn(label: Text('Completion Rate')),
                        ],
                        rows: data.doctorStats.map((doc) {
                          return DataRow(cells: [
                            DataCell(Text(
                              doc.doctorName,
                              style:
                                  const TextStyle(fontWeight: FontWeight.w600),
                            )),
                            DataCell(
                                _DepartmentBadge(department: doc.department)),
                            DataCell(Text(doc.totalAppointments.toString())),
                            DataCell(Text(
                              doc.completedAppointments.toString(),
                              style: TextStyle(
                                  color: AppColors.primary,
                                  fontWeight: FontWeight.w600),
                            )),
                            DataCell(Text(
                              doc.cancelledAppointments.toString(),
                              style: TextStyle(
                                color: doc.cancelledAppointments > 0
                                    ? AppColors.error
                                    : AppColors.outline,
                              ),
                            )),
                            DataCell(
                              Row(
                                children: [
                                  SizedBox(
                                    width: 60,
                                    child: LinearProgressIndicator(
                                      value: doc.completionRate / 100,
                                      backgroundColor: AppColors.outlineVariant,
                                      valueColor: AlwaysStoppedAnimation(
                                          AppColors.primary),
                                      borderRadius: BorderRadius.circular(4),
                                    ),
                                  ),
                                  const SizedBox(width: 8),
                                  Text(
                                      '${doc.completionRate.toStringAsFixed(1)}%'),
                                ],
                              ),
                            ),
                          ]);
                        }).toList(),
                      ),
                    )
                  : const _EmptyStateView(
                      title: 'No doctor appointment data recorded.'),
            ),
          ],
        );
      },
    );
  }
}

// ==========================================
// 4. STAFF REPORTS SECTION
// ==========================================
class _StaffReportsView extends ConsumerWidget {
  const _StaffReportsView();

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    final asyncData = ref.watch(staffReportsProvider);
    final isDark = Theme.of(context).brightness == Brightness.dark;

    return asyncData.when(
      loading: () =>
          const _LoadingView(message: 'Loading staff & attendance reports...'),
      error: (err, _) => _ErrorView(message: err.toString()),
      data: (data) {
        return Column(
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            // KPI Grid
            LayoutBuilder(
              builder: (context, constraints) {
                final count = constraints.maxWidth > 1100
                    ? 4
                    : constraints.maxWidth > 650
                        ? 2
                        : 1;
                return GridView.count(
                  crossAxisCount: count,
                  shrinkWrap: true,
                  physics: const NeverScrollableScrollPhysics(),
                  mainAxisSpacing: 16,
                  crossAxisSpacing: 16,
                  childAspectRatio: constraints.maxWidth > 650 ? 1.6 : 2.2,
                  children: [
                    ReportsMetricCard(
                      title: 'Total Staff',
                      value: data.totalStaff.toString(),
                      subtitle: '${data.activeStaff} active staff members',
                      icon: Icons.badge_outlined,
                      iconColor: AppColors.primary,
                    ),
                    ReportsMetricCard(
                      title: 'Attendance Rate',
                      value:
                          '${data.overallAttendanceRate.toStringAsFixed(1)}%',
                      subtitle:
                          '${data.presentCount} present • ${data.lateCount} late • ${data.leaveCount} leave',
                      icon: Icons.how_to_reg_outlined,
                      iconColor: AppColors.secondary,
                    ),
                    ReportsMetricCard(
                      title: 'Task Completion Rate',
                      value: '${data.taskCompletionRate.toStringAsFixed(1)}%',
                      subtitle:
                          '${data.completedTasks} of ${data.totalTasks} tasks completed',
                      icon: Icons.task_alt_rounded,
                      iconColor: AppColors.tertiary,
                    ),
                    ReportsMetricCard(
                      title: 'Overdue Tasks',
                      value: data.overdueTasks.toString(),
                      subtitle: '${data.pendingTasks} pending tasks',
                      icon: Icons.warning_amber_rounded,
                      iconColor: data.overdueTasks > 0
                          ? AppColors.error
                          : AppColors.primary,
                    ),
                  ],
                );
              },
            ),
            const SizedBox(height: 20),

            // Daily Attendance Trend
            _CardContainer(
              title: 'Daily Attendance Trends',
              child: data.attendanceTrends.isNotEmpty
                  ? ReportsLineChart(
                      primaryLabel: 'Present',
                      secondaryLabel: 'Late / Leave',
                      primaryColor: AppColors.primary,
                      secondaryColor: AppColors.secondary,
                      data: data.attendanceTrends.map((p) {
                        return ChartDataPoint(
                          label: p.label,
                          value: p.present.toDouble(),
                          secondaryValue: (p.late + p.leave).toDouble(),
                        );
                      }).toList(),
                    )
                  : const _EmptyStateView(
                      title: 'No attendance logs recorded in this range.'),
            ),
            const SizedBox(height: 20),

            // Staff Performance Breakdown Table
            _CardContainer(
              title: 'Staff Performance & Task Execution',
              child: data.staffStats.isNotEmpty
                  ? SingleChildScrollView(
                      scrollDirection: Axis.horizontal,
                      child: DataTable(
                        headingRowColor: WidgetStateProperty.all(
                          isDark
                              ? AppColors.surfaceContainerHigh
                              : AppColors.surfaceContainerLow,
                        ),
                        columns: const [
                          DataColumn(label: Text('Staff Member')),
                          DataColumn(label: Text('Designation')),
                          DataColumn(label: Text('Present Days')),
                          DataColumn(label: Text('Late Days')),
                          DataColumn(label: Text('Leave Days')),
                          DataColumn(label: Text('Attendance %')),
                          DataColumn(label: Text('Total Tasks')),
                          DataColumn(label: Text('Completed Tasks')),
                          DataColumn(label: Text('Overdue')),
                          DataColumn(label: Text('Task Completion %')),
                        ],
                        rows: data.staffStats.map((st) {
                          return DataRow(cells: [
                            DataCell(Text(
                              st.staffName,
                              style:
                                  const TextStyle(fontWeight: FontWeight.w600),
                            )),
                            DataCell(Text(st.designation ?? '-')),
                            DataCell(Text(st.presentDays.toString())),
                            DataCell(Text(
                              st.lateDays.toString(),
                              style: TextStyle(
                                color: st.lateDays > 0
                                    ? AppColors.secondary
                                    : AppColors.outline,
                              ),
                            )),
                            DataCell(Text(
                              st.leaveDays.toString(),
                              style: TextStyle(
                                color: st.leaveDays > 0
                                    ? AppColors.error
                                    : AppColors.outline,
                              ),
                            )),
                            DataCell(Text(
                              '${st.attendancePercentage.toStringAsFixed(0)}%',
                              style:
                                  const TextStyle(fontWeight: FontWeight.w600),
                            )),
                            DataCell(Text(st.totalTasks.toString())),
                            DataCell(Text(
                              st.completedTasks.toString(),
                              style: TextStyle(
                                  color: AppColors.primary,
                                  fontWeight: FontWeight.w600),
                            )),
                            DataCell(Text(
                              st.overdueTasks.toString(),
                              style: TextStyle(
                                color: st.overdueTasks > 0
                                    ? AppColors.error
                                    : AppColors.outline,
                              ),
                            )),
                            DataCell(
                              Row(
                                children: [
                                  SizedBox(
                                    width: 50,
                                    child: LinearProgressIndicator(
                                      value: st.taskCompletionPercentage / 100,
                                      backgroundColor: AppColors.outlineVariant,
                                      valueColor: AlwaysStoppedAnimation(
                                          AppColors.primary),
                                      borderRadius: BorderRadius.circular(4),
                                    ),
                                  ),
                                  const SizedBox(width: 8),
                                  Text(
                                      '${st.taskCompletionPercentage.toStringAsFixed(0)}%'),
                                ],
                              ),
                            ),
                          ]);
                        }).toList(),
                      ),
                    )
                  : const _EmptyStateView(
                      title: 'No staff performance data available.'),
            ),
          ],
        );
      },
    );
  }
}

// ==========================================
// 5. CLINICAL / PROCEDURE REPORTS SECTION
// ==========================================
class _ClinicalReportsView extends ConsumerWidget {
  const _ClinicalReportsView();

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    final asyncData = ref.watch(clinicalReportsProvider);
    final filter = ref.watch(adminReportsFilterProvider);
    final dept = filter.department.toLowerCase();
    final currency =
        NumberFormat.currency(locale: 'en_IN', symbol: '₹', decimalDigits: 0);
    final isDark = Theme.of(context).brightness == Brightness.dark;

    return asyncData.when(
      loading: () => const _LoadingView(
          message: 'Loading clinical & procedure analytics...'),
      error: (err, _) => _ErrorView(message: err.toString()),
      data: (data) {
        final isEyeOnly = dept == 'eye';
        final isDentalOnly = dept == 'dental';

        return Column(
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            // KPI Grid
            LayoutBuilder(
              builder: (context, constraints) {
                final List<Widget> kpiCards = [];

                if (isEyeOnly) {
                  kpiCards.addAll([
                    ReportsMetricCard(
                      title: 'Eye Care Procedures',
                      value: data.eyeProcedures.toString(),
                      subtitle: 'Direct clinical treatments & surgeries',
                      icon: Icons.remove_red_eye_outlined,
                      iconColor: AppColors.primary,
                    ),
                    ReportsMetricCard(
                      title: 'Total Clinical Value',
                      value: currency.format(data.totalProceduresValue),
                      subtitle: 'Direct billed eye services revenue',
                      icon: Icons.payments_outlined,
                      iconColor: AppColors.secondary,
                    ),
                  ]);
                } else if (isDentalOnly) {
                  kpiCards.addAll([
                    ReportsMetricCard(
                      title: 'Dental Care Procedures',
                      value: data.dentalProcedures.toString(),
                      subtitle: 'Direct clinical treatments & procedures',
                      icon: Icons.health_and_safety_outlined,
                      iconColor: AppColors.secondary,
                    ),
                    ReportsMetricCard(
                      title: 'Total Clinical Value',
                      value: currency.format(data.totalProceduresValue),
                      subtitle: 'Direct billed dental services revenue',
                      icon: Icons.payments_outlined,
                      iconColor: AppColors.primary,
                    ),
                  ]);
                } else {
                  kpiCards.addAll([
                    ReportsMetricCard(
                      title: 'Total Procedures Performed',
                      value: data.totalProcedures.toString(),
                      icon: Icons.medical_services_outlined,
                      iconColor: AppColors.primary,
                    ),
                    ReportsMetricCard(
                      title: 'Eye Care Procedures',
                      value: data.eyeProcedures.toString(),
                      subtitle:
                          '${data.eyePercentage.toStringAsFixed(1)}% of all clinical activity',
                      icon: Icons.remove_red_eye_outlined,
                      iconColor: AppColors.primary,
                    ),
                    ReportsMetricCard(
                      title: 'Dental Care Procedures',
                      value: data.dentalProcedures.toString(),
                      subtitle:
                          '${data.dentalPercentage.toStringAsFixed(1)}% of all clinical activity',
                      icon: Icons.health_and_safety_outlined,
                      iconColor: AppColors.secondary,
                    ),
                    ReportsMetricCard(
                      title: 'Total Clinical Value',
                      value: currency.format(data.totalProceduresValue),
                      subtitle: 'Direct billed services revenue',
                      icon: Icons.payments_outlined,
                      iconColor: AppColors.tertiary,
                    ),
                  ]);
                }

                final count = constraints.maxWidth > 1100
                    ? (kpiCards.length > 2 ? 4 : 2)
                    : constraints.maxWidth > 650
                        ? 2
                        : 1;

                return GridView.count(
                  crossAxisCount: count,
                  shrinkWrap: true,
                  physics: const NeverScrollableScrollPhysics(),
                  mainAxisSpacing: 16,
                  crossAxisSpacing: 16,
                  childAspectRatio: constraints.maxWidth > 650 ? 1.6 : 2.2,
                  children: kpiCards,
                );
              },
            ),
            const SizedBox(height: 20),

            // Procedure Trends
            _CardContainer(
              title: isEyeOnly
                  ? 'Eye Procedure Frequency Trends'
                  : isDentalOnly
                      ? 'Dental Procedure Frequency Trends'
                      : 'Procedure Frequency Trends',
              child: data.procedureTrends.isNotEmpty
                  ? ReportsLineChart(
                      primaryLabel: isEyeOnly
                          ? 'Eye Procedures'
                          : isDentalOnly
                              ? 'Dental Procedures'
                              : 'Eye Procedures',
                      secondaryLabel: isEyeOnly || isDentalOnly
                          ? null
                          : 'Dental Procedures',
                      primaryColor: isDentalOnly
                          ? AppColors.secondary
                          : AppColors.primary,
                      secondaryColor: AppColors.secondary,
                      data: data.procedureTrends.map((p) {
                        return ChartDataPoint(
                          label: p.label,
                          value: isDentalOnly
                              ? p.dentalCount.toDouble()
                              : p.eyeCount.toDouble(),
                          secondaryValue: isEyeOnly || isDentalOnly
                              ? null
                              : p.dentalCount.toDouble(),
                        );
                      }).toList(),
                    )
                  : const _EmptyStateView(
                      title: 'No procedures recorded for this period.'),
            ),
            const SizedBox(height: 20),

            // Top Procedures Leaderboard Table
            _CardContainer(
              title: isEyeOnly
                  ? 'Most Frequently Performed Procedures (Eye Clinic)'
                  : isDentalOnly
                      ? 'Most Frequently Performed Procedures (Dental Care)'
                      : 'Most Frequently Performed Procedures',
              child: data.topProcedures.isNotEmpty
                  ? SingleChildScrollView(
                      scrollDirection: Axis.horizontal,
                      child: DataTable(
                        headingRowColor: WidgetStateProperty.all(
                          isDark
                              ? AppColors.surfaceContainerHigh
                              : AppColors.surfaceContainerLow,
                        ),
                        columns: const [
                          DataColumn(label: Text('Rank')),
                          DataColumn(label: Text('Procedure / Service')),
                          DataColumn(label: Text('Department')),
                          DataColumn(label: Text('Frequency (Count)')),
                          DataColumn(label: Text('Avg Price')),
                          DataColumn(label: Text('Total Value')),
                        ],
                        rows: data.topProcedures.asMap().entries.map((entry) {
                          final rank = entry.key + 1;
                          final proc = entry.value;
                          return DataRow(cells: [
                            DataCell(Text(
                              '#$rank',
                              style: TextStyle(
                                fontWeight: FontWeight.bold,
                                color: rank <= 3 ? AppColors.primary : null,
                              ),
                            )),
                            DataCell(Text(
                              proc.procedureName,
                              style:
                                  const TextStyle(fontWeight: FontWeight.w600),
                            )),
                            DataCell(
                                _DepartmentBadge(department: proc.department)),
                            DataCell(Text(
                              proc.count.toString(),
                              style:
                                  const TextStyle(fontWeight: FontWeight.bold),
                            )),
                            DataCell(Text(currency.format(proc.averagePrice))),
                            DataCell(Text(
                              currency.format(proc.totalRevenue),
                              style: TextStyle(
                                fontWeight: FontWeight.w600,
                                color: AppColors.primary,
                              ),
                            )),
                          ]);
                        }).toList(),
                      ),
                    )
                  : const _EmptyStateView(
                      title: 'No clinical procedure data available.'),
            ),
          ],
        );
      },
    );
  }
}

// ==========================================
// 6. FINANCIAL / BILLING SUMMARY SECTION
// ==========================================
class _FinancialReportsView extends ConsumerWidget {
  const _FinancialReportsView();

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    final asyncData = ref.watch(financialReportsProvider);
    final filter = ref.watch(adminReportsFilterProvider);
    final dept = filter.department.toLowerCase();
    final currency =
        NumberFormat.currency(locale: 'en_IN', symbol: '₹', decimalDigits: 0);
    final isDark = Theme.of(context).brightness == Brightness.dark;

    return asyncData.when(
      loading: () =>
          const _LoadingView(message: 'Loading financial summary...'),
      error: (err, _) => _ErrorView(message: err.toString()),
      data: (data) {
        final departmentSummaries = dept == 'eye'
            ? [data.eyeSummary]
            : (dept == 'dental'
                ? [data.dentalSummary]
                : [data.eyeSummary, data.dentalSummary]);

        return Column(
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            // KPI Grid
            LayoutBuilder(
              builder: (context, constraints) {
                final count = constraints.maxWidth > 1100
                    ? 4
                    : constraints.maxWidth > 650
                        ? 2
                        : 1;
                return GridView.count(
                  crossAxisCount: count,
                  shrinkWrap: true,
                  physics: const NeverScrollableScrollPhysics(),
                  mainAxisSpacing: 16,
                  crossAxisSpacing: 16,
                  childAspectRatio: constraints.maxWidth > 650 ? 1.6 : 2.2,
                  children: [
                    ReportsMetricCard(
                      title: 'Total Invoiced Sales',
                      value: currency.format(data.totalSales),
                      subtitle: '${data.totalInvoices} invoices issued',
                      icon: Icons.receipt_long_outlined,
                      iconColor: AppColors.primary,
                    ),
                    ReportsMetricCard(
                      title: 'Revenue Collected',
                      value: currency.format(data.totalRevenue),
                      subtitle:
                          '${data.collectionRate.toStringAsFixed(1)}% collected',
                      icon: Icons.payments_outlined,
                      iconColor: AppColors.secondary,
                    ),
                    ReportsMetricCard(
                      title: 'Outstanding Balance',
                      value: currency.format(data.totalOutstanding),
                      subtitle:
                          '${data.partiallyPaidInvoicesCount} partially paid',
                      icon: Icons.account_balance_wallet_outlined,
                      iconColor: data.totalOutstanding > 0
                          ? AppColors.error
                          : AppColors.primary,
                    ),
                    ReportsMetricCard(
                      title: 'Estimated Profit',
                      value: currency.format(data.estimatedProfit),
                      subtitle: 'Standard 70% estimated margin',
                      icon: Icons.trending_up_rounded,
                      iconColor: AppColors.tertiary,
                    ),
                  ],
                );
              },
            ),
            const SizedBox(height: 20),

            // Revenue Trends
            _CardContainer(
              title: 'Revenue & Sales Trend',
              child: data.periodicBuckets.isNotEmpty
                  ? ReportsLineChart(
                      primaryLabel: 'Invoiced Sales',
                      secondaryLabel: 'Collected Revenue',
                      primaryColor: AppColors.primary,
                      secondaryColor: AppColors.secondary,
                      data: data.periodicBuckets.reversed.map((p) {
                        return ChartDataPoint(
                          label: p.periodLabel,
                          value: p.totalSales,
                          secondaryValue: p.revenueCollected,
                        );
                      }).toList(),
                    )
                  : const _EmptyStateView(
                      title: 'No billing records in this range.'),
            ),
            const SizedBox(height: 20),

            // Payment Modes & Department Breakdown
            Row(
              children: [
                Expanded(
                  child: _CardContainer(
                    title: 'Payment Mode Distribution',
                    child: ReportsDonutChart(
                      centerTitle: currency.format(data.totalRevenue),
                      centerSubtitle: 'Collected',
                      segments: data.paymentModes.map((m) {
                        Color col;
                        switch (m.mode.toLowerCase()) {
                          case 'cash':
                            col = AppColors.primary;
                            break;
                          case 'upi':
                            col = AppColors.secondary;
                            break;
                          case 'bank_transfer':
                            col = AppColors.tertiary;
                            break;
                          default:
                            col = AppColors.outline;
                        }
                        return DonutSegment(
                          label: m.mode.toUpperCase(),
                          value: m.totalAmount,
                          color: col,
                        );
                      }).toList(),
                    ),
                  ),
                ),
              ],
            ),
            const SizedBox(height: 20),

            // Department Financial Breakdown Table
            _CardContainer(
              title: dept == 'eye'
                  ? 'Eye Clinic Financial Summary'
                  : (dept == 'dental'
                      ? 'Dental Care Financial Summary'
                      : 'Department-Wise Financial Summary'),
              child: departmentSummaries.isNotEmpty
                  ? SingleChildScrollView(
                      scrollDirection: Axis.horizontal,
                      child: DataTable(
                        headingRowColor: WidgetStateProperty.all(
                          isDark
                              ? AppColors.surfaceContainerHigh
                              : AppColors.surfaceContainerLow,
                        ),
                        columns: const [
                          DataColumn(label: Text('Department')),
                          DataColumn(label: Text('Invoices')),
                          DataColumn(label: Text('Total Sales')),
                          DataColumn(label: Text('Revenue Collected')),
                          DataColumn(label: Text('Outstanding')),
                          DataColumn(label: Text('Share %')),
                        ],
                        rows: departmentSummaries.map((d) {
                          return DataRow(cells: [
                            DataCell(
                                _DepartmentBadge(department: d.department)),
                            DataCell(Text(d.invoiceCount.toString())),
                            DataCell(Text(
                              currency.format(d.totalSales),
                              style:
                                  const TextStyle(fontWeight: FontWeight.w600),
                            )),
                            DataCell(Text(
                              currency.format(d.revenueCollected),
                              style: TextStyle(
                                  color: AppColors.primary,
                                  fontWeight: FontWeight.w600),
                            )),
                            DataCell(Text(
                              currency.format(d.outstandingBalance),
                              style: TextStyle(
                                color: d.outstandingBalance > 0
                                    ? AppColors.error
                                    : AppColors.outline,
                              ),
                            )),
                            DataCell(
                              Row(
                                children: [
                                  SizedBox(
                                    width: 50,
                                    child: LinearProgressIndicator(
                                      value: d.sharePercentage / 100,
                                      backgroundColor: AppColors.outlineVariant,
                                      valueColor: AlwaysStoppedAnimation(
                                          AppColors.primary),
                                      borderRadius: BorderRadius.circular(4),
                                    ),
                                  ),
                                  const SizedBox(width: 8),
                                  Text(
                                      '${d.sharePercentage.toStringAsFixed(1)}%'),
                                ],
                              ),
                            ),
                          ]);
                        }).toList(),
                      ),
                    )
                  : const _EmptyStateView(
                      title: 'No department financials available.'),
            ),
          ],
        );
      },
    );
  }
}

// ==========================================
// 7. INVENTORY REPORTS SECTION (Phase 8.2)
// ==========================================
class _InventoryReportsView extends ConsumerWidget {
  const _InventoryReportsView();

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    final asyncData = ref.watch(inventoryReportsProvider);
    final filter = ref.watch(adminReportsFilterProvider);
    final dept = filter.department.toLowerCase();
    final currency =
        NumberFormat.currency(locale: 'en_IN', symbol: '₹', decimalDigits: 0);
    final isDark = Theme.of(context).brightness == Brightness.dark;

    return asyncData.when(
      loading: () =>
          const _LoadingView(message: 'Loading inventory & stock analytics...'),
      error: (err, _) => _ErrorView(message: err.toString()),
      data: (data) {
        return Column(
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            // Quick action exports bar
            Row(
              mainAxisAlignment: MainAxisAlignment.spaceBetween,
              children: [
                Text(
                  'Inventory & Stock Analytics',
                  style: TextStyle(
                    fontSize: 18,
                    fontWeight: FontWeight.bold,
                    color: isDark ? AppColors.onSurface : AppColors.onSurface,
                  ),
                ),
                Row(
                  children: [
                    OutlinedButton.icon(
                      icon: const Icon(Icons.table_chart_outlined, size: 16),
                      label: const Text('Excel (.xlsx)'),
                      style: OutlinedButton.styleFrom(
                        foregroundColor: AppColors.primary,
                        side: BorderSide(color: AppColors.primary),
                        padding: const EdgeInsets.symmetric(
                            horizontal: 12, vertical: 8),
                      ),
                      onPressed: () => _handleDownloadReport(
                        context,
                        ref,
                        ReportsSection.inventory,
                        ref.read(adminReportsFilterProvider),
                      ),
                    ),
                    const SizedBox(width: 8),
                    ElevatedButton.icon(
                      icon: const Icon(Icons.print_outlined, size: 16),
                      label: const Text('Print / PDF'),
                      style: ElevatedButton.styleFrom(
                        backgroundColor: AppColors.primary,
                        foregroundColor: Colors.white,
                        padding: const EdgeInsets.symmetric(
                            horizontal: 12, vertical: 8),
                      ),
                      onPressed: () =>
                          ReportsExportService.exportInventoryToPrintableHtml(
                        data: data,
                        filter: ref.read(adminReportsFilterProvider),
                      ),
                    ),
                  ],
                ),
              ],
            ),
            const SizedBox(height: 16),

            // 1. Overview & Valuation Metric Cards
            LayoutBuilder(
              builder: (context, constraints) {
                final count = constraints.maxWidth > 1100
                    ? 4
                    : constraints.maxWidth > 650
                        ? 2
                        : 1;
                return GridView.count(
                  crossAxisCount: count,
                  shrinkWrap: true,
                  physics: const NeverScrollableScrollPhysics(),
                  mainAxisSpacing: 16,
                  crossAxisSpacing: 16,
                  childAspectRatio: constraints.maxWidth > 650 ? 1.6 : 2.2,
                  children: [
                    ReportsMetricCard(
                      title: 'Total Stock Valuation',
                      value: currency.format(data.totalValuation),
                      subtitle:
                          '${data.totalUnits.toInt()} total inventory units',
                      icon: Icons.account_balance_wallet_outlined,
                      iconColor: AppColors.primary,
                    ),
                    ReportsMetricCard(
                      title: 'Catalog Items',
                      value: data.totalCatalogItems.toString(),
                      subtitle: '${data.activeItemsCount} active catalog items',
                      icon: Icons.inventory_2_outlined,
                      iconColor: AppColors.primary,
                    ),
                    ReportsMetricCard(
                      title: 'Central Store Stock',
                      value: currency.format(data.centralValuation),
                      subtitle:
                          '${data.centralUnits.toInt()} units in central store',
                      icon: Icons.warehouse_outlined,
                      iconColor: AppColors.tertiary,
                    ),
                    ReportsMetricCard(
                      title: dept == 'eye'
                          ? 'Eye Dept Allocation'
                          : (dept == 'dental'
                              ? 'Dental Dept Allocation'
                              : 'Department Allocations'),
                      value: currency.format(
                        dept == 'eye'
                            ? data.eyeValuation
                            : (dept == 'dental'
                                ? data.dentalValuation
                                : (data.eyeValuation + data.dentalValuation)),
                      ),
                      subtitle: dept == 'eye'
                          ? '${data.eyeUnits.toInt()} units allocated to Eye Clinic'
                          : (dept == 'dental'
                              ? '${data.dentalUnits.toInt()} units allocated to Dental Care'
                              : 'Eye: ${currency.format(data.eyeValuation)} • Dental: ${currency.format(data.dentalValuation)}'),
                      icon: Icons.storefront_outlined,
                      iconColor: AppColors.secondary,
                    ),
                  ],
                );
              },
            ),
            const SizedBox(height: 20),

            // Stock Allocation Breakdown
            _CardContainer(
              title: 'Stock Allocation & Distribution',
              child: Column(
                crossAxisAlignment: CrossAxisAlignment.start,
                children: [
                  _AllocationRatioBar(
                    centralUnits: data.centralUnits,
                    eyeUnits: dept == 'dental' ? 0.0 : data.eyeUnits,
                    dentalUnits: dept == 'eye' ? 0.0 : data.dentalUnits,
                  ),
                  const SizedBox(height: 16),
                  Row(
                    mainAxisAlignment: MainAxisAlignment.spaceAround,
                    children: [
                      _MiniSummary(
                        label: 'Central Store',
                        value: '${data.centralUnits.toInt()} units',
                        color: AppColors.tertiary,
                      ),
                      if (dept != 'dental')
                        _MiniSummary(
                          label: 'Eye Clinic',
                          value: '${data.eyeUnits.toInt()} units',
                          color: AppColors.primary,
                        ),
                      if (dept != 'eye')
                        _MiniSummary(
                          label: 'Dental Clinic',
                          value: '${data.dentalUnits.toInt()} units',
                          color: AppColors.secondary,
                        ),
                    ],
                  ),
                ],
              ),
            ),
            const SizedBox(height: 20),

            // Category Valuation Table
            _CardContainer(
              title: 'Category-wise Stock Valuation',
              child: data.categoryValuations.isNotEmpty
                  ? SingleChildScrollView(
                      scrollDirection: Axis.horizontal,
                      child: DataTable(
                        columnSpacing: 24,
                        columns: const [
                          DataColumn(
                              label: Text('Category',
                                  style:
                                      TextStyle(fontWeight: FontWeight.bold))),
                          DataColumn(
                              label: Text('Items',
                                  style:
                                      TextStyle(fontWeight: FontWeight.bold)),
                              numeric: true),
                          DataColumn(
                              label: Text('Stock Units',
                                  style:
                                      TextStyle(fontWeight: FontWeight.bold)),
                              numeric: true),
                          DataColumn(
                              label: Text('Valuation (₹)',
                                  style:
                                      TextStyle(fontWeight: FontWeight.bold)),
                              numeric: true),
                          DataColumn(
                              label: Text('Share',
                                  style:
                                      TextStyle(fontWeight: FontWeight.bold))),
                        ],
                        rows: data.categoryValuations.map((c) {
                          return DataRow(cells: [
                            DataCell(Text(c.category,
                                style: const TextStyle(
                                    fontWeight: FontWeight.w600))),
                            DataCell(Text(c.itemCount.toString())),
                            DataCell(Text(c.totalUnits.toInt().toString())),
                            DataCell(Text(currency.format(c.totalValuation))),
                            DataCell(
                              Row(
                                children: [
                                  SizedBox(
                                    width: 50,
                                    child: LinearProgressIndicator(
                                      value: c.percentage / 100,
                                      backgroundColor: AppColors.outlineVariant,
                                      valueColor: AlwaysStoppedAnimation(
                                          AppColors.primary),
                                      borderRadius: BorderRadius.circular(4),
                                    ),
                                  ),
                                  const SizedBox(width: 8),
                                  Text('${c.percentage.toStringAsFixed(1)}%'),
                                ],
                              ),
                            ),
                          ]);
                        }).toList(),
                      ),
                    )
                  : const _EmptyStateView(
                      title: 'No category inventory available.'),
            ),
            const SizedBox(height: 20),

            // 2. Low-Stock & Reordering Alert Section
            _CardContainer(
              title: 'Low-Stock & Reorder Alerts',
              child: Column(
                crossAxisAlignment: CrossAxisAlignment.start,
                children: [
                  Row(
                    children: [
                      _StatusChip(
                        label: 'Central Low: ${data.centralLowStockCount}',
                        color: AppColors.tertiary,
                        icon: Icons.warehouse_outlined,
                      ),
                      const SizedBox(width: 8),
                      _StatusChip(
                        label: 'Dept Low: ${data.departmentLowStockCount}',
                        color: AppColors.secondary,
                        icon: Icons.storefront_outlined,
                      ),
                      const SizedBox(width: 8),
                      _StatusChip(
                        label: 'Stock-Outs: ${data.stockOutCount}',
                        color: AppColors.error,
                        icon: Icons.cancel_outlined,
                      ),
                    ],
                  ),
                  const SizedBox(height: 16),
                  if (data.lowStockItems.isNotEmpty)
                    SingleChildScrollView(
                      scrollDirection: Axis.horizontal,
                      child: DataTable(
                        columnSpacing: 20,
                        columns: const [
                          DataColumn(
                              label: Text('Item Name',
                                  style:
                                      TextStyle(fontWeight: FontWeight.bold))),
                          DataColumn(
                              label: Text('Location',
                                  style:
                                      TextStyle(fontWeight: FontWeight.bold))),
                          DataColumn(
                              label: Text('Current Stock',
                                  style:
                                      TextStyle(fontWeight: FontWeight.bold)),
                              numeric: true),
                          DataColumn(
                              label: Text('Min Stock',
                                  style:
                                      TextStyle(fontWeight: FontWeight.bold)),
                              numeric: true),
                          DataColumn(
                              label: Text('Shortfall',
                                  style:
                                      TextStyle(fontWeight: FontWeight.bold)),
                              numeric: true),
                          DataColumn(
                              label: Text('Preferred Vendor',
                                  style:
                                      TextStyle(fontWeight: FontWeight.bold))),
                          DataColumn(
                              label: Text('Est. Reorder Cost',
                                  style:
                                      TextStyle(fontWeight: FontWeight.bold)),
                              numeric: true),
                        ],
                        rows: data.lowStockItems.map((item) {
                          final estCost = item.lastPrice != null
                              ? item.shortfall * item.lastPrice!
                              : null;
                          return DataRow(cells: [
                            DataCell(
                              Column(
                                crossAxisAlignment: CrossAxisAlignment.start,
                                mainAxisAlignment: MainAxisAlignment.center,
                                children: [
                                  Text(item.itemName,
                                      style: const TextStyle(
                                          fontWeight: FontWeight.w600)),
                                  if (item.sku != null && item.sku!.isNotEmpty)
                                    Text('SKU: ${item.sku}',
                                        style: const TextStyle(
                                            fontSize: 11, color: Colors.grey)),
                                ],
                              ),
                            ),
                            DataCell(_LocationBadge(location: item.location)),
                            DataCell(
                              Text(
                                '${item.currentStock.toInt()} ${item.unit}',
                                style: TextStyle(
                                  fontWeight: FontWeight.bold,
                                  color: item.isStockOut
                                      ? AppColors.error
                                      : AppColors.secondary,
                                ),
                              ),
                            ),
                            DataCell(Text(
                                '${item.minimumStock.toInt()} ${item.unit}')),
                            DataCell(
                              Container(
                                padding: const EdgeInsets.symmetric(
                                    horizontal: 8, vertical: 3),
                                decoration: BoxDecoration(
                                  color: (item.isStockOut
                                          ? AppColors.error
                                          : AppColors.secondary)
                                      .withValues(alpha: 0.15),
                                  borderRadius: BorderRadius.circular(6),
                                ),
                                child: Text(
                                  item.isStockOut
                                      ? 'OUT OF STOCK'
                                      : '-${item.shortfall.toInt()} ${item.unit}',
                                  style: TextStyle(
                                    fontSize: 11,
                                    fontWeight: FontWeight.bold,
                                    color: item.isStockOut
                                        ? AppColors.error
                                        : AppColors.secondary,
                                  ),
                                ),
                              ),
                            ),
                            DataCell(
                              Column(
                                crossAxisAlignment: CrossAxisAlignment.start,
                                mainAxisAlignment: MainAxisAlignment.center,
                                children: [
                                  Text(item.vendorName ?? 'No vendor listed',
                                      style: const TextStyle(fontSize: 12)),
                                  if (item.vendorPhone != null &&
                                      item.vendorPhone!.isNotEmpty)
                                    Text('📞 ${item.vendorPhone}',
                                        style: const TextStyle(
                                            fontSize: 11, color: Colors.grey)),
                                ],
                              ),
                            ),
                            DataCell(Text(estCost != null
                                ? currency.format(estCost)
                                : '—')),
                          ]);
                        }).toList(),
                      ),
                    )
                  else
                    const _EmptyStateView(
                        title:
                            'All items are currently above safety stock thresholds.'),
                ],
              ),
            ),
            const SizedBox(height: 20),

            // 3. Expiry Analytics Section
            _CardContainer(
              title: 'Batch Expiry Risk Analytics',
              child: Column(
                crossAxisAlignment: CrossAxisAlignment.start,
                children: [
                  LayoutBuilder(
                    builder: (context, constraints) {
                      final count = constraints.maxWidth > 900
                          ? 4
                          : constraints.maxWidth > 550
                              ? 2
                              : 1;
                      return GridView.count(
                        crossAxisCount: count,
                        shrinkWrap: true,
                        physics: const NeverScrollableScrollPhysics(),
                        mainAxisSpacing: 12,
                        crossAxisSpacing: 12,
                        childAspectRatio:
                            constraints.maxWidth > 550 ? 2.2 : 2.8,
                        children: [
                          _ExpiryRiskCard(
                            title: 'Already Expired',
                            count: data.expiredBatchesCount,
                            value: currency.format(data.expiredValueLost),
                            color: AppColors.error,
                          ),
                          _ExpiryRiskCard(
                            title: 'Expiring in ≤ 30 Days',
                            count: data.expiring30DaysCount,
                            value: currency.format(data.expiring30DaysValue),
                            color: AppColors.error,
                          ),
                          _ExpiryRiskCard(
                            title: 'Expiring in 31–60 Days',
                            count: data.expiring60DaysCount,
                            value: currency.format(data.expiring60DaysValue),
                            color: AppColors.secondary,
                          ),
                          _ExpiryRiskCard(
                            title: 'Expiring in 61–90 Days',
                            count: data.expiring90DaysCount,
                            value: currency.format(data.expiring90DaysValue),
                            color: AppColors.primary,
                          ),
                        ],
                      );
                    },
                  ),
                  const SizedBox(height: 12),
                  Container(
                    padding: const EdgeInsets.symmetric(
                        horizontal: 14, vertical: 10),
                    decoration: BoxDecoration(
                      color: AppColors.error.withValues(alpha: 0.08),
                      borderRadius: BorderRadius.circular(8),
                      border: Border.all(
                          color: AppColors.error.withValues(alpha: 0.2)),
                    ),
                    child: Row(
                      children: [
                        const Icon(Icons.shield_outlined,
                            color: AppColors.error, size: 18),
                        const SizedBox(width: 8),
                        Text(
                          'Total At-Risk Expiry Valuation: ${currency.format(data.totalAtRiskValue)}',
                          style: const TextStyle(
                              fontWeight: FontWeight.bold,
                              color: AppColors.error,
                              fontSize: 13),
                        ),
                      ],
                    ),
                  ),
                  const SizedBox(height: 16),
                  if (data.batchExpiryDetails.isNotEmpty)
                    SingleChildScrollView(
                      scrollDirection: Axis.horizontal,
                      child: DataTable(
                        columnSpacing: 20,
                        columns: const [
                          DataColumn(
                              label: Text('Batch #',
                                  style:
                                      TextStyle(fontWeight: FontWeight.bold))),
                          DataColumn(
                              label: Text('Item Name',
                                  style:
                                      TextStyle(fontWeight: FontWeight.bold))),
                          DataColumn(
                              label: Text('Expiry Date',
                                  style:
                                      TextStyle(fontWeight: FontWeight.bold))),
                          DataColumn(
                              label: Text('Status / Days',
                                  style:
                                      TextStyle(fontWeight: FontWeight.bold))),
                          DataColumn(
                              label: Text('Remaining Qty',
                                  style:
                                      TextStyle(fontWeight: FontWeight.bold)),
                              numeric: true),
                          DataColumn(
                              label: Text('Unit Cost',
                                  style:
                                      TextStyle(fontWeight: FontWeight.bold)),
                              numeric: true),
                          DataColumn(
                              label: Text('At-Risk Value',
                                  style:
                                      TextStyle(fontWeight: FontWeight.bold)),
                              numeric: true),
                        ],
                        rows: data.batchExpiryDetails.map((b) {
                          return DataRow(cells: [
                            DataCell(Text(b.batchNumber,
                                style: const TextStyle(
                                    fontWeight: FontWeight.w600))),
                            DataCell(Text(b.itemName)),
                            DataCell(Text(b.expiryDate != null
                                ? DateFormat('dd MMM yyyy')
                                    .format(b.expiryDate!)
                                : '—')),
                            DataCell(_ExpiryUrgencyBadge(stat: b)),
                            DataCell(
                                Text(b.remainingQuantity.toInt().toString())),
                            DataCell(Text(currency.format(b.unitPrice))),
                            DataCell(
                              Text(
                                currency.format(b.totalAmount),
                                style: const TextStyle(
                                    fontWeight: FontWeight.bold),
                              ),
                            ),
                          ]);
                        }).toList(),
                      ),
                    )
                  else
                    const _EmptyStateView(
                        title: 'No expired or near-expiry batches detected.'),
                ],
              ),
            ),
            const SizedBox(height: 20),

            // 4. Stock Movement & Fast Moving Items Section
            _CardContainer(
              title: 'Stock Movement & Consumption Trends',
              child: Column(
                crossAxisAlignment: CrossAxisAlignment.start,
                children: [
                  Row(
                    children: [
                      Expanded(
                        child: Container(
                          padding: const EdgeInsets.all(16),
                          decoration: BoxDecoration(
                            color: AppColors.primary.withValues(alpha: 0.1),
                            borderRadius: BorderRadius.circular(10),
                            border: Border.all(
                                color:
                                    AppColors.primary.withValues(alpha: 0.3)),
                          ),
                          child: Column(
                            crossAxisAlignment: CrossAxisAlignment.start,
                            children: [
                              Text('Total Stock-In (Purchases/Returns)',
                                  style: TextStyle(
                                      fontSize: 12, color: AppColors.primary)),
                              const SizedBox(height: 4),
                              Text('${data.totalStockInUnits.toInt()} Units',
                                  style: TextStyle(
                                      fontSize: 18,
                                      fontWeight: FontWeight.bold,
                                      color: AppColors.primary)),
                              Text(
                                  'Valuation: ${currency.format(data.totalStockInValue)}',
                                  style: const TextStyle(
                                      fontSize: 12, color: Colors.grey)),
                            ],
                          ),
                        ),
                      ),
                      const SizedBox(width: 16),
                      Expanded(
                        child: Container(
                          padding: const EdgeInsets.all(16),
                          decoration: BoxDecoration(
                            color: AppColors.error.withValues(alpha: 0.1),
                            borderRadius: BorderRadius.circular(10),
                            border: Border.all(
                                color: AppColors.error.withValues(alpha: 0.3)),
                          ),
                          child: Column(
                            crossAxisAlignment: CrossAxisAlignment.start,
                            children: [
                              Text('Total Stock-Out (Consumed/Dispensed)',
                                  style: TextStyle(
                                      fontSize: 12, color: AppColors.error)),
                              const SizedBox(height: 4),
                              Text('${data.totalStockOutUnits.toInt()} Units',
                                  style: TextStyle(
                                      fontSize: 18,
                                      fontWeight: FontWeight.bold,
                                      color: AppColors.error)),
                              Text(
                                  'Valuation: ${currency.format(data.totalStockOutValue)}',
                                  style: const TextStyle(
                                      fontSize: 12, color: Colors.grey)),
                            ],
                          ),
                        ),
                      ),
                    ],
                  ),
                  const SizedBox(height: 20),

                  // Fast Moving Items Leaderboard
                  const Text('Fast-Moving / High-Consumption Items',
                      style:
                          TextStyle(fontSize: 14, fontWeight: FontWeight.bold)),
                  const SizedBox(height: 10),
                  if (data.fastMovingItems.isNotEmpty)
                    SingleChildScrollView(
                      scrollDirection: Axis.horizontal,
                      child: DataTable(
                        columnSpacing: 24,
                        columns: const [
                          DataColumn(
                              label: Text('Item Name',
                                  style:
                                      TextStyle(fontWeight: FontWeight.bold))),
                          DataColumn(
                              label: Text('Category',
                                  style:
                                      TextStyle(fontWeight: FontWeight.bold))),
                          DataColumn(
                              label: Text('Units Consumed',
                                  style:
                                      TextStyle(fontWeight: FontWeight.bold)),
                              numeric: true),
                          DataColumn(
                              label: Text('Value Consumed',
                                  style:
                                      TextStyle(fontWeight: FontWeight.bold)),
                              numeric: true),
                          DataColumn(
                              label: Text('Dispense Count',
                                  style:
                                      TextStyle(fontWeight: FontWeight.bold)),
                              numeric: true),
                        ],
                        rows: data.fastMovingItems.take(10).map((f) {
                          return DataRow(cells: [
                            DataCell(Text(f.itemName,
                                style: const TextStyle(
                                    fontWeight: FontWeight.w600))),
                            DataCell(Text(f.category)),
                            DataCell(
                                Text(f.totalConsumedUnits.toInt().toString())),
                            DataCell(
                                Text(currency.format(f.totalConsumedValue))),
                            DataCell(Text('${f.transactionCount} times')),
                          ]);
                        }).toList(),
                      ),
                    )
                  else
                    const _EmptyStateView(
                        title: 'No consumption transactions in this period.'),
                  const SizedBox(height: 20),

                  // Movement Reasons Breakdown
                  const Text('Movement by Reason',
                      style:
                          TextStyle(fontSize: 14, fontWeight: FontWeight.bold)),
                  const SizedBox(height: 10),
                  if (data.movementReasons.isNotEmpty)
                    Wrap(
                      spacing: 8,
                      runSpacing: 8,
                      children: data.movementReasons.map((r) {
                        return Container(
                          padding: const EdgeInsets.symmetric(
                              horizontal: 12, vertical: 8),
                          decoration: BoxDecoration(
                            color: isDark
                                ? AppColors.surfaceContainerHigh
                                : AppColors.surfaceContainerLow,
                            borderRadius: BorderRadius.circular(8),
                            border: Border.all(
                              color: (r.isStockIn
                                      ? AppColors.primary
                                      : AppColors.error)
                                  .withValues(alpha: 0.3),
                            ),
                          ),
                          child: Column(
                            crossAxisAlignment: CrossAxisAlignment.start,
                            mainAxisSize: MainAxisSize.min,
                            children: [
                              Row(
                                mainAxisSize: MainAxisSize.min,
                                children: [
                                  Icon(
                                    r.isStockIn
                                        ? Icons.arrow_downward
                                        : Icons.arrow_upward,
                                    size: 14,
                                    color: r.isStockIn
                                        ? AppColors.primary
                                        : AppColors.error,
                                  ),
                                  const SizedBox(width: 4),
                                  Text(r.reason,
                                      style: const TextStyle(
                                          fontWeight: FontWeight.w600,
                                          fontSize: 13)),
                                ],
                              ),
                              const SizedBox(height: 2),
                              Text(
                                '${r.totalUnits.toInt()} units (${r.transactionCount} txns)',
                                style: const TextStyle(
                                    fontSize: 11, color: Colors.grey),
                              ),
                            ],
                          ),
                        );
                      }).toList(),
                    )
                  else
                    const _EmptyStateView(
                        title: 'No movement reasons recorded.'),
                ],
              ),
            ),
            const SizedBox(height: 20),

            // 5. Immutable Inventory Audit Ledger
            _CardContainer(
              title: 'Inventory Audit Ledger (Immutable)',
              child: data.auditLedger.isNotEmpty
                  ? SingleChildScrollView(
                      scrollDirection: Axis.horizontal,
                      child: DataTable(
                        columnSpacing: 18,
                        columns: const [
                          DataColumn(
                              label: Text('Date & Time',
                                  style:
                                      TextStyle(fontWeight: FontWeight.bold))),
                          DataColumn(
                              label: Text('Item Name',
                                  style:
                                      TextStyle(fontWeight: FontWeight.bold))),
                          DataColumn(
                              label: Text('Type',
                                  style:
                                      TextStyle(fontWeight: FontWeight.bold))),
                          DataColumn(
                              label: Text('Qty',
                                  style:
                                      TextStyle(fontWeight: FontWeight.bold)),
                              numeric: true),
                          DataColumn(
                              label: Text('Before → After',
                                  style:
                                      TextStyle(fontWeight: FontWeight.bold))),
                          DataColumn(
                              label: Text('Reason & Remarks',
                                  style:
                                      TextStyle(fontWeight: FontWeight.bold))),
                          DataColumn(
                              label: Text('Recipient / Vendor',
                                  style:
                                      TextStyle(fontWeight: FontWeight.bold))),
                          DataColumn(
                              label: Text('Performed By',
                                  style:
                                      TextStyle(fontWeight: FontWeight.bold))),
                        ],
                        rows: data.auditLedger.take(50).map((entry) {
                          final isIn = entry.transactionType == 'stock_in';
                          return DataRow(cells: [
                            DataCell(Text(
                                DateFormat('dd MMM yy, hh:mm a')
                                    .format(entry.date),
                                style: const TextStyle(fontSize: 12))),
                            DataCell(Text(entry.itemName,
                                style: const TextStyle(
                                    fontWeight: FontWeight.w600))),
                            DataCell(
                              Container(
                                padding: const EdgeInsets.symmetric(
                                    horizontal: 6, vertical: 2),
                                decoration: BoxDecoration(
                                  color: (isIn
                                          ? AppColors.primary
                                          : AppColors.error)
                                      .withValues(alpha: 0.15),
                                  borderRadius: BorderRadius.circular(4),
                                ),
                                child: Text(
                                  isIn ? 'Stock In' : 'Stock Out',
                                  style: TextStyle(
                                    fontSize: 11,
                                    fontWeight: FontWeight.bold,
                                    color: isIn
                                        ? AppColors.primary
                                        : AppColors.error,
                                  ),
                                ),
                              ),
                            ),
                            DataCell(Text(
                                '${isIn ? '+' : '-'}${entry.quantity.toInt()}')),
                            DataCell(
                              Text(
                                entry.stockBefore != null &&
                                        entry.stockAfter != null
                                    ? '${entry.stockBefore!.toInt()} → ${entry.stockAfter!.toInt()}'
                                    : '—',
                                style: const TextStyle(fontSize: 12),
                              ),
                            ),
                            DataCell(
                              Column(
                                crossAxisAlignment: CrossAxisAlignment.start,
                                mainAxisAlignment: MainAxisAlignment.center,
                                children: [
                                  Text(entry.reason ?? 'Unspecified',
                                      style: const TextStyle(fontSize: 12)),
                                  if (entry.remarks != null &&
                                      entry.remarks!.isNotEmpty)
                                    Text(entry.remarks!,
                                        style: const TextStyle(
                                            fontSize: 11, color: Colors.grey)),
                                ],
                              ),
                            ),
                            DataCell(Text(entry.recipientInfo ?? '—',
                                style: const TextStyle(fontSize: 12))),
                            DataCell(Text(entry.performedByName ?? 'Admin',
                                style: const TextStyle(fontSize: 12))),
                          ]);
                        }).toList(),
                      ),
                    )
                  : const _EmptyStateView(
                      title:
                          'No audit transactions found for the selected period.'),
            ),
          ],
        );
      },
    );
  }
}

// -------------------------------------------------------------
// Inventory specific helper widgets
// -------------------------------------------------------------
class _AllocationRatioBar extends StatelessWidget {
  final double centralUnits;
  final double eyeUnits;
  final double dentalUnits;

  const _AllocationRatioBar({
    required this.centralUnits,
    required this.eyeUnits,
    required this.dentalUnits,
  });

  @override
  Widget build(BuildContext context) {
    final total = centralUnits + eyeUnits + dentalUnits;
    if (total <= 0) {
      return Container(
        height: 12,
        decoration: BoxDecoration(
          color: AppColors.outlineVariant.withValues(alpha: 0.3),
          borderRadius: BorderRadius.circular(6),
        ),
      );
    }

    final centralFlex = ((centralUnits / total) * 1000).toInt();
    final eyeFlex = ((eyeUnits / total) * 1000).toInt();
    final dentalFlex = ((dentalUnits / total) * 1000).toInt();

    return ClipRRect(
      borderRadius: BorderRadius.circular(6),
      child: SizedBox(
        height: 12,
        child: Row(
          children: [
            if (centralFlex > 0)
              Expanded(
                flex: centralFlex,
                child: Container(color: AppColors.tertiary),
              ),
            if (eyeFlex > 0)
              Expanded(
                flex: eyeFlex,
                child: Container(color: AppColors.primary),
              ),
            if (dentalFlex > 0)
              Expanded(
                flex: dentalFlex,
                child: Container(color: AppColors.secondary),
              ),
          ],
        ),
      ),
    );
  }
}

class _StatusChip extends StatelessWidget {
  final String label;
  final Color color;
  final IconData icon;

  const _StatusChip({
    required this.label,
    required this.color,
    required this.icon,
  });

  @override
  Widget build(BuildContext context) {
    return Container(
      padding: const EdgeInsets.symmetric(horizontal: 10, vertical: 6),
      decoration: BoxDecoration(
        color: color.withValues(alpha: 0.12),
        borderRadius: BorderRadius.circular(8),
        border: Border.all(color: color.withValues(alpha: 0.3)),
      ),
      child: Row(
        mainAxisSize: MainAxisSize.min,
        children: [
          Icon(icon, size: 14, color: color),
          const SizedBox(width: 6),
          Text(
            label,
            style: TextStyle(
              fontSize: 12,
              fontWeight: FontWeight.bold,
              color: color,
            ),
          ),
        ],
      ),
    );
  }
}

class _LocationBadge extends StatelessWidget {
  final String location;

  const _LocationBadge({required this.location});

  @override
  Widget build(BuildContext context) {
    Color color;
    if (location.toLowerCase().contains('central')) {
      color = AppColors.tertiary;
    } else if (location.toLowerCase().contains('eye')) {
      color = AppColors.primary;
    } else {
      color = AppColors.secondary;
    }

    return Container(
      padding: const EdgeInsets.symmetric(horizontal: 8, vertical: 3),
      decoration: BoxDecoration(
        color: color.withValues(alpha: 0.12),
        borderRadius: BorderRadius.circular(6),
      ),
      child: Text(
        location,
        style:
            TextStyle(fontSize: 11, fontWeight: FontWeight.w600, color: color),
      ),
    );
  }
}

class _ExpiryRiskCard extends StatelessWidget {
  final String title;
  final int count;
  final String value;
  final Color color;

  const _ExpiryRiskCard({
    required this.title,
    required this.count,
    required this.value,
    required this.color,
  });

  @override
  Widget build(BuildContext context) {
    final isDark = Theme.of(context).brightness == Brightness.dark;
    return Container(
      padding: const EdgeInsets.all(12),
      decoration: BoxDecoration(
        color: isDark
            ? AppColors.surfaceContainerHigh
            : AppColors.surfaceContainerLowest,
        borderRadius: BorderRadius.circular(10),
        border: Border.all(color: color.withValues(alpha: 0.3)),
      ),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        mainAxisAlignment: MainAxisAlignment.center,
        children: [
          Row(
            children: [
              Container(
                  width: 8,
                  height: 8,
                  decoration:
                      BoxDecoration(color: color, shape: BoxShape.circle)),
              const SizedBox(width: 6),
              Expanded(
                child: Text(
                  title,
                  style: TextStyle(
                    fontSize: 11,
                    color: isDark
                        ? AppColors.outlineVariant
                        : AppColors.onSurfaceVariant,
                    fontWeight: FontWeight.w600,
                  ),
                  maxLines: 1,
                  overflow: TextOverflow.ellipsis,
                ),
              ),
            ],
          ),
          const SizedBox(height: 4),
          Text(
            '$count batches',
            style: TextStyle(
                fontSize: 16, fontWeight: FontWeight.bold, color: color),
          ),
          Text(
            'Valuation: $value',
            style: TextStyle(fontSize: 11, color: AppColors.outline),
          ),
        ],
      ),
    );
  }
}

class _ExpiryUrgencyBadge extends StatelessWidget {
  final BatchExpiryStat stat;

  const _ExpiryUrgencyBadge({required this.stat});

  @override
  Widget build(BuildContext context) {
    Color bg;
    Color fg;
    String label;

    if (stat.isExpired) {
      bg = AppColors.error;
      fg = Colors.white;
      final days = stat.daysRemaining != null ? stat.daysRemaining!.abs() : 0;
      label = days > 0 ? 'EXPIRED ($days d ago)' : 'EXPIRED';
    } else if (stat.urgencyStatus == '30days') {
      bg = AppColors.error;
      fg = Colors.white;
      label = '${stat.daysRemaining} days left';
    } else if (stat.urgencyStatus == '60days') {
      bg = AppColors.secondary;
      fg = Colors.white;
      label = '${stat.daysRemaining} days left';
    } else {
      bg = AppColors.primary;
      fg = Colors.white;
      label = '${stat.daysRemaining} days left';
    }

    return Container(
      padding: const EdgeInsets.symmetric(horizontal: 8, vertical: 3),
      decoration: BoxDecoration(
        color: bg,
        borderRadius: BorderRadius.circular(4),
      ),
      child: Text(
        label,
        style: TextStyle(color: fg, fontSize: 10, fontWeight: FontWeight.bold),
      ),
    );
  }
}

// ==========================================
// SHARED HELPER WIDGETS
// ==========================================
class _CardContainer extends StatelessWidget {
  final String title;
  final Widget child;

  const _CardContainer({
    required this.title,
    required this.child,
  });

  @override
  Widget build(BuildContext context) {
    final isDark = Theme.of(context).brightness == Brightness.dark;
    return Container(
      width: double.infinity,
      padding: const EdgeInsets.all(20),
      decoration: BoxDecoration(
        color: isDark
            ? AppColors.surfaceContainerHigh
            : AppColors.surfaceContainerLowest,
        borderRadius: BorderRadius.circular(16),
        border: Border.all(
          color: isDark
              ? AppColors.outlineVariant.withValues(alpha: 0.5)
              : AppColors.outlineVariant,
        ),
        boxShadow: [
          BoxShadow(
            color: Colors.black.withValues(alpha: isDark ? 0.2 : 0.03),
            blurRadius: 10,
            offset: const Offset(0, 4),
          ),
        ],
      ),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Text(
            title,
            style: TextStyle(
              fontSize: 16,
              fontWeight: FontWeight.w700,
              color: isDark ? AppColors.onSurface : AppColors.onSurface,
            ),
          ),
          const SizedBox(height: 16),
          child,
        ],
      ),
    );
  }
}

class _MiniSummary extends StatelessWidget {
  final String label;
  final String value;
  final Color color;

  const _MiniSummary({
    required this.label,
    required this.value,
    required this.color,
  });

  @override
  Widget build(BuildContext context) {
    final isDark = Theme.of(context).brightness == Brightness.dark;
    return Column(
      children: [
        Text(
          value,
          style: TextStyle(
            fontSize: 16,
            fontWeight: FontWeight.bold,
            color: color,
          ),
        ),
        const SizedBox(height: 2),
        Text(
          label,
          style: TextStyle(
            fontSize: 11,
            color:
                isDark ? AppColors.outlineVariant : AppColors.onSurfaceVariant,
          ),
        ),
      ],
    );
  }
}

class _DepartmentBadge extends StatelessWidget {
  final String department;

  const _DepartmentBadge({required this.department});

  @override
  Widget build(BuildContext context) {
    final isEye = department.toLowerCase() == 'eye';
    final bg = isEye
        ? AppColors.primary.withValues(alpha: 0.12)
        : AppColors.secondary.withValues(alpha: 0.12);
    final text = isEye ? AppColors.primary : AppColors.secondary;

    return Container(
      padding: const EdgeInsets.symmetric(horizontal: 8, vertical: 4),
      decoration: BoxDecoration(
        color: bg,
        borderRadius: BorderRadius.circular(6),
      ),
      child: Text(
        isEye ? 'Eye Clinic' : 'Dental Clinic',
        style: TextStyle(
          fontSize: 12,
          fontWeight: FontWeight.w600,
          color: text,
        ),
      ),
    );
  }
}

class _LoadingView extends StatelessWidget {
  final String message;
  const _LoadingView({required this.message});

  @override
  Widget build(BuildContext context) {
    return Center(
      child: Padding(
        padding: const EdgeInsets.all(40),
        child: Column(
          children: [
            CircularProgressIndicator(color: AppColors.primary),
            const SizedBox(height: 16),
            Text(message, style: TextStyle(color: AppColors.outline)),
          ],
        ),
      ),
    );
  }
}

class _ErrorView extends StatelessWidget {
  final String message;
  const _ErrorView({required this.message});

  @override
  Widget build(BuildContext context) {
    return Container(
      padding: const EdgeInsets.all(20),
      decoration: BoxDecoration(
        color: AppColors.errorContainer.withValues(alpha: 0.5),
        borderRadius: BorderRadius.circular(12),
        border: Border.all(color: AppColors.error.withValues(alpha: 0.3)),
      ),
      child: Row(
        children: [
          Icon(Icons.error_outline, color: AppColors.error),
          const SizedBox(width: 12),
          Expanded(
            child: Text(
              'Error loading analytics: $message',
              style: TextStyle(color: AppColors.error),
            ),
          ),
        ],
      ),
    );
  }
}

class _EmptyStateView extends StatelessWidget {
  final String title;
  const _EmptyStateView({required this.title});

  @override
  Widget build(BuildContext context) {
    return Center(
      child: Padding(
        padding: const EdgeInsets.symmetric(vertical: 24),
        child: Column(
          mainAxisSize: MainAxisSize.min,
          children: [
            Icon(Icons.bar_chart_rounded, size: 40, color: AppColors.outline),
            const SizedBox(height: 8),
            Text(
              title,
              style: TextStyle(color: AppColors.outline, fontSize: 13),
              textAlign: TextAlign.center,
            ),
          ],
        ),
      ),
    );
  }
}
