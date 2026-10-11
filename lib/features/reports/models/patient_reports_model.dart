import '../../patients/models/patient_model.dart';

class PatientTrendPoint {
  final String label;
  final DateTime date;
  final int count;

  const PatientTrendPoint({
    required this.label,
    required this.date,
    required this.count,
  });
}

class PatientReportsData {
  final int totalPatients;
  final int newPatients;
  final int returningPatients;
  final int eyePatients;
  final int dentalPatients;
  final double eyePercentage;
  final double dentalPercentage;
  final List<PatientTrendPoint> registrationTrends;
  final List<PatientModel> recentPatients;

  const PatientReportsData({
    required this.totalPatients,
    required this.newPatients,
    required this.returningPatients,
    required this.eyePatients,
    required this.dentalPatients,
    required this.eyePercentage,
    required this.dentalPercentage,
    required this.registrationTrends,
    required this.recentPatients,
  });

  static const PatientReportsData empty = PatientReportsData(
    totalPatients: 0,
    newPatients: 0,
    returningPatients: 0,
    eyePatients: 0,
    dentalPatients: 0,
    eyePercentage: 0.0,
    dentalPercentage: 0.0,
    registrationTrends: [],
    recentPatients: [],
  );
}
