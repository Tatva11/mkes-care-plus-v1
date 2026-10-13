import 'package:flutter/foundation.dart';

/// Represents a single record from `public.excel_sync_state`.
@immutable
class ExcelSyncStateModel {
  const ExcelSyncStateModel({
    required this.id,
    required this.syncType,
    required this.status,
    required this.startedAt,
    this.completedAt,
    required this.recordsUpserted,
    required this.fileSizeBytes,
    required this.storagePath,
    required this.worksheetsSynced,
    this.errorMessage,
    this.triggeredBy,
    required this.createdAt,
  });

  final String id;
  final String syncType; // 'initial' | 'scheduled' | 'manual'
  final String status; // 'pending' | 'in_progress' | 'success' | 'failed'
  final DateTime startedAt;
  final DateTime? completedAt;
  final int recordsUpserted;
  final int fileSizeBytes;
  final String storagePath;
  final List<String> worksheetsSynced;
  final String? errorMessage;
  final String? triggeredBy;
  final DateTime createdAt;

  bool get isSuccess => status.toLowerCase() == 'success';
  bool get isInProgress => status.toLowerCase() == 'in_progress';
  bool get isFailed => status.toLowerCase() == 'failed';

  double get fileSizeMegabytes => fileSizeBytes / (1024 * 1024);

  factory ExcelSyncStateModel.fromJson(Map<String, dynamic> json) {
    return ExcelSyncStateModel(
      id: json['id'] as String? ?? '',
      syncType: json['sync_type'] as String? ?? 'scheduled',
      status: json['status'] as String? ?? 'pending',
      startedAt: json['started_at'] != null
          ? DateTime.tryParse(json['started_at'] as String) ?? DateTime.now()
          : DateTime.now(),
      completedAt: json['completed_at'] != null
          ? DateTime.tryParse(json['completed_at'] as String)
          : null,
      recordsUpserted: (json['records_upserted'] as num?)?.toInt() ?? 0,
      fileSizeBytes: (json['file_size_bytes'] as num?)?.toInt() ?? 0,
      storagePath: json['storage_path'] as String? ??
          'clinic-excel-sync/MKES_CARE_Plus_Master.xlsx',
      worksheetsSynced: (json['worksheets_synced'] as List<dynamic>?)
              ?.map((e) => e.toString())
              .toList() ??
          const [],
      errorMessage: json['error_message'] as String?,
      triggeredBy: json['triggered_by'] as String?,
      createdAt: json['created_at'] != null
          ? DateTime.tryParse(json['created_at'] as String) ?? DateTime.now()
          : DateTime.now(),
    );
  }

  Map<String, dynamic> toJson() {
    return {
      'id': id,
      'sync_type': syncType,
      'status': status,
      'started_at': startedAt.toIso8601String(),
      'completed_at': completedAt?.toIso8601String(),
      'records_upserted': recordsUpserted,
      'file_size_bytes': fileSizeBytes,
      'storage_path': storagePath,
      'worksheets_synced': worksheetsSynced,
      'error_message': errorMessage,
      'triggered_by': triggeredBy,
      'created_at': createdAt.toIso8601String(),
    };
  }
}

/// Represents high-water mark metadata from `public.excel_sync_checkpoints`.
@immutable
class ExcelSyncCheckpointModel {
  const ExcelSyncCheckpointModel({
    required this.worksheetName,
    required this.sourceTable,
    required this.lastSyncTimestamp,
    required this.recordCount,
    required this.updatedAt,
  });

  final String worksheetName;
  final String sourceTable;
  final DateTime lastSyncTimestamp;
  final int recordCount;
  final DateTime updatedAt;

  factory ExcelSyncCheckpointModel.fromJson(Map<String, dynamic> json) {
    return ExcelSyncCheckpointModel(
      worksheetName: json['worksheet_name'] as String? ?? '',
      sourceTable: json['source_table'] as String? ?? '',
      lastSyncTimestamp: json['last_sync_timestamp'] != null
          ? DateTime.tryParse(json['last_sync_timestamp'] as String) ??
              DateTime.fromMillisecondsSinceEpoch(0, isUtc: true)
          : DateTime.fromMillisecondsSinceEpoch(0, isUtc: true),
      recordCount: (json['record_count'] as num?)?.toInt() ?? 0,
      updatedAt: json['updated_at'] != null
          ? DateTime.tryParse(json['updated_at'] as String) ?? DateTime.now()
          : DateTime.now(),
    );
  }

  Map<String, dynamic> toJson() {
    return {
      'worksheet_name': worksheetName,
      'source_table': sourceTable,
      'last_sync_timestamp': lastSyncTimestamp.toIso8601String(),
      'record_count': recordCount,
      'updated_at': updatedAt.toIso8601String(),
    };
  }
}

/// Represents the historical export result for a single worksheet.
@immutable
class WorksheetExportSummaryModel {
  const WorksheetExportSummaryModel({
    required this.worksheetName,
    required this.sourceTable,
    required this.recordCount,
    required this.highWaterMark,
    required this.status,
    this.errorMessage,
  });

  final String worksheetName;
  final String sourceTable;
  final int recordCount;
  final String highWaterMark;
  final String status;
  final String? errorMessage;

  bool get isSuccess => status.toLowerCase() == 'success';
  bool get isEmpty => status.toLowerCase() == 'empty';
  bool get isFailed => status.toLowerCase() == 'failed';

  factory WorksheetExportSummaryModel.fromJson(Map<String, dynamic> json) {
    return WorksheetExportSummaryModel(
      worksheetName: json['worksheetName'] as String? ??
          json['worksheet_name'] as String? ??
          '',
      sourceTable: json['sourceTable'] as String? ??
          json['source_table'] as String? ??
          '',
      recordCount: (json['recordCount'] as num? ??
              json['record_count'] as num?)
          ?.toInt() ??
          0,
      highWaterMark: json['highWaterMark'] as String? ??
          json['high_water_mark'] as String? ??
          '1970-01-01T00:00:00.000Z',
      status: json['status'] as String? ?? 'success',
      errorMessage: json['errorMessage'] as String? ??
          json['error_message'] as String?,
    );
  }

  Map<String, dynamic> toJson() {
    return {
      'worksheetName': worksheetName,
      'sourceTable': sourceTable,
      'recordCount': recordCount,
      'highWaterMark': highWaterMark,
      'status': status,
      'errorMessage': errorMessage,
    };
  }
}

/// Represents the overall result of a historical workbook export execution.
@immutable
class HistoricalExportResultModel {
  const HistoricalExportResultModel({
    required this.success,
    required this.syncId,
    required this.totalRecords,
    required this.fileSizeBytes,
    required this.storagePath,
    required this.durationMs,
    required this.worksheetSummaries,
    this.errorMessage,
  });

  final bool success;
  final String syncId;
  final int totalRecords;
  final int fileSizeBytes;
  final String storagePath;
  final int durationMs;
  final List<WorksheetExportSummaryModel> worksheetSummaries;
  final String? errorMessage;

  double get fileSizeMegabytes => fileSizeBytes / (1024 * 1024);

  factory HistoricalExportResultModel.fromJson(Map<String, dynamic> json) {
    final summariesRaw = json['worksheetSummaries'] as List<dynamic>? ??
        json['worksheet_summaries'] as List<dynamic>? ??
        const [];

    return HistoricalExportResultModel(
      success: json['success'] as bool? ?? false,
      syncId: json['syncId'] as String? ?? json['sync_id'] as String? ?? '',
      totalRecords: (json['totalRecords'] as num? ??
              json['total_records'] as num?)
          ?.toInt() ??
          0,
      fileSizeBytes: (json['fileSizeBytes'] as num? ??
              json['file_size_bytes'] as num?)
          ?.toInt() ??
          0,
      storagePath: json['storagePath'] as String? ??
          json['storage_path'] as String? ??
          'clinic-excel-sync/MKES_CARE_Plus_Master.xlsx',
      durationMs: (json['durationMs'] as num? ??
              json['duration_ms'] as num?)
          ?.toInt() ??
          0,
      worksheetSummaries: summariesRaw
          .map((e) =>
              WorksheetExportSummaryModel.fromJson(e as Map<String, dynamic>))
          .toList(),
      errorMessage: json['errorMessage'] as String? ??
          json['error_message'] as String? ??
          json['error'] as String?,
    );
  }

  Map<String, dynamic> toJson() {
    return {
      'success': success,
      'syncId': syncId,
      'totalRecords': totalRecords,
      'fileSizeBytes': fileSizeBytes,
      'storagePath': storagePath,
      'durationMs': durationMs,
      'worksheetSummaries':
          worksheetSummaries.map((w) => w.toJson()).toList(),
      'errorMessage': errorMessage,
    };
  }
}

