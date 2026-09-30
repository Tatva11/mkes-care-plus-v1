import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';

import '../../../core/theme/app_colors.dart';
import '../../../core/theme/app_spacing.dart';
import '../../../core/theme/app_typography.dart';
import '../../auth/providers/auth_provider.dart';

/// Displays the currently logged-in user's own profile, sourced from Supabase.
/// Uses [currentProfileProvider] for real data instead of hardcoded values.
class MyProfileScreen extends ConsumerWidget {
  const MyProfileScreen({
    super.key,
    // These optional overrides are kept for backward compatibility
    // with calls from UserProfileMenu, but real data takes precedence.
    this.name,
    this.role,
    this.initials,
  });

  final String? name;
  final String? role;
  final String? initials;

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    final profileAsync = ref.watch(currentProfileProvider);

    return profileAsync.when(
      data: (profile) {
        final displayName = profile?.fullName ?? name ?? 'User';
        final displayRole =
            profile?.designation ?? profile?.roleDisplayName ?? role ?? 'Staff';
        final displayInitials = profile?.initials ?? initials ?? '?';
        final displayEmail = profile?.email ?? '—';
        final displayPhone = profile?.phoneNumber ?? '—';
        final displayDepartment =
            profile?.departmentName ?? profile?.department ?? '—';
        final displayDesignation = profile?.designation ?? '—';

        final content = _buildContent(
          context,
          displayName: displayName,
          displayRole: displayRole,
          displayInitials: displayInitials,
          displayEmail: displayEmail,
          displayPhone: displayPhone,
          displayDepartment: displayDepartment,
          displayDesignation: displayDesignation,
        );
        return Scaffold(body: content);
      },
      loading: () => const Scaffold(
        body: Center(child: CircularProgressIndicator()),
      ),
      error: (e, st) => Scaffold(
        body: Center(
          child: Padding(
            padding: const EdgeInsets.all(AppSpacing.lg),
            child: Column(
              mainAxisSize: MainAxisSize.min,
              children: [
                const Icon(Icons.error_outline,
                    size: 48, color: AppColors.error),
                const SizedBox(height: AppSpacing.md),
                Text(
                  'Could not load profile.',
                  style: AppTypography.headlineMd,
                ),
                const SizedBox(height: AppSpacing.xs),
                Text(
                  'Please check your connection and try again.',
                  style: AppTypography.bodySm.copyWith(
                    color: AppColors.onSurfaceVariant,
                  ),
                ),
              ],
            ),
          ),
        ),
      ),
    );
  }

  Widget _buildContent(
    BuildContext context, {
    required String displayName,
    required String displayRole,
    required String displayInitials,
    required String displayEmail,
    required String displayPhone,
    required String displayDepartment,
    required String displayDesignation,
  }) {
    return LayoutBuilder(
      builder: (context, constraints) {
        final isDesktop = constraints.maxWidth >= 768.0;

        return SingleChildScrollView(
          padding: EdgeInsets.all(
            isDesktop ? AppSpacing.marginDesktop : AppSpacing.marginMobile,
          ),
          child: Column(
            crossAxisAlignment: CrossAxisAlignment.start,
            children: [
              // Header Bar
              Row(
                children: [
                  IconButton(
                    icon: const Icon(Icons.arrow_back),
                    onPressed: () => Navigator.of(context).pop(),
                  ),
                  const SizedBox(width: AppSpacing.xs),
                  Expanded(
                    child: Text(
                      'My Profile',
                      style: AppTypography.displayLg.copyWith(
                        color: AppColors.onBackground,
                      ),
                    ),
                  ),
                ],
              ),

              const SizedBox(height: AppSpacing.lg),

              // Hero Profile Card
              Container(
                padding: const EdgeInsets.all(AppSpacing.lg),
                decoration: BoxDecoration(
                  color: AppColors.surfaceContainerLowest,
                  borderRadius: BorderRadius.circular(AppSpacing.radiusXl),
                  border: Border.all(color: AppColors.outlineVariant),
                  boxShadow: const [
                    BoxShadow(
                      color: Color(0x0A000000),
                      blurRadius: 12,
                      offset: Offset(0, 2),
                    ),
                  ],
                ),
                child: Row(
                  children: [
                    CircleAvatar(
                      radius: 36,
                      backgroundColor: AppColors.primary,
                      child: Text(
                        displayInitials,
                        style: AppTypography.displayLg.copyWith(
                          color: AppColors.onPrimary,
                          fontSize: 28,
                        ),
                      ),
                    ),
                    const SizedBox(width: AppSpacing.md),
                    Expanded(
                      child: Column(
                        crossAxisAlignment: CrossAxisAlignment.start,
                        children: [
                          Text(
                            displayName,
                            style: AppTypography.headlineMd.copyWith(
                              fontSize: 22,
                              fontWeight: FontWeight.bold,
                            ),
                          ),
                          const SizedBox(height: 4),
                          Text(
                            displayRole,
                            style: AppTypography.bodyMd.copyWith(
                              color: AppColors.onSurfaceVariant,
                            ),
                          ),
                          const SizedBox(height: 8),
                          Container(
                            padding: const EdgeInsets.symmetric(
                              horizontal: 8,
                              vertical: 3,
                            ),
                            decoration: BoxDecoration(
                              color: AppColors.primaryContainer
                                  .withValues(alpha: 0.2),
                              borderRadius: BorderRadius.circular(4),
                            ),
                            child: Text(
                              displayDepartment != '—'
                                  ? 'Dept: $displayDepartment'
                                  : 'MKES CARE+ Platform',
                              style: AppTypography.dataMono.copyWith(
                                color: AppColors.primaryContainer,
                                fontSize: 11,
                                fontWeight: FontWeight.bold,
                              ),
                            ),
                          ),
                        ],
                      ),
                    ),
                  ],
                ),
              ),

              const SizedBox(height: AppSpacing.lg),

              // Details Grid
              if (isDesktop)
                Row(
                  crossAxisAlignment: CrossAxisAlignment.start,
                  children: [
                    Expanded(
                      child: _buildSectionCard(
                        'Personal Information',
                        Icons.person_outline,
                        [
                          _detailRow('Full Name', displayName),
                          _detailRow('Email Address', displayEmail),
                          _detailRow('Phone Number', displayPhone),
                        ],
                      ),
                    ),
                    const SizedBox(width: AppSpacing.md),
                    Expanded(
                      child: _buildSectionCard(
                        'Professional Details',
                        Icons.workspace_premium_outlined,
                        [
                          _detailRow('Department', displayDepartment),
                          _detailRow('Designation', displayDesignation),
                          _detailRow('Role', displayRole),
                        ],
                      ),
                    ),
                  ],
                )
              else
                Column(
                  children: [
                    _buildSectionCard(
                      'Personal Information',
                      Icons.person_outline,
                      [
                        _detailRow('Full Name', displayName),
                        _detailRow('Email Address', displayEmail),
                        _detailRow('Phone Number', displayPhone),
                      ],
                    ),
                    const SizedBox(height: AppSpacing.md),
                    _buildSectionCard(
                      'Professional Details',
                      Icons.workspace_premium_outlined,
                      [
                        _detailRow('Department', displayDepartment),
                        _detailRow('Designation', displayDesignation),
                        _detailRow('Role', displayRole),
                      ],
                    ),
                  ],
                ),
            ],
          ),
        );
      },
    );
  }

  Widget _buildSectionCard(String title, IconData icon, List<Widget> children) {
    return Container(
      padding: const EdgeInsets.all(AppSpacing.md),
      decoration: BoxDecoration(
        color: AppColors.surfaceContainerLowest,
        borderRadius: BorderRadius.circular(AppSpacing.radiusLg),
        border: Border.all(color: AppColors.outlineVariant),
      ),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Row(
            children: [
              Icon(icon, color: AppColors.primary, size: 20),
              const SizedBox(width: AppSpacing.xs),
              Text(title, style: AppTypography.headlineMd),
            ],
          ),
          const SizedBox(height: AppSpacing.sm),
          const Divider(height: 1),
          const SizedBox(height: AppSpacing.sm),
          ...children,
        ],
      ),
    );
  }

  Widget _detailRow(String label, String value) {
    return Padding(
      padding: const EdgeInsets.symmetric(vertical: AppSpacing.xs),
      child: Row(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Expanded(
            flex: 4,
            child: Text(
              label,
              style: AppTypography.labelCaps.copyWith(
                color: AppColors.onSurfaceVariant,
              ),
            ),
          ),
          Expanded(
            flex: 6,
            child: Text(
              value,
              style: AppTypography.bodyMd.copyWith(
                fontWeight: FontWeight.w600,
                color: AppColors.onSurface,
              ),
            ),
          ),
        ],
      ),
    );
  }
}
