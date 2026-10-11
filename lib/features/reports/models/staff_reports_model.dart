class StaffPerformanceStat {
  final String staffId;
  final String staffName;
  final String? designation;
  final String? department;
  final int attendanceLogs;
  final int presentDays;
  final int lateDays;
  final int leaveDays;
  final double attendancePercentage;
  final int totalTasks;
  final int completedTasks;
  final int pendingTasks;
  final int overdueTasks;
  final double taskCompletionPercentage;

  const StaffPerformanceStat({
    required this.staffId,
    required this.staffName,
    this.designation,
    this.department,
    required this.attendanceLogs,
    required this.presentDays,
    required this.lateDays,
    required this.leaveDays,
    required this.attendancePercentage,
    required this.totalTasks,
    required this.completedTasks,
    required this.pendingTasks,
    required this.overdueTasks,
    required this.taskCompletionPercentage,
  });
}

class AttendanceTrendPoint {
  final String label;
  final DateTime date;
  final int present;
  final int late;
  final int leave;

  const AttendanceTrendPoint({
    required this.label,
    required this.date,
    required this.present,
    required this.late,
    required this.leave,
  });
}

class StaffReportsData {
  final int totalStaff;
  final int activeStaff;

  // Attendance summary
  final int totalAttendanceLogs;
  final int presentCount;
  final int lateCount;
  final int leaveCount;
  final double overallAttendanceRate;
  final List<AttendanceTrendPoint> attendanceTrends;

  // Task summary
  final int totalTasks;
  final int completedTasks;
  final int pendingTasks;
  final int inProgressTasks;
  final int overdueTasks;
  final double taskCompletionRate;

  // Staff-wise leaderboard / table
  final List<StaffPerformanceStat> staffStats;

  const StaffReportsData({
    required this.totalStaff,
    required this.activeStaff,
    required this.totalAttendanceLogs,
    required this.presentCount,
    required this.lateCount,
    required this.leaveCount,
    required this.overallAttendanceRate,
    required this.attendanceTrends,
    required this.totalTasks,
    required this.completedTasks,
    required this.pendingTasks,
    required this.inProgressTasks,
    required this.overdueTasks,
    required this.taskCompletionRate,
    required this.staffStats,
  });

  static const StaffReportsData empty = StaffReportsData(
    totalStaff: 0,
    activeStaff: 0,
    totalAttendanceLogs: 0,
    presentCount: 0,
    lateCount: 0,
    leaveCount: 0,
    overallAttendanceRate: 0.0,
    attendanceTrends: [],
    totalTasks: 0,
    completedTasks: 0,
    pendingTasks: 0,
    inProgressTasks: 0,
    overdueTasks: 0,
    taskCompletionRate: 0.0,
    staffStats: [],
  );
}
