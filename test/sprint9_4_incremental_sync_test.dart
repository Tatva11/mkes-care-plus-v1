// test/sprint9_4_incremental_sync_test.dart
// ─────────────────────────────────────────────────────────────────────────────
// Sprint 9.4 — Incremental Synchronization, Outbox, Leases & Atomic Publication
// Tests covering:
// 1. Transactional Outbox Change-Capture & Event Ordering
// 2. Distributed Leases, Concurrency & Fencing Generation Control
// 3. Immutable Versioning, OpenXML Validation & Atomic Publication
// 4. Fast No-Op Exit, Crash Recovery & Idempotency
// 5. Security Invariance, Salary Redaction & Server-Side Scheduling
// ─────────────────────────────────────────────────────────────────────────────

import 'package:flutter_test/flutter_test.dart';

import 'package:mkes_care/features/reports/models/excel_sync_state_model.dart';
import 'package:mkes_care/features/reports/services/excel_workbook_builder.dart';

/// In-memory simulation of the Sprint 9.4 PostgreSQL Outbox & Lease State Machine
class MockPostgreSqlSyncKernel {
  final List<Map<String, dynamic>> outbox = [];
  final Map<String, dynamic> lease = {
    'lease_key': 'master_sync',
    'holder_id': '00000000-0000-0000-0000-000000000000',
    'fencing_token': 0,
    'acquired_at': DateTime.fromMillisecondsSinceEpoch(0, isUtc: true),
    'expires_at': DateTime.fromMillisecondsSinceEpoch(0, isUtc: true),
    'status': 'released',
  };
  final List<Map<String, dynamic>> versions = [];
  final Map<String, Map<String, dynamic>> checkpoints = {};
  int _outboxSequence = 1;

  // Insert mutation into outbox (simulating table trigger)
  void recordMutation({
    required String tableName,
    required String recordId,
    required String operation,
  }) {
    outbox.add({
      'id': _outboxSequence++,
      'table_name': tableName,
      'record_id': recordId,
      'operation': operation,
      'status': 'pending',
      'claim_id': null,
      'claimed_at': null,
      'created_at': DateTime.now().toUtc(),
    });
  }

  // Claim outbox events (simulating claim_excel_sync_outbox_events RPC)
  int claimEvents(String syncId, {int limit = 1000}) {
    final now = DateTime.now().toUtc();
    final eligible = outbox.where((e) {
      if (e['status'] == 'pending') return true;
      if (e['status'] == 'claimed' && e['claimed_at'] != null) {
        final claimedAt = e['claimed_at'] as DateTime;
        if (now.difference(claimedAt).inMinutes >= 10) return true;
      }
      return false;
    }).take(limit).toList();

    for (final e in eligible) {
      e['status'] = 'claimed';
      e['claim_id'] = syncId;
      e['claimed_at'] = now;
    }
    return eligible.length;
  }

  // Acquire distributed lease (simulating acquire_excel_sync_lease RPC)
  Map<String, dynamic> acquireLease(String holderId, {int ttlSeconds = 300}) {
    final now = DateTime.now().toUtc();
    final expiresAt = lease['expires_at'] as DateTime;
    final isExpired = now.isAfter(expiresAt);
    final isReleased = lease['status'] == 'released';

    if (isReleased || isExpired) {
      final newToken = (lease['fencing_token'] as int) + 1;
      lease['holder_id'] = holderId;
      lease['fencing_token'] = newToken;
      lease['acquired_at'] = now;
      lease['expires_at'] = now.add(Duration(seconds: ttlSeconds));
      lease['status'] = 'active';

      return {
        'acquired': true,
        'fencing_token': newToken,
        'current_holder': holderId,
        'expires_at': lease['expires_at'],
      };
    }

    return {
      'acquired': false,
      'fencing_token': lease['fencing_token'],
      'current_holder': lease['holder_id'],
      'expires_at': lease['expires_at'],
    };
  }

  // Renew lease (simulating renew_excel_sync_lease RPC)
  bool renewLease(String holderId, int fencingToken, {int extensionSeconds = 180}) {
    final now = DateTime.now().toUtc();
    final expiresAt = lease['expires_at'] as DateTime;

    if (lease['holder_id'] == holderId &&
        lease['fencing_token'] == fencingToken &&
        lease['status'] == 'active' &&
        !now.isAfter(expiresAt)) {
      lease['expires_at'] = now.add(Duration(seconds: extensionSeconds));
      return true;
    }
    return false;
  }

  // Release lease (simulating release_excel_sync_lease RPC)
  bool releaseLease(String holderId, int fencingToken) {
    if (lease['holder_id'] == holderId &&
        lease['fencing_token'] == fencingToken) {
      lease['status'] = 'released';
      return true;
    }
    return false;
  }

  // Publish version (simulating publish_excel_sync_version RPC)
  Map<String, dynamic> publishVersion({
    required String holderId,
    required int fencingToken,
    required String syncId,
    required String versionId,
    required String storagePath,
    required int fileSizeBytes,
    required int totalRecords,
    required List<Map<String, dynamic>> worksheetsSummary,
    required List<Map<String, dynamic>> checkpointsData,
    String? claimId,
  }) {
    final now = DateTime.now().toUtc();
    final expiresAt = lease['expires_at'] as DateTime;

    // Validate lease and fencing generation
    if (lease['holder_id'] != holderId ||
        lease['fencing_token'] != fencingToken ||
        lease['status'] != 'active' ||
        now.isAfter(expiresAt)) {
      throw StateError(
          'Publication rejected: worker lease expired or superseded (fencing token mismatch).');
    }

    // Idempotency: check if version already published
    final existing = versions.where((v) => v['id'] == versionId && v['is_active'] == true).firstOrNull;
    if (existing != null) {
      return {'success': true, 'version_id': versionId, 'already_published': true};
    }

    // Deactivate previous versions
    for (final v in versions) {
      v['is_active'] = false;
    }

    // Insert new version
    final versionNum = versions.length + 1;
    versions.add({
      'id': versionId,
      'sync_id': syncId,
      'fencing_token': fencingToken,
      'version_number': versionNum,
      'storage_path': storagePath,
      'file_size_bytes': fileSizeBytes,
      'total_records': totalRecords,
      'worksheets_summary': worksheetsSummary,
      'is_active': true,
      'published_at': now,
    });

    // Update checkpoints
    for (final chk in checkpointsData) {
      checkpoints[chk['worksheetName']] = {
        'worksheet_name': chk['worksheetName'],
        'source_table': chk['sourceTable'],
        'last_sync_timestamp': chk['highWaterMark'],
        'record_count': chk['recordCount'],
        'last_sync_id': syncId,
        'updated_at': now,
      };
    }

    // Acknowledge and purge claimed outbox events
    if (claimId != null) {
      outbox.removeWhere((e) => e['claim_id'] == claimId && e['status'] == 'claimed');
    }

    // Release lease
    lease['status'] = 'released';

    return {
      'success': true,
      'version_id': versionId,
      'version_number': versionNum,
      'published_at': now.toIso8601String(),
    };
  }

  Map<String, dynamic>? getActiveVersion() {
    return versions.where((v) => v['is_active'] == true).firstOrNull;
  }
}

void main() {
  group('Sprint 9.4 — Outbox Change-Capture & Event Ordering Tests', () {
    late MockPostgreSqlSyncKernel db;

    setUp(() {
      db = MockPostgreSqlSyncKernel();
    });

    test('Outbox records inserts, updates, and hard deletions across source tables', () {
      db.recordMutation(tableName: 'patients', recordId: 'p-1', operation: 'INSERT');
      db.recordMutation(tableName: 'patients', recordId: 'p-1', operation: 'UPDATE');
      db.recordMutation(tableName: 'patients', recordId: 'p-2', operation: 'DELETE');

      expect(db.outbox.length, equals(3));
      expect(db.outbox[0]['operation'], equals('INSERT'));
      expect(db.outbox[1]['operation'], equals('UPDATE'));
      expect(db.outbox[2]['operation'], equals('DELETE'));
      expect(db.outbox[2]['record_id'], equals('p-2'));
    });

    test('Tables lacking updated_at capture mutations reliably in the outbox', () {
      // sales, billing_items, billing_payments, task_history, inventory_transactions
      db.recordMutation(tableName: 'sales', recordId: 's-100', operation: 'INSERT');
      db.recordMutation(tableName: 'billing_items', recordId: 'bi-200', operation: 'INSERT');
      db.recordMutation(tableName: 'billing_items', recordId: 'bi-200', operation: 'DELETE');
      db.recordMutation(tableName: 'billing_payments', recordId: 'bp-300', operation: 'INSERT');
      db.recordMutation(tableName: 'task_history', recordId: 'th-400', operation: 'INSERT');

      expect(db.outbox.length, equals(5));
      expect(db.outbox.map((e) => e['table_name']).toSet(), equals({
        'sales',
        'billing_items',
        'billing_payments',
        'task_history',
      }));
    });

    test('Parent table modifications (departments, profiles) are captured for joined worksheets', () {
      // When a department is renamed or profile full_name changes
      db.recordMutation(tableName: 'departments', recordId: 'dept-eye', operation: 'UPDATE');
      db.recordMutation(tableName: 'profiles', recordId: 'doc-smith', operation: 'UPDATE');

      expect(db.outbox.length, equals(2));
      expect(db.outbox[0]['table_name'], equals('departments'));
      expect(db.outbox[1]['table_name'], equals('profiles'));
    });

    test('Transactions committing during sync remain pending and are not acknowledged prematurely', () {
      // 1. Initial 2 events
      db.recordMutation(tableName: 'patients', recordId: 'p-1', operation: 'INSERT');
      db.recordMutation(tableName: 'patients', recordId: 'p-2', operation: 'INSERT');

      // 2. Worker 1 claims events
      final claimedCount = db.claimEvents('sync-worker-1');
      expect(claimedCount, equals(2));

      // 3. New event commits while Worker 1 is generating the workbook
      db.recordMutation(tableName: 'patients', recordId: 'p-3', operation: 'INSERT');
      expect(db.outbox.length, equals(3));
      expect(db.outbox[2]['status'], equals('pending'));
      expect(db.outbox[2]['claim_id'], isNull);

      // 4. Worker 1 finishes and publishes version
      db.acquireLease('sync-worker-1');
      db.publishVersion(
        holderId: 'sync-worker-1',
        fencingToken: 1,
        syncId: 'sync-worker-1',
        versionId: 'ver-1',
        storagePath: 'clinic-excel-sync/versions/v1.xlsx',
        fileSizeBytes: 1024,
        totalRecords: 2,
        worksheetsSummary: [],
        checkpointsData: [],
        claimId: 'sync-worker-1',
      );

      // Only the claimed events are acknowledged and removed; p-3 remains pending!
      expect(db.outbox.length, equals(1));
      expect(db.outbox[0]['record_id'], equals('p-3'));
      expect(db.outbox[0]['status'], equals('pending'));
    });

    test('Abandoned claims from a crashed worker can be reclaimed after lease expiry', () {
      db.recordMutation(tableName: 'inventory', recordId: 'inv-1', operation: 'UPDATE');

      // Worker 1 claims event
      db.claimEvents('sync-worker-crashed');
      expect(db.outbox[0]['status'], equals('claimed'));

      // Simulate crash: 11 minutes pass without publication
      db.outbox[0]['claimed_at'] = DateTime.now().toUtc().subtract(const Duration(minutes: 11));

      // Worker 2 attempts to claim events
      final reclaimedCount = db.claimEvents('sync-worker-2');
      expect(reclaimedCount, equals(1));
      expect(db.outbox[0]['claim_id'], equals('sync-worker-2'));
      expect(db.outbox[0]['status'], equals('claimed'));
    });
  });

  group('Sprint 9.4 — Distributed Leases & Fencing Generation Control Tests', () {
    late MockPostgreSqlSyncKernel db;

    setUp(() {
      db = MockPostgreSqlSyncKernel();
    });

    test('Initial lease acquisition succeeds with fencing_token = 1', () {
      final res = db.acquireLease('worker-1');
      expect(res['acquired'], isTrue);
      expect(res['fencing_token'], equals(1));
      expect(res['current_holder'], equals('worker-1'));
    });

    test('Simultaneous acquisition by a second worker is rejected while lease is active', () {
      final res1 = db.acquireLease('worker-1', ttlSeconds: 300);
      expect(res1['acquired'], isTrue);

      final res2 = db.acquireLease('worker-2', ttlSeconds: 300);
      expect(res2['acquired'], isFalse);
      expect(res2['current_holder'], equals('worker-1'));
      expect(res2['fencing_token'], equals(1));
    });

    test('Expired lease takeover succeeds and monotonically increments fencing token', () {
      db.acquireLease('worker-1', ttlSeconds: 300);

      // Simulate Worker 1 expiring
      db.lease['expires_at'] = DateTime.now().toUtc().subtract(const Duration(seconds: 10));

      final res2 = db.acquireLease('worker-2', ttlSeconds: 300);
      expect(res2['acquired'], isTrue);
      expect(res2['fencing_token'], equals(2)); // Monotonic increment!
      expect(res2['current_holder'], equals('worker-2'));
    });

    test('Lease renewal extends expiry only for the legitimate active holder', () {
      db.acquireLease('worker-1', ttlSeconds: 100);

      final renewed = db.renewLease('worker-1', 1, extensionSeconds: 200);
      expect(renewed, isTrue);

      // Attempted renewal with wrong fencing token or wrong holder is rejected
      expect(db.renewLease('worker-1', 99, extensionSeconds: 200), isFalse);
      expect(db.renewLease('imposter', 1, extensionSeconds: 200), isFalse);
    });

    test('Stale worker with superseded fencing token is strictly rejected from publishing', () {
      // Worker 1 acquires lease
      db.acquireLease('worker-1', ttlSeconds: 300);

      // Worker 1 lags, lease expires, Worker 2 takes over with token 2
      db.lease['expires_at'] = DateTime.now().toUtc().subtract(const Duration(seconds: 1));
      db.acquireLease('worker-2', ttlSeconds: 300);
      expect(db.lease['fencing_token'], equals(2));

      // Worker 1 wakes up and attempts to publish with stale token 1
      expect(
        () => db.publishVersion(
          holderId: 'worker-1',
          fencingToken: 1, // Stale!
          syncId: 'sync-1',
          versionId: 'ver-stale',
          storagePath: 'clinic-excel-sync/versions/stale.xlsx',
          fileSizeBytes: 2048,
          totalRecords: 10,
          worksheetsSummary: [],
          checkpointsData: [],
        ),
        throwsA(isA<StateError>()),
      );

      // Confirm no versions were published by the stale worker
      expect(db.versions.isEmpty, isTrue);
    });
  });

  group('Sprint 9.4 — Immutable Versioning & Atomic Publication Tests', () {
    late MockPostgreSqlSyncKernel db;
    late ExcelWorkbookBuilder builder;

    setUp(() {
      db = MockPostgreSqlSyncKernel();
      builder = ExcelWorkbookBuilder();
    });

    test('Master workbook builder generates valid 21-sheet XLSX buffer with PK ZIP header', () {
      final recordsBySheet = <String, List<Map<String, dynamic>>>{
        'Patients': [
          {'id': 'p-1', 'name': 'John Doe', 'patient_number': 'P1001'},
        ],
        'Staff_Directory': [
          {'id': 's-1', 'full_name': 'Dr. Alice', 'salary': 150000}, // Salary present
        ],
      };

      final bytes = builder.buildWorkbook(recordsByWorksheet: recordsBySheet);

      // Verify PK zip magic header (0x50, 0x4B, 0x03, 0x04)
      expect(bytes.length, greaterThan(4));
      expect(bytes[0], equals(0x50));
      expect(bytes[1], equals(0x4B));
      expect(bytes[2], equals(0x03));
      expect(bytes[3], equals(0x04));

      // Verify OpenXML package parts
      final text = String.fromCharCodes(bytes);
      expect(text.contains('[Content_Types].xml'), isTrue);
      expect(text.contains('xl/workbook.xml'), isTrue);
      expect(text.contains('xl/worksheets/sheet1.xml'), isTrue);
      expect(text.contains('xl/worksheets/sheet21.xml'), isTrue);

      // Strict salary exclusion
      expect(text.contains('150000'), isFalse);
    });

    test('Formula injection defense sanitizes strings starting with =, +, -, @, tab, cr', () {
      expect(ExcelWorkbookBuilder.sanitizeSpreadsheetString('=SUM(A1:A10)'), equals("'=SUM(A1:A10)"));
      expect(ExcelWorkbookBuilder.sanitizeSpreadsheetString('@cmd|calc'), equals("'@cmd|calc"));
      expect(ExcelWorkbookBuilder.sanitizeSpreadsheetString('+cmd.exe'), equals("'+cmd.exe"));
      expect(ExcelWorkbookBuilder.sanitizeSpreadsheetString('\tmalicious'), equals("'\tmalicious"));
      expect(ExcelWorkbookBuilder.sanitizeSpreadsheetString('\r\nmalicious'), equals("'\r\nmalicious"));
      expect(ExcelWorkbookBuilder.sanitizeSpreadsheetString('   =SUM(1,2)'), equals("'   =SUM(1,2)"));

      final records = <String, List<Map<String, dynamic>>>{
        'Patients': [
          {'id': 'p-1', 'name': '=SUM(A1:A10)', 'reference': '@cmd|calc'},
          {'id': 'p-2', 'name': '+cmd.exe', 'reference': '\tmalicious'},
        ],
      };

      final bytes = builder.buildWorkbook(recordsByWorksheet: records);
      final text = String.fromCharCodes(bytes);

      // In the OpenXML spreadsheet XML, the prepended apostrophe is XML-escaped as &apos;
      expect(text.contains('&apos;=SUM(A1:A10)'), isTrue);
      expect(text.contains('&apos;@cmd|calc'), isTrue);
      expect(text.contains('&apos;+cmd.exe'), isTrue);
      expect(text.contains('&apos;\tmalicious'), isTrue);
    });

    test('Atomic publication commits single-active version, updates checkpoints, and purges outbox', () {
      db.recordMutation(tableName: 'patients', recordId: 'p-1', operation: 'INSERT');
      db.claimEvents('sync-1');
      db.acquireLease('sync-1');

      final checkpoints = [
        {'worksheetName': 'Patients', 'sourceTable': 'patients', 'highWaterMark': '2026-10-15T01:00:00Z', 'recordCount': 100},
        {'worksheetName': 'Staff_Directory', 'sourceTable': 'profiles', 'highWaterMark': '2026-10-15T01:00:00Z', 'recordCount': 25},
      ];

      final res = db.publishVersion(
        holderId: 'sync-1',
        fencingToken: 1,
        syncId: 'sync-1',
        versionId: 'ver-uuid-1',
        storagePath: 'clinic-excel-sync/versions/v1.xlsx',
        fileSizeBytes: 45000,
        totalRecords: 125,
        worksheetsSummary: [],
        checkpointsData: checkpoints,
        claimId: 'sync-1',
      );

      expect(res['success'], isTrue);
      expect(res['version_number'], equals(1));

      // Active version in DB is authoritative
      final active = db.getActiveVersion();
      expect(active, isNotNull);
      expect(active!['id'], equals('ver-uuid-1'));
      expect(active['is_active'], isTrue);
      expect(active['total_records'], equals(125));

      // Checkpoints updated
      expect(db.checkpoints['Patients']?['record_count'], equals(100));
      expect(db.checkpoints['Patients']?['last_sync_id'], equals('sync-1'));

      // Outbox purged of claimed events
      expect(db.outbox.isEmpty, isTrue);

      // Lease released
      expect(db.lease['status'], equals('released'));
    });

    test('Second publication automatically deactivates previous version (single-active invariant)', () {
      db.acquireLease('sync-1');
      db.publishVersion(
        holderId: 'sync-1',
        fencingToken: 1,
        syncId: 'sync-1',
        versionId: 'ver-1',
        storagePath: 'versions/v1.xlsx',
        fileSizeBytes: 1000,
        totalRecords: 10,
        worksheetsSummary: [],
        checkpointsData: [],
      );

      // Second sync run
      db.acquireLease('sync-2');
      db.publishVersion(
        holderId: 'sync-2',
        fencingToken: 2,
        syncId: 'sync-2',
        versionId: 'ver-2',
        storagePath: 'versions/v2.xlsx',
        fileSizeBytes: 1100,
        totalRecords: 12,
        worksheetsSummary: [],
        checkpointsData: [],
      );

      expect(db.versions.length, equals(2));
      expect(db.versions[0]['is_active'], isFalse); // Old deactivated
      expect(db.versions[1]['is_active'], isTrue);  // New active
      expect(db.getActiveVersion()!['id'], equals('ver-2'));
    });

    test('Idempotency: Re-submitting an already published version ID returns cleanly without error', () {
      db.acquireLease('sync-1');
      db.publishVersion(
        holderId: 'sync-1',
        fencingToken: 1,
        syncId: 'sync-1',
        versionId: 'ver-idempotent',
        storagePath: 'versions/v1.xlsx',
        fileSizeBytes: 1000,
        totalRecords: 10,
        worksheetsSummary: [],
        checkpointsData: [],
      );

      // Re-acquire and re-publish same versionId (simulating lost HTTP response retry)
      db.acquireLease('sync-1-retry');
      final retryRes = db.publishVersion(
        holderId: 'sync-1-retry',
        fencingToken: 2,
        syncId: 'sync-1-retry',
        versionId: 'ver-idempotent',
        storagePath: 'versions/v1.xlsx',
        fileSizeBytes: 1000,
        totalRecords: 10,
        worksheetsSummary: [],
        checkpointsData: [],
      );

      expect(retryRes['success'], isTrue);
      expect(retryRes['already_published'], isTrue);
    });
  });

  group('Sprint 9.4 — Fast No-Op Exit, Models & Security Tests', () {
    test('ExcelIncrementalSyncResultModel correctly deserializes no-op status and duration', () {
      final json = {
        'success': true,
        'status': 'no_op',
        'syncId': 'sync-noop-1',
        'versionId': 'ver-active',
        'versionNumber': 3,
        'fencingToken': 5,
        'totalRecords': 450,
        'fileSizeBytes': 524288,
        'storagePath': 'clinic-excel-sync/versions/v3.xlsx',
        'durationMs': 24,
        'eventsProcessed': 0,
      };

      final model = ExcelIncrementalSyncResultModel.fromJson(json);

      expect(model.success, isTrue);
      expect(model.isNoOp, isTrue);
      expect(model.isAlreadyRunning, isFalse);
      expect(model.isFailed, isFalse);
      expect(model.durationMs, equals(24));
      expect(model.eventsProcessed, equals(0));
      expect(model.fileSizeMegabytes, closeTo(0.5, 0.05));
    });

    test('ExcelIncrementalSyncResultModel correctly handles already_running collision state', () {
      final json = {
        'success': true,
        'status': 'already_running',
        'syncId': 'sync-busy-1',
        'totalRecords': 0,
        'fileSizeBytes': 0,
        'durationMs': 12,
        'eventsProcessed': 0,
      };

      final model = ExcelIncrementalSyncResultModel.fromJson(json);

      expect(model.success, isTrue);
      expect(model.isAlreadyRunning, isTrue);
      expect(model.isNoOp, isFalse);
    });

    test('ExcelSyncLeaseModel correctly calculates active vs expired lease TTL', () {
      final activeJson = {
        'lease_key': 'master_sync',
        'holder_id': 'h-1',
        'fencing_token': 4,
        'acquired_at': DateTime.now().toUtc().toIso8601String(),
        'expires_at': DateTime.now().toUtc().add(const Duration(minutes: 4)).toIso8601String(),
        'status': 'active',
      };

      final activeModel = ExcelSyncLeaseModel.fromJson(activeJson);
      expect(activeModel.isActive, isTrue);
      expect(activeModel.isExpired, isFalse);

      final expiredJson = {
        'lease_key': 'master_sync',
        'holder_id': 'h-2',
        'fencing_token': 5,
        'acquired_at': DateTime.now().toUtc().subtract(const Duration(minutes: 10)).toIso8601String(),
        'expires_at': DateTime.now().toUtc().subtract(const Duration(minutes: 5)).toIso8601String(),
        'status': 'active',
      };

      final expiredModel = ExcelSyncLeaseModel.fromJson(expiredJson);
      expect(expiredModel.isActive, isFalse);
      expect(expiredModel.isExpired, isTrue);
    });

    test('ExcelSyncVersionModel serializes and deserializes accurately with roundtrip fidelity', () {
      final version = ExcelSyncVersionModel(
        versionId: 'ver-uuid-10',
        versionNumber: 10,
        storagePath: 'clinic-excel-sync/versions/v10.xlsx',
        fileSizeBytes: 1048576,
        totalRecords: 1500,
        worksheetsSummary: [
          const WorksheetExportSummaryModel(
            worksheetName: 'Patients',
            sourceTable: 'patients',
            recordCount: 500,
            highWaterMark: '2026-10-15T00:00:00Z',
            status: 'success',
          ),
        ],
        publishedAt: DateTime.parse('2026-10-15T01:00:00.000Z'),
        syncId: 'sync-10',
      );

      final json = version.toJson();
      final reconstituted = ExcelSyncVersionModel.fromJson(json);

      expect(reconstituted.versionId, equals('ver-uuid-10'));
      expect(reconstituted.versionNumber, equals(10));
      expect(reconstituted.totalRecords, equals(1500));
      expect(reconstituted.fileSizeMegabytes, closeTo(1.0, 0.01));
      expect(reconstituted.worksheetsSummary.first.worksheetName, equals('Patients'));
    });
  });
}
