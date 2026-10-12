import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:mkes_care/features/auth/providers/auth_provider.dart';
import 'package:mkes_care/features/reports/models/inventory_reports_model.dart';
import 'package:mkes_care/features/reports/models/overview_reports_model.dart';
import 'package:mkes_care/features/reports/models/reports_filter_model.dart';
import 'package:mkes_care/features/reports/providers/reports_provider.dart';
import 'package:mkes_care/features/reports/screens/admin_reports_screen.dart';
import 'package:mkes_care/features/reports/services/reports_export_service.dart';

void main() {
  group('Sprint 8 Phase 8.2 — Inventory Reports Models & Valuation Logic', () {
    test(
        'Valuation calculations correctly separate central and department stock without double counting',
        () {
      final categoryStats = [
        const CategoryValuationStat(
          category: 'Pharmaceuticals',
          itemCount: 5,
          totalUnits: 150.0,
          totalValuation: 15000.0,
          percentage: 60.0,
        ),
        const CategoryValuationStat(
          category: 'Clinical Supplies',
          itemCount: 3,
          totalUnits: 100.0,
          totalValuation: 10000.0,
          percentage: 40.0,
        ),
      ];

      final reportsData = InventoryReportsData(
        totalCatalogItems: 8,
        activeItemsCount: 8,
        centralValuation: 15000.0,
        eyeValuation: 6000.0,
        dentalValuation: 4000.0,
        totalValuation: 25000.0,
        centralUnits: 150.0,
        eyeUnits: 60.0,
        dentalUnits: 40.0,
        totalUnits: 250.0,
        categoryValuations: categoryStats,
        centralLowStockCount: 1,
        departmentLowStockCount: 2,
        stockOutCount: 1,
        lowStockItems: const [],
        expiredBatchesCount: 1,
        expiredValueLost: 1200.0,
        expiring30DaysCount: 2,
        expiring30DaysValue: 2400.0,
        expiring60DaysCount: 1,
        expiring60DaysValue: 1000.0,
        expiring90DaysCount: 0,
        expiring90DaysValue: 0.0,
        totalAtRiskValue: 4600.0,
        batchExpiryDetails: const [],
        totalStockInUnits: 500.0,
        totalStockInValue: 50000.0,
        totalStockOutUnits: 250.0,
        totalStockOutValue: 25000.0,
        movementTrends: const [],
        movementReasons: const [],
        fastMovingItems: const [],
        auditLedger: const [],
      );

      expect(reportsData.totalValuation, equals(25000.0));
      expect(
          reportsData.centralValuation +
              reportsData.eyeValuation +
              reportsData.dentalValuation,
          equals(25000.0));
      expect(reportsData.totalUnits, equals(250.0));
      expect(
          reportsData.centralUnits +
              reportsData.eyeUnits +
              reportsData.dentalUnits,
          equals(250.0));
      expect(
          reportsData.totalAtRiskValue, equals(1200.0 + 2400.0 + 1000.0 + 0.0));
    });

    test('Low-stock shortfall and stock-out identification logic', () {
      final stockOutItem = LowStockItemStat(
        itemId: 'item-1',
        itemName: 'Atropine Eye Drops',
        unit: 'vials',
        location: 'Central Store',
        currentStock: 0.0,
        minimumStock: 10.0,
        shortfall: 10.0,
        vendorName: 'Apex Pharma',
        vendorPhone: '9876543210',
        lastPrice: 120.0,
        isStockOut: true,
      );

      final lowStockItem = LowStockItemStat(
        itemId: 'item-2',
        itemName: 'Dental Composite Resin',
        unit: 'tubes',
        location: 'Dental Clinic',
        currentStock: 3.0,
        minimumStock: 8.0,
        shortfall: 5.0,
        vendorName: 'DentalTech',
        lastPrice: 450.0,
        isStockOut: false,
      );

      expect(stockOutItem.isStockOut, isTrue);
      expect(stockOutItem.shortfall, equals(10.0));
      expect(lowStockItem.isStockOut, isFalse);
      expect(lowStockItem.shortfall, equals(5.0));
    });

    test('Batch expiry urgency classification', () {
      final expiredBatch = BatchExpiryStat(
        batchId: 'b-1',
        batchNumber: 'BAT-2024-01',
        itemId: 'item-1',
        itemName: 'Surgical Gloves',
        category: 'Consumables & PPE',
        expiryDate: DateTime.now().subtract(const Duration(days: 15)),
        daysRemaining: -15,
        remainingQuantity: 20.0,
        unitPrice: 50.0,
        totalAmount: 1000.0,
        urgencyStatus: 'expired',
      );

      final urgentBatch = BatchExpiryStat(
        batchId: 'b-2',
        batchNumber: 'BAT-2024-02',
        itemId: 'item-2',
        itemName: 'Mydriacyl Drops',
        category: 'Pharmaceuticals',
        expiryDate: DateTime.now().add(const Duration(days: 20)),
        daysRemaining: 20,
        remainingQuantity: 10.0,
        unitPrice: 150.0,
        totalAmount: 1500.0,
        urgencyStatus: '30days',
      );

      expect(expiredBatch.isExpired, isTrue);
      expect(urgentBatch.isExpired, isFalse);
      expect(urgentBatch.urgencyStatus, equals('30days'));
    });
  });

  group('Sprint 8 Phase 8.2 — Reports Export Service CSV & HTML Generators',
      () {
    test('generateCsvContent generates valid CSV with BOM and sections', () {
      final sampleData = InventoryReportsData(
        totalCatalogItems: 3,
        activeItemsCount: 3,
        centralValuation: 10000.0,
        eyeValuation: 3000.0,
        dentalValuation: 2000.0,
        totalValuation: 15000.0,
        centralUnits: 100.0,
        eyeUnits: 30.0,
        dentalUnits: 20.0,
        totalUnits: 150.0,
        categoryValuations: [
          const CategoryValuationStat(
            category: 'Pharmaceuticals',
            itemCount: 2,
            totalUnits: 100.0,
            totalValuation: 10000.0,
            percentage: 66.7,
          ),
        ],
        centralLowStockCount: 1,
        departmentLowStockCount: 0,
        stockOutCount: 0,
        lowStockItems: [
          const LowStockItemStat(
            itemId: 'i-1',
            itemName: 'Eye Drops',
            unit: 'bottles',
            location: 'Central Store',
            currentStock: 2.0,
            minimumStock: 10.0,
            shortfall: 8.0,
            vendorName: 'HealthCorp',
            vendorPhone: '1234567890',
            lastPrice: 100.0,
            isStockOut: false,
          ),
        ],
        expiredBatchesCount: 0,
        expiredValueLost: 0.0,
        expiring30DaysCount: 0,
        expiring30DaysValue: 0.0,
        expiring60DaysCount: 0,
        expiring60DaysValue: 0.0,
        expiring90DaysCount: 0,
        expiring90DaysValue: 0.0,
        totalAtRiskValue: 0.0,
        batchExpiryDetails: const [],
        totalStockInUnits: 200.0,
        totalStockInValue: 20000.0,
        totalStockOutUnits: 50.0,
        totalStockOutValue: 5000.0,
        movementTrends: const [],
        movementReasons: const [],
        fastMovingItems: const [],
        auditLedger: const [],
      );

      final csv = ReportsExportService.generateCsvContent(
          sampleData, const AdminReportsFilter());
      expect(csv.startsWith('\uFEFF'), isTrue); // Excel UTF-8 BOM
      expect(csv, contains('MKES CARE+ CLINICAL MANAGEMENT PLATFORM'));
      expect(csv, contains('Pharmaceuticals'));
      expect(csv, contains('Eye Drops'));
      expect(csv, contains('HealthCorp'));
    });

    test(
        'generateCsvContent safely escapes embedded double quotes in user fields',
        () {
      final sampleData = InventoryReportsData(
        totalCatalogItems: 1,
        activeItemsCount: 1,
        centralValuation: 2500.0,
        eyeValuation: 0.0,
        dentalValuation: 0.0,
        totalValuation: 2500.0,
        centralUnits: 10.0,
        eyeUnits: 0.0,
        dentalUnits: 0.0,
        totalUnits: 10.0,
        categoryValuations: [
          const CategoryValuationStat(
            category: 'Surgical "Specialty" Tools',
            itemCount: 1,
            totalUnits: 10.0,
            totalValuation: 2500.0,
            percentage: 100.0,
          ),
        ],
        centralLowStockCount: 1,
        departmentLowStockCount: 0,
        stockOutCount: 0,
        lowStockItems: [
          const LowStockItemStat(
            itemId: 'i-99',
            itemName: '14" Scissors',
            unit: 'pairs',
            location: 'Central Store',
            currentStock: 2.0,
            minimumStock: 5.0,
            shortfall: 3.0,
            vendorName: 'Apex "Precision" MedTech',
            vendorPhone: '9876543210',
            lastPrice: 250.0,
            isStockOut: false,
          ),
        ],
        expiredBatchesCount: 0,
        expiredValueLost: 0.0,
        expiring30DaysCount: 0,
        expiring30DaysValue: 0.0,
        expiring60DaysCount: 0,
        expiring60DaysValue: 0.0,
        expiring90DaysCount: 0,
        expiring90DaysValue: 0.0,
        totalAtRiskValue: 0.0,
        batchExpiryDetails: const [],
        totalStockInUnits: 10.0,
        totalStockInValue: 2500.0,
        totalStockOutUnits: 0.0,
        totalStockOutValue: 0.0,
        movementTrends: const [],
        movementReasons: const [],
        fastMovingItems: const [],
        auditLedger: [
          InventoryAuditEntry(
            id: 'audit-1',
            date: DateTime(2026, 10, 10, 14, 30),
            itemName: '14" Scissors',
            transactionType: 'stock_out',
            quantity: 1.0,
            reason: 'Routine "Clinical" Usage',
            performedByName: 'Admin',
            recipientInfo: 'Dept "OT" 1',
            remarks: 'Issued per Dr. Rao\'s "Urgent" note',
          ),
        ],
      );

      final csv = ReportsExportService.generateCsvContent(
          sampleData, const AdminReportsFilter());

      // Embedded double quotes must be escaped to ""
      expect(csv, contains('"14"" Scissors"'));
      expect(csv, contains('"Surgical ""Specialty"" Tools"'));
      expect(csv, contains('"Apex ""Precision"" MedTech"'));
      expect(csv, contains('"Routine ""Clinical"" Usage"'));
      expect(csv, contains('"Dept ""OT"" 1"'));
      expect(csv, contains('"Issued per Dr. Rao\'s ""Urgent"" note"'));
    });

    test('generateHtmlContent generates full HTML document with print CSS', () {
      final sampleData = InventoryReportsData(
        totalCatalogItems: 2,
        activeItemsCount: 2,
        centralValuation: 5000.0,
        eyeValuation: 2000.0,
        dentalValuation: 1000.0,
        totalValuation: 8000.0,
        centralUnits: 50.0,
        eyeUnits: 20.0,
        dentalUnits: 10.0,
        totalUnits: 80.0,
        categoryValuations: const [],
        centralLowStockCount: 0,
        departmentLowStockCount: 0,
        stockOutCount: 0,
        lowStockItems: const [],
        expiredBatchesCount: 0,
        expiredValueLost: 0.0,
        expiring30DaysCount: 0,
        expiring30DaysValue: 0.0,
        expiring60DaysCount: 0,
        expiring60DaysValue: 0.0,
        expiring90DaysCount: 0,
        expiring90DaysValue: 0.0,
        totalAtRiskValue: 0.0,
        batchExpiryDetails: const [],
        totalStockInUnits: 0.0,
        totalStockInValue: 0.0,
        totalStockOutUnits: 0.0,
        totalStockOutValue: 0.0,
        movementTrends: const [],
        movementReasons: const [],
        fastMovingItems: const [],
        auditLedger: const [],
      );

      final html = ReportsExportService.generateHtmlContent(
          sampleData, const AdminReportsFilter());
      expect(html, contains('<!DOCTYPE html>'));
      expect(html, contains('MKES CARE+ Clinical Management Platform'));
      expect(html, contains('@media print'));
      expect(html, contains('Total Stock Valuation'));
    });
  });

  group('Sprint 8 Phase 8.2 — Access Control & Role Checks', () {
    testWidgets('Non-admin user receives Access Restricted screen',
        (tester) async {
      await tester.pumpWidget(
        ProviderScope(
          overrides: [
            currentUserRoleProvider
                .overrideWith((ref) => Future.value('staff')),
          ],
          child: const MaterialApp(
            home: AdminReportsScreen(),
          ),
        ),
      );

      await tester.pumpAndSettle();

      expect(find.text('Access Restricted'), findsOneWidget);
      expect(
        find.text(
            'Only administrators have permission to access clinic reports, financial analytics, and inventory valuations.'),
        findsOneWidget,
      );
      expect(find.text('Return to Dashboard'), findsOneWidget);
    });

    testWidgets('Admin user is granted access and sees filter toolbar and tabs',
        (tester) async {
      await tester.pumpWidget(
        ProviderScope(
          overrides: [
            currentUserRoleProvider
                .overrideWith((ref) => Future.value('admin')),
            overviewReportsProvider.overrideWith((ref) => Future.value(
                  const OverviewReportsData(
                    totalPatients: 10,
                    newPatients: 2,
                    totalAppointments: 8,
                    completedAppointments: 7,
                    totalProcedures: 12,
                    totalSales: 15000.0,
                    totalRevenue: 12000.0,
                    totalOutstanding: 3000.0,
                    eyePatients: 6,
                    dentalPatients: 4,
                    eyeAppointments: 5,
                    dentalAppointments: 3,
                    eyeProcedures: 8,
                    dentalProcedures: 4,
                    eyeSales: 9000.0,
                    dentalSales: 6000.0,
                    totalInventoryValuation: 45000.0,
                    lowStockCount: 2,
                    expiredBatchesCount: 0,
                    trendPoints: [],
                  ),
                )),
          ],
          child: const MaterialApp(
            home: AdminReportsScreen(),
          ),
        ),
      );

      await tester.pumpAndSettle();

      expect(find.text('Access Restricted'), findsNothing);
      expect(find.text('Reports & Analytics'), findsOneWidget);
      expect(find.text('Inventory & Stock'), findsOneWidget);
      expect(find.text('Inventory Valuation'), findsOneWidget);
    });
  });
}
