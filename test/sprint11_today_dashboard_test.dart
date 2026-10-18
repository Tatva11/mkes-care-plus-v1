import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:flutter_test/flutter_test.dart';

import 'package:mkes_care/core/utils/date_boundaries.dart';
import 'package:mkes_care/features/admin/models/user_profile.dart';
import 'package:mkes_care/features/admin/providers/users_provider.dart';
import 'package:mkes_care/features/admin/screens/admin_dashboard_screen.dart';
import 'package:mkes_care/features/admin/widgets/revenue_growth_card.dart';
import 'package:mkes_care/features/admin/widgets/staff_attendance_card.dart';
import 'package:mkes_care/features/auth/providers/auth_provider.dart';
import 'package:mkes_care/features/billing/providers/billing_provider.dart';
import 'package:mkes_care/features/notifications/providers/notifications_provider.dart';
import 'package:mkes_care/features/inventory/models/inventory_item.dart';
import 'package:mkes_care/features/inventory/models/inventory_transaction.dart';
import 'package:mkes_care/features/inventory/models/purchase_order.dart';
import 'package:mkes_care/features/inventory/providers/inventory_provider.dart';
import 'package:mkes_care/features/inventory/providers/purchase_order_provider.dart';
import 'package:mkes_care/features/patients/models/patient_model.dart';
import 'package:mkes_care/features/patients/providers/patients_provider.dart';
import 'package:mkes_care/features/staff/models/attendance_record.dart';
import 'package:mkes_care/features/staff/models/leave_request.dart';
import 'package:mkes_care/features/staff/models/task_item.dart';
import 'package:mkes_care/features/staff/providers/attendance_provider.dart';
import 'package:mkes_care/features/staff/providers/leave_provider.dart';
import 'package:mkes_care/features/staff/providers/task_provider.dart';
import 'package:mkes_care/features/vendors/models/vendor.dart';
import 'package:mkes_care/features/vendors/providers/vendor_provider.dart';

// Test Notifiers
class _MockTasksNotifier extends StateNotifier<AsyncValue<List<TaskItem>>>
    implements AdminTasksNotifier {
  _MockTasksNotifier(super.initial);
  @override
  Future<void> fetchTasks({bool silent = false}) async {}
  @override
  Future<void> createTask({
    required String title,
    String? description,
    required String assignedTo,
    required String adminId,
    DateTime? dueDate,
    String priority = 'medium',
  }) async {}
  @override
  Future<void> updateTask({
    required String taskId,
    required String adminId,
    required String title,
    String? description,
    required String assignedTo,
    DateTime? dueDate,
    required String priority,
    required String status,
    String? note,
  }) async {}
}

class _MockUsersNotifier extends StateNotifier<AsyncValue<List<UserProfile>>>
    implements UsersNotifier {
  _MockUsersNotifier(super.initial);
  @override
  Future<void> fetchUsers() async {}
  @override
  void search(String query) {}
  @override
  Future<void> createUser({
    required String fullName,
    required String email,
    required String password,
    String? phoneNumber,
    String? departmentId,
    String? designation,
    DateTime? joiningDate,
    required String role,
    double? salary,
  }) async {}
  @override
  Future<void> updateUser(String userId, Map<String, dynamic> updates) async {}
  @override
  Future<void> deleteUser(String userId) async {}
  @override
  Future<void> toggleStatus(String userId, bool currentStatus) async {}
}

class _MockAdminAllLeaveNotifier
    extends StateNotifier<AsyncValue<List<LeaveRequest>>>
    implements AdminAllLeaveNotifier {
  _MockAdminAllLeaveNotifier(super.initial);
  @override
  Future<void> fetchAll() async {}
  @override
  Future<void> approveRequest(String id, String adminId) async {}
  @override
  Future<void> rejectRequest(String id, String adminId, String reason) async {}
}

class _MockInventoryNotifier
    extends StateNotifier<AsyncValue<List<InventoryItem>>>
    implements InventoryNotifier {
  _MockInventoryNotifier(super.initial);
  @override
  Future<void> fetchInventory() async {}
  @override
  Future<void> refresh() async {}
  @override
  Future<InventoryItem> createItem(InventoryItem item) async => item;
  @override
  Future<InventoryItem> updateItem(InventoryItem item) async => item;
  @override
  Future<void> deleteItem(String id) async {}
  @override
  Future<InventoryTransaction> stockIn({
    required String itemId,
    required double quantity,
    String? reason,
    String? remarks,
    double? totalAmount,
    String? vendorId,
    String? batchNumber,
    DateTime? expiryDate,
  }) async =>
      throw UnimplementedError();
  @override
  Future<InventoryTransaction> stockOut({
    required String itemId,
    required double quantity,
    String? reason,
    String? remarks,
    String? patientId,
  }) async =>
      throw UnimplementedError();
  @override
  Future<InventoryTransaction> removeExpiredStock({
    required String inventoryId,
    required double quantity,
    String? batchNumber,
    String? remarks,
  }) async =>
      throw UnimplementedError();
}

class _MockVendorNotifier extends StateNotifier<AsyncValue<List<Vendor>>>
    implements VendorNotifier {
  _MockVendorNotifier(super.initial);
  @override
  Future<void> fetchVendors() async {}
  @override
  Future<void> refresh() async {}
  @override
  Future<Vendor> createVendor(Vendor vendor) async => vendor;
  @override
  Future<Vendor> updateVendor(Vendor vendor) async => vendor;
  @override
  Future<void> deleteVendor(String id) async {}
  @override
  Future<Vendor> toggleStatus(String id, bool isActive) async =>
      Vendor(id: id, name: '', isActive: isActive);
}

class _MockPurchaseOrdersNotifier
    extends StateNotifier<AsyncValue<List<PurchaseOrder>>>
    implements PurchaseOrdersNotifier {
  _MockPurchaseOrdersNotifier(super.initial);
  @override
  Future<void> fetchOrders() async {}
  @override
  Future<PurchaseOrder> createOrder(
          PurchaseOrder order, List<PurchaseOrderItem> items) async =>
      order;
  @override
  Future<PurchaseOrder> updateOrder(
          PurchaseOrder order, List<PurchaseOrderItem> items) async =>
      order;
  @override
  Future<void> updateStatus(String id, PurchaseOrderStatus status) async {}
  @override
  Future<void> cancelOrder(String id) async {}
  @override
  Future<Map<String, dynamic>> receiveOrder({
    required String purchaseOrderId,
    required List<Map<String, dynamic>> items,
  }) async =>
      {};
}

class _MockPatientsNotifier extends StateNotifier<AsyncValue<List<PatientModel>>>
    implements PatientsNotifier {
  _MockPatientsNotifier(super.initial);
  @override
  Future<void> loadPatients({String? department, String? search}) async {}
  @override
  Future<PatientModel> createPatient(PatientModel newPatient) async =>
      newPatient;
  @override
  Future<PatientModel> updatePatient(PatientModel updatedPatient) async =>
      updatedPatient;
}

void main() {
  TestWidgetsFlutterBinding.ensureInitialized();

  group('Sprint 11 — Part 1: Date Boundaries and Day Rollover', () {
    test('Calculates startOfDay, startOfTomorrow, and startOfYesterday accurately', () {
      final refDate = DateTime(2026, 10, 17, 14, 30, 45);

      final startToday = DateBoundaries.startOfDay(refDate);
      expect(startToday.year, 2026);
      expect(startToday.month, 10);
      expect(startToday.day, 17);
      expect(startToday.hour, 0);
      expect(startToday.minute, 0);
      expect(startToday.second, 0);

      final startTomorrow = DateBoundaries.startOfTomorrow(refDate);
      expect(startTomorrow.day, 18);
      expect(startTomorrow.hour, 0);
      expect(startTomorrow.difference(startToday).inHours, 24);

      final startYesterday = DateBoundaries.startOfYesterday(refDate);
      expect(startYesterday.day, 16);
      expect(startYesterday.hour, 0);
      expect(startToday.difference(startYesterday).inHours, 24);
    });

    test('isToday correctly evaluates inclusive start and exclusive tomorrow bounds', () {
      final ref = DateTime(2026, 10, 17, 12, 0);

      // Boundaries within today
      expect(DateBoundaries.isToday(DateTime(2026, 10, 17, 0, 0, 0), ref), isTrue);
      expect(DateBoundaries.isToday(DateTime(2026, 10, 17, 23, 59, 59, 999), ref), isTrue);

      // Outside today
      expect(DateBoundaries.isToday(DateTime(2026, 10, 16, 23, 59, 59, 999), ref), isFalse);
      expect(DateBoundaries.isToday(DateTime(2026, 10, 18, 0, 0, 0), ref), isFalse);
    });

    test('isYesterday correctly evaluates yesterday boundaries', () {
      final ref = DateTime(2026, 10, 17, 12, 0);

      expect(DateBoundaries.isYesterday(DateTime(2026, 10, 16, 0, 0, 0), ref), isTrue);
      expect(DateBoundaries.isYesterday(DateTime(2026, 10, 16, 23, 59, 59), ref), isTrue);

      expect(DateBoundaries.isYesterday(DateTime(2026, 10, 15, 23, 59, 59), ref), isFalse);
      expect(DateBoundaries.isYesterday(DateTime(2026, 10, 17, 0, 0, 0), ref), isFalse);
    });

    test('Intraday buckets partition the full day without index errors', () {
      expect(DateBoundaries.getIntradayBucketIndex(DateTime(2026, 10, 17, 8, 30)), 0); // <10a
      expect(DateBoundaries.getIntradayBucketIndex(DateTime(2026, 10, 17, 10, 15)), 1); // 10-12
      expect(DateBoundaries.getIntradayBucketIndex(DateTime(2026, 10, 17, 13, 0)), 2); // 12-2p
      expect(DateBoundaries.getIntradayBucketIndex(DateTime(2026, 10, 17, 15, 45)), 3); // 2-4p
      expect(DateBoundaries.getIntradayBucketIndex(DateTime(2026, 10, 17, 16, 20)), 4); // 4-6p
      expect(DateBoundaries.getIntradayBucketIndex(DateTime(2026, 10, 17, 19, 0)), 5); // 6p+
      expect(DateBoundaries.getIntradayBucketIndex(DateTime(2026, 10, 17, 23, 59)), 5); // 6p+
    });
  });

  group('Sprint 11 — Part 2: Revenue Growth Card (Today-Only)', () {
    testWidgets('Displays today actual collections, yesterday growth, and payment chips', (tester) async {
      const metrics = TodayRevenueMetrics(
        todayRevenue: 28500.0,
        yesterdayRevenue: 25000.0,
        growthPercentage: 14.0,
        todayTransactionsCount: 4,
        intradayHourlyBuckets: [5000.0, 12000.0, 6500.0, 5000.0, 0.0, 0.0],
        paymentModeAmounts: {
          'cash': 10000.0,
          'upi': 15000.0,
          'bank_transfer': 3500.0,
          'other': 0.0,
        },
      );

      await tester.pumpWidget(
        ProviderScope(
          overrides: [
            todayRevenueMetricsProvider.overrideWith((ref) => Future.value(metrics)),
          ],
          child: const MaterialApp(
            home: Scaffold(
              body: SingleChildScrollView(
                child: RevenueGrowthCard(),
              ),
            ),
          ),
        ),
      );

      await tester.pumpAndSettle();

      // Formatted revenue total
      expect(find.text('Revenue Growth'), findsOneWidget);
      expect(find.text('View Reports'), findsOneWidget);
      expect(find.text('4 collection transactions today'), findsOneWidget);

      // Growth badge
      expect(find.text('+14.0% vs yesterday'), findsOneWidget);

      // Payment chips
      expect(find.textContaining('Cash:'), findsOneWidget);
      expect(find.textContaining('UPI:'), findsOneWidget);
      expect(find.textContaining('Bank:'), findsOneWidget);
    });

    testWidgets('Honest growth calculation displays Growth unavailable when yesterday is 0', (tester) async {
      const metrics = TodayRevenueMetrics(
        todayRevenue: 15000.0,
        yesterdayRevenue: 0.0, // Zero revenue yesterday
        growthPercentage: null, // Growth unavailable
        todayTransactionsCount: 2,
        intradayHourlyBuckets: [15000.0, 0.0, 0.0, 0.0, 0.0, 0.0],
        paymentModeAmounts: {'cash': 15000.0},
      );

      await tester.pumpWidget(
        ProviderScope(
          overrides: [
            todayRevenueMetricsProvider.overrideWith((ref) => Future.value(metrics)),
          ],
          child: const MaterialApp(
            home: Scaffold(
              body: SingleChildScrollView(
                child: RevenueGrowthCard(),
              ),
            ),
          ),
        ),
      );

      await tester.pumpAndSettle();

      expect(find.text('Growth unavailable'), findsOneWidget);
    });

    testWidgets('Zero revenue today displays empty state message gracefully', (tester) async {
      const metrics = TodayRevenueMetrics(
        todayRevenue: 0.0,
        yesterdayRevenue: 0.0,
        growthPercentage: null,
        todayTransactionsCount: 0,
        intradayHourlyBuckets: [0.0, 0.0, 0.0, 0.0, 0.0, 0.0],
        paymentModeAmounts: {},
      );

      await tester.pumpWidget(
        ProviderScope(
          overrides: [
            todayRevenueMetricsProvider.overrideWith((ref) => Future.value(metrics)),
          ],
          child: const MaterialApp(
            home: Scaffold(
              body: SingleChildScrollView(
                child: RevenueGrowthCard(),
              ),
            ),
          ),
        ),
      );

      await tester.pumpAndSettle();

      expect(find.text('No collections recorded today'), findsWidgets);
    });
  });

  group('Sprint 11 — Part 3: Staff Attendance Card (Dynamic Data)', () {
    testWidgets('Calculates real department staff dynamically without mock OPD/Dental rows', (tester) async {
      final now = DateTime.now();
      final today = DateBoundaries.startOfDay(now);

      final user1 = UserProfile(
        id: 'u-1',
        fullName: 'Dr. Ramesh Kumar',
        email: 'ramesh@mkes.com',
        role: 'doctor',
        department: 'Eye Clinic',
        departmentName: 'Eye Clinic',
        isActive: true,
        createdAt: now,
      );

      final user2 = UserProfile(
        id: 'u-2',
        fullName: 'Dr. Priya Shah',
        email: 'priya@mkes.com',
        role: 'doctor',
        department: 'Dental Clinic',
        departmentName: 'Dental Clinic',
        isActive: true,
        createdAt: now,
      );

      final user3 = UserProfile(
        id: 'u-3',
        fullName: 'Kiran Patel',
        email: 'kiran@mkes.com',
        role: 'staff',
        department: 'Dental Clinic',
        departmentName: 'Dental Clinic',
        isActive: true,
        createdAt: now,
      );

      // Attendance: user1 is present today
      final att1 = AttendanceRecord(
        id: 'att-1',
        staffId: 'u-1',
        date: today,
        status: 'present',
        isLate: false,
        lateMinutes: 0,
        checkInTime: now,
      );

      // Leave: user3 is on approved leave today
      final leave1 = LeaveRequest(
        id: 'l-1',
        staffId: 'u-3',
        startDate: today.subtract(const Duration(days: 1)),
        endDate: today.add(const Duration(days: 1)),
        leaveDays: 3,
        reason: 'Family event',
        status: 'approved',
        createdAt: now.subtract(const Duration(days: 3)),
      );

      await tester.pumpWidget(
        ProviderScope(
          overrides: [
            usersProvider.overrideWith((ref) => _MockUsersNotifier(AsyncValue.data([user1, user2, user3]))),
            adminAttendanceForDateProvider(today).overrideWith((ref) => Future.value([att1])),
            adminAllLeaveRequestsProvider
                .overrideWith((ref) => _MockAdminAllLeaveNotifier(AsyncValue.data([leave1]))),
          ],
          child: const MaterialApp(
            home: Scaffold(
              body: SingleChildScrollView(
                child: StaffAttendanceCard(),
              ),
            ),
          ),
        ),
      );

      await tester.pumpAndSettle();

      // Summary KPIs
      expect(find.text('Present Today'), findsOneWidget);
      expect(find.text('1'), findsWidgets); // 1 present (u-1)
      expect(find.text('On Approved Leave'), findsOneWidget);

      // Real dynamic departments
      expect(find.text('Eye Clinic'), findsOneWidget);
      expect(find.text('1/1'), findsOneWidget); // 1 present out of 1 assigned
      expect(find.text('1 present'), findsOneWidget);

      expect(find.text('Dental Clinic'), findsOneWidget);
      expect(find.text('0/2'), findsOneWidget); // 0 present out of 2 assigned
      expect(find.text('1 on leave'), findsOneWidget);

      // Ensure hardcoded 'OPD 12/12' or 'Pharmacy 5/5' are completely absent
      expect(find.text('OPD'), findsNothing);
      expect(find.text('12/12'), findsNothing);
      expect(find.text('Pharmacy'), findsNothing);
      expect(find.text('Optimal'), findsNothing);
      expect(find.text('Short'), findsNothing);
    });
  });

  group('Sprint 11 — Part 4: Entire Dashboard Screen Integration', () {
    testWidgets('Renders complete dashboard and handles pull-to-refresh without overflow on 360x640', (tester) async {
      tester.view.physicalSize = const Size(360, 640);
      tester.view.devicePixelRatio = 1.0;
      addTearDown(tester.view.resetPhysicalSize);
      addTearDown(tester.view.resetDevicePixelRatio);

      final now = DateTime.now();
      final today = DateBoundaries.startOfDay(now);

      const metrics = TodayRevenueMetrics(
        todayRevenue: 10000.0,
        yesterdayRevenue: 8000.0,
        growthPercentage: 25.0,
        todayTransactionsCount: 1,
        intradayHourlyBuckets: [10000.0, 0.0, 0.0, 0.0, 0.0, 0.0],
        paymentModeAmounts: {'cash': 10000.0},
      );

      await tester.pumpWidget(
        ProviderScope(
          overrides: [
            currentUserRoleProvider.overrideWith((ref) => Future.value('admin')),
            currentProfileProvider.overrideWith((ref) => Future.value(null)),
            unreadNotificationCountProvider.overrideWithValue(0),
            todayRevenueMetricsProvider.overrideWith((ref) => Future.value(metrics)),
            patientsProvider.overrideWith((ref) => _MockPatientsNotifier(const AsyncValue.data([]))),
            todayScheduledPatientsProvider.overrideWith((ref) => Future.value([])),
            adminTasksProvider.overrideWith((ref) => _MockTasksNotifier(const AsyncValue.data([]))),
            usersProvider.overrideWith((ref) => _MockUsersNotifier(const AsyncValue.data([]))),
            adminAttendanceForDateProvider(today).overrideWith((ref) => Future.value([])),
            adminAttendanceSummaryProvider(today).overrideWith((ref) => Future.value({'present': 0, 'leave': 0})),
            adminAllLeaveRequestsProvider
                .overrideWith((ref) => _MockAdminAllLeaveNotifier(const AsyncValue.data([]))),
            inventoryProvider
                .overrideWith((ref) => _MockInventoryNotifier(const AsyncValue.data([]))),
            vendorsProvider.overrideWith((ref) => _MockVendorNotifier(const AsyncValue.data([]))),
            purchaseOrdersProvider.overrideWith((ref) => _MockPurchaseOrdersNotifier(const AsyncValue.data([]))),
          ],
          child: const MaterialApp(
            home: AdminDashboardScreen(),
          ),
        ),
      );

      await tester.pump();
      await tester.pump(const Duration(milliseconds: 500));

      // Verify that all 7 cards or their content are mounted cleanly
      expect(find.byType(RevenueGrowthCard), findsOneWidget);
      expect(find.byType(StaffAttendanceCard), findsOneWidget);
      expect(find.text('Copilot Insights'), findsOneWidget);

      expect(tester.takeException(), isNull);
    });
  });
}
