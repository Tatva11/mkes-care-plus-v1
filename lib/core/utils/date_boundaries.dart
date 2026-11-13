/// Shared utility functions for calculating local calendar day boundaries and
/// scoping dashboard metrics consistently to the current local calendar day.
class DateBoundaries {
  DateBoundaries._();

  /// Start of day (00:00:00.000) in local timezone.
  static DateTime startOfDay([DateTime? date]) {
    final d = (date ?? DateTime.now()).toLocal();
    return DateTime(d.year, d.month, d.day);
  }

  /// Start of tomorrow (00:00:00.000 of next calendar day) in local timezone.
  /// Used as the exclusive upper bound for today's filtering: [startOfDay, startOfTomorrow).
  static DateTime startOfTomorrow([DateTime? date]) {
    final d = (date ?? DateTime.now()).toLocal();
    return DateTime(d.year, d.month, d.day + 1);
  }

  /// Start of yesterday (00:00:00.000 of previous calendar day) in local timezone.
  /// Used for yesterday comparison: [startOfYesterday, startOfDay).
  static DateTime startOfYesterday([DateTime? date]) {
    final d = (date ?? DateTime.now()).toLocal();
    return DateTime(d.year, d.month, d.day - 1);
  }

  /// Returns true if [dateTime] falls within the local calendar day of [referenceDate]
  /// (inclusive start-of-day, exclusive start-of-tomorrow).
  static bool isToday(DateTime dateTime, [DateTime? referenceDate]) {
    final local = dateTime.toLocal();
    final start = startOfDay(referenceDate);
    final end = startOfTomorrow(referenceDate);
    return !local.isBefore(start) && local.isBefore(end);
  }

  /// Returns true if [dateTime] falls within the local calendar day before [referenceDate]
  /// (inclusive start-of-yesterday, exclusive start-of-today).
  static bool isYesterday(DateTime dateTime, [DateTime? referenceDate]) {
    final local = dateTime.toLocal();
    final start = startOfYesterday(referenceDate);
    final end = startOfDay(referenceDate);
    return !local.isBefore(start) && local.isBefore(end);
  }

  /// Returns true if two [DateTime] instances occur on the exact same local calendar day.
  static bool isSameDay(DateTime a, DateTime b) {
    final la = a.toLocal();
    final lb = b.toLocal();
    return la.year == lb.year && la.month == lb.month && la.day == lb.day;
  }

  /// Returns the bucket index (0 to 5) for a given timestamp within the 24h operational day:
  /// 0: < 10:00 AM ('<10a')
  /// 1: 10:00 AM - 12:00 PM ('10-12')
  /// 2: 12:00 PM - 02:00 PM ('12-2p')
  /// 3: 02:00 PM - 04:00 PM ('2-4p')
  /// 4: 04:00 PM - 06:00 PM ('4-6p')
  /// 5: >= 06:00 PM ('6p+')
  static int getIntradayBucketIndex(DateTime dateTime) {
    final hour = dateTime.toLocal().hour;
    if (hour < 10) return 0;
    if (hour < 12) return 1;
    if (hour < 14) return 2;
    if (hour < 16) return 3;
    if (hour < 18) return 4;
    return 5;
  }

  /// Labels corresponding to the 6 intraday buckets.
  static const List<String> intradayBucketLabels = [
    '<10a',
    '10-12',
    '12-2p',
    '2-4p',
    '4-6p',
    '6p+',
  ];

  /// Opening hour for clinic operating hours (9:00 AM).
  static const int clinicOpeningHour = 9;

  /// Closing hour for clinic operating hours (8:00 PM).
  static const int clinicClosingHour = 20;

  /// Number of 1-hour time slots spanning operating hours (9:00 AM to 8:00 PM = 11 slots).
  static const int hourlySlotCount = clinicClosingHour - clinicOpeningHour; // 11

  /// Returns the hourly slot index (0 to 10) for operating hours.
  /// If payment occurs before 9 AM, it is counted in the opening slot (0).
  /// If payment occurs after 8 PM, it is counted in the final slot (10).
  static int getHourlySlotIndex(DateTime dateTime) {
    final hour = dateTime.toLocal().hour;
    if (hour < clinicOpeningHour) return 0;
    if (hour >= clinicClosingHour) return hourlySlotCount - 1;
    return hour - clinicOpeningHour;
  }

  /// Compact hourly slot labels (11 slots).
  static const List<String> hourlySlotLabels = [
    '9-10a',
    '10-11a',
    '11-12p',
    '12-1p',
    '1-2p',
    '2-3p',
    '3-4p',
    '4-5p',
    '5-6p',
    '6-7p',
    '7-8p',
  ];

  /// Full descriptive hourly slot labels for tooltips and headers.
  static const List<String> hourlySlotFullLabels = [
    '9:00 AM - 10:00 AM',
    '10:00 AM - 11:00 AM',
    '11:00 AM - 12:00 PM',
    '12:00 PM - 1:00 PM',
    '1:00 PM - 2:00 PM',
    '2:00 PM - 3:00 PM',
    '3:00 PM - 4:00 PM',
    '4:00 PM - 5:00 PM',
    '5:00 PM - 6:00 PM',
    '6:00 PM - 7:00 PM',
    '7:00 PM - 8:00 PM',
  ];
}
