import 'package:flutter/material.dart';
import '../widgets/staff_shell.dart';
import 'staff_attendance_screen.dart';
import 'staff_patients_screen.dart';
import 'staff_schedule_screen.dart';
import 'staff_tasks_screen.dart';

class StaffDashboardScreen extends StatefulWidget {
  const StaffDashboardScreen({super.key});

  @override
  State<StaffDashboardScreen> createState() => _StaffDashboardScreenState();
}

class _StaffDashboardScreenState extends State<StaffDashboardScreen> {
  StaffNavItem _selectedItem = StaffNavItem.schedule;

  @override
  Widget build(BuildContext context) {
    return StaffShell(
      selectedItem: _selectedItem,
      onNavItemSelected: (item) {
        setState(() => _selectedItem = item);
      },
      body: _buildBody(),
    );
  }

  Widget _buildBody() {
    switch (_selectedItem) {
      case StaffNavItem.schedule:
        return const StaffScheduleScreen();
      case StaffNavItem.patients:
        return const StaffPatientsScreen();
      case StaffNavItem.tasks:
        return const StaffTasksScreen();
      case StaffNavItem.attendance:
        return const StaffAttendanceScreen();
    }
  }
}
