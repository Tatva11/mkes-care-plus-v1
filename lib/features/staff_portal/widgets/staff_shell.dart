import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:supabase_flutter/supabase_flutter.dart';

import '../../../core/theme/app_colors.dart';
import '../../../core/theme/app_spacing.dart';
import '../../../core/theme/app_typography.dart';
import '../../../shared/widgets/notification_center_modal.dart';
import '../../../shared/widgets/user_profile_menu.dart';
import '../../auth/providers/auth_provider.dart';

enum StaffNavItem { schedule, patients, tasks, attendance, billing }

class StaffShell extends ConsumerWidget {
  const StaffShell({
    super.key,
    required this.body,
    this.selectedItem = StaffNavItem.schedule,
    this.onNavItemSelected,
  });

  final Widget body;
  final StaffNavItem selectedItem;
  final ValueChanged<StaffNavItem>? onNavItemSelected;

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    // Role-based access check
    final roleAsync = ref.watch(currentUserRoleProvider);

    return roleAsync.when(
      data: (role) {
        if (Supabase.instance.client.auth.currentSession == null) {
          WidgetsBinding.instance.addPostFrameCallback((_) {
            if (context.mounted && Navigator.of(context, rootNavigator: true).canPop()) {
              Navigator.of(context, rootNavigator: true).popUntil((route) => route.isFirst);
            }
          });
          return const Scaffold(
            body: Center(child: CircularProgressIndicator()),
          );
        }

        if (role != 'staff') {
          // Redirect to login if not staff
          WidgetsBinding.instance.addPostFrameCallback((_) {
            if (context.mounted && Navigator.of(context, rootNavigator: true).canPop()) {
              Navigator.of(context, rootNavigator: true).popUntil((route) => route.isFirst);
            }
            if (Supabase.instance.client.auth.currentSession == null) return;
            ScaffoldMessenger.of(context).showSnackBar(
              const SnackBar(
                content: Text('Access denied. Staff privileges required.'),
                backgroundColor: Colors.red,
              ),
            );
            Supabase.instance.client.auth.signOut();
          });
          return const Scaffold(
              body: Center(child: CircularProgressIndicator()));
        }

        final isDesktop = MediaQuery.sizeOf(context).width >= 768.0;

        return Scaffold(
          backgroundColor: AppColors.background,
          body: Column(
            children: [
              _StaffTopAppBar(
                isDesktop: isDesktop,
                selectedItem: selectedItem,
                onNavItemSelected: onNavItemSelected,
              ),
              Expanded(child: body),
            ],
          ),
          bottomNavigationBar: isDesktop
              ? null
              : _StaffBottomNavBar(
                  selectedItem: selectedItem,
                  onNavItemSelected: onNavItemSelected,
                ),
        );
      },
      loading: () =>
          const Scaffold(body: Center(child: CircularProgressIndicator())),
      error: (e, st) {
        // SECURITY: On error, do NOT allow access. Sign out and show error.
        debugPrint('Role check error in StaffShell: $e');
        WidgetsBinding.instance.addPostFrameCallback((_) {
          ScaffoldMessenger.of(context).showSnackBar(
            const SnackBar(
              content:
                  Text('Session verification failed. Please sign in again.'),
              backgroundColor: Colors.red,
            ),
          );
          Supabase.instance.client.auth.signOut();
        });
        return const Scaffold(body: Center(child: CircularProgressIndicator()));
      },
    );
  }
}

class _StaffTopAppBar extends StatelessWidget {
  const _StaffTopAppBar({
    required this.isDesktop,
    required this.selectedItem,
    this.onNavItemSelected,
  });

  final bool isDesktop;
  final StaffNavItem selectedItem;
  final ValueChanged<StaffNavItem>? onNavItemSelected;

  @override
  Widget build(BuildContext context) {
    final horizontalPadding =
        isDesktop ? AppSpacing.marginDesktop : AppSpacing.marginMobile;

    return DecoratedBox(
      decoration: const BoxDecoration(
        color: AppColors.surface,
        border: Border(
          bottom: BorderSide(color: AppColors.outlineVariant),
        ),
      ),
      child: SafeArea(
        bottom: false,
        child: SizedBox(
          height: isDesktop ? 72 : 64,
          child: Padding(
            padding: EdgeInsets.symmetric(horizontal: horizontalPadding),
            child: Row(
              children: [
                _BrandCluster(isDesktop: isDesktop),
                if (isDesktop) ...[
                  const SizedBox(width: AppSpacing.md),
                  Expanded(
                    child: SingleChildScrollView(
                      scrollDirection: Axis.horizontal,
                      child: _DesktopNavCluster(
                        selectedItem: selectedItem,
                        onNavItemSelected: onNavItemSelected,
                      ),
                    ),
                  ),
                  const SizedBox(width: AppSpacing.xs),
                ] else ...[
                  const Spacer(),
                ],
                const NotificationCenterButton(),
                const SizedBox(width: AppSpacing.xs),
                const _StaffProfileMenuConsumer(),
              ],
            ),
          ),
        ),
      ),
    );
  }
}

class _BrandCluster extends StatelessWidget {
  const _BrandCluster({required this.isDesktop});

  final bool isDesktop;

  @override
  Widget build(BuildContext context) {
    return Row(
      mainAxisSize: MainAxisSize.min,
      children: [
        Container(
          width: 32,
          height: 32,
          decoration: BoxDecoration(
            color: AppColors.primaryContainer,
            borderRadius: BorderRadius.circular(8),
          ),
          child: const Icon(
            Icons.local_hospital,
            color: AppColors.onPrimaryContainer,
            size: 20,
          ),
        ),
        const SizedBox(width: AppSpacing.sm),
        Flexible(
          child: Column(
            mainAxisAlignment: MainAxisAlignment.center,
            crossAxisAlignment: CrossAxisAlignment.start,
            children: [
              Text(
                'MKES CARE+',
                style: AppTypography.headlineMd.copyWith(
                  fontWeight: FontWeight.bold,
                ),
                overflow: TextOverflow.ellipsis,
              ),
              if (isDesktop)
                Text(
                  'Staff Portal',
                  style: AppTypography.labelCaps.copyWith(
                    color: AppColors.onSurfaceVariant,
                    fontSize: 10,
                  ),
                  overflow: TextOverflow.ellipsis,
                ),
            ],
          ),
        ),
      ],
    );
  }
}

class _DesktopNavCluster extends StatelessWidget {
  const _DesktopNavCluster({
    required this.selectedItem,
    this.onNavItemSelected,
  });

  final StaffNavItem selectedItem;
  final ValueChanged<StaffNavItem>? onNavItemSelected;

  @override
  Widget build(BuildContext context) {
    return Row(
      children: [
        _DesktopNavLink(
          label: 'Schedule',
          icon: Icons.calendar_today,
          selected: selectedItem == StaffNavItem.schedule,
          onTap: () => onNavItemSelected?.call(StaffNavItem.schedule),
        ),
        const SizedBox(width: AppSpacing.md),
        _DesktopNavLink(
          label: 'Patients',
          icon: Icons.people_outline,
          selected: selectedItem == StaffNavItem.patients,
          onTap: () => onNavItemSelected?.call(StaffNavItem.patients),
        ),
        const SizedBox(width: AppSpacing.md),
        _DesktopNavLink(
          label: 'Tasks',
          icon: Icons.task_alt_outlined,
          selected: selectedItem == StaffNavItem.tasks,
          onTap: () => onNavItemSelected?.call(StaffNavItem.tasks),
        ),
        const SizedBox(width: AppSpacing.md),
        _DesktopNavLink(
          label: 'Attendance',
          icon: Icons.access_time_outlined,
          selected: selectedItem == StaffNavItem.attendance,
          onTap: () => onNavItemSelected?.call(StaffNavItem.attendance),
        ),
        const SizedBox(width: AppSpacing.md),
        _DesktopNavLink(
          label: 'Billing',
          icon: Icons.receipt_long_outlined,
          selected: selectedItem == StaffNavItem.billing,
          onTap: () => onNavItemSelected?.call(StaffNavItem.billing),
        ),
      ],
    );
  }
}

class _DesktopNavLink extends StatelessWidget {
  const _DesktopNavLink({
    required this.label,
    required this.icon,
    required this.selected,
    required this.onTap,
  });

  final String label;
  final IconData icon;
  final bool selected;
  final VoidCallback onTap;

  @override
  Widget build(BuildContext context) {
    final color = selected ? AppColors.onSurface : AppColors.onSurfaceVariant;
    final bgColor =
        selected ? AppColors.surfaceContainerLow : Colors.transparent;

    return InkWell(
      onTap: onTap,
      borderRadius: BorderRadius.circular(AppSpacing.radiusMd),
      child: AnimatedContainer(
        duration: const Duration(milliseconds: 200),
        padding: const EdgeInsets.symmetric(
          horizontal: AppSpacing.md,
          vertical: AppSpacing.sm,
        ),
        decoration: BoxDecoration(
          color: bgColor,
          borderRadius: BorderRadius.circular(AppSpacing.radiusMd),
        ),
        child: Row(
          children: [
            Icon(icon, size: 20, color: color),
            const SizedBox(width: AppSpacing.sm),
            Text(
              label,
              style: AppTypography.labelCaps.copyWith(
                color: color,
                fontWeight: selected ? FontWeight.w600 : FontWeight.w500,
              ),
            ),
          ],
        ),
      ),
    );
  }
}

class _StaffBottomNavBar extends StatelessWidget {
  const _StaffBottomNavBar({
    required this.selectedItem,
    this.onNavItemSelected,
  });

  final StaffNavItem selectedItem;
  final ValueChanged<StaffNavItem>? onNavItemSelected;

  @override
  Widget build(BuildContext context) {
    return DecoratedBox(
      decoration: const BoxDecoration(
        color: AppColors.surface,
        border: Border(
          top: BorderSide(color: AppColors.outlineVariant),
        ),
      ),
      child: SafeArea(
        top: false,
        child: SizedBox(
          height: 64,
          child: Row(
            mainAxisAlignment: MainAxisAlignment.spaceAround,
            children: [
              _BottomNavItem(
                label: 'Schedule',
                icon: Icons.calendar_today,
                selected: selectedItem == StaffNavItem.schedule,
                onTap: () => onNavItemSelected?.call(StaffNavItem.schedule),
              ),
              _BottomNavItem(
                label: 'Patients',
                icon: Icons.people_outline,
                selected: selectedItem == StaffNavItem.patients,
                onTap: () => onNavItemSelected?.call(StaffNavItem.patients),
              ),
              _BottomNavItem(
                label: 'Tasks',
                icon: Icons.task_alt_outlined,
                selected: selectedItem == StaffNavItem.tasks,
                onTap: () => onNavItemSelected?.call(StaffNavItem.tasks),
              ),
              _BottomNavItem(
                label: 'Attendance',
                icon: Icons.access_time_outlined,
                selected: selectedItem == StaffNavItem.attendance,
                onTap: () => onNavItemSelected?.call(StaffNavItem.attendance),
              ),
              _BottomNavItem(
                label: 'Billing',
                icon: Icons.receipt_long_outlined,
                selected: selectedItem == StaffNavItem.billing,
                onTap: () => onNavItemSelected?.call(StaffNavItem.billing),
              ),
            ],
          ),
        ),
      ),
    );
  }
}

class _BottomNavItem extends StatelessWidget {
  const _BottomNavItem({
    required this.label,
    required this.icon,
    required this.selected,
    required this.onTap,
  });

  final String label;
  final IconData icon;
  final bool selected;
  final VoidCallback onTap;

  @override
  Widget build(BuildContext context) {
    final isActive = selected;
    final foreground =
        isActive ? AppColors.onPrimaryContainer : AppColors.onSurfaceVariant;

    return InkWell(
      onTap: onTap,
      borderRadius: BorderRadius.circular(999),
      child: AnimatedContainer(
        duration: const Duration(milliseconds: 200),
        padding: const EdgeInsets.symmetric(
          horizontal: AppSpacing.sm,
          vertical: AppSpacing.base,
        ),
        decoration: isActive
            ? BoxDecoration(
                color: AppColors.primaryContainer,
                borderRadius: BorderRadius.circular(999),
              )
            : null,
        child: Column(
          mainAxisSize: MainAxisSize.min,
          children: [
            Icon(icon, size: 22, color: foreground),
            const SizedBox(height: AppSpacing.base),
            Text(
              label,
              style: AppTypography.labelCaps.copyWith(
                color: foreground,
                fontSize: 11,
              ),
            ),
          ],
        ),
      ),
    );
  }
}

/// Reads the current staff user's profile from Supabase and passes it to [UserProfileMenu].
/// Falls back to safe defaults while loading or on error.
class _StaffProfileMenuConsumer extends ConsumerWidget {
  const _StaffProfileMenuConsumer();

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    final profileAsync = ref.watch(currentProfileProvider);

    return profileAsync.when(
      data: (profile) => UserProfileMenu(
        name: profile?.fullName ?? 'Staff Member',
        role: profile?.designation ?? profile?.roleDisplayName ?? 'Staff',
        initials: profile?.initials ?? 'S',
      ),
      loading: () => const UserProfileMenu(
        name: 'Loading...',
        role: 'Staff Member',
        initials: '...',
      ),
      error: (_, __) => const UserProfileMenu(
        name: 'Staff Member',
        role: 'Staff Member',
        initials: 'S',
      ),
    );
  }
}
