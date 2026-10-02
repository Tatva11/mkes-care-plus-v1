import 'package:flutter_test/flutter_test.dart';
import 'package:mkes_care/features/dental/models/dental_lab_model.dart';
import 'package:mkes_care/features/dental/providers/dental_lab_provider.dart';

void main() {
  group('Sprint 5.1 — Dental Lab Model & Serialization', () {
    test('1. Model parses completely from Supabase JSON with joined patient', () {
      final json = {
        'id': 'dl-101',
        'patient_id': 'pat-202',
        'case_number': 'DEN-20261002-0001',
        'case_type': 'Zirconia Crown #14',
        'status': 'processing',
        'sent_date': '2026-10-02',
        'ready_date': null,
        'delivered_date': null,
        'remarks': 'Shade A2, urgent case',
        'created_at': '2026-10-02T09:00:00Z',
        'updated_at': '2026-10-02T09:00:00Z',
        'patients': {
          'id': 'pat-202',
          'patient_number': 'D102',
          'name': 'Sarah Connor',
          'mobile': '+919876543210',
          'department': 'dental',
          'created_at': '2026-10-01T10:00:00Z',
          'updated_at': '2026-10-01T10:00:00Z',
        },
      };

      final item = DentalLabModel.fromJson(json);

      expect(item.id, equals('dl-101'));
      expect(item.patientId, equals('pat-202'));
      expect(item.caseNumber, equals('DEN-20261002-0001'));
      expect(item.caseType, equals('Zirconia Crown #14'));
      expect(item.status, equals('processing'));
      expect(item.isProcessing, isTrue);
      expect(item.isReady, isFalse);
      expect(item.isDelivered, isFalse);
      expect(item.sentDate, equals(DateTime(2026, 10, 2)));
      expect(item.readyDate, isNull);
      expect(item.deliveredDate, isNull);
      expect(item.remarks, equals('Shade A2, urgent case'));
      expect(item.patientName, equals('Sarah Connor'));
      expect(item.patientNumber, equals('D102'));
      expect(item.patientMobile, equals('+919876543210'));
    });

    test('2. Model toJson serializes clean table payload with formatted dates', () {
      final item = DentalLabModel(
        id: 'dl-101',
        patientId: 'pat-202',
        caseNumber: 'DEN-20261002-0001',
        caseType: '3-Unit Bridge',
        status: 'ready',
        sentDate: DateTime(2026, 10, 1),
        readyDate: DateTime(2026, 10, 4),
        deliveredDate: null,
        remarks: 'Occlusal clearance checked',
        createdAt: DateTime(2026, 10, 1),
        updatedAt: DateTime(2026, 10, 4),
      );

      final json = item.toJson();

      expect(json['id'], equals('dl-101'));
      expect(json['patient_id'], equals('pat-202'));
      expect(json['case_number'], equals('DEN-20261002-0001'));
      expect(json['case_type'], equals('3-Unit Bridge'));
      expect(json['status'], equals('ready'));
      expect(json['sent_date'], equals('2026-10-01'));
      expect(json['ready_date'], equals('2026-10-04'));
      expect(json['delivered_date'], isNull);
      expect(json['remarks'], equals('Occlusal clearance checked'));
      // Ensure joined helper fields are not written back to table
      expect(json.containsKey('patient_name'), isFalse);
      expect(json.containsKey('patient_mobile'), isFalse);
    });

    test('3. Status values and labels are strictly enforced', () {
      expect(DentalLabModel.validStatuses, containsAll(['processing', 'ready', 'delivered']));
      expect(DentalLabModel.validStatuses.length, equals(3));

      final processing = DentalLabModel(
        id: '1',
        caseNumber: 'C1',
        caseType: 'Crown',
        status: 'processing',
        sentDate: DateTime(2026, 10, 1),
        createdAt: DateTime.now(),
        updatedAt: DateTime.now(),
      );
      expect(processing.statusLabel, equals('Processing'));

      final ready = processing.copyWith(status: 'ready');
      expect(ready.statusLabel, equals('Ready'));
      expect(ready.isReady, isTrue);

      final delivered = processing.copyWith(status: 'delivered');
      expect(delivered.statusLabel, equals('Delivered'));
      expect(delivered.isDelivered, isTrue);
    });
  });

  group('Sprint 5.1 — Date Validation & Status Transitions', () {
    test('4. Date validation returns null when dates are chronologically valid', () {
      final sent = DateTime(2026, 10, 1);
      final ready = DateTime(2026, 10, 3);
      final delivered = DateTime(2026, 10, 5);

      final error = DentalLabModel.validateDates(
        sentDate: sent,
        readyDate: ready,
        deliveredDate: delivered,
      );

      expect(error, isNull);
    });

    test('5. Date validation fails when ready date is before sent date', () {
      final sent = DateTime(2026, 10, 5);
      final ready = DateTime(2026, 10, 2);

      final error = DentalLabModel.validateDates(
        sentDate: sent,
        readyDate: ready,
      );

      expect(error, equals('Ready date cannot be before sent date.'));
    });

    test('6. Date validation fails when delivered date is before sent date', () {
      final sent = DateTime(2026, 10, 5);
      final delivered = DateTime(2026, 10, 1);

      final error = DentalLabModel.validateDates(
        sentDate: sent,
        deliveredDate: delivered,
      );

      expect(error, equals('Delivered date cannot be before sent date.'));
    });

    test('7. Date validation fails when delivered date is before ready date', () {
      final sent = DateTime(2026, 10, 1);
      final ready = DateTime(2026, 10, 4);
      final delivered = DateTime(2026, 10, 2);

      final error = DentalLabModel.validateDates(
        sentDate: sent,
        readyDate: ready,
        deliveredDate: delivered,
      );

      expect(error, equals('Delivered date cannot be before ready date.'));
    });

    test('8. Status transition: processing -> ready sets readyDate and enables WhatsApp', () {
      final initial = DentalLabModel(
        id: 'dl-1',
        patientId: 'p-1',
        caseNumber: 'DEN-401',
        caseType: 'Zirconia Crown',
        status: 'processing',
        sentDate: DateTime(2026, 10, 1),
        createdAt: DateTime(2026, 10, 1),
        updatedAt: DateTime(2026, 10, 1),
        patientMobile: '+919876543210',
      );

      final ready = initial.copyWith(
        status: 'ready',
        readyDate: DateTime(2026, 10, 3),
        updatedAt: DateTime(2026, 10, 3),
      );

      expect(ready.isProcessing, isFalse);
      expect(ready.isReady, isTrue);
      expect(ready.readyDate, isNotNull);
      expect(ready.patientMobile, isNotNull);
      expect(DentalLabModel.validateDates(sentDate: ready.sentDate, readyDate: ready.readyDate), isNull);
    });

    test('9. Status transition: ready -> delivered sets deliveredDate', () {
      final ready = DentalLabModel(
        id: 'dl-1',
        patientId: 'p-1',
        caseNumber: 'DEN-401',
        caseType: 'Zirconia Crown',
        status: 'ready',
        sentDate: DateTime(2026, 10, 1),
        readyDate: DateTime(2026, 10, 3),
        createdAt: DateTime(2026, 10, 1),
        updatedAt: DateTime(2026, 10, 3),
      );

      final delivered = ready.copyWith(
        status: 'delivered',
        deliveredDate: DateTime(2026, 10, 5),
        updatedAt: DateTime(2026, 10, 5),
      );

      expect(delivered.isDelivered, isTrue);
      expect(delivered.deliveredDate, equals(DateTime(2026, 10, 5)));
      expect(
        DentalLabModel.validateDates(
          sentDate: delivered.sentDate,
          readyDate: delivered.readyDate,
          deliveredDate: delivered.deliveredDate,
        ),
        isNull,
      );
    });
  });

  group('Sprint 5.1 — Search, Filter & Stats Calculation', () {
    final sampleCases = [
      DentalLabModel(
        id: '1',
        patientId: 'p1',
        patientName: 'David Miller',
        patientNumber: 'D101',
        caseNumber: 'DEN-4012',
        caseType: 'Zirconia Crown #14',
        status: 'processing',
        sentDate: DateTime(2026, 10, 1),
        createdAt: DateTime.now(),
        updatedAt: DateTime.now(),
      ),
      DentalLabModel(
        id: '2',
        patientId: 'p2',
        patientName: 'Sophia Martinez',
        patientNumber: 'D102',
        caseNumber: 'DEN-4013',
        caseType: '3-Unit Porc. Bridge',
        status: 'ready',
        sentDate: DateTime(2026, 10, 1),
        readyDate: DateTime(2026, 10, 3),
        createdAt: DateTime.now(),
        updatedAt: DateTime.now(),
      ),
      DentalLabModel(
        id: '3',
        patientId: 'p3',
        patientName: 'Olivia Taylor',
        patientNumber: 'D103',
        caseNumber: 'DEN-4014',
        caseType: 'Full Upper Denture',
        status: 'delivered',
        sentDate: DateTime(2026, 9, 25),
        readyDate: DateTime(2026, 9, 28),
        deliveredDate: DateTime(2026, 9, 30),
        createdAt: DateTime.now(),
        updatedAt: DateTime.now(),
      ),
    ];

    test('10. DentalLabStats computes correct KPI counts', () {
      int processing = 0;
      int ready = 0;
      int delivered = 0;

      for (final c in sampleCases) {
        if (c.isProcessing) processing++;
        if (c.isReady) ready++;
        if (c.isDelivered) delivered++;
      }

      final stats = DentalLabStats(
        total: sampleCases.length,
        processing: processing,
        ready: ready,
        delivered: delivered,
      );

      expect(stats.total, equals(3));
      expect(stats.processing, equals(1));
      expect(stats.ready, equals(1));
      expect(stats.delivered, equals(1));
    });

    test('11. Empty state handles zero cases gracefully', () {
      const emptyStats = DentalLabStats(
        total: 0,
        processing: 0,
        ready: 0,
        delivered: 0,
      );

      expect(emptyStats.total, equals(0));
      expect(emptyStats.processing, equals(0));
      expect(emptyStats.ready, equals(0));
      expect(emptyStats.delivered, equals(0));
    });

    test('12. Search filters by case number, patient name, and restoration type', () {
      final searchByCase = sampleCases.where((c) => c.caseNumber.contains('4013')).toList();
      expect(searchByCase.length, equals(1));
      expect(searchByCase.first.patientName, equals('Sophia Martinez'));

      final searchByName = sampleCases.where((c) => (c.patientName ?? '').toLowerCase().contains('taylor')).toList();
      expect(searchByName.length, equals(1));
      expect(searchByName.first.caseType, equals('Full Upper Denture'));

      final searchByType = sampleCases.where((c) => c.caseType.toLowerCase().contains('crown')).toList();
      expect(searchByType.length, equals(1));
      expect(searchByType.first.caseNumber, equals('DEN-4012'));
    });

    test('13. Status filter correctly partitions cases', () {
      final processingOnly = sampleCases.where((c) => c.isProcessing).toList();
      expect(processingOnly.length, equals(1));
      expect(processingOnly.first.caseNumber, equals('DEN-4012'));

      final readyOnly = sampleCases.where((c) => c.isReady).toList();
      expect(readyOnly.length, equals(1));
      expect(readyOnly.first.caseNumber, equals('DEN-4013'));

      final deliveredOnly = sampleCases.where((c) => c.isDelivered).toList();
      expect(deliveredOnly.length, equals(1));
      expect(deliveredOnly.first.caseNumber, equals('DEN-4014'));
    });
  });
}
