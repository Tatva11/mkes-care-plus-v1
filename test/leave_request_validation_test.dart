import 'package:flutter_test/flutter_test.dart';
import 'package:mkes_care/features/staff/models/leave_request.dart';

void main() {
  group('LeaveRequest validation', () {
    test('rejects missing dates and impossible ranges', () {
      expect(
        () => LeaveRequest.validateSubmission(
          startDate: null,
          endDate: DateTime(2026, 9, 20),
          reason: 'Medical appointment',
        ),
        throwsA(isA<ArgumentError>()),
      );

      expect(
        () => LeaveRequest.validateSubmission(
          startDate: DateTime(2026, 9, 21),
          endDate: DateTime(2026, 9, 20),
          reason: 'Medical appointment',
        ),
        throwsA(isA<ArgumentError>()),
      );
    });

    test('requires a reason for a new leave request', () {
      expect(
        () => LeaveRequest.validateSubmission(
          startDate: DateTime(2026, 9, 20),
          endDate: DateTime(2026, 9, 22),
          reason: '   ',
        ),
        throwsA(isA<ArgumentError>()),
      );
    });
  });
}
