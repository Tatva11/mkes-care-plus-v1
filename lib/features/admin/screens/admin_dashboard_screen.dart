import 'package:flutter/material.dart';

import '../../../core/theme/app_spacing.dart';
import '../../../shared/widgets/app_footer.dart';
import '../../patients/screens/patient_list_screen.dart';
import '../../staff/screens/staff_management_screen.dart';
import 'administration_screen.dart';
import '../widgets/admin_shell.dart';
import '../widgets/copilot_insights_card.dart';
import '../widgets/inventory_alerts_card.dart';
import '../widgets/operations_tab_content.dart';
import '../widgets/revenue_growth_card.dart';
import '../widgets/staff_attendance_card.dart';

class AdminDashboardScreen extends StatefulWidget {
  const AdminDashboardScreen({super.key});

  @override
  State<AdminDashboardScreen> createState() => _AdminDashboardScreenState();
}

class _AdminDashboardScreenState extends State<AdminDashboardScreen> {
  AdminNavItem _selectedItem = AdminNavItem.dashboard;

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

        return SingleChildScrollView(
          padding: EdgeInsets.symmetric(
            horizontal: horizontalPadding,
            vertical: AppSpacing.lg,
          ),
          child: isDesktop ? _DesktopLayout() : _MobileLayout(),
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

/// Two-column grid layout for desktop (≥ 768 px).
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
            Expanded(child: InventoryAlertsCard()),
            SizedBox(width: AppSpacing.md),
            Expanded(child: CopilotInsightsCard()),
          ],
        ),
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
        StaffAttendanceCard(),
        SizedBox(height: AppSpacing.md),
        InventoryAlertsCard(),
        SizedBox(height: AppSpacing.md),
        CopilotInsightsCard(),
        SizedBox(height: AppSpacing.lg),
        AppFooter(),
      ],
    );
  }
}

/// Temporary placeholder shown for nav tabs that are not yet implemented.

