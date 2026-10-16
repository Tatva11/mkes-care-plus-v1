import 'package:flutter/foundation.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:intl/intl.dart';
import 'package:supabase_flutter/supabase_flutter.dart';

import '../../../core/providers/supabase_provider.dart';
import '../../billing/models/billing_reports_model.dart';
import '../../billing/repositories/billing_repository.dart';
import '../../inventory/models/inventory_item.dart';
import '../../inventory/repositories/department_inventory_repository.dart';
import '../../inventory/repositories/inventory_repository.dart';
import '../../patients/models/patient_model.dart';
import '../models/appointment_reports_model.dart';
import '../models/clinical_reports_model.dart';
import '../models/inventory_reports_model.dart';
import '../models/overview_reports_model.dart';
import '../models/patient_reports_model.dart';
import '../models/reports_filter_model.dart';
import '../models/staff_reports_model.dart';

final reportsRepositoryProvider = Provider<ReportsRepository>((ref) {
  final supabase = ref.watch(supabaseProvider);
  final billingRepo = ref.watch(billingRepositoryProvider);
  final inventoryRepo = ref.watch(inventoryRepositoryProvider);
  final deptInventoryRepo = ref.watch(departmentInventoryRepositoryProvider);
  return ReportsRepository(
      supabase, billingRepo, inventoryRepo, deptInventoryRepo);
});

class ReportsRepository {
  final SupabaseClient _supabase;
  final BillingRepository _billingRepo;
  final InventoryRepository _inventoryRepo;
  final DepartmentInventoryRepository _deptInventoryRepo;

  ReportsRepository(
    this._supabase,
    this._billingRepo,
    this._inventoryRepo,
    this._deptInventoryRepo,
  );

  /// 1. Fetch Overview snapshot analytics
  Future<OverviewReportsData> fetchOverviewData(
      AdminReportsFilter filter) async {
    final start = filter.effectiveStartDate;
    final end = filter.effectiveEndDate;
    final dept =
        filter.department == 'all' ? null : filter.department.toLowerCase();

    // 1. Fetch all patients
    var patientsQuery =
        _supabase.from('patients').select('id, department, created_at');
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

      final createdAt = p['created_at'] != null
          ? DateTime.tryParse(p['created_at'] as String)
          : null;
      if (createdAt != null) {
        final afterStart = start == null ||
            createdAt.isAfter(start) ||
            createdAt.isAtSameMomentAs(start);
        final beforeEnd = end == null ||
            createdAt.isBefore(end) ||
            createdAt.isAtSameMomentAs(end);
        if (afterStart && beforeEnd) {
          newPatients++;
        }
      }
    }

    // 2. Fetch appointments in period
    var apptQuery = _supabase
        .from('appointments')
        .select('id, department, status, appointment_date, created_at');
    if (dept != null) {
      apptQuery = apptQuery.eq('department', dept);
    }
    if (start != null) {
      apptQuery = apptQuery.gte(
          'appointment_date', start.toIso8601String().split('T').first);
    }
    if (end != null) {
      apptQuery = apptQuery.lte(
          'appointment_date', end.toIso8601String().split('T').first);
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
          date: DateTime(
              inv.createdAt.year, inv.createdAt.month, inv.createdAt.day),
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
        procedureCount: current.procedureCount +
            inv.items.fold(0, (sum, i) => sum + i.quantity),
        salesAmount: current.salesAmount + inv.totalAmount,
      );
    }

    final sortedTrend = trendMap.values.toList()
      ..sort((a, b) => a.date.compareTo(b.date));

    // Inventory metrics for overview
    double totalInventoryValuation = 0.0;
    int lowStockCount = 0;
    int expiredBatchesCount = 0;
    try {
      final items = await _inventoryRepo.getInventoryItems();
      final deptItems = await _deptInventoryRepo.fetchDepartmentInventory();
      final itemMap = {for (final i in items) i.id: i};

      if (dept == null) {
        for (final item in items) {
          final price = item.price ?? 0.0;
          final cStock = item.currentStock;
          totalInventoryValuation += cStock * price;
          if (cStock <= (item.minimumStock ?? 5.0)) {
            lowStockCount++;
          }
          if (item.batches != null) {
            final now = DateTime.now();
            for (final b in item.batches!) {
              if (b.hasRemainingStock &&
                  b.expiryDate != null &&
                  b.expiryDate!.isBefore(now)) {
                expiredBatchesCount++;
              }
            }
          }
        }

        for (final d in deptItems) {
          final price = itemMap[d.inventoryId]?.price ?? 0.0;
          totalInventoryValuation += d.quantity * price;
          if (d.isLowStock) {
            lowStockCount++;
          }
        }
      } else {
        for (final d in deptItems) {
          final dName = d.departmentName.toLowerCase();
          if (dName.contains(dept)) {
            final price = itemMap[d.inventoryId]?.price ?? 0.0;
            totalInventoryValuation += d.quantity * price;
            if (d.isLowStock || d.quantity <= d.minimumStock) {
              lowStockCount++;
            }
          }
        }

        final now = DateTime.now();
        for (final item in items) {
          final itemDept = item.department?.toLowerCase();
          if (itemDept == dept) {
            if (item.batches != null) {
              for (final b in item.batches!) {
                if (b.hasRemainingStock &&
                    b.expiryDate != null &&
                    b.expiryDate!.isBefore(now)) {
                  expiredBatchesCount++;
                }
              }
            }
          }
        }
      }
    } catch (_) {}

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
      totalInventoryValuation: totalInventoryValuation,
      lowStockCount: lowStockCount,
      expiredBatchesCount: expiredBatchesCount,
      trendPoints: sortedTrend,
    );
  }

  /// 2. Fetch Patient Reports & Demographics
  Future<PatientReportsData> fetchPatientReports(
      AdminReportsFilter filter) async {
    final start = filter.effectiveStartDate;
    final end = filter.effectiveEndDate;
    final dept =
        filter.department == 'all' ? null : filter.department.toLowerCase();

    var query = _supabase.from('patients').select();
    if (dept != null) {
      query = query.eq('department', dept);
    }

    final res = await query.order('created_at', ascending: false);
    final allPatients = (res as List)
        .map((json) => PatientModel.fromJson(json as Map<String, dynamic>))
        .toList();

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
      final afterStart = start == null ||
          createdAt.isAfter(start) ||
          createdAt.isAtSameMomentAs(start);
      final beforeEnd = end == null ||
          createdAt.isBefore(end) ||
          createdAt.isAtSameMomentAs(end);

      if (afterStart && beforeEnd) {
        newPatients++;
        recentInPeriod.add(p);

        final dateKey = DateFormat('yyyy-MM-dd').format(createdAt);
        trendMap[dateKey] = (trendMap[dateKey] ?? 0) + 1;
      }
    }

    // Query returning patients (patients with >1 appointment)
    final returningRes =
        await _supabase.from('appointments').select('patient_id');
    final Map<String, int> patientVisits = {};
    for (final a in returningRes as List) {
      final pid = a['patient_id'] as String?;
      if (pid != null) {
        patientVisits[pid] = (patientVisits[pid] ?? 0) + 1;
      }
    }
    final returningPatients =
        patientVisits.values.where((count) => count > 1).length;

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
  Future<AppointmentReportsData> fetchAppointmentReports(
      AdminReportsFilter filter) async {
    final start = filter.effectiveStartDate;
    final end = filter.effectiveEndDate;
    final dept =
        filter.department == 'all' ? null : filter.department.toLowerCase();

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
      query = query.gte(
          'appointment_date', start.toIso8601String().split('T').first);
    }
    if (end != null) {
      query =
          query.lte('appointment_date', end.toIso8601String().split('T').first);
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
      if (status == 'waiting' || status == 'in_triage' || status == 'in triage') {
        inTriage++;
      }

      final type =
          (item['appointment_type'] as String?)?.toLowerCase() ?? 'regular';
      if (type == 'walk_in' || type == 'walkin') {
        walkIn++;
      } else if (type == 'follow_up' || type == 'followup') {
        followUp++;
      } else {
        regular++;
      }

      // Doctor breakdown
      final docProfile = item['profiles'] is Map
          ? item['profiles'] as Map<String, dynamic>
          : null;
      final docId = (item['doctor_id'] as String?) ?? 'unassigned';
      final docName =
          docProfile?['full_name'] as String? ?? 'General Consultation';

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

    final staffProfiles = (profilesRes as List)
        .where((p) => (p['role'] as String?) == 'staff')
        .toList();
    final int totalStaff = staffProfiles.length;
    final int activeStaff =
        staffProfiles.where((p) => p['is_active'] == true).length;

    final Set<String> eligibleStaffIds =
        staffProfiles.map((p) => p['id'] as String).toSet();

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
      attQuery =
          attQuery.gte('record_date', start.toIso8601String().split('T').first);
    }
    if (end != null) {
      attQuery =
          attQuery.lte('record_date', end.toIso8601String().split('T').first);
    }
    final attRes = await attQuery;
    final attList = (attRes as List)
        .where((item) => eligibleStaffIds.contains(item['staff_id']))
        .toList();

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
    var taskQuery = _supabase.from('tasks').select(
        'id, assigned_to, priority, status, due_date, created_at, completed_at');
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
      final dueDate = item['due_date'] != null
          ? DateTime.tryParse(item['due_date'] as String)
          : null;
      final isOverdue = (status != 'completed' && status != 'cancelled') &&
          dueDate != null &&
          dueDate.isBefore(DateTime.now());

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

      final attPct =
          att.totalLogs > 0 ? (att.presentDays / att.totalLogs * 100) : 0.0;
      final taskPct =
          task.total > 0 ? (task.completed / task.total * 100) : 0.0;

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

    final overallAttRate = totalAttendanceLogs > 0
        ? ((presentCount + lateCount) / totalAttendanceLogs * 100)
        : 0.0;
    final taskCompRate =
        totalTasks > 0 ? (completedTasks / totalTasks * 100) : 0.0;

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
  Future<ClinicalReportsData> fetchClinicalReports(
      AdminReportsFilter filter) async {
    final start = filter.effectiveStartDate;
    final end = filter.effectiveEndDate;
    final dept =
        filter.department == 'all' ? null : filter.department.toLowerCase();

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
          date: DateTime(
              inv.createdAt.year, inv.createdAt.month, inv.createdAt.day),
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
  Future<BillingReportsData> fetchFinancialReports(
      AdminReportsFilter filter) async {
    final invoices = await _billingRepo.fetchInvoicesForReports(
      department:
          filter.department == 'all' ? null : filter.department.toLowerCase(),
      startDate: filter.effectiveStartDate,
      endDate: filter.effectiveEndDate,
    );

    return BillingReportsData.fromInvoices(
      invoices: invoices,
      aggregationMode: ReportAggregationMode.daily,
    );
  }

  /// 7. Fetch Inventory & Stock Reports (Sprint 8 Phase 8.2)
  Future<InventoryReportsData> fetchInventoryReports(
      AdminReportsFilter filter) async {
    final start = filter.effectiveStartDate;
    final end = filter.effectiveEndDate;
    final dept =
        filter.department == 'all' ? null : filter.department.toLowerCase();

    // 1. Fetch catalog items and department allocations
    final allItems = await _inventoryRepo.getInventoryItems();
    final allDeptItems = await _deptInventoryRepo.fetchDepartmentInventory();

    final itemMap = {for (final item in allItems) item.id: item};

    // Filter items if specific department chosen
    final List<InventoryItem> relevantItems;
    if (dept == null) {
      relevantItems = allItems;
    } else {
      relevantItems = allItems.where((i) {
        final itemDept = i.department?.toLowerCase();
        return itemDept == dept || itemDept == 'all' || itemDept == null;
      }).toList();
    }

    final int totalCatalogItems = relevantItems.length;
    final int activeItemsCount = relevantItems.where((i) => i.isActive).length;

    // 2. Valuation calculation (Preventing double-counting)
    // Central stock + Eye department allocated stock + Dental department allocated stock
    double centralValuation = 0.0;
    double centralUnits = 0.0;
    for (final item in relevantItems) {
      final unitPrice = item.price ?? 0.0;
      centralValuation += item.currentStock * unitPrice;
      centralUnits += item.currentStock;
    }

    double eyeValuation = 0.0;
    double eyeUnits = 0.0;
    double dentalValuation = 0.0;
    double dentalUnits = 0.0;

    for (final d in allDeptItems) {
      final dName = d.departmentName.toLowerCase();
      final unitPrice = itemMap[d.inventoryId]?.price ?? 0.0;
      if (dName.contains('eye')) {
        eyeValuation += d.quantity * unitPrice;
        eyeUnits += d.quantity;
      } else if (dName.contains('dental')) {
        dentalValuation += d.quantity * unitPrice;
        dentalUnits += d.quantity;
      }
    }

    // Adjust for department filter if applied
    double totalValuation = 0.0;
    double totalUnits = 0.0;
    if (dept == 'eye') {
      totalValuation = eyeValuation;
      totalUnits = eyeUnits;
    } else if (dept == 'dental') {
      totalValuation = dentalValuation;
      totalUnits = dentalUnits;
    } else {
      totalValuation = centralValuation + eyeValuation + dentalValuation;
      totalUnits = centralUnits + eyeUnits + dentalUnits;
    }

    // 3. Category-wise valuation
    final Map<String, _CatStatAccumulator> catMap = {};
    for (final item in relevantItems) {
      final cat = item.category.trim().isEmpty ? 'General' : item.category;
      final acc =
          catMap.putIfAbsent(cat, () => _CatStatAccumulator(category: cat));
      acc.itemCount++;
      final uPrice = item.price ?? 0.0;
      if (dept == null || dept == 'all') {
        acc.totalUnits += item.currentStock;
        acc.totalValuation += item.currentStock * uPrice;
      }
    }

    for (final d in allDeptItems) {
      final dName = d.departmentName.toLowerCase();
      if (dept != null && !dName.contains(dept)) continue;
      final parent = itemMap[d.inventoryId];
      final cat = (parent?.category ?? d.itemCategory ?? 'General').trim();
      final safeCat = cat.isEmpty ? 'General' : cat;
      final acc = catMap.putIfAbsent(
          safeCat, () => _CatStatAccumulator(category: safeCat));
      final uPrice = parent?.price ?? 0.0;
      acc.totalUnits += d.quantity;
      acc.totalValuation += d.quantity * uPrice;
    }

    final List<CategoryValuationStat> categoryValuations =
        catMap.values.map((c) {
      final pct =
          totalValuation > 0 ? (c.totalValuation / totalValuation * 100) : 0.0;
      return CategoryValuationStat(
        category: c.category,
        itemCount: c.itemCount,
        totalUnits: c.totalUnits,
        totalValuation: c.totalValuation,
        percentage: pct,
      );
    }).toList()
          ..sort((a, b) => b.totalValuation.compareTo(a.totalValuation));

    // 4. Low-Stock & Reordering
    final List<LowStockItemStat> lowStockList = [];
    int centralLowStockCount = 0;
    int deptLowStockCount = 0;
    int stockOutCount = 0;

    // Central store check
    if (dept == null || dept == 'all') {
      for (final item in relevantItems) {
        final minStock = item.minimumStock ?? 5.0;
        final isStockOut = item.currentStock <= 0;
        final isLow = item.currentStock <= minStock;

        if (isStockOut) stockOutCount++;
        if (isLow) centralLowStockCount++;

        if (isLow) {
          final shortfall = (minStock - item.currentStock) > 0
              ? (minStock - item.currentStock)
              : 0.0;
          lowStockList.add(LowStockItemStat(
            itemId: item.id,
            itemName: item.name,
            sku: item.sku,
            unit: item.unit,
            location: 'Central Store',
            currentStock: item.currentStock,
            minimumStock: minStock,
            shortfall: shortfall,
            vendorName: item.vendorName,
            vendorPhone: item.vendorPhone,
            lastPrice: item.price,
            isStockOut: isStockOut,
          ));
        }
      }
    }

    // Department-level check
    for (final d in allDeptItems) {
      final dName = d.departmentName.toLowerCase();
      if (dept != null && !dName.contains(dept)) continue;

      final isStockOut = d.quantity <= 0;
      final isLow = d.isLowStock || d.quantity <= d.minimumStock;
      if (isStockOut) stockOutCount++;
      if (isLow) deptLowStockCount++;

      if (isLow) {
        final parent = itemMap[d.inventoryId];
        final shortfall = (d.minimumStock - d.quantity) > 0
            ? (d.minimumStock - d.quantity)
            : 0.0;
        final loc = dName.contains('eye')
            ? 'Eye Clinic'
            : (dName.contains('dental') ? 'Dental Clinic' : d.departmentName);

        lowStockList.add(LowStockItemStat(
          itemId: d.inventoryId,
          itemName: d.itemName,
          sku: d.itemSku,
          unit: d.itemUnit,
          location: loc,
          currentStock: d.quantity,
          minimumStock: d.minimumStock,
          shortfall: shortfall,
          vendorName: parent?.vendorName,
          vendorPhone: parent?.vendorPhone,
          lastPrice: parent?.price,
          isStockOut: isStockOut,
        ));
      }
    }

    // Sort: Stockouts first, then highest shortfall
    lowStockList.sort((a, b) {
      if (a.isStockOut != b.isStockOut) {
        return a.isStockOut ? -1 : 1;
      }
      return b.shortfall.compareTo(a.shortfall);
    });

    // 5. Expiry Analytics (Batches)
    final now = DateTime.now();
    final List<BatchExpiryStat> batchExpiryDetails = [];
    int expiredBatchesCount = 0;
    double expiredValueLost = 0.0;
    int expiring30DaysCount = 0;
    double expiring30DaysValue = 0.0;
    int expiring60DaysCount = 0;
    double expiring60DaysValue = 0.0;
    int expiring90DaysCount = 0;
    double expiring90DaysValue = 0.0;

    for (final item in relevantItems) {
      final batches = item.batches;
      if (batches != null && batches.isNotEmpty) {
        for (final b in batches) {
          if (!b.hasRemainingStock) continue;
          final expDate = b.expiryDate;
          final uPrice = b.unitPrice > 0 ? b.unitPrice : (item.price ?? 0.0);
          final batchValue = b.remainingQuantity * uPrice;

          int? daysRemaining;
          String status = 'safe';
          if (expDate != null) {
            daysRemaining = expDate.difference(now).inDays;
            if (daysRemaining < 0) {
              status = 'expired';
              expiredBatchesCount++;
              expiredValueLost += batchValue;
            } else if (daysRemaining <= 30) {
              status = '30days';
              expiring30DaysCount++;
              expiring30DaysValue += batchValue;
            } else if (daysRemaining <= 60) {
              status = '60days';
              expiring60DaysCount++;
              expiring60DaysValue += batchValue;
            } else if (daysRemaining <= 90) {
              status = '90days';
              expiring90DaysCount++;
              expiring90DaysValue += batchValue;
            }
          }

          if (status != 'safe') {
            batchExpiryDetails.add(BatchExpiryStat(
              batchId: b.id,
              batchNumber: b.batchNumber,
              itemId: item.id,
              itemName: item.name,
              category: item.category,
              expiryDate: expDate,
              daysRemaining: daysRemaining,
              remainingQuantity: b.remainingQuantity,
              unitPrice: uPrice,
              totalAmount: batchValue,
              urgencyStatus: status,
            ));
          }
        }
      } else if (item.expiryDate != null && item.currentStock > 0) {
        final expDate = item.expiryDate!;
        final daysRemaining = expDate.difference(now).inDays;
        final uPrice = item.price ?? 0.0;
        final totalVal = item.currentStock * uPrice;
        String status = 'safe';
        if (daysRemaining < 0) {
          status = 'expired';
          expiredBatchesCount++;
          expiredValueLost += totalVal;
        } else if (daysRemaining <= 30) {
          status = '30days';
          expiring30DaysCount++;
          expiring30DaysValue += totalVal;
        } else if (daysRemaining <= 60) {
          status = '60days';
          expiring60DaysCount++;
          expiring60DaysValue += totalVal;
        } else if (daysRemaining <= 90) {
          status = '90days';
          expiring90DaysCount++;
          expiring90DaysValue += totalVal;
        }

        if (status != 'safe') {
          batchExpiryDetails.add(BatchExpiryStat(
            batchId: 'item-${item.id}',
            batchNumber: 'N/A',
            itemId: item.id,
            itemName: item.name,
            category: item.category,
            expiryDate: expDate,
            daysRemaining: daysRemaining,
            remainingQuantity: item.currentStock,
            unitPrice: uPrice,
            totalAmount: totalVal,
            urgencyStatus: status,
          ));
        }
      }
    }

    batchExpiryDetails.sort((a, b) {
      final dayA = a.daysRemaining ?? 9999;
      final dayB = b.daysRemaining ?? 9999;
      return dayA.compareTo(dayB);
    });

    final double totalAtRiskValue = expiredValueLost +
        expiring30DaysValue +
        expiring60DaysValue +
        expiring90DaysValue;

    // 6. Stock Movement, Trends & Audit Ledger
    double totalStockInUnits = 0.0;
    double totalStockInValue = 0.0;
    double totalStockOutUnits = 0.0;
    double totalStockOutValue = 0.0;

    final Map<String, _StockTrendAccumulator> trendMap = {};
    final Map<String, _ReasonAccumulator> reasonMap = {};
    final Map<String, _FastMovingAccumulator> fastMovingMap = {};
    final List<InventoryAuditEntry> auditList = [];

    try {
      final txnQuery = _supabase.from('inventory_transactions').select(
          '*, profiles!performed_by(full_name), patients(name, patient_number), vendors(id, name, phone)');

      final txnsRes = await txnQuery.order('created_at', ascending: false);
      final txnsList = (txnsRes as List).cast<Map<String, dynamic>>();

      for (final raw in txnsList) {
        final createdAtStr = raw['created_at'] as String?;
        final dt =
            createdAtStr != null ? DateTime.tryParse(createdAtStr) : null;
        if (dt == null) continue;

        if (start != null && dt.isBefore(start)) continue;
        if (end != null && dt.isAfter(end)) continue;

        final invId = (raw['inventory_id'] ?? '').toString();
        final parentItem = itemMap[invId];

        if (dept != null && parentItem != null) {
          final pDept = parentItem.department?.toLowerCase();
          if (pDept != null && pDept != dept && pDept != 'all') {
            continue;
          }
        }

        final tType =
            (raw['transaction_type'] as String? ?? 'stock_out').toLowerCase();
        final qty = (raw['quantity'] as num?)?.toDouble() ?? 0.0;
        final uPrice = (raw['unit_price'] as num?)?.toDouble() ??
            (parentItem?.price ?? 0.0);
        final tAmount =
            (raw['total_amount'] as num?)?.toDouble() ?? (qty * uPrice);
        final reason = (raw['reason'] as String?)?.trim() ?? 'Unspecified';
        final remarks = raw['remarks'] as String?;
        final stockBefore = (raw['stock_before'] as num?)?.toDouble();
        final stockAfter = (raw['stock_after'] as num?)?.toDouble();

        final performedByName =
            (raw['profiles'] as Map<String, dynamic>?)?['full_name'] as String?;
        final patientName =
            (raw['patients'] as Map<String, dynamic>?)?['name'] as String?;
        final patientNum = (raw['patients']
            as Map<String, dynamic>?)?['patient_number'] as String?;
        final vendorName =
            (raw['vendors'] as Map<String, dynamic>?)?['name'] as String?;

        String? recipientInfo;
        if (patientName != null && patientName.isNotEmpty) {
          recipientInfo =
              'Patient: $patientName${patientNum != null ? ' ($patientNum)' : ''}';
        } else if (vendorName != null && vendorName.isNotEmpty) {
          recipientInfo = 'Vendor: $vendorName';
        }

        final itemName =
            parentItem?.name ?? (raw['item_name'] as String? ?? 'Unknown Item');

        if (tType == 'stock_in') {
          totalStockInUnits += qty;
          totalStockInValue += tAmount;
        } else {
          totalStockOutUnits += qty;
          totalStockOutValue += tAmount;

          final fastAcc = fastMovingMap.putIfAbsent(
            invId,
            () => _FastMovingAccumulator(
              itemId: invId,
              itemName: itemName,
              category: parentItem?.category ?? 'General',
            ),
          );
          fastAcc.totalUnits += qty;
          fastAcc.totalValue += tAmount;
          fastAcc.count++;
        }

        final dateKey = DateFormat('yyyy-MM-dd').format(dt);
        final trendAcc = trendMap.putIfAbsent(
          dateKey,
          () => _StockTrendAccumulator(
            label: DateFormat('dd MMM').format(dt),
            date: DateTime(dt.year, dt.month, dt.day),
          ),
        );
        if (tType == 'stock_in') {
          trendAcc.stockInUnits += qty;
          trendAcc.stockInValue += tAmount;
        } else {
          trendAcc.stockOutUnits += qty;
          trendAcc.stockOutValue += tAmount;
        }

        final reasonAcc = reasonMap.putIfAbsent(
          reason,
          () => _ReasonAccumulator(
              reason: reason, isStockIn: tType == 'stock_in'),
        );
        reasonAcc.count++;
        reasonAcc.units += qty;
        reasonAcc.value += tAmount;

        auditList.add(InventoryAuditEntry(
          id: (raw['id'] ?? '').toString(),
          date: dt,
          itemName: itemName,
          transactionType: tType,
          quantity: qty,
          stockBefore: stockBefore,
          stockAfter: stockAfter,
          reason: reason,
          performedByName: performedByName,
          recipientInfo: recipientInfo,
          remarks: remarks,
          totalAmount: tAmount,
        ));
      }
    } catch (e) {
      debugPrint(
          'ReportsRepository.fetchInventoryReports transactions error: $e');
    }

    final sortedTrends = trendMap.values
        .map((t) => StockMovementTrendPoint(
              label: t.label,
              date: t.date,
              stockInUnits: t.stockInUnits,
              stockOutUnits: t.stockOutUnits,
              stockInValue: t.stockInValue,
              stockOutValue: t.stockOutValue,
            ))
        .toList()
      ..sort((a, b) => a.date.compareTo(b.date));

    final sortedReasons = reasonMap.values
        .map((r) => MovementReasonStat(
              reason: r.reason,
              transactionCount: r.count,
              totalUnits: r.units,
              totalValue: r.value,
              isStockIn: r.isStockIn,
            ))
        .toList()
      ..sort((a, b) => b.totalUnits.compareTo(a.totalUnits));

    final sortedFastMoving = fastMovingMap.values
        .map((f) => FastMovingItemStat(
              itemId: f.itemId,
              itemName: f.itemName,
              category: f.category,
              totalConsumedUnits: f.totalUnits,
              totalConsumedValue: f.totalValue,
              transactionCount: f.count,
            ))
        .toList()
      ..sort((a, b) => b.totalConsumedUnits.compareTo(a.totalConsumedUnits));

    auditList.sort((a, b) => b.date.compareTo(a.date));

    return InventoryReportsData(
      totalCatalogItems: totalCatalogItems,
      activeItemsCount: activeItemsCount,
      centralValuation: centralValuation,
      eyeValuation: eyeValuation,
      dentalValuation: dentalValuation,
      totalValuation: totalValuation,
      centralUnits: centralUnits,
      eyeUnits: eyeUnits,
      dentalUnits: dentalUnits,
      totalUnits: totalUnits,
      categoryValuations: categoryValuations,
      centralLowStockCount: centralLowStockCount,
      departmentLowStockCount: deptLowStockCount,
      stockOutCount: stockOutCount,
      lowStockItems: lowStockList,
      expiredBatchesCount: expiredBatchesCount,
      expiredValueLost: expiredValueLost,
      expiring30DaysCount: expiring30DaysCount,
      expiring30DaysValue: expiring30DaysValue,
      expiring60DaysCount: expiring60DaysCount,
      expiring60DaysValue: expiring60DaysValue,
      expiring90DaysCount: expiring90DaysCount,
      expiring90DaysValue: expiring90DaysValue,
      totalAtRiskValue: totalAtRiskValue,
      batchExpiryDetails: batchExpiryDetails,
      totalStockInUnits: totalStockInUnits,
      totalStockInValue: totalStockInValue,
      totalStockOutUnits: totalStockOutUnits,
      totalStockOutValue: totalStockOutValue,
      movementTrends: sortedTrends,
      movementReasons: sortedReasons,
      fastMovingItems: sortedFastMoving,
      auditLedger: auditList,
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

class _CatStatAccumulator {
  final String category;
  int itemCount = 0;
  double totalUnits = 0.0;
  double totalValuation = 0.0;

  _CatStatAccumulator({required this.category});
}

class _StockTrendAccumulator {
  final String label;
  final DateTime date;
  double stockInUnits = 0.0;
  double stockOutUnits = 0.0;
  double stockInValue = 0.0;
  double stockOutValue = 0.0;

  _StockTrendAccumulator({required this.label, required this.date});
}

class _ReasonAccumulator {
  final String reason;
  final bool isStockIn;
  int count = 0;
  double units = 0.0;
  double value = 0.0;

  _ReasonAccumulator({required this.reason, required this.isStockIn});
}

class _FastMovingAccumulator {
  final String itemId;
  final String itemName;
  final String category;
  double totalUnits = 0.0;
  double totalValue = 0.0;
  int count = 0;

  _FastMovingAccumulator({
    required this.itemId,
    required this.itemName,
    required this.category,
  });
}
