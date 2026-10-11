import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:intl/intl.dart';
import 'package:supabase_flutter/supabase_flutter.dart';

import '../../../core/providers/supabase_provider.dart';
import '../../billing/models/billing_reports_model.dart';
import '../../billing/repositories/billing_repository.dart';
import '../../patients/models/patient_model.dart';
import '../models/appointment_reports_model.dart';
import '../models/clinical_reports_model.dart';
import '../models/overview_reports_model.dart';
import '../models/patient_reports_model.dart';
import '../models/reports_filter_model.dart';
import '../models/staff_reports_model.dart';

final reportsRepositoryProvider = Provider<ReportsRepository>((ref) {
  final supabase = ref.watch(supabaseProvider);
  final billingRepo = ref.watch(billingRepositoryProvider);
  return ReportsRepository(supabase, billingRepo);
});

class ReportsRepository {
  final SupabaseClient _supabase;
  final BillingRepository _billingRepo;

  ReportsRepository(this._supabase, this._billingRepo);

  /// 1. Fetch Overview snapshot analytics
  Future<OverviewReportsData> fetchOverviewData(AdminReportsFilter filter) async {
    final start = filter.effectiveStartDate;
    final end = filter.effectiveEndDate;
    final dept = filter.department == 'all' ? null : filter.department.toLowerCase();

    // 1. Fetch all patients
    var patientsQuery = _supabase.from('patients').select('id, department, created_at');
    if (dept != null) {
      patientsQuery = patientsQuery.eq('department', dept);
    }
    final patientsRes = await patientsQuery;
    final patientsList = patientsRes as List;

    int totalPatients = patientsList.length;
    int newPatients = 0;
    int eyePatients = 0;
    int dentalPatients = 0;

    for (final p in patientsList) {
      final pDept = (p['department'] as String?)?.toLowerCase();
      if (pDept == 'eye') eyePatients++;
      if (pDept == 'dental') dentalPatients++;

      final createdAt = p['created_at'] != null ? DateTime.tryParse(p['created_at'] as String) : null;
      if (createdAt != null) {
        final afterStart = start == null || createdAt.isAfter(start) || createdAt.isAtSameMomentAs(start);
        final beforeEnd = end == null || createdAt.isBefore(end) || createdAt.isAtSameMomentAs(end);
        if (afterStart && beforeEnd) {
          newPatients++;
        }
      }
    }

    // 2. Fetch appointments in period
    var apptQuery = _supabase.from('appointments').select('id, department, status, appointment_date, created_at');
    if (dept != null) {
      apptQuery = apptQuery.eq('department', dept);
    }
    if (start != null) {
      apptQuery = apptQuery.gte('appointment_date', start.toIso8601String().split('T').first);
    }
    if (end != null) {
      apptQuery = apptQuery.lte('appointment_date', end.toIso8601String().split('T').first);
    }
    final apptRes = await apptQuery;
    final apptList = apptRes as List;

    int totalAppointments = apptList.length;
    int completedAppointments = 0;
    int eyeAppointments = 0;
    int dentalAppointments = 0;

    for (final a in apptList) {
      final aDept = (a['department'] as String?)?.toLowerCase();
      if (aDept == 'eye') eyeAppointments++;
      if (aDept == 'dental') dentalAppointments++;

      final status = (a['status'] as String?)?.toLowerCase();
      if (status == 'completed') completedAppointments++;
    }

    // 3. Fetch billing invoices & items in period
    final invoices = await _billingRepo.fetchInvoicesForReports(
      department: dept,
      startDate: start,
      endDate: end,
    );

    double totalSales = 0.0;
    double totalRevenue = 0.0;
    double totalOutstanding = 0.0;
    double eyeSales = 0.0;
    double dentalSales = 0.0;
    int totalProcedures = 0;
    int eyeProcedures = 0;
    int dentalProcedures = 0;

    // Trend aggregation map by date
    final Map<String, ActivityTrendPoint> trendMap = {};

    for (final inv in invoices) {
      if (inv.isCancelled) continue;
      totalSales += inv.totalAmount;
      totalRevenue += inv.amountPaid;
      totalOutstanding += inv.remainingAmount;

      if (inv.department == 'eye') {
        eyeSales += inv.totalAmount;
      } else if (inv.department == 'dental') {
        dentalSales += inv.totalAmount;
      }

      for (final item in inv.items) {
        totalProcedures += item.quantity;
        if (inv.department == 'eye') {
          eyeProcedures += item.quantity;
        } else if (inv.department == 'dental') {
          dentalProcedures += item.quantity;
        }
      }

      final dateKey = DateFormat('yyyy-MM-dd').format(inv.createdAt);
      if (!trendMap.containsKey(dateKey)) {
        trendMap[dateKey] = ActivityTrendPoint(
          label: DateFormat('dd MMM').format(inv.createdAt),
          date: DateTime(inv.createdAt.year, inv.createdAt.month, inv.createdAt.day),
          patientCount: 0,
          appointmentCount: 0,
          procedureCount: 0,
          salesAmount: 0.0,
        );
      }
      final current = trendMap[dateKey]!;
      trendMap[dateKey] = ActivityTrendPoint(
        label: current.label,
        date: current.date,
        patientCount: current.patientCount,
        appointmentCount: current.appointmentCount,
        procedureCount: current.procedureCount + inv.items.fold(0, (sum, i) => sum + i.quantity),
        salesAmount: current.salesAmount + inv.totalAmount,
      );
    }

    final sortedTrend = trendMap.values.toList()..sort((a, b) => a.date.compareTo(b.date));

    return OverviewReportsData(
      totalPatients: totalPatients,
      newPatients: newPatients,
      totalAppointments: totalAppointments,
      completedAppointments: completedAppointments,
      totalProcedures: totalProcedures,
      totalSales: totalSales,
      totalRevenue: totalRevenue,
      totalOutstanding: totalOutstanding,
      eyePatients: eyePatients,
      dentalPatients: dentalPatients,
      eyeAppointments: eyeAppointments,
      dentalAppointments: dentalAppointments,
      eyeProcedures: eyeProcedures,
      dentalProcedures: dentalProcedures,
      eyeSales: eyeSales,
      dentalSales: dentalSales,
      trendPoints: sortedTrend,
    );
  }

  /// 2. Fetch Patient Reports & Demographics
  Future<PatientReportsData> fetchPatientReports(AdminReportsFilter filter) async {
    final start = filter.effectiveStartDate;
    final end = filter.effectiveEndDate;
    final dept = filter.department == 'all' ? null : filter.department.toLowerCase();

    var query = _supabase.from('patients').select();
    if (dept != null) {
      query = query.eq('department', dept);
    }

    final res = await query.order('created_at', ascending: false);
    final allPatients = (res as List).map((json) => PatientModel.fromJson(json as Map<String, dynamic>)).toList();

    int totalPatients = allPatients.length;
    int newPatients = 0;
    int eyePatients = 0;
    int dentalPatients = 0;

    final Map<String, int> trendMap = {};
    final List<PatientModel> recentInPeriod = [];

    for (final p in allPatients) {
      final pDept = p.department?.toLowerCase();
      if (pDept == 'eye') eyePatients++;
      if (pDept == 'dental') dentalPatients++;

      final createdAt = p.createdAt;
      final afterStart = start == null || createdAt.isAfter(start) || createdAt.isAtSameMomentAs(start);
      final beforeEnd = end == null || createdAt.isBefore(end) || createdAt.isAtSameMomentAs(end);

      if (afterStart && beforeEnd) {
        newPatients++;
        recentInPeriod.add(p);

        final dateKey = DateFormat('yyyy-MM-dd').format(createdAt);
        trendMap[dateKey] = (trendMap[dateKey] ?? 0) + 1;
      }
    }

    // Query returning patients (patients with >1 appointment)
    final returningRes = await _supabase.from('appointments').select('patient_id');
    final Map<String, int> patientVisits = {};
    for (final a in returningRes as List) {
      final pid = a['patient_id'] as String?;
      if (pid != null) {
        patientVisits[pid] = (patientVisits[pid] ?? 0) + 1;
      }
    }
    final returningPatients = patientVisits.values.where((count) => count > 1).length;

    final sortedTrend = trendMap.entries.map((e) {
      final d = DateTime.parse(e.key);
      return PatientTrendPoint(
        label: DateFormat('dd MMM').format(d),
        date: d,
        count: e.value,
      );
    }).toList()
      ..sort((a, b) => a.date.compareTo(b.date));

    final totalCount = totalPatients > 0 ? totalPatients : 1;
    final eyePct = (eyePatients / totalCount) * 100;
    final dentalPct = (dentalPatients / totalCount) * 100;

    return PatientReportsData(
      totalPatients: totalPatients,
      newPatients: newPatients,
      returningPatients: returningPatients,
      eyePatients: eyePatients,
      dentalPatients: dentalPatients,
      eyePercentage: eyePct,
      dentalPercentage: dentalPct,
      registrationTrends: sortedTrend,
      recentPatients: recentInPeriod.take(20).toList(),
    );
  }

  /// 3. Fetch Appointment Reports & Doctor Analytics
  Future<AppointmentReportsData> fetchAppointmentReports(AdminReportsFilter filter) async {
    final start = filter.effectiveStartDate;
    final end = filter.effectiveEndDate;
    final dept = filter.department == 'all' ? null : filter.department.toLowerCase();

    var query = _supabase.from('appointments').select('''
      id,
      patient_id,
      department,
      doctor_id,
      appointment_date,
      appointment_time,
      appointment_type,
      status,
      created_at,
      profiles:doctor_id (
        id,
        full_name,
        designation
      )
    ''');

    if (dept != null) {
      query = query.eq('department', dept);
    }
    if (start != null) {
      query = query.gte('appointment_date', start.toIso8601String().split('T').first);
    }
    if (end != null) {
      query = query.lte('appointment_date', end.toIso8601String().split('T').first);
    }

    final res = await query.order('appointment_date', ascending: true);
    final list = res as List;

    int total = list.length;
    int completed = 0;
    int cancelled = 0;
    int scheduled = 0;
    int inTriage = 0;
    int eye = 0;
    int dental = 0;
    int regular = 0;
    int walkIn = 0;
    int followUp = 0;

    final Map<String, _DoctorAccumulator> doctorMap = {};
    final Map<String, _TrendAccumulator> trendMap = {};

    for (final item in list) {
      final aDept = (item['department'] as String?)?.toLowerCase() ?? 'eye';
      if (aDept == 'eye') eye++;
      if (aDept == 'dental') dental++;

      final status = (item['status'] as String?)?.toLowerCase() ?? 'scheduled';
      if (status == 'completed') completed++;
      if (status == 'cancelled' || status == 'missed') cancelled++;
      if (status == 'scheduled' || status == 'confirmed') scheduled++;
      if (status == 'waiting' || status == 'in_triage' || status == 'in triage') inTriage++;

      final type = (item['appointment_type'] as String?)?.toLowerCase() ?? 'regular';
      if (type == 'walk_in' || type == 'walkin') {
        walkIn++;
      } else if (type == 'follow_up' || type == 'followup') {
        followUp++;
      } else {
        regular++;
      }

      // Doctor breakdown
      final docProfile = item['profiles'] is Map ? item['profiles'] as Map<String, dynamic> : null;
      final docId = (item['doctor_id'] as String?) ?? 'unassigned';
      final docName = docProfile?['full_name'] as String? ?? 'General Consultation';

      if (!doctorMap.containsKey(docId)) {
        doctorMap[docId] = _DoctorAccumulator(
          id: docId,
          name: docName,
          dept: aDept,
        );
      }
      final d = doctorMap[docId]!;
      d.total++;
      if (status == 'completed') d.completed++;
      if (status == 'cancelled' || status == 'missed') d.cancelled++;

      // Daily trend
      final apptDateStr = item['appointment_date'] as String? ?? '';
      if (apptDateStr.isNotEmpty) {
        if (!trendMap.containsKey(apptDateStr)) {
          trendMap[apptDateStr] = _TrendAccumulator(
            dateStr: apptDateStr,
            date: DateTime.tryParse(apptDateStr) ?? DateTime.now(),
          );
        }
        final t = trendMap[apptDateStr]!;
        t.total++;
        if (status == 'completed') t.completed++;
        if (status == 'cancelled' || status == 'missed') t.cancelled++;
      }
    }

    final doctorStats = doctorMap.values.map((d) {
      return DoctorAppointmentStat(
        doctorId: d.id,
        doctorName: d.name,
        department: d.dept,
        totalAppointments: d.total,
        completedAppointments: d.completed,
        cancelledAppointments: d.cancelled,
      );
    }).toList()
      ..sort((a, b) => b.totalAppointments.compareTo(a.totalAppointments));

    final sortedTrend = trendMap.values.map((t) {
      return AppointmentTrendPoint(
        label: DateFormat('dd MMM').format(t.date),
        date: t.date,
        total: t.total,
        completed: t.completed,
        cancelled: t.cancelled,
      );
    }).toList()
      ..sort((a, b) => a.date.compareTo(b.date));

    final compRate = total > 0 ? (completed / total * 100) : 0.0;
    final cancRate = total > 0 ? (cancelled / total * 100) : 0.0;
    final eyePct = total > 0 ? (eye / total * 100) : 0.0;
    final dentalPct = total > 0 ? (dental / total * 100) : 0.0;

    return AppointmentReportsData(
      totalAppointments: total,
      completedAppointments: completed,
      cancelledAppointments: cancelled,
      scheduledAppointments: scheduled,
      inTriageAppointments: inTriage,
      completionRate: compRate,
      cancellationRate: cancRate,
      eyeAppointments: eye,
      dentalAppointments: dental,
      eyePercentage: eyePct,
      dentalPercentage: dentalPct,
      regularAppointments: regular,
      walkInAppointments: walkIn,
      followUpAppointments: followUp,
      doctorStats: doctorStats,
      appointmentTrends: sortedTrend,
    );
  }

  /// 4. Fetch Staff Attendance & Task Reports
  Future<StaffReportsData> fetchStaffReports(AdminReportsFilter filter) async {
    final start = filter.effectiveStartDate;
    final end = filter.effectiveEndDate;

    // 1. Fetch Staff Profiles
    final profilesRes = await _supabase
        .from('profiles')
        .select('id, full_name, designation, department_id, is_active, role')
        .order('full_name', ascending: true);

    final staffProfiles = (profilesRes as List).where((p) => (p['role'] as String?) == 'staff' || (p['role'] as String?) == 'admin').toList();
    final int totalStaff = staffProfiles.length;
    final int activeStaff = staffProfiles.where((p) => p['is_active'] == true).length;

    // 2. Fetch Attendance in date range
    var attQuery = _supabase.from('staff_attendance').select('''
      id,
      staff_id,
      record_date,
      status,
      is_late,
      working_hours
    ''');
    if (start != null) {
      attQuery = attQuery.gte('record_date', start.toIso8601String().split('T').first);
    }
    if (end != null) {
      attQuery = attQuery.lte('record_date', end.toIso8601String().split('T').first);
    }
    final attRes = await attQuery;
    final attList = attRes as List;

    int totalAttendanceLogs = attList.length;
    int presentCount = 0;
    int lateCount = 0;
    int leaveCount = 0;

    final Map<String, _StaffAttAccumulator> staffAttMap = {};
    final Map<String, _AttTrendAccumulator> attTrendMap = {};

    for (final item in attList) {
      final sid = item['staff_id'] as String;
      final status = (item['status'] as String?)?.toLowerCase() ?? 'present';
      final isLate = item['is_late'] as bool? ?? false;

      if (status == 'present') presentCount++;
      if (isLate || status == 'late') lateCount++;
      if (status == 'leave' || status == 'absent') leaveCount++;

      if (!staffAttMap.containsKey(sid)) {
        staffAttMap[sid] = _StaffAttAccumulator();
      }
      final s = staffAttMap[sid]!;
      s.totalLogs++;
      if (status == 'present' || isLate || status == 'late') s.presentDays++;
      if (isLate || status == 'late') s.lateDays++;
      if (status == 'leave' || status == 'absent') s.leaveDays++;

      final dateStr = item['record_date'] as String? ?? '';
      if (dateStr.isNotEmpty) {
        if (!attTrendMap.containsKey(dateStr)) {
          attTrendMap[dateStr] = _AttTrendAccumulator(
            date: DateTime.tryParse(dateStr) ?? DateTime.now(),
          );
        }
        final t = attTrendMap[dateStr]!;
        if (status == 'present') t.present++;
        if (isLate || status == 'late') t.late++;
        if (status == 'leave' || status == 'absent') t.leave++;
      }
    }

    // 3. Fetch Tasks in date range
    var taskQuery = _supabase.from('tasks').select('id, assigned_to, priority, status, due_date, created_at, completed_at');
    if (start != null) {
      taskQuery = taskQuery.gte('created_at', start.toIso8601String());
    }
    if (end != null) {
      taskQuery = taskQuery.lte('created_at', end.toIso8601String());
    }
    final taskRes = await taskQuery;
    final taskList = taskRes as List;

    int totalTasks = taskList.length;
    int completedTasks = 0;
    int pendingTasks = 0;
    int inProgressTasks = 0;
    int overdueTasks = 0;

    final Map<String, _StaffTaskAccumulator> staffTaskMap = {};

    for (final item in taskList) {
      final sid = item['assigned_to'] as String;
      final status = (item['status'] as String?)?.toLowerCase() ?? 'pending';
      final dueDate = item['due_date'] != null ? DateTime.tryParse(item['due_date'] as String) : null;
      final isOverdue = (status != 'completed' && status != 'cancelled') && dueDate != null && dueDate.isBefore(DateTime.now());

      if (status == 'completed') completedTasks++;
      if (status == 'pending') pendingTasks++;
      if (status == 'in_progress') inProgressTasks++;
      if (isOverdue || status == 'overdue') overdueTasks++;

      if (!staffTaskMap.containsKey(sid)) {
        staffTaskMap[sid] = _StaffTaskAccumulator();
      }
      final st = staffTaskMap[sid]!;
      st.total++;
      if (status == 'completed') st.completed++;
      if (status == 'pending' || status == 'in_progress') st.pending++;
      if (isOverdue || status == 'overdue') st.overdue++;
    }

    // Build Staff Performance Stat list
    final List<StaffPerformanceStat> staffStats = [];
    for (final profile in staffProfiles) {
      final sid = profile['id'] as String;
      final name = profile['full_name'] as String? ?? 'Staff';
      final designation = profile['designation'] as String?;
      final att = staffAttMap[sid] ?? _StaffAttAccumulator();
      final task = staffTaskMap[sid] ?? _StaffTaskAccumulator();

      final attPct = att.totalLogs > 0 ? (att.presentDays / att.totalLogs * 100) : 0.0;
      final taskPct = task.total > 0 ? (task.completed / task.total * 100) : 0.0;

      staffStats.add(StaffPerformanceStat(
        staffId: sid,
        staffName: name,
        designation: designation,
        attendanceLogs: att.totalLogs,
        presentDays: att.presentDays,
        lateDays: att.lateDays,
        leaveDays: att.leaveDays,
        attendancePercentage: attPct,
        totalTasks: task.total,
        completedTasks: task.completed,
        pendingTasks: task.pending,
        overdueTasks: task.overdue,
        taskCompletionPercentage: taskPct,
      ));
    }

    final overallAttRate = totalAttendanceLogs > 0 ? ((presentCount + lateCount) / totalAttendanceLogs * 100) : 0.0;
    final taskCompRate = totalTasks > 0 ? (completedTasks / totalTasks * 100) : 0.0;

    final sortedAttTrends = attTrendMap.values.map((t) {
      return AttendanceTrendPoint(
        label: DateFormat('dd MMM').format(t.date),
        date: t.date,
        present: t.present,
        late: t.late,
        leave: t.leave,
      );
    }).toList()
      ..sort((a, b) => a.date.compareTo(b.date));

    return StaffReportsData(
      totalStaff: totalStaff,
      activeStaff: activeStaff,
      totalAttendanceLogs: totalAttendanceLogs,
      presentCount: presentCount,
      lateCount: lateCount,
      leaveCount: leaveCount,
      overallAttendanceRate: overallAttRate,
      attendanceTrends: sortedAttTrends,
      totalTasks: totalTasks,
      completedTasks: completedTasks,
      pendingTasks: pendingTasks,
      inProgressTasks: inProgressTasks,
      overdueTasks: overdueTasks,
      taskCompletionRate: taskCompRate,
      staffStats: staffStats,
    );
  }

  /// 5. Fetch Clinical Procedure Reports
  Future<ClinicalReportsData> fetchClinicalReports(AdminReportsFilter filter) async {
    final start = filter.effectiveStartDate;
    final end = filter.effectiveEndDate;
    final dept = filter.department == 'all' ? null : filter.department.toLowerCase();

    final invoices = await _billingRepo.fetchInvoicesForReports(
      department: dept,
      startDate: start,
      endDate: end,
    );

    int totalProcedures = 0;
    int eyeProcedures = 0;
    int dentalProcedures = 0;
    double totalValue = 0.0;

    final Map<String, _ProcedureAccumulator> procMap = {};
    final Map<String, _ProcTrendAccumulator> trendMap = {};

    for (final inv in invoices) {
      if (inv.isCancelled) continue;

      final dateKey = DateFormat('yyyy-MM-dd').format(inv.createdAt);
      if (!trendMap.containsKey(dateKey)) {
        trendMap[dateKey] = _ProcTrendAccumulator(
          date: DateTime(inv.createdAt.year, inv.createdAt.month, inv.createdAt.day),
        );
      }
      final t = trendMap[dateKey]!;

      for (final item in inv.items) {
        totalProcedures += item.quantity;
        totalValue += item.totalAmount;

        if (inv.department == 'eye') {
          eyeProcedures += item.quantity;
          t.eye += item.quantity;
        } else if (inv.department == 'dental') {
          dentalProcedures += item.quantity;
          t.dental += item.quantity;
        }

        final key = '${inv.department}_${item.serviceName}';
        if (!procMap.containsKey(key)) {
          procMap[key] = _ProcedureAccumulator(
            name: item.serviceName,
            department: inv.department,
          );
        }
        final p = procMap[key]!;
        p.count += item.quantity;
        p.totalRevenue += item.totalAmount;
      }
    }

    final topProcedures = procMap.values.map((p) {
      return ProcedureLeaderboardItem(
        procedureName: p.name,
        department: p.department,
        count: p.count,
        totalRevenue: p.totalRevenue,
        averagePrice: p.count > 0 ? (p.totalRevenue / p.count) : 0.0,
      );
    }).toList()
      ..sort((a, b) => b.count.compareTo(a.count));

    final sortedTrend = trendMap.values.map((t) {
      return ProcedureTrendPoint(
        label: DateFormat('dd MMM').format(t.date),
        date: t.date,
        eyeCount: t.eye,
        dentalCount: t.dental,
        totalCount: t.eye + t.dental,
      );
    }).toList()
      ..sort((a, b) => a.date.compareTo(b.date));

    final totalCount = totalProcedures > 0 ? totalProcedures : 1;
    final eyePct = (eyeProcedures / totalCount) * 100;
    final dentalPct = (dentalProcedures / totalCount) * 100;

    return ClinicalReportsData(
      totalProcedures: totalProcedures,
      eyeProcedures: eyeProcedures,
      dentalProcedures: dentalProcedures,
      eyePercentage: eyePct,
      dentalPercentage: dentalPct,
      totalProceduresValue: totalValue,
      topProcedures: topProcedures,
      procedureTrends: sortedTrend,
    );
  }

  /// 6. Fetch Financial Reports (Reusing Sprint 7 billing data)
  Future<BillingReportsData> fetchFinancialReports(AdminReportsFilter filter) async {
    final invoices = await _billingRepo.fetchInvoicesForReports(
      department: filter.department == 'all' ? null : filter.department.toLowerCase(),
      startDate: filter.effectiveStartDate,
      endDate: filter.effectiveEndDate,
    );

    return BillingReportsData.fromInvoices(
      invoices: invoices,
      aggregationMode: ReportAggregationMode.daily,
    );
  }
}

class _DoctorAccumulator {
  final String id;
  final String name;
  final String dept;
  int total = 0;
  int completed = 0;
  int cancelled = 0;

  _DoctorAccumulator({
    required this.id,
    required this.name,
    required this.dept,
  });
}

class _TrendAccumulator {
  final String dateStr;
  final DateTime date;
  int total = 0;
  int completed = 0;
  int cancelled = 0;

  _TrendAccumulator({
    required this.dateStr,
    required this.date,
  });
}

class _StaffAttAccumulator {
  int totalLogs = 0;
  int presentDays = 0;
  int lateDays = 0;
  int leaveDays = 0;
}

class _StaffTaskAccumulator {
  int total = 0;
  int completed = 0;
  int pending = 0;
  int overdue = 0;
}

class _AttTrendAccumulator {
  final DateTime date;
  int present = 0;
  int late = 0;
  int leave = 0;

  _AttTrendAccumulator({required this.date});
}

class _ProcedureAccumulator {
  final String name;
  final String department;
  int count = 0;
  double totalRevenue = 0.0;

  _ProcedureAccumulator({
    required this.name,
    required this.department,
  });
}

class _ProcTrendAccumulator {
  final DateTime date;
  int eye = 0;
  int dental = 0;

  _ProcTrendAccumulator({required this.date});
}
