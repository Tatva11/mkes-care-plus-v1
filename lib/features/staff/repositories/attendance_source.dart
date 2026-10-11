import '../models/shift_configuration.dart';

abstract class AttendanceSource {
  Future<void> recordCheckIn(
    String staffId,
    DateTime time, {
    String shift = 'morning',
    ShiftConfiguration? config,
  });

  Future<void> recordCheckOut(
    String staffId,
    DateTime time, {
    String shift = 'morning',
    ShiftConfiguration? config,
  });
}
