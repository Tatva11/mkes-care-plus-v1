import 'dart:convert';
import 'package:flutter/foundation.dart';
import 'package:intl/intl.dart';
import 'package:supabase_flutter/supabase_flutter.dart';
import 'package:url_launcher/url_launcher.dart';

import '../../billing/models/billing_reports_model.dart';
import '../models/appointment_reports_model.dart';
import '../models/clinical_reports_model.dart';
import '../models/inventory_reports_model.dart';
import '../models/overview_reports_model.dart';
import '../models/patient_reports_model.dart';
import '../models/reports_filter_model.dart';
import '../models/staff_reports_model.dart';
import 'excel_workbook_builder.dart';
import 'excel_workbook_schema.dart';

/// Result object for an Excel report export operation.
class ExportReportResult {
  final bool success;
  final String fileName;
  final int fileSizeBytes;
  final String? signedUrl;
  final bool launched;
  final String? errorMessage;

  const ExportReportResult({
    required this.success,
    required this.fileName,
    this.fileSizeBytes = 0,
    this.signedUrl,
    this.launched = false,
    this.errorMessage,
  });

  String get formattedSize {
    if (fileSizeBytes <= 0) return '0 KB';
    final kb = fileSizeBytes / 1024;
    if (kb < 1024) return '${kb.toStringAsFixed(1)} KB';
    final mb = kb / 1024;
    return '${mb.toStringAsFixed(2)} MB';
  }
}

/// Service providing export capabilities (Standalone OpenXML .xlsx, CSV & HTML)
/// for MKES CARE+ Admin Reports with full support for Android downloading.
class ReportsExportService {
  static final NumberFormat _currencyFormat =
      NumberFormat.currency(locale: 'en_IN', symbol: '₹', decimalDigits: 2);
  static final DateFormat _dateFormat = DateFormat('dd-MM-yyyy hh:mm a');
  static final DateFormat _shortDateFormat = DateFormat('dd-MM-yyyy');

  static const String storageBucket = 'clinic-excel-sync';

  // ── 1. STANDALONE OPENXML (.XLSX) BUILDERS BY SECTION ───────────────────────

  /// Generates a standalone .xlsx workbook containing Overview metrics & activity trends.
  static Uint8List generateOverviewReportWorkbook(
    OverviewReportsData data, [
    AdminReportsFilter filter = const AdminReportsFilter(),
  ]) {
    final builder = ExcelWorkbookBuilder();

    final metricsSheet = ExcelWorksheetSpec(
      name: 'Overview_Metrics',
      sourceTable: 'overview_metrics',
      stableIdKey: 'metric',
      timestampKey: 'timestamp',
      description: 'Key performance indicators and operational health summary',
      columns: const [
        ExcelColumnSpec(header: 'Category', sourceField: 'category', width: 22),
        ExcelColumnSpec(header: 'Metric', sourceField: 'metric', width: 34),
        ExcelColumnSpec(header: 'Value', sourceField: 'value', width: 24),
      ],
    );

    final trendsSheet = ExcelWorksheetSpec(
      name: 'Activity_Trends',
      sourceTable: 'activity_trends',
      stableIdKey: 'date',
      timestampKey: 'date',
      description: 'Periodic patient, appointment, procedure, and sales trends',
      columns: const [
        ExcelColumnSpec(header: 'Date', sourceField: 'date', width: 14, type: ExcelColumnType.date),
        ExcelColumnSpec(header: 'Period Label', sourceField: 'label', width: 18),
        ExcelColumnSpec(header: 'New Patients', sourceField: 'patients', width: 14, type: ExcelColumnType.number),
        ExcelColumnSpec(header: 'Appointments', sourceField: 'appointments', width: 14, type: ExcelColumnType.number),
        ExcelColumnSpec(header: 'Procedures', sourceField: 'procedures', width: 14, type: ExcelColumnType.number),
        ExcelColumnSpec(header: 'Sales Amount (INR)', sourceField: 'sales', width: 18, type: ExcelColumnType.currency),
      ],
    );

    final metricsRows = <Map<String, dynamic>>[
      {'category': 'Patient Activity', 'metric': 'Total Registered Patients', 'value': data.totalPatients.toString()},
      {'category': 'Patient Activity', 'metric': 'New Registrations in Period', 'value': data.newPatients.toString()},
      {'category': 'Patient Activity', 'metric': 'Eye Clinic Patients', 'value': '${data.eyePatients} (${data.eyePercentage.toStringAsFixed(1)}%)'},
      {'category': 'Patient Activity', 'metric': 'Dental Clinic Patients', 'value': '${data.dentalPatients} (${data.dentalPercentage.toStringAsFixed(1)}%)'},
      {'category': 'Appointments', 'metric': 'Total Appointments', 'value': data.totalAppointments.toString()},
      {'category': 'Appointments', 'metric': 'Completed Appointments', 'value': data.completedAppointments.toString()},
      {'category': 'Appointments', 'metric': 'Eye Appointments', 'value': data.eyeAppointments.toString()},
      {'category': 'Appointments', 'metric': 'Dental Appointments', 'value': data.dentalAppointments.toString()},
      {'category': 'Clinical Procedures', 'metric': 'Total Procedures', 'value': data.totalProcedures.toString()},
      {'category': 'Clinical Procedures', 'metric': 'Eye Procedures', 'value': data.eyeProcedures.toString()},
      {'category': 'Clinical Procedures', 'metric': 'Dental Procedures', 'value': data.dentalProcedures.toString()},
      {'category': 'Financial Sales', 'metric': 'Total Invoiced Sales', 'value': _currencyFormat.format(data.totalSales)},
      {'category': 'Financial Sales', 'metric': 'Revenue Collected', 'value': _currencyFormat.format(data.totalRevenue)},
      {'category': 'Financial Sales', 'metric': 'Outstanding Balance', 'value': _currencyFormat.format(data.totalOutstanding)},
      {'category': 'Financial Sales', 'metric': 'Eye Department Sales', 'value': _currencyFormat.format(data.eyeSales)},
      {'category': 'Financial Sales', 'metric': 'Dental Department Sales', 'value': _currencyFormat.format(data.dentalSales)},
      {'category': 'Inventory & Stock', 'metric': 'Total Stock Valuation', 'value': _currencyFormat.format(data.totalInventoryValuation)},
      {'category': 'Inventory & Stock', 'metric': 'Low Stock Alert Items', 'value': data.lowStockCount.toString()},
      {'category': 'Inventory & Stock', 'metric': 'Expired Batches', 'value': data.expiredBatchesCount.toString()},
    ];

    final trendsRows = data.trendPoints.map((p) => {
      'date': p.date,
      'label': p.label,
      'patients': p.patientCount,
      'appointments': p.appointmentCount,
      'procedures': p.procedureCount,
      'sales': p.salesAmount,
    }).toList();

    return builder.buildCustomWorkbook(
      worksheets: [metricsSheet, trendsSheet],
      recordsByWorksheet: {
        'Overview_Metrics': metricsRows,
        'Activity_Trends': trendsRows,
      },
    );
  }

  /// Generates a standalone .xlsx workbook containing Patients registry & summary.
  static Uint8List generatePatientsReportWorkbook(
    PatientReportsData data, [
    AdminReportsFilter filter = const AdminReportsFilter(),
  ]) {
    final builder = ExcelWorkbookBuilder();

    final registrySheet = ExcelWorksheetSpec(
      name: 'Patients_Registry',
      sourceTable: 'patients',
      stableIdKey: 'id',
      timestampKey: 'created_at',
      description: 'Patient records matching active date and department filters',
      columns: const [
        ExcelColumnSpec(header: 'Patient ID', sourceField: 'id', width: 36),
        ExcelColumnSpec(header: 'Patient Number', sourceField: 'patient_number', width: 18),
        ExcelColumnSpec(header: 'Full Name', sourceField: 'name', width: 26),
        ExcelColumnSpec(header: 'Contact Mobile', sourceField: 'mobile', width: 16),
        ExcelColumnSpec(header: 'Date of Birth', sourceField: 'dob', width: 14, type: ExcelColumnType.date),
        ExcelColumnSpec(header: 'Department', sourceField: 'department', width: 14),
        ExcelColumnSpec(header: 'Address', sourceField: 'address', width: 30),
        ExcelColumnSpec(header: 'Reference Source', sourceField: 'reference', width: 20),
        ExcelColumnSpec(header: 'First Visit Date', sourceField: 'visit_date', width: 16, type: ExcelColumnType.date),
        ExcelColumnSpec(header: 'Created At', sourceField: 'created_at', width: 18, type: ExcelColumnType.datetime),
      ],
    );

    final summarySheet = ExcelWorksheetSpec(
      name: 'Patient_Summary',
      sourceTable: 'patient_summary',
      stableIdKey: 'metric',
      timestampKey: 'metric',
      description: 'Aggregated patient counts and department distribution',
      columns: const [
        ExcelColumnSpec(header: 'Metric', sourceField: 'metric', width: 32),
        ExcelColumnSpec(header: 'Count', sourceField: 'count', width: 16),
        ExcelColumnSpec(header: 'Share Percentage', sourceField: 'percentage', width: 18),
      ],
    );

    final trendsSheet = ExcelWorksheetSpec(
      name: 'Registration_Trends',
      sourceTable: 'registration_trends',
      stableIdKey: 'date',
      timestampKey: 'date',
      description: 'Daily registration volume over the selected reporting period',
      columns: const [
        ExcelColumnSpec(header: 'Date', sourceField: 'date', width: 14, type: ExcelColumnType.date),
        ExcelColumnSpec(header: 'Period Label', sourceField: 'label', width: 18),
        ExcelColumnSpec(header: 'New Registrations', sourceField: 'count', width: 18, type: ExcelColumnType.number),
      ],
    );

    final registryRows = data.recentPatients.map((p) => {
      'id': p.id,
      'patient_number': p.patientNumber,
      'name': p.name,
      'mobile': p.mobile,
      'dob': p.dob != null ? _shortDateFormat.format(p.dob!) : '-',
      'department': p.department ?? 'General',
      'address': p.address ?? '-',
      'reference': p.reference ?? '-',
      'visit_date': p.visitDate != null ? _shortDateFormat.format(p.visitDate!) : '-',
      'created_at': p.createdAt.toIso8601String(),
    }).toList();

    final summaryRows = <Map<String, dynamic>>[
      {'metric': 'Total Patient Base', 'count': data.totalPatients.toString(), 'percentage': '100%'},
      {'metric': 'New Registrations in Period', 'count': data.newPatients.toString(), 'percentage': data.totalPatients > 0 ? '${((data.newPatients / data.totalPatients) * 100).toStringAsFixed(1)}%' : '-'},
      {'metric': 'Returning Patients', 'count': data.returningPatients.toString(), 'percentage': data.totalPatients > 0 ? '${((data.returningPatients / data.totalPatients) * 100).toStringAsFixed(1)}%' : '-'},
      {'metric': 'Eye Clinic Patients', 'count': data.eyePatients.toString(), 'percentage': '${data.eyePercentage.toStringAsFixed(1)}%'},
      {'metric': 'Dental Clinic Patients', 'count': data.dentalPatients.toString(), 'percentage': '${data.dentalPercentage.toStringAsFixed(1)}%'},
    ];

    final trendsRows = data.registrationTrends.map((t) => {
      'date': t.date,
      'label': t.label,
      'count': t.count,
    }).toList();

    return builder.buildCustomWorkbook(
      worksheets: [registrySheet, summarySheet, trendsSheet],
      recordsByWorksheet: {
        'Patients_Registry': registryRows,
        'Patient_Summary': summaryRows,
        'Registration_Trends': trendsRows,
      },
    );
  }

  /// Generates a standalone .xlsx workbook containing Appointments data & doctor metrics.
  static Uint8List generateAppointmentsReportWorkbook(
    AppointmentReportsData data, [
    AdminReportsFilter filter = const AdminReportsFilter(),
  ]) {
    final builder = ExcelWorkbookBuilder();

    final doctorSheet = ExcelWorksheetSpec(
      name: 'Doctor_Performance',
      sourceTable: 'doctor_performance',
      stableIdKey: 'doctor_name',
      timestampKey: 'doctor_name',
      description: 'Appointment workload and completion rates by clinical practitioner',
      columns: const [
        ExcelColumnSpec(header: 'Doctor Name', sourceField: 'doctor_name', width: 26),
        ExcelColumnSpec(header: 'Department', sourceField: 'department', width: 16),
        ExcelColumnSpec(header: 'Total Appointments', sourceField: 'total', width: 18, type: ExcelColumnType.number),
        ExcelColumnSpec(header: 'Completed', sourceField: 'completed', width: 14, type: ExcelColumnType.number),
        ExcelColumnSpec(header: 'Cancelled', sourceField: 'cancelled', width: 14, type: ExcelColumnType.number),
        ExcelColumnSpec(header: 'Completion Rate', sourceField: 'completion_rate', width: 16),
      ],
    );

    final summarySheet = ExcelWorksheetSpec(
      name: 'Appointment_Summary',
      sourceTable: 'appointment_summary',
      stableIdKey: 'metric',
      timestampKey: 'metric',
      description: 'Operational status, triage and department breakdown',
      columns: const [
        ExcelColumnSpec(header: 'Metric', sourceField: 'metric', width: 30),
        ExcelColumnSpec(header: 'Count', sourceField: 'count', width: 16, type: ExcelColumnType.number),
        ExcelColumnSpec(header: 'Share / Rate', sourceField: 'percentage', width: 18),
      ],
    );

    final trendsSheet = ExcelWorksheetSpec(
      name: 'Appointment_Trends',
      sourceTable: 'appointment_trends',
      stableIdKey: 'date',
      timestampKey: 'date',
      description: 'Daily appointment scheduling and completion trends',
      columns: const [
        ExcelColumnSpec(header: 'Date', sourceField: 'date', width: 14, type: ExcelColumnType.date),
        ExcelColumnSpec(header: 'Period Label', sourceField: 'label', width: 18),
        ExcelColumnSpec(header: 'Total Appointments', sourceField: 'total', width: 18, type: ExcelColumnType.number),
        ExcelColumnSpec(header: 'Completed', sourceField: 'completed', width: 14, type: ExcelColumnType.number),
        ExcelColumnSpec(header: 'Cancelled', sourceField: 'cancelled', width: 14, type: ExcelColumnType.number),
      ],
    );

    final doctorRows = data.doctorStats.map((d) => {
      'doctor_name': d.doctorName,
      'department': d.department,
      'total': d.totalAppointments,
      'completed': d.completedAppointments,
      'cancelled': d.cancelledAppointments,
      'completion_rate': '${d.completionRate.toStringAsFixed(1)}%',
    }).toList();

    final summaryRows = <Map<String, dynamic>>[
      {'metric': 'Total Appointments', 'count': data.totalAppointments, 'percentage': '100%'},
      {'metric': 'Completed Appointments', 'count': data.completedAppointments, 'percentage': '${data.completionRate.toStringAsFixed(1)}%'},
      {'metric': 'Cancelled Appointments', 'count': data.cancelledAppointments, 'percentage': '${data.cancellationRate.toStringAsFixed(1)}%'},
      {'metric': 'Currently Scheduled', 'count': data.scheduledAppointments, 'percentage': '-'},
      {'metric': 'In Triage', 'count': data.inTriageAppointments, 'percentage': '-'},
      {'metric': 'Eye Clinic Appointments', 'count': data.eyeAppointments, 'percentage': '${data.eyePercentage.toStringAsFixed(1)}%'},
      {'metric': 'Dental Clinic Appointments', 'count': data.dentalAppointments, 'percentage': '${data.dentalPercentage.toStringAsFixed(1)}%'},
      {'metric': 'Regular Bookings', 'count': data.regularAppointments, 'percentage': '-'},
      {'metric': 'Walk-in Patients', 'count': data.walkInAppointments, 'percentage': '-'},
      {'metric': 'Follow-up Visits', 'count': data.followUpAppointments, 'percentage': '-'},
    ];

    final trendsRows = data.appointmentTrends.map((t) => {
      'date': t.date,
      'label': t.label,
      'total': t.total,
      'completed': t.completed,
      'cancelled': t.cancelled,
    }).toList();

    return builder.buildCustomWorkbook(
      worksheets: [doctorSheet, summarySheet, trendsSheet],
      recordsByWorksheet: {
        'Doctor_Performance': doctorRows,
        'Appointment_Summary': summaryRows,
        'Appointment_Trends': trendsRows,
      },
    );
  }

  /// Generates a standalone .xlsx workbook containing Staff performance & attendance analytics.
  static Uint8List generateStaffReportWorkbook(
    StaffReportsData data, [
    AdminReportsFilter filter = const AdminReportsFilter(),
  ]) {
    final builder = ExcelWorkbookBuilder();

    final staffSheet = ExcelWorksheetSpec(
      name: 'Staff_Performance',
      sourceTable: 'staff_performance',
      stableIdKey: 'staff_id',
      timestampKey: 'staff_id',
      description: 'Individual employee attendance consistency and task fulfillment',
      columns: const [
        ExcelColumnSpec(header: 'Staff Name', sourceField: 'staff_name', width: 24),
        ExcelColumnSpec(header: 'Designation', sourceField: 'designation', width: 18),
        ExcelColumnSpec(header: 'Department', sourceField: 'department', width: 16),
        ExcelColumnSpec(header: 'Attendance Logs', sourceField: 'attendance_logs', width: 16, type: ExcelColumnType.number),
        ExcelColumnSpec(header: 'Present Days', sourceField: 'present_days', width: 14, type: ExcelColumnType.number),
        ExcelColumnSpec(header: 'Late Days', sourceField: 'late_days', width: 14, type: ExcelColumnType.number),
        ExcelColumnSpec(header: 'Leave Days', sourceField: 'leave_days', width: 14, type: ExcelColumnType.number),
        ExcelColumnSpec(header: 'Attendance Rate', sourceField: 'attendance_rate', width: 16),
        ExcelColumnSpec(header: 'Total Tasks', sourceField: 'total_tasks', width: 14, type: ExcelColumnType.number),
        ExcelColumnSpec(header: 'Completed Tasks', sourceField: 'completed_tasks', width: 16, type: ExcelColumnType.number),
        ExcelColumnSpec(header: 'Pending Tasks', sourceField: 'pending_tasks', width: 14, type: ExcelColumnType.number),
        ExcelColumnSpec(header: 'Overdue Tasks', sourceField: 'overdue_tasks', width: 14, type: ExcelColumnType.number),
        ExcelColumnSpec(header: 'Task Completion Rate', sourceField: 'task_completion_rate', width: 20),
      ],
    );

    final trendsSheet = ExcelWorksheetSpec(
      name: 'Attendance_Trends',
      sourceTable: 'attendance_trends',
      stableIdKey: 'date',
      timestampKey: 'date',
      description: 'Daily staff attendance, late arrivals, and leave trends',
      columns: const [
        ExcelColumnSpec(header: 'Date', sourceField: 'date', width: 14, type: ExcelColumnType.date),
        ExcelColumnSpec(header: 'Period Label', sourceField: 'label', width: 18),
        ExcelColumnSpec(header: 'Present Staff', sourceField: 'present', width: 14, type: ExcelColumnType.number),
        ExcelColumnSpec(header: 'Late Arrivals', sourceField: 'late', width: 14, type: ExcelColumnType.number),
        ExcelColumnSpec(header: 'On Leave', sourceField: 'leave', width: 14, type: ExcelColumnType.number),
      ],
    );

    final summarySheet = ExcelWorksheetSpec(
      name: 'Staff_KPI_Summary',
      sourceTable: 'staff_kpi_summary',
      stableIdKey: 'metric',
      timestampKey: 'metric',
      description: 'High-level workforce headcount, attendance and task KPIs',
      columns: const [
        ExcelColumnSpec(header: 'Workforce KPI', sourceField: 'metric', width: 32),
        ExcelColumnSpec(header: 'Value', sourceField: 'value', width: 20),
      ],
    );

    final staffRows = data.staffStats.map((s) => {
      'staff_id': s.staffId,
      'staff_name': s.staffName,
      'designation': s.designation ?? '-',
      'department': s.department ?? '-',
      'attendance_logs': s.attendanceLogs,
      'present_days': s.presentDays,
      'late_days': s.lateDays,
      'leave_days': s.leaveDays,
      'attendance_rate': '${s.attendancePercentage.toStringAsFixed(1)}%',
      'total_tasks': s.totalTasks,
      'completed_tasks': s.completedTasks,
      'pending_tasks': s.pendingTasks,
      'overdue_tasks': s.overdueTasks,
      'task_completion_rate': '${s.taskCompletionPercentage.toStringAsFixed(1)}%',
    }).toList();

    final trendsRows = data.attendanceTrends.map((t) => {
      'date': t.date,
      'label': t.label,
      'present': t.present,
      'late': t.late,
      'leave': t.leave,
    }).toList();

    final summaryRows = <Map<String, dynamic>>[
      {'metric': 'Total Staff Headcount', 'value': data.totalStaff.toString()},
      {'metric': 'Active Staff Accounts', 'value': data.activeStaff.toString()},
      {'metric': 'Total Attendance Logs in Period', 'value': data.totalAttendanceLogs.toString()},
      {'metric': 'On-Time / Present Shifts', 'value': data.presentCount.toString()},
      {'metric': 'Late Check-in Incidents', 'value': data.lateCount.toString()},
      {'metric': 'Approved Leaves Count', 'value': data.leaveCount.toString()},
      {'metric': 'Overall Attendance Consistency Rate', 'value': '${data.overallAttendanceRate.toStringAsFixed(1)}%'},
      {'metric': 'Total Assigned Tasks', 'value': data.totalTasks.toString()},
      {'metric': 'Completed Tasks', 'value': data.completedTasks.toString()},
      {'metric': 'In-Progress Tasks', 'value': data.inProgressTasks.toString()},
      {'metric': 'Pending Tasks', 'value': data.pendingTasks.toString()},
      {'metric': 'Overdue Tasks', 'value': data.overdueTasks.toString()},
      {'metric': 'Overall Task Completion Rate', 'value': '${data.taskCompletionRate.toStringAsFixed(1)}%'},
    ];

    return builder.buildCustomWorkbook(
      worksheets: [staffSheet, trendsSheet, summarySheet],
      recordsByWorksheet: {
        'Staff_Performance': staffRows,
        'Attendance_Trends': trendsRows,
        'Staff_KPI_Summary': summaryRows,
      },
    );
  }

  /// Generates a standalone .xlsx workbook containing Clinical & Procedure statistics.
  static Uint8List generateClinicalReportWorkbook(
    ClinicalReportsData data, [
    AdminReportsFilter filter = const AdminReportsFilter(),
  ]) {
    final builder = ExcelWorkbookBuilder();

    final leaderboardSheet = ExcelWorksheetSpec(
      name: 'Procedure_Leaderboard',
      sourceTable: 'procedure_leaderboard',
      stableIdKey: 'procedure_name',
      timestampKey: 'procedure_name',
      description: 'Most frequently performed treatments and clinical interventions',
      columns: const [
        ExcelColumnSpec(header: 'Procedure Name', sourceField: 'procedure_name', width: 32),
        ExcelColumnSpec(header: 'Department', sourceField: 'department', width: 16),
        ExcelColumnSpec(header: 'Procedures Performed', sourceField: 'count', width: 22, type: ExcelColumnType.number),
        ExcelColumnSpec(header: 'Total Revenue (INR)', sourceField: 'revenue', width: 20, type: ExcelColumnType.currency),
        ExcelColumnSpec(header: 'Average Fee (INR)', sourceField: 'avg_price', width: 18, type: ExcelColumnType.currency),
      ],
    );

    final trendsSheet = ExcelWorksheetSpec(
      name: 'Procedure_Trends',
      sourceTable: 'procedure_trends',
      stableIdKey: 'date',
      timestampKey: 'date',
      description: 'Daily procedure volume trends across Eye and Dental specialties',
      columns: const [
        ExcelColumnSpec(header: 'Date', sourceField: 'date', width: 14, type: ExcelColumnType.date),
        ExcelColumnSpec(header: 'Period Label', sourceField: 'label', width: 18),
        ExcelColumnSpec(header: 'Eye Procedures', sourceField: 'eye_count', width: 16, type: ExcelColumnType.number),
        ExcelColumnSpec(header: 'Dental Procedures', sourceField: 'dental_count', width: 18, type: ExcelColumnType.number),
        ExcelColumnSpec(header: 'Total Procedures', sourceField: 'total_count', width: 16, type: ExcelColumnType.number),
      ],
    );

    final summarySheet = ExcelWorksheetSpec(
      name: 'Clinical_Summary',
      sourceTable: 'clinical_summary',
      stableIdKey: 'metric',
      timestampKey: 'metric',
      description: 'Departmental procedure share and gross clinical volume valuation',
      columns: const [
        ExcelColumnSpec(header: 'Clinical Metric', sourceField: 'metric', width: 30),
        ExcelColumnSpec(header: 'Value', sourceField: 'value', width: 22),
      ],
    );

    final leaderboardRows = data.topProcedures.map((p) => {
      'procedure_name': p.procedureName,
      'department': p.department,
      'count': p.count,
      'revenue': p.totalRevenue,
      'avg_price': p.averagePrice,
    }).toList();

    final trendsRows = data.procedureTrends.map((t) => {
      'date': t.date,
      'label': t.label,
      'eye_count': t.eyeCount,
      'dental_count': t.dentalCount,
      'total_count': t.totalCount,
    }).toList();

    final summaryRows = <Map<String, dynamic>>[
      {'metric': 'Total Procedures Performed', 'value': data.totalProcedures.toString()},
      {'metric': 'Total Procedure Clinical Value', 'value': _currencyFormat.format(data.totalProceduresValue)},
      {'metric': 'Eye Clinic Procedures', 'value': '${data.eyeProcedures} (${data.eyePercentage.toStringAsFixed(1)}%)'},
      {'metric': 'Dental Clinic Procedures', 'value': '${data.dentalProcedures} (${data.dentalPercentage.toStringAsFixed(1)}%)'},
    ];

    return builder.buildCustomWorkbook(
      worksheets: [leaderboardSheet, trendsSheet, summarySheet],
      recordsByWorksheet: {
        'Procedure_Leaderboard': leaderboardRows,
        'Procedure_Trends': trendsRows,
        'Clinical_Summary': summaryRows,
      },
    );
  }

  /// Generates a standalone .xlsx workbook containing Billing & Financial reports.
  static Uint8List generateFinancialReportWorkbook(
    BillingReportsData data, [
    AdminReportsFilter filter = const AdminReportsFilter(),
  ]) {
    final builder = ExcelWorkbookBuilder();

    final summarySheet = ExcelWorksheetSpec(
      name: 'Financial_Summary',
      sourceTable: 'financial_summary',
      stableIdKey: 'metric',
      timestampKey: 'metric',
      description: 'Executive revenue, profit, invoice, and collection snapshot',
      columns: const [
        ExcelColumnSpec(header: 'Financial Metric', sourceField: 'metric', width: 32),
        ExcelColumnSpec(header: 'Value', sourceField: 'value', width: 22),
      ],
    );

    final deptSheet = ExcelWorksheetSpec(
      name: 'Department_Revenue',
      sourceTable: 'department_revenue',
      stableIdKey: 'department',
      timestampKey: 'department',
      description: 'Sales, collection, receivables, and profit margin by clinic department',
      columns: const [
        ExcelColumnSpec(header: 'Department', sourceField: 'department', width: 18),
        ExcelColumnSpec(header: 'Invoice Count', sourceField: 'invoice_count', width: 14, type: ExcelColumnType.number),
        ExcelColumnSpec(header: 'Invoiced Sales (INR)', sourceField: 'sales', width: 20, type: ExcelColumnType.currency),
        ExcelColumnSpec(header: 'Revenue Collected (INR)', sourceField: 'collected', width: 22, type: ExcelColumnType.currency),
        ExcelColumnSpec(header: 'Outstanding Balance (INR)', sourceField: 'outstanding', width: 24, type: ExcelColumnType.currency),
        ExcelColumnSpec(header: 'Estimated Profit (INR)', sourceField: 'profit', width: 22, type: ExcelColumnType.currency),
        ExcelColumnSpec(header: 'Revenue Share', sourceField: 'share', width: 16),
      ],
    );

    final paymentSheet = ExcelWorksheetSpec(
      name: 'Payment_Modes',
      sourceTable: 'payment_modes',
      stableIdKey: 'mode',
      timestampKey: 'mode',
      description: 'Collections segmented by payment tender (UPI, Cash, Card, Insurance)',
      columns: const [
        ExcelColumnSpec(header: 'Payment Tender', sourceField: 'mode', width: 20),
        ExcelColumnSpec(header: 'Transaction Count', sourceField: 'count', width: 18, type: ExcelColumnType.number),
        ExcelColumnSpec(header: 'Amount Collected (INR)', sourceField: 'amount', width: 22, type: ExcelColumnType.currency),
        ExcelColumnSpec(header: 'Share Percentage', sourceField: 'percentage', width: 18),
      ],
    );

    final periodicSheet = ExcelWorksheetSpec(
      name: 'Periodic_Revenue',
      sourceTable: 'periodic_revenue',
      stableIdKey: 'period_label',
      timestampKey: 'date',
      description: 'Daily/monthly revenue collections, invoices, and profitability',
      columns: const [
        ExcelColumnSpec(header: 'Period Label', sourceField: 'period_label', width: 18),
        ExcelColumnSpec(header: 'Date', sourceField: 'date', width: 14, type: ExcelColumnType.date),
        ExcelColumnSpec(header: 'Invoices', sourceField: 'invoice_count', width: 12, type: ExcelColumnType.number),
        ExcelColumnSpec(header: 'Total Sales (INR)', sourceField: 'sales', width: 18, type: ExcelColumnType.currency),
        ExcelColumnSpec(header: 'Collected (INR)', sourceField: 'collected', width: 18, type: ExcelColumnType.currency),
        ExcelColumnSpec(header: 'Outstanding (INR)', sourceField: 'outstanding', width: 18, type: ExcelColumnType.currency),
        ExcelColumnSpec(header: 'Estimated Profit (INR)', sourceField: 'profit', width: 20, type: ExcelColumnType.currency),
        ExcelColumnSpec(header: 'Collection Rate', sourceField: 'collection_rate', width: 16),
      ],
    );

    final servicesSheet = ExcelWorksheetSpec(
      name: 'Top_Services',
      sourceTable: 'top_services',
      stableIdKey: 'service_name',
      timestampKey: 'service_name',
      description: 'Highest billing clinical treatments, diagnostic items and consumables',
      columns: const [
        ExcelColumnSpec(header: 'Service / Procedure Name', sourceField: 'service_name', width: 32),
        ExcelColumnSpec(header: 'Department', sourceField: 'department', width: 16),
        ExcelColumnSpec(header: 'Quantity Dispensed', sourceField: 'quantity', width: 20, type: ExcelColumnType.number),
        ExcelColumnSpec(header: 'Total Revenue (INR)', sourceField: 'revenue', width: 20, type: ExcelColumnType.currency),
      ],
    );

    final summaryRows = <Map<String, dynamic>>[
      {'metric': 'Gross Invoiced Sales', 'value': _currencyFormat.format(data.totalSales)},
      {'metric': 'Revenue Collected', 'value': _currencyFormat.format(data.totalRevenue)},
      {'metric': 'Outstanding Receivables', 'value': _currencyFormat.format(data.totalOutstanding)},
      {'metric': 'Estimated Profit Margin', 'value': _currencyFormat.format(data.estimatedProfit)},
      {'metric': 'Total Invoices Generated', 'value': data.totalInvoices.toString()},
      {'metric': 'Fully Settled Invoices', 'value': data.paidInvoicesCount.toString()},
      {'metric': 'Partially Settled Invoices', 'value': data.partiallyPaidInvoicesCount.toString()},
      {'metric': 'Average Order Value (AOV)', 'value': _currencyFormat.format(data.averageOrderValue)},
      {'metric': 'Collection Efficiency Rate', 'value': '${data.collectionRate.toStringAsFixed(1)}%'},
    ];

    final deptRows = <Map<String, dynamic>>[
      {
        'department': 'Eye Clinic',
        'invoice_count': data.eyeSummary.invoiceCount,
        'sales': data.eyeSummary.totalSales,
        'collected': data.eyeSummary.revenueCollected,
        'outstanding': data.eyeSummary.outstandingBalance,
        'profit': data.eyeSummary.estimatedProfit,
        'share': '${data.eyeSummary.sharePercentage.toStringAsFixed(1)}%',
      },
      {
        'department': 'Dental Clinic',
        'invoice_count': data.dentalSummary.invoiceCount,
        'sales': data.dentalSummary.totalSales,
        'collected': data.dentalSummary.revenueCollected,
        'outstanding': data.dentalSummary.outstandingBalance,
        'profit': data.dentalSummary.estimatedProfit,
        'share': '${data.dentalSummary.sharePercentage.toStringAsFixed(1)}%',
      },
    ];

    final paymentRows = data.paymentModes.map((p) => {
      'mode': p.mode,
      'count': p.transactionCount,
      'amount': p.totalAmount,
      'percentage': '${p.percentage.toStringAsFixed(1)}%',
    }).toList();

    final periodicRows = data.periodicBuckets.map((b) => {
      'period_label': b.periodLabel,
      'date': b.date,
      'invoice_count': b.invoiceCount,
      'sales': b.totalSales,
      'collected': b.revenueCollected,
      'outstanding': b.outstandingBalance,
      'profit': b.estimatedProfit,
      'collection_rate': '${b.collectionRate.toStringAsFixed(1)}%',
    }).toList();

    final serviceRows = data.topServices.map((s) => {
      'service_name': s.serviceName,
      'department': s.department,
      'quantity': s.quantity,
      'revenue': s.totalRevenue,
    }).toList();

    return builder.buildCustomWorkbook(
      worksheets: [summarySheet, deptSheet, paymentSheet, periodicSheet, servicesSheet],
      recordsByWorksheet: {
        'Financial_Summary': summaryRows,
        'Department_Revenue': deptRows,
        'Payment_Modes': paymentRows,
        'Periodic_Revenue': periodicRows,
        'Top_Services': serviceRows,
      },
    );
  }

  /// Generates a standalone .xlsx workbook containing Inventory & Stock analytics.
  static Uint8List generateInventoryReportWorkbook(
    InventoryReportsData data, [
    AdminReportsFilter filter = const AdminReportsFilter(),
  ]) {
    final builder = ExcelWorkbookBuilder();

    final snapshotSheet = ExcelWorksheetSpec(
      name: 'Inventory_Snapshot',
      sourceTable: 'inventory_snapshot',
      stableIdKey: 'metric',
      timestampKey: 'metric',
      description: 'Stock valuation, low stock alerts, and expiration risk overview',
      columns: const [
        ExcelColumnSpec(header: 'Inventory Metric', sourceField: 'metric', width: 34),
        ExcelColumnSpec(header: 'Value', sourceField: 'value', width: 22),
      ],
    );

    final categorySheet = ExcelWorksheetSpec(
      name: 'Category_Valuation',
      sourceTable: 'category_valuation',
      stableIdKey: 'category',
      timestampKey: 'category',
      description: 'Stock holding distribution across clinical categories',
      columns: const [
        ExcelColumnSpec(header: 'Category', sourceField: 'category', width: 24),
        ExcelColumnSpec(header: 'Items Count', sourceField: 'item_count', width: 14, type: ExcelColumnType.number),
        ExcelColumnSpec(header: 'Stock Units', sourceField: 'units', width: 14, type: ExcelColumnType.number),
        ExcelColumnSpec(header: 'Valuation (INR)', sourceField: 'valuation', width: 18, type: ExcelColumnType.currency),
        ExcelColumnSpec(header: 'Share Percentage', sourceField: 'share', width: 16),
      ],
    );

    final lowStockSheet = ExcelWorksheetSpec(
      name: 'Low_Stock_Alerts',
      sourceTable: 'low_stock_items',
      stableIdKey: 'item_name',
      timestampKey: 'item_name',
      description: 'Items below minimum reorder thresholds requiring purchase replenishment',
      columns: const [
        ExcelColumnSpec(header: 'Item Name', sourceField: 'item_name', width: 28),
        ExcelColumnSpec(header: 'SKU', sourceField: 'sku', width: 16),
        ExcelColumnSpec(header: 'Location', sourceField: 'location', width: 16),
        ExcelColumnSpec(header: 'Current Stock', sourceField: 'current_stock', width: 14, type: ExcelColumnType.number),
        ExcelColumnSpec(header: 'Min Stock', sourceField: 'min_stock', width: 12, type: ExcelColumnType.number),
        ExcelColumnSpec(header: 'Shortfall', sourceField: 'shortfall', width: 12, type: ExcelColumnType.number),
        ExcelColumnSpec(header: 'Unit', sourceField: 'unit', width: 10),
        ExcelColumnSpec(header: 'Preferred Vendor', sourceField: 'vendor_name', width: 22),
        ExcelColumnSpec(header: 'Vendor Contact', sourceField: 'vendor_phone', width: 16),
        ExcelColumnSpec(header: 'Last Price (INR)', sourceField: 'last_price', width: 16, type: ExcelColumnType.currency),
        ExcelColumnSpec(header: 'Stock Status', sourceField: 'status', width: 16),
      ],
    );

    final expirySheet = ExcelWorksheetSpec(
      name: 'Batch_Expiry_Risk',
      sourceTable: 'batch_expiry',
      stableIdKey: 'batch_number',
      timestampKey: 'expiry_date',
      description: 'Pharmaceutical and consumable lots nearing or past expiration',
      columns: const [
        ExcelColumnSpec(header: 'Batch Number', sourceField: 'batch_number', width: 18),
        ExcelColumnSpec(header: 'Item Name', sourceField: 'item_name', width: 26),
        ExcelColumnSpec(header: 'Category', sourceField: 'category', width: 18),
        ExcelColumnSpec(header: 'Expiry Date', sourceField: 'expiry_date', width: 14, type: ExcelColumnType.date),
        ExcelColumnSpec(header: 'Days Remaining', sourceField: 'days_remaining', width: 16, type: ExcelColumnType.number),
        ExcelColumnSpec(header: 'Remaining Units', sourceField: 'quantity', width: 16, type: ExcelColumnType.number),
        ExcelColumnSpec(header: 'Unit Cost (INR)', sourceField: 'unit_price', width: 16, type: ExcelColumnType.currency),
        ExcelColumnSpec(header: 'At-Risk Value (INR)', sourceField: 'total_amount', width: 18, type: ExcelColumnType.currency),
        ExcelColumnSpec(header: 'Urgency Status', sourceField: 'status', width: 16),
      ],
    );

    final auditSheet = ExcelWorksheetSpec(
      name: 'Stock_Movement_Audit',
      sourceTable: 'stock_movement',
      stableIdKey: 'date',
      timestampKey: 'date',
      description: 'Immutable ledger of stock-in, stock-out, allocations and write-offs',
      columns: const [
        ExcelColumnSpec(header: 'Date & Time', sourceField: 'date', width: 18, type: ExcelColumnType.datetime),
        ExcelColumnSpec(header: 'Item Name', sourceField: 'item_name', width: 26),
        ExcelColumnSpec(header: 'Transaction Type', sourceField: 'type', width: 16),
        ExcelColumnSpec(header: 'Quantity', sourceField: 'quantity', width: 12, type: ExcelColumnType.number),
        ExcelColumnSpec(header: 'Stock Before', sourceField: 'stock_before', width: 14, type: ExcelColumnType.number),
        ExcelColumnSpec(header: 'Stock After', sourceField: 'stock_after', width: 14, type: ExcelColumnType.number),
        ExcelColumnSpec(header: 'Operational Reason', sourceField: 'reason', width: 22),
        ExcelColumnSpec(header: 'Performed By', sourceField: 'performed_by', width: 20),
        ExcelColumnSpec(header: 'Recipient / Patient', sourceField: 'recipient', width: 20),
        ExcelColumnSpec(header: 'Remarks', sourceField: 'remarks', width: 28),
      ],
    );

    final fastMovingSheet = ExcelWorksheetSpec(
      name: 'Fast_Moving_Items',
      sourceTable: 'fast_moving_items',
      stableIdKey: 'item_name',
      timestampKey: 'item_name',
      description: 'Frequently dispensed medications, supplies and consumables',
      columns: const [
        ExcelColumnSpec(header: 'Item Name', sourceField: 'item_name', width: 28),
        ExcelColumnSpec(header: 'Category', sourceField: 'category', width: 18),
        ExcelColumnSpec(header: 'Units Consumed', sourceField: 'units_consumed', width: 16, type: ExcelColumnType.number),
        ExcelColumnSpec(header: 'Value Consumed (INR)', sourceField: 'value_consumed', width: 20, type: ExcelColumnType.currency),
        ExcelColumnSpec(header: 'Dispense Count', sourceField: 'transaction_count', width: 16, type: ExcelColumnType.number),
      ],
    );

    final snapshotRows = <Map<String, dynamic>>[
      {'metric': 'Total Catalog Items', 'value': data.totalCatalogItems.toString()},
      {'metric': 'Active Stocked SKUs', 'value': data.activeItemsCount.toString()},
      {'metric': 'Total Physical Units in Stock', 'value': data.totalUnits.toStringAsFixed(1)},
      {'metric': 'Total Stock Valuation', 'value': _currencyFormat.format(data.totalValuation)},
      {'metric': 'Central Store Valuation', 'value': _currencyFormat.format(data.centralValuation)},
      {'metric': 'Eye Clinic Valuation', 'value': _currencyFormat.format(data.eyeValuation)},
      {'metric': 'Dental Clinic Valuation', 'value': _currencyFormat.format(data.dentalValuation)},
      {'metric': 'Central Store Low Stock Alerts', 'value': data.centralLowStockCount.toString()},
      {'metric': 'Department Low Stock Alerts', 'value': data.departmentLowStockCount.toString()},
      {'metric': 'Critical Stock-Outs (0 Units)', 'value': data.stockOutCount.toString()},
      {'metric': 'Expired Batches Detected', 'value': data.expiredBatchesCount.toString()},
      {'metric': 'Expired Stock Value Lost', 'value': _currencyFormat.format(data.expiredValueLost)},
      {'metric': '30-Day At-Risk Expiry Valuation', 'value': _currencyFormat.format(data.expiring30DaysValue)},
    ];

    final categoryRows = data.categoryValuations.map((c) => {
      'category': c.category,
      'item_count': c.itemCount,
      'units': c.totalUnits,
      'valuation': c.totalValuation,
      'share': '${c.percentage.toStringAsFixed(1)}%',
    }).toList();

    final lowStockRows = data.lowStockItems.map((i) => {
      'item_name': i.itemName,
      'sku': i.sku ?? '-',
      'location': i.location,
      'current_stock': i.currentStock,
      'min_stock': i.minimumStock,
      'shortfall': i.shortfall,
      'unit': i.unit,
      'vendor_name': i.vendorName ?? '-',
      'vendor_phone': i.vendorPhone ?? '-',
      'last_price': i.lastPrice ?? 0.0,
      'status': i.isStockOut ? 'DEPLETED / ZERO' : 'LOW STOCK',
    }).toList();

    final expiryRows = data.batchExpiryDetails.map((b) => {
      'batch_number': b.batchNumber,
      'item_name': b.itemName,
      'category': b.category,
      'expiry_date': b.expiryDate != null ? _shortDateFormat.format(b.expiryDate!) : '-',
      'days_remaining': b.daysRemaining ?? 0,
      'quantity': b.remainingQuantity,
      'unit_price': b.unitPrice,
      'total_amount': b.totalAmount,
      'status': b.urgencyStatus.toUpperCase(),
    }).toList();

    final auditRows = data.auditLedger.map((tx) => {
      'date': tx.date,
      'item_name': tx.itemName,
      'type': tx.transactionType.toUpperCase(),
      'quantity': tx.quantity,
      'stock_before': tx.stockBefore ?? 0.0,
      'stock_after': tx.stockAfter ?? 0.0,
      'reason': tx.reason ?? '-',
      'performed_by': tx.performedByName ?? '-',
      'recipient': tx.recipientInfo ?? '-',
      'remarks': tx.remarks ?? '-',
    }).toList();

    final fastMovingRows = data.fastMovingItems.map((f) => {
      'item_name': f.itemName,
      'category': f.category,
      'units_consumed': f.totalConsumedUnits,
      'value_consumed': f.totalConsumedValue,
      'transaction_count': f.transactionCount,
    }).toList();

    return builder.buildCustomWorkbook(
      worksheets: [
        snapshotSheet,
        categorySheet,
        lowStockSheet,
        expirySheet,
        auditSheet,
        fastMovingSheet,
      ],
      recordsByWorksheet: {
        'Inventory_Snapshot': snapshotRows,
        'Category_Valuation': categoryRows,
        'Low_Stock_Alerts': lowStockRows,
        'Batch_Expiry_Risk': expiryRows,
        'Stock_Movement_Audit': auditRows,
        'Fast_Moving_Items': fastMovingRows,
      },
    );
  }

  // ── 2. GENERAL STANDALONE EXCEL EXPORT ORCHESTRATOR ────────────────────────

  /// Builds the standalone .xlsx bytes for any given section and filter.
  static Uint8List buildSectionWorkbookBytes({
    required ReportsSection section,
    required AdminReportsFilter filter,
    required dynamic sectionData,
  }) {
    switch (section) {
      case ReportsSection.overview:
        return generateOverviewReportWorkbook(
          sectionData is OverviewReportsData
              ? sectionData
              : const OverviewReportsData(
                  totalPatients: 0,
                  newPatients: 0,
                  totalAppointments: 0,
                  completedAppointments: 0,
                  totalProcedures: 0,
                  totalSales: 0.0,
                  totalRevenue: 0.0,
                  totalOutstanding: 0.0,
                  eyePatients: 0,
                  dentalPatients: 0,
                  eyeAppointments: 0,
                  dentalAppointments: 0,
                  eyeProcedures: 0,
                  dentalProcedures: 0,
                  eyeSales: 0.0,
                  dentalSales: 0.0,
                  trendPoints: [],
                ),
          filter,
        );
      case ReportsSection.patients:
        return generatePatientsReportWorkbook(
          sectionData is PatientReportsData ? sectionData : PatientReportsData.empty,
          filter,
        );
      case ReportsSection.appointments:
        return generateAppointmentsReportWorkbook(
          sectionData is AppointmentReportsData
              ? sectionData
              : const AppointmentReportsData(
                  totalAppointments: 0,
                  completedAppointments: 0,
                  cancelledAppointments: 0,
                  scheduledAppointments: 0,
                  inTriageAppointments: 0,
                  completionRate: 0.0,
                  cancellationRate: 0.0,
                  eyeAppointments: 0,
                  dentalAppointments: 0,
                  eyePercentage: 0.0,
                  dentalPercentage: 0.0,
                  regularAppointments: 0,
                  walkInAppointments: 0,
                  followUpAppointments: 0,
                  doctorStats: [],
                  appointmentTrends: [],
                ),
          filter,
        );
      case ReportsSection.staff:
        return generateStaffReportWorkbook(
          sectionData is StaffReportsData ? sectionData : StaffReportsData.empty,
          filter,
        );
      case ReportsSection.clinical:
        return generateClinicalReportWorkbook(
          sectionData is ClinicalReportsData ? sectionData : ClinicalReportsData.empty,
          filter,
        );
      case ReportsSection.financial:
        return generateFinancialReportWorkbook(
          sectionData is BillingReportsData
              ? sectionData
              : const BillingReportsData(
                  totalSales: 0.0,
                  totalRevenue: 0.0,
                  totalOutstanding: 0.0,
                  estimatedProfit: 0.0,
                  totalInvoices: 0,
                  paidInvoicesCount: 0,
                  partiallyPaidInvoicesCount: 0,
                  averageOrderValue: 0.0,
                  collectionRate: 0.0,
                  eyeSummary: DepartmentRevenueSummary(
                    department: 'Eye',
                    invoiceCount: 0,
                    totalSales: 0.0,
                    revenueCollected: 0.0,
                    outstandingBalance: 0.0,
                    estimatedProfit: 0.0,
                    sharePercentage: 0.0,
                  ),
                  dentalSummary: DepartmentRevenueSummary(
                    department: 'Dental',
                    invoiceCount: 0,
                    totalSales: 0.0,
                    revenueCollected: 0.0,
                    outstandingBalance: 0.0,
                    estimatedProfit: 0.0,
                    sharePercentage: 0.0,
                  ),
                  paymentModes: [],
                  periodicBuckets: [],
                  topServices: [],
                ),
          filter,
        );
      case ReportsSection.inventory:
        return generateInventoryReportWorkbook(
          sectionData is InventoryReportsData
              ? sectionData
              : InventoryReportsData.empty,
          filter,
        );
    }
  }

  /// Exports the currently selected section report as a standalone .xlsx file.
  ///
  /// Uploads to Supabase storage (`clinic-excel-sync/reports/<fileName>`) and triggers
  /// direct Android download via signed URL in an external browser / download manager.
  static Future<ExportReportResult> exportReportToExcel({
    required ReportsSection section,
    required AdminReportsFilter filter,
    required dynamic sectionData,
    required SupabaseClient supabase,
  }) async {
    final fileName = filter.getReportFileName(section);

    try {
      // 1. Generate standalone .xlsx bytes in memory
      final bytes = buildSectionWorkbookBytes(
        section: section,
        filter: filter,
        sectionData: sectionData,
      );

      final fileSizeBytes = bytes.length;

      // 2. Upload to clinic-excel-sync/reports/<fileName>
      final storagePath = 'reports/$fileName';
      await supabase.storage.from(storageBucket).uploadBinary(
            storagePath,
            bytes,
            fileOptions: const FileOptions(
              upsert: true,
              contentType:
                  'application/vnd.openxmlformats-officedocument.spreadsheetml.sheet',
            ),
          );

      // 3. Generate 1-hour signed URL
      final signedUrl = await supabase.storage
          .from(storageBucket)
          .createSignedUrl(storagePath, 3600);

      // 4. Launch download on Android
      bool launched = false;
      if (signedUrl.isNotEmpty) {
        final uri = Uri.parse(signedUrl);
        if (await canLaunchUrl(uri)) {
          launched =
              await launchUrl(uri, mode: LaunchMode.externalApplication);
        }
      }

      return ExportReportResult(
        success: true,
        fileName: fileName,
        fileSizeBytes: fileSizeBytes,
        signedUrl: signedUrl,
        launched: launched,
      );
    } catch (e) {
      debugPrint('ReportsExportService export error: $e');
      return ExportReportResult(
        success: false,
        fileName: fileName,
        errorMessage: e.toString().replaceAll('Exception:', '').trim(),
      );
    }
  }

  // ── 3. PRESERVED SHARED CSV & HTML UTILITIES ───────────────────────────────

  /// Generates the complete Inventory Analytics report as an Excel-compatible CSV string.
  static String generateCsvContent(InventoryReportsData data,
      [AdminReportsFilter filter = const AdminReportsFilter()]) {
    final buffer = StringBuffer();
    buffer.write('\uFEFF'); // UTF-8 BOM for Microsoft Excel

    // 1. Header & Metadata
    buffer.writeln('"MKES CARE+ CLINICAL MANAGEMENT PLATFORM"');
    buffer.writeln('"INVENTORY & STOCK ANALYTICS REPORT"');
    buffer.writeln('"Generated At","${_dateFormat.format(DateTime.now())}"');
    buffer.writeln(
        '"Date Range Preset","${_cleanCsvValue(filter.datePresetLabel)}"');
    buffer.writeln(
        '"Department Filter","${_cleanCsvValue(filter.department.toUpperCase())}"');
    buffer.writeln();

    // 2. Executive Snapshot
    buffer.writeln('"=== EXECUTIVE INVENTORY SNAPSHOT ==="');
    buffer.writeln('"Metric","Value"');
    buffer.writeln('"Total Catalog Items","${data.totalCatalogItems}"');
    buffer.writeln('"Active Items","${data.activeItemsCount}"');
    buffer
        .writeln('"Total Stock Units","${data.totalUnits.toStringAsFixed(1)}"');
    buffer.writeln(
        '"Total Stock Valuation","${_cleanCsvValue(_currencyFormat.format(data.totalValuation))}"');
    buffer.writeln(
        '"Central Store Valuation","${_cleanCsvValue(_currencyFormat.format(data.centralValuation))}"');
    buffer.writeln(
        '"Eye Clinic Valuation","${_cleanCsvValue(_currencyFormat.format(data.eyeValuation))}"');
    buffer.writeln(
        '"Dental Clinic Valuation","${_cleanCsvValue(_currencyFormat.format(data.dentalValuation))}"');
    buffer.writeln('"Central Low Stock Items","${data.centralLowStockCount}"');
    buffer.writeln(
        '"Department Low Stock Items","${data.departmentLowStockCount}"');
    buffer.writeln('"Critical Stock-Outs","${data.stockOutCount}"');
    buffer.writeln('"Expired Batches","${data.expiredBatchesCount}"');
    buffer.writeln(
        '"Expired Stock Value Lost","${_cleanCsvValue(_currencyFormat.format(data.expiredValueLost))}"');
    buffer.writeln(
        '"Expiring in 30 Days (At-Risk Value)","${_cleanCsvValue(_currencyFormat.format(data.expiring30DaysValue))}"');
    buffer.writeln();

    // 3. Category Breakdown
    buffer.writeln('"=== CATEGORY VALUATION BREAKDOWN ==="');
    buffer.writeln(
        '"Category","Items Count","Total Units","Valuation (INR)","Share (%)"');
    for (final cat in data.categoryValuations) {
      buffer.writeln(
          '"${_cleanCsvValue(cat.category)}","${cat.itemCount}","${cat.totalUnits.toStringAsFixed(1)}","${cat.totalValuation.toStringAsFixed(2)}","${cat.percentage.toStringAsFixed(1)}%"');
    }
    buffer.writeln();

    // 4. Low-Stock & Reorder Priority List
    buffer.writeln('"=== LOW-STOCK & REORDER PRIORITIES ==="');
    buffer.writeln(
        '"Item Name","SKU","Location","Current Stock","Min Stock","Shortfall","Unit","Preferred Vendor","Vendor Phone","Last Price (INR)","Status"');
    for (final item in data.lowStockItems) {
      buffer.writeln(
          '"${_cleanCsvValue(item.itemName)}","${_cleanCsvValue(item.sku ?? '-')}","${_cleanCsvValue(item.location)}","${item.currentStock.toStringAsFixed(1)}","${item.minimumStock.toStringAsFixed(1)}","${item.shortfall.toStringAsFixed(1)}","${_cleanCsvValue(item.unit)}","${_cleanCsvValue(item.vendorName ?? '-')}","${_cleanCsvValue(item.vendorPhone ?? '-')}","${item.lastPrice?.toStringAsFixed(2) ?? '-'}","${item.isStockOut ? 'OUT OF STOCK' : 'LOW STOCK'}"');
    }
    buffer.writeln();

    // 5. Batch Expiry Traceability
    buffer.writeln('"=== BATCH EXPIRY & RISK TRACEABILITY ==="');
    buffer.writeln(
        '"Batch Number","Item Name","Category","Expiry Date","Days Remaining","Remaining Qty","Unit Price (INR)","Total Batch Value (INR)","Status"');
    for (final b in data.batchExpiryDetails) {
      final expStr = b.expiryDate != null
          ? DateFormat('dd-MM-yyyy').format(b.expiryDate!)
          : 'No Expiry';
      buffer.writeln(
          '"${_cleanCsvValue(b.batchNumber)}","${_cleanCsvValue(b.itemName)}","${_cleanCsvValue(b.category)}","$expStr","${b.daysRemaining ?? '-'}","${b.remainingQuantity.toStringAsFixed(1)}","${b.unitPrice.toStringAsFixed(2)}","${b.totalAmount.toStringAsFixed(2)}","${b.urgencyStatus.toUpperCase()}"');
    }
    buffer.writeln();

    // 6. Stock Movement Audit Ledger
    buffer.writeln('"=== STOCK MOVEMENT AUDIT LEDGER (SELECTED PERIOD) ==="');
    buffer.writeln(
        '"Timestamp","Item Name","Transaction Type","Quantity","Stock Before","Stock After","Reason","Performed By","Recipient / Patient","Remarks"');
    for (final tx in data.auditLedger) {
      buffer.writeln(
          '"${_dateFormat.format(tx.date)}","${_cleanCsvValue(tx.itemName)}","${tx.transactionType.toUpperCase()}","${tx.quantity.toStringAsFixed(1)}","${tx.stockBefore?.toStringAsFixed(1) ?? '-'}","${tx.stockAfter?.toStringAsFixed(1) ?? '-'}","${_cleanCsvValue(tx.reason ?? '-')}","${_cleanCsvValue(tx.performedByName ?? '-')}","${_cleanCsvValue(tx.recipientInfo ?? '-')}","${_cleanCsvValue(tx.remarks ?? '-')}"');
    }

    return buffer.toString();
  }

  /// Exports the complete Inventory Analytics report as an Excel-compatible CSV file.
  static Future<bool> exportInventoryToCsv({
    required InventoryReportsData data,
    AdminReportsFilter filter = const AdminReportsFilter(),
  }) async {
    final csv = generateCsvContent(data, filter);
    return _launchDataUri(
      content: csv,
      mimeType: 'text/csv',
      filename:
          'MKES_Inventory_Report_${DateFormat('yyyyMMdd_HHmmss').format(DateTime.now())}.csv',
    );
  }

  /// Generates a styled, printable HTML report string.
  static String generateHtmlContent(InventoryReportsData data,
      [AdminReportsFilter filter = const AdminReportsFilter()]) {
    final currency =
        NumberFormat.currency(locale: 'en_IN', symbol: '₹', decimalDigits: 2);
    final nowStr = _dateFormat.format(DateTime.now());

    return '''
<!DOCTYPE html>
<html>
<head>
  <meta charset="utf-8">
  <title>MKES CARE+ Inventory & Stock Report</title>
  <style>
    @media print {
      body { font-size: 11px; margin: 10mm; }
      .no-print { display: none; }
      .page-break { page-break-after: always; }
    }
    body { font-family: -apple-system, BlinkMacSystemFont, "Segoe UI", Roboto, Arial, sans-serif; color: #1e293b; line-height: 1.4; padding: 24px; background: #fff; }
    .header { border-bottom: 2px solid #0d9488; padding-bottom: 12px; margin-bottom: 20px; display: flex; justify-content: space-between; align-items: flex-start; }
    .header h1 { margin: 0; color: #0d9488; font-size: 24px; font-weight: 700; }
    .header p { margin: 4px 0 0 0; color: #64748b; font-size: 12px; }
    .meta { font-size: 11px; color: #475569; text-align: right; }
    .kpi-grid { display: grid; grid-template-columns: repeat(4, 1fr); gap: 12px; margin-bottom: 24px; }
    .kpi-card { border: 1px solid #e2e8f0; border-radius: 8px; padding: 12px; background: #f8fafc; }
    .kpi-title { font-size: 11px; color: #64748b; text-transform: uppercase; font-weight: 600; margin-bottom: 4px; }
    .kpi-value { font-size: 20px; font-weight: 700; color: #0f172a; }
    .kpi-sub { font-size: 10px; color: #94a3b8; margin-top: 2px; }
    h2 { font-size: 15px; border-left: 4px solid #0d9488; padding-left: 8px; margin: 24px 0 10px 0; color: #0f172a; }
    table { width: 100%; border-collapse: collapse; margin-bottom: 20px; font-size: 11px; }
    th { background: #f1f5f9; text-align: left; padding: 8px; border: 1px solid #e2e8f0; font-weight: 600; color: #334155; }
    td { padding: 7px 8px; border: 1px solid #e2e8f0; }
    tr:nth-child(even) { background: #f8fafc; }
    .badge-alert { background: #fee2e2; color: #b91c1c; padding: 2px 6px; border-radius: 4px; font-weight: 600; }
    .badge-warn { background: #fef3c7; color: #d97706; padding: 2px 6px; border-radius: 4px; font-weight: 600; }
    .badge-success { background: #dcfce7; color: #15803d; padding: 2px 6px; border-radius: 4px; font-weight: 600; }
    .footer { text-align: center; margin-top: 30px; font-size: 10px; color: #94a3b8; border-top: 1px solid #e2e8f0; padding-top: 10px; }
    .print-btn { background: #0d9488; color: #fff; border: none; padding: 10px 18px; border-radius: 6px; font-weight: 600; cursor: pointer; font-size: 13px; }
  </style>
</head>
<body>
  <div class="header">
    <div>
      <h1>MKES CARE+ Clinical Management Platform</h1>
      <p>Comprehensive Inventory, Stock Valuation & Movement Audit</p>
    </div>
    <div class="meta">
      <strong>Generated:</strong> $nowStr<br>
      <strong>Preset:</strong> ${filter.datePresetLabel}<br>
      <strong>Department:</strong> ${filter.department.toUpperCase()}<br>
      <div class="no-print" style="margin-top: 8px;">
        <button class="print-btn" onclick="window.print()">Print / Save as PDF</button>
      </div>
    </div>
  </div>

  <div class="kpi-grid">
    <div class="kpi-card">
      <div class="kpi-title">Total Stock Valuation</div>
      <div class="kpi-value">${currency.format(data.totalValuation)}</div>
      <div class="kpi-sub">Central: ${currency.format(data.centralValuation)}</div>
    </div>
    <div class="kpi-card">
      <div class="kpi-title">Total Catalog Items</div>
      <div class="kpi-value">${data.totalCatalogItems}</div>
      <div class="kpi-sub">${data.activeItemsCount} active SKUs • ${data.totalUnits.toInt()} units</div>
    </div>
    <div class="kpi-card">
      <div class="kpi-title">Low Stock & Stock-Outs</div>
      <div class="kpi-value" style="color: ${data.totalUrgentAlerts > 0 ? '#dc2626' : '#15803d'};">${data.lowStockItems.length}</div>
      <div class="kpi-sub">${data.stockOutCount} completely depleted</div>
    </div>
    <div class="kpi-card">
      <div class="kpi-title">Expired & At-Risk Value</div>
      <div class="kpi-value" style="color: ${data.totalAtRiskValue > 0 ? '#d97706' : '#15803d'};">${currency.format(data.totalAtRiskValue)}</div>
      <div class="kpi-sub">${data.expiredBatchesCount} expired batches (${currency.format(data.expiredValueLost)})</div>
    </div>
  </div>

  <h2>1. Stock Valuation by Category</h2>
  <table>
    <thead>
      <tr>
        <th>Category</th>
        <th>Items Count</th>
        <th>Total Units</th>
        <th>Valuation</th>
        <th>Share (%)</th>
      </tr>
    </thead>
    <tbody>
      ${data.categoryValuations.map((c) => '''
      <tr>
        <td><strong>${c.category}</strong></td>
        <td>${c.itemCount}</td>
        <td>${c.totalUnits.toStringAsFixed(1)}</td>
        <td>${currency.format(c.totalValuation)}</td>
        <td>${c.percentage.toStringAsFixed(1)}%</td>
      </tr>
      ''').join('')}
    </tbody>
  </table>

  <h2>2. Low-Stock & Reorder Priorities (${data.lowStockItems.length})</h2>
  <table>
    <thead>
      <tr>
        <th>Item Name</th>
        <th>SKU</th>
        <th>Location</th>
        <th>Current Stock</th>
        <th>Min Stock</th>
        <th>Shortfall</th>
        <th>Preferred Vendor</th>
        <th>Contact</th>
        <th>Status</th>
      </tr>
    </thead>
    <tbody>
      ${data.lowStockItems.isEmpty ? '<tr><td colspan="9" style="text-align:center; color:#94a3b8;">All items are comfortably stocked above minimum thresholds.</td></tr>' : data.lowStockItems.map((i) => '''
      <tr>
        <td><strong>${i.itemName}</strong></td>
        <td>${i.sku ?? '-'}</td>
        <td>${i.location}</td>
        <td>${i.currentStock.toStringAsFixed(1)} ${i.unit}</td>
        <td>${i.minimumStock.toStringAsFixed(1)} ${i.unit}</td>
        <td style="color:#dc2626; font-weight:600;">+${i.shortfall.toStringAsFixed(1)}</td>
        <td>${i.vendorName ?? '-'}</td>
        <td>${i.vendorPhone ?? '-'}</td>
        <td><span class="${i.isStockOut ? 'badge-alert' : 'badge-warn'}">${i.isStockOut ? 'DEPLETED' : 'LOW STOCK'}</span></td>
      </tr>
      ''').join('')}
    </tbody>
  </table>

  <div class="page-break"></div>

  <h2>3. Batch Expiry & Risk Traceability (${data.batchExpiryDetails.length})</h2>
  <table>
    <thead>
      <tr>
        <th>Batch Number</th>
        <th>Item Name</th>
        <th>Category</th>
        <th>Expiry Date</th>
        <th>Days Remaining</th>
        <th>Remaining Units</th>
        <th>Unit Price</th>
        <th>Batch Value</th>
        <th>Status</th>
      </tr>
    </thead>
    <tbody>
      ${data.batchExpiryDetails.isEmpty ? '<tr><td colspan="9" style="text-align:center; color:#94a3b8;">No expired or soon-to-expire batches identified.</td></tr>' : data.batchExpiryDetails.map((b) => '''
      <tr>
        <td><strong>${b.batchNumber}</strong></td>
        <td>${b.itemName}</td>
        <td>${b.category}</td>
        <td>${b.expiryDate != null ? DateFormat('dd-MM-yyyy').format(b.expiryDate!) : '-'}</td>
        <td>${b.daysRemaining != null ? (b.daysRemaining! < 0 ? '${b.daysRemaining!.abs()}d ago' : '${b.daysRemaining}d') : '-'}</td>
        <td>${b.remainingQuantity.toStringAsFixed(1)}</td>
        <td>${currency.format(b.unitPrice)}</td>
        <td><strong>${currency.format(b.totalAmount)}</strong></td>
        <td><span class="${b.isExpired ? 'badge-alert' : 'badge-warn'}">${b.urgencyStatus.toUpperCase()}</span></td>
      </tr>
      ''').join('')}
    </tbody>
  </table>

  <h2>4. Stock Movement Audit Ledger (${data.auditLedger.length})</h2>
  <table>
    <thead>
      <tr>
        <th>Timestamp</th>
        <th>Item Name</th>
        <th>Type</th>
        <th>Quantity</th>
        <th>Stock (Before &rarr; After)</th>
        <th>Reason</th>
        <th>Performed By</th>
        <th>Recipient</th>
      </tr>
    </thead>
    <tbody>
      ${data.auditLedger.isEmpty ? '<tr><td colspan="8" style="text-align:center; color:#94a3b8;">No stock transactions recorded in the selected period.</td></tr>' : data.auditLedger.map((tx) => '''
      <tr>
        <td>${DateFormat('dd-MM-yyyy hh:mm a').format(tx.date)}</td>
        <td><strong>${tx.itemName}</strong></td>
        <td><span class="${tx.transactionType.toLowerCase() == 'stock_in' ? 'badge-success' : 'badge-warn'}">${tx.transactionType.toUpperCase()}</span></td>
        <td>${tx.quantity.toStringAsFixed(1)}</td>
        <td>${tx.stockBefore?.toStringAsFixed(1) ?? '-'} &rarr; ${tx.stockAfter?.toStringAsFixed(1) ?? '-'}</td>
        <td>${tx.reason ?? '-'}</td>
        <td>${tx.performedByName ?? '-'}</td>
        <td>${tx.recipientInfo ?? '-'}</td>
      </tr>
      ''').join('')}
    </tbody>
  </table>

  <div class="footer">
    MKES CARE+ Internal Confidential Document • Generated by Admin Reports System
  </div>
</body>
</html>
''';
  }

  /// Exports a styled, printable HTML report that triggers browser/OS Print to PDF.
  static Future<bool> exportInventoryToPrintableHtml({
    required InventoryReportsData data,
    AdminReportsFilter filter = const AdminReportsFilter(),
  }) async {
    final html = generateHtmlContent(data, filter);
    return _launchDataUri(
      content: html,
      mimeType: 'text/html',
      filename: 'MKES_Inventory_Report.html',
    );
  }

  /// Helper to launch Data URI in browser/web/desktop environment.
  static Future<bool> _launchDataUri({
    required String content,
    required String mimeType,
    required String filename,
  }) async {
    try {
      final base64Content = base64Encode(utf8.encode(content));
      final uri =
          Uri.parse('data:$mimeType;charset=utf-8;base64,$base64Content');
      if (await canLaunchUrl(uri)) {
        return await launchUrl(uri);
      } else {
        final plainUri = Uri.dataFromString(
          content,
          mimeType: mimeType,
          encoding: utf8,
        );
        return await launchUrl(plainUri);
      }
    } catch (e) {
      debugPrint('ReportsExportService error launching export: $e');
      return false;
    }
  }

  static String _cleanCsvValue(String value) {
    return value.replaceAll('"', '""');
  }
}
