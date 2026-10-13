// supabase/functions/sync-excel-workbook/types.ts
// ─────────────────────────────────────────────────────────────────────────────
// Type definitions for Central Excel Workbook Synchronization
// ─────────────────────────────────────────────────────────────────────────────

export type ExcelDataFormat =
  | "text"
  | "number"
  | "currency"
  | "date"
  | "datetime"
  | "boolean";

export interface ExcelColumnDefinition {
  header: string;
  key: string;
  width: number;
  format: ExcelDataFormat;
  sourceField: string;
  defaultValue?: string | number | boolean;
  transform?: (val: any, row: Record<string, any>) => any;
}

export interface ExcelWorksheetDefinition {
  name: string;
  sourceTable: string;
  stableIdKey: string;
  timestampKey: string;
  columns: ExcelColumnDefinition[];
  selectQuery: string;
  orderByField?: string;
  sensitiveExcludedFields?: string[];
}

export interface ExcelSyncCheckpoint {
  worksheet_name: string;
  source_table: string;
  last_sync_timestamp: string;
  record_count: number;
  updated_at: string;
}

export interface ExcelSyncState {
  id: string;
  sync_type: "initial" | "scheduled" | "manual";
  status: "pending" | "in_progress" | "success" | "failed";
  started_at: string;
  completed_at?: string;
  records_upserted: number;
  file_size_bytes: number;
  storage_path: string;
  worksheets_synced: string[];
  error_message?: string;
  triggered_by?: string;
}

export interface SyncExecutionResult {
  success: boolean;
  syncId: string;
  recordsProcessed: number;
  worksheetsUpdated: string[];
  fileSizeBytes: number;
  durationMs: number;
  errorMessage?: string;
}

export interface WorksheetExportSummary {
  worksheetName: string;
  sourceTable: string;
  recordCount: number;
  highWaterMark: string;
  status: "success" | "empty" | "failed";
  errorMessage?: string;
}

export interface HistoricalExportResult {
  success: boolean;
  syncId: string;
  totalRecords: number;
  fileSizeBytes: number;
  storagePath: string;
  durationMs: number;
  worksheetSummaries: WorksheetExportSummary[];
  errorMessage?: string;
}

