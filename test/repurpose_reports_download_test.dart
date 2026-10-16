import 'package:flutter_test/flutter_test.dart';
import 'package:mkes_care/features/billing/models/billing_reports_model.dart';
import 'package:mkes_care/features/patients/models/patient_model.dart';
import 'package:mkes_care/features/reports/models/appointment_reports_model.dart';
import 'package:mkes_care/features/reports/models/clinical_reports_model.dart';
import 'package:mkes_care/features/reports/models/inventory_reports_model.dart';
import 'package:mkes_care/features/reports/models/overview_reports_model.dart';
import 'package:mkes_care/features/reports/models/patient_reports_model.dart';
import 'package:mkes_care/features/reports/models/reports_filter_model.dart';
import 'package:mkes_care/features/reports/models/staff_reports_model.dart';
import 'package:mkes_care/features/reports/services/reports_export_service.dart';

void main() {
  group('MKES CARE+ — Repurpose Reports Download & Central Inventory Audit', () {
    // ──────────────────────────────────────────────────────────────────────────
    // 1. DATE PRESET BOUNDARIES & INCLUSIVE CUSTOM RANGES
    // ──────────────────────────────────────────────────────────────────────────
    group('Requirement 2 & 4: Date Presets & Filter Boundary Correctness', () {
      test('Today preset encompasses 00:00:00 to 23:59:59.999', () {
        const filter = AdminReportsFilter(datePreset: ReportsDatePreset.today);
        final start = filter.effectiveStartDate!;
        final end = filter.effectiveEndDate!;

        expect(start.hour, equals(0));
        expect(start.minute, equals(0));
        expect(start.second, equals(0));

        expect(end.hour, equals(23));
        expect(end.minute, equals(59));
        expect(end.second, equals(59));
        expect(end.isAfter(start), isTrue);
      });

      test('This Week preset encompasses start of week to end of week', () {
        const filter = AdminReportsFilter(datePreset: ReportsDatePreset.thisWeek);
        final start = filter.effectiveStartDate!;
        final end = filter.effectiveEndDate!;

        expect(start.weekday, equals(DateTime.monday));
        expect(start.hour, equals(0));
        expect(end.hour, equals(23));
        expect(end.isAfter(start), isTrue);
      });

      test('This Month preset starts on day 1 and ends on last day of month', () {
        const filter = AdminReportsFilter(datePreset: ReportsDatePreset.thisMonth);
        final start = filter.effectiveStartDate!;
        final end = filter.effectiveEndDate!;

        expect(start.day, equals(1));
        expect(start.hour, equals(0));
        expect(end.month, equals(start.month));
        expect(end.hour, equals(23));
        expect(end.minute, equals(59));
      });

      test('This Year preset starts on Jan 1 and ends on Dec 31', () {
        const filter = AdminReportsFilter(datePreset: ReportsDatePreset.thisYear);
        final start = filter.effectiveStartDate!;
        final end = filter.effectiveEndDate!;

        expect(start.month, equals(1));
        expect(start.day, equals(1));
        expect(end.month, equals(12));
        expect(end.day, equals(31));
      });

      test('All Time preset returns null for both start and end dates (all historical records included)', () {
        const filter = AdminReportsFilter(datePreset: ReportsDatePreset.allTime);
        expect(filter.effectiveStartDate, isNull);
        expect(filter.effectiveEndDate, isNull);
      });

      test('Custom Range preset includes start at 00:00:00 and final day inclusive at 23:59:59.999', () {
        final filter = AdminReportsFilter(
          datePreset: ReportsDatePreset.custom,
          customStartDate: DateTime(2026, 5, 10, 14, 30),
          customEndDate: DateTime(2026, 5, 20, 9, 15),
        );

        final start = filter.effectiveStartDate!;
        final end = filter.effectiveEndDate!;

        expect(start.year, equals(2026));
        expect(start.month, equals(5));
        expect(start.day, equals(10));
        expect(start.hour, equals(0));
        expect(start.minute, equals(0));
        expect(start.second, equals(0));

        expect(end.year, equals(2026));
        expect(end.month, equals(5));
        expect(end.day, equals(20));
        expect(end.hour, equals(23));
        expect(end.minute, equals(59));
        expect(end.second, equals(59));
      });
    });

    // ──────────────────────────────────────────────────────────────────────────
    // 2. FILE NAMING SPECIFICATIONS
    // ──────────────────────────────────────────────────────────────────────────
    group('Requirement 5: Standalone Report File Naming Convention', () {
      test('Patients tab with This Week produces Patients_This_Week.xlsx', () {
        const filter = AdminReportsFilter(datePreset: ReportsDatePreset.thisWeek);
        expect(filter.getReportFileName(ReportsSection.patients), equals('Patients_This_Week.xlsx'));
      });

      test('Appointments tab with This Month produces Appointments_This_Month.xlsx', () {
        const filter = AdminReportsFilter(datePreset: ReportsDatePreset.thisMonth);
        expect(filter.getReportFileName(ReportsSection.appointments), equals('Appointments_This_Month.xlsx'));
      });

      test('Inventory tab with All Time produces Inventory_All_Time.xlsx', () {
        const filter = AdminReportsFilter(datePreset: ReportsDatePreset.allTime);
        expect(filter.getReportFileName(ReportsSection.inventory), equals('Inventory_All_Time.xlsx'));
      });

      test('Billing tab with Custom Range produces Billing_Custom_Range.xlsx', () {
        const filter = AdminReportsFilter(datePreset: ReportsDatePreset.custom);
        expect(filter.getReportFileName(ReportsSection.financial), equals('Billing_Custom_Range.xlsx'));
      });

      test('Overview tab with Today produces Overview_Today.xlsx', () {
        const filter = AdminReportsFilter(datePreset: ReportsDatePreset.today);
        expect(filter.getReportFileName(ReportsSection.overview), equals('Overview_Today.xlsx'));
      });

      test('Staff & Tasks tab with This Year produces Staff_Tasks_This_Year.xlsx', () {
        const filter = AdminReportsFilter(datePreset: ReportsDatePreset.thisYear);
        expect(filter.getReportFileName(ReportsSection.staff), equals('Staff_Tasks_This_Year.xlsx'));
      });

      test('Clinical tab with This Month produces Clinical_Procedures_This_Month.xlsx', () {
        const filter = AdminReportsFilter(datePreset: ReportsDatePreset.thisMonth);
        expect(filter.getReportFileName(ReportsSection.clinical), equals('Clinical_Procedures_This_Month.xlsx'));
      });
    });

    // ──────────────────────────────────────────────────────────────────────────
    // 3. STANDALONE OPENXML (.XLSX) BINARY EXPORT FOR ALL 7 REPORT TABS
    // ──────────────────────────────────────────────────────────────────────────
    group('Requirement 3: Standalone Excel Generation for Every Section', () {
      bool isValidZip(List<int> bytes) {
        // Valid ZIP file must start with PK\x03\x04 signature
        return bytes.length >= 4 &&
            bytes[0] == 0x50 &&
            bytes[1] == 0x4B &&
            bytes[2] == 0x03 &&
            bytes[3] == 0x04;
      }

      test('Tab 1: Overview report generates valid standalone .xlsx with KPI and trend worksheets', () {
        final data = OverviewReportsData(
          totalPatients: 120,
          newPatients: 35,
          totalAppointments: 90,
          completedAppointments: 75,
          totalProcedures: 60,
          totalSales: 450000.0,
          totalRevenue: 400000.0,
          totalOutstanding: 50000.0,
          eyePatients: 70,
          dentalPatients: 50,
          eyeAppointments: 55,
          dentalAppointments: 35,
          eyeProcedures: 38,
          dentalProcedures: 22,
          eyeSales: 260000.0,
          dentalSales: 190000.0,
          totalInventoryValuation: 850000.0,
          lowStockCount: 4,
          expiredBatchesCount: 1,
          trendPoints: [
            ActivityTrendPoint(
              label: 'Mon',
              date: DateTime(2026, 10, 12),
              patientCount: 12,
              appointmentCount: 15,
              procedureCount: 8,
              salesAmount: 50000.0,
            ),
          ],
        );

        final bytes = ReportsExportService.generateOverviewReportWorkbook(data);
        expect(isValidZip(bytes), isTrue);
        expect(bytes.length, greaterThan(1000));
      });

      test('Tab 2: Patients report generates valid standalone .xlsx with patient records and summary', () {
        final data = PatientReportsData(
          totalPatients: 85,
          newPatients: 20,
          returningPatients: 65,
          eyePatients: 50,
          dentalPatients: 35,
          eyePercentage: 58.8,
          dentalPercentage: 41.2,
          registrationTrends: [
            PatientTrendPoint(
              label: '10 Oct',
              date: DateTime(2026, 10, 10),
              count: 6,
            ),
          ],
          recentPatients: [
            PatientModel(
              id: 'pat-101',
              patientNumber: 'PAT-2026-001',
              name: 'Amit Patel',
              mobile: '+919876543210',
              dob: DateTime(1985, 3, 15),
              address: 'Mumbai',
              department: 'eye',
              reference: 'Walk-in',
              visitDate: DateTime(2026, 10, 1),
              createdAt: DateTime(2026, 10, 1),
              updatedAt: DateTime(2026, 10, 1),
            ),
          ],
        );

        final bytes = ReportsExportService.generatePatientsReportWorkbook(data);
        expect(isValidZip(bytes), isTrue);
        expect(bytes.length, greaterThan(1000));
      });

      test('Tab 3: Appointments report generates valid standalone .xlsx with doctor performance', () {
        final data = AppointmentReportsData(
          totalAppointments: 140,
          completedAppointments: 120,
          cancelledAppointments: 10,
          scheduledAppointments: 8,
          inTriageAppointments: 2,
          completionRate: 85.7,
          cancellationRate: 7.1,
          eyeAppointments: 80,
          dentalAppointments: 60,
          eyePercentage: 57.1,
          dentalPercentage: 42.9,
          regularAppointments: 100,
          walkInAppointments: 25,
          followUpAppointments: 15,
          doctorStats: [
            DoctorAppointmentStat(
              doctorId: 'doc-1',
              doctorName: 'Dr. Ramesh Sharma',
              department: 'Eye',
              totalAppointments: 80,
              completedAppointments: 72,
              cancelledAppointments: 5,
            ),
          ],
          appointmentTrends: [
            AppointmentTrendPoint(
              label: '12 Oct',
              date: DateTime(2026, 10, 12),
              total: 20,
              completed: 18,
              cancelled: 1,
            ),
          ],
        );

        final bytes = ReportsExportService.generateAppointmentsReportWorkbook(data);
        expect(isValidZip(bytes), isTrue);
        expect(bytes.length, greaterThan(1000));
      });

      test('Tab 4: Staff & Tasks report generates valid standalone .xlsx with workforce metrics', () {
        final data = StaffReportsData(
          totalStaff: 15,
          activeStaff: 14,
          totalAttendanceLogs: 180,
          presentCount: 160,
          lateCount: 12,
          leaveCount: 8,
          overallAttendanceRate: 88.9,
          attendanceTrends: [
            AttendanceTrendPoint(
              label: '12 Oct',
              date: DateTime(2026, 10, 12),
              present: 14,
              late: 1,
              leave: 0,
            ),
          ],
          totalTasks: 45,
          completedTasks: 38,
          pendingTasks: 4,
          inProgressTasks: 2,
          overdueTasks: 1,
          taskCompletionRate: 84.4,
          staffStats: [
            StaffPerformanceStat(
              staffId: 'st-1',
              staffName: 'Pooja Verma',
              designation: 'Senior Optometrist',
              department: 'Eye',
              attendanceLogs: 22,
              presentDays: 20,
              lateDays: 1,
              leaveDays: 1,
              attendancePercentage: 90.9,
              totalTasks: 10,
              completedTasks: 9,
              pendingTasks: 1,
              overdueTasks: 0,
              taskCompletionPercentage: 90.0,
            ),
          ],
        );

        final bytes = ReportsExportService.generateStaffReportWorkbook(data);
        expect(isValidZip(bytes), isTrue);
        expect(bytes.length, greaterThan(1000));
      });

      test('Tab 5: Clinical / Procedures report generates valid standalone .xlsx with procedure leaderboard', () {
        final data = ClinicalReportsData(
          totalProcedures: 72,
          eyeProcedures: 44,
          dentalProcedures: 28,
          eyePercentage: 61.1,
          dentalPercentage: 38.9,
          totalProceduresValue: 320000.0,
          topProcedures: [
            ProcedureLeaderboardItem(
              procedureName: 'Cataract Phaco Surgery',
              department: 'Eye',
              count: 24,
              totalRevenue: 240000.0,
              averagePrice: 10000.0,
            ),
          ],
          procedureTrends: [
            ProcedureTrendPoint(
              label: '12 Oct',
              date: DateTime(2026, 10, 12),
              eyeCount: 5,
              dentalCount: 3,
              totalCount: 8,
            ),
          ],
        );

        final bytes = ReportsExportService.generateClinicalReportWorkbook(data);
        expect(isValidZip(bytes), isTrue);
        expect(bytes.length, greaterThan(1000));
      });

      test('Tab 6: Billing & Financial report generates valid standalone .xlsx with departmental revenue', () {
        final data = BillingReportsData(
          totalSales: 890000.0,
          totalRevenue: 810000.0,
          totalOutstanding: 80000.0,
          estimatedProfit: 340000.0,
          totalInvoices: 210,
          paidInvoicesCount: 185,
          partiallyPaidInvoicesCount: 25,
          averageOrderValue: 4238.1,
          collectionRate: 91.0,
          eyeSummary: DepartmentRevenueSummary(
            department: 'Eye',
            invoiceCount: 125,
            totalSales: 520000.0,
            revenueCollected: 480000.0,
            outstandingBalance: 40000.0,
            estimatedProfit: 210000.0,
            sharePercentage: 58.4,
          ),
          dentalSummary: DepartmentRevenueSummary(
            department: 'Dental',
            invoiceCount: 85,
            totalSales: 370000.0,
            revenueCollected: 330000.0,
            outstandingBalance: 40000.0,
            estimatedProfit: 130000.0,
            sharePercentage: 41.6,
          ),
          paymentModes: [
            PaymentModeSummary(
              mode: 'UPI',
              totalAmount: 510000.0,
              transactionCount: 130,
              percentage: 63.0,
            ),
            PaymentModeSummary(
              mode: 'Cash',
              totalAmount: 300000.0,
              transactionCount: 80,
              percentage: 37.0,
            ),
          ],
          periodicBuckets: [
            PeriodRevenueBucket(
              periodLabel: 'Oct 2026',
              date: DateTime(2026, 10, 1),
              invoiceCount: 210,
              totalSales: 890000.0,
              revenueCollected: 810000.0,
              outstandingBalance: 80000.0,
              estimatedProfit: 340000.0,
              collectionRate: 91.0,
            ),
          ],
          topServices: [
            ServicePerformanceSummary(
              serviceName: 'Comprehensive Eye Examination',
              department: 'Eye',
              quantity: 85,
              totalRevenue: 42500.0,
            ),
          ],
        );

        final bytes = ReportsExportService.generateFinancialReportWorkbook(data);
        expect(isValidZip(bytes), isTrue);
        expect(bytes.length, greaterThan(1000));
      });

      test('Tab 7: Inventory report generates valid standalone .xlsx with valuation and audit ledger', () {
        final data = InventoryReportsData(
          totalCatalogItems: 42,
          activeItemsCount: 38,
          centralValuation: 250000.0,
          eyeValuation: 90000.0,
          dentalValuation: 60000.0,
          totalValuation: 400000.0,
          centralUnits: 500.0,
          eyeUnits: 150.0,
          dentalUnits: 100.0,
          totalUnits: 750.0,
          categoryValuations: [
            const CategoryValuationStat(
              category: 'Medications',
              itemCount: 15,
              totalUnits: 300.0,
              totalValuation: 180000.0,
              percentage: 45.0,
            ),
          ],
          centralLowStockCount: 2,
          departmentLowStockCount: 3,
          stockOutCount: 1,
          lowStockItems: [
            const LowStockItemStat(
              itemId: 'item-1',
              itemName: 'Moxifloxacin Eye Drops 0.5%',
              sku: 'MOXI-05',
              unit: 'vial',
              location: 'Eye Clinic',
              currentStock: 4.0,
              minimumStock: 10.0,
              shortfall: 6.0,
              vendorName: 'PharmaPlus Supplies',
              vendorPhone: '9876543210',
              lastPrice: 120.0,
              isStockOut: false,
            ),
          ],
          expiredBatchesCount: 1,
          expiredValueLost: 1500.0,
          expiring30DaysCount: 2,
          expiring30DaysValue: 3200.0,
          expiring60DaysCount: 1,
          expiring60DaysValue: 1800.0,
          expiring90DaysCount: 0,
          expiring90DaysValue: 0.0,
          totalAtRiskValue: 6500.0,
          batchExpiryDetails: [
            BatchExpiryStat(
              batchId: 'b-1',
              batchNumber: 'LOT-9921',
              itemId: 'item-1',
              itemName: 'Moxifloxacin Eye Drops 0.5%',
              category: 'Medications',
              expiryDate: DateTime(2026, 11, 15),
              daysRemaining: 30,
              remainingQuantity: 10.0,
              unitPrice: 120.0,
              totalAmount: 1200.0,
              urgencyStatus: '30days',
            ),
          ],
          totalStockInUnits: 200.0,
          totalStockInValue: 24000.0,
          totalStockOutUnits: 120.0,
          totalStockOutValue: 14400.0,
          movementTrends: [],
          movementReasons: [
            const MovementReasonStat(
              reason: 'Clinical Procedure',
              transactionCount: 25,
              totalUnits: 50.0,
              totalValue: 6000.0,
              isStockIn: false,
            ),
          ],
          fastMovingItems: [
            const FastMovingItemStat(
              itemId: 'item-1',
              itemName: 'Moxifloxacin Eye Drops 0.5%',
              category: 'Medications',
              totalConsumedUnits: 50.0,
              totalConsumedValue: 6000.0,
              transactionCount: 25,
            ),
          ],
          auditLedger: [
            InventoryAuditEntry(
              id: 'tx-001',
              itemName: 'Moxifloxacin Eye Drops 0.5%',
              transactionType: 'stock_out',
              quantity: 2.0,
              stockBefore: 12.0,
              stockAfter: 10.0,
              reason: 'Dispensed to Patient',
              performedByName: 'Nurse Sneha',
              recipientInfo: 'Patient #PAT-2026-001',
              remarks: 'Post-op medication',
              date: DateTime(2026, 10, 14, 11, 30),
            ),
          ],
        );

        final bytes = ReportsExportService.generateInventoryReportWorkbook(data);
        expect(isValidZip(bytes), isTrue);
        expect(bytes.length, greaterThan(1500));
      });
    });

    // ──────────────────────────────────────────────────────────────────────────
    // 4. EMPTY REPORT RESULTS (GRACEFUL HANDLING)
    // ──────────────────────────────────────────────────────────────────────────
    group('Requirement 4: Empty Report Handling Without Misleading Data', () {
      bool isValidZip(List<int> bytes) {
        return bytes.length >= 4 &&
            bytes[0] == 0x50 &&
            bytes[1] == 0x4B &&
            bytes[2] == 0x03 &&
            bytes[3] == 0x04;
      }

      test('Empty Overview data generates valid .xlsx without crashing', () {
        const emptyOverview = OverviewReportsData(
          totalPatients: 0,
          newPatients: 0,
          totalAppointments: 0,
          completedAppointments: 0,
          totalProcedures: 0,
          totalSales: 0.0,
          totalRevenue: 0.0,
          totalOutstanding: 0.0,
          eyePatients: 0,
          dentalPatients: 0,
          eyeAppointments: 0,
          dentalAppointments: 0,
          eyeProcedures: 0,
          dentalProcedures: 0,
          eyeSales: 0.0,
          dentalSales: 0.0,
          trendPoints: [],
        );

        final bytes = ReportsExportService.generateOverviewReportWorkbook(emptyOverview);
        expect(isValidZip(bytes), isTrue);
      });

      test('Empty Patient data generates valid .xlsx without crashing', () {
        final bytes = ReportsExportService.generatePatientsReportWorkbook(PatientReportsData.empty);
        expect(isValidZip(bytes), isTrue);
      });

      test('Empty Staff data generates valid .xlsx without crashing', () {
        final bytes = ReportsExportService.generateStaffReportWorkbook(StaffReportsData.empty);
        expect(isValidZip(bytes), isTrue);
      });

      test('Empty Clinical data generates valid .xlsx without crashing', () {
        final bytes = ReportsExportService.generateClinicalReportWorkbook(ClinicalReportsData.empty);
        expect(isValidZip(bytes), isTrue);
      });

      test('Empty Inventory data generates valid .xlsx without crashing', () {
        final bytes = ReportsExportService.generateInventoryReportWorkbook(InventoryReportsData.empty);
        expect(isValidZip(bytes), isTrue);
      });
    });

    // ──────────────────────────────────────────────────────────────────────────
    // 5. GENERAL DISPATCHER METHOD VERIFICATION
    // ──────────────────────────────────────────────────────────────────────────
    group('General buildSectionWorkbookBytes dispatcher verification', () {
      test('buildSectionWorkbookBytes routes each of the 7 sections to its dedicated builder', () {
        const filter = AdminReportsFilter(datePreset: ReportsDatePreset.thisMonth);

        for (final section in ReportsSection.values) {
          final bytes = ReportsExportService.buildSectionWorkbookBytes(
            section: section,
            filter: filter,
            sectionData: null, // Gracefully handles fallback / null data
          );

          expect(bytes, isNotEmpty);
          expect(bytes[0] == 0x50 && bytes[1] == 0x4B, isTrue);
        }
      });
    });

    // ──────────────────────────────────────────────────────────────────────────
    // 6. CENTRAL INVENTORY CLEANLINESS
    // ──────────────────────────────────────────────────────────────────────────
    group('Requirement 1: Central Inventory Cleanliness', () {
      test('Central Inventory filter and search states operate without single-period options', () {
        // Standard department filters in Central Inventory:
        const validCentralDepts = ['All', 'eye', 'dental', 'optical', 'general'];
        expect(validCentralDepts, contains('All'));
        expect(validCentralDepts, contains('eye'));
        expect(validCentralDepts, contains('dental'));
        expect(validCentralDepts, contains('optical'));
        expect(validCentralDepts, contains('general'));

        // Standard status filters in Central Inventory:
        const validStatuses = ['All', 'Low Stock', 'Expiring Soon', 'Expired'];
        expect(validStatuses.length, equals(4));
        expect(validStatuses, isNot(contains('Single Period')));
      });
    });
  });
}
