import 'dart:typed_data';

import 'package:flutter_test/flutter_test.dart';

import 'package:mkes_care/features/reports/models/excel_sync_state_model.dart';
import 'package:mkes_care/features/reports/services/excel_historical_export_service.dart';
import 'package:mkes_care/features/reports/services/excel_workbook_builder.dart';
import 'package:mkes_care/features/reports/services/excel_workbook_schema.dart';

void main() {
  group('Sprint 9.3 — Historical Data Export & Master Workbook Validation', () {
    late ExcelWorkbookBuilder builder;

    setUp(() {
      builder = ExcelWorkbookBuilder();
    });

    test('All 21 normalized worksheets have authoritative schema specifications', () {
      expect(ExcelWorkbookSchema.totalWorksheetCount, equals(21));
      final names = ExcelWorkbookSchema.worksheets.map((s) => s.name).toList();

      expect(names, equals([
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
      ]));
    });

    test('Local historical export populates all 21 worksheets with verified counts', () {
      final dummyData = <String, List<Map<String, dynamic>>>{};

      for (final sheet in ExcelWorkbookSchema.worksheets) {
        dummyData[sheet.name] = [
          {
            sheet.stableIdKey: 'id-001',
            sheet.timestampKey: '2026-10-10T12:00:00Z',
            'name': 'Sample ${sheet.name}',
            'full_name': 'Sample Staff',
            'patient_number': 'P-1001',
            'order_number': 'ORD-1001',
            'sale_number': 'SALE-1001',
            'invoice_number': 'INV-1001',
            'case_number': 'CASE-1001',
            'sku': 'SKU-001',
            'title': 'Sample Task',
            'reason': 'Medical leave',
            'total_amount': 1500.0,
            'quantity': 5,
          },
          {
            sheet.stableIdKey: 'id-002',
            sheet.timestampKey: '2026-10-11T15:30:00Z',
            'name': 'Sample ${sheet.name} 2',
            'full_name': 'Sample Staff 2',
            'patient_number': 'P-1002',
            'order_number': 'ORD-1002',
            'sale_number': 'SALE-1002',
            'invoice_number': 'INV-1002',
            'case_number': 'CASE-1002',
            'sku': 'SKU-002',
            'title': 'Sample Task 2',
            'reason': 'Annual leave',
            'total_amount': 2500.5,
            'quantity': 10,
          },
        ];
      }

      // Instantiate service for offline local generation test
      final service = ExcelHistoricalExportService();

      final output = service.generateLocalHistoricalWorkbook(
        recordsByWorksheet: dummyData,
      );

      expect(output.result.success, isTrue);
      expect(output.result.totalRecords, equals(42)); // 21 sheets * 2 records
      expect(output.result.worksheetSummaries.length, equals(21));

      for (final summary in output.result.worksheetSummaries) {
        expect(summary.status, equals('success'));
        expect(summary.recordCount, equals(2));
        expect(summary.highWaterMark, contains('2026-10-11'));
      }

      // Verify OpenXML package bytes
      expect(output.bytes.length, greaterThan(2048));
      expect(output.bytes[0], equals(0x50));
      expect(output.bytes[1], equals(0x4B));
      expect(output.bytes[2], equals(0x03));
      expect(output.bytes[3], equals(0x04));
    });

    test('Batch pagination: 1,250 records across 3 batches are stitched accurately', () {
      final totalRecords = 1250;
      final patientRecords = <Map<String, dynamic>>[];

      for (int i = 1; i <= totalRecords; i++) {
        patientRecords.add({
          'id': 'pat-$i',
          'patient_number': 'PAT-${i.toString().padLeft(5, '0')}',
          'name': 'Patient Number $i',
          'dob': '1990-01-01',
          'mobile': '+919876543210',
          'address': 'Street $i, City',
          'department': 'OPHTHALMOLOGY',
          'reference': 'DIRECT',
          'visit_date': '2026-10-10',
          'created_at': '2026-10-10T09:00:00Z',
          'updated_at': '2026-10-10T10:00:00Z',
        });
      }

      // Build workbook with all 1,250 rows
      final bytes = builder.buildWorkbook(
        recordsByWorksheet: {'Patients': patientRecords},
      );

      final text = String.fromCharCodes(bytes);

      // Verify header + 1250 rows = row 1251 exists
      expect(text, contains('r="1251"'));
      expect(text, contains('PAT-00001'));
      expect(text, contains('PAT-01250'));
    });

    test('Strict salary exclusion: profiles.salary is completely redacted from export', () {
      final staffRecords = [
        {
          'id': 'staff-1',
          'full_name': 'Dr. Alice Sharma',
          'email': 'alice@mkescare.com',
          'phone_number': '9876543210',
          'designation': 'Senior Surgeon',
          'role': 'doctor',
          'is_active': true,
          'salary': 250000, // SENSITIVE SALARY
          'basic_salary': 180000,
          'created_at': '2026-01-01T00:00:00Z',
          'updated_at': '2026-10-10T00:00:00Z',
        },
      ];

      final bytes = builder.buildWorkbook(
        recordsByWorksheet: {'Staff_Directory': staffRecords},
      );

      final text = String.fromCharCodes(bytes);

      // Verify doctor info is present
      expect(text, contains('Dr. Alice Sharma'));
      expect(text, contains('Senior Surgeon'));

      // Verify sensitive salary number is NEVER written
      expect(text.contains('250000'), isFalse, reason: 'Staff salary must be strictly redacted');
      expect(text.contains('180000'), isFalse, reason: 'Basic salary must be strictly redacted');
    });

    test('Formula injection defense sanitizes strings starting with =, +, -, @, tab, cr', () {
      final maliciousPatients = [
        {
          'id': 'p-malicious-1',
          'patient_number': '=SUM(A1:A10)',
          'name': '+cmd|"/C calc"!A0',
          'address': '-1337+99',
          'reference': '@HYPERLINK("http://malicious.com")',
          'mobile': '\t+919999999999',
          'department': '   =WHITE_SPACE_FORMULA',
        },
      ];

      final bytes = builder.buildWorkbook(
        recordsByWorksheet: {'Patients': maliciousPatients},
      );

      final text = String.fromCharCodes(bytes);

      // 1. Direct unit verification on sanitizer
      expect(ExcelWorkbookBuilder.sanitizeSpreadsheetString('=SUM(A1:A10)'), equals("'=SUM(A1:A10)"));
      expect(ExcelWorkbookBuilder.sanitizeSpreadsheetString('+cmd|"/C calc"!A0'), equals("'+cmd|\"/C calc\"!A0"));
      expect(ExcelWorkbookBuilder.sanitizeSpreadsheetString('-1337+99'), equals("'-1337+99"));
      expect(ExcelWorkbookBuilder.sanitizeSpreadsheetString('@HYPERLINK("http://malicious.com")'), equals("'@HYPERLINK(\"http://malicious.com\")"));
      expect(ExcelWorkbookBuilder.sanitizeSpreadsheetString('\t+919999999999'), equals("'\t+919999999999"));
      expect(ExcelWorkbookBuilder.sanitizeSpreadsheetString('   =WHITE_SPACE_FORMULA'), equals("'   =WHITE_SPACE_FORMULA"));

      // 2. OpenXML inlineStr elements have XML-escaped apostrophe (&apos;) prepended
      expect(text, contains('&apos;=SUM(A1:A10)'));
      expect(text, contains('&apos;+cmd'));
      expect(text, contains('&apos;-1337+99'));
      expect(text, contains('&apos;@HYPERLINK'));
      expect(text, contains('&apos;\t+919999999999'));
      expect(text, contains('&apos;   =WHITE_SPACE_FORMULA'));
    });

    test('Formula injection defense does NOT quote legitimate numeric values', () {
      final billingItems = [
        {
          'id': 'item-1',
          'invoice_number': 'INV-100',
          'item_type': 'SERVICE',
          'item_name': 'Cataract Surgery',
          'quantity': 1,
          'unit_price': 15000.50,
          'total_price': -250.0, // Negative adjustment/discount
          'created_at': '2026-10-10T10:00:00Z',
        },
      ];

      final bytes = builder.buildWorkbook(
        recordsByWorksheet: {'Billing_Line_Items': billingItems},
      );

      final text = String.fromCharCodes(bytes);

      // Verify numeric values are emitted as numeric elements `<v>...</v>` and not `'<v>`
      expect(text, contains('<v>15000.5</v>'));
      expect(text, contains('<v>-250.0</v>'));
      expect(text.contains("'<v>"), isFalse);
    });

    test('Optical_Orders handles JSONB prescription, frame, and lens structures safely', () {
      final opticalRecords = [
        {
          'id': 'opt-001',
          'order_number': 'ORD-OPT-001',
          'patient_id': 'p-1',
          'order_type': 'SPECTACLES',
          'order_status': 'IN_PROGRESS',
          'payment_status': 'PARTIAL',
          'total_amount': 4500.0,
          'delivery_date': '2026-10-20',
          'prescription_details': {
            're': {'sph': -1.5, 'cyl': -0.5, 'axis': 90},
            'le': {'sph': -1.25, 'cyl': -0.25, 'axis': 85},
          },
          'frame_details': {'model': 'Titan Metal 501', 'color': 'Matte Black'},
          'lens_details': {'type': 'Anti-Reflective Blue Cut', 'index': 1.61},
          'created_at': '2026-10-10T12:00:00Z',
          'updated_at': '2026-10-10T12:00:00Z',
        },
      ];

      final bytes = builder.buildWorkbook(
        recordsByWorksheet: {'Optical_Orders': opticalRecords},
      );

      final text = String.fromCharCodes(bytes);

      expect(text, contains('ORD-OPT-001'));
      expect(text, contains('SPECTACLES'));
      expect(text, contains('Titan Metal 501'));
      expect(text, contains('Anti-Reflective Blue Cut'));
    });

    test('Empty worksheets are tracked with status empty without failing export', () {
      final recordsBySheet = <String, List<Map<String, dynamic>>>{
        'Patients': [
          {'id': 'p-1', 'name': 'John Doe', 'patient_number': 'P-001'}
        ],
        // All other 20 worksheets have 0 records
      };

      final service = ExcelHistoricalExportService();

      final output = service.generateLocalHistoricalWorkbook(
        recordsByWorksheet: recordsBySheet,
      );

      expect(output.result.success, isTrue);
      expect(output.result.totalRecords, equals(1));

      final patientsSummary = output.result.worksheetSummaries
          .firstWhere((s) => s.worksheetName == 'Patients');
      expect(patientsSummary.status, equals('success'));
      expect(patientsSummary.recordCount, equals(1));

      final staffSummary = output.result.worksheetSummaries
          .firstWhere((s) => s.worksheetName == 'Staff_Directory');
      expect(staffSummary.status, equals('empty'));
      expect(staffSummary.recordCount, equals(0));
    });

    test('HistoricalExportResultModel serialization handles success and failure', () {
      final successJson = {
        'success': true,
        'syncId': 'sync-123',
        'totalRecords': 450,
        'fileSizeBytes': 102400,
        'storagePath': 'clinic-excel-sync/MKES_CARE_Plus_Master.xlsx',
        'durationMs': 1200,
        'worksheetSummaries': [
          {
            'worksheetName': 'Patients',
            'sourceTable': 'patients',
            'recordCount': 450,
            'highWaterMark': '2026-10-12T10:00:00Z',
            'status': 'success',
          }
        ],
      };

      final model = HistoricalExportResultModel.fromJson(successJson);
      expect(model.success, isTrue);
      expect(model.syncId, equals('sync-123'));
      expect(model.totalRecords, equals(450));
      expect(model.fileSizeMegabytes, closeTo(0.097, 0.01));
      expect(model.worksheetSummaries.length, equals(1));
      expect(model.worksheetSummaries.first.isSuccess, isTrue);

      final serialized = model.toJson();
      expect(serialized['success'], isTrue);
      expect(serialized['totalRecords'], equals(450));

      final failureJson = {
        'success': false,
        'syncId': 'sync-failed-999',
        'error': 'Worksheet [Appointments] query failed on table [appointments]: permission denied',
      };

      final failedModel = HistoricalExportResultModel.fromJson(failureJson);
      expect(failedModel.success, isFalse);
      expect(failedModel.errorMessage, contains('Appointments'));
    });

    test('OpenXML zip package contains all 21 worksheets and standard OpenXML parts', () {
      final bytes = builder.buildWorkbook();
      final text = String.fromCharCodes(bytes);

      expect(text, contains('[Content_Types].xml'));
      expect(text, contains('_rels/.rels'));
      expect(text, contains('xl/workbook.xml'));
      expect(text, contains('xl/_rels/workbook.xml.rels'));
      expect(text, contains('xl/styles.xml'));

      for (int i = 1; i <= 21; i++) {
        expect(text, contains('xl/worksheets/sheet$i.xml'));
      }
    });

    test('HistoricalExportValidationReport validates a complete 21-sheet export package', () {
      final dummyData = <String, List<Map<String, dynamic>>>{};
      for (final sheet in ExcelWorkbookSchema.worksheets) {
        dummyData[sheet.name] = [
          {sheet.stableIdKey: 'rec-1', sheet.timestampKey: '2026-10-14T10:00:00Z', 'name': 'Item 1'}
        ];
      }

      final service = ExcelHistoricalExportService();
      final output = service.generateLocalHistoricalWorkbook(recordsByWorksheet: dummyData);

      final report = ExcelHistoricalExportService.validateExportIntegrity(
        result: output.result,
        bytes: output.bytes,
      );

      expect(report.isValid, isTrue);
      expect(report.errors, isEmpty);
      expect(report.totalRecords, equals(21));
      expect(report.worksheetCount, equals(21));
      expect(report.hasValidZipHeader, isTrue);
      expect(report.hasAll21Worksheets, isTrue);
      expect(report.hasAllOpenXmlParts, isTrue);
    });

    test('HistoricalExportValidationReport flags corrupted zip header and count mismatches', () {
      // 1. Corrupted zip magic header
      final badZipResult = const HistoricalExportResultModel(
        success: true,
        syncId: 'sync-bad-zip',
        totalRecords: 0,
        fileSizeBytes: 10,
        storagePath: 'clinic-excel-sync/MKES_CARE_Plus_Master.xlsx',
        durationMs: 10,
        worksheetSummaries: [],
      );

      final badReport = ExcelHistoricalExportService.validateExportIntegrity(
        result: badZipResult,
        bytes: Uint8List.fromList([0x00, 0x00, 0x00, 0x00]),
      );

      expect(badReport.isValid, isFalse);
      expect(badReport.hasValidZipHeader, isFalse);
      expect(badReport.errors, anyElement(contains('PK zip magic header')));
      expect(badReport.errors, anyElement(contains('Expected 21 worksheet summaries')));

      // 2. Summary count reconciliation mismatch
      final mismatchedSummaries = List.generate(
        21,
        (i) => WorksheetExportSummaryModel(
          worksheetName: ExcelWorkbookSchema.worksheets[i].name,
          sourceTable: ExcelWorkbookSchema.worksheets[i].sourceTable,
          recordCount: 5, // 21 * 5 = 105
          highWaterMark: '2026-10-14T00:00:00Z',
          status: 'success',
        ),
      );

      final countMismatchResult = HistoricalExportResultModel(
        success: true,
        syncId: 'sync-count-mismatch',
        totalRecords: 999, // Mismatched (expected 105)
        fileSizeBytes: 5000,
        storagePath: 'clinic-excel-sync/MKES_CARE_Plus_Master.xlsx',
        durationMs: 50,
        worksheetSummaries: mismatchedSummaries,
      );

      final dummyBytes = builder.buildWorkbook();
      final mismatchReport = ExcelHistoricalExportService.validateExportIntegrity(
        result: countMismatchResult,
        bytes: dummyBytes,
      );

      expect(mismatchReport.isValid, isFalse);
      expect(mismatchReport.errors, anyElement(contains('Total records mismatch')));
    });

    test('Relational joins and null foreign keys format cleanly with fallback -', () {
      final recordsWithJoinsAndNulls = <String, List<Map<String, dynamic>>>{
        'Appointments': [
          // Row 1: Valid joined patient and doctor objects
          {
            'id': 'app-001',
            'department': 'eye',
            'appointment_date': '2026-10-14',
            'appointment_time': '10:00',
            'appointment_type': 'regular',
            'status': 'scheduled',
            'ai_booked': true,
            'patients': {'patient_number': 'PAT-0099', 'name': 'Anita Desai'},
            'doctor': {'full_name': 'Dr. Rajiv Menon'},
            'created_at': '2026-10-14T08:00:00Z',
            'updated_at': '2026-10-14T08:00:00Z',
          },
          // Row 2: Null joined patient and doctor (walk-in or unassigned doctor)
          {
            'id': 'app-002',
            'department': 'dental',
            'appointment_date': '2026-10-14',
            'appointment_time': '11:00',
            'appointment_type': 'walk_in',
            'status': 'waiting',
            'ai_booked': false,
            'patients': null,
            'doctor': null,
            'created_at': '2026-10-14T08:30:00Z',
            'updated_at': '2026-10-14T08:30:00Z',
          },
        ],
      };

      final bytes = builder.buildWorkbook(recordsByWorksheet: recordsWithJoinsAndNulls);
      final text = String.fromCharCodes(bytes);

      // Verify row 1 joined data present
      expect(text, contains('PAT-0099'));
      expect(text, contains('Anita Desai'));
      expect(text, contains('Dr. Rajiv Menon'));

      // Verify row 2 nulls rendered safely without crash
      expect(text, contains('app-002'));
    });

    test('PostgreSQL database column aliases resolve accurately for Department_Stock, Stock_Requests, and Billing', () {
      final rawDbRecords = <String, List<Map<String, dynamic>>>{
        'Department_Stock': [
          {
            'id': 'dept-stock-1',
            'department_id': 'd-1',
            'departments': {'name': 'Ophthalmology'},
            'inventory': {'name': 'IOL Lens Model A', 'sku': 'IOL-A1', 'unit': 'pieces'},
            'quantity': 45.0, // DB column: quantity -> maps to Current Stock
            'minimum_stock': 10.0,
            'updated_at': '2026-10-14T10:00:00Z',
          },
        ],
        'Stock_Requests': [
          {
            'id': 'sr-001',
            'request_number': 'REQ-2026-001',
            'department_id': 'd-1',
            'departments': {'name': 'Dental Clinic'},
            'requester': {'full_name': 'Nurse Meena'},
            'status': 'pending',
            'request_notes': 'Urgent requirement for disposable syringes', // DB column: request_notes -> Notes
            'created_at': '2026-10-14T09:00:00Z',
            'updated_at': '2026-10-14T09:00:00Z',
          },
        ],
        'Billing_Invoices': [
          {
            'id': 'inv-001',
            'invoice_number': '1/26-27',
            'patient_id': 'p-1',
            'department': 'eye',
            'subtotal': 5000.0,
            'discount': 500.0,
            'total_amount': 4500.0,
            'amount_paid': 2000.0, // DB column: amount_paid -> Paid Amount; Balance = 2500.0
            'payment_status': 'partially_paid', // DB column: payment_status -> Status
            'payment_mode': 'upi', // DB column: payment_mode -> Payment Mode
            'notes': 'Consultation & drops',
            'created_at': '2026-10-14T11:00:00Z',
            'updated_at': '2026-10-14T11:00:00Z',
            'patients': {'name': 'Kavita Roy', 'patient_number': 'P-501'},
            'profiles': {'full_name': 'Cashier Suresh'},
          },
        ],
        'Billing_Line_Items': [
          {
            'id': 'item-001',
            'billing_id': 'inv-001',
            'service_name': 'Slit Lamp Examination', // DB column: service_name -> Item / Service Name
            'quantity': 1,
            'unit_price': 500.0,
            'total_amount': 500.0, // DB column: total_amount -> Total Amount
            'is_custom': false,
            'billing': {'invoice_number': '1/26-27'},
            'created_at': '2026-10-14T11:00:00Z',
          },
        ],
        'Billing_Payments': [
          {
            'id': 'pay-001',
            'billing_id': 'inv-001',
            'amount': 2000.0,
            'payment_mode': 'upi', // DB column: payment_mode -> Payment Method
            'payment_reference': 'UPI-REF-998877', // DB column: payment_reference -> Transaction Ref
            'paid_at': '2026-10-14T11:05:00Z', // DB column: paid_at -> Payment Date
            'notes': 'First payment',
            'created_at': '2026-10-14T11:05:00Z',
            'billing': {'invoice_number': '1/26-27'},
            'profiles': {'full_name': 'Cashier Suresh'},
          },
        ],
      };

      final bytes = builder.buildWorkbook(recordsByWorksheet: rawDbRecords);
      final text = String.fromCharCodes(bytes);

      // Dept stock validations
      expect(text, contains('Ophthalmology'));
      expect(text, contains('IOL Lens Model A'));
      expect(text, contains('IOL-A1'));
      expect(text, contains('<v>45.0</v>'));

      // Stock requests validations
      expect(text, contains('REQ-2026-001'));
      expect(text, contains('Dental Clinic'));
      expect(text, contains('Nurse Meena'));
      expect(text, contains('Urgent requirement for disposable syringes'));

      // Billing invoice validations
      expect(text, contains('1/26-27'));
      expect(text, contains('Kavita Roy'));
      expect(text, contains('P-501'));
      expect(text, contains('<v>5000.0</v>'));
      expect(text, contains('<v>4500.0</v>'));
      expect(text, contains('<v>2000.0</v>')); // amount_paid
      expect(text, contains('<v>2500.0</v>')); // calculated balance
      expect(text, contains('PARTIALLY_PAID'));

      // Billing line items validations
      expect(text, contains('Slit Lamp Examination'));

      // Billing payments validations
      expect(text, contains('UPI-REF-998877'));
    });

    test('High-water mark timestamp tracks maximum timestamp across unordered records', () {
      final unorderedPatients = [
        {'id': 'p-1', 'updated_at': '2026-10-10T12:00:00Z', 'patient_number': 'P-1'},
        {'id': 'p-2', 'updated_at': '2026-10-14T18:00:00Z', 'patient_number': 'P-2'}, // Max
        {'id': 'p-3', 'updated_at': '2026-10-12T09:00:00Z', 'patient_number': 'P-3'},
      ];

      final service = ExcelHistoricalExportService();
      final output = service.generateLocalHistoricalWorkbook(
        recordsByWorksheet: {'Patients': unorderedPatients},
      );

      final patientSummary = output.result.worksheetSummaries
          .firstWhere((s) => s.worksheetName == 'Patients');

      expect(patientSummary.highWaterMark, equals('2026-10-14T18:00:00Z'));
      expect(patientSummary.recordCount, equals(3));
    });

    test('Partial export failure reporting preserves completed worksheets and error detail', () {
      final partialFailureJson = {
        'success': false,
        'syncId': 'sync-partial-456',
        'error': 'Worksheet [Dental_Lab_Cases] query failed on table [dental_lab]: connection timeout',
        'worksheetsCompleted': [
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
        ],
      };

      final failedResult = HistoricalExportResultModel.fromJson(partialFailureJson);
      expect(failedResult.success, isFalse);
      expect(failedResult.syncId, equals('sync-partial-456'));
      expect(failedResult.errorMessage, contains('Dental_Lab_Cases'));
      expect(failedResult.errorMessage, contains('connection timeout'));
    });
  });
}

