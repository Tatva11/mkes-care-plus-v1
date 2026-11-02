import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';

import '../../billing/screens/billing_management_screen.dart';
import '../widgets/staff_shell.dart';
import 'staff_attendance_screen.dart';
import 'staff_patients_screen.dart';
import 'staff_schedule_screen.dart';
import 'staff_tasks_screen.dart';

/// Provider for staff navigation state across the portal.
final staffNavProvider =
    StateProvider<StaffNavItem>((ref) => StaffNavItem.schedule);

class StaffDashboardScreen extends ConsumerWidget {
  const StaffDashboardScreen({super.key});

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    final selectedItem = ref.watch(staffNavProvider);

    return StaffShell(
      selectedItem: selectedItem,
      onNavItemSelected: (item) {
        ref.read(staffNavProvider.notifier).state = item;
      },
      body: _buildBody(selectedItem),
    );
  }

  Widget _buildBody(StaffNavItem selectedItem) {
    switch (selectedItem) {
      case StaffNavItem.schedule:
        return const StaffScheduleScreen();
      case StaffNavItem.patients:
        return const StaffPatientsScreen();
      case StaffNavItem.tasks:
        return const StaffTasksScreen();
      case StaffNavItem.attendance:
        return const StaffAttendanceScreen();
      case StaffNavItem.billing:
        return const BillingManagementScreen(isEmbedded: true, isStaff: true);
    }
  }
}
