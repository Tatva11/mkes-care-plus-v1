class ProcedureLeaderboardItem {
  final String procedureName;
  final String department;
  final int count;
  final double totalRevenue;
  final double averagePrice;

  const ProcedureLeaderboardItem({
    required this.procedureName,
    required this.department,
    required this.count,
    required this.totalRevenue,
    required this.averagePrice,
  });
}

class ProcedureTrendPoint {
  final String label;
  final DateTime date;
  final int eyeCount;
  final int dentalCount;
  final int totalCount;

  const ProcedureTrendPoint({
    required this.label,
    required this.date,
    required this.eyeCount,
    required this.dentalCount,
    required this.totalCount,
  });
}

class ClinicalReportsData {
  final int totalProcedures;
  final int eyeProcedures;
  final int dentalProcedures;
  final double eyePercentage;
  final double dentalPercentage;
  final double totalProceduresValue;

  final List<ProcedureLeaderboardItem> topProcedures;
  final List<ProcedureTrendPoint> procedureTrends;

  const ClinicalReportsData({
    required this.totalProcedures,
    required this.eyeProcedures,
    required this.dentalProcedures,
    required this.eyePercentage,
    required this.dentalPercentage,
    required this.totalProceduresValue,
    required this.topProcedures,
    required this.procedureTrends,
  });

  static const ClinicalReportsData empty = ClinicalReportsData(
    totalProcedures: 0,
    eyeProcedures: 0,
    dentalProcedures: 0,
    eyePercentage: 0.0,
    dentalPercentage: 0.0,
    totalProceduresValue: 0.0,
    topProcedures: [],
    procedureTrends: [],
  );
}
