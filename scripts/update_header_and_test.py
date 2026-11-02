with open('lib/features/admin/widgets/revenue_growth_card.dart', 'r', encoding='utf-8') as f:
    text = f.read()

# Replace header block
import re
pattern = re.compile(r'// Header: Title.*?const SizedBox\(height: AppSpacing\.sm\),', re.DOTALL)

new_header = '''// Header: Title and View Reports
          Row(
            mainAxisAlignment: MainAxisAlignment.spaceBetween,
            children: [
              Row(
                mainAxisSize: MainAxisSize.min,
                children: [
                  const Icon(
                    Icons.trending_up,
                    color: AppColors.primaryContainer,
                    size: 22,
                  ),
                  const SizedBox(width: AppSpacing.xs),
                  Text(
                    'Revenue Growth',
                    style: AppTypography.headlineMd,
                  ),
                ],
              ),
              TextButton(
                onPressed: () {
                  ref.read(adminReportsSectionProvider.notifier).state =
                      ReportsSection.financial;
                  Navigator.of(context).push(
                    MaterialPageRoute(
                      builder: (_) => const AdminReportsScreen(),
                    ),
                  );
                },
                style: TextButton.styleFrom(
                  padding: EdgeInsets.zero,
                  minimumSize: Size.zero,
                  tapTargetSize: MaterialTapTargetSize.shrinkWrap,
                ),
                child: Row(
                  mainAxisSize: MainAxisSize.min,
                  children: [
                    Text(
                      'View Reports',
                      style: AppTypography.labelCaps.copyWith(
                        color: AppColors.primary,
                      ),
                    ),
                    const SizedBox(width: 2),
                    const Icon(
                      Icons.chevron_right,
                      size: 16,
                      color: AppColors.primary,
                    ),
                  ],
                ),
              ),
            ],
          ),
          const SizedBox(height: AppSpacing.sm),
          _buildDateSelector(context, ref, selectedDate),
          const SizedBox(height: AppSpacing.sm),'''

text = pattern.sub(new_header, text)

with open('lib/features/admin/widgets/revenue_growth_card.dart', 'w', encoding='utf-8') as f:
    f.write(text)

# Also restore test/sprint11_today_dashboard_test.dart
with open('test/sprint11_today_dashboard_test.dart', 'r', encoding='utf-8') as f:
    test_text = f.read()

# Restore original clean test without FlutterError.onError hook
test_pattern = re.compile(r'testWidgets\(\'Renders complete dashboard and handles pull-to-refresh without overflow on 360x640\'.*?\n  \}\);', re.DOTALL)

clean_test = '''testWidgets('Renders complete dashboard and handles pull-to-refresh without overflow on 360x640', (tester) async {
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
      expect(find.text('Copilot Insights'), findsNothing);

      expect(tester.takeException(), isNull);
    });'''

test_text = test_pattern.sub(clean_test, test_text)

with open('test/sprint11_today_dashboard_test.dart', 'w', encoding='utf-8') as f:
    f.write(test_text)

print('Updated revenue_growth_card.dart header and restored clean test!')

