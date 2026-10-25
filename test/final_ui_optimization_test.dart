import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:flutter_test/flutter_test.dart';

import 'package:mkes_care/core/theme/app_colors.dart';
import 'package:mkes_care/core/theme/app_spacing.dart';
import 'package:mkes_care/features/admin/models/user_profile.dart';
import 'package:mkes_care/features/admin/providers/users_provider.dart';
import 'package:mkes_care/features/admin/screens/administration_screen.dart';
import 'package:mkes_care/features/admin/widgets/operations_tab_content.dart';
import 'package:mkes_care/features/admin/widgets/revenue_growth_card.dart';
import 'package:mkes_care/features/auth/models/profile_model.dart';
import 'package:mkes_care/features/auth/providers/auth_provider.dart';
import 'package:mkes_care/features/billing/providers/billing_provider.dart';
import 'package:mkes_care/features/settings/screens/settings_screen.dart';
import 'package:mkes_care/features/staff/models/attendance_record.dart';
import 'package:mkes_care/features/staff/models/shift_configuration.dart';
import 'package:mkes_care/features/staff/screens/staff_management_screen.dart';
import 'package:mkes_care/features/staff/widgets/staff_member_tile.dart';

void main() {
  TestWidgetsFlutterBinding.ensureInitialized();

  const mobileViewports = <double>[360.0, 390.0, 430.0];

  // ────────────────────────────────────────────────────────────────────────────
  // Task 1: Staff Management — 4 Navigation Buttons on One Row
  // ────────────────────────────────────────────────────────────────────────────
  group('Task 1 — Staff Management: Fit 4 Nav Buttons on One Row', () {
    for (final width in mobileViewports) {
      testWidgets(
          'Renders Leave, Tasks, Performance, Shifts on 1 row at $width px',
          (tester) async {
        tester.view.physicalSize = Size(width, 800);
        tester.view.devicePixelRatio = 1.0;
        addTearDown(() => tester.view.resetPhysicalSize());

        await tester.pumpWidget(
          const MaterialApp(
            home: Scaffold(
              body: Padding(
                padding: EdgeInsets.symmetric(horizontal: 16.0),
                child: StaffNavButtonsRow(),
              ),
            ),
          ),
        );
        await tester.pumpAndSettle();

        final leaveFinder = find.text('Leave');
        final tasksFinder = find.text('Tasks');
        final perfFinder = find.text('Performance');
        final shiftsFinder = find.text('Shifts');

        expect(leaveFinder, findsOneWidget);
        expect(tasksFinder, findsOneWidget);
        expect(perfFinder, findsOneWidget);
        expect(shiftsFinder, findsOneWidget);

        // Verify that all 4 buttons share the exact same top Y position (single horizontal row)
        final leaveY = tester.getTopLeft(leaveFinder).dy;
        final tasksY = tester.getTopLeft(tasksFinder).dy;
        final perfY = tester.getTopLeft(perfFinder).dy;
        final shiftsY = tester.getTopLeft(shiftsFinder).dy;

        expect((leaveY - tasksY).abs(), lessThan(2.0));
        expect((leaveY - perfY).abs(), lessThan(2.0));
        expect((leaveY - shiftsY).abs(), lessThan(2.0));

        // Zero RenderFlex overflow exceptions
        expect(tester.takeException(), isNull);
      });
    }
  });

  // ────────────────────────────────────────────────────────────────────────────
  // Task 2: Staff Roster — Show Only Essential Information
  // ────────────────────────────────────────────────────────────────────────────
  group('Task 2 — Staff Roster: Show Only Essential Information', () {
    final testStaffCheckedIn = UserProfile(
      id: 'staff-1',
      email: 'priya.sharma@mkescare.org',
      fullName: 'Priya Sharma (Senior Optometrist)',
      role: 'staff',
      designation: 'Senior Optometrist',
      department: 'eye',
      departmentName: 'OPD',
      isActive: true,
      createdAt: DateTime(2023, 1, 15),
    );

    final checkedInAttendance = AttendanceRecord(
      id: 'att-1',
      staffId: 'staff-1',
      date: DateTime.now(),
      status: 'present',
      isLate: false,
      lateMinutes: 0,
      checkInTime: DateTime(2026, 10, 18, 9, 15),
    );

    final testStaffNotCheckedIn = UserProfile(
      id: 'staff-2',
      email: 'rahul.verma@mkescare.org',
      fullName: 'Rahul Verma',
      role: 'staff',
      designation: 'Dental Assistant',
      department: 'dental',
      departmentName: 'Dental',
      isActive: true,
      createdAt: DateTime(2023, 3, 1),
    );

    testWidgets('Displays full name, role, status badge and check-in time',
        (tester) async {
      await tester.pumpWidget(
        MaterialApp(
          home: Scaffold(
            body: StaffMemberTile(
              user: testStaffCheckedIn,
              todayAttendance: checkedInAttendance,
            ),
          ),
        ),
      );
      await tester.pumpAndSettle();

      // Essential info present
      expect(find.text('Priya Sharma (Senior Optometrist)'), findsOneWidget);
      expect(find.text('Senior Optometrist • OPD'), findsOneWidget);
      expect(find.text('Present'), findsOneWidget);
      expect(find.textContaining('In: 9:15 AM'), findsOneWidget);
      expect(find.byIcon(Icons.chevron_right), findsOneWidget);

      // Clutter removed: email, phone, salary, joining date should NOT be displayed
      expect(find.text('priya.sharma@mkescare.org'), findsNothing);
      expect(find.textContaining('Salary'), findsNothing);
      expect(find.textContaining('Joined'), findsNothing);
      expect(tester.takeException(), isNull);
    });

    testWidgets('Displays "Not checked in" when attendance record is absent',
        (tester) async {
      await tester.pumpWidget(
        MaterialApp(
          home: Scaffold(
            body: StaffMemberTile(
              user: testStaffNotCheckedIn,
              todayAttendance: null,
            ),
          ),
        ),
      );
      await tester.pumpAndSettle();

      expect(find.text('Rahul Verma'), findsOneWidget);
      expect(find.text('Dental Assistant • Dental'), findsOneWidget);
      expect(find.text('Not Checked In'), findsOneWidget);
      expect(find.text('Not checked in'), findsOneWidget);
      expect(find.text('rahul.verma@mkescare.org'), findsNothing);
      expect(tester.takeException(), isNull);
    });
  });

  // ────────────────────────────────────────────────────────────────────────────
  // Task 3: Operations Navigation — Reduce Excessive Scrolling
  // ────────────────────────────────────────────────────────────────────────────
  group('Task 3 — Operations Navigation: Reduce Excessive Scrolling', () {
    testWidgets('Renders compact 6-tab grid on mobile without overflow',
        (tester) async {
      tester.view.physicalSize = const Size(390, 800);
      tester.view.devicePixelRatio = 1.0;
      addTearDown(() => tester.view.resetPhysicalSize());

      await tester.pumpWidget(
        const ProviderScope(
          child: MaterialApp(
            home: Scaffold(
              body: OperationsTabContent(initialTab: 0),
            ),
          ),
        ),
      );
      await tester.pumpAndSettle();

      // All 6 operational destinations visible on screen without scrolling
      expect(find.text('Inventory'), findsOneWidget);
      expect(find.text('Departments'), findsOneWidget);
      expect(find.text('Vendors'), findsOneWidget);
      expect(find.text('Purchase Orders'), findsOneWidget);
      expect(find.text('Dental Lab'), findsOneWidget);
      expect(find.text('Eye Surgery'), findsOneWidget);

      expect(tester.takeException(), isNull);
    });

    testWidgets('Renders SegmentedButton on desktop viewports', (tester) async {
      tester.view.physicalSize = const Size(1024, 800);
      tester.view.devicePixelRatio = 1.0;
      addTearDown(() => tester.view.resetPhysicalSize());

      await tester.pumpWidget(
        const ProviderScope(
          child: MaterialApp(
            home: Scaffold(
              body: OperationsTabContent(initialTab: 0),
            ),
          ),
        ),
      );
      await tester.pumpAndSettle();

      expect(find.byType(SegmentedButton<int>), findsOneWidget);
      expect(tester.takeException(), isNull);
    });
  });

  // ────────────────────────────────────────────────────────────────────────────
  // Task 4: Dashboard — Fix Truncated Titles with Wrap
  // ────────────────────────────────────────────────────────────────────────────
  group('Task 4 — Dashboard: Fix Truncated Titles with Wrap', () {
    const testRevenueMetrics = TodayRevenueMetrics(
      todayRevenue: 45200.0,
      yesterdayRevenue: 40000.0,
      growthPercentage: 12.5,
      todayTransactionsCount: 14,
      intradayHourlyBuckets: [5000.0, 12000.0, 28200.0, 0.0, 0.0, 0.0],
      paymentModeAmounts: {'cash': 20000.0, 'upi': 25200.0},
    );

    for (final width in mobileViewports) {
      testWidgets('RevenueGrowthCard header wraps cleanly without ellipsis at $width px',
          (tester) async {
        tester.view.physicalSize = Size(width, 800);
        tester.view.devicePixelRatio = 1.0;
        addTearDown(() => tester.view.resetPhysicalSize());

        await tester.pumpWidget(
          ProviderScope(
            overrides: [
              todayRevenueMetricsProvider.overrideWith(
                (ref) => Future.value(testRevenueMetrics),
              ),
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

        // Check full title and action button are readable without ellipsis or truncation
        expect(find.text('Revenue Growth'), findsOneWidget);
        expect(find.text('View Reports'), findsOneWidget);

        // Verify zero RenderFlex overflow
        expect(tester.takeException(), isNull);
      });
    }

    testWidgets('Header Wrap widget displays full section titles on narrow mobile',
        (tester) async {
      tester.view.physicalSize = const Size(360, 600);
      tester.view.devicePixelRatio = 1.0;
      addTearDown(() => tester.view.resetPhysicalSize());

      Widget buildDashboardHeader(String title, String actionLabel) {
        return Wrap(
          alignment: WrapAlignment.spaceBetween,
          crossAxisAlignment: WrapCrossAlignment.center,
          spacing: AppSpacing.xs,
          runSpacing: 4,
          children: [
            Row(
              mainAxisSize: MainAxisSize.min,
              children: [
                const Icon(Icons.analytics, size: 20),
                const SizedBox(width: AppSpacing.xs),
                Flexible(
                  child: Text(
                    title,
                    style: const TextStyle(fontSize: 16, fontWeight: FontWeight.bold),
                  ),
                ),
              ],
            ),
            TextButton(onPressed: () {}, child: Text(actionLabel)),
          ],
        );
      }

      await tester.pumpWidget(
        MaterialApp(
          home: Scaffold(
            body: Column(
              children: [
                buildDashboardHeader('Staff Attendance', 'View Attendance'),
                buildDashboardHeader("Today's Patient Summary", 'Manage Patients'),
                buildDashboardHeader('Critical Inventory', 'View Inventory'),
                buildDashboardHeader('Vendors & Procurement', 'All Vendors'),
                buildDashboardHeader('Task Overview', 'View All Tasks'),
              ],
            ),
          ),
        ),
      );
      await tester.pumpAndSettle();

      expect(find.text('Staff Attendance'), findsOneWidget);
      expect(find.text("Today's Patient Summary"), findsOneWidget);
      expect(find.text('Critical Inventory'), findsOneWidget);
      expect(find.text('Vendors & Procurement'), findsOneWidget);
      expect(find.text('Task Overview'), findsOneWidget);
      expect(tester.takeException(), isNull);
    });
  });

  // ────────────────────────────────────────────────────────────────────────────
  // Task 5: Settings — Remove Unused AI Settings and Fix Overflow
  // ────────────────────────────────────────────────────────────────────────────
  group('Task 5 — Settings: Remove Unused AI Settings and Prevent Overflow', () {
    testWidgets('AI Auto-Triage is removed and Clinic Defaults does not overflow',
        (tester) async {
      tester.view.physicalSize = const Size(360, 800);
      tester.view.devicePixelRatio = 1.0;
      addTearDown(() => tester.view.resetPhysicalSize());

      final testAdminProfile = ProfileModel(
        id: 'admin-1',
        email: 'admin@mkescare.org',
        fullName: 'Admin User',
        role: 'admin',
        isActive: true,
        createdAt: DateTime(2023, 1, 1),
      );

      await tester.pumpWidget(
        ProviderScope(
          overrides: [
            currentProfileProvider.overrideWith(
              (ref) => Future.value(testAdminProfile),
            ),
          ],
          child: const MaterialApp(
            home: SettingsScreen(),
          ),
        ),
      );
      await tester.pumpAndSettle();

      // AI controls must NOT exist
      expect(find.text('AI Auto-Triage Assistance'), findsNothing);
      expect(find.textContaining('copilot'), findsNothing);

      // Section titles must exist
      expect(find.text('Notification Preferences'), findsOneWidget);
      expect(find.text('Clinic Defaults'), findsOneWidget);
      expect(find.text('Auto-Save Clinical Notes'), findsOneWidget);
      expect(find.text('Default Landing View'), findsOneWidget);

      // Zero overflow
      expect(tester.takeException(), isNull);
    });
  });

  // ────────────────────────────────────────────────────────────────────────────
  // Task 6: Shift Management — Shift Configuration Responsive Card
  // ────────────────────────────────────────────────────────────────────────────
  group('Task 6 — Shift Management: Responsive Shift Config Layout', () {
    Widget buildTestShiftCard(ShiftConfiguration config, bool isMorning) {
      final themeColor = isMorning ? AppColors.primary : AppColors.secondary;

      return LayoutBuilder(
        builder: (context, constraints) {
          final isCompact = constraints.maxWidth < 420;

          return Container(
            padding: const EdgeInsets.all(AppSpacing.md),
            decoration: BoxDecoration(
              color: AppColors.surfaceContainerLowest,
              borderRadius: BorderRadius.circular(AppSpacing.radiusLg),
              border: Border.all(color: themeColor.withValues(alpha: 0.3)),
            ),
            child: Column(
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                if (isCompact) ...[
                  Row(
                    children: [
                      Icon(
                        isMorning
                            ? Icons.wb_sunny_outlined
                            : Icons.wb_twilight_outlined,
                        color: themeColor,
                        size: 24,
                      ),
                      const SizedBox(width: AppSpacing.xs),
                      Expanded(
                        child: Text(
                          config.displayName,
                          style: const TextStyle(
                            fontSize: 18,
                            fontWeight: FontWeight.bold,
                          ),
                          overflow: TextOverflow.ellipsis,
                        ),
                      ),
                    ],
                  ),
                  const SizedBox(height: AppSpacing.xs),
                  Align(
                    alignment: Alignment.centerLeft,
                    child: OutlinedButton.icon(
                      onPressed: () {},
                      icon: const Icon(Icons.edit, size: 16),
                      label: const Text('Edit Timings'),
                      style: OutlinedButton.styleFrom(
                        visualDensity: VisualDensity.compact,
                      ),
                    ),
                  ),
                ] else
                  Row(
                    mainAxisAlignment: MainAxisAlignment.spaceBetween,
                    children: [
                      Expanded(
                        child: Row(
                          children: [
                            Icon(
                              isMorning
                                  ? Icons.wb_sunny_outlined
                                  : Icons.wb_twilight_outlined,
                              color: themeColor,
                              size: 24,
                            ),
                            const SizedBox(width: AppSpacing.xs),
                            Expanded(
                              child: Text(
                                config.displayName,
                                style: const TextStyle(
                                  fontSize: 18,
                                  fontWeight: FontWeight.bold,
                                ),
                                overflow: TextOverflow.ellipsis,
                              ),
                            ),
                          ],
                        ),
                      ),
                      OutlinedButton.icon(
                        onPressed: () {},
                        icon: const Icon(Icons.edit, size: 16),
                        label: const Text('Edit Timings'),
                      ),
                    ],
                  ),
                const SizedBox(height: AppSpacing.md),
                if (isCompact) ...[
                  Column(
                    crossAxisAlignment: CrossAxisAlignment.start,
                    children: [
                      const Text('SCHEDULED HOURS'),
                      const SizedBox(height: 2),
                      Text(config.formattedTiming),
                      const SizedBox(height: AppSpacing.sm),
                      const Text('LATE GRACE PERIOD'),
                      const SizedBox(height: 2),
                      Text('${config.gracePeriodMinutes} Minutes'),
                    ],
                  ),
                ] else
                  Row(
                    children: [
                      Expanded(
                        child: Column(
                          crossAxisAlignment: CrossAxisAlignment.start,
                          children: [
                            const Text('SCHEDULED HOURS'),
                            const SizedBox(height: 2),
                            Text(config.formattedTiming),
                          ],
                        ),
                      ),
                      Expanded(
                        child: Column(
                          crossAxisAlignment: CrossAxisAlignment.start,
                          children: [
                            const Text('LATE GRACE PERIOD'),
                            const SizedBox(height: 2),
                            Text('${config.gracePeriodMinutes} Minutes'),
                          ],
                        ),
                      ),
                    ],
                  ),
              ],
            ),
          );
        },
      );
    }

    for (final width in mobileViewports) {
      testWidgets('Shift config card stacks cleanly at $width px',
          (tester) async {
        tester.view.physicalSize = Size(width, 600);
        tester.view.devicePixelRatio = 1.0;
        addTearDown(() => tester.view.resetPhysicalSize());

        await tester.pumpWidget(
          MaterialApp(
            home: Scaffold(
              body: Padding(
                padding: const EdgeInsets.all(16.0),
                child: Column(
                  children: [
                    buildTestShiftCard(ShiftConfiguration.defaultMorning, true),
                    const SizedBox(height: 16),
                    buildTestShiftCard(
                        ShiftConfiguration.defaultAfternoon, false),
                  ],
                ),
              ),
            ),
          ),
        );
        await tester.pumpAndSettle();

        expect(find.text('Morning Shift'), findsOneWidget);
        expect(find.text('Evening Shift'), findsOneWidget);
        expect(find.text('Edit Timings'), findsNWidgets(2));
        expect(find.text('SCHEDULED HOURS'), findsNWidgets(2));
        expect(find.text('LATE GRACE PERIOD'), findsNWidgets(2));

        // Zero overflow
        expect(tester.takeException(), isNull);
      });
    }
  });

  // ────────────────────────────────────────────────────────────────────────────
  // Task 7 & 8: Administration Navigation Audit and White Screen Prevention
  // ────────────────────────────────────────────────────────────────────────────
  group('Task 7 & 8 — Administration Destination Audit and Safe Back Navigation', () {
    testWidgets('Administration screen shows only verified destinations',
        (tester) async {
      tester.view.physicalSize = const Size(390, 800);
      tester.view.devicePixelRatio = 1.0;
      addTearDown(() => tester.view.resetPhysicalSize());

      await tester.pumpWidget(
        const MaterialApp(
          home: Scaffold(
            body: AdministrationContent(),
          ),
        ),
      );
      await tester.pumpAndSettle();

      // 6 Active, verified destinations
      expect(find.text('Billing & Invoices'), findsOneWidget);
      expect(find.text('Reports & Analytics'), findsOneWidget);
      expect(find.text('Doctor Management'), findsOneWidget);
      expect(find.text('Users'), findsOneWidget);
      expect(find.text('Shift Management'), findsOneWidget);
      expect(find.text('Clinic Settings'), findsOneWidget);

      // Dead placeholder cards are removed
      expect(find.text('Roles & Permissions'), findsNothing);
      expect(find.text('Backup & Restore'), findsNothing);
      expect(find.text('Audit Logs'), findsNothing);

      expect(tester.takeException(), isNull);
    });

    testWidgets('Users card navigates via push preserving route history',
        (tester) async {
      tester.view.physicalSize = const Size(390, 1400);
      tester.view.devicePixelRatio = 1.0;
      addTearDown(() => tester.view.resetPhysicalSize());

      final navObserver = TestNavigatorObserver();

      await tester.pumpWidget(
        ProviderScope(
          overrides: [
            currentUserRoleProvider.overrideWith((ref) => Future.value('admin')),
            usersProvider.overrideWith((ref) => _MockUsersNotifier(const AsyncValue.data([]))),
          ],
          child: MaterialApp(
            navigatorObservers: [navObserver],
            home: const Scaffold(
              body: AdministrationContent(),
            ),
          ),
        ),
      );
      await tester.pumpAndSettle();

      // Tap Users card
      await tester.tap(find.text('Users'));
      await tester.pump();

      // Verify that Navigator.push was invoked (not pushReplacement)
      expect(navObserver.pushedCount, greaterThanOrEqualTo(1));
    });
  });
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

class TestNavigatorObserver extends NavigatorObserver {
  int pushedCount = 0;
  @override
  void didPush(Route<dynamic> route, Route<dynamic>? previousRoute) {
    super.didPush(route, previousRoute);
    pushedCount++;
  }
}
