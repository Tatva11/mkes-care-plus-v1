import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:supabase_flutter/supabase_flutter.dart';

import '../../../core/theme/app_colors.dart';
import '../../../core/theme/app_spacing.dart';
import '../../../core/theme/app_typography.dart';
import '../../../shared/widgets/global_search_modal.dart';
import '../../../shared/widgets/notification_center_modal.dart';
import '../../../shared/widgets/user_profile_menu.dart';
import '../../auth/providers/auth_provider.dart';
import '../../whatsapp/widgets/whatsapp_inbox_button.dart';

enum AdminNavItem { dashboard, staff, patients, operations, administration }

class AdminShell extends ConsumerWidget {
  const AdminShell({
    super.key,
    required this.body,
    this.selectedItem = AdminNavItem.dashboard,
    this.onNavItemSelected,
  });

  final Widget body;
  final AdminNavItem selectedItem;
  final ValueChanged<AdminNavItem>? onNavItemSelected;

  static const _desktopBreakpoint = 768.0;

  static bool _hasSupabaseSession() {
    try {
      return Supabase.instance.client.auth.currentSession != null;
    } catch (_) {
      // In test or non-initialized environments, fallback to true
      return true;
    }
  }

  static void _safeSupabaseSignOut() {
    try {
      Supabase.instance.client.auth.signOut();
    } catch (_) {}
  }

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    // Role-based access check
    final roleAsync = ref.watch(currentUserRoleProvider);
    final hasSession = _hasSupabaseSession();
    debugPrint(
      '[LOGOUT] AdminShell built; roleState='
      '${roleAsync.hasError ? 'error' : roleAsync.isLoading ? 'loading' : 'data'}; '
      'sessionPresent=$hasSession',
    );

    return roleAsync.when(
      data: (role) {
        if (!hasSession) {
          debugPrint(
              '[LOGOUT] AdminShell session is cleared; ensuring pushed routes popped');
          WidgetsBinding.instance.addPostFrameCallback((_) {
            if (context.mounted &&
                Navigator.of(context, rootNavigator: true).canPop()) {
              Navigator.of(context, rootNavigator: true)
                  .popUntil((route) => route.isFirst);
            }
          });
          return const Scaffold(
            body: Center(child: CircularProgressIndicator()),
          );
        }

        if (role != 'admin') {
          debugPrint(
            '[LOGOUT] AdminShell rejecting active session with role=$role',
          );
          // Redirect to login if not admin
          WidgetsBinding.instance.addPostFrameCallback((_) {
            if (context.mounted &&
                Navigator.of(context, rootNavigator: true).canPop()) {
              Navigator.of(context, rootNavigator: true)
                  .popUntil((route) => route.isFirst);
            }
            if (!_hasSupabaseSession()) return;
            ScaffoldMessenger.of(context).showSnackBar(
              const SnackBar(
                content: Text('Access denied. Admin privileges required.'),
                backgroundColor: Colors.red,
              ),
            );
            _safeSupabaseSignOut();
          });
          return const Scaffold(
              body: Center(child: CircularProgressIndicator()));
        }

        final isDesktop =
            MediaQuery.sizeOf(context).width >= _desktopBreakpoint;

        return Scaffold(
          backgroundColor: AppColors.surfaceContainerLowest,
          body: Column(
            children: [
              _AdminTopAppBar(
                isDesktop: isDesktop,
                selectedItem: selectedItem,
                onNavItemSelected: onNavItemSelected,
              ),
              Expanded(child: body),
            ],
          ),
          bottomNavigationBar: isDesktop
              ? null
              : _AdminBottomNavBar(
                  selectedItem: selectedItem,
                  onNavItemSelected: onNavItemSelected,
                ),
        );
      },
      loading: () =>
          const Scaffold(body: Center(child: CircularProgressIndicator())),
      error: (e, st) {
        // SECURITY: On error, do NOT allow access. Sign out and show error.
        debugPrint('Role check error in AdminShell: $e');
        WidgetsBinding.instance.addPostFrameCallback((_) {
          if (!_hasSupabaseSession()) return;
          ScaffoldMessenger.of(context).showSnackBar(
            const SnackBar(
              content:
                  Text('Session verification failed. Please sign in again.'),
              backgroundColor: Colors.red,
            ),
          );
          _safeSupabaseSignOut();
        });
        return const Scaffold(body: Center(child: CircularProgressIndicator()));
      },
    );
  }
}

class _AdminTopAppBar extends StatelessWidget {
  const _AdminTopAppBar({
    required this.isDesktop,
    required this.selectedItem,
    this.onNavItemSelected,
  });

  final bool isDesktop;
  final AdminNavItem selectedItem;
  final ValueChanged<AdminNavItem>? onNavItemSelected;

  @override
  Widget build(BuildContext context) {
    final horizontalPadding =
        isDesktop ? AppSpacing.marginDesktop : AppSpacing.marginMobile;

    return Material(
      color: AppColors.surface,
      elevation: 0,
      shadowColor: Colors.black26,
      child: DecoratedBox(
        decoration: const BoxDecoration(
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
                  if (Navigator.of(context).canPop()) ...[
                    IconButton(
                      icon: const Icon(Icons.arrow_back),
                      tooltip: 'Back',
                      onPressed: () => Navigator.of(context).maybePop(),
                    ),
                    const SizedBox(width: AppSpacing.xs),
                  ],
                  if (isDesktop) ...[
                    _BrandCluster(isDesktop: isDesktop),
                    const SizedBox(width: AppSpacing.sm),
                    const SizedBox(
                      width: 180,
                      child: _GlobalSearchBar(),
                    ),
                    const SizedBox(width: AppSpacing.sm),
                    Expanded(
                      child: _DesktopNavCluster(
                        selectedItem: selectedItem,
                        onNavItemSelected: onNavItemSelected,
                      ),
                    ),
                    const SizedBox(width: AppSpacing.xs),
                  ] else ...[
                    Expanded(
                      child: _BrandCluster(isDesktop: isDesktop),
                    ),
                    IconButton(
                      icon: const Icon(Icons.search),
                      color: AppColors.onSurfaceVariant,
                      onPressed: () {
                        showGlobalSearchModal(context);
                      },
                    ),
                  ],
                  const WhatsAppInboxButton(),
                  const SizedBox(width: AppSpacing.xs),
                  const NotificationCenterButton(),
                  const SizedBox(width: AppSpacing.xs),
                  const _ProfileMenuConsumer(),
                ],
              ),
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
    final avatarSize = isDesktop ? 40.0 : 32.0;
    final iconSize = isDesktop ? 24.0 : 20.0;

    return Row(
      mainAxisSize: isDesktop ? MainAxisSize.min : MainAxisSize.max,
      children: [
        Container(
          width: avatarSize,
          height: avatarSize,
          decoration: BoxDecoration(
            color: const Color(0xFFE5E2E1),
            shape: BoxShape.circle,
            border: Border.all(color: AppColors.outlineVariant),
          ),
          child: Icon(
            Icons.person,
            size: iconSize,
            color: AppColors.onSurfaceVariant,
          ),
        ),
        const SizedBox(width: AppSpacing.sm),
        if (isDesktop)
          Text(
            'MKES CARE+',
            style: AppTypography.headlineMd.copyWith(
              fontWeight: FontWeight.w700,
              color: AppColors.primary,
            ),
          )
        else
          Expanded(
            child: Text(
              'MKES CARE+',
              style: AppTypography.headlineMd.copyWith(
                fontSize: 18,
                fontWeight: FontWeight.w700,
                color: AppColors.primary,
              ),
              overflow: TextOverflow.ellipsis,
              maxLines: 1,
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

  final AdminNavItem selectedItem;
  final ValueChanged<AdminNavItem>? onNavItemSelected;

  @override
  Widget build(BuildContext context) {
    return SingleChildScrollView(
      scrollDirection: Axis.horizontal,
      child: Row(
        mainAxisSize: MainAxisSize.min,
        children: [
          _DesktopNavLink(
            label: 'Dashboard',
            icon: Icons.dashboard,
            selected: selectedItem == AdminNavItem.dashboard,
            onTap: () => onNavItemSelected?.call(AdminNavItem.dashboard),
          ),
          const SizedBox(width: AppSpacing.xs),
          _DesktopNavLink(
            label: 'Staff',
            icon: Icons.badge_outlined,
            selected: selectedItem == AdminNavItem.staff,
            onTap: () => onNavItemSelected?.call(AdminNavItem.staff),
          ),
          const SizedBox(width: AppSpacing.xs),
          _DesktopNavLink(
            label: 'Patients',
            icon: Icons.people_outline,
            selected: selectedItem == AdminNavItem.patients,
            onTap: () => onNavItemSelected?.call(AdminNavItem.patients),
          ),
          const SizedBox(width: AppSpacing.xs),
          _DesktopNavLink(
            label: 'Operations',
            icon: Icons.inventory_2_outlined,
            selected: selectedItem == AdminNavItem.operations,
            onTap: () => onNavItemSelected?.call(AdminNavItem.operations),
          ),
          const SizedBox(width: AppSpacing.xs),
          _DesktopNavLink(
            label: 'Administration',
            icon: Icons.admin_panel_settings_outlined,
            selected: selectedItem == AdminNavItem.administration,
            onTap: () => onNavItemSelected?.call(AdminNavItem.administration),
          ),
        ],
      ),
    );
  }
}

class _DesktopNavLink extends StatelessWidget {
  const _DesktopNavLink({
    required this.label,
    required this.icon,
    required this.onTap,
    this.selected = false,
  });

  final String label;
  final IconData icon;
  final VoidCallback onTap;
  final bool selected;

  @override
  Widget build(BuildContext context) {
    final foreground =
        selected ? AppColors.primary : AppColors.onSurfaceVariant;

    return Material(
      color: selected ? AppColors.surfaceContainerLow : Colors.transparent,
      borderRadius: BorderRadius.circular(AppSpacing.radiusMd),
      child: InkWell(
        onTap: onTap,
        borderRadius: BorderRadius.circular(AppSpacing.radiusMd),
        child: Padding(
          padding: const EdgeInsets.symmetric(
            horizontal: AppSpacing.sm,
            vertical: AppSpacing.xs,
          ),
          child: Row(
            children: [
              Icon(
                icon,
                size: 20,
                color: foreground,
              ),
              const SizedBox(width: AppSpacing.xs),
              Text(
                label,
                style: AppTypography.labelCaps.copyWith(color: foreground),
              ),
            ],
          ),
        ),
      ),
    );
  }
}

class _AdminBottomNavBar extends StatelessWidget {
  const _AdminBottomNavBar({
    required this.selectedItem,
    this.onNavItemSelected,
  });

  final AdminNavItem selectedItem;
  final ValueChanged<AdminNavItem>? onNavItemSelected;

  @override
  Widget build(BuildContext context) {
    return DecoratedBox(
      decoration: const BoxDecoration(
        color: AppColors.surfaceContainerLow,
        border: Border(
          top: BorderSide(color: AppColors.outlineVariant),
        ),
        boxShadow: [
          BoxShadow(
            color: Color(0x1A000000),
            blurRadius: 12,
            offset: Offset(0, -2),
          ),
        ],
      ),
      child: SafeArea(
        top: false,
        child: SizedBox(
          height: 72,
          child: Row(
            children: [
              Expanded(
                child: _BottomNavItem(
                  label: 'Dashboard',
                  icon: Icons.dashboard,
                  selected: selectedItem == AdminNavItem.dashboard,
                  onTap: () => onNavItemSelected?.call(AdminNavItem.dashboard),
                ),
              ),
              Expanded(
                child: _BottomNavItem(
                  label: 'Staff',
                  icon: Icons.badge_outlined,
                  selected: selectedItem == AdminNavItem.staff,
                  onTap: () => onNavItemSelected?.call(AdminNavItem.staff),
                ),
              ),
              Expanded(
                child: _BottomNavItem(
                  label: 'Patients',
                  icon: Icons.people_outline,
                  selected: selectedItem == AdminNavItem.patients,
                  onTap: () => onNavItemSelected?.call(AdminNavItem.patients),
                ),
              ),
              Expanded(
                child: _BottomNavItem(
                  label: 'Operations',
                  icon: Icons.inventory_2_outlined,
                  selected: selectedItem == AdminNavItem.operations,
                  onTap: () => onNavItemSelected?.call(AdminNavItem.operations),
                ),
              ),
              Expanded(
                child: _BottomNavItem(
                  label: 'Admin',
                  icon: Icons.admin_panel_settings_outlined,
                  selected: selectedItem == AdminNavItem.administration,
                  onTap: () =>
                      onNavItemSelected?.call(AdminNavItem.administration),
                ),
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
    required this.onTap,
    this.selected = false,
  });

  final String label;
  final IconData icon;
  final VoidCallback onTap;
  final bool selected;

  @override
  Widget build(BuildContext context) {
    final isActive = selected;
    final foreground =
        isActive ? AppColors.onPrimaryContainer : AppColors.onSurfaceVariant;

    return InkWell(
      onTap: onTap,
      borderRadius: BorderRadius.circular(AppSpacing.radiusMd),
      child: AnimatedContainer(
        duration: const Duration(milliseconds: 200),
        padding: const EdgeInsets.symmetric(
          horizontal: AppSpacing.xs,
          vertical: AppSpacing.xs,
        ),
        decoration: isActive
            ? BoxDecoration(
                color: AppColors.primaryContainer,
                borderRadius: BorderRadius.circular(AppSpacing.radiusMd),
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
              overflow: TextOverflow.ellipsis,
              maxLines: 1,
            ),
          ],
        ),
      ),
    );
  }
}

class _GlobalSearchBar extends StatelessWidget {
  const _GlobalSearchBar();

  @override
  Widget build(BuildContext context) {
    return Container(
      height: 40,
      decoration: BoxDecoration(
        color: AppColors.surfaceContainerLow,
        borderRadius: BorderRadius.circular(999),
        border: Border.all(color: AppColors.outlineVariant),
      ),
      child: Material(
        color: Colors.transparent,
        child: InkWell(
          borderRadius: BorderRadius.circular(999),
          onTap: () {
            showGlobalSearchModal(context);
          },
          child: Padding(
            padding: const EdgeInsets.symmetric(horizontal: AppSpacing.sm),
            child: Row(
              children: [
                const Icon(
                  Icons.search,
                  size: 20,
                  color: AppColors.outline,
                ),
                const SizedBox(width: AppSpacing.xs),
                Expanded(
                  child: Text(
                    'Search patients, staff, inventory...',
                    style: AppTypography.bodyMd.copyWith(
                      color: AppColors.outline,
                    ),
                    overflow: TextOverflow.ellipsis,
                  ),
                ),
                const SizedBox(width: AppSpacing.xs),
                Container(
                  padding:
                      const EdgeInsets.symmetric(horizontal: 6, vertical: 2),
                  decoration: BoxDecoration(
                    color: AppColors.surface,
                    borderRadius: BorderRadius.circular(4),
                    border: Border.all(color: AppColors.outlineVariant),
                  ),
                  child: Text(
                    'Ctrl K',
                    style: AppTypography.labelCaps.copyWith(
                      color: AppColors.onSurfaceVariant,
                      fontSize: 10,
                    ),
                  ),
                ),
              ],
            ),
          ),
        ),
      ),
    );
  }
}

/// Reads the current user's profile from Supabase and passes it to [UserProfileMenu].
/// Falls back to safe defaults while loading or on error.
class _ProfileMenuConsumer extends ConsumerWidget {
  const _ProfileMenuConsumer();

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    final profileAsync = ref.watch(currentProfileProvider);

    return profileAsync.when(
      data: (profile) => UserProfileMenu(
        name: profile?.fullName ?? 'Administrator',
        role:
            profile?.designation ?? profile?.roleDisplayName ?? 'Administrator',
        initials: profile?.initials ?? 'A',
      ),
      loading: () => const UserProfileMenu(
        name: 'Loading...',
        role: 'Administrator',
        initials: '...',
      ),
      error: (_, __) => const UserProfileMenu(
        name: 'Administrator',
        role: 'Administrator',
        initials: 'A',
      ),
    );
  }
}
