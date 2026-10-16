// supabase/functions/sync-excel-workbook/deploy_bundle.ts
// ─────────────────────────────────────────────────────────────────────────────
// SELF-CONTAINED STANDALONE BUNDLE FOR SUPABASE BROWSER DASHBOARD DEPLOYMENT
//
// This file bundles:
//   1. types.ts (Data models, lease, version, and sync response interfaces)
//   2. schema.ts (Authoritative catalog of all 21 normalized worksheets)
//   3. workbook_builder.ts (ExcelJS OpenXML builder with formula injection protection)
//   4. index.ts (Dual-auth router, incremental sync, historical export, and single worksheet export)
//
// Why this file exists:
//   The Supabase Web Dashboard Edge Function editor does not support multi-file projects
//   or local relative imports (e.g. "./schema.ts"). This standalone bundle can be
//   pasted directly into the online Supabase Dashboard code editor and deployed in 1 click!
// ─────────────────────────────────────────────────────────────────────────────

import { createClient } from "npm:@supabase/supabase-js@2.49.1";
import ExcelJS from "npm:exceljs@4.4.0";

// ============================================================================
// SECTION 1: TYPES & INTERFACES
// ============================================================================

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

// ============================================================================
// SECTION 2: WORKBOOK & WORKSHEET SCHEMA DEFINITIONS
// ============================================================================

// supabase/functions/sync-excel-workbook/schema.ts
// ─────────────────────────────────────────────────────────────────────────────
// Master Workbook & Worksheet Schema Definitions (Sprint 9.5)
// Defines all normalized worksheets, column mappings, stable IDs, formatting,
// sensitive field redaction rules, and deterministic date-wise sorting clauses.
// ─────────────────────────────────────────────────────────────────────────────

export const MASTER_WORKBOOK_FILENAME = "MKES_CARE_Plus_Master.xlsx";
export const STORAGE_BUCKET_NAME = "clinic-excel-sync";
export const STORAGE_FILE_PATH = `${STORAGE_BUCKET_NAME}/${MASTER_WORKBOOK_FILENAME}`;

// Helper formatters
const formatDateOnly = (val: any): string => {
  if (!val) return "-";
  const str = String(val).trim();
  if (!str) return "-";
  return str.split("T")[0];
};

const formatDateTime = (val: any): string => {
  if (!val) return "-";
  const str = String(val).trim();
  if (!str) return "-";
  try {
    const d = new Date(str);
    if (isNaN(d.getTime())) return str;
    const yyyy = d.getFullYear();
    const mm = String(d.getMonth() + 1).padStart(2, "0");
    const dd = String(d.getDate()).padStart(2, "0");
    const hh = String(d.getHours()).padStart(2, "0");
    const min = String(d.getMinutes()).padStart(2, "0");
    return `${yyyy}-${mm}-${dd} ${hh}:${min}`;
  } catch {
    return str;
  }
};

const formatCurrency = (val: any): number => {
  if (val === null || val === undefined) return 0.0;
  const num = Number(val);
  return isNaN(num) ? 0.0 : Math.round(num * 100) / 100;
};

const formatNumber = (val: any, decimals = 1): number => {
  if (val === null || val === undefined) return 0.0;
  const num = Number(val);
  return isNaN(num) ? 0.0 : Number(num.toFixed(decimals));
};

const formatBoolean = (val: any): string => {
  if (val === true || val === "true" || val === 1) return "YES";
  return "NO";
};

const formatJsonb = (val: any): string => {
  if (val === null || val === undefined) return "-";
  if (typeof val === "string") {
    const trimmed = val.trim();
    return trimmed ? trimmed : "-";
  }
  try {
    const serialized = JSON.stringify(val);
    return serialized === "{}" || serialized === "[]" ? "-" : serialized;
  } catch {
    return String(val);
  }
};

export const MASTER_WORKSHEETS: ExcelWorksheetDefinition[] = [
  // ── 1. PATIENTS ───────────────────────────────────────────────────────────
  {
    name: "Patients",
    sourceTable: "patients",
    stableIdKey: "id",
    timestampKey: "updated_at",
    sortClauses: [
      { column: "created_at", ascending: false },
      { column: "id", ascending: true },
    ],
    selectQuery: "id, patient_number, name, dob, address, mobile, department, reference, visit_date, created_at, updated_at",
    columns: [
      { header: "Patient ID", key: "id", width: 36, format: "text", sourceField: "id" },
      { header: "Patient Number", key: "patient_number", width: 18, format: "text", sourceField: "patient_number" },
      { header: "Full Name", key: "name", width: 26, format: "text", sourceField: "name" },
      { header: "Date of Birth", key: "dob", width: 14, format: "date", sourceField: "dob", transform: formatDateOnly },
      { header: "Contact Mobile", key: "mobile", width: 16, format: "text", sourceField: "mobile", defaultValue: "-" },
      { header: "Address", key: "address", width: 32, format: "text", sourceField: "address", defaultValue: "-" },
      { header: "Department", key: "department", width: 14, format: "text", sourceField: "department", transform: (v) => (v ? String(v).toUpperCase() : "-") },
      { header: "Reference Source", key: "reference", width: 20, format: "text", sourceField: "reference", defaultValue: "-" },
      { header: "First Visit Date", key: "visit_date", width: 16, format: "date", sourceField: "visit_date", transform: formatDateOnly },
      { header: "Created At", key: "created_at", width: 18, format: "datetime", sourceField: "created_at", transform: formatDateTime },
      { header: "Updated At", key: "updated_at", width: 18, format: "datetime", sourceField: "updated_at", transform: formatDateTime },
    ],
  },

  // ── 2. STAFF DIRECTORY ────────────────────────────────────────────────────
  {
    name: "Staff_Directory",
    sourceTable: "profiles",
    stableIdKey: "id",
    timestampKey: "updated_at",
    sensitiveExcludedFields: ["salary"],
    sortClauses: [
      { column: "full_name", ascending: true },
      { column: "id", ascending: true },
    ],
    selectQuery: "id, full_name, email, phone_number, designation, role, is_active, assigned_shift, next_shift, shift_effective_date, joining_date, departments(name), created_at, updated_at",
    columns: [
      { header: "Staff ID", key: "id", width: 36, format: "text", sourceField: "id" },
      { header: "Full Name", key: "full_name", width: 26, format: "text", sourceField: "full_name" },
      { header: "Email Address", key: "email", width: 30, format: "text", sourceField: "email" },
      { header: "Phone Number", key: "phone_number", width: 16, format: "text", sourceField: "phone_number", defaultValue: "-" },
      { header: "Department", key: "department", width: 18, format: "text", sourceField: "departments", transform: (v) => (v && v.name ? v.name : "-") },
      { header: "Designation", key: "designation", width: 22, format: "text", sourceField: "designation", defaultValue: "-" },
      { header: "System Role", key: "role", width: 14, format: "text", sourceField: "role", transform: (v) => (v ? String(v).toUpperCase() : "STAFF") },
      { header: "Status", key: "is_active", width: 12, format: "text", sourceField: "is_active", transform: (v) => (v ? "ACTIVE" : "INACTIVE") },
      { header: "Assigned Shift", key: "assigned_shift", width: 16, format: "text", sourceField: "assigned_shift", defaultValue: "-" },
      { header: "Next Shift", key: "next_shift", width: 16, format: "text", sourceField: "next_shift", defaultValue: "-" },
      { header: "Shift Effective Date", key: "shift_effective_date", width: 20, format: "date", sourceField: "shift_effective_date", transform: formatDateOnly },
      { header: "Joining Date", key: "joining_date", width: 16, format: "date", sourceField: "joining_date", transform: formatDateOnly },
      { header: "Created At", key: "created_at", width: 18, format: "datetime", sourceField: "created_at", transform: formatDateTime },
      { header: "Updated At", key: "updated_at", width: 18, format: "datetime", sourceField: "updated_at", transform: formatDateTime },
    ],
  },

  // ── 3. STAFF ATTENDANCE ───────────────────────────────────────────────────
  {
    name: "Staff_Attendance",
    sourceTable: "staff_attendance",
    stableIdKey: "id",
    timestampKey: "updated_at",
    sortClauses: [
      { column: "record_date", ascending: false },
      { column: "check_in_time", ascending: false, nullsFirst: false },
      { column: "id", ascending: true },
    ],
    selectQuery: "id, staff_id, record_date, check_in_time, check_out_time, status, is_late, working_hours, late_minutes, shift, notes, profiles(full_name, email), created_at, updated_at",
    columns: [
      { header: "Record ID", key: "id", width: 36, format: "text", sourceField: "id" },
      { header: "Staff Name", key: "staff_name", width: 24, format: "text", sourceField: "profiles", transform: (v) => (v && v.full_name ? v.full_name : "-") },
      { header: "Staff Email", key: "staff_email", width: 28, format: "text", sourceField: "profiles", transform: (v) => (v && v.email ? v.email : "-") },
      { header: "Record Date", key: "record_date", width: 14, format: "date", sourceField: "record_date", transform: formatDateOnly },
      { header: "Shift", key: "shift", width: 14, format: "text", sourceField: "shift", defaultValue: "morning", transform: (v) => (v ? String(v).toUpperCase() : "-") },
      { header: "Check-In Time", key: "check_in_time", width: 18, format: "datetime", sourceField: "check_in_time", transform: formatDateTime },
      { header: "Check-Out Time", key: "check_out_time", width: 18, format: "datetime", sourceField: "check_out_time", transform: formatDateTime },
      { header: "Working Hours", key: "working_hours", width: 15, format: "number", sourceField: "working_hours", transform: (v) => formatNumber(v, 2) },
      { header: "Status", key: "status", width: 14, format: "text", sourceField: "status", transform: (v) => (v ? String(v).toUpperCase() : "PRESENT") },
      { header: "Is Late", key: "is_late", width: 10, format: "text", sourceField: "is_late", transform: formatBoolean },
      { header: "Late Mins", key: "late_minutes", width: 12, format: "number", sourceField: "late_minutes", defaultValue: 0 },
      { header: "Notes", key: "notes", width: 30, format: "text", sourceField: "notes", defaultValue: "-" },
      { header: "Updated At", key: "updated_at", width: 18, format: "datetime", sourceField: "updated_at", transform: formatDateTime },
    ],
  },

  // ── 4. LEAVE REQUESTS ─────────────────────────────────────────────────────
  {
    name: "Leave_Requests",
    sourceTable: "leave_requests",
    stableIdKey: "id",
    timestampKey: "updated_at",
    sortClauses: [
      { column: "start_date", ascending: false },
      { column: "created_at", ascending: false },
      { column: "id", ascending: true },
    ],
    selectQuery: "id, staff_id, start_date, end_date, leave_days, reason, status, approved_at, rejection_reason, applicant:profiles!leave_requests_staff_id_fkey(full_name), approver:profiles!leave_requests_approved_by_fkey(full_name), created_at, updated_at",
    columns: [
      { header: "Leave ID", key: "id", width: 36, format: "text", sourceField: "id" },
      { header: "Applicant", key: "applicant", width: 24, format: "text", sourceField: "applicant", transform: (v) => (v && v.full_name ? v.full_name : "-") },
      { header: "Start Date", key: "start_date", width: 14, format: "date", sourceField: "start_date", transform: formatDateOnly },
      { header: "End Date", key: "end_date", width: 14, format: "date", sourceField: "end_date", transform: formatDateOnly },
      { header: "Days", key: "leave_days", width: 10, format: "number", sourceField: "leave_days", transform: (v) => formatNumber(v, 1) },
      { header: "Reason", key: "reason", width: 32, format: "text", sourceField: "reason" },
      { header: "Status", key: "status", width: 14, format: "text", sourceField: "status", transform: (v) => (v ? String(v).toUpperCase() : "PENDING") },
      { header: "Reviewed By", key: "approver", width: 24, format: "text", sourceField: "approver", transform: (v) => (v && v.full_name ? v.full_name : "-") },
      { header: "Decision Date", key: "approved_at", width: 18, format: "datetime", sourceField: "approved_at", transform: formatDateTime },
      { header: "Rejection Reason", key: "rejection_reason", width: 30, format: "text", sourceField: "rejection_reason", defaultValue: "-" },
      { header: "Created At", key: "created_at", width: 18, format: "datetime", sourceField: "created_at", transform: formatDateTime },
    ],
  },

  // ── 5. TASKS ──────────────────────────────────────────────────────────────
  {
    name: "Tasks",
    sourceTable: "tasks",
    stableIdKey: "id",
    timestampKey: "updated_at",
    sortClauses: [
      { column: "due_date", ascending: false, nullsFirst: false },
      { column: "created_at", ascending: false },
      { column: "id", ascending: true },
    ],
    selectQuery: "id, title, description, assigned_to, assigned_by, due_date, priority, status, completed_at, assignee:profiles!tasks_assigned_to_fkey(full_name), assigner:profiles!tasks_assigned_by_fkey(full_name), created_at, updated_at",
    columns: [
      { header: "Task ID", key: "id", width: 36, format: "text", sourceField: "id" },
      { header: "Title", key: "title", width: 30, format: "text", sourceField: "title" },
      { header: "Assigned To", key: "assignee", width: 24, format: "text", sourceField: "assignee", transform: (v) => (v && v.full_name ? v.full_name : "-") },
      { header: "Assigned By", key: "assigner", width: 24, format: "text", sourceField: "assigner", transform: (v) => (v && v.full_name ? v.full_name : "-") },
      { header: "Priority", key: "priority", width: 14, format: "text", sourceField: "priority", transform: (v) => (v ? String(v).toUpperCase() : "MEDIUM") },
      { header: "Status", key: "status", width: 14, format: "text", sourceField: "status", transform: (v) => (v ? String(v).toUpperCase() : "PENDING") },
      { header: "Due Date", key: "due_date", width: 18, format: "datetime", sourceField: "due_date", transform: formatDateTime },
      { header: "Completed At", key: "completed_at", width: 18, format: "datetime", sourceField: "completed_at", transform: formatDateTime },
      { header: "Description", key: "description", width: 36, format: "text", sourceField: "description", defaultValue: "-" },
      { header: "Created At", key: "created_at", width: 18, format: "datetime", sourceField: "created_at", transform: formatDateTime },
    ],
  },

  // ── 6. TASK HISTORY ───────────────────────────────────────────────────────
  {
    name: "Task_History",
    sourceTable: "task_history",
    stableIdKey: "id",
    timestampKey: "created_at",
    sortClauses: [
      { column: "created_at", ascending: false },
      { column: "id", ascending: true },
    ],
    selectQuery: "id, task_id, changed_by, old_status, new_status, note, changer:profiles(full_name), created_at",
    columns: [
      { header: "History ID", key: "id", width: 36, format: "text", sourceField: "id" },
      { header: "Task ID", key: "task_id", width: 36, format: "text", sourceField: "task_id" },
      { header: "Changed By", key: "changer", width: 24, format: "text", sourceField: "changer", transform: (v) => (v && v.full_name ? v.full_name : "-") },
      { header: "Previous Status", key: "old_status", width: 16, format: "text", sourceField: "old_status", transform: (v) => (v ? String(v).toUpperCase() : "-") },
      { header: "New Status", key: "new_status", width: 16, format: "text", sourceField: "new_status", transform: (v) => (v ? String(v).toUpperCase() : "-") },
      { header: "Note", key: "note", width: 32, format: "text", sourceField: "note", defaultValue: "-" },
      { header: "Timestamp", key: "created_at", width: 18, format: "datetime", sourceField: "created_at", transform: formatDateTime },
    ],
  },

  // ── 7. APPOINTMENTS ───────────────────────────────────────────────────────
  {
    name: "Appointments",
    sourceTable: "appointments",
    stableIdKey: "id",
    timestampKey: "updated_at",
    sortClauses: [
      { column: "appointment_date", ascending: false },
      { column: "appointment_time", ascending: false, nullsFirst: false },
      { column: "id", ascending: true },
    ],
    selectQuery: "id, patient_id, department, doctor_id, appointment_date, appointment_time, appointment_type, status, notes, ai_booked, patients(patient_number, name), doctor:profiles(full_name), created_at, updated_at",
    columns: [
      { header: "Appointment ID", key: "id", width: 36, format: "text", sourceField: "id" },
      { header: "Patient Number", key: "patient_number", width: 18, format: "text", sourceField: "patients", transform: (v) => (v && v.patient_number ? v.patient_number : "-") },
      { header: "Patient Name", key: "patient_name", width: 26, format: "text", sourceField: "patients", transform: (v) => (v && v.name ? v.name : "-") },
      { header: "Department", key: "department", width: 14, format: "text", sourceField: "department", transform: (v) => (v ? String(v).toUpperCase() : "-") },
      { header: "Doctor", key: "doctor", width: 24, format: "text", sourceField: "doctor", transform: (v) => (v && v.full_name ? v.full_name : "-") },
      { header: "Date", key: "appointment_date", width: 14, format: "date", sourceField: "appointment_date", transform: formatDateOnly },
      { header: "Time", key: "appointment_time", width: 12, format: "text", sourceField: "appointment_time", defaultValue: "-" },
      { header: "Type", key: "appointment_type", width: 14, format: "text", sourceField: "appointment_type", transform: (v) => (v ? String(v).toUpperCase() : "REGULAR") },
      { header: "Status", key: "status", width: 14, format: "text", sourceField: "status", transform: (v) => (v ? String(v).toUpperCase() : "SCHEDULED") },
      { header: "AI Booked", key: "ai_booked", width: 12, format: "text", sourceField: "ai_booked", transform: formatBoolean },
      { header: "Notes", key: "notes", width: 32, format: "text", sourceField: "notes", defaultValue: "-" },
      { header: "Created At", key: "created_at", width: 18, format: "datetime", sourceField: "created_at", transform: formatDateTime },
      { header: "Updated At", key: "updated_at", width: 18, format: "datetime", sourceField: "updated_at", transform: formatDateTime },
    ],
  },

  // ── 8. INVENTORY CATALOG ──────────────────────────────────────────────────
  {
    name: "Inventory_Catalog",
    sourceTable: "inventory",
    stableIdKey: "id",
    timestampKey: "updated_at",
    sortClauses: [
      { column: "name", ascending: true },
      { column: "id", ascending: true },
    ],
    selectQuery: "id, name, category, department, sku, quantity, minimum_stock, unit, price, is_active, vendors(name), created_at, updated_at",
    columns: [
      { header: "Item ID", key: "id", width: 36, format: "text", sourceField: "id" },
      { header: "SKU", key: "sku", width: 16, format: "text", sourceField: "sku", defaultValue: "-" },
      { header: "Item Name", key: "name", width: 30, format: "text", sourceField: "name" },
      { header: "Category", key: "category", width: 18, format: "text", sourceField: "category" },
      { header: "Department", key: "department", width: 14, format: "text", sourceField: "department", transform: (v) => (v ? String(v).toUpperCase() : "GENERAL") },
      { header: "Unit", key: "unit", width: 12, format: "text", sourceField: "unit", defaultValue: "units" },
      { header: "Current Stock", key: "quantity", width: 15, format: "number", sourceField: "quantity", transform: (v) => formatNumber(v, 1) },
      { header: "Min Stock", key: "minimum_stock", width: 14, format: "number", sourceField: "minimum_stock", transform: (v) => formatNumber(v, 1) },
      { header: "Unit Price (INR)", key: "price", width: 16, format: "currency", sourceField: "price", transform: formatCurrency },
      { header: "Total Valuation (INR)", key: "total_valuation", width: 22, format: "currency", sourceField: "price", transform: (v, r) => formatCurrency((r.quantity || 0) * (r.price || 0)) },
      { header: "Preferred Vendor", key: "vendor", width: 24, format: "text", sourceField: "vendors", transform: (v) => (v && v.name ? v.name : "-") },
      { header: "Status", key: "is_active", width: 12, format: "text", sourceField: "is_active", transform: (v) => (v ? "ACTIVE" : "INACTIVE") },
      { header: "Updated At", key: "updated_at", width: 18, format: "datetime", sourceField: "updated_at", transform: formatDateTime },
    ],
  },

  // ── 9. INVENTORY BATCHES ──────────────────────────────────────────────────
  {
    name: "Inventory_Batches",
    sourceTable: "inventory_batches",
    stableIdKey: "id",
    timestampKey: "updated_at",
    sortClauses: [
      { column: "received_date", ascending: false, nullsFirst: false },
      { column: "created_at", ascending: false },
      { column: "id", ascending: true },
    ],
    selectQuery: "id, inventory_id, batch_number, received_quantity, remaining_quantity, unit_price, total_amount, expiry_date, received_date, inventory(name, sku), purchase_orders(purchase_order_number), created_at, updated_at",
    columns: [
      { header: "Batch ID", key: "id", width: 36, format: "text", sourceField: "id" },
      { header: "Batch Number", key: "batch_number", width: 18, format: "text", sourceField: "batch_number" },
      { header: "Item Name", key: "item_name", width: 28, format: "text", sourceField: "inventory", transform: (v) => (v && v.name ? v.name : "-") },
      { header: "SKU", key: "sku", width: 16, format: "text", sourceField: "inventory", transform: (v) => (v && v.sku ? v.sku : "-") },
      { header: "PO Number", key: "po_number", width: 20, format: "text", sourceField: "purchase_orders", transform: (v) => (v && v.purchase_order_number ? v.purchase_order_number : "-") },
      { header: "Received Date", key: "received_date", width: 16, format: "date", sourceField: "received_date", transform: formatDateOnly },
      { header: "Expiry Date", key: "expiry_date", width: 16, format: "date", sourceField: "expiry_date", transform: formatDateOnly },
      { header: "Received Qty", key: "received_quantity", width: 15, format: "number", sourceField: "received_quantity", transform: (v) => formatNumber(v, 1) },
      { header: "Remaining Qty", key: "remaining_quantity", width: 15, format: "number", sourceField: "remaining_quantity", transform: (v) => formatNumber(v, 1) },
      { header: "Unit Cost (INR)", key: "unit_price", width: 16, format: "currency", sourceField: "unit_price", transform: formatCurrency },
      { header: "Batch Value (INR)", key: "total_amount", width: 18, format: "currency", sourceField: "total_amount", transform: formatCurrency },
      { header: "Created At", key: "created_at", width: 18, format: "datetime", sourceField: "created_at", transform: formatDateTime },
    ],
  },

  // ── 10. STOCK TRANSACTIONS ────────────────────────────────────────────────
  {
    name: "Stock_Transactions",
    sourceTable: "inventory_transactions",
    stableIdKey: "id",
    timestampKey: "created_at",
    sortClauses: [
      { column: "created_at", ascending: false },
      { column: "id", ascending: true },
    ],
    selectQuery: "id, inventory_id, transaction_type, quantity, remarks, created_at, inventory(name), performer:profiles!performed_by(full_name), creator:profiles!created_by(full_name)",
    columns: [
      { header: "Transaction ID", key: "id", width: 36, format: "text", sourceField: "id" },
      { header: "Timestamp", key: "created_at", width: 18, format: "datetime", sourceField: "created_at", transform: formatDateTime },
      { header: "Item Name", key: "item_name", width: 28, format: "text", sourceField: "inventory", transform: (v) => (v && v.name ? v.name : "-") },
      { header: "Transaction Type", key: "transaction_type", width: 18, format: "text", sourceField: "transaction_type", transform: (v) => (v ? String(v).toUpperCase() : "-") },
      { header: "Quantity", key: "quantity", width: 14, format: "number", sourceField: "quantity", transform: (v) => formatNumber(v, 1) },
      { header: "Performed By", key: "performer", width: 24, format: "text", sourceField: "performer", transform: (v, r) => (v && v.full_name ? v.full_name : (r && r.creator && r.creator.full_name ? r.creator.full_name : (r && r.profiles && r.profiles.full_name ? r.profiles.full_name : "-"))) },
      { header: "Remarks", key: "remarks", width: 32, format: "text", sourceField: "remarks", defaultValue: "-" },
    ],
  },

  // ── 11. DEPARTMENT STOCK ──────────────────────────────────────────────────
  {
    name: "Department_Stock",
    sourceTable: "department_inventory",
    stableIdKey: "id",
    timestampKey: "updated_at",
    sortClauses: [
      { column: "updated_at", ascending: false },
      { column: "id", ascending: true },
    ],
    selectQuery: "id, department_id, quantity, minimum_stock, updated_at, departments(name), inventory(name, sku, unit)",
    columns: [
      { header: "Dept Stock ID", key: "id", width: 36, format: "text", sourceField: "id" },
      { header: "Department", key: "department", width: 16, format: "text", sourceField: "departments", transform: (v, r) => (v && v.name ? v.name : (r.department || "-")) },
      { header: "Item Name", key: "item_name", width: 28, format: "text", sourceField: "inventory", transform: (v, r) => (v && v.name ? v.name : (r.item_name || r.name || "-")) },
      { header: "SKU", key: "sku", width: 16, format: "text", sourceField: "inventory", transform: (v, r) => (v && v.sku ? v.sku : (r.sku || "-")) },
      { header: "Current Stock", key: "current_stock", width: 15, format: "number", sourceField: "quantity", transform: (v, r) => formatNumber(v !== undefined ? v : r.current_stock, 1) },
      { header: "Min Stock", key: "minimum_stock", width: 14, format: "number", sourceField: "minimum_stock", transform: (v) => formatNumber(v, 1) },
      { header: "Unit", key: "unit", width: 12, format: "text", sourceField: "inventory", transform: (v, r) => (v && v.unit ? v.unit : (r.unit || "units")) },
      { header: "Updated At", key: "updated_at", width: 18, format: "datetime", sourceField: "updated_at", transform: formatDateTime },
    ],
  },

  // ── 12. STOCK REQUESTS ────────────────────────────────────────────────────
  {
    name: "Stock_Requests",
    sourceTable: "stock_requests",
    stableIdKey: "id",
    timestampKey: "updated_at",
    sortClauses: [
      { column: "created_at", ascending: false },
      { column: "id", ascending: true },
    ],
    selectQuery: "id, request_number, department_id, status, request_notes, requested_by, created_at, updated_at, departments(name)",
    columns: [
      { header: "Request ID", key: "id", width: 36, format: "text", sourceField: "id" },
      { header: "Request Number", key: "request_number", width: 20, format: "text", sourceField: "request_number" },
      { header: "Department", key: "department", width: 16, format: "text", sourceField: "departments", transform: (v, r) => (v && v.name ? v.name : (r.department || "-")) },
      { header: "Requested By", key: "requester", width: 24, format: "text", sourceField: "requester", transform: (v, r) => (v && v.full_name ? v.full_name : (r && r.requester_name ? r.requester_name : "-")) },
      { header: "Status", key: "status", width: 16, format: "text", sourceField: "status", transform: (v) => (v ? String(v).toUpperCase() : "PENDING") },
      { header: "Notes", key: "notes", width: 30, format: "text", sourceField: "request_notes", transform: (v, r) => (v || r.notes || "-") },
      { header: "Created At", key: "created_at", width: 18, format: "datetime", sourceField: "created_at", transform: formatDateTime },
      { header: "Updated At", key: "updated_at", width: 18, format: "datetime", sourceField: "updated_at", transform: formatDateTime },
    ],
  },

  // ── 13. VENDORS ───────────────────────────────────────────────────────────
  {
    name: "Vendors",
    sourceTable: "vendors",
    stableIdKey: "id",
    timestampKey: "updated_at",
    sortClauses: [
      { column: "name", ascending: true },
      { column: "id", ascending: true },
    ],
    selectQuery: "id, name, contact_person, phone, email, address, products_supplied, remarks, created_at, updated_at",
    columns: [
      { header: "Vendor ID", key: "id", width: 36, format: "text", sourceField: "id" },
      { header: "Vendor Name", key: "name", width: 28, format: "text", sourceField: "name" },
      { header: "Contact Person", key: "contact_person", width: 24, format: "text", sourceField: "contact_person", defaultValue: "-" },
      { header: "Phone", key: "phone", width: 16, format: "text", sourceField: "phone", defaultValue: "-" },
      { header: "Email", key: "email", width: 28, format: "text", sourceField: "email", defaultValue: "-" },
      { header: "Address", key: "address", width: 32, format: "text", sourceField: "address", defaultValue: "-" },
      { header: "Supplied Products", key: "products_supplied", width: 28, format: "text", sourceField: "products_supplied", transform: (v) => (Array.isArray(v) ? v.join(", ") : "-") },
      { header: "Remarks", key: "remarks", width: 30, format: "text", sourceField: "remarks", defaultValue: "-" },
      { header: "Updated At", key: "updated_at", width: 18, format: "datetime", sourceField: "updated_at", transform: formatDateTime },
    ],
  },

  // ── 14. PURCHASE ORDERS ───────────────────────────────────────────────────
  {
    name: "Purchase_Orders",
    sourceTable: "purchase_orders",
    stableIdKey: "id",
    timestampKey: "updated_at",
    sortClauses: [
      { column: "order_date", ascending: false },
      { column: "created_at", ascending: false },
      { column: "id", ascending: true },
    ],
    selectQuery: "id, purchase_order_number, vendor_id, order_date, expected_delivery_date, actual_delivery_date, status, subtotal, total_amount, notes, created_by, ordered_by, created_at, updated_at, vendors(name)",
    columns: [
      { header: "PO ID", key: "id", width: 36, format: "text", sourceField: "id" },
      { header: "PO Number", key: "purchase_order_number", width: 22, format: "text", sourceField: "purchase_order_number" },
      { header: "Vendor Name", key: "vendor_name", width: 26, format: "text", sourceField: "vendors", transform: (v) => (v && v.name ? v.name : "-") },
      { header: "Order Date", key: "order_date", width: 14, format: "date", sourceField: "order_date", transform: formatDateOnly },
      { header: "Expected Delivery", key: "expected_delivery_date", width: 18, format: "date", sourceField: "expected_delivery_date", transform: formatDateOnly },
      { header: "Actual Delivery", key: "actual_delivery_date", width: 16, format: "date", sourceField: "actual_delivery_date", transform: formatDateOnly },
      { header: "Status", key: "status", width: 18, format: "text", sourceField: "status", transform: (v) => (v ? String(v).toUpperCase() : "DRAFT") },
      { header: "Subtotal (INR)", key: "subtotal", width: 16, format: "currency", sourceField: "subtotal", transform: formatCurrency },
      { header: "Total Amount (INR)", key: "total_amount", width: 18, format: "currency", sourceField: "total_amount", transform: formatCurrency },
      { header: "Created By", key: "creator", width: 22, format: "text", sourceField: "creator", transform: (v, r) => (v && v.full_name ? v.full_name : (r && r.creator_name ? r.creator_name : "-")) },
      { header: "Ordered By", key: "orderer", width: 22, format: "text", sourceField: "orderer", transform: (v, r) => (v && v.full_name ? v.full_name : (r && r.orderer_name ? r.orderer_name : "-")) },
      { header: "Notes", key: "notes", width: 30, format: "text", sourceField: "notes", defaultValue: "-" },
      { header: "Updated At", key: "updated_at", width: 18, format: "datetime", sourceField: "updated_at", transform: formatDateTime },
    ],
  },

  // ── 15. PURCHASE ORDER ITEMS ──────────────────────────────────────────────
  {
    name: "Purchase_Order_Items",
    sourceTable: "purchase_order_items",
    stableIdKey: "id",
    timestampKey: "updated_at",
    sortClauses: [
      { column: "created_at", ascending: false },
      { column: "id", ascending: true },
    ],
    selectQuery: "id, purchase_order_id, inventory_id, quantity, unit_price, total_amount, received_quantity, purchase_orders(purchase_order_number), inventory(name, sku, unit), created_at, updated_at",
    columns: [
      { header: "Item ID", key: "id", width: 36, format: "text", sourceField: "id" },
      { header: "PO Number", key: "po_number", width: 22, format: "text", sourceField: "purchase_orders", transform: (v) => (v && v.purchase_order_number ? v.purchase_order_number : "-") },
      { header: "Item Name", key: "item_name", width: 28, format: "text", sourceField: "inventory", transform: (v) => (v && v.name ? v.name : "-") },
      { header: "SKU", key: "sku", width: 16, format: "text", sourceField: "inventory", transform: (v) => (v && v.sku ? v.sku : "-") },
      { header: "Ordered Qty", key: "quantity", width: 14, format: "number", sourceField: "quantity", transform: (v) => formatNumber(v, 1) },
      { header: "Unit", key: "unit", width: 12, format: "text", sourceField: "inventory", transform: (v) => (v && v.unit ? v.unit : "units") },
      { header: "Unit Price (INR)", key: "unit_price", width: 16, format: "currency", sourceField: "unit_price", transform: formatCurrency },
      { header: "Total Price (INR)", key: "total_amount", width: 18, format: "currency", sourceField: "total_amount", transform: formatCurrency },
      { header: "Received Qty", key: "received_quantity", width: 15, format: "number", sourceField: "received_quantity", transform: (v) => formatNumber(v, 1) },
      { header: "Remaining Qty", key: "remaining_quantity", width: 15, format: "number", sourceField: "quantity", transform: (v, r) => formatNumber((r.quantity || 0) - (r.received_quantity || 0), 1) },
      { header: "Updated At", key: "updated_at", width: 18, format: "datetime", sourceField: "updated_at", transform: formatDateTime },
    ],
  },

  // ── 16. OPTICAL SALES ─────────────────────────────────────────────────────
  {
    name: "Optical_Sales",
    sourceTable: "sales",
    stableIdKey: "id",
    timestampKey: "created_at",
    sortClauses: [
      { column: "sale_date", ascending: false },
      { column: "created_at", ascending: false },
      { column: "id", ascending: true },
    ],
    selectQuery: "id, sale_number, patient_id, frame_brand, frame_name, quantity, amount, sale_date, sold_by, created_at, patients(name)",
    columns: [
      { header: "Sale ID", key: "id", width: 36, format: "text", sourceField: "id" },
      { header: "Sale Number", key: "sale_number", width: 18, format: "text", sourceField: "sale_number" },
      { header: "Sale Date", key: "sale_date", width: 14, format: "date", sourceField: "sale_date", transform: formatDateOnly },
      { header: "Patient Name", key: "patient_name", width: 24, format: "text", sourceField: "patients", transform: (v) => (v && v.name ? v.name : "-") },
      { header: "Frame Brand", key: "frame_brand", width: 20, format: "text", sourceField: "frame_brand", defaultValue: "-" },
      { header: "Frame Model", key: "frame_name", width: 22, format: "text", sourceField: "frame_name", defaultValue: "-" },
      { header: "Quantity", key: "quantity", width: 12, format: "number", sourceField: "quantity", defaultValue: 1 },
      { header: "Amount (INR)", key: "amount", width: 16, format: "currency", sourceField: "amount", transform: formatCurrency },
      { header: "Sold By", key: "seller", width: 22, format: "text", sourceField: "seller", transform: (v, r) => (v && v.full_name ? v.full_name : (r && r.sold_by_name ? r.sold_by_name : (r && r.profiles && r.profiles.full_name ? r.profiles.full_name : "-"))) },
      { header: "Created At", key: "created_at", width: 18, format: "datetime", sourceField: "created_at", transform: formatDateTime },
    ],
  },

  // ── 17. OPTICAL ORDERS ────────────────────────────────────────────────────
  {
    name: "Optical_Orders",
    sourceTable: "optical_orders",
    stableIdKey: "id",
    timestampKey: "updated_at",
    sortClauses: [
      { column: "created_at", ascending: false },
      { column: "id", ascending: true },
    ],
    selectQuery: "id, order_number, patient_id, order_type, prescription_details, frame_details, lens_details, order_status, delivery_date, payment_status, total_amount, patients(name, patient_number), created_at, updated_at",
    columns: [
      { header: "Order ID", key: "id", width: 36, format: "text", sourceField: "id" },
      { header: "Order Number", key: "order_number", width: 18, format: "text", sourceField: "order_number" },
      { header: "Patient Number", key: "patient_number", width: 18, format: "text", sourceField: "patients", transform: (v) => (v && v.patient_number ? v.patient_number : "-") },
      { header: "Patient Name", key: "patient_name", width: 24, format: "text", sourceField: "patients", transform: (v) => (v && v.name ? v.name : "-") },
      { header: "Order Type", key: "order_type", width: 16, format: "text", sourceField: "order_type", transform: (v) => (v ? String(v).toUpperCase() : "-") },
      { header: "Order Status", key: "order_status", width: 16, format: "text", sourceField: "order_status", transform: (v) => (v ? String(v).toUpperCase() : "PENDING") },
      { header: "Payment Status", key: "payment_status", width: 16, format: "text", sourceField: "payment_status", transform: (v) => (v ? String(v).toUpperCase() : "PENDING") },
      { header: "Delivery Date", key: "delivery_date", width: 14, format: "date", sourceField: "delivery_date", transform: formatDateOnly },
      { header: "Total Amount (INR)", key: "total_amount", width: 18, format: "currency", sourceField: "total_amount", transform: formatCurrency },
      { header: "Prescription Details", key: "prescription_details", width: 32, format: "text", sourceField: "prescription_details", transform: formatJsonb },
      { header: "Frame Details", key: "frame_details", width: 28, format: "text", sourceField: "frame_details", transform: formatJsonb },
      { header: "Lens Details", key: "lens_details", width: 28, format: "text", sourceField: "lens_details", transform: formatJsonb },
      { header: "Created At", key: "created_at", width: 18, format: "datetime", sourceField: "created_at", transform: formatDateTime },
      { header: "Updated At", key: "updated_at", width: 18, format: "datetime", sourceField: "updated_at", transform: formatDateTime },
    ],
  },

  // ── 18. DENTAL LAB CASES ──────────────────────────────────────────────────
  {
    name: "Dental_Lab_Cases",
    sourceTable: "dental_lab",
    stableIdKey: "id",
    timestampKey: "updated_at",
    sortClauses: [
      { column: "sent_date", ascending: false, nullsFirst: false },
      { column: "created_at", ascending: false },
      { column: "id", ascending: true },
    ],
    selectQuery: "id, case_number, patient_id, case_type, status, sent_date, ready_date, delivered_date, remarks, patients(name, patient_number), created_at, updated_at",
    columns: [
      { header: "Case ID", key: "id", width: 36, format: "text", sourceField: "id" },
      { header: "Case Number", key: "case_number", width: 18, format: "text", sourceField: "case_number" },
      { header: "Patient Number", key: "patient_number", width: 18, format: "text", sourceField: "patients", transform: (v) => (v && v.patient_number ? v.patient_number : "-") },
      { header: "Patient Name", key: "patient_name", width: 24, format: "text", sourceField: "patients", transform: (v) => (v && v.name ? v.name : "-") },
      { header: "Case Type", key: "case_type", width: 22, format: "text", sourceField: "case_type", defaultValue: "-" },
      { header: "Status", key: "status", width: 16, format: "text", sourceField: "status", transform: (v) => (v ? String(v).toUpperCase() : "PROCESSING") },
      { header: "Sent Date", key: "sent_date", width: 14, format: "date", sourceField: "sent_date", transform: formatDateOnly },
      { header: "Ready Date", key: "ready_date", width: 14, format: "date", sourceField: "ready_date", transform: formatDateOnly },
      { header: "Delivered Date", key: "delivered_date", width: 16, format: "date", sourceField: "delivered_date", transform: formatDateOnly },
      { header: "Remarks", key: "remarks", width: 30, format: "text", sourceField: "remarks", defaultValue: "-" },
      { header: "Updated At", key: "updated_at", width: 18, format: "datetime", sourceField: "updated_at", transform: formatDateTime },
    ],
  },

  // ── 19. BILLING INVOICES ──────────────────────────────────────────────────
  {
    name: "Billing_Invoices",
    sourceTable: "billing",
    stableIdKey: "id",
    timestampKey: "updated_at",
    sortClauses: [
      { column: "created_at", ascending: false },
      { column: "id", ascending: true },
    ],
    selectQuery: "id, invoice_number, patient_id, department, subtotal, discount, total_amount, amount_paid, payment_status, payment_mode, notes, billed_by, created_at, updated_at, patients(name, patient_number)",
    columns: [
      { header: "Invoice ID", key: "id", width: 36, format: "text", sourceField: "id" },
      { header: "Invoice Number", key: "invoice_number", width: 22, format: "text", sourceField: "invoice_number" },
      { header: "Patient Number", key: "patient_number", width: 18, format: "text", sourceField: "patients", transform: (v, r) => (v && v.patient_number ? v.patient_number : (r.patient_number || "-")) },
      { header: "Patient Name", key: "patient_name", width: 24, format: "text", sourceField: "patients", transform: (v, r) => (v && v.name ? v.name : (r.patient_name || "-")) },
      { header: "Department", key: "department", width: 14, format: "text", sourceField: "department", transform: (v) => (v ? String(v).toUpperCase() : "-") },
      { header: "Invoice Date", key: "invoice_date", width: 14, format: "date", sourceField: "created_at", transform: (v, r) => formatDateOnly(r.invoice_date || v) },
      { header: "Subtotal (INR)", key: "subtotal", width: 16, format: "currency", sourceField: "subtotal", transform: formatCurrency },
      { header: "Discount (INR)", key: "discount", width: 16, format: "currency", sourceField: "discount", transform: formatCurrency },
      { header: "Tax (INR)", key: "tax_amount", width: 14, format: "currency", sourceField: "tax_amount", defaultValue: 0.0, transform: formatCurrency },
      { header: "Total Amount (INR)", key: "total_amount", width: 18, format: "currency", sourceField: "total_amount", transform: formatCurrency },
      { header: "Paid Amount (INR)", key: "paid_amount", width: 18, format: "currency", sourceField: "amount_paid", transform: (v, r) => formatCurrency(v !== undefined ? v : r.paid_amount) },
      { header: "Balance (INR)", key: "balance_amount", width: 16, format: "currency", sourceField: "total_amount", transform: (_v, r) => formatCurrency(Math.max(0, (r.total_amount || 0) - (r.amount_paid !== undefined ? r.amount_paid : (r.paid_amount || 0)))) },
      { header: "Status", key: "status", width: 14, format: "text", sourceField: "payment_status", transform: (v, r) => (v || r.status ? String(v || r.status).toUpperCase() : "PENDING") },
      { header: "Payment Mode", key: "payment_method", width: 16, format: "text", sourceField: "payment_mode", transform: (v, r) => (v || r.payment_method ? String(v || r.payment_method).toUpperCase() : "-") },
      { header: "Billed By", key: "billed_by", width: 22, format: "text", sourceField: "billed_by", transform: (v, r) => (v && v.full_name ? v.full_name : (r && r.billed_by_name ? r.billed_by_name : (r && r.profiles && r.profiles.full_name ? r.profiles.full_name : "-"))) },
      { header: "Updated At", key: "updated_at", width: 18, format: "datetime", sourceField: "updated_at", transform: formatDateTime },
    ],
  },

  // ── 20. BILLING LINE ITEMS ────────────────────────────────────────────────
  {
    name: "Billing_Line_Items",
    sourceTable: "billing_items",
    stableIdKey: "id",
    timestampKey: "created_at",
    sortClauses: [
      { column: "created_at", ascending: false },
      { column: "id", ascending: true },
    ],
    selectQuery: "id, billing_id, service_id, service_name, quantity, unit_price, total_amount, is_custom, created_at, billing(invoice_number)",
    columns: [
      { header: "Line Item ID", key: "id", width: 36, format: "text", sourceField: "id" },
      { header: "Invoice Number", key: "invoice_number", width: 22, format: "text", sourceField: "billing", transform: (v, r) => (v && v.invoice_number ? v.invoice_number : (r.invoice_number || "-")) },
      { header: "Item Type", key: "item_type", width: 14, format: "text", sourceField: "is_custom", transform: (v, r) => (r.item_type ? String(r.item_type).toUpperCase() : (v === true ? "CUSTOM" : "SERVICE")) },
      { header: "Item / Service Name", key: "item_name", width: 30, format: "text", sourceField: "service_name", transform: (v, r) => (v || r.item_name || "-") },
      { header: "Quantity", key: "quantity", width: 12, format: "number", sourceField: "quantity", transform: (v) => formatNumber(v, 1) },
      { header: "Unit Rate (INR)", key: "unit_price", width: 16, format: "currency", sourceField: "unit_price", transform: formatCurrency },
      { header: "Total Amount (INR)", key: "total_price", width: 18, format: "currency", sourceField: "total_amount", transform: (v, r) => formatCurrency(v !== undefined ? v : r.total_price) },
      { header: "Created At", key: "created_at", width: 18, format: "datetime", sourceField: "created_at", transform: formatDateTime },
    ],
  },

  // ── 21. BILLING PAYMENTS ──────────────────────────────────────────────────
  {
    name: "Billing_Payments",
    sourceTable: "billing_payments",
    stableIdKey: "id",
    timestampKey: "created_at",
    sortClauses: [
      { column: "paid_at", ascending: false, nullsFirst: false },
      { column: "created_at", ascending: false },
      { column: "id", ascending: true },
    ],
    selectQuery: "id, billing_id, amount, payment_mode, payment_reference, paid_at, recorded_by, notes, created_at, billing(invoice_number)",
    columns: [
      { header: "Payment ID", key: "id", width: 36, format: "text", sourceField: "id" },
      { header: "Invoice Number", key: "invoice_number", width: 22, format: "text", sourceField: "billing", transform: (v, r) => (v && v.invoice_number ? v.invoice_number : (r.invoice_number || "-")) },
      { header: "Payment Date", key: "payment_date", width: 18, format: "datetime", sourceField: "paid_at", transform: (v, r) => formatDateTime(v || r.payment_date) },
      { header: "Amount Paid (INR)", key: "amount", width: 18, format: "currency", sourceField: "amount", transform: formatCurrency },
      { header: "Payment Method", key: "payment_method", width: 16, format: "text", sourceField: "payment_mode", transform: (v, r) => (v || r.payment_method ? String(v || r.payment_method).toUpperCase() : "CASH") },
      { header: "Transaction Ref", key: "transaction_reference", width: 24, format: "text", sourceField: "payment_reference", defaultValue: "-", transform: (v, r) => (v || r.transaction_reference || "-") },
      { header: "Received By", key: "received_by", width: 22, format: "text", sourceField: "received_by", transform: (v, r) => (v && v.full_name ? v.full_name : (r && r.received_by_name ? r.received_by_name : (r && r.profiles && r.profiles.full_name ? r.profiles.full_name : "-"))) },
      { header: "Notes", key: "notes", width: 28, format: "text", sourceField: "notes", defaultValue: "-" },
      { header: "Recorded At", key: "created_at", width: 18, format: "datetime", sourceField: "created_at", transform: formatDateTime },
    ],
  },
];

/**
 * In-memory chronological sort helper.
 * Sorts an array of records according to the worksheet's sortClauses.
 * Handles null/undefined date values safely (nulls last for descending sorts).
 * Uses ISO timestamp parsing for date comparisons and deterministic string/number
 * secondary tie-breakers.
 */
export function sortRecordsForWorksheet(
  sheetName: string,
  records: Record<string, any>[]
): Record<string, any>[] {
  const sheetDef = MASTER_WORKSHEETS.find((w) => w.name === sheetName);
  if (!sheetDef || !sheetDef.sortClauses || sheetDef.sortClauses.length === 0) {
    return records;
  }

  const clauses = sheetDef.sortClauses;

  return [...records].sort((a, b) => {
    for (const clause of clauses) {
      const col = clause.column;
      const asc = clause.ascending;
      const valA = a[col];
      const valB = b[col];

      // Handle null / undefined
      if (valA === valB) continue;
      if (valA === null || valA === undefined || valA === "") {
        return clause.nullsFirst ? -1 : 1;
      }
      if (valB === null || valB === undefined || valB === "") {
        return clause.nullsFirst ? 1 : -1;
      }

      // Check if values can be parsed as numbers
      if (typeof valA === "number" && typeof valB === "number") {
        if (valA !== valB) {
          return asc ? valA - valB : valB - valA;
        }
        continue;
      }

      // Check if values are dates or ISO strings
      const isDateA = typeof valA === "string" && (valA.includes("-") || !isNaN(Date.parse(valA)));
      const isDateB = typeof valB === "string" && (valB.includes("-") || !isNaN(Date.parse(valB)));
      if (isDateA && isDateB) {
        const timeA = Date.parse(valA);
        const timeB = Date.parse(valB);
        if (!isNaN(timeA) && !isNaN(timeB)) {
          if (timeA !== timeB) {
            return asc ? timeA - timeB : timeB - timeA;
          }
          continue;
        }
      }

      // Fallback string locale comparison
      const cmp = String(valA).localeCompare(String(valB));
      if (cmp !== 0) {
        return asc ? cmp : -cmp;
      }
    }
    return 0;
  });
}

// ============================================================================
// SECTION 3: OPENXML WORKBOOK BUILDER (ExcelJS)
// ============================================================================

// supabase/functions/sync-excel-workbook/workbook_builder.ts
// ─────────────────────────────────────────────────────────────────────────────
// ExcelJS Master Workbook Generator (Sprint 9.2)
// Builds styled, normalized .xlsx workbooks for MKES CARE+ in Deno runtime.
// ─────────────────────────────────────────────────────────────────────────────
export interface WorkbookBuildOptions {
  includeSampleRows?: boolean;
  clinicName?: string;
}

/**
 * Sanitizes untrusted text strings to prevent spreadsheet formula injection.
 * If a string (or the string after stripping leading whitespace and control characters)
 * begins with '=', '+', '-', '@', tab, or carriage return, prepends an apostrophe (').
 *
 * Legitimate numeric values (numbers and currency) are preserved as numeric types
 * and never converted to strings or prepended with an apostrophe.
 */
export function sanitizeSpreadsheetString(val: string): string {
  if (!val) return val;
  if (val.startsWith("\t") || val.startsWith("\r")) {
    return `'${val}`;
  }
  const trimmed = val.replace(/^[\s\u0000-\u001F]+/, "");
  if (trimmed.length > 0) {
    const firstChar = trimmed[0];
    if (
      firstChar === "=" ||
      firstChar === "+" ||
      firstChar === "-" ||
      firstChar === "@" ||
      firstChar === "\t" ||
      firstChar === "\r"
    ) {
      return `'${val}`;
    }
  }
  return val;
}

export class MasterWorkbookBuilder {
  private workbook: ExcelJS.Workbook;

  constructor(clinicName = "MKES CARE+ Clinical Management Platform") {
    const WorkbookConstructor =
      (ExcelJS as any)?.Workbook ||
      (ExcelJS as any)?.default?.Workbook ||
      (ExcelJS as any)?.default ||
      (ExcelJS as any);
    this.workbook = new WorkbookConstructor();
    this.workbook.creator = clinicName;
    this.workbook.lastModifiedBy = "MKES CARE+ Automated Synchronizer";
    this.workbook.created = new Date();
    this.workbook.modified = new Date();
    this.workbook.properties.date1904 = false;
  }

  /**
   * Initializes all 21 normalized worksheets according to the authoritative schema.
   */
  public initializeAllWorksheets(options: WorkbookBuildOptions = {}): ExcelJS.Workbook {
    for (const sheetDef of MASTER_WORKSHEETS) {
      this.createWorksheet(sheetDef, options);
    }
    return this.workbook;
  }

  /**
   * Initializes a single worksheet for individual sheet download.
   */
  public initializeWorksheet(sheetName: string, options: WorkbookBuildOptions = {}): ExcelJS.Worksheet {
    const sheetDef = MASTER_WORKSHEETS.find((w) => w.name === sheetName);
    if (!sheetDef) {
      throw new Error(`Worksheet definition not found for name: ${sheetName}`);
    }
    return this.createWorksheet(sheetDef, options);
  }

  /**
   * Creates and styles an individual worksheet.
   */
  public createWorksheet(
    sheetDef: ExcelWorksheetDefinition,
    _options: WorkbookBuildOptions = {}
  ): ExcelJS.Worksheet {
    const sheet = this.workbook.addWorksheet(sheetDef.name, {
      views: [{ state: "frozen", xSplit: 0, ySplit: 1, activeCell: "A2" }],
      properties: { defaultRowHeight: 20 },
    });

    // Configure columns
    sheet.columns = sheetDef.columns.map((col) => ({
      header: col.header,
      key: col.key,
      width: Math.max(col.width, 12),
      style: this.getColumnStyle(col.format),
    }));

    // Style the header row (Row 1)
    const headerRow = sheet.getRow(1);
    headerRow.height = 28;
    headerRow.eachCell((cell) => {
      cell.fill = {
        type: "pattern",
        pattern: "solid",
        fgColor: { argb: "FF0D9488" }, // MKES Teal (#0D9488)
      };
      cell.font = {
        name: "Segoe UI",
        size: 11,
        bold: true,
        color: { argb: "FFFFFFFF" }, // White text
      };
      cell.alignment = {
        vertical: "middle",
        horizontal: "left",
        wrapText: true,
      };
      cell.border = {
        bottom: { style: "medium", color: { argb: "FF0F766E" } },
      };
    });

    return sheet;
  }

  /**
   * Appends a batch of rows to a worksheet, with an optional row index offset for alternating styling.
   */
  public appendWorksheetRows(
    sheetName: string,
    records: Record<string, any>[],
    rowIndexOffset = 0
  ): void {
    const sheetDef = MASTER_WORKSHEETS.find((w) => w.name === sheetName);
    if (!sheetDef) {
      throw new Error(`Worksheet definition not found for name: ${sheetName}`);
    }

    const sheet = this.workbook.getWorksheet(sheetName) || this.createWorksheet(sheetDef);

    records.forEach((record, index) => {
      const rowValues: Record<string, any> = {};

      for (const col of sheetDef.columns) {
        // Enforce strict redaction of sensitive fields
        if (
          sheetDef.sensitiveExcludedFields?.includes(col.sourceField) ||
          col.key.toLowerCase().includes("salary")
        ) {
          continue;
        }

        const rawValue = record[col.sourceField];
        let transformed = col.transform
          ? col.transform(rawValue, record)
          : rawValue;

        if (transformed === null || transformed === undefined || transformed === "") {
          transformed = col.defaultValue ?? "-";
        } else if (typeof transformed === "string") {
          // Prevent formula injection on string cells
          transformed = sanitizeSpreadsheetString(transformed);
        } else if (typeof transformed === "object" && !Array.isArray(transformed)) {
          // Guard against untrusted objects that might contain a formula property
          if ("formula" in transformed) {
            transformed = sanitizeSpreadsheetString(String(transformed.formula));
          }
        }

        rowValues[col.key] = transformed;
      }

      const row = sheet.addRow(rowValues);
      row.height = 22;

      // Zebra striping: alternate light gray / white accounting for batch offset
      const isEven = (rowIndexOffset + index) % 2 === 0;
      row.eachCell((cell) => {
        if (isEven) {
          cell.fill = {
            type: "pattern",
            pattern: "solid",
            fgColor: { argb: "FFF8FAFC" }, // Slate 50
          };
        }
        cell.font = { name: "Segoe UI", size: 10 };
        cell.alignment = { vertical: "middle" };
        cell.border = {
          bottom: { style: "thin", color: { argb: "FFE2E8F0" } },
        };
      });
    });
  }

  /**
   * Populates a worksheet with database records, applying transforms and formatting.
   */
  public populateWorksheetRows(
    sheetName: string,
    records: Record<string, any>[]
  ): void {
    this.appendWorksheetRows(sheetName, records, 0);
  }

  /**
   * Returns current data row count (excluding header row) for a given worksheet.
   */
  public getWorksheetRowCount(sheetName: string): number {
    const sheet = this.workbook.getWorksheet(sheetName);
    if (!sheet) return 0;
    return Math.max(0, sheet.rowCount - 1);
  }

  /**
   * Generates the binary Uint8Array buffer of the complete .xlsx file.
   */
  public async writeBuffer(): Promise<Uint8Array> {
    const buffer = await this.workbook.xlsx.writeBuffer();
    return new Uint8Array(buffer);
  }

  /**
   * Helper returning standard cell formatting per column type.
   */
  private getColumnStyle(format: string): Partial<ExcelJS.Style> {
    switch (format) {
      case "currency":
        return { numFmt: '"₹"#,##0.00' };
      case "date":
        return { numFmt: "yyyy-mm-dd" };
      case "datetime":
        return { numFmt: "yyyy-mm-dd hh:mm" };
      case "number":
        return { numFmt: "#,##0.0" };
      default:
        return {};
    }
  }
}

// ============================================================================
// SECTION 4: EDGE FUNCTION ROUTER & EXECUTION CONTROLLER
// ============================================================================

// supabase/functions/sync-excel-workbook/index.ts
// ─────────────────────────────────────────────────────────────────────────────
// Supabase Edge Function: sync-excel-workbook (Sprint 9.4)
// Handles schema discovery, template generation, full historical export,
// and 5-minute incremental synchronization with transactional outbox,
// distributed leases, fencing tokens, and atomic version publication.
//
// Authentication:
//   - Admin JWT (Bearer <user_jwt>): active administrator (role = 'admin', is_active = true)
//   - Service-Role (Bearer <service_role_key>): trusted automated scheduler
// ─────────────────────────────────────────────────────────────────────────────




const corsHeaders = {
  "Access-Control-Allow-Origin": "*",
  "Access-Control-Allow-Headers":
    "authorization, x-client-info, apikey, content-type",
  "Access-Control-Allow-Methods": "POST, GET, OPTIONS",
};

function respond(
  data: Record<string, any> | Uint8Array,
  status = 200,
  contentType = "application/json",
  filename = MASTER_WORKBOOK_FILENAME
) {
  if (data instanceof Uint8Array) {
    return new Response(data, {
      status,
      headers: {
        ...corsHeaders,
        "Content-Type": contentType,
        "Content-Disposition": `attachment; filename="${filename}"`,
      },
    });
  }
  return new Response(JSON.stringify(data), {
    status,
    headers: { ...corsHeaders, "Content-Type": "application/json" },
  });
}

async function resolveProfileReferences(
  client: any,
  tableName: string,
  rows: any[]
): Promise<void> {
  if (!rows || rows.length === 0) return;

  const idFieldMap: Record<string, string[]> = {
    stock_requests: ["requested_by", "reviewed_by", "fulfilled_by"],
    sales: ["sold_by"],
    purchase_orders: ["created_by", "ordered_by"],
    billing: ["billed_by"],
    billing_payments: ["recorded_by"],
  };

  const fields = idFieldMap[tableName];
  if (!fields) return;

  const userIds = new Set<string>();
  for (const r of rows) {
    for (const f of fields) {
      if (r[f] && typeof r[f] === "string") {
        userIds.add(r[f]);
      }
    }
  }

  if (userIds.size === 0) return;

  try {
    const { data: profiles } = await client
      .from("profiles")
      .select("id, full_name, email")
      .in("id", Array.from(userIds));

    if (!profiles || profiles.length === 0) return;

    const profMap = new Map<string, { full_name: string; email?: string }>();
    for (const p of profiles) {
      profMap.set(p.id, { full_name: p.full_name, email: p.email });
    }

    for (const r of rows) {
      if (tableName === "stock_requests") {
        if (r.requested_by && profMap.has(r.requested_by)) {
          r.requester = profMap.get(r.requested_by);
          r.requester_name = r.requester.full_name;
        }
      } else if (tableName === "sales") {
        if (r.sold_by && profMap.has(r.sold_by)) {
          r.profiles = profMap.get(r.sold_by);
          r.seller = r.profiles;
          r.sold_by_name = r.profiles.full_name;
        }
      } else if (tableName === "purchase_orders") {
        if (r.created_by && profMap.has(r.created_by)) {
          r.creator = profMap.get(r.created_by);
          r.creator_name = r.creator.full_name;
        }
        if (r.ordered_by && profMap.has(r.ordered_by)) {
          r.orderer = profMap.get(r.ordered_by);
          r.orderer_name = r.orderer.full_name;
        }
      } else if (tableName === "billing") {
        if (r.billed_by && profMap.has(r.billed_by)) {
          r.profiles = profMap.get(r.billed_by);
          r.billed_by_name = r.profiles.full_name;
        }
      } else if (tableName === "billing_payments") {
        if (r.recorded_by && profMap.has(r.recorded_by)) {
          r.profiles = profMap.get(r.recorded_by);
          r.received_by_name = r.profiles.full_name;
        }
      }
    }
  } catch {
    // Non-fatal: formatters provide fallback '-'
  }
}

Deno.serve(async (req: Request) => {
  // CORS preflight
  if (req.method === "OPTIONS") {
    return respond({ ok: true }, 200);
  }

  try {
    const authHeader =
      req.headers.get("Authorization") || req.headers.get("authorization");
    const apikeyHeader =
      req.headers.get("apikey") ||
      req.headers.get("apiKey") ||
      req.headers.get("x-api-key");

    if (!authHeader && !apikeyHeader) {
      return respond({ error: "Missing Authorization or apikey header" }, 401);
    }

    const supabaseUrl = Deno.env.get("SUPABASE_URL");
    const supabaseAnonKey = Deno.env.get("SUPABASE_ANON_KEY");
    const serviceRoleKey =
      Deno.env.get("SUPABASE_SERVICE_ROLE_KEY") ||
      Deno.env.get("SERVICE_ROLE_KEY");

    if (!supabaseUrl || !supabaseAnonKey || !serviceRoleKey) {
      return respond(
        { error: "Server misconfiguration: missing Supabase environment variables" },
        500
      );
    }

    const adminClient = createClient(supabaseUrl, serviceRoleKey);

    // Helper: strip quotes, whitespace, and all leading "Bearer " prefixes
    const sanitizeToken = (token: string | null | undefined): string => {
      if (!token) return "";
      let t = token.trim().replace(/^["']|["']$/g, "").trim();
      while (/^Bearer\s+/i.test(t)) {
        t = t.replace(/^Bearer\s+/i, "").trim().replace(/^["']|["']$/g, "").trim();
      }
      return t;
    };

    const cleanAuthToken = sanitizeToken(authHeader);
    const cleanApiKey = sanitizeToken(apikeyHeader);
    const cleanServiceRoleKey = sanitizeToken(serviceRoleKey);

    // Dual-authentication: Service-Role (Scheduler) or Admin JWT (User)
    let callerUserId: string | null = null;
    const isServiceRole =
      (cleanAuthToken.length > 0 && cleanAuthToken === cleanServiceRoleKey) ||
      (cleanApiKey.length > 0 && cleanApiKey === cleanServiceRoleKey);

    if (!isServiceRole) {
      // Helper to inspect JWT claims safely without external libs
      const parseJwtRole = (token: string): string | null => {
        try {
          const parts = token.split(".");
          if (parts.length !== 3) return null;
          const base64 = parts[1].replace(/-/g, "+").replace(/_/g, "/");
          const json = JSON.parse(atob(base64));
          return json?.role || null;
        } catch {
          return null;
        }
      };

      const incomingRole = parseJwtRole(cleanAuthToken) || parseJwtRole(cleanApiKey);

      if (incomingRole === "anon") {
        console.error(
          "[Auth] Rejected: Incoming credentials contain 'role': 'anon'. Scheduled Edge Function invocations require the 'service_role' secret key."
        );
        return respond(
          {
            error:
              "Unauthorized: received anon key instead of service_role key. Scheduled Edge Function invocations require the service_role key. Update your Supabase Vault secret 'service_role_key' with the service_role secret from Supabase Dashboard -> Project Settings -> API.",
            receivedRole: "anon",
          },
          401
        );
      }

      if (incomingRole === "service_role") {
        const inFp = cleanAuthToken.length > 10 ? `${cleanAuthToken.slice(0, 6)}...${cleanAuthToken.slice(-4)}` : "too_short";
        const expFp = cleanServiceRoleKey.length > 10 ? `${cleanServiceRoleKey.slice(0, 6)}...${cleanServiceRoleKey.slice(-4)}` : "not_configured";
        console.error(
          `[Auth] Rejected: Incoming service_role key mismatch against SUPABASE_SERVICE_ROLE_KEY. Incoming: ${inFp} (len ${cleanAuthToken.length}), Expected: ${expFp} (len ${cleanServiceRoleKey.length})`
        );
        return respond(
          {
            error:
              "Unauthorized: service_role key mismatch. The key provided in the request does not match SUPABASE_SERVICE_ROLE_KEY in the Edge Function environment. Please verify that the secret stored in Supabase Vault matches the active service_role key in Project Settings -> API.",
            incomingFingerprint: inFp,
            expectedFingerprint: expFp,
          },
          401
        );
      }

      // If not service_role and not anon, authenticate as end-user session
      const callerClient = createClient(supabaseUrl, supabaseAnonKey, {
        global: { headers: { Authorization: `Bearer ${cleanAuthToken}` } },
      });

      const {
        data: { user: callerUser },
        error: userErr,
      } = await callerClient.auth.getUser();

      if (userErr || !callerUser) {
        return respond({ error: "Unauthorized: invalid user session" }, 401);
      }

      const { data: profile, error: profileErr } = await adminClient
        .from("profiles")
        .select("role, is_active")
        .eq("id", callerUser.id)
        .maybeSingle();

      if (profileErr || !profile) {
        return respond({ error: "Unauthorized: profile not found" }, 401);
      }

      if (profile.role !== "admin" || !profile.is_active) {
        return respond(
          { error: "Forbidden: only active administrators can access workbook synchronization" },
          403
        );
      }

      callerUserId = callerUser.id;
    }

    // Process action
    let action = "get-schema";
    let requestBody: Record<string, any> = {};
    if (req.method === "POST") {
      try {
        requestBody = await req.json();
        action = requestBody.action || action;
      } catch {
        // Fallback
      }
    }

    const url = new URL(req.url);
    if (url.searchParams.has("action")) {
      action = url.searchParams.get("action")!;
    }

    switch (action) {
      case "get-schema": {
        return respond({
          workbookName: MASTER_WORKBOOK_FILENAME,
          worksheetCount: MASTER_WORKSHEETS.length,
          worksheets: MASTER_WORKSHEETS.map((w) => ({
            name: w.name,
            sourceTable: w.sourceTable,
            stableIdKey: w.stableIdKey,
            timestampKey: w.timestampKey,
            columnCount: w.columns.length,
            columns: w.columns.map((c) => ({
              header: c.header,
              key: c.key,
              width: c.width,
              format: c.format,
            })),
            sensitiveExcludedFields: w.sensitiveExcludedFields || [],
          })),
        });
      }

      case "get-active-version": {
        const { data: activeVersion, error: verErr } = await adminClient
          .rpc("get_excel_sync_active_version")
          .maybeSingle();

        if (verErr) {
          return respond({ error: `Failed to fetch active version: ${verErr.message}` }, 500);
        }

        if (!activeVersion) {
          return respond({ activeVersion: null, message: "No active workbook version found" });
        }

        return respond({
          activeVersion: {
            versionId: activeVersion.version_id,
            versionNumber: activeVersion.version_number,
            storagePath: activeVersion.storage_path,
            fileSizeBytes: activeVersion.file_size_bytes,
            totalRecords: activeVersion.total_records,
            worksheetsSummary: activeVersion.worksheets_summary,
            publishedAt: activeVersion.published_at,
            syncId: activeVersion.sync_id,
          },
        });
      }

      case "generate-template": {
        const builder = new MasterWorkbookBuilder();
        builder.initializeAllWorksheets();
        const buffer = await builder.writeBuffer();

        if (url.searchParams.get("download") === "true") {
          return respond(
            buffer,
            200,
            "application/vnd.openxmlformats-officedocument.spreadsheetml.sheet"
          );
        }

        return respond({
          success: true,
          workbookName: MASTER_WORKBOOK_FILENAME,
          worksheetCount: MASTER_WORKSHEETS.length,
          fileSizeBytes: buffer.byteLength,
          generatedAt: new Date().toISOString(),
        });
      }

      case "download-worksheet":
      case "export-worksheet": {
        const targetSheetName =
          requestBody.worksheet_name ||
          requestBody.sheet ||
          url.searchParams.get("worksheet_name") ||
          url.searchParams.get("sheet");

        if (!targetSheetName) {
          return respond(
            {
              error: "Missing required parameter 'worksheet_name'.",
              availableWorksheets: MASTER_WORKSHEETS.map((w) => w.name),
            },
            400
          );
        }

        const sheetDef = MASTER_WORKSHEETS.find(
          (w) => w.name.toLowerCase() === String(targetSheetName).trim().toLowerCase()
        );

        if (!sheetDef) {
          return respond(
            {
              error: `Worksheet [${targetSheetName}] not found.`,
              availableWorksheets: MASTER_WORKSHEETS.map((w) => w.name),
            },
            404
          );
        }

        const builder = new MasterWorkbookBuilder();
        builder.initializeWorksheet(sheetDef.name);

        const PAGE_SIZE = 500;
        let offset = 0;
        let sheetFetchedCount = 0;
        let expectedTotalCount: number | null = null;
        const allRows: Record<string, any>[] = [];

        while (true) {
          let query = adminClient
            .from(sheetDef.sourceTable)
            .select(sheetDef.selectQuery, { count: "exact" });

          if (sheetDef.sortClauses && sheetDef.sortClauses.length > 0) {
            for (const sort of sheetDef.sortClauses) {
              query = query.order(sort.column, {
                ascending: sort.ascending,
                nullsFirst: sort.nullsFirst ?? false,
              });
            }
          } else {
            query = query.order(sheetDef.stableIdKey, { ascending: true });
          }

          const { data: pageData, count: totalCount, error: queryErr } =
            await query.range(offset, offset + PAGE_SIZE - 1);

          if (queryErr) {
            return respond(
              {
                error: `Worksheet [${sheetDef.name}] query failed on table [${sheetDef.sourceTable}]: ${queryErr.message}`,
              },
              500
            );
          }

          if (totalCount !== null) {
            expectedTotalCount = totalCount;
          }

          if (!pageData || pageData.length === 0) {
            break;
          }

          await resolveProfileReferences(adminClient, sheetDef.sourceTable, pageData);
          allRows.push(...pageData);
          sheetFetchedCount += pageData.length;
          offset += pageData.length;

          if (totalCount !== null && offset >= totalCount) {
            break;
          }
        }

        if (expectedTotalCount !== null && sheetFetchedCount !== expectedTotalCount) {
          return respond(
            {
              error: `Record count mismatch for worksheet [${sheetDef.name}]: fetched ${sheetFetchedCount} rows out of ${expectedTotalCount} expected rows.`,
            },
            500
          );
        }

        const sortedRows = sortRecordsForWorksheet(sheetDef.name, allRows);
        builder.appendWorksheetRows(sheetDef.name, sortedRows, 0);

        const buffer = await builder.writeBuffer();
        if (
          buffer.byteLength < 4 ||
          buffer[0] !== 0x50 ||
          buffer[1] !== 0x4B ||
          buffer[2] !== 0x03 ||
          buffer[3] !== 0x04
        ) {
          return respond(
            { error: "Generated worksheet workbook buffer failed PK ZIP signature validation" },
            500
          );
        }

        const fileName = `MKES_CARE_Plus_${sheetDef.name}.xlsx`;

        // Direct stream download
        if (url.searchParams.get("download") === "true" || requestBody.download === true) {
          return respond(
            buffer,
            200,
            "application/vnd.openxmlformats-officedocument.spreadsheetml.sheet",
            fileName
          );
        }

        // Upload to storage under sheets/ and generate signed URL
        const sheetStoragePath = `sheets/${fileName}`;
        const { error: uploadErr } = await adminClient.storage
          .from("clinic-excel-sync")
          .upload(sheetStoragePath, buffer, {
            contentType:
              "application/vnd.openxmlformats-officedocument.spreadsheetml.sheet",
            upsert: true,
          });

        if (uploadErr) {
          return respond(
            { error: `Storage upload failed for worksheet [${sheetDef.name}]: ${uploadErr.message}` },
            500
          );
        }

        const { data: signedData, error: signErr } = await adminClient.storage
          .from("clinic-excel-sync")
          .createSignedUrl(sheetStoragePath, 3600);

        if (signErr) {
          return respond(
            { error: `Signed URL generation failed for worksheet [${sheetDef.name}]: ${signErr.message}` },
            500
          );
        }

        const result: SingleWorksheetExportResult = {
          success: true,
          worksheetName: sheetDef.name,
          fileName,
          storagePath: `clinic-excel-sync/${sheetStoragePath}`,
          recordCount: sortedRows.length,
          fileSizeBytes: buffer.byteLength,
          downloadUrl: signedData?.signedUrl,
        };

        return respond(result);
      }

      case "sync-incremental": {
        const syncId = crypto.randomUUID();
        const startTime = new Date();
        const syncType = isServiceRole ? "scheduled" : requestBody.sync_type || "manual";

        // 1. Acquire distributed lease with fencing generation
        const { data: leaseData, error: leaseErr } = await adminClient
          .rpc("acquire_excel_sync_lease", {
            p_holder_id: syncId,
            p_ttl_seconds: 300,
          });

        if (leaseErr) {
          return respond({ error: `Lease acquisition error: ${leaseErr.message}` }, 500);
        }

        const lease = Array.isArray(leaseData) ? leaseData[0] : leaseData;
        if (!lease || !lease.acquired) {
          return respond({
            success: true,
            status: "already_running",
            message: "A synchronization worker is already running or holding active lease.",
            currentHolder: lease?.current_holder,
            expiresAt: lease?.expires_at,
          });
        }

        const fencingToken = lease.fencing_token;

        // 2. Initialize sync state audit record
        await adminClient.from("excel_sync_state").insert({
          id: syncId,
          sync_type: syncType,
          status: "in_progress",
          started_at: startTime.toISOString(),
          triggered_by: callerUserId,
          records_upserted: 0,
          file_size_bytes: 0,
          storage_path: `clinic-excel-sync/versions/MKES_CARE_Plus_Master_${syncId}.xlsx`,
          worksheets_synced: [],
        });

        // 3. Claim pending outbox mutation events
        const { data: claimData, error: claimErr } = await adminClient
          .rpc("claim_excel_sync_outbox_events", {
            p_sync_id: syncId,
            p_limit: 2000,
          });

        if (claimErr) {
          await adminClient.rpc("release_excel_sync_lease", {
            p_holder_id: syncId,
            p_fencing_token: fencingToken,
          });
          return respond({ error: `Outbox claim failed: ${claimErr.message}` }, 500);
        }

        const claimInfo = Array.isArray(claimData) ? claimData[0] : claimData;
        const eventsClaimed = claimInfo?.claimed_count ?? 0;

        const { data: activeVersion } = await adminClient
          .rpc("get_excel_sync_active_version")
          .maybeSingle();

        if (!activeVersion) {
          await adminClient.rpc("release_excel_sync_lease", {
            p_holder_id: syncId,
            p_fencing_token: fencingToken,
          });
          await adminClient
            .from("excel_sync_state")
            .update({
              status: "failed",
              completed_at: new Date().toISOString(),
              error_message:
                "No active baseline workbook exists. Please initialize the baseline with a full historical export first.",
            })
            .eq("id", syncId);

          return respond(
            {
              success: false,
              status: "failed",
              syncId,
              error:
                "No active baseline workbook exists. Please initialize the baseline with a full historical export first.",
            },
            400
          );
        }

        // 4. Fast No-Op Exit if outbox has no pending mutations
        if (eventsClaimed === 0) {
          // Release lease immediately and finalize audit
          await adminClient.rpc("release_excel_sync_lease", {
            p_holder_id: syncId,
            p_fencing_token: fencingToken,
          });

          const endTime = new Date();
          await adminClient
            .from("excel_sync_state")
            .update({
              status: "success",
              completed_at: endTime.toISOString(),
              records_upserted: 0,
              file_size_bytes: activeVersion.file_size_bytes,
              storage_path: activeVersion.storage_path,
              error_message: null,
            })
            .eq("id", syncId);

          const noOpResult: IncrementalSyncResult = {
            success: true,
            status: "no_op",
            syncId,
            versionId: activeVersion.version_id,
            versionNumber: activeVersion.version_number,
            fencingToken,
            totalRecords: activeVersion.total_records,
            fileSizeBytes: activeVersion.file_size_bytes,
            storagePath: activeVersion.storage_path,
            durationMs: endTime.getTime() - startTime.getTime(),
            eventsProcessed: 0,
          };
          return respond(noOpResult);
        }

        // 5. Full Regeneration of all 21 worksheets from authoritative DB
        try {
          const builder = new MasterWorkbookBuilder();
          builder.initializeAllWorksheets();

          const PAGE_SIZE = 500;
          let totalExportedRecords = 0;
          const worksheetSummaries: WorksheetExportSummary[] = [];
          const checkpointsData: Array<{
            worksheetName: string;
            sourceTable: string;
            highWaterMark: string;
            recordCount: number;
          }> = [];

          for (const sheetDef of MASTER_WORKSHEETS) {
            let offset = 0;
            let sheetFetchedCount = 0;
            let maxTimestamp = "1970-01-01T00:00:00.000Z";
            let expectedTotalCount: number | null = null;

            while (true) {
              let query = adminClient
                .from(sheetDef.sourceTable)
                .select(sheetDef.selectQuery, { count: "exact" });

              if (sheetDef.sortClauses && sheetDef.sortClauses.length > 0) {
                for (const sort of sheetDef.sortClauses) {
                  query = query.order(sort.column, {
                    ascending: sort.ascending,
                    nullsFirst: sort.nullsFirst ?? false,
                  });
                }
              } else {
                query = query.order(sheetDef.stableIdKey, { ascending: true });
              }

              const { data: pageData, count: totalCount, error: queryErr } =
                await query.range(offset, offset + PAGE_SIZE - 1);

              if (queryErr) {
                throw new Error(
                  `Worksheet [${sheetDef.name}] query failed on table [${sheetDef.sourceTable}]: ${queryErr.message}`
                );
              }

              if (totalCount !== null) {
                expectedTotalCount = totalCount;
              }

              if (!pageData || pageData.length === 0) {
                break;
              }

              for (const row of pageData) {
                const ts = row[sheetDef.timestampKey];
                if (ts && typeof ts === "string" && ts > maxTimestamp) {
                  maxTimestamp = ts;
                }
              }

              await resolveProfileReferences(adminClient, sheetDef.sourceTable, pageData);
              const sortedPage = sortRecordsForWorksheet(sheetDef.name, pageData);
              builder.appendWorksheetRows(sheetDef.name, sortedPage, offset);
              sheetFetchedCount += pageData.length;
              offset += pageData.length;

              if (totalCount !== null && offset >= totalCount) {
                break;
              }
            }

            if (expectedTotalCount !== null && sheetFetchedCount !== expectedTotalCount) {
              throw new Error(
                `Record count mismatch for worksheet [${sheetDef.name}]: fetched ${sheetFetchedCount} rows out of ${expectedTotalCount} expected rows.`
              );
            }

            worksheetSummaries.push({
              worksheetName: sheetDef.name,
              sourceTable: sheetDef.sourceTable,
              recordCount: sheetFetchedCount,
              highWaterMark: maxTimestamp,
              status: sheetFetchedCount > 0 ? "success" : "empty",
            });

            checkpointsData.push({
              worksheetName: sheetDef.name,
              sourceTable: sheetDef.sourceTable,
              highWaterMark: maxTimestamp,
              recordCount: sheetFetchedCount,
            });

            totalExportedRecords += sheetFetchedCount;
          }

          // 6. Build and validate XLSX binary package
          const buffer = await builder.writeBuffer();

          if (
            buffer.byteLength < 4 ||
            buffer[0] !== 0x50 ||
            buffer[1] !== 0x4B ||
            buffer[2] !== 0x03 ||
            buffer[3] !== 0x04
          ) {
            throw new Error("Generated workbook buffer failed PK ZIP signature validation");
          }

          // 7. Upload to unique immutable version path in private storage
          const versionId = crypto.randomUUID();
          const versionStoragePath = `versions/MKES_CARE_Plus_Master_${versionId}.xlsx`;

          const { error: uploadErr } = await adminClient.storage
            .from("clinic-excel-sync")
            .upload(versionStoragePath, buffer, {
              contentType:
                "application/vnd.openxmlformats-officedocument.spreadsheetml.sheet",
              upsert: false,
            });

          if (uploadErr) {
            throw new Error(`Storage version upload failed: ${uploadErr.message}`);
          }

          // 8. Atomic Database Publication & Checkpoint Commitment RPC
          const { data: pubData, error: pubErr } = await adminClient.rpc(
            "publish_excel_sync_version",
            {
              p_holder_id: syncId,
              p_fencing_token: fencingToken,
              p_sync_id: syncId,
              p_version_id: versionId,
              p_storage_path: `clinic-excel-sync/${versionStoragePath}`,
              p_file_size_bytes: buffer.byteLength,
              p_total_records: totalExportedRecords,
              p_worksheets_summary: worksheetSummaries,
              p_checkpoints: checkpointsData,
              p_claim_id: syncId,
            }
          );

          if (pubErr) {
            throw new Error(`Publication RPC failed: ${pubErr.message}`);
          }

          // 9. Best-effort update of canonical storage pointer (database remains authoritative)
          try {
            await adminClient.storage
              .from("clinic-excel-sync")
              .upload(MASTER_WORKBOOK_FILENAME, buffer, {
                contentType:
                  "application/vnd.openxmlformats-officedocument.spreadsheetml.sheet",
                upsert: true,
              });
          } catch {
            // Non-fatal: DB version pointer guarantees consistency
          }

          const endTime = new Date();
          const durationMs = endTime.getTime() - startTime.getTime();

          const result: IncrementalSyncResult = {
            success: true,
            status: "success",
            syncId,
            versionId,
            versionNumber: pubData?.version_number ?? 1,
            fencingToken,
            totalRecords: totalExportedRecords,
            fileSizeBytes: buffer.byteLength,
            storagePath: `clinic-excel-sync/${versionStoragePath}`,
            durationMs,
            eventsProcessed: eventsClaimed,
            worksheetSummaries,
          };

          return respond(result);
        } catch (workerErr: any) {
          const errMsg = workerErr?.message || "Incremental sync execution failed";

          // Safely release lease and mark failed state
          try {
            await adminClient.rpc("release_excel_sync_lease", {
              p_holder_id: syncId,
              p_fencing_token: fencingToken,
            });
          } catch {
            // Ignore lease release error during failure recovery
          }

          await adminClient
            .from("excel_sync_state")
            .update({
              status: "failed",
              completed_at: new Date().toISOString(),
              error_message: errMsg,
            })
            .eq("id", syncId);

          return respond(
            {
              success: false,
              status: "failed",
              syncId,
              error: errMsg,
            },
            500
          );
        }
      }

      case "export-historical": {
        const syncId = crypto.randomUUID();
        const startTime = new Date();
        const syncType = requestBody.sync_type || "initial";

        // Acquire lease for historical export as well to prevent concurrency conflicts
        const { data: leaseData } = await adminClient.rpc(
          "acquire_excel_sync_lease",
          {
            p_holder_id: syncId,
            p_ttl_seconds: 600,
          }
        );

        const lease = Array.isArray(leaseData) ? leaseData[0] : leaseData;
        if (lease && !lease.acquired) {
          return respond(
            {
              success: false,
              error: "Another synchronization worker is currently active. Please try again later.",
            },
            409
          );
        }

        const fencingToken = lease?.fencing_token ?? 1;

        // Record sync state
        await adminClient.from("excel_sync_state").insert({
          id: syncId,
          sync_type: syncType,
          status: "in_progress",
          started_at: startTime.toISOString(),
          triggered_by: callerUserId,
          records_upserted: 0,
          file_size_bytes: 0,
          storage_path: `clinic-excel-sync/${MASTER_WORKBOOK_FILENAME}`,
          worksheets_synced: [],
        });

        const builder = new MasterWorkbookBuilder();
        builder.initializeAllWorksheets();

        const PAGE_SIZE = 500;
        let totalExportedRecords = 0;
        const worksheetSummaries: WorksheetExportSummary[] = [];
        const successfulSheets: string[] = [];
        const checkpointsData: Array<{
          worksheetName: string;
          sourceTable: string;
          highWaterMark: string;
          recordCount: number;
        }> = [];

        try {
          for (const sheetDef of MASTER_WORKSHEETS) {
            let offset = 0;
            let sheetFetchedCount = 0;
            let maxTimestamp = "1970-01-01T00:00:00.000Z";
            let expectedTotalCount: number | null = null;

            while (true) {
              let query = adminClient
                .from(sheetDef.sourceTable)
                .select(sheetDef.selectQuery, { count: "exact" });

              if (sheetDef.sortClauses && sheetDef.sortClauses.length > 0) {
                for (const sort of sheetDef.sortClauses) {
                  query = query.order(sort.column, {
                    ascending: sort.ascending,
                    nullsFirst: sort.nullsFirst ?? false,
                  });
                }
              } else {
                query = query.order(sheetDef.stableIdKey, { ascending: true });
              }

              const { data: pageData, count: totalCount, error: queryErr } =
                await query.range(offset, offset + PAGE_SIZE - 1);

              if (queryErr) {
                throw new Error(
                  `Worksheet [${sheetDef.name}] query failed on table [${sheetDef.sourceTable}]: ${queryErr.message}`
                );
              }

              if (totalCount !== null) {
                expectedTotalCount = totalCount;
              }

              if (!pageData || pageData.length === 0) {
                break;
              }

              for (const row of pageData) {
                const ts = row[sheetDef.timestampKey];
                if (ts && typeof ts === "string" && ts > maxTimestamp) {
                  maxTimestamp = ts;
                }
              }

              await resolveProfileReferences(adminClient, sheetDef.sourceTable, pageData);
              const sortedPage = sortRecordsForWorksheet(sheetDef.name, pageData);
              builder.appendWorksheetRows(sheetDef.name, sortedPage, offset);
              sheetFetchedCount += pageData.length;
              offset += pageData.length;

              if (totalCount !== null && offset >= totalCount) {
                break;
              }
            }

            if (expectedTotalCount !== null && sheetFetchedCount !== expectedTotalCount) {
              throw new Error(
                `Record count mismatch for worksheet [${sheetDef.name}]: fetched ${sheetFetchedCount} rows out of ${expectedTotalCount} expected rows.`
              );
            }

            worksheetSummaries.push({
              worksheetName: sheetDef.name,
              sourceTable: sheetDef.sourceTable,
              recordCount: sheetFetchedCount,
              highWaterMark: maxTimestamp,
              status: sheetFetchedCount > 0 ? "success" : "empty",
            });
            checkpointsData.push({
              worksheetName: sheetDef.name,
              sourceTable: sheetDef.sourceTable,
              highWaterMark: maxTimestamp,
              recordCount: sheetFetchedCount,
            });

            successfulSheets.push(sheetDef.name);
            totalExportedRecords += sheetFetchedCount;
          }

          const buffer = await builder.writeBuffer();

          // Upload immutable version
          const versionId = crypto.randomUUID();
          const versionStoragePath = `versions/MKES_CARE_Plus_Master_${versionId}.xlsx`;

          await adminClient.storage
            .from("clinic-excel-sync")
            .upload(versionStoragePath, buffer, {
              contentType:
                "application/vnd.openxmlformats-officedocument.spreadsheetml.sheet",
              upsert: false,
            });

          // Upload canonical copy
          await adminClient.storage
            .from("clinic-excel-sync")
            .upload(MASTER_WORKBOOK_FILENAME, buffer, {
              contentType:
                "application/vnd.openxmlformats-officedocument.spreadsheetml.sheet",
              upsert: true,
            });

          // Publish version and update checkpoints atomically
          await adminClient.rpc("publish_excel_sync_version", {
            p_holder_id: syncId,
            p_fencing_token: fencingToken,
            p_sync_id: syncId,
            p_version_id: versionId,
            p_storage_path: `clinic-excel-sync/${versionStoragePath}`,
            p_file_size_bytes: buffer.byteLength,
            p_total_records: totalExportedRecords,
            p_worksheets_summary: worksheetSummaries,
            p_checkpoints: checkpointsData,
            p_claim_id: null,
          });

          const endTime = new Date();
          const durationMs = endTime.getTime() - startTime.getTime();

          if (url.searchParams.get("download") === "true") {
            return respond(
              buffer,
              200,
              "application/vnd.openxmlformats-officedocument.spreadsheetml.sheet"
            );
          }

          const result: HistoricalExportResult = {
            success: true,
            syncId,
            totalRecords: totalExportedRecords,
            fileSizeBytes: buffer.byteLength,
            storagePath: `clinic-excel-sync/${versionStoragePath}`,
            durationMs,
            worksheetSummaries,
          };

          return respond(result);
        } catch (exportErr: any) {
          const errMsg = exportErr?.message || "Historical export failed";

          try {
            await adminClient.rpc("release_excel_sync_lease", {
              p_holder_id: syncId,
              p_fencing_token: fencingToken,
            });
          } catch {
            // Ignore
          }

          await adminClient
            .from("excel_sync_state")
            .update({
              status: "failed",
              completed_at: new Date().toISOString(),
              error_message: errMsg,
            })
            .eq("id", syncId);

          return respond(
            {
              success: false,
              syncId,
              error: errMsg,
              worksheetsCompleted: successfulSheets,
            },
            500
          );
        }
      }

      default:
        return respond({ error: `Unknown action: ${action}` }, 400);
    }
  } catch (e: any) {
    return respond({ error: e?.message || "Internal server error" }, 500);
  }
});

