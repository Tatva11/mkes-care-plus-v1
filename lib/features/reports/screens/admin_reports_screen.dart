import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:intl/intl.dart';

import '../models/reports_filter_model.dart';
import '../providers/reports_provider.dart';
import '../widgets/reports_chart_painters.dart';
import '../widgets/reports_filter_toolbar.dart';
import '../widgets/reports_metric_card.dart';

class AdminReportsScreen extends ConsumerWidget {
  const AdminReportsScreen({super.key});

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    final activeSection = ref.watch(adminReportsSectionProvider);
    final isDark = Theme.of(context).brightness == Brightness.dark;

    return Scaffold(
      backgroundColor: isDark ? const Color(0xFF0F172A) : const Color(0xFFF8FAFC),
      appBar: AppBar(
        title: const Column(
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            Text(
              'Reports & Analytics',
              style: TextStyle(fontWeight: FontWeight.w700, fontSize: 18),
            ),
            Text(
              'Clinic-wide insights & performance overview',
              style: TextStyle(fontSize: 12, fontWeight: FontWeight.normal),
            ),
          ],
        ),
        backgroundColor: isDark ? const Color(0xFF1E293B) : Colors.white,
        foregroundColor: isDark ? Colors.white : const Color(0xFF0F172A),
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
            },
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
    final currency = NumberFormat.currency(locale: 'en_IN', symbol: '₹', decimalDigits: 0);

    return asyncData.when(
      loading: () => const _LoadingView(message: 'Loading clinic overview analytics...'),
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
                      subtitle: '${data.newPatients} registered in selected period',
                      icon: Icons.people_alt_outlined,
                      iconColor: const Color(0xFF0D9488),
                    ),
                    ReportsMetricCard(
                      title: 'Total Appointments',
                      value: data.totalAppointments.toString(),
                      subtitle: '${data.completedAppointments} successfully completed',
                      icon: Icons.calendar_month_outlined,
                      iconColor: const Color(0xFF3B82F6),
                    ),
                    ReportsMetricCard(
                      title: 'Procedures & Services',
                      value: data.totalProcedures.toString(),
                      subtitle: 'Eye: ${data.eyeProcedures} • Dental: ${data.dentalProcedures}',
                      icon: Icons.medical_services_outlined,
                      iconColor: const Color(0xFF8B5CF6),
                    ),
                    ReportsMetricCard(
                      title: 'Total Invoiced Sales',
                      value: currency.format(data.totalSales),
                      subtitle: 'Revenue: ${currency.format(data.totalRevenue)}',
                      icon: Icons.account_balance_wallet_outlined,
                      iconColor: const Color(0xFF10B981),
                    ),
                  ],
                );
              },
            ),
            const SizedBox(height: 20),

            // Department Ratio
            _CardContainer(
              title: 'Department Distribution Snapshot',
              child: Column(
                children: [
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
                        color: const Color(0xFF0D9488),
                      ),
                      _MiniSummary(
                        label: 'Dental Appointments',
                        value: data.dentalAppointments.toString(),
                        color: const Color(0xFF6366F1),
                      ),
                      _MiniSummary(
                        label: 'Eye Invoiced',
                        value: currency.format(data.eyeSales),
                        color: const Color(0xFF0D9488),
                      ),
                      _MiniSummary(
                        label: 'Dental Invoiced',
                        value: currency.format(data.dentalSales),
                        color: const Color(0xFF6366F1),
                      ),
                    ],
                  ),
                ],
              ),
            ),
            const SizedBox(height: 20),

            // Trend Chart
            if (data.trendPoints.isNotEmpty)
              _CardContainer(
                title: 'Clinical Activity & Sales Trend',
                child: ReportsLineChart(
                  primaryLabel: 'Procedures Count',
                  secondaryLabel: 'Invoiced Sales (₹)',
                  primaryColor: const Color(0xFF0D9488),
                  secondaryColor: const Color(0xFF10B981),
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
              const _EmptyStateView(title: 'No activity data available for the selected period.'),
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
                      iconColor: const Color(0xFF0D9488),
                    ),
                    ReportsMetricCard(
                      title: 'New Patients in Period',
                      value: data.newPatients.toString(),
                      icon: Icons.person_add_alt_1_outlined,
                      iconColor: const Color(0xFF10B981),
                    ),
                    ReportsMetricCard(
                      title: 'Returning Patients',
                      value: data.returningPatients.toString(),
                      subtitle: 'Patients with >1 appointment',
                      icon: Icons.repeat_rounded,
                      iconColor: const Color(0xFF6366F1),
                    ),
                    ReportsMetricCard(
                      title: 'Department Breakdown',
                      value: '${data.eyePatients} Eye / ${data.dentalPatients} Dental',
                      icon: Icons.pie_chart_outline_rounded,
                      iconColor: const Color(0xFFF59E0B),
                    ),
                  ],
                );
              },
            ),
            const SizedBox(height: 20),

            // Registration Trends Chart
            _CardContainer(
              title: 'Patient Registration Trend',
              child: data.registrationTrends.isNotEmpty
                  ? ReportsLineChart(
                      primaryLabel: 'Registrations',
                      primaryColor: const Color(0xFF0D9488),
                      data: data.registrationTrends.map((p) {
                        return ChartDataPoint(
                          label: p.label,
                          value: p.count.toDouble(),
                        );
                      }).toList(),
                    )
                  : const _EmptyStateView(title: 'No new registrations in this period.'),
            ),
            const SizedBox(height: 20),

            // Donut & Ratio
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
                        color: const Color(0xFF0D9488),
                      ),
                      DonutSegment(
                        label: 'Dental Clinic',
                        value: data.dentalPatients.toDouble(),
                        color: const Color(0xFF6366F1),
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
            ),
            const SizedBox(height: 20),

            // Recent Registrations Table
            _CardContainer(
              title: 'Recent Patient Registrations',
              child: data.recentPatients.isNotEmpty
                  ? SingleChildScrollView(
                      scrollDirection: Axis.horizontal,
                      child: DataTable(
                        headingRowColor: WidgetStateProperty.all(
                          isDark ? const Color(0xFF0F172A) : const Color(0xFFF1F5F9),
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
                              style: const TextStyle(fontWeight: FontWeight.w600),
                            )),
                            DataCell(Text(p.name)),
                            DataCell(_DepartmentBadge(department: p.department ?? 'eye')),
                            DataCell(Text(p.mobile ?? '-')),
                            DataCell(Text(DateFormat('dd MMM yyyy, hh:mm a').format(p.createdAt))),
                          ]);
                        }).toList(),
                      ),
                    )
                  : const _EmptyStateView(title: 'No patient registrations found in this range.'),
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
      loading: () => const _LoadingView(message: 'Loading appointment analytics...'),
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
                      iconColor: const Color(0xFF3B82F6),
                    ),
                    ReportsMetricCard(
                      title: 'Completed Appointments',
                      value: data.completedAppointments.toString(),
                      subtitle: '${data.completionRate.toStringAsFixed(1)}% completion rate',
                      icon: Icons.check_circle_outline_rounded,
                      iconColor: const Color(0xFF10B981),
                    ),
                    ReportsMetricCard(
                      title: 'Cancelled / Missed',
                      value: data.cancelledAppointments.toString(),
                      subtitle: '${data.cancellationRate.toStringAsFixed(1)}% cancellation rate',
                      icon: Icons.cancel_outlined,
                      iconColor: const Color(0xFFEF4444),
                    ),
                    ReportsMetricCard(
                      title: 'Scheduled / Waiting',
                      value: (data.scheduledAppointments + data.inTriageAppointments).toString(),
                      subtitle: '${data.scheduledAppointments} scheduled • ${data.inTriageAppointments} in triage',
                      icon: Icons.hourglass_top_rounded,
                      iconColor: const Color(0xFFF59E0B),
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
                      primaryColor: const Color(0xFF3B82F6),
                      secondaryColor: const Color(0xFF10B981),
                      data: data.appointmentTrends.map((p) {
                        return ChartDataPoint(
                          label: p.label,
                          value: p.total.toDouble(),
                          secondaryValue: p.completed.toDouble(),
                        );
                      }).toList(),
                    )
                  : const _EmptyStateView(title: 'No appointments recorded in this range.'),
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
                          color: const Color(0xFF3B82F6),
                        ),
                        DonutSegment(
                          label: 'Walk-in',
                          value: data.walkInAppointments.toDouble(),
                          color: const Color(0xFFF59E0B),
                        ),
                        DonutSegment(
                          label: 'Follow-up',
                          value: data.followUpAppointments.toDouble(),
                          color: const Color(0xFF10B981),
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
                          isDark ? const Color(0xFF0F172A) : const Color(0xFFF1F5F9),
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
                              style: const TextStyle(fontWeight: FontWeight.w600),
                            )),
                            DataCell(_DepartmentBadge(department: doc.department)),
                            DataCell(Text(doc.totalAppointments.toString())),
                            DataCell(Text(
                              doc.completedAppointments.toString(),
                              style: const TextStyle(color: Color(0xFF10B981), fontWeight: FontWeight.w600),
                            )),
                            DataCell(Text(
                              doc.cancelledAppointments.toString(),
                              style: TextStyle(
                                color: doc.cancelledAppointments > 0 ? const Color(0xFFEF4444) : Colors.grey,
                              ),
                            )),
                            DataCell(
                              Row(
                                children: [
                                  SizedBox(
                                    width: 60,
                                    child: LinearProgressIndicator(
                                      value: doc.completionRate / 100,
                                      backgroundColor: isDark ? const Color(0xFF334155) : const Color(0xFFE2E8F0),
                                      valueColor: const AlwaysStoppedAnimation(Color(0xFF10B981)),
                                      borderRadius: BorderRadius.circular(4),
                                    ),
                                  ),
                                  const SizedBox(width: 8),
                                  Text('${doc.completionRate.toStringAsFixed(1)}%'),
                                ],
                              ),
                            ),
                          ]);
                        }).toList(),
                      ),
                    )
                  : const _EmptyStateView(title: 'No doctor appointment data recorded.'),
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
      loading: () => const _LoadingView(message: 'Loading staff & attendance reports...'),
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
                      iconColor: const Color(0xFF6366F1),
                    ),
                    ReportsMetricCard(
                      title: 'Attendance Rate',
                      value: '${data.overallAttendanceRate.toStringAsFixed(1)}%',
                      subtitle: '${data.presentCount} present • ${data.lateCount} late • ${data.leaveCount} leave',
                      icon: Icons.how_to_reg_outlined,
                      iconColor: const Color(0xFF0D9488),
                    ),
                    ReportsMetricCard(
                      title: 'Task Completion Rate',
                      value: '${data.taskCompletionRate.toStringAsFixed(1)}%',
                      subtitle: '${data.completedTasks} of ${data.totalTasks} tasks completed',
                      icon: Icons.task_alt_rounded,
                      iconColor: const Color(0xFF10B981),
                    ),
                    ReportsMetricCard(
                      title: 'Overdue Tasks',
                      value: data.overdueTasks.toString(),
                      subtitle: '${data.pendingTasks} pending tasks',
                      icon: Icons.warning_amber_rounded,
                      iconColor: data.overdueTasks > 0 ? const Color(0xFFEF4444) : const Color(0xFF10B981),
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
                      primaryColor: const Color(0xFF0D9488),
                      secondaryColor: const Color(0xFFF59E0B),
                      data: data.attendanceTrends.map((p) {
                        return ChartDataPoint(
                          label: p.label,
                          value: p.present.toDouble(),
                          secondaryValue: (p.late + p.leave).toDouble(),
                        );
                      }).toList(),
                    )
                  : const _EmptyStateView(title: 'No attendance logs recorded in this range.'),
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
                          isDark ? const Color(0xFF0F172A) : const Color(0xFFF1F5F9),
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
                              style: const TextStyle(fontWeight: FontWeight.w600),
                            )),
                            DataCell(Text(st.designation ?? '-')),
                            DataCell(Text(st.presentDays.toString())),
                            DataCell(Text(
                              st.lateDays.toString(),
                              style: TextStyle(
                                color: st.lateDays > 0 ? const Color(0xFFF59E0B) : Colors.grey,
                              ),
                            )),
                            DataCell(Text(
                              st.leaveDays.toString(),
                              style: TextStyle(
                                color: st.leaveDays > 0 ? const Color(0xFFEF4444) : Colors.grey,
                              ),
                            )),
                            DataCell(Text(
                              '${st.attendancePercentage.toStringAsFixed(0)}%',
                              style: const TextStyle(fontWeight: FontWeight.w600),
                            )),
                            DataCell(Text(st.totalTasks.toString())),
                            DataCell(Text(
                              st.completedTasks.toString(),
                              style: const TextStyle(color: Color(0xFF10B981), fontWeight: FontWeight.w600),
                            )),
                            DataCell(Text(
                              st.overdueTasks.toString(),
                              style: TextStyle(
                                color: st.overdueTasks > 0 ? const Color(0xFFEF4444) : Colors.grey,
                              ),
                            )),
                            DataCell(
                              Row(
                                children: [
                                  SizedBox(
                                    width: 50,
                                    child: LinearProgressIndicator(
                                      value: st.taskCompletionPercentage / 100,
                                      backgroundColor: isDark ? const Color(0xFF334155) : const Color(0xFFE2E8F0),
                                      valueColor: const AlwaysStoppedAnimation(Color(0xFF10B981)),
                                      borderRadius: BorderRadius.circular(4),
                                    ),
                                  ),
                                  const SizedBox(width: 8),
                                  Text('${st.taskCompletionPercentage.toStringAsFixed(0)}%'),
                                ],
                              ),
                            ),
                          ]);
                        }).toList(),
                      ),
                    )
                  : const _EmptyStateView(title: 'No staff performance data available.'),
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
    final currency = NumberFormat.currency(locale: 'en_IN', symbol: '₹', decimalDigits: 0);
    final isDark = Theme.of(context).brightness == Brightness.dark;

    return asyncData.when(
      loading: () => const _LoadingView(message: 'Loading clinical & procedure analytics...'),
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
                      title: 'Total Procedures Performed',
                      value: data.totalProcedures.toString(),
                      icon: Icons.medical_services_outlined,
                      iconColor: const Color(0xFF8B5CF6),
                    ),
                    ReportsMetricCard(
                      title: 'Eye Care Procedures',
                      value: data.eyeProcedures.toString(),
                      subtitle: '${data.eyePercentage.toStringAsFixed(1)}% of all clinical activity',
                      icon: Icons.remove_red_eye_outlined,
                      iconColor: const Color(0xFF0D9488),
                    ),
                    ReportsMetricCard(
                      title: 'Dental Care Procedures',
                      value: data.dentalProcedures.toString(),
                      subtitle: '${data.dentalPercentage.toStringAsFixed(1)}% of all clinical activity',
                      icon: Icons.health_and_safety_outlined,
                      iconColor: const Color(0xFF6366F1),
                    ),
                    ReportsMetricCard(
                      title: 'Total Clinical Value',
                      value: currency.format(data.totalProceduresValue),
                      subtitle: 'Direct billed services revenue',
                      icon: Icons.payments_outlined,
                      iconColor: const Color(0xFF10B981),
                    ),
                  ],
                );
              },
            ),
            const SizedBox(height: 20),

            // Procedure Trends
            _CardContainer(
              title: 'Procedure Frequency Trends',
              child: data.procedureTrends.isNotEmpty
                  ? ReportsLineChart(
                      primaryLabel: 'Eye Procedures',
                      secondaryLabel: 'Dental Procedures',
                      primaryColor: const Color(0xFF0D9488),
                      secondaryColor: const Color(0xFF6366F1),
                      data: data.procedureTrends.map((p) {
                        return ChartDataPoint(
                          label: p.label,
                          value: p.eyeCount.toDouble(),
                          secondaryValue: p.dentalCount.toDouble(),
                        );
                      }).toList(),
                    )
                  : const _EmptyStateView(title: 'No procedures recorded for this period.'),
            ),
            const SizedBox(height: 20),

            // Top Procedures Leaderboard Table
            _CardContainer(
              title: 'Most Frequently Performed Procedures',
              child: data.topProcedures.isNotEmpty
                  ? SingleChildScrollView(
                      scrollDirection: Axis.horizontal,
                      child: DataTable(
                        headingRowColor: WidgetStateProperty.all(
                          isDark ? const Color(0xFF0F172A) : const Color(0xFFF1F5F9),
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
                                color: rank <= 3 ? const Color(0xFF0D9488) : null,
                              ),
                            )),
                            DataCell(Text(
                              proc.procedureName,
                              style: const TextStyle(fontWeight: FontWeight.w600),
                            )),
                            DataCell(_DepartmentBadge(department: proc.department)),
                            DataCell(Text(
                              proc.count.toString(),
                              style: const TextStyle(fontWeight: FontWeight.bold),
                            )),
                            DataCell(Text(currency.format(proc.averagePrice))),
                            DataCell(Text(
                              currency.format(proc.totalRevenue),
                              style: const TextStyle(
                                fontWeight: FontWeight.w600,
                                color: Color(0xFF10B981),
                              ),
                            )),
                          ]);
                        }).toList(),
                      ),
                    )
                  : const _EmptyStateView(title: 'No clinical procedure data available.'),
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
    final currency = NumberFormat.currency(locale: 'en_IN', symbol: '₹', decimalDigits: 0);
    final isDark = Theme.of(context).brightness == Brightness.dark;

    return asyncData.when(
      loading: () => const _LoadingView(message: 'Loading financial summary...'),
      error: (err, _) => _ErrorView(message: err.toString()),
      data: (data) {
        final departmentSummaries = [data.eyeSummary, data.dentalSummary];

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
                      iconColor: const Color(0xFF0D9488),
                    ),
                    ReportsMetricCard(
                      title: 'Revenue Collected',
                      value: currency.format(data.totalRevenue),
                      subtitle: '${data.collectionRate.toStringAsFixed(1)}% collected',
                      icon: Icons.payments_outlined,
                      iconColor: const Color(0xFF10B981),
                    ),
                    ReportsMetricCard(
                      title: 'Outstanding Balance',
                      value: currency.format(data.totalOutstanding),
                      subtitle: '${data.partiallyPaidInvoicesCount} partially paid',
                      icon: Icons.account_balance_wallet_outlined,
                      iconColor: data.totalOutstanding > 0
                          ? const Color(0xFFF59E0B)
                          : const Color(0xFF10B981),
                    ),
                    ReportsMetricCard(
                      title: 'Estimated Profit',
                      value: currency.format(data.estimatedProfit),
                      subtitle: 'Standard 70% estimated margin',
                      icon: Icons.trending_up_rounded,
                      iconColor: const Color(0xFF6366F1),
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
                      primaryColor: const Color(0xFF0D9488),
                      secondaryColor: const Color(0xFF10B981),
                      data: data.periodicBuckets.reversed.map((p) {
                        return ChartDataPoint(
                          label: p.periodLabel,
                          value: p.totalSales,
                          secondaryValue: p.revenueCollected,
                        );
                      }).toList(),
                    )
                  : const _EmptyStateView(title: 'No billing records in this range.'),
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
                            col = const Color(0xFF10B981);
                            break;
                          case 'upi':
                            col = const Color(0xFF6366F1);
                            break;
                          case 'bank_transfer':
                            col = const Color(0xFF3B82F6);
                            break;
                          default:
                            col = const Color(0xFFF59E0B);
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
              title: 'Department-Wise Financial Summary',
              child: departmentSummaries.isNotEmpty
                  ? SingleChildScrollView(
                      scrollDirection: Axis.horizontal,
                      child: DataTable(
                        headingRowColor: WidgetStateProperty.all(
                          isDark ? const Color(0xFF0F172A) : const Color(0xFFF1F5F9),
                        ),
                        columns: const [
                          DataColumn(label: Text('Department')),
                          DataColumn(label: Text('Invoices')),
                          DataColumn(label: Text('Total Sales')),
                          DataColumn(label: Text('Revenue Collected')),
                          DataColumn(label: Text('Outstanding')),
                          DataColumn(label: Text('Share %')),
                        ],
                        rows: departmentSummaries.map((dept) {
                          return DataRow(cells: [
                            DataCell(_DepartmentBadge(department: dept.department)),
                            DataCell(Text(dept.invoiceCount.toString())),
                            DataCell(Text(
                              currency.format(dept.totalSales),
                              style: const TextStyle(fontWeight: FontWeight.w600),
                            )),
                            DataCell(Text(
                              currency.format(dept.revenueCollected),
                              style: const TextStyle(color: Color(0xFF10B981), fontWeight: FontWeight.w600),
                            )),
                            DataCell(Text(
                              currency.format(dept.outstandingBalance),
                              style: TextStyle(
                                color: dept.outstandingBalance > 0 ? const Color(0xFFEF4444) : Colors.grey,
                              ),
                            )),
                            DataCell(
                              Row(
                                children: [
                                  SizedBox(
                                    width: 50,
                                    child: LinearProgressIndicator(
                                      value: dept.sharePercentage / 100,
                                      backgroundColor: isDark ? const Color(0xFF334155) : const Color(0xFFE2E8F0),
                                      valueColor: const AlwaysStoppedAnimation(Color(0xFF10B981)),
                                      borderRadius: BorderRadius.circular(4),
                                    ),
                                  ),
                                  const SizedBox(width: 8),
                                  Text('${dept.sharePercentage.toStringAsFixed(1)}%'),
                                ],
                              ),
                            ),
                          ]);
                        }).toList(),
                      ),
                    )
                  : const _EmptyStateView(title: 'No department financials available.'),
            ),
          ],
        );
      },
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
        color: isDark ? const Color(0xFF1E293B) : Colors.white,
        borderRadius: BorderRadius.circular(16),
        border: Border.all(
          color: isDark ? const Color(0xFF334155) : const Color(0xFFE2E8F0),
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
              color: isDark ? Colors.white : const Color(0xFF0F172A),
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
            color: isDark ? const Color(0xFF94A3B8) : const Color(0xFF64748B),
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
        ? const Color(0xFF0D9488).withValues(alpha: 0.12)
        : const Color(0xFF6366F1).withValues(alpha: 0.12);
    final text = isEye ? const Color(0xFF0D9488) : const Color(0xFF6366F1);

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
            const CircularProgressIndicator(color: Color(0xFF0D9488)),
            const SizedBox(height: 16),
            Text(message, style: const TextStyle(color: Colors.grey)),
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
        color: const Color(0xFFEF4444).withValues(alpha: 0.1),
        borderRadius: BorderRadius.circular(12),
        border: Border.all(color: const Color(0xFFEF4444).withValues(alpha: 0.3)),
      ),
      child: Row(
        children: [
          const Icon(Icons.error_outline, color: Color(0xFFEF4444)),
          const SizedBox(width: 12),
          Expanded(
            child: Text(
              'Error loading analytics: $message',
              style: const TextStyle(color: Color(0xFFEF4444)),
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
            const Icon(Icons.bar_chart_rounded, size: 40, color: Colors.grey),
            const SizedBox(height: 8),
            Text(
              title,
              style: const TextStyle(color: Colors.grey, fontSize: 13),
              textAlign: TextAlign.center,
            ),
          ],
        ),
      ),
    );
  }
}
