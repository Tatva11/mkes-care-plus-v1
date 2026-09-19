import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';

import '../../../core/theme/app_colors.dart';
import '../../../core/theme/app_spacing.dart';
import '../../../core/theme/app_typography.dart';
import '../../admin/widgets/admin_shell.dart';
import '../../admin/screens/administration_screen.dart';
import '../../department/screens/department_management_screen.dart';
import '../../patients/screens/patient_list_screen.dart';
import '../../admin/screens/user_form_dialog.dart';
import '../widgets/staff_attendance_summary_card.dart';
import '../widgets/staff_copilot_insights_card.dart';
import '../widgets/staff_roster_card.dart';
import '../widgets/staff_stat_card.dart';
import '../../admin/screens/admin_leave_screen.dart';
import '../../admin/screens/admin_task_screen.dart';
import '../../admin/screens/admin_performance_attendance_screens.dart';
import '../../admin/providers/users_provider.dart';

class StaffManagementScreen extends StatelessWidget {
  const StaffManagementScreen({super.key});

  @override
  Widget build(BuildContext context) {
    return AdminShell(
      selectedItem: AdminNavItem.staff,
      onNavItemSelected: (item) {
        if (item == AdminNavItem.dashboard) {
          Navigator.of(context).popUntil((route) => route.isFirst);
          return;
        }
        if (item == AdminNavItem.operations) {
          Navigator.of(context).pushReplacement(
            MaterialPageRoute(
              builder: (_) => const DepartmentManagementScreen(),
            ),
          );
          return;
        }
        if (item == AdminNavItem.patients) {
          Navigator.of(context).pushReplacement(
            MaterialPageRoute(
              builder: (_) => const PatientListScreen(),
            ),
          );
          return;
        }
        if (item == AdminNavItem.administration) {
          Navigator.of(context).pushReplacement(
            MaterialPageRoute(
              builder: (_) => const AdministrationScreen(),
            ),
          );
          return;
        }
      },
      body: const StaffManagementContent(),
    );
  }
}

class StaffManagementContent extends StatefulWidget {
  const StaffManagementContent({super.key});

  @override
  State<StaffManagementContent> createState() => _StaffManagementContentState();
}

class _StaffManagementContentState extends State<StaffManagementContent> {
  @override
  Widget build(BuildContext context) {
    final isDesktop = MediaQuery.sizeOf(context).width >= 768.0;
    final horizontalPadding =
        isDesktop ? AppSpacing.marginDesktop : AppSpacing.marginMobile;

    return SingleChildScrollView(
      padding: EdgeInsets.symmetric(
        horizontal: horizontalPadding,
        vertical: AppSpacing.lg,
      ),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          // ── Page Header ─────────────────────────────────────────────────
          _PageHeader(isDesktop: isDesktop),
          const SizedBox(height: AppSpacing.lg),

          // ── Stat tiles ──────────────────────────────────────────────────
          _StatRow(isDesktop: isDesktop),
          const SizedBox(height: AppSpacing.md),

          // ── Main content ────────────────────────────────────────────────
          isDesktop ? _DesktopLayout() : _MobileLayout(),
        ],
      ),
    );
  }
}

// ──────────────────────────────────────────────────────────────────────────────
// Page Header
// ──────────────────────────────────────────────────────────────────────────────

class _PageHeader extends StatelessWidget {
  const _PageHeader({required this.isDesktop});

  final bool isDesktop;

  @override
  Widget build(BuildContext context) {
    return Row(
      crossAxisAlignment: CrossAxisAlignment.start,
      children: [
        Expanded(
          child: Column(
            crossAxisAlignment: CrossAxisAlignment.start,
            children: [
              Text(
                'Staff Management',
                style: isDesktop
                    ? AppTypography.headlineMd.copyWith(
                        fontSize: 32,
                        fontWeight: FontWeight.w700,
                        letterSpacing: -0.01 * 32,
                      )
                    : AppTypography.headlineMd.copyWith(
                        fontSize: 24,
                        fontWeight: FontWeight.w700,
                      ),
                maxLines: 1,
                overflow: TextOverflow.ellipsis,
              ),
              const SizedBox(height: AppSpacing.base),
              Text(
                'Track attendance and manage your clinical team.',
                style: AppTypography.bodyLg,
                maxLines: 2,
                overflow: TextOverflow.ellipsis,
              ),
            ],
          ),
        ),
        const SizedBox(width: AppSpacing.sm),
        Column(
          crossAxisAlignment: CrossAxisAlignment.end,
          children: [
            Row(
              children: [
                OutlinedButton(
                  onPressed: () => Navigator.of(context).push(MaterialPageRoute(
                      builder: (_) => const AdminLeaveScreen())),
                  child: const Text('Leave'),
                ),
                const SizedBox(width: AppSpacing.sm),
                OutlinedButton(
                  onPressed: () => Navigator.of(context).push(MaterialPageRoute(
                      builder: (_) => const AdminTaskScreen())),
                  child: const Text('Tasks'),
                ),
                const SizedBox(width: AppSpacing.sm),
                OutlinedButton(
                  onPressed: () => Navigator.of(context).push(MaterialPageRoute(
                      builder: (_) => const AdminPerformanceScreen())),
                  child: const Text('Performance'),
                ),
                const SizedBox(width: AppSpacing.sm),
                _AddStaffButton(isDesktop: isDesktop),
              ],
            )
          ],
        )
      ],
    );
  }
}

class _AddStaffButton extends StatelessWidget {
  const _AddStaffButton({required this.isDesktop});

  final bool isDesktop;

  @override
  Widget build(BuildContext context) {
    return FilledButton.icon(
      onPressed: () {
        showDialog(
          context: context,
          barrierDismissible: false,
          builder: (context) => const UserFormDialog(),
        );
      },
      icon: const Icon(Icons.add, size: 20),
      label: Text(
        isDesktop ? 'Add Staff' : 'Add',
        style: AppTypography.labelCaps.copyWith(color: AppColors.onPrimary),
      ),
      style: FilledButton.styleFrom(
        backgroundColor: AppColors.primaryContainer,
        foregroundColor: AppColors.onPrimary,
        padding: EdgeInsets.symmetric(
          horizontal: isDesktop ? AppSpacing.md : AppSpacing.sm,
          vertical: AppSpacing.sm,
        ),
        shape: RoundedRectangleBorder(
          borderRadius: BorderRadius.circular(AppSpacing.radiusMd),
        ),
      ),
    );
  }
}

// ──────────────────────────────────────────────────────────────────────────────
// Stat Row
// ──────────────────────────────────────────────────────────────────────────────

class _StatRow extends ConsumerWidget {
  const _StatRow({required this.isDesktop});

  final bool isDesktop;

  static const _errorContainer = Color(0xFFFFDAD6);

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    final usersState = ref.watch(usersProvider);
    final users = (usersState.valueOrNull ?? const [])
      .where((user) => user.role == 'staff')
      .toList();
    final activeCount = users.where((user) => user.isActive).length;
    final inactiveCount = users.length - activeCount;

    return Row(
      children: [
        Expanded(
          child: StaffStatCard(
            value: usersState.isLoading ? '...' : '${users.length}',
            label: 'Total Staff',
            valueColor: AppColors.onSurface,
            icon: Icons.people_outlined,
          ),
        ),
        const SizedBox(width: AppSpacing.sm),
        Expanded(
          child: StaffStatCard(
            value: usersState.isLoading ? '...' : '$activeCount',
            label: 'Present',
            valueColor: AppColors.primary,
            icon: Icons.check_circle_outline,
          ),
        ),
        const SizedBox(width: AppSpacing.sm),
        Expanded(
          child: StaffStatCard(
            value: usersState.isLoading ? '...' : '$inactiveCount',
            label: 'Inactive',
            valueColor: AppColors.secondary,
            backgroundColor: _errorContainer.withValues(alpha: 0.2),
            borderColor: _errorContainer,
            icon: Icons.event_busy_outlined,
          ),
        ),
      ],
    );
  }
}

// ──────────────────────────────────────────────────────────────────────────────
// Layouts
// ──────────────────────────────────────────────────────────────────────────────

/// Two-column layout for desktop (≥ 768 px):
/// left column = department overview, right column = roster
class _DesktopLayout extends StatelessWidget {
  @override
  Widget build(BuildContext context) {
    return Row(
      crossAxisAlignment: CrossAxisAlignment.start,
      children: const [
        Expanded(
          flex: 5,
          child: Column(
            children: [
              StaffAttendanceSummaryCard(),
              SizedBox(height: AppSpacing.md),
              StaffCopilotInsightsCard(),
            ],
          ),
        ),
        SizedBox(width: AppSpacing.md),
        Expanded(
          flex: 7,
          child: StaffRosterCard(),
        ),
      ],
    );
  }
}

/// Single-column layout for mobile (< 768 px)
class _MobileLayout extends StatelessWidget {
  @override
  Widget build(BuildContext context) {
    return Column(
      children: const [
        StaffAttendanceSummaryCard(),
        SizedBox(height: AppSpacing.md),
        StaffCopilotInsightsCard(),
        SizedBox(height: AppSpacing.md),
        StaffRosterCard(),
      ],
    );
  }
}
