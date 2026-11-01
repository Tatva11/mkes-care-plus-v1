/// Constants defining the MKES CARE+ physical clinic location and geofence parameters.
abstract final class ClinicLocationConstants {
  /// Target clinic latitude: 18.99110
  static const double clinicLatitude = 18.99110;

  /// Target clinic longitude: 72.838885
  static const double clinicLongitude = 72.838885;

  /// Maximum allowed distance from clinic coordinates for staff access (in metres).
  static const double allowedRadiusMeters = 200.0;

  /// Maximum acceptable GPS accuracy radius (in metres).
  /// Default set to 150.0m to accommodate typical indoor mobile GPS reception in urban clinic environments
  /// while strictly rejecting unreliable cell-tower readings (> 150m).
  static const double maxAcceptableAccuracyMeters = 150.0;

  /// Verification validity duration (freshness window).
  /// Stored verification is considered valid for 15 minutes before requiring re-check.
  static const Duration verificationFreshness = Duration(minutes: 15);

  /// Human-readable physical clinic address.
  static const String clinicAddress =
      'Shop No 13,14, Harharwala Building, S. G. Marg, Chinchpokli East, Lal Baug, Parel, Mumbai, Maharashtra 400012';
}
