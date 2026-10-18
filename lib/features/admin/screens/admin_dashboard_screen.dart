import 'dart:async';

import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';

import '../../../core/theme/app_spacing.dart';
import '../../../core/utils/date_boundaries.dart';
import '../../../shared/widgets/app_footer.dart';
import '../../billing/providers/billing_provider.dart';
import '../../inventory/providers/inventory_provider.dart';
import '../../inventory/providers/purchase_order_provider.dart';
import '../../patients/providers/patients_provider.dart';
import '../../patients/screens/patient_list_screen.dart';
import '../../staff/providers/attendance_provider.dart';
import '../../staff/providers/leave_provider.dart';
import '../../staff/providers/task_provider.dart';
import '../../staff/screens/staff_management_screen.dart';
import '../../vendors/providers/vendor_provider.dart';
import '../providers/users_provider.dart';
import '../widgets/admin_shell.dart';
import '../widgets/copilot_insights_card.dart';
import '../widgets/inventory_alerts_card.dart';
import '../widgets/operations_tab_content.dart';
import '../widgets/patient_summary_card.dart';
import '../widgets/revenue_growth_card.dart';
import '../widgets/staff_attendance_card.dart';
import '../widgets/task_overview_card.dart';
import '../widgets/vendor_purchase_order_summary_card.dart';
import 'administration_screen.dart';

class AdminDashboardScreen extends ConsumerStatefulWidget {
  const AdminDashboardScreen({super.key});

  @override
  ConsumerState<AdminDashboardScreen> createState() =>
      _AdminDashboardScreenState();
}

class _AdminDashboardScreenState extends ConsumerState<AdminDashboardScreen>
    with WidgetsBindingObserver {
  AdminNavItem _selectedItem = AdminNavItem.dashboard;
  Timer? _midnightTimer;
  DateTime _lastObservedDate = DateTime.now();

  @override
  void initState() {
    super.initState();
    WidgetsBinding.instance.addObserver(this);
    _scheduleMidnightRollover();
  }

  @override
  void dispose() {
    WidgetsBinding.instance.removeObserver(this);
    _midnightTimer?.cancel();
    super.dispose();
  }

  @override
  void didChangeAppLifecycleState(AppLifecycleState state) {
    if (state == AppLifecycleState.resumed) {
      final now = DateTime.now();
      if (!DateBoundaries.isSameDay(_lastObservedDate, now)) {
        // Date changed while app was in background
        _lastObservedDate = now;
        _scheduleMidnightRollover();
      }
      _refreshDashboardData();
    }
  }

  void _scheduleMidnightRollover() {
    _midnightTimer?.cancel();
    final now = DateTime.now();
    final tomorrow = DateBoundaries.startOfTomorrow(now);
    // Add 1 second past midnight to guarantee local date has rolled over
    final delay = tomorrow.difference(now) + const Duration(seconds: 1);

    _midnightTimer = Timer(delay, () {
      if (mounted) {
        _lastObservedDate = DateTime.now();
        _refreshDashboardData();
        _scheduleMidnightRollover();
      }
    });
  }

  Future<void> _refreshDashboardData() async {
    final today = DateBoundaries.startOfDay();

    ref.invalidate(todayRevenueMetricsProvider);
    ref.invalidate(todayScheduledPatientsProvider);
    ref.invalidate(patientsProvider);
    ref.invalidate(adminTasksProvider);
    ref.invalidate(adminAttendanceForDateProvider(today));
    ref.invalidate(adminAttendanceSummaryProvider(today));
    ref.invalidate(adminAllLeaveRequestsProvider);
    ref.invalidate(usersProvider);
    ref.invalidate(inventoryProvider);
    ref.invalidate(purchaseOrdersProvider);
    ref.invalidate(vendorsProvider);
  }

  @override
  Widget build(BuildContext context) {
    return AdminShell(
      selectedItem: _selectedItem,
      onNavItemSelected: (item) {
        setState(() => _selectedItem = item);
      },
      body: _buildBody(),
    );
  }

  Widget _buildBody() {
    switch (_selectedItem) {
      case AdminNavItem.dashboard:
        final isDesktop = MediaQuery.sizeOf(context).width >= 768.0;
        final horizontalPadding =
            isDesktop ? AppSpacing.marginDesktop : AppSpacing.marginMobile;

        return RefreshIndicator(
          onRefresh: _refreshDashboardData,
          child: SingleChildScrollView(
            physics: const AlwaysScrollableScrollPhysics(),
            padding: EdgeInsets.symmetric(
              horizontal: horizontalPadding,
              vertical: AppSpacing.lg,
            ),
            child: isDesktop ? _DesktopLayout() : _MobileLayout(),
          ),
        );
      case AdminNavItem.staff:
        return const StaffManagementContent();
      case AdminNavItem.patients:
        return const PatientListContent();
      case AdminNavItem.operations:
        return const OperationsTabContent();
      case AdminNavItem.administration:
        return const AdministrationContent();
    }
  }
}

/// Two-column grid layout for desktop (>= 768 px).
class _DesktopLayout extends StatelessWidget {
  @override
  Widget build(BuildContext context) {
    return Column(
      children: [
        Row(
          crossAxisAlignment: CrossAxisAlignment.start,
          children: const [
            Expanded(child: RevenueGrowthCard()),
            SizedBox(width: AppSpacing.md),
            Expanded(child: StaffAttendanceCard()),
          ],
        ),
        const SizedBox(height: AppSpacing.md),
        Row(
          crossAxisAlignment: CrossAxisAlignment.start,
          children: const [
            Expanded(child: PatientSummaryCard()),
            SizedBox(width: AppSpacing.md),
            Expanded(child: InventoryAlertsCard()),
          ],
        ),
        const SizedBox(height: AppSpacing.md),
        Row(
          crossAxisAlignment: CrossAxisAlignment.start,
          children: const [
            Expanded(child: TaskOverviewCard()),
            SizedBox(width: AppSpacing.md),
            Expanded(child: VendorPurchaseOrderSummaryCard()),
          ],
        ),
        const SizedBox(height: AppSpacing.md),
        const CopilotInsightsCard(),
        const SizedBox(height: AppSpacing.lg),
        const AppFooter(),
      ],
    );
  }
}

/// Single-column stacked layout for mobile (< 768 px).
class _MobileLayout extends StatelessWidget {
  @override
  Widget build(BuildContext context) {
    return const Column(
      children: [
        RevenueGrowthCard(),
        SizedBox(height: AppSpacing.md),
        PatientSummaryCard(),
        SizedBox(height: AppSpacing.md),
        StaffAttendanceCard(),
        SizedBox(height: AppSpacing.md),
        TaskOverviewCard(),
        SizedBox(height: AppSpacing.md),
        InventoryAlertsCard(),
        SizedBox(height: AppSpacing.md),
        VendorPurchaseOrderSummaryCard(),
        SizedBox(height: AppSpacing.md),
        CopilotInsightsCard(),
        SizedBox(height: AppSpacing.lg),
        AppFooter(),
      ],
    );
  }
}
