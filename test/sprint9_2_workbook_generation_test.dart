import 'package:flutter_test/flutter_test.dart';
import 'package:mkes_care/features/reports/services/excel_workbook_builder.dart';
import 'package:mkes_care/features/reports/services/excel_workbook_schema.dart';

void main() {
  group('Sprint 9.2 — Master Workbook Generation & OpenXML Validation Tests', () {
    late ExcelWorkbookBuilder builder;

    setUp(() {
      builder = ExcelWorkbookBuilder();
    });

    test('All 21 finalized worksheets exist in the catalog', () {
      expect(ExcelWorkbookSchema.totalWorksheetCount, equals(21));

      final sheetNames = ExcelWorkbookSchema.worksheets.map((s) => s.name).toList();
      final expected = [
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

      expect(sheetNames, equals(expected));
    });

    test('Generated buffer begins with standard PK zip magic bytes (0x50, 0x4B, 0x03, 0x04)', () {
      final bytes = builder.buildWorkbook();

      expect(bytes.length, greaterThan(1024), reason: 'Workbook should contain OpenXML parts');
      expect(bytes[0], equals(0x50)); // 'P'
      expect(bytes[1], equals(0x4B)); // 'K'
      expect(bytes[2], equals(0x03)); // 0x03
      expect(bytes[3], equals(0x04)); // 0x04
    });

    test('Generated XLSX package contains all required OpenXML parts and all 21 sheets', () {
      final bytes = builder.buildWorkbook();
      final textContent = String.fromCharCodes(bytes);

      // Verify essential OpenXML package structure
      expect(textContent, contains('[Content_Types].xml'));
      expect(textContent, contains('_rels/.rels'));
      expect(textContent, contains('xl/workbook.xml'));
      expect(textContent, contains('xl/_rels/workbook.xml.rels'));
      expect(textContent, contains('xl/styles.xml'));

      // Verify all 21 worksheets are packaged as sheet1.xml through sheet21.xml
      for (int i = 1; i <= 21; i++) {
        expect(textContent, contains('xl/worksheets/sheet$i.xml'));
      }

      // Verify all 20 sheet names appear in the workbook xml part
      for (final sheet in ExcelWorkbookSchema.worksheets) {
        expect(textContent, contains('name="${sheet.name}"'));
      }

      // Verify frozen pane declaration exists in worksheets
      expect(textContent, contains('state="frozen"'));
      expect(textContent, contains('ySplit="1"'));
    });

    test('Staff_Directory strictly excludes salary and authentication secrets even when provided in records', () {
      final sampleStaff = [
        {
          'id': 'staff-uuid-001',
          'full_name': 'Dr. Sharma',
          'email': 'sharma@mkescare.com',
          'phone_number': '+919876543210',
          'department': 'Eye Clinic',
          'designation': 'Ophthalmologist',
          'role': 'staff',
          'is_active': true,
          'salary': 150000.00, // SENSITIVE COMPENSATION
          'password_hash': 'sha256_secret_hash_value', // AUTH SECRET
        }
      ];

      final bytes = builder.buildWorkbook(recordsByWorksheet: {
        'Staff_Directory': sampleStaff,
      });

      final textContent = String.fromCharCodes(bytes);

      // Verify Dr. Sharma exists
      expect(textContent, contains('Dr. Sharma'));
      expect(textContent, contains('sharma@mkescare.com'));

      // Verify salary value 150000 and auth secrets are NOT present in the workbook
      expect(textContent, isNot(contains('150000')));
      expect(textContent, isNot(contains('sha256_secret_hash_value')));
      expect(textContent, isNot(contains('password_hash')));
    });

    test('Relational identifiers are preserved between parent and child worksheets', () {
      final sampleInvoice = [
        {
          'id': 'inv-uuid-1',
          'invoice_number': 'INV-EYE-2026-0001',
          'patient_number': 'EYE-2026-0001',
          'patient_name': 'Ramesh Kumar',
          'department': 'eye',
          'invoice_date': '2026-10-13',
          'subtotal': 1200.00,
          'discount': 0.00,
          'total_amount': 1200.00,
          'paid_amount': 1200.00,
          'balance_amount': 0.00,
          'status': 'paid',
        }
      ];

      final sampleItems = [
        {
          'id': 'item-uuid-1',
          'invoice_number': 'INV-EYE-2026-0001',
          'item_type': 'service',
          'item_name': 'Comprehensive Eye Examination',
          'quantity': 1,
          'unit_price': 800.00,
          'total_price': 800.00,
        },
        {
          'id': 'item-uuid-2',
          'invoice_number': 'INV-EYE-2026-0001',
          'item_type': 'service',
          'item_name': 'Tonometry Test',
          'quantity': 1,
          'unit_price': 400.00,
          'total_price': 400.00,
        }
      ];

      final samplePayments = [
        {
          'id': 'pay-uuid-1',
          'invoice_number': 'INV-EYE-2026-0001',
          'payment_date': '2026-10-13 10:30',
          'amount': 1200.00,
          'payment_method': 'UPI',
        }
      ];

      final bytes = builder.buildWorkbook(recordsByWorksheet: {
        'Billing_Invoices': sampleInvoice,
        'Billing_Line_Items': sampleItems,
        'Billing_Payments': samplePayments,
      });

      final textContent = String.fromCharCodes(bytes);

      // Verify linking key INV-EYE-2026-0001 is present across invoices, items, and payments
      expect(textContent, contains('INV-EYE-2026-0001'));
      expect(textContent, contains('Comprehensive Eye Examination'));
      expect(textContent, contains('Tonometry Test'));
      expect(textContent, contains('Ramesh Kumar'));
    });

    test('Null values and formatting fallbacks are handled cleanly without exceptions', () {
      final samplePatient = [
        {
          'id': 'pat-uuid-null-test',
          'patient_number': 'EYE-2026-9999',
          'name': 'Test Patient',
          'dob': null, // null date
          'address': null, // null text
          'mobile': null, // null mobile
          'department': null,
          'reference': null,
          'visit_date': null,
          'created_at': '2026-10-13T10:00:00Z',
          'updated_at': null,
        }
      ];

      final bytes = builder.buildWorkbook(recordsByWorksheet: {
        'Patients': samplePatient,
      });

      expect(bytes.length, greaterThan(1000));
      final textContent = String.fromCharCodes(bytes);
      expect(textContent, contains('Test Patient'));
      expect(textContent, contains('EYE-2026-9999'));
    });

    test('Repeated generation produces deterministic schema without duplicate worksheets', () {
      final run1 = builder.buildWorkbook();
      final run2 = builder.buildWorkbook();

      expect(run1.length, equals(run2.length), reason: 'Repeated generation should produce identical output length');

      // Verify each worksheet name occurs exactly once in the workbook XML
      final text1 = String.fromCharCodes(run1);
      for (final sheet in ExcelWorkbookSchema.worksheets) {
        final matches = RegExp('name="${sheet.name}"').allMatches(text1);
        expect(matches.length, equals(1), reason: 'Sheet ${sheet.name} must appear exactly once');
      }
    });

    test('Formula injection defense sanitizes strings starting with =, +, -, @, tab, and CR', () {
      // 1. Direct unit assertions on sanitizeSpreadsheetString
      expect(
        ExcelWorkbookBuilder.sanitizeSpreadsheetString("=cmd|' /C calc'!A0"),
        equals("'=cmd|' /C calc'!A0"),
      );
      expect(
        ExcelWorkbookBuilder.sanitizeSpreadsheetString("@SUM(A1:B10)"),
        equals("'@SUM(A1:B10)"),
      );
      expect(
        ExcelWorkbookBuilder.sanitizeSpreadsheetString("+12345"),
        equals("'+12345"),
      );
      expect(
        ExcelWorkbookBuilder.sanitizeSpreadsheetString("-2+3"),
        equals("'-2+3"),
      );
      expect(
        ExcelWorkbookBuilder.sanitizeSpreadsheetString("\t=1+1"),
        equals("'\t=1+1"),
      );
      expect(
        ExcelWorkbookBuilder.sanitizeSpreadsheetString("\r@dangerous"),
        equals("'\r@dangerous"),
      );
      expect(
        ExcelWorkbookBuilder.sanitizeSpreadsheetString("   =1+1"),
        equals("'   =1+1"),
      );
      expect(
        ExcelWorkbookBuilder.sanitizeSpreadsheetString("  \t+999"),
        equals("'  \t+999"),
      );

      // Ordinary text must NOT have apostrophe prepended
      expect(
        ExcelWorkbookBuilder.sanitizeSpreadsheetString("Standard Patient Name"),
        equals("Standard Patient Name"),
      );
      expect(
        ExcelWorkbookBuilder.sanitizeSpreadsheetString(""),
        equals(""),
      );
      expect(
        ExcelWorkbookBuilder.sanitizeSpreadsheetString("Eye Clinic Department"),
        equals("Eye Clinic Department"),
      );
    });

    test('Workbook builder safely handles formula injection, XML characters, and preserves negative numbers', () {
      final samplePatient = [
        {
          'id': 'pat-safe-001',
          'patient_number': 'EYE-2026-0001',
          'name': '=cmd|\' /C calc\'!A0', // Formula injection attempt in name
          'dob': '1990-01-01',
          'mobile': '+919876543210', // Phone with leading +
          'address': '<Hospital & Clinic "North" Wing \'A\'>', // XML special characters
          'department': '@SUM(A1:B1)', // Formula injection attempt in text
          'reference': '   =1+1', // Formula injection attempt with leading spaces
          'visit_date': '2026-10-13',
          'created_at': '2026-10-13 10:00',
          'updated_at': '2026-10-13 10:00',
        }
      ];

      final sampleBilling = [
        {
          'id': 'inv-neg-001',
          'invoice_number': 'INV-2026-9001',
          'patient_number': 'EYE-2026-0001',
          'patient_name': 'Safe Patient',
          'department': 'eye',
          'invoice_date': '2026-10-13',
          'subtotal': 1000.00,
          'discount': -150.50, // Legitimate negative numeric discount
          'tax_amount': 50.00,
          'total_amount': 900.00,
          'paid_amount': 1000.00,
          'balance_amount': -100.00, // Legitimate negative balance (credit)
          'status': 'paid',
          'payment_method': 'cash',
          'billed_by_name': 'Reception',
          'updated_at': '2026-10-13 10:00',
        }
      ];

      final sampleOpticalOrders = [
        {
          'id': 'opt-ord-001',
          'order_number': 'ORD-2026-001',
          'patient_number': 'EYE-2026-0001',
          'patient_name': 'Safe Patient',
          'order_type': 'spectacle',
          'order_status': 'processing',
          'payment_status': 'paid',
          'delivery_date': '2026-10-20',
          'total_amount': 3500.00,
          'prescription_details': {'sph_od': -2.5, 'sph_os': -3.0}, // JSONB with numbers
          'frame_details': {'brand': 'RayBan', 'color': 'Matte Black'},
          'lens_details': {'type': 'Progressive', 'index': 1.67},
          'created_at': '2026-10-13 10:00',
          'updated_at': '2026-10-13 10:00',
        }
      ];

      final bytes = builder.buildWorkbook(recordsByWorksheet: {
        'Patients': samplePatient,
        'Billing_Invoices': sampleBilling,
        'Optical_Orders': sampleOpticalOrders,
      });

      final textContent = String.fromCharCodes(bytes);

      // 1. Verify formula injection attempt strings have prepended apostrophe and are XML-escaped
      expect(
        textContent,
        contains('&apos;=cmd'),
        reason: 'Formula starting with = must have quote prepended',
      );
      expect(
        textContent,
        contains('&apos;@SUM'),
        reason: 'Formula starting with @ must have quote prepended',
      );
      expect(
        textContent,
        contains('&apos;+919876543210'),
        reason: 'Text starting with + must have quote prepended',
      );
      expect(
        textContent,
        contains('&apos;   =1+1'),
        reason: 'Formula with leading whitespace must have quote prepended',
      );

      // 2. Verify XML special characters are safely escaped
      expect(textContent, contains('&lt;Hospital &amp; Clinic &quot;North&quot; Wing &apos;A&apos;&gt;'));

      // 3. Verify legitimate negative numbers REMAIN numeric <v> values and do NOT become strings
      expect(
        textContent,
        contains('<v>-150.5</v>'),
        reason: 'Negative numeric discount must be preserved as numeric <v> value',
      );
      expect(
        textContent,
        contains('<v>-100.0</v>'),
        reason: 'Negative numeric balance must be preserved as numeric <v> value',
      );
      expect(
        textContent,
        isNot(contains('&apos;-150.5')),
        reason: 'Negative numeric discount must not have apostrophe prepended',
      );
      expect(
        textContent,
        isNot(contains('&apos;-100')),
        reason: 'Negative numeric balance must not have apostrophe prepended',
      );

      // 4. Verify Optical_Orders JSONB details are serialized and present
      expect(textContent, contains('ORD-2026-001'));
      expect(textContent, contains('RayBan'));
      expect(textContent, contains('Progressive'));

      // 5. Verify NO formula tags (<f>) are emitted anywhere in the workbook
      expect(
        textContent,
        isNot(contains('<f>')),
        reason: 'Untrusted user strings must never be emitted as executable formula cells',
      );
      expect(
        textContent,
        isNot(contains('</f>')),
        reason: 'Workbook must not contain any closing formula tags',
      );
    });
  });
}
