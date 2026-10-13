import 'dart:io';

import 'package:flutter_test/flutter_test.dart';

import 'package:mkes_care/features/reports/models/excel_sync_state_model.dart';
import 'package:mkes_care/features/reports/services/excel_workbook_schema.dart';

void main() {
  group('Sprint 9.2 — Master Excel Workbook & Worksheet Schema Tests', () {
    test('Schema includes all required normalized worksheets', () {
      expect(ExcelWorkbookSchema.totalWorksheetCount, equals(21));

      final expectedWorksheets = [
        'Patients',
        'Staff_Directory',
        'Staff_Attendance',
        'Leave_Requests',
        'Tasks',
        'Task_History',
        'Appointments',
        'Inventory_Catalog',
        'Inventory_Batches',
        'Stock_Transactions',
        'Department_Stock',
        'Stock_Requests',
        'Vendors',
        'Purchase_Orders',
        'Purchase_Order_Items',
        'Optical_Sales',
        'Optical_Orders',
        'Dental_Lab_Cases',
        'Billing_Invoices',
        'Billing_Line_Items',
        'Billing_Payments',
      ];

      for (final expected in expectedWorksheets) {
        final sheet = ExcelWorkbookSchema.getWorksheet(expected);
        expect(sheet, isNotNull, reason: 'Worksheet $expected should exist');
        expect(sheet!.name, equals(expected));
        expect(sheet.sourceTable.isNotEmpty, isTrue);
        expect(sheet.stableIdKey, equals('id'));
        expect(sheet.timestampKey.isNotEmpty, isTrue);
        expect(sheet.columns.isNotEmpty, isTrue);
      }
    });

    test('Staff_Directory strictly redacts staff salary from column definitions', () {
      final staffSheet = ExcelWorkbookSchema.getWorksheet('Staff_Directory')!;

      // Verify salary is in sensitiveExcludedFields
      expect(staffSheet.sensitiveExcludedFields, contains('salary'));

      // Verify no column in the sheet exposes salary
      final salaryColumns = staffSheet.columns.where(
        (col) =>
            col.header.toLowerCase().contains('salary') ||
            col.sourceField.toLowerCase().contains('salary'),
      );
      expect(salaryColumns, isEmpty,
          reason: 'Salary must be completely excluded from Staff_Directory worksheet');
    });

    test('Financial worksheets maintain relational foreign keys and non-flattened structure', () {
      final invoices = ExcelWorkbookSchema.getWorksheet('Billing_Invoices')!;
      final items = ExcelWorkbookSchema.getWorksheet('Billing_Line_Items')!;
      final payments = ExcelWorkbookSchema.getWorksheet('Billing_Payments')!;

      // Invoices must have invoice_number
      expect(
        invoices.columns.any((c) => c.header == 'Invoice Number'),
        isTrue,
      );

      // Line items must have invoice_number linking key
      expect(
        items.columns.any((c) => c.header == 'Invoice Number'),
        isTrue,
      );

      // Payments must have invoice_number linking key
      expect(
        payments.columns.any((c) => c.header == 'Invoice Number'),
        isTrue,
      );

      // Verify currency types on monetary columns
      final totalCol = invoices.columns.firstWhere((c) => c.header == 'Total Amount (INR)');
      expect(totalCol.type, equals(ExcelColumnType.currency));

      final balanceCol = invoices.columns.firstWhere((c) => c.header == 'Balance (INR)');
      expect(balanceCol.type, equals(ExcelColumnType.currency));
    });

    test('Purchase orders maintain separate sheets for headers and line items', () {
      final poHeaders = ExcelWorkbookSchema.getWorksheet('Purchase_Orders')!;
      final poItems = ExcelWorkbookSchema.getWorksheet('Purchase_Order_Items')!;

      expect(poHeaders.columns.any((c) => c.header == 'PO Number'), isTrue);
      expect(poItems.columns.any((c) => c.header == 'PO Number'), isTrue);
    });

    test('Inventory catalog and batches maintain traceability without batch flattening', () {
      final catalog = ExcelWorkbookSchema.getWorksheet('Inventory_Catalog')!;
      final batches = ExcelWorkbookSchema.getWorksheet('Inventory_Batches')!;

      expect(catalog.columns.any((c) => c.header == 'SKU'), isTrue);
      expect(batches.columns.any((c) => c.header == 'Batch Number'), isTrue);
      expect(batches.columns.any((c) => c.header == 'Expiry Date'), isTrue);
    });

    test('Tasks and Task_History retain relationship and chronological tracking', () {
      final tasks = ExcelWorkbookSchema.getWorksheet('Tasks')!;
      final history = ExcelWorkbookSchema.getWorksheet('Task_History')!;

      expect(tasks.columns.any((c) => c.header == 'Task ID'), isTrue);
      expect(history.columns.any((c) => c.header == 'Task ID'), isTrue);
      expect(history.columns.any((c) => c.header == 'Previous Status'), isTrue);
      expect(history.columns.any((c) => c.header == 'New Status'), isTrue);
    });

    test('ExcelSyncStateModel deserializes from Supabase JSON accurately', () {
      final json = {
        'id': 'a1b2c3d4-e5f6-7890-abcd-ef1234567890',
        'sync_type': 'scheduled',
        'status': 'success',
        'started_at': '2026-10-13T00:00:00.000Z',
        'completed_at': '2026-10-13T00:00:04.500Z',
        'records_upserted': 452,
        'file_size_bytes': 1048576, // 1 MB
        'storage_path': 'clinic-excel-sync/MKES_CARE_Plus_Master.xlsx',
        'worksheets_synced': ['Patients', 'Appointments', 'Billing_Invoices'],
        'created_at': '2026-10-13T00:00:05.000Z',
      };

      final model = ExcelSyncStateModel.fromJson(json);

      expect(model.id, equals('a1b2c3d4-e5f6-7890-abcd-ef1234567890'));
      expect(model.isSuccess, isTrue);
      expect(model.isInProgress, isFalse);
      expect(model.isFailed, isFalse);
      expect(model.recordsUpserted, equals(452));
      expect(model.fileSizeMegabytes, closeTo(1.0, 0.01));
      expect(model.worksheetsSynced.length, equals(3));
    });

    test('ExcelSyncCheckpointModel parses high-water mark timestamp', () {
      final json = {
        'worksheet_name': 'Patients',
        'source_table': 'patients',
        'last_sync_timestamp': '2026-10-13T00:15:00.000Z',
        'record_count': 1250,
        'updated_at': '2026-10-13T00:15:02.000Z',
      };

      final checkpoint = ExcelSyncCheckpointModel.fromJson(json);

      expect(checkpoint.worksheetName, equals('Patients'));
      expect(checkpoint.sourceTable, equals('patients'));
      expect(checkpoint.recordCount, equals(1250));
      expect(checkpoint.lastSyncTimestamp.year, equals(2026));
    });

    test('Optical_Orders worksheet includes full tracking fields and jsonb details safely defined', () {
      final sheet = ExcelWorkbookSchema.getWorksheet('Optical_Orders');
      expect(sheet, isNotNull);
      expect(sheet!.sourceTable, equals('optical_orders'));
      expect(sheet.stableIdKey, equals('id'));
      expect(sheet.timestampKey, equals('updated_at'));
      expect(sheet.columns.length, equals(14));

      final headers = sheet.columns.map((c) => c.header).toList();
      expect(
        headers,
        equals([
          'Order ID',
          'Order Number',
          'Patient Number',
          'Patient Name',
          'Order Type',
          'Order Status',
          'Payment Status',
          'Delivery Date',
          'Total Amount (INR)',
          'Prescription Details',
          'Frame Details',
          'Lens Details',
          'Created At',
          'Updated At',
        ]),
      );

      final totalCol = sheet.columns.firstWhere((c) => c.header == 'Total Amount (INR)');
      expect(totalCol.type, equals(ExcelColumnType.currency));

      final deliveryCol = sheet.columns.firstWhere((c) => c.header == 'Delivery Date');
      expect(deliveryCol.type, equals(ExcelColumnType.date));
    });

    test('TypeScript and Dart schema catalogs maintain full structural parity without drift', () {
      final tsSchemaFile = File('supabase/functions/sync-excel-workbook/schema.ts');
      expect(tsSchemaFile.existsSync(), isTrue, reason: 'schema.ts must exist');
      final tsContent = tsSchemaFile.readAsStringSync();

      // 1. Verify workbook file and storage constants parity
      final fileNameMatch = RegExp(r'export const MASTER_WORKBOOK_FILENAME = "([^"]+)";').firstMatch(tsContent);
      expect(fileNameMatch?.group(1), equals(ExcelWorkbookSchema.masterWorkbookFileName));

      final bucketMatch = RegExp(r'export const STORAGE_BUCKET_NAME = "([^"]+)";').firstMatch(tsContent);
      expect(bucketMatch?.group(1), equals(ExcelWorkbookSchema.storageBucketName));

      // 2. Extract and verify all worksheet names and count
      final sheetNameMatches = RegExp(r'name:\s*"([^"]+)",').allMatches(tsContent).map((m) => m.group(1)!).toList();
      expect(sheetNameMatches.length, equals(21));
      expect(sheetNameMatches.length, equals(ExcelWorkbookSchema.totalWorksheetCount));

      final dartSheetNames = ExcelWorkbookSchema.worksheets.map((w) => w.name).toList();
      expect(sheetNameMatches, equals(dartSheetNames));

      // 3. Extract and verify source tables
      final tableMatches = RegExp(r'sourceTable:\s*"([^"]+)",').allMatches(tsContent).map((m) => m.group(1)!).toList();
      final dartTables = ExcelWorkbookSchema.worksheets.map((w) => w.sourceTable).toList();
      expect(tableMatches, equals(dartTables));

      // 4. Extract and verify stableIdKey
      final stableIdMatches = RegExp(r'stableIdKey:\s*"([^"]+)",').allMatches(tsContent).map((m) => m.group(1)!).toList();
      final dartStableIds = ExcelWorkbookSchema.worksheets.map((w) => w.stableIdKey).toList();
      expect(stableIdMatches, equals(dartStableIds));

      // 5. Extract and verify column headers for every single worksheet
      for (final dartSheet in ExcelWorkbookSchema.worksheets) {
        final sheetBlockRegex = RegExp(
          'name:\\s*"${dartSheet.name}",[\\s\\S]*?columns:\\s*\\[([\\s\\S]*?)\\]\\s*,',
        );
        final match = sheetBlockRegex.firstMatch(tsContent);
        expect(match, isNotNull, reason: 'Sheet ${dartSheet.name} block should be found in schema.ts');
        final columnsBlock = match!.group(1)!;

        final tsHeaders = RegExp(r'header:\s*"([^"]+)"').allMatches(columnsBlock).map((m) => m.group(1)!).toList();
        final dartHeaders = dartSheet.columns.map((c) => c.header).toList();

        expect(tsHeaders, equals(dartHeaders), reason: 'Headers mismatch in worksheet ${dartSheet.name}');
        expect(tsHeaders.length, equals(dartSheet.columns.length), reason: 'Column count mismatch in worksheet ${dartSheet.name}');
      }
    });
  });
}
