class DoctorAppointmentStat {
  final String doctorId;
  final String doctorName;
  final String department;
  final int totalAppointments;
  final int completedAppointments;
  final int cancelledAppointments;

  const DoctorAppointmentStat({
    required this.doctorId,
    required this.doctorName,
    required this.department,
    required this.totalAppointments,
    required this.completedAppointments,
    required this.cancelledAppointments,
  });

  double get completionRate => totalAppointments > 0
      ? (completedAppointments / totalAppointments * 100)
      : 0.0;
}

class AppointmentTrendPoint {
  final String label;
  final DateTime date;
  final int total;
  final int completed;
  final int cancelled;

  const AppointmentTrendPoint({
    required this.label,
    required this.date,
    required this.total,
    required this.completed,
    required this.cancelled,
  });
}

class AppointmentReportsData {
  final int totalAppointments;
  final int completedAppointments;
  final int cancelledAppointments;
  final int scheduledAppointments;
  final int inTriageAppointments;
  final double completionRate;
  final double cancellationRate;

  final int eyeAppointments;
  final int dentalAppointments;
  final double eyePercentage;
  final double dentalPercentage;

  final int regularAppointments;
  final int walkInAppointments;
  final int followUpAppointments;

  final List<DoctorAppointmentStat> doctorStats;
  final List<AppointmentTrendPoint> appointmentTrends;

  const AppointmentReportsData({
    required this.totalAppointments,
    required this.completedAppointments,
    required this.cancelledAppointments,
    required this.scheduledAppointments,
    required this.inTriageAppointments,
    required this.completionRate,
    required this.cancellationRate,
    required this.eyeAppointments,
    required this.dentalAppointments,
    required this.eyePercentage,
    required this.dentalPercentage,
    required this.regularAppointments,
    required this.walkInAppointments,
    required this.followUpAppointments,
    required this.doctorStats,
    required this.appointmentTrends,
  });
}
