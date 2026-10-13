import 'package:flutter/foundation.dart';

/// Column format data types for Excel worksheets.
enum ExcelColumnType { text, number, currency, date, datetime, boolean }

/// Definition of an individual column in an Excel worksheet.
@immutable
class ExcelColumnSpec {
  const ExcelColumnSpec({
    required this.header,
    required this.sourceField,
    this.width = 16,
    this.type = ExcelColumnType.text,
    this.defaultValue = '-',
  });

  final String header;
  final String sourceField;
  final double width;
  final ExcelColumnType type;
  final dynamic defaultValue;
}

/// Definition of a normalized Excel worksheet.
@immutable
class ExcelWorksheetSpec {
  const ExcelWorksheetSpec({
    required this.name,
    required this.sourceTable,
    required this.stableIdKey,
    required this.timestampKey,
    required this.columns,
    this.sensitiveExcludedFields = const [],
    this.description = '',
  });

  final String name;
  final String sourceTable;
  final String stableIdKey;
  final String timestampKey;
  final List<ExcelColumnSpec> columns;
  final List<String> sensitiveExcludedFields;
  final String description;

  int get columnCount => columns.length;
}

/// Central catalog defining the master Excel workbook structure for MKES CARE+.
class ExcelWorkbookSchema {
  static const String masterWorkbookFileName = 'MKES_CARE_Plus_Master.xlsx';
  static const String storageBucketName = 'clinic-excel-sync';
  static const String storageFilePath =
      '$storageBucketName/$masterWorkbookFileName';

  /// All 21 normalized worksheets representing the entire clinic data domain.
  static const List<ExcelWorksheetSpec> worksheets = [
    // 1. Patients
    ExcelWorksheetSpec(
      name: 'Patients',
      sourceTable: 'patients',
      stableIdKey: 'id',
      timestampKey: 'updated_at',
      description: 'Master patient registry, demographic and contact records',
      columns: [
        ExcelColumnSpec(header: 'Patient ID', sourceField: 'id', width: 36),
        ExcelColumnSpec(header: 'Patient Number', sourceField: 'patient_number', width: 18),
        ExcelColumnSpec(header: 'Full Name', sourceField: 'name', width: 26),
        ExcelColumnSpec(header: 'Date of Birth', sourceField: 'dob', width: 14, type: ExcelColumnType.date),
        ExcelColumnSpec(header: 'Contact Mobile', sourceField: 'mobile', width: 16),
        ExcelColumnSpec(header: 'Address', sourceField: 'address', width: 32),
        ExcelColumnSpec(header: 'Department', sourceField: 'department', width: 14),
        ExcelColumnSpec(header: 'Reference Source', sourceField: 'reference', width: 20),
        ExcelColumnSpec(header: 'First Visit Date', sourceField: 'visit_date', width: 16, type: ExcelColumnType.date),
        ExcelColumnSpec(header: 'Created At', sourceField: 'created_at', width: 18, type: ExcelColumnType.datetime),
        ExcelColumnSpec(header: 'Updated At', sourceField: 'updated_at', width: 18, type: ExcelColumnType.datetime),
      ],
    ),

    // 2. Staff Directory
    ExcelWorksheetSpec(
      name: 'Staff_Directory',
      sourceTable: 'profiles',
      stableIdKey: 'id',
      timestampKey: 'updated_at',
      sensitiveExcludedFields: ['salary'],
      description: 'Staff directory with shifts, designations and department assignments (salary redacted)',
      columns: [
        ExcelColumnSpec(header: 'Staff ID', sourceField: 'id', width: 36),
        ExcelColumnSpec(header: 'Full Name', sourceField: 'full_name', width: 26),
        ExcelColumnSpec(header: 'Email Address', sourceField: 'email', width: 30),
        ExcelColumnSpec(header: 'Phone Number', sourceField: 'phone_number', width: 16),
        ExcelColumnSpec(header: 'Department', sourceField: 'department', width: 18),
        ExcelColumnSpec(header: 'Designation', sourceField: 'designation', width: 22),
        ExcelColumnSpec(header: 'System Role', sourceField: 'role', width: 14),
        ExcelColumnSpec(header: 'Status', sourceField: 'is_active', width: 12),
        ExcelColumnSpec(header: 'Assigned Shift', sourceField: 'assigned_shift', width: 16),
        ExcelColumnSpec(header: 'Next Shift', sourceField: 'next_shift', width: 16),
        ExcelColumnSpec(header: 'Shift Effective Date', sourceField: 'shift_effective_date', width: 20, type: ExcelColumnType.date),
        ExcelColumnSpec(header: 'Joining Date', sourceField: 'joining_date', width: 16, type: ExcelColumnType.date),
        ExcelColumnSpec(header: 'Created At', sourceField: 'created_at', width: 18, type: ExcelColumnType.datetime),
        ExcelColumnSpec(header: 'Updated At', sourceField: 'updated_at', width: 18, type: ExcelColumnType.datetime),
      ],
    ),

    // 3. Staff Attendance
    ExcelWorksheetSpec(
      name: 'Staff_Attendance',
      sourceTable: 'staff_attendance',
      stableIdKey: 'id',
      timestampKey: 'updated_at',
      description: 'Shift attendance logs, check-ins, check-outs and hours',
      columns: [
        ExcelColumnSpec(header: 'Record ID', sourceField: 'id', width: 36),
        ExcelColumnSpec(header: 'Staff Name', sourceField: 'staff_name', width: 24),
        ExcelColumnSpec(header: 'Staff Email', sourceField: 'staff_email', width: 28),
        ExcelColumnSpec(header: 'Record Date', sourceField: 'record_date', width: 14, type: ExcelColumnType.date),
        ExcelColumnSpec(header: 'Shift', sourceField: 'shift', width: 14),
        ExcelColumnSpec(header: 'Check-In Time', sourceField: 'check_in_time', width: 18, type: ExcelColumnType.datetime),
        ExcelColumnSpec(header: 'Check-Out Time', sourceField: 'check_out_time', width: 18, type: ExcelColumnType.datetime),
        ExcelColumnSpec(header: 'Working Hours', sourceField: 'working_hours', width: 15, type: ExcelColumnType.number),
        ExcelColumnSpec(header: 'Status', sourceField: 'status', width: 14),
        ExcelColumnSpec(header: 'Is Late', sourceField: 'is_late', width: 10, type: ExcelColumnType.boolean),
        ExcelColumnSpec(header: 'Late Mins', sourceField: 'late_minutes', width: 12, type: ExcelColumnType.number),
        ExcelColumnSpec(header: 'Notes', sourceField: 'notes', width: 30),
        ExcelColumnSpec(header: 'Updated At', sourceField: 'updated_at', width: 18, type: ExcelColumnType.datetime),
      ],
    ),

    // 4. Leave Requests
    ExcelWorksheetSpec(
      name: 'Leave_Requests',
      sourceTable: 'leave_requests',
      stableIdKey: 'id',
      timestampKey: 'updated_at',
      description: 'Staff leave applications, approvals and balance tracking',
      columns: [
        ExcelColumnSpec(header: 'Leave ID', sourceField: 'id', width: 36),
        ExcelColumnSpec(header: 'Applicant', sourceField: 'applicant_name', width: 24),
        ExcelColumnSpec(header: 'Start Date', sourceField: 'start_date', width: 14, type: ExcelColumnType.date),
        ExcelColumnSpec(header: 'End Date', sourceField: 'end_date', width: 14, type: ExcelColumnType.date),
        ExcelColumnSpec(header: 'Days', sourceField: 'leave_days', width: 10, type: ExcelColumnType.number),
        ExcelColumnSpec(header: 'Reason', sourceField: 'reason', width: 32),
        ExcelColumnSpec(header: 'Status', sourceField: 'status', width: 14),
        ExcelColumnSpec(header: 'Reviewed By', sourceField: 'approver_name', width: 24),
        ExcelColumnSpec(header: 'Decision Date', sourceField: 'approved_at', width: 18, type: ExcelColumnType.datetime),
        ExcelColumnSpec(header: 'Rejection Reason', sourceField: 'rejection_reason', width: 30),
        ExcelColumnSpec(header: 'Created At', sourceField: 'created_at', width: 18, type: ExcelColumnType.datetime),
      ],
    ),

    // 5. Tasks
    ExcelWorksheetSpec(
      name: 'Tasks',
      sourceTable: 'tasks',
      stableIdKey: 'id',
      timestampKey: 'updated_at',
      description: 'Clinic operational tasks, assignments and priorities',
      columns: [
        ExcelColumnSpec(header: 'Task ID', sourceField: 'id', width: 36),
        ExcelColumnSpec(header: 'Title', sourceField: 'title', width: 30),
        ExcelColumnSpec(header: 'Assigned To', sourceField: 'assignee_name', width: 24),
        ExcelColumnSpec(header: 'Assigned By', sourceField: 'assigner_name', width: 24),
        ExcelColumnSpec(header: 'Priority', sourceField: 'priority', width: 14),
        ExcelColumnSpec(header: 'Status', sourceField: 'status', width: 14),
        ExcelColumnSpec(header: 'Due Date', sourceField: 'due_date', width: 18, type: ExcelColumnType.datetime),
        ExcelColumnSpec(header: 'Completed At', sourceField: 'completed_at', width: 18, type: ExcelColumnType.datetime),
        ExcelColumnSpec(header: 'Description', sourceField: 'description', width: 36),
        ExcelColumnSpec(header: 'Created At', sourceField: 'created_at', width: 18, type: ExcelColumnType.datetime),
      ],
    ),

    // 6. Task History
    ExcelWorksheetSpec(
      name: 'Task_History',
      sourceTable: 'task_history',
      stableIdKey: 'id',
      timestampKey: 'created_at',
      description: 'Audit trail of task status transitions and notes',
      columns: [
        ExcelColumnSpec(header: 'History ID', sourceField: 'id', width: 36),
        ExcelColumnSpec(header: 'Task ID', sourceField: 'task_id', width: 36),
        ExcelColumnSpec(header: 'Changed By', sourceField: 'changer_name', width: 24),
        ExcelColumnSpec(header: 'Previous Status', sourceField: 'old_status', width: 16),
        ExcelColumnSpec(header: 'New Status', sourceField: 'new_status', width: 16),
        ExcelColumnSpec(header: 'Note', sourceField: 'note', width: 32),
        ExcelColumnSpec(header: 'Timestamp', sourceField: 'created_at', width: 18, type: ExcelColumnType.datetime),
      ],
    ),

    // 7. Appointments
    ExcelWorksheetSpec(
      name: 'Appointments',
      sourceTable: 'appointments',
      stableIdKey: 'id',
      timestampKey: 'updated_at',
      description: 'Clinical appointments, schedules and doctors',
      columns: [
        ExcelColumnSpec(header: 'Appointment ID', sourceField: 'id', width: 36),
        ExcelColumnSpec(header: 'Patient Number', sourceField: 'patient_number', width: 18),
        ExcelColumnSpec(header: 'Patient Name', sourceField: 'patient_name', width: 26),
        ExcelColumnSpec(header: 'Department', sourceField: 'department', width: 14),
        ExcelColumnSpec(header: 'Doctor', sourceField: 'doctor_name', width: 24),
        ExcelColumnSpec(header: 'Date', sourceField: 'appointment_date', width: 14, type: ExcelColumnType.date),
        ExcelColumnSpec(header: 'Time', sourceField: 'appointment_time', width: 12),
        ExcelColumnSpec(header: 'Type', sourceField: 'appointment_type', width: 14),
        ExcelColumnSpec(header: 'Status', sourceField: 'status', width: 14),
        ExcelColumnSpec(header: 'AI Booked', sourceField: 'ai_booked', width: 12, type: ExcelColumnType.boolean),
        ExcelColumnSpec(header: 'Notes', sourceField: 'notes', width: 32),
        ExcelColumnSpec(header: 'Created At', sourceField: 'created_at', width: 18, type: ExcelColumnType.datetime),
        ExcelColumnSpec(header: 'Updated At', sourceField: 'updated_at', width: 18, type: ExcelColumnType.datetime),
      ],
    ),

    // 8. Inventory Catalog
    ExcelWorksheetSpec(
      name: 'Inventory_Catalog',
      sourceTable: 'inventory',
      stableIdKey: 'id',
      timestampKey: 'updated_at',
      description: 'Central stock catalog, minimum levels and valuations',
      columns: [
        ExcelColumnSpec(header: 'Item ID', sourceField: 'id', width: 36),
        ExcelColumnSpec(header: 'SKU', sourceField: 'sku', width: 16),
        ExcelColumnSpec(header: 'Item Name', sourceField: 'name', width: 30),
        ExcelColumnSpec(header: 'Category', sourceField: 'category', width: 18),
        ExcelColumnSpec(header: 'Department', sourceField: 'department', width: 14),
        ExcelColumnSpec(header: 'Unit', sourceField: 'unit', width: 12),
        ExcelColumnSpec(header: 'Current Stock', sourceField: 'quantity', width: 15, type: ExcelColumnType.number),
        ExcelColumnSpec(header: 'Min Stock', sourceField: 'minimum_stock', width: 14, type: ExcelColumnType.number),
        ExcelColumnSpec(header: 'Unit Price (INR)', sourceField: 'price', width: 16, type: ExcelColumnType.currency),
        ExcelColumnSpec(header: 'Total Valuation (INR)', sourceField: 'total_valuation', width: 22, type: ExcelColumnType.currency),
        ExcelColumnSpec(header: 'Preferred Vendor', sourceField: 'vendor_name', width: 24),
        ExcelColumnSpec(header: 'Status', sourceField: 'is_active', width: 12),
        ExcelColumnSpec(header: 'Updated At', sourceField: 'updated_at', width: 18, type: ExcelColumnType.datetime),
      ],
    ),

    // 9. Inventory Batches
    ExcelWorksheetSpec(
      name: 'Inventory_Batches',
      sourceTable: 'inventory_batches',
      stableIdKey: 'id',
      timestampKey: 'updated_at',
      description: 'Batch and consignment tracking with individual expiry dates',
      columns: [
        ExcelColumnSpec(header: 'Batch ID', sourceField: 'id', width: 36),
        ExcelColumnSpec(header: 'Batch Number', sourceField: 'batch_number', width: 18),
        ExcelColumnSpec(header: 'Item Name', sourceField: 'item_name', width: 28),
        ExcelColumnSpec(header: 'SKU', sourceField: 'sku', width: 16),
        ExcelColumnSpec(header: 'PO Number', sourceField: 'po_number', width: 20),
        ExcelColumnSpec(header: 'Received Date', sourceField: 'received_date', width: 16, type: ExcelColumnType.date),
        ExcelColumnSpec(header: 'Expiry Date', sourceField: 'expiry_date', width: 16, type: ExcelColumnType.date),
        ExcelColumnSpec(header: 'Received Qty', sourceField: 'received_quantity', width: 15, type: ExcelColumnType.number),
        ExcelColumnSpec(header: 'Remaining Qty', sourceField: 'remaining_quantity', width: 15, type: ExcelColumnType.number),
        ExcelColumnSpec(header: 'Unit Cost (INR)', sourceField: 'unit_price', width: 16, type: ExcelColumnType.currency),
        ExcelColumnSpec(header: 'Batch Value (INR)', sourceField: 'total_amount', width: 18, type: ExcelColumnType.currency),
        ExcelColumnSpec(header: 'Created At', sourceField: 'created_at', width: 18, type: ExcelColumnType.datetime),
      ],
    ),

    // 10. Stock Transactions
    ExcelWorksheetSpec(
      name: 'Stock_Transactions',
      sourceTable: 'inventory_transactions',
      stableIdKey: 'id',
      timestampKey: 'created_at',
      description: 'Immutable ledger of stock movements and write-offs',
      columns: [
        ExcelColumnSpec(header: 'Transaction ID', sourceField: 'id', width: 36),
        ExcelColumnSpec(header: 'Timestamp', sourceField: 'created_at', width: 18, type: ExcelColumnType.datetime),
        ExcelColumnSpec(header: 'Item Name', sourceField: 'item_name', width: 28),
        ExcelColumnSpec(header: 'Transaction Type', sourceField: 'transaction_type', width: 18),
        ExcelColumnSpec(header: 'Quantity', sourceField: 'quantity', width: 14, type: ExcelColumnType.number),
        ExcelColumnSpec(header: 'Performed By', sourceField: 'performer_name', width: 24),
        ExcelColumnSpec(header: 'Remarks', sourceField: 'remarks', width: 32),
      ],
    ),

    // 11. Department Stock
    ExcelWorksheetSpec(
      name: 'Department_Stock',
      sourceTable: 'department_inventory',
      stableIdKey: 'id',
      timestampKey: 'updated_at',
      description: 'Sub-inventory counts segregated by clinic department',
      columns: [
        ExcelColumnSpec(header: 'Dept Stock ID', sourceField: 'id', width: 36),
        ExcelColumnSpec(header: 'Department', sourceField: 'department', width: 16),
        ExcelColumnSpec(header: 'Item Name', sourceField: 'item_name', width: 28),
        ExcelColumnSpec(header: 'SKU', sourceField: 'sku', width: 16),
        ExcelColumnSpec(header: 'Current Stock', sourceField: 'current_stock', width: 15, type: ExcelColumnType.number),
        ExcelColumnSpec(header: 'Min Stock', sourceField: 'minimum_stock', width: 14, type: ExcelColumnType.number),
        ExcelColumnSpec(header: 'Unit', sourceField: 'unit', width: 12),
        ExcelColumnSpec(header: 'Updated At', sourceField: 'updated_at', width: 18, type: ExcelColumnType.datetime),
      ],
    ),

    // 12. Stock Requests
    ExcelWorksheetSpec(
      name: 'Stock_Requests',
      sourceTable: 'stock_requests',
      stableIdKey: 'id',
      timestampKey: 'updated_at',
      description: 'Departmental replenishment requests and approvals',
      columns: [
        ExcelColumnSpec(header: 'Request ID', sourceField: 'id', width: 36),
        ExcelColumnSpec(header: 'Request Number', sourceField: 'request_number', width: 20),
        ExcelColumnSpec(header: 'Department', sourceField: 'department', width: 16),
        ExcelColumnSpec(header: 'Requested By', sourceField: 'requester_name', width: 24),
        ExcelColumnSpec(header: 'Status', sourceField: 'status', width: 16),
        ExcelColumnSpec(header: 'Notes', sourceField: 'notes', width: 30),
        ExcelColumnSpec(header: 'Created At', sourceField: 'created_at', width: 18, type: ExcelColumnType.datetime),
        ExcelColumnSpec(header: 'Updated At', sourceField: 'updated_at', width: 18, type: ExcelColumnType.datetime),
      ],
    ),

    // 13. Vendors
    ExcelWorksheetSpec(
      name: 'Vendors',
      sourceTable: 'vendors',
      stableIdKey: 'id',
      timestampKey: 'updated_at',
      description: 'Supplier directory and supplied product catalogs',
      columns: [
        ExcelColumnSpec(header: 'Vendor ID', sourceField: 'id', width: 36),
        ExcelColumnSpec(header: 'Vendor Name', sourceField: 'name', width: 28),
        ExcelColumnSpec(header: 'Contact Person', sourceField: 'contact_person', width: 24),
        ExcelColumnSpec(header: 'Phone', sourceField: 'phone', width: 16),
        ExcelColumnSpec(header: 'Email', sourceField: 'email', width: 28),
        ExcelColumnSpec(header: 'Address', sourceField: 'address', width: 32),
        ExcelColumnSpec(header: 'Supplied Products', sourceField: 'products_supplied', width: 28),
        ExcelColumnSpec(header: 'Remarks', sourceField: 'remarks', width: 30),
        ExcelColumnSpec(header: 'Updated At', sourceField: 'updated_at', width: 18, type: ExcelColumnType.datetime),
      ],
    ),

    // 14. Purchase Orders
    ExcelWorksheetSpec(
      name: 'Purchase_Orders',
      sourceTable: 'purchase_orders',
      stableIdKey: 'id',
      timestampKey: 'updated_at',
      description: 'Supplier purchase orders, delivery statuses and totals',
      columns: [
        ExcelColumnSpec(header: 'PO ID', sourceField: 'id', width: 36),
        ExcelColumnSpec(header: 'PO Number', sourceField: 'purchase_order_number', width: 22),
        ExcelColumnSpec(header: 'Vendor Name', sourceField: 'vendor_name', width: 26),
        ExcelColumnSpec(header: 'Order Date', sourceField: 'order_date', width: 14, type: ExcelColumnType.date),
        ExcelColumnSpec(header: 'Expected Delivery', sourceField: 'expected_delivery_date', width: 18, type: ExcelColumnType.date),
        ExcelColumnSpec(header: 'Actual Delivery', sourceField: 'actual_delivery_date', width: 16, type: ExcelColumnType.date),
        ExcelColumnSpec(header: 'Status', sourceField: 'status', width: 18),
        ExcelColumnSpec(header: 'Subtotal (INR)', sourceField: 'subtotal', width: 16, type: ExcelColumnType.currency),
        ExcelColumnSpec(header: 'Total Amount (INR)', sourceField: 'total_amount', width: 18, type: ExcelColumnType.currency),
        ExcelColumnSpec(header: 'Created By', sourceField: 'creator_name', width: 22),
        ExcelColumnSpec(header: 'Ordered By', sourceField: 'orderer_name', width: 22),
        ExcelColumnSpec(header: 'Notes', sourceField: 'notes', width: 30),
        ExcelColumnSpec(header: 'Updated At', sourceField: 'updated_at', width: 18, type: ExcelColumnType.datetime),
      ],
    ),

    // 15. Purchase Order Items
    ExcelWorksheetSpec(
      name: 'Purchase_Order_Items',
      sourceTable: 'purchase_order_items',
      stableIdKey: 'id',
      timestampKey: 'updated_at',
      description: 'Individual line items inside purchase orders',
      columns: [
        ExcelColumnSpec(header: 'Item ID', sourceField: 'id', width: 36),
        ExcelColumnSpec(header: 'PO Number', sourceField: 'po_number', width: 22),
        ExcelColumnSpec(header: 'Item Name', sourceField: 'item_name', width: 28),
        ExcelColumnSpec(header: 'SKU', sourceField: 'sku', width: 16),
        ExcelColumnSpec(header: 'Ordered Qty', sourceField: 'quantity', width: 14, type: ExcelColumnType.number),
        ExcelColumnSpec(header: 'Unit', sourceField: 'unit', width: 12),
        ExcelColumnSpec(header: 'Unit Price (INR)', sourceField: 'unit_price', width: 16, type: ExcelColumnType.currency),
        ExcelColumnSpec(header: 'Total Price (INR)', sourceField: 'total_amount', width: 18, type: ExcelColumnType.currency),
        ExcelColumnSpec(header: 'Received Qty', sourceField: 'received_quantity', width: 15, type: ExcelColumnType.number),
        ExcelColumnSpec(header: 'Remaining Qty', sourceField: 'remaining_quantity', width: 15, type: ExcelColumnType.number),
        ExcelColumnSpec(header: 'Updated At', sourceField: 'updated_at', width: 18, type: ExcelColumnType.datetime),
      ],
    ),

    // 16. Optical Sales
    ExcelWorksheetSpec(
      name: 'Optical_Sales',
      sourceTable: 'sales',
      stableIdKey: 'id',
      timestampKey: 'created_at',
      description: 'Dispensary optical frame and spectacle sales',
      columns: [
        ExcelColumnSpec(header: 'Sale ID', sourceField: 'id', width: 36),
        ExcelColumnSpec(header: 'Sale Number', sourceField: 'sale_number', width: 18),
        ExcelColumnSpec(header: 'Sale Date', sourceField: 'sale_date', width: 14, type: ExcelColumnType.date),
        ExcelColumnSpec(header: 'Patient Name', sourceField: 'patient_name', width: 24),
        ExcelColumnSpec(header: 'Frame Brand', sourceField: 'frame_brand', width: 20),
        ExcelColumnSpec(header: 'Frame Model', sourceField: 'frame_name', width: 22),
        ExcelColumnSpec(header: 'Quantity', sourceField: 'quantity', width: 12, type: ExcelColumnType.number),
        ExcelColumnSpec(header: 'Amount (INR)', sourceField: 'amount', width: 16, type: ExcelColumnType.currency),
        ExcelColumnSpec(header: 'Sold By', sourceField: 'sold_by_name', width: 22),
        ExcelColumnSpec(header: 'Created At', sourceField: 'created_at', width: 18, type: ExcelColumnType.datetime),
      ],
    ),

    // 17. Optical Orders
    ExcelWorksheetSpec(
      name: 'Optical_Orders',
      sourceTable: 'optical_orders',
      stableIdKey: 'id',
      timestampKey: 'updated_at',
      description: 'Prescription eyewear fabrication orders, status and delivery tracking',
      columns: [
        ExcelColumnSpec(header: 'Order ID', sourceField: 'id', width: 36),
        ExcelColumnSpec(header: 'Order Number', sourceField: 'order_number', width: 18),
        ExcelColumnSpec(header: 'Patient Number', sourceField: 'patient_number', width: 18),
        ExcelColumnSpec(header: 'Patient Name', sourceField: 'patient_name', width: 24),
        ExcelColumnSpec(header: 'Order Type', sourceField: 'order_type', width: 16),
        ExcelColumnSpec(header: 'Order Status', sourceField: 'order_status', width: 16),
        ExcelColumnSpec(header: 'Payment Status', sourceField: 'payment_status', width: 16),
        ExcelColumnSpec(header: 'Delivery Date', sourceField: 'delivery_date', width: 14, type: ExcelColumnType.date),
        ExcelColumnSpec(header: 'Total Amount (INR)', sourceField: 'total_amount', width: 18, type: ExcelColumnType.currency),
        ExcelColumnSpec(header: 'Prescription Details', sourceField: 'prescription_details', width: 32),
        ExcelColumnSpec(header: 'Frame Details', sourceField: 'frame_details', width: 28),
        ExcelColumnSpec(header: 'Lens Details', sourceField: 'lens_details', width: 28),
        ExcelColumnSpec(header: 'Created At', sourceField: 'created_at', width: 18, type: ExcelColumnType.datetime),
        ExcelColumnSpec(header: 'Updated At', sourceField: 'updated_at', width: 18, type: ExcelColumnType.datetime),
      ],
    ),

    // 18. Dental Lab Cases
    ExcelWorksheetSpec(
      name: 'Dental_Lab_Cases',
      sourceTable: 'dental_lab',
      stableIdKey: 'id',
      timestampKey: 'updated_at',
      description: 'Prosthodontic lab work orders and delivery progress',
      columns: [
        ExcelColumnSpec(header: 'Case ID', sourceField: 'id', width: 36),
        ExcelColumnSpec(header: 'Case Number', sourceField: 'case_number', width: 18),
        ExcelColumnSpec(header: 'Patient Number', sourceField: 'patient_number', width: 18),
        ExcelColumnSpec(header: 'Patient Name', sourceField: 'patient_name', width: 24),
        ExcelColumnSpec(header: 'Case Type', sourceField: 'case_type', width: 22),
        ExcelColumnSpec(header: 'Status', sourceField: 'status', width: 16),
        ExcelColumnSpec(header: 'Sent Date', sourceField: 'sent_date', width: 14, type: ExcelColumnType.date),
        ExcelColumnSpec(header: 'Ready Date', sourceField: 'ready_date', width: 14, type: ExcelColumnType.date),
        ExcelColumnSpec(header: 'Delivered Date', sourceField: 'delivered_date', width: 16, type: ExcelColumnType.date),
        ExcelColumnSpec(header: 'Remarks', sourceField: 'remarks', width: 30),
        ExcelColumnSpec(header: 'Updated At', sourceField: 'updated_at', width: 18, type: ExcelColumnType.datetime),
      ],
    ),

    // 19. Billing Invoices
    ExcelWorksheetSpec(
      name: 'Billing_Invoices',
      sourceTable: 'billing',
      stableIdKey: 'id',
      timestampKey: 'updated_at',
      description: 'Patient billing invoices, totals, discounts and balances',
      columns: [
        ExcelColumnSpec(header: 'Invoice ID', sourceField: 'id', width: 36),
        ExcelColumnSpec(header: 'Invoice Number', sourceField: 'invoice_number', width: 22),
        ExcelColumnSpec(header: 'Patient Number', sourceField: 'patient_number', width: 18),
        ExcelColumnSpec(header: 'Patient Name', sourceField: 'patient_name', width: 24),
        ExcelColumnSpec(header: 'Department', sourceField: 'department', width: 14),
        ExcelColumnSpec(header: 'Invoice Date', sourceField: 'invoice_date', width: 14, type: ExcelColumnType.date),
        ExcelColumnSpec(header: 'Subtotal (INR)', sourceField: 'subtotal', width: 16, type: ExcelColumnType.currency),
        ExcelColumnSpec(header: 'Discount (INR)', sourceField: 'discount', width: 16, type: ExcelColumnType.currency),
        ExcelColumnSpec(header: 'Tax (INR)', sourceField: 'tax_amount', width: 14, type: ExcelColumnType.currency),
        ExcelColumnSpec(header: 'Total Amount (INR)', sourceField: 'total_amount', width: 18, type: ExcelColumnType.currency),
        ExcelColumnSpec(header: 'Paid Amount (INR)', sourceField: 'paid_amount', width: 18, type: ExcelColumnType.currency),
        ExcelColumnSpec(header: 'Balance (INR)', sourceField: 'balance_amount', width: 16, type: ExcelColumnType.currency),
        ExcelColumnSpec(header: 'Status', sourceField: 'status', width: 14),
        ExcelColumnSpec(header: 'Payment Mode', sourceField: 'payment_method', width: 16),
        ExcelColumnSpec(header: 'Billed By', sourceField: 'billed_by_name', width: 22),
        ExcelColumnSpec(header: 'Updated At', sourceField: 'updated_at', width: 18, type: ExcelColumnType.datetime),
      ],
    ),

    // 20. Billing Line Items
    ExcelWorksheetSpec(
      name: 'Billing_Line_Items',
      sourceTable: 'billing_items',
      stableIdKey: 'id',
      timestampKey: 'created_at',
      description: 'Itemized clinical services and stock consumables billed to patients',
      columns: [
        ExcelColumnSpec(header: 'Line Item ID', sourceField: 'id', width: 36),
        ExcelColumnSpec(header: 'Invoice Number', sourceField: 'invoice_number', width: 22),
        ExcelColumnSpec(header: 'Item Type', sourceField: 'item_type', width: 14),
        ExcelColumnSpec(header: 'Item / Service Name', sourceField: 'item_name', width: 30),
        ExcelColumnSpec(header: 'Quantity', sourceField: 'quantity', width: 12, type: ExcelColumnType.number),
        ExcelColumnSpec(header: 'Unit Rate (INR)', sourceField: 'unit_price', width: 16, type: ExcelColumnType.currency),
        ExcelColumnSpec(header: 'Total Amount (INR)', sourceField: 'total_price', width: 18, type: ExcelColumnType.currency),
        ExcelColumnSpec(header: 'Created At', sourceField: 'created_at', width: 18, type: ExcelColumnType.datetime),
      ],
    ),

    // 21. Billing Payments
    ExcelWorksheetSpec(
      name: 'Billing_Payments',
      sourceTable: 'billing_payments',
      stableIdKey: 'id',
      timestampKey: 'created_at',
      description: 'Individual payment receipts and financial collections',
      columns: [
        ExcelColumnSpec(header: 'Payment ID', sourceField: 'id', width: 36),
        ExcelColumnSpec(header: 'Invoice Number', sourceField: 'invoice_number', width: 22),
        ExcelColumnSpec(header: 'Payment Date', sourceField: 'payment_date', width: 18, type: ExcelColumnType.datetime),
        ExcelColumnSpec(header: 'Amount Paid (INR)', sourceField: 'amount', width: 18, type: ExcelColumnType.currency),
        ExcelColumnSpec(header: 'Payment Method', sourceField: 'payment_method', width: 16),
        ExcelColumnSpec(header: 'Transaction Ref', sourceField: 'transaction_reference', width: 24),
        ExcelColumnSpec(header: 'Received By', sourceField: 'received_by_name', width: 22),
        ExcelColumnSpec(header: 'Notes', sourceField: 'notes', width: 28),
        ExcelColumnSpec(header: 'Recorded At', sourceField: 'created_at', width: 18, type: ExcelColumnType.datetime),
      ],
    ),
  ];

  /// Finds a worksheet specification by name.
  static ExcelWorksheetSpec? getWorksheet(String name) {
    try {
      return worksheets.firstWhere((w) => w.name.toLowerCase() == name.toLowerCase());
    } catch (_) {
      return null;
    }
  }

  /// Total count of normalized worksheets in the central workbook.
  static int get totalWorksheetCount => worksheets.length;
}
