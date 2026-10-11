import 'package:flutter/material.dart';

import '../../../core/theme/app_colors.dart';
import '../../../core/theme/app_spacing.dart';
import '../../../core/theme/app_typography.dart';
import '../../billing/screens/billing_management_screen.dart';
import '../../reports/screens/admin_reports_screen.dart';
import '../../admin/widgets/admin_shell.dart';
import 'user_management_screen.dart';
import 'shift_management_screen.dart';

class AdministrationScreen extends StatelessWidget {
  const AdministrationScreen({super.key});

  @override
  Widget build(BuildContext context) {
    return AdminShell(
      selectedItem: AdminNavItem.administration,
      onNavItemSelected: (item) {
        if (item == AdminNavItem.dashboard) {
          Navigator.of(context).popUntil((route) => route.isFirst);
          return;
        }
      },
      body: const AdministrationContent(),
    );
  }
}

class AdministrationContent extends StatelessWidget {
  const AdministrationContent({super.key});

  @override
  Widget build(BuildContext context) {
    return LayoutBuilder(
      builder: (context, constraints) {
        final isDesktop = constraints.maxWidth > 768;
        return SingleChildScrollView(
          padding: EdgeInsets.all(
            isDesktop ? AppSpacing.marginDesktop : AppSpacing.marginMobile,
          ),
          child: Column(
            crossAxisAlignment: CrossAxisAlignment.start,
            children: [
              _buildHeaderTexts(),
              const SizedBox(height: AppSpacing.lg),
              if (isDesktop)
                Row(
                  crossAxisAlignment: CrossAxisAlignment.start,
                  children: [
                    Expanded(
                      child: Column(
                        crossAxisAlignment: CrossAxisAlignment.stretch,
                        children: [
                          _buildSettingCard(
                            Icons.receipt_long_outlined,
                            'Billing & Invoices',
                            'Create patient invoices, record payments, and view billing records.',
                            onTap: () {
                              Navigator.of(context).push(
                                MaterialPageRoute(
                                  builder: (_) => const BillingManagementScreen(),
                                ),
                              );
                            },
                          ),
                          const SizedBox(height: AppSpacing.md),
                          _buildSettingCard(
                            Icons.analytics_outlined,
                            'Reports & Analytics',
                            'View clinical, financial, and operational reports.',
                            onTap: () {
                              Navigator.of(context).push(
                                MaterialPageRoute(
                                  builder: (_) => const AdminReportsScreen(),
                                ),
                              );
                            },
                          ),
                          const SizedBox(height: AppSpacing.md),
                          _buildSettingCard(
                            Icons.security_outlined,
                            'Roles & Permissions',
                            'Manage staff access levels and system permissions.',
                          ),
                          const SizedBox(height: AppSpacing.md),
                          _buildSettingCard(
                            Icons.restore_outlined,
                            'Backup & Restore',
                            'Manage automated backups and data retention.',
                          ),
                        ],
                      ),
                    ),
                    const SizedBox(width: AppSpacing.md),
                    Expanded(
                      child: Column(
                        crossAxisAlignment: CrossAxisAlignment.stretch,
                        children: [
                          _buildSettingCard(
                            Icons.manage_accounts_outlined,
                            'Users',
                            'Add, remove, or modify user accounts.',
                            onTap: () {
                              Navigator.of(context).pushReplacement(
                                MaterialPageRoute(
                                  builder: (_) => const UserManagementScreen(),
                                ),
                              );
                            },
                          ),
                          const SizedBox(height: AppSpacing.md),
                          _buildSettingCard(
                            Icons.schedule_outlined,
                            'Shift Management',
                            'Configure shift timings, grace periods, and assign staff shifts.',
                            onTap: () {
                              Navigator.of(context).push(
                                MaterialPageRoute(
                                  builder: (_) => const ShiftManagementScreen(),
                                ),
                              );
                            },
                          ),
                          const SizedBox(height: AppSpacing.md),
                          _buildSettingCard(
                            Icons.settings_suggest_outlined,
                            'Clinic Settings',
                            'Configure clinic details, locations, and defaults.',
                          ),
                          const SizedBox(height: AppSpacing.md),
                          _buildSettingCard(
                            Icons.history_outlined,
                            'Audit Logs',
                            'Review system activity and security events.',
                          ),
                        ],
                      ),
                    ),
                  ],
                )
              else
                Column(
                  crossAxisAlignment: CrossAxisAlignment.stretch,
                  children: [
                    _buildSettingCard(
                      Icons.receipt_long_outlined,
                      'Billing & Invoices',
                      'Create patient invoices, record payments, and view billing records.',
                      onTap: () {
                        Navigator.of(context).push(
                          MaterialPageRoute(
                            builder: (_) => const BillingManagementScreen(),
                          ),
                        );
                      },
                    ),
                    const SizedBox(height: AppSpacing.md),
                    _buildSettingCard(
                      Icons.analytics_outlined,
                      'Reports & Analytics',
                      'View clinical, financial, and operational reports.',
                      onTap: () {
                        Navigator.of(context).push(
                          MaterialPageRoute(
                            builder: (_) => const AdminReportsScreen(),
                          ),
                        );
                      },
                    ),
                    const SizedBox(height: AppSpacing.md),
                    _buildSettingCard(
                      Icons.security_outlined,
                      'Roles & Permissions',
                      'Manage staff access levels and system permissions.',
                    ),
                    const SizedBox(height: AppSpacing.md),
                    _buildSettingCard(
                      Icons.restore_outlined,
                      'Backup & Restore',
                      'Manage automated backups and data retention.',
                    ),
                    const SizedBox(height: AppSpacing.md),
                    _buildSettingCard(
                      Icons.manage_accounts_outlined,
                      'Users',
                      'Add, remove, or modify user accounts.',
                      onTap: () {
                        Navigator.of(context).pushReplacement(
                          MaterialPageRoute(
                            builder: (_) => const UserManagementScreen(),
                          ),
                        );
                      },
                    ),
                    const SizedBox(height: AppSpacing.md),
                    _buildSettingCard(
                      Icons.schedule_outlined,
                      'Shift Management',
                      'Configure shift timings, grace periods, and assign staff shifts.',
                      onTap: () {
                        Navigator.of(context).push(
                          MaterialPageRoute(
                            builder: (_) => const ShiftManagementScreen(),
                          ),
                        );
                      },
                    ),
                    const SizedBox(height: AppSpacing.md),
                    _buildSettingCard(
                      Icons.settings_suggest_outlined,
                      'Clinic Settings',
                      'Configure clinic details, locations, and defaults.',
                    ),
                    const SizedBox(height: AppSpacing.md),
                    _buildSettingCard(
                      Icons.history_outlined,
                      'Audit Logs',
                      'Review system activity and security events.',
                    ),
                  ],
                ),
            ],
          ),
        );
      },
    );
  }

  Widget _buildHeaderTexts() {
    return Column(
      crossAxisAlignment: CrossAxisAlignment.start,
      children: [
        Text(
          'Administration',
          style: AppTypography.displayLg.copyWith(
            color: AppColors.onBackground,
          ),
        ),
        const SizedBox(height: AppSpacing.xs),
        Text(
          'Manage system settings, users, roles, and global configurations.',
          style: AppTypography.bodyLg.copyWith(
            color: AppColors.onSurfaceVariant,
          ),
        ),
      ],
    );
  }

  Widget _buildSettingCard(
    IconData icon,
    String title,
    String subtitle, {
    VoidCallback? onTap,
  }) {
    return InkWell(
      onTap: onTap ?? () {},
      borderRadius: BorderRadius.circular(AppSpacing.radiusLg),
      child: Container(
        padding: const EdgeInsets.all(AppSpacing.md),
        decoration: BoxDecoration(
          color: AppColors.surfaceContainerLowest,
          borderRadius: BorderRadius.circular(AppSpacing.radiusLg),
          border: Border.all(color: AppColors.outlineVariant),
          boxShadow: const [
            BoxShadow(
              color: Color(0x0A000000),
              blurRadius: 8,
              offset: Offset(0, 1),
            ),
          ],
        ),
        child: Row(
          children: [
            Container(
              padding: const EdgeInsets.all(AppSpacing.sm),
              decoration: BoxDecoration(
                color: AppColors.surfaceContainerLow,
                borderRadius: BorderRadius.circular(AppSpacing.radiusMd),
              ),
              child: Icon(icon, color: AppColors.primary, size: 28),
            ),
            const SizedBox(width: AppSpacing.md),
            Expanded(
              child: Column(
                crossAxisAlignment: CrossAxisAlignment.start,
                children: [
                  Text(
                    title,
                    style: AppTypography.headlineMd,
                  ),
                  const SizedBox(height: AppSpacing.xs),
                  Text(
                    subtitle,
                    style: AppTypography.bodyMd.copyWith(
                      color: AppColors.onSurfaceVariant,
                    ),
                  ),
                ],
              ),
            ),
            const Icon(Icons.chevron_right, color: AppColors.outline),
          ],
        ),
      ),
    );
  }
}
