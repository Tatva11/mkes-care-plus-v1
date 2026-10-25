import 'package:flutter/material.dart';

import '../../../core/theme/app_colors.dart';
import '../../../core/theme/app_spacing.dart';
import '../../../core/theme/app_typography.dart';
import 'admin_login_screen.dart';
import 'staff_login_screen.dart';

/// Landing page where the user selects which portal to enter.
/// Routes to AdminLoginScreen or StaffLoginScreen.
class RoleSelectionScreen extends StatelessWidget {
  const RoleSelectionScreen({super.key});

  @override
  Widget build(BuildContext context) {
    final screenSize = MediaQuery.sizeOf(context);
    final isDesktop = screenSize.width >= 600;

    return Scaffold(
      backgroundColor: AppColors.background,
      body: SafeArea(
        child: Center(
          child: SingleChildScrollView(
            padding: EdgeInsets.all(
              isDesktop ? AppSpacing.marginDesktop : AppSpacing.marginMobile,
            ),
            child: ConstrainedBox(
              constraints: const BoxConstraints(maxWidth: 520),
              child: Column(
                mainAxisAlignment: MainAxisAlignment.center,
                children: [
                  _buildBrandHeader(isDesktop),
                  SizedBox(height: isDesktop ? 56 : AppSpacing.lg),
                  _buildPortalCard(
                    context,
                    icon: Icons.admin_panel_settings_outlined,
                    iconColor: AppColors.primary,
                    iconBgColor: AppColors.primaryFixed,
                    title: 'Admin Portal',
                    subtitle:
                        'For clinic administrators, doctors, and department heads.',
                    onTap: () {
                      Navigator.of(context).push(
                        MaterialPageRoute(
                          builder: (_) => const AdminLoginScreen(),
                        ),
                      );
                    },
                  ),
                  const SizedBox(height: AppSpacing.md),
                  _buildPortalCard(
                    context,
                    icon: Icons.badge_outlined,
                    iconColor: AppColors.secondary,
                    iconBgColor: Color(0xFFFFE8F5),
                    title: 'Staff Portal',
                    subtitle:
                        'For receptionists, assistants, and clinic support staff.',
                    onTap: () {
                      Navigator.of(context).push(
                        MaterialPageRoute(
                          builder: (_) => const StaffLoginScreen(),
                        ),
                      );
                    },
                  ),
                  const SizedBox(height: AppSpacing.xl),
                  Text(
                    'MKES CARE+ — Clinical Management Platform',
                    textAlign: TextAlign.center,
                    style: AppTypography.bodySm.copyWith(
                      color: AppColors.outline,
                    ),
                  ),
                ],
              ),
            ),
          ),
        ),
      ),
    );
  }

  Widget _buildBrandHeader(bool isDesktop) {
    final logoSize = isDesktop ? 96.0 : 80.0;
    return Column(
      children: [
        // MKES CARE+ Official Circular Logo
        Hero(
          tag: 'mkes_logo',
          child: Image.asset(
            'assets/images/mkes_logo.png',
            width: logoSize,
            height: logoSize,
            fit: BoxFit.contain,
          ),
        ),
        SizedBox(height: isDesktop ? AppSpacing.md : AppSpacing.sm),
        Text(
          'MKES CARE+',
          textAlign: TextAlign.center,
          style: (isDesktop
                  ? AppTypography.displayLg
                  : AppTypography.displayLg
                      .copyWith(fontSize: 36, height: 44 / 36))
              .copyWith(letterSpacing: -0.5),
        ),
        const SizedBox(height: AppSpacing.xs),
        Text(
          'Select your portal to continue',
          textAlign: TextAlign.center,
          style: AppTypography.bodyLg,
        ),
      ],
    );
  }

  Widget _buildPortalCard(
    BuildContext context, {
    required IconData icon,
    required Color iconColor,
    required Color iconBgColor,
    required String title,
    required String subtitle,
    required VoidCallback onTap,
  }) {
    return Material(
      color: AppColors.surfaceContainerLowest,
      borderRadius: BorderRadius.circular(AppSpacing.radiusXl),
      child: InkWell(
        onTap: onTap,
        borderRadius: BorderRadius.circular(AppSpacing.radiusXl),
        child: Container(
          padding: const EdgeInsets.all(AppSpacing.md),
          decoration: BoxDecoration(
            borderRadius: BorderRadius.circular(AppSpacing.radiusXl),
            border: Border.all(color: AppColors.outlineVariant),
            boxShadow: const [
              BoxShadow(
                color: Color(0x08000000),
                blurRadius: 12,
                offset: Offset(0, 2),
              ),
            ],
          ),
          child: Row(
            children: [
              Container(
                width: 52,
                height: 52,
                decoration: BoxDecoration(
                  color: iconBgColor,
                  borderRadius: BorderRadius.circular(14),
                ),
                child: Icon(icon, color: iconColor, size: 28),
              ),
              const SizedBox(width: AppSpacing.md),
              Expanded(
                child: Column(
                  crossAxisAlignment: CrossAxisAlignment.start,
                  children: [
                    Text(
                      title,
                      style: AppTypography.headlineMd.copyWith(fontSize: 18),
                    ),
                    const SizedBox(height: 4),
                    Text(
                      subtitle,
                      style: AppTypography.bodySm.copyWith(
                        color: AppColors.onSurfaceVariant,
                      ),
                    ),
                  ],
                ),
              ),
              const SizedBox(width: AppSpacing.xs),
              Icon(
                Icons.arrow_forward_ios_rounded,
                size: 16,
                color: AppColors.outline,
              ),
            ],
          ),
        ),
      ),
    );
  }
}
