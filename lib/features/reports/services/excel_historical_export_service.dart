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

  /// Downloads the master Excel workbook from the private storage bucket.
  Future<Uint8List> downloadMasterWorkbook() async {
    final client = _supabase;
    if (client == null) {
      throw StateError('SupabaseClient is not configured');
    }
    return client.storage.from(storageBucket).download(masterWorkbookFile);
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
}
