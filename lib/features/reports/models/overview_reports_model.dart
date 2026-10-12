class ActivityTrendPoint {
  final String label;
  final DateTime date;
  final int patientCount;
  final int appointmentCount;
  final int procedureCount;
  final double salesAmount;

  const ActivityTrendPoint({
    required this.label,
    required this.date,
    required this.patientCount,
    required this.appointmentCount,
    required this.procedureCount,
    required this.salesAmount,
  });
}

class OverviewReportsData {
  final int totalPatients;
  final int newPatients;
  final int totalAppointments;
  final int completedAppointments;
  final int totalProcedures;
  final double totalSales;
  final double totalRevenue;
  final double totalOutstanding;

  final int eyePatients;
  final int dentalPatients;
  final int eyeAppointments;
  final int dentalAppointments;
  final int eyeProcedures;
  final int dentalProcedures;
  final double eyeSales;
  final double dentalSales;

  final double totalInventoryValuation;
  final int lowStockCount;
  final int expiredBatchesCount;

  final List<ActivityTrendPoint> trendPoints;

  const OverviewReportsData({
    required this.totalPatients,
    required this.newPatients,
    required this.totalAppointments,
    required this.completedAppointments,
    required this.totalProcedures,
    required this.totalSales,
    required this.totalRevenue,
    required this.totalOutstanding,
    required this.eyePatients,
    required this.dentalPatients,
    required this.eyeAppointments,
    required this.dentalAppointments,
    required this.eyeProcedures,
    required this.dentalProcedures,
    required this.eyeSales,
    required this.dentalSales,
    this.totalInventoryValuation = 0.0,
    this.lowStockCount = 0,
    this.expiredBatchesCount = 0,
    required this.trendPoints,
  });

  double get eyePercentage =>
      totalPatients > 0 ? (eyePatients / totalPatients * 100) : 0.0;
  double get dentalPercentage =>
      totalPatients > 0 ? (dentalPatients / totalPatients * 100) : 0.0;
}
