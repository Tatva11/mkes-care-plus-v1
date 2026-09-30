import 'package:flutter/material.dart';

import '../../core/theme/app_colors.dart';
import '../../core/theme/app_spacing.dart';
import '../../core/theme/app_typography.dart';
import 'package:supabase_flutter/supabase_flutter.dart';

import '../../features/profile/screens/my_profile_screen.dart';
import '../../features/settings/screens/settings_screen.dart';

class UserProfileMenu extends StatelessWidget {
  const UserProfileMenu({
    super.key,
    this.name = 'Dr. Alex Morgan',
    this.role = 'Clinic Administrator',
    this.initials = 'AM',
  });

  final String name;
  final String role;
  final String initials;

  @override
  Widget build(BuildContext context) {
    return PopupMenuButton<String>(
      offset: const Offset(0, 48),
      shape: RoundedRectangleBorder(
        borderRadius: BorderRadius.circular(AppSpacing.radiusLg),
        side: const BorderSide(color: AppColors.outlineVariant),
      ),
      color: AppColors.surfaceContainerLowest,
      elevation: 8,
      child: Container(
        padding: const EdgeInsets.all(2),
        decoration: BoxDecoration(
          shape: BoxShape.circle,
          border: Border.all(color: AppColors.outlineVariant, width: 1.5),
        ),
        child: CircleAvatar(
          radius: 18,
          backgroundColor: AppColors.primaryContainer.withValues(alpha: 0.2),
          child: Text(
            initials,
            style: AppTypography.labelCaps.copyWith(
              color: AppColors.primary,
              fontWeight: FontWeight.w700,
            ),
          ),
        ),
      ),
      onSelected: (value) async {
        if (value == 'logout') {
          debugPrint('[LOGOUT] menu callback entered');
          try {
            debugPrint('[LOGOUT] starting Supabase signOut');
            await Supabase.instance.client.auth.signOut();
            debugPrint(
              '[LOGOUT] signOut completed; sessionPresent='
              '${Supabase.instance.client.auth.currentSession != null}',
            );
            debugPrint(
              '[LOGOUT] waiting for the root AuthWrapper auth-state route',
            );
          } catch (error, stackTrace) {
            debugPrint('[LOGOUT] signOut failed: $error\n$stackTrace');
            if (context.mounted) {
              ScaffoldMessenger.of(context).showSnackBar(
                SnackBar(content: Text('Could not log out: $error')),
              );
            }
          }
        } else if (value == 'My Profile') {
          Navigator.of(context).push(
            MaterialPageRoute(
              builder: (_) => UserProfileMenu._buildProfileScreenForRole(name, role, initials),
            ),
          );
        } else if (value == 'Settings') {
          Navigator.of(context).push(
            MaterialPageRoute(
              builder: (_) => const SettingsScreen(),
            ),
          );
        }
      },
      itemBuilder: (context) => [
        PopupMenuItem<String>(
          enabled: false,
          child: Padding(
            padding: const EdgeInsets.symmetric(vertical: AppSpacing.xs),
            child: Row(
              children: [
                CircleAvatar(
                  radius: 20,
                  backgroundColor: AppColors.primary,
                  child: Text(
                    initials,
                    style: AppTypography.bodyLg.copyWith(
                      color: AppColors.onPrimary,
                      fontWeight: FontWeight.bold,
                    ),
                  ),
                ),
                const SizedBox(width: AppSpacing.sm),
                Expanded(
                  child: Column(
                    crossAxisAlignment: CrossAxisAlignment.start,
                    mainAxisSize: MainAxisSize.min,
                    children: [
                      Text(
                        name,
                        style: AppTypography.bodyMd.copyWith(
                          fontWeight: FontWeight.bold,
                          color: AppColors.onSurface,
                        ),
                        overflow: TextOverflow.ellipsis,
                      ),
                      Text(
                        role,
                        style: AppTypography.bodySm.copyWith(
                          color: AppColors.onSurfaceVariant,
                          fontSize: 12,
                        ),
                        overflow: TextOverflow.ellipsis,
                      ),
                    ],
                  ),
                ),
              ],
            ),
          ),
        ),
        const PopupMenuDivider(),
        PopupMenuItem<String>(
          value: 'My Profile',
          child: Row(
            children: [
              const Icon(Icons.person_outline, size: 20, color: AppColors.onSurfaceVariant),
              const SizedBox(width: AppSpacing.sm),
              Text('My Profile', style: AppTypography.bodyMd),
            ],
          ),
        ),
        PopupMenuItem<String>(
          value: 'Settings',
          child: Row(
            children: [
              const Icon(Icons.settings_outlined, size: 20, color: AppColors.onSurfaceVariant),
              const SizedBox(width: AppSpacing.sm),
              Text('Settings', style: AppTypography.bodyMd),
            ],
          ),
        ),
        const PopupMenuDivider(),
        PopupMenuItem<String>(
          value: 'logout',
          child: Row(
            children: [
              const Icon(Icons.logout, size: 20, color: AppColors.error),
              const SizedBox(width: AppSpacing.sm),
              Text(
                'Logout',
                style: AppTypography.bodyMd.copyWith(
                  color: AppColors.error,
                  fontWeight: FontWeight.w600,
                ),
              ),
            ],
          ),
        ),
      ],
    );
  }

  static Widget _buildProfileScreenForRole(String name, String role, String initials) {
    return MyProfileScreen(name: name, role: role, initials: initials);
  }
}
