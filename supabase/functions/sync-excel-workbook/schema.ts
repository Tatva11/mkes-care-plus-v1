// supabase/functions/sync-excel-workbook/schema.ts
// ─────────────────────────────────────────────────────────────────────────────
// Master Workbook & Worksheet Schema Definitions (Sprint 9.2)
// Defines all normalized worksheets, column mappings, stable IDs, formatting,
// and sensitive field redaction rules.
// ─────────────────────────────────────────────────────────────────────────────

import { ExcelWorksheetDefinition } from "./types.ts";

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
    // salary is strictly excluded to protect compensation privacy
    sensitiveExcludedFields: ["salary"],
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
    selectQuery: "id, inventory_id, transaction_type, quantity, remarks, created_at, inventory(name), profiles(full_name)",
    columns: [
      { header: "Transaction ID", key: "id", width: 36, format: "text", sourceField: "id" },
      { header: "Timestamp", key: "created_at", width: 18, format: "datetime", sourceField: "created_at", transform: formatDateTime },
      { header: "Item Name", key: "item_name", width: 28, format: "text", sourceField: "inventory", transform: (v) => (v && v.name ? v.name : "-") },
      { header: "Transaction Type", key: "transaction_type", width: 18, format: "text", sourceField: "transaction_type", transform: (v) => (v ? String(v).toUpperCase() : "-") },
      { header: "Quantity", key: "quantity", width: 14, format: "number", sourceField: "quantity", transform: (v) => formatNumber(v, 1) },
      { header: "Performed By", key: "performer", width: 24, format: "text", sourceField: "profiles", transform: (v) => (v && v.full_name ? v.full_name : "-") },
      { header: "Remarks", key: "remarks", width: 32, format: "text", sourceField: "remarks", defaultValue: "-" },
    ],
  },

  // ── 11. DEPARTMENT STOCK ──────────────────────────────────────────────────
  {
    name: "Department_Stock",
    sourceTable: "department_inventory",
    stableIdKey: "id",
    timestampKey: "updated_at",
    selectQuery: "id, department, current_stock, minimum_stock, updated_at, inventory(name, sku, unit)",
    columns: [
      { header: "Dept Stock ID", key: "id", width: 36, format: "text", sourceField: "id" },
      { header: "Department", key: "department", width: 16, format: "text", sourceField: "department", transform: (v) => (v ? String(v).toUpperCase() : "-") },
      { header: "Item Name", key: "item_name", width: 28, format: "text", sourceField: "inventory", transform: (v) => (v && v.name ? v.name : "-") },
      { header: "SKU", key: "sku", width: 16, format: "text", sourceField: "inventory", transform: (v) => (v && v.sku ? v.sku : "-") },
      { header: "Current Stock", key: "current_stock", width: 15, format: "number", sourceField: "current_stock", transform: (v) => formatNumber(v, 1) },
      { header: "Min Stock", key: "minimum_stock", width: 14, format: "number", sourceField: "minimum_stock", transform: (v) => formatNumber(v, 1) },
      { header: "Unit", key: "unit", width: 12, format: "text", sourceField: "inventory", transform: (v) => (v && v.unit ? v.unit : "units") },
      { header: "Updated At", key: "updated_at", width: 18, format: "datetime", sourceField: "updated_at", transform: formatDateTime },
    ],
  },

  // ── 12. STOCK REQUESTS ────────────────────────────────────────────────────
  {
    name: "Stock_Requests",
    sourceTable: "stock_requests",
    stableIdKey: "id",
    timestampKey: "updated_at",
    selectQuery: "id, request_number, department, status, notes, profiles(full_name), created_at, updated_at",
    columns: [
      { header: "Request ID", key: "id", width: 36, format: "text", sourceField: "id" },
      { header: "Request Number", key: "request_number", width: 20, format: "text", sourceField: "request_number" },
      { header: "Department", key: "department", width: 16, format: "text", sourceField: "department", transform: (v) => (v ? String(v).toUpperCase() : "-") },
      { header: "Requested By", key: "requester", width: 24, format: "text", sourceField: "profiles", transform: (v) => (v && v.full_name ? v.full_name : "-") },
      { header: "Status", key: "status", width: 16, format: "text", sourceField: "status", transform: (v) => (v ? String(v).toUpperCase() : "PENDING") },
      { header: "Notes", key: "notes", width: 30, format: "text", sourceField: "notes", defaultValue: "-" },
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
    selectQuery: "id, purchase_order_number, vendor_id, order_date, expected_delivery_date, actual_delivery_date, status, subtotal, total_amount, notes, vendors(name), creator:profiles!purchase_orders_created_by_fkey(full_name), orderer:profiles!purchase_orders_ordered_by_fkey(full_name), created_at, updated_at",
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
      { header: "Created By", key: "creator", width: 22, format: "text", sourceField: "creator", transform: (v) => (v && v.full_name ? v.full_name : "-") },
      { header: "Ordered By", key: "orderer", width: 22, format: "text", sourceField: "orderer", transform: (v) => (v && v.full_name ? v.full_name : "-") },
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
    selectQuery: "id, sale_number, patient_id, frame_brand, frame_name, quantity, amount, sale_date, sold_by, patients(name), profiles(full_name), created_at",
    columns: [
      { header: "Sale ID", key: "id", width: 36, format: "text", sourceField: "id" },
      { header: "Sale Number", key: "sale_number", width: 18, format: "text", sourceField: "sale_number" },
      { header: "Sale Date", key: "sale_date", width: 14, format: "date", sourceField: "sale_date", transform: formatDateOnly },
      { header: "Patient Name", key: "patient_name", width: 24, format: "text", sourceField: "patients", transform: (v) => (v && v.name ? v.name : "-") },
      { header: "Frame Brand", key: "frame_brand", width: 20, format: "text", sourceField: "frame_brand", defaultValue: "-" },
      { header: "Frame Model", key: "frame_name", width: 22, format: "text", sourceField: "frame_name", defaultValue: "-" },
      { header: "Quantity", key: "quantity", width: 12, format: "number", sourceField: "quantity", defaultValue: 1 },
      { header: "Amount (INR)", key: "amount", width: 16, format: "currency", sourceField: "amount", transform: formatCurrency },
      { header: "Sold By", key: "seller", width: 22, format: "text", sourceField: "profiles", transform: (v) => (v && v.full_name ? v.full_name : "-") },
      { header: "Created At", key: "created_at", width: 18, format: "datetime", sourceField: "created_at", transform: formatDateTime },
    ],
  },

  // ── 17. OPTICAL ORDERS ────────────────────────────────────────────────────
  {
    name: "Optical_Orders",
    sourceTable: "optical_orders",
    stableIdKey: "id",
    timestampKey: "updated_at",
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
    selectQuery: "id, invoice_number, patient_id, department, invoice_date, subtotal, discount, tax_amount, total_amount, paid_amount, balance_amount, status, payment_method, notes, patients(name, patient_number), profiles(full_name), created_at, updated_at",
    columns: [
      { header: "Invoice ID", key: "id", width: 36, format: "text", sourceField: "id" },
      { header: "Invoice Number", key: "invoice_number", width: 22, format: "text", sourceField: "invoice_number" },
      { header: "Patient Number", key: "patient_number", width: 18, format: "text", sourceField: "patients", transform: (v) => (v && v.patient_number ? v.patient_number : "-") },
      { header: "Patient Name", key: "patient_name", width: 24, format: "text", sourceField: "patients", transform: (v) => (v && v.name ? v.name : "-") },
      { header: "Department", key: "department", width: 14, format: "text", sourceField: "department", transform: (v) => (v ? String(v).toUpperCase() : "-") },
      { header: "Invoice Date", key: "invoice_date", width: 14, format: "date", sourceField: "invoice_date", transform: formatDateOnly },
      { header: "Subtotal (INR)", key: "subtotal", width: 16, format: "currency", sourceField: "subtotal", transform: formatCurrency },
      { header: "Discount (INR)", key: "discount", width: 16, format: "currency", sourceField: "discount", transform: formatCurrency },
      { header: "Tax (INR)", key: "tax_amount", width: 14, format: "currency", sourceField: "tax_amount", transform: formatCurrency },
      { header: "Total Amount (INR)", key: "total_amount", width: 18, format: "currency", sourceField: "total_amount", transform: formatCurrency },
      { header: "Paid Amount (INR)", key: "paid_amount", width: 18, format: "currency", sourceField: "paid_amount", transform: formatCurrency },
      { header: "Balance (INR)", key: "balance_amount", width: 16, format: "currency", sourceField: "balance_amount", transform: formatCurrency },
      { header: "Status", key: "status", width: 14, format: "text", sourceField: "status", transform: (v) => (v ? String(v).toUpperCase() : "PENDING") },
      { header: "Payment Mode", key: "payment_method", width: 16, format: "text", sourceField: "payment_method", transform: (v) => (v ? String(v).toUpperCase() : "-") },
      { header: "Billed By", key: "billed_by", width: 22, format: "text", sourceField: "profiles", transform: (v) => (v && v.full_name ? v.full_name : "-") },
      { header: "Updated At", key: "updated_at", width: 18, format: "datetime", sourceField: "updated_at", transform: formatDateTime },
    ],
  },

  // ── 20. BILLING LINE ITEMS ────────────────────────────────────────────────
  {
    name: "Billing_Line_Items",
    sourceTable: "billing_items",
    stableIdKey: "id",
    timestampKey: "created_at",
    selectQuery: "id, billing_id, item_type, item_name, quantity, unit_price, total_price, billing(invoice_number), created_at",
    columns: [
      { header: "Line Item ID", key: "id", width: 36, format: "text", sourceField: "id" },
      { header: "Invoice Number", key: "invoice_number", width: 22, format: "text", sourceField: "billing", transform: (v) => (v && v.invoice_number ? v.invoice_number : "-") },
      { header: "Item Type", key: "item_type", width: 14, format: "text", sourceField: "item_type", transform: (v) => (v ? String(v).toUpperCase() : "SERVICE") },
      { header: "Item / Service Name", key: "item_name", width: 30, format: "text", sourceField: "item_name" },
      { header: "Quantity", key: "quantity", width: 12, format: "number", sourceField: "quantity", transform: (v) => formatNumber(v, 1) },
      { header: "Unit Rate (INR)", key: "unit_price", width: 16, format: "currency", sourceField: "unit_price", transform: formatCurrency },
      { header: "Total Amount (INR)", key: "total_price", width: 18, format: "currency", sourceField: "total_price", transform: formatCurrency },
      { header: "Created At", key: "created_at", width: 18, format: "datetime", sourceField: "created_at", transform: formatDateTime },
    ],
  },

  // ── 21. BILLING PAYMENTS ──────────────────────────────────────────────────
  {
    name: "Billing_Payments",
    sourceTable: "billing_payments",
    stableIdKey: "id",
    timestampKey: "created_at",
    selectQuery: "id, billing_id, payment_date, amount, payment_method, transaction_reference, notes, billing(invoice_number), profiles(full_name), created_at",
    columns: [
      { header: "Payment ID", key: "id", width: 36, format: "text", sourceField: "id" },
      { header: "Invoice Number", key: "invoice_number", width: 22, format: "text", sourceField: "billing", transform: (v) => (v && v.invoice_number ? v.invoice_number : "-") },
      { header: "Payment Date", key: "payment_date", width: 18, format: "datetime", sourceField: "payment_date", transform: formatDateTime },
      { header: "Amount Paid (INR)", key: "amount", width: 18, format: "currency", sourceField: "amount", transform: formatCurrency },
      { header: "Payment Method", key: "payment_method", width: 16, format: "text", sourceField: "payment_method", transform: (v) => (v ? String(v).toUpperCase() : "CASH") },
      { header: "Transaction Ref", key: "transaction_reference", width: 24, format: "text", sourceField: "transaction_reference", defaultValue: "-" },
      { header: "Received By", key: "received_by", width: 22, format: "text", sourceField: "profiles", transform: (v) => (v && v.full_name ? v.full_name : "-") },
      { header: "Notes", key: "notes", width: 28, format: "text", sourceField: "notes", defaultValue: "-" },
      { header: "Recorded At", key: "created_at", width: 18, format: "datetime", sourceField: "created_at", transform: formatDateTime },
    ],
  },
];
