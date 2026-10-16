// lib/features/reports/services/excel_historical_export_service.dart
// ─────────────────────────────────────────────────────────────────────────────
// Client service for triggering, tracking, and validating historical workbook
// exports from Supabase to the master 21-sheet Excel workbook (Sprint 9.3).
//
// Security & Architecture:
// - Uses authenticated Supabase client session (caller JWT).
// - Service-role key is NEVER exposed to client.
// - All data transformations and salary redactions enforced.
// ─────────────────────────────────────────────────────────────────────────────

import 'package:flutter/foundation.dart';
import 'package:supabase_flutter/supabase_flutter.dart';

import '../models/excel_sync_state_model.dart';
import 'excel_workbook_builder.dart';
import 'excel_workbook_schema.dart';

/// Container for local workbook export output (used for offline export / testing).
@immutable
class LocalHistoricalExportOutput {
  const LocalHistoricalExportOutput({
    required this.result,
    required this.bytes,
  });

  final HistoricalExportResultModel result;
  final Uint8List bytes;
}

/// Comprehensive validation report for historical export integrity.
@immutable
class HistoricalExportValidationReport {
  const HistoricalExportValidationReport({
    required this.isValid,
    required this.errors,
    required this.totalRecords,
    required this.worksheetCount,
    required this.hasValidZipHeader,
    required this.hasAll21Worksheets,
    required this.hasAllOpenXmlParts,
  });

  final bool isValid;
  final List<String> errors;
  final int totalRecords;
  final int worksheetCount;
  final bool hasValidZipHeader;
  final bool hasAll21Worksheets;
  final bool hasAllOpenXmlParts;
}

class ExcelHistoricalExportService {
  ExcelHistoricalExportService({
    SupabaseClient? supabase,
  }) : _supabase = supabase;

  final SupabaseClient? _supabase;

  static const String storageBucket = 'clinic-excel-sync';
  static const String masterWorkbookFile = 'MKES_CARE_Plus_Master.xlsx';

  /// Triggers a server-side historical workbook export via Supabase Edge Function.
  ///
  /// The Edge Function runs with server-side admin privileges, iterates through
  /// all 21 worksheets in batches of 500, verifies counts, uploads the binary
  /// workbook to private storage, and updates sync state and checkpoints.
  Future<HistoricalExportResultModel> triggerServerHistoricalExport({
    String syncType = 'initial',
  }) async {
    final client = _supabase;
    if (client == null) {
      return const HistoricalExportResultModel(
        success: false,
        syncId: '',
        totalRecords: 0,
        fileSizeBytes: 0,
        storagePath: '$storageBucket/$masterWorkbookFile',
        durationMs: 0,
        worksheetSummaries: [],
        errorMessage: 'SupabaseClient is not configured for remote operations',
      );
    }

    try {
      final response = await client.functions.invoke(
        'sync-excel-workbook',
        body: {
          'action': 'export-historical',
          'sync_type': syncType,
        },
      );


      final status = response.status;
      final data = response.data;

      if (status != 200 || data == null) {
        final errorMsg = data is Map<String, dynamic>
            ? data['error'] ?? 'Server returned status $status'
            : 'Export request failed with status $status';
        return HistoricalExportResultModel(
          success: false,
          syncId: data is Map<String, dynamic> ? data['syncId'] ?? '' : '',
          totalRecords: 0,
          fileSizeBytes: 0,
          storagePath: '$storageBucket/$masterWorkbookFile',
          durationMs: 0,
          worksheetSummaries: const [],
          errorMessage: errorMsg.toString(),
        );
      }

      if (data is Map<String, dynamic>) {
        return HistoricalExportResultModel.fromJson(data);
      }

      return HistoricalExportResultModel(
        success: false,
        syncId: '',
        totalRecords: 0,
        fileSizeBytes: 0,
        storagePath: '$storageBucket/$masterWorkbookFile',
        durationMs: 0,
        worksheetSummaries: const [],
        errorMessage: 'Unexpected server response format',
      );
    } catch (e) {
      return HistoricalExportResultModel(
        success: false,
        syncId: '',
        totalRecords: 0,
        fileSizeBytes: 0,
        storagePath: '$storageBucket/$masterWorkbookFile',
        durationMs: 0,
        worksheetSummaries: const [],
        errorMessage: 'Historical export invocation error: $e',
      );
    }
  }

  /// Fetches the most recent sync execution state from `public.excel_sync_state`.
  Future<ExcelSyncStateModel?> fetchLatestSyncState() async {
    final client = _supabase;
    if (client == null) return null;
    try {
      final response = await client
          .from('excel_sync_state')
          .select('*')
          .order('created_at', ascending: false)
          .limit(1)
          .maybeSingle();

      if (response == null) return null;
      return ExcelSyncStateModel.fromJson(response);
    } catch (e) {
      debugPrint('Error fetching latest excel sync state: $e');
      return null;
    }
  }

  /// Fetches the high-water mark checkpoints across all worksheets from `public.excel_sync_checkpoints`.
  Future<List<ExcelSyncCheckpointModel>> fetchSyncCheckpoints() async {
    final client = _supabase;
    if (client == null) return const [];
    try {
      final response = await client
          .from('excel_sync_checkpoints')
          .select('*')
          .order('worksheet_name', ascending: true);

      final list = response as List<dynamic>? ?? const [];
      return list
          .map((e) => ExcelSyncCheckpointModel.fromJson(e as Map<String, dynamic>))
          .toList();
    } catch (e) {
      debugPrint('Error fetching excel sync checkpoints: $e');
      return const [];
    }
  }

  /// Triggers a 5-minute incremental sync run via Supabase Edge Function (Sprint 9.4).
  ///
  /// Acquires distributed lease, claims pending outbox events, checks for no-op,
  /// regenerates workbook, uploads immutable version, and atomically commits checkpoints.
  Future<ExcelIncrementalSyncResultModel> triggerIncrementalSync({
    String syncType = 'manual',
  }) async {
    final client = _supabase;
    if (client == null) {
      return const ExcelIncrementalSyncResultModel(
        success: false,
        status: 'failed',
        syncId: '',
        totalRecords: 0,
        fileSizeBytes: 0,
        durationMs: 0,
        eventsProcessed: 0,
        errorMessage: 'SupabaseClient is not configured for remote operations',
      );
    }

    try {
      final response = await client.functions.invoke(
        'sync-excel-workbook',
        body: {
          'action': 'sync-incremental',
          'sync_type': syncType,
        },
      );

      final status = response.status;
      final data = response.data;

      if (status != 200 || data == null) {
        final errorMsg = data is Map<String, dynamic>
            ? data['error'] ?? 'Server returned status $status'
            : 'Incremental sync request failed with status $status';
        return ExcelIncrementalSyncResultModel(
          success: false,
          status: 'failed',
          syncId: data is Map<String, dynamic> ? data['syncId'] ?? '' : '',
          totalRecords: 0,
          fileSizeBytes: 0,
          durationMs: 0,
          eventsProcessed: 0,
          errorMessage: errorMsg.toString(),
        );
      }

      if (data is Map<String, dynamic>) {
        return ExcelIncrementalSyncResultModel.fromJson(data);
      }

      return const ExcelIncrementalSyncResultModel(
        success: false,
        status: 'failed',
        syncId: '',
        totalRecords: 0,
        fileSizeBytes: 0,
        durationMs: 0,
        eventsProcessed: 0,
        errorMessage: 'Unexpected server response format',
      );
    } catch (e) {
      return ExcelIncrementalSyncResultModel(
        success: false,
        status: 'failed',
        syncId: '',
        totalRecords: 0,
        fileSizeBytes: 0,
        durationMs: 0,
        eventsProcessed: 0,
        errorMessage: 'Incremental sync invocation error: $e',
      );
    }
  }

  /// Fetches the currently active workbook version from `public.excel_sync_versions`.
  Future<ExcelSyncVersionModel?> fetchActiveVersion() async {
    final client = _supabase;
    if (client == null) return null;
    try {
      final response = await client
          .rpc('get_excel_sync_active_version')
          .maybeSingle();

      if (response == null) return null;
      return ExcelSyncVersionModel.fromJson(response);
    } catch (e) {
      debugPrint('Error fetching active excel sync version: $e');
      return null;
    }
  }

  /// Fetches the current distributed lease status from `public.excel_sync_leases`.
  Future<ExcelSyncLeaseModel?> fetchActiveLease() async {
    final client = _supabase;
    if (client == null) return null;
    try {
      final response = await client
          .from('excel_sync_leases')
          .select('*')
          .eq('lease_key', 'master_sync')
          .maybeSingle();

      if (response == null) return null;
      return ExcelSyncLeaseModel.fromJson(response);
    } catch (e) {
      debugPrint('Error fetching excel sync lease: $e');
      return null;
    }
  }

  /// Fetches the number of pending mutation events in `public.excel_sync_outbox`.
  Future<int> fetchPendingOutboxCount() async {
    final client = _supabase;
    if (client == null) return 0;
    try {
      final response = await client
          .from('excel_sync_outbox')
          .select('id')
          .eq('status', 'pending');

      return (response as List<dynamic>?)?.length ?? 0;
    } catch (e) {
      debugPrint('Error fetching pending outbox count: $e');
      return 0;
    }
  }

  /// Generates a signed URL for direct browser/device download of the active workbook.
  Future<String> getActiveWorkbookSignedUrl({int expiresIn = 3600}) async {
    final client = _supabase;
    if (client == null) {
      throw StateError('SupabaseClient is not configured');
    }

    final activeVersion = await fetchActiveVersion();
    String relativePath = masterWorkbookFile;
    if (activeVersion != null && activeVersion.storagePath.isNotEmpty) {
      relativePath = activeVersion.storagePath;
      if (relativePath.startsWith('$storageBucket/')) {
        relativePath = relativePath.substring(storageBucket.length + 1);
      }
    } else {
      throw StateError(
        'No active master workbook has been published yet. Please run "Full Export" first to generate the initial baseline workbook.',
      );
    }

    try {
      return await client.storage.from(storageBucket).createSignedUrl(relativePath, expiresIn);
    } on StorageException catch (e) {
      if (e.statusCode == '404' || e.message.contains('not found') || e.message.contains('NoSuchKey')) {
        throw StateError(
          'Active workbook file was not found in storage ($relativePath). Please run "Full Export" to regenerate the baseline.',
        );
      }
      rethrow;
    }
  }

  /// Downloads the authoritative active workbook version from Storage.
  Future<Uint8List> downloadActiveWorkbook() async {
    final client = _supabase;
    if (client == null) {
      throw StateError('SupabaseClient is not configured');
    }

    final activeVersion = await fetchActiveVersion();
    if (activeVersion != null && activeVersion.storagePath.isNotEmpty) {
      String relativePath = activeVersion.storagePath;
      if (relativePath.startsWith('$storageBucket/')) {
        relativePath = relativePath.substring(storageBucket.length + 1);
      }
      try {
        return await client.storage.from(storageBucket).download(relativePath);
      } on StorageException catch (e) {
        if (e.statusCode == '404' || e.message.contains('not found') || e.message.contains('NoSuchKey')) {
          throw StateError(
            'Published workbook file was not found in storage ($relativePath). Please run "Full Export" to regenerate the baseline.',
          );
        }
        rethrow;
      }
    }

    // No active version recorded: attempt canonical file or provide actionable error
    try {
      return await client.storage.from(storageBucket).download(masterWorkbookFile);
    } on StorageException catch (e) {
      if (e.statusCode == '404' || e.message.contains('not found') || e.message.contains('NoSuchKey')) {
        throw StateError(
          'No active master workbook has been published yet. Please run "Full Export" first to initialize the baseline workbook.',
        );
      }
      rethrow;
    }
  }

  /// Downloads the master Excel workbook from the private storage bucket.
  Future<Uint8List> downloadMasterWorkbook() async {
    return downloadActiveWorkbook();
  }

  /// Generates a signed URL for direct browser/device download of an individual worksheet.
  Future<String> getSingleWorksheetSignedUrl(
    String worksheetName, {
    int expiresIn = 3600,
  }) async {
    final client = _supabase;
    if (client == null) {
      throw StateError('SupabaseClient is not configured');
    }

    final spec = ExcelWorkbookSchema.getWorksheet(worksheetName);
    if (spec == null) {
      throw ArgumentError('Worksheet "$worksheetName" is not recognized.');
    }

    try {
      final response = await client.functions.invoke(
        'sync-excel-workbook',
        body: {
          'action': 'export-worksheet',
          'worksheet_name': spec.name,
        },
      );

      final status = response.status;
      final data = response.data;

      if (status == 200 && data is Map<String, dynamic>) {
        final downloadUrl = data['downloadUrl'] as String?;
        if (downloadUrl != null && downloadUrl.isNotEmpty) {
          return downloadUrl;
        }

        final storagePath = data['storagePath'] as String?;
        if (storagePath != null && storagePath.isNotEmpty) {
          String relPath = storagePath;
          if (relPath.startsWith('$storageBucket/')) {
            relPath = relPath.substring(storageBucket.length + 1);
          }
          return await client.storage
              .from(storageBucket)
              .createSignedUrl(relPath, expiresIn);
        }
      }

      final errorMsg = data is Map<String, dynamic>
          ? data['error'] ?? 'Server returned status $status'
          : 'Export request failed with status $status';
      throw StateError('Failed to prepare single worksheet: $errorMsg');
    } catch (e) {
      if (e is StateError || e is ArgumentError) rethrow;
      throw StateError('Worksheet export request failed: $e');
    }
  }

  /// Downloads an individual worksheet as a standalone .xlsx file.
  Future<Uint8List> downloadSingleWorksheet(String worksheetName) async {
    final client = _supabase;
    if (client == null) {
      throw StateError('SupabaseClient is not configured');
    }

    final spec = ExcelWorkbookSchema.getWorksheet(worksheetName);
    if (spec == null) {
      throw ArgumentError('Worksheet "$worksheetName" is not recognized.');
    }

    // 1. Attempt server-side Edge Function generation
    try {
      final response = await client.functions.invoke(
        'sync-excel-workbook',
        body: {
          'action': 'export-worksheet',
          'worksheet_name': spec.name,
        },
      );

      if (response.status == 200 && response.data is Map<String, dynamic>) {
        final data = response.data as Map<String, dynamic>;
        final storagePath = data['storagePath'] as String?;
        if (storagePath != null && storagePath.isNotEmpty) {
          String relPath = storagePath;
          if (relPath.startsWith('$storageBucket/')) {
            relPath = relPath.substring(storageBucket.length + 1);
          }
          return await client.storage.from(storageBucket).download(relPath);
        }
      }
    } catch (e) {
      debugPrint('Server single worksheet download fallback: $e');
    }

    // 2. Client-side fallback generation from live database query
    try {
      final queryRes = await client
          .from(spec.sourceTable)
          .select(spec.columns.map((c) => c.sourceField).toSet().join(', '))
          .limit(1000);

      final rawList = queryRes as List<dynamic>? ?? const [];
      final rows = rawList
          .map((e) => Map<String, dynamic>.from(e as Map))
          .toList();

      final builder = ExcelWorkbookBuilder();
      return builder.buildSingleWorksheetWorkbook(
        sheetSpec: spec,
        records: rows,
      );
    } catch (e) {
      throw StateError('Failed to generate single worksheet "$worksheetName": $e');
    }
  }

  /// Generates a local single-worksheet workbook in-memory.
  Uint8List generateLocalSingleWorksheet({
    required String worksheetName,
    required List<Map<String, dynamic>> records,
    String clinicName = 'MKES CARE+ Clinical Management Platform',
  }) {
    final spec = ExcelWorkbookSchema.getWorksheet(worksheetName);
    if (spec == null) {
      throw ArgumentError('Worksheet "$worksheetName" is not recognized.');
    }
    final builder = ExcelWorkbookBuilder(clinicName: clinicName);
    return builder.buildSingleWorksheetWorkbook(
      sheetSpec: spec,
      records: records,
    );
  }

  /// Generates a local historical workbook in-memory from supplied records.
  ///
  /// Used for offline batch generation, regression testing, and local verification
  /// without requiring live cloud credentials or network roundtrips.
  LocalHistoricalExportOutput generateLocalHistoricalWorkbook({
    required Map<String, List<Map<String, dynamic>>> recordsByWorksheet,
    String clinicName = 'MKES CARE+ Clinical Management Platform',
  }) {
    final startTime = DateTime.now();
    final builder = ExcelWorkbookBuilder(clinicName: clinicName);
    final worksheets = ExcelWorkbookSchema.worksheets;
    final summaries = <WorksheetExportSummaryModel>[];
    int totalRecords = 0;

    for (final sheet in worksheets) {
      final rows = recordsByWorksheet[sheet.name] ?? const [];
      int sheetCount = rows.length;
      totalRecords += sheetCount;

      String maxTimestamp = '1970-01-01T00:00:00.000Z';
      for (final row in rows) {
        final ts = row[sheet.timestampKey];
        if (ts != null) {
          final tsStr = ts.toString();
          if (tsStr.compareTo(maxTimestamp) > 0) {
            maxTimestamp = tsStr;
          }
        }
      }

      summaries.add(
        WorksheetExportSummaryModel(
          worksheetName: sheet.name,
          sourceTable: sheet.sourceTable,
          recordCount: sheetCount,
          highWaterMark: maxTimestamp,
          status: sheetCount > 0 ? 'success' : 'empty',
        ),
      );
    }

    final bytes = builder.buildWorkbook(recordsByWorksheet: recordsByWorksheet);
    final duration = DateTime.now().difference(startTime).inMilliseconds;

    final result = HistoricalExportResultModel(
      success: true,
      syncId: 'local-${DateTime.now().millisecondsSinceEpoch}',
      totalRecords: totalRecords,
      fileSizeBytes: bytes.length,
      storagePath: '$storageBucket/$masterWorkbookFile',
      durationMs: duration,
      worksheetSummaries: summaries,
    );

    return LocalHistoricalExportOutput(
      result: result,
      bytes: bytes,
    );
  }

  /// Validates the structural, record count, and packaging integrity of an exported workbook.
  static HistoricalExportValidationReport validateExportIntegrity({
    required HistoricalExportResultModel result,
    required Uint8List bytes,
  }) {
    final errors = <String>[];

    // 1. Result status check
    if (!result.success) {
      errors.add(result.errorMessage ?? 'Export result indicates failure');
    }

    // 2. Worksheet count check
    if (result.worksheetSummaries.length != ExcelWorkbookSchema.totalWorksheetCount) {
      errors.add(
        'Expected ${ExcelWorkbookSchema.totalWorksheetCount} worksheet summaries, but found ${result.worksheetSummaries.length}',
      );
    }

    // 3. Record count reconciliation
    final sumOfRecords = result.worksheetSummaries.fold<int>(
      0,
      (acc, s) => acc + s.recordCount,
    );
    if (sumOfRecords != result.totalRecords) {
      errors.add(
        'Total records mismatch: summaries sum to $sumOfRecords but totalRecords is ${result.totalRecords}',
      );
    }

    // 4. Canonical worksheet presence
    final summaryNames = result.worksheetSummaries.map((s) => s.worksheetName).toSet();
    for (final expected in ExcelWorkbookSchema.worksheets) {
      if (!summaryNames.contains(expected.name)) {
        errors.add('Missing worksheet summary for [${expected.name}]');
      }
    }

    // 5. Zip header verification
    final hasValidZipHeader = bytes.length >= 4 &&
        bytes[0] == 0x50 &&
        bytes[1] == 0x4B &&
        bytes[2] == 0x03 &&
        bytes[3] == 0x04;
    if (!hasValidZipHeader) {
      errors.add('Buffer does not start with valid PK zip magic header');
    }

    // 6. OpenXML parts verification
    final text = String.fromCharCodes(bytes);
    final hasContentTypes = text.contains('[Content_Types].xml');
    final hasRels = text.contains('_rels/.rels');
    final hasWorkbook = text.contains('xl/workbook.xml');
    final hasWorkbookRels = text.contains('xl/_rels/workbook.xml.rels');
    final hasStyles = text.contains('xl/styles.xml');

    final hasAllOpenXmlParts =
        hasContentTypes && hasRels && hasWorkbook && hasWorkbookRels && hasStyles;
    if (!hasAllOpenXmlParts) {
      errors.add('Missing core OpenXML package parts');
    }

    bool hasAll21Worksheets = true;
    for (int i = 1; i <= ExcelWorkbookSchema.totalWorksheetCount; i++) {
      if (!text.contains('xl/worksheets/sheet$i.xml')) {
        hasAll21Worksheets = false;
        errors.add('Missing OpenXML sheet xml part for worksheet index $i');
      }
    }

    return HistoricalExportValidationReport(
      isValid: errors.isEmpty,
      errors: errors,
      totalRecords: result.totalRecords,
      worksheetCount: result.worksheetSummaries.length,
      hasValidZipHeader: hasValidZipHeader,
      hasAll21Worksheets: hasAll21Worksheets,
      hasAllOpenXmlParts: hasAllOpenXmlParts,
    );
  }
}
