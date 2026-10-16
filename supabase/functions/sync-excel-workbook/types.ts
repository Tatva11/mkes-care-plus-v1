// supabase/functions/sync-excel-workbook/types.ts
// ─────────────────────────────────────────────────────────────────────────────
// Type definitions for Central Excel Workbook Synchronization (Sprint 9.4)
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

export interface ExcelSortClause {
  column: string;
  ascending: boolean;
  nullsFirst?: boolean;
}

export interface ExcelWorksheetDefinition {
  name: string;
  sourceTable: string;
  stableIdKey: string;
  timestampKey: string;
  columns: ExcelColumnDefinition[];
  selectQuery: string;
  orderByField?: string;
  sortClauses?: ExcelSortClause[];
  sensitiveExcludedFields?: string[];
}

export interface ExcelSyncCheckpoint {
  worksheet_name: string;
  source_table: string;
  last_sync_timestamp: string;
  record_count: number;
  last_sync_id?: string;
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

export interface ExcelSyncLease {
  acquired: boolean;
  fencing_token: number;
  current_holder: string;
  expires_at: string;
}

export interface ExcelSyncVersion {
  version_id: string;
  version_number: number;
  storage_path: string;
  file_size_bytes: number;
  total_records: number;
  worksheets_summary: WorksheetExportSummary[];
  published_at: string;
  sync_id: string;
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

export interface IncrementalSyncResult {
  success: boolean;
  status: "success" | "no_op" | "already_running" | "failed";
  syncId: string;
  versionId?: string;
  versionNumber?: number;
  fencingToken?: number;
  totalRecords: number;
  fileSizeBytes: number;
  storagePath?: string;
  durationMs: number;
  eventsProcessed: number;
  worksheetSummaries?: WorksheetExportSummary[];
  errorMessage?: string;
}

export interface SingleWorksheetExportResult {
  success: boolean;
  worksheetName: string;
  fileName: string;
  storagePath: string;
  recordCount: number;
  fileSizeBytes: number;
  downloadUrl?: string;
  errorMessage?: string;
}
