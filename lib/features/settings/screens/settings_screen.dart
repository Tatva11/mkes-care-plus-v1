import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';

import '../../../core/theme/app_colors.dart';
import '../../../core/theme/app_spacing.dart';
import '../../../core/theme/app_typography.dart';
import '../../auth/providers/auth_provider.dart';
import '../../auth/repositories/auth_repository.dart';

class SettingsScreen extends ConsumerStatefulWidget {
  const SettingsScreen({super.key});

  @override
  ConsumerState<SettingsScreen> createState() => _SettingsScreenState();
}

class _SettingsScreenState extends ConsumerState<SettingsScreen> {
  bool _emailAlerts = true;
  bool _pushNotifications = true;
  bool _autoSaveNotes = true;
  String _defaultView = 'Dashboard';

  @override
  Widget build(BuildContext context) {
    final profileAsync = ref.watch(currentProfileProvider);
    final content = LayoutBuilder(
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
                    onPressed: () {
                      if (Navigator.of(context).canPop()) {
                        Navigator.of(context).pop();
                      }
                    },
                  ),
                  const SizedBox(width: AppSpacing.xs),
                  Expanded(
                    child: Text(
                      'Application Settings',
                      style: (isDesktop
                              ? AppTypography.displayLg
                              : AppTypography.displayLg.copyWith(fontSize: 24))
                          .copyWith(color: AppColors.onBackground),
                      overflow: TextOverflow.ellipsis,
                    ),
                  ),
                ],
              ),

              const SizedBox(height: AppSpacing.lg),

              // Settings Cards Grid
              if (isDesktop)
                Row(
                  crossAxisAlignment: CrossAxisAlignment.start,
                  children: [
                    Expanded(
                      child: Column(
                        children: [
                          _buildNotificationSettings(),
                          const SizedBox(height: AppSpacing.md),
                          _buildSecuritySettings(),
                        ],
                      ),
                    ),
                    const SizedBox(width: AppSpacing.md),
                    Expanded(
                      child: Column(
                        children: [
                          _buildClinicalDefaults(),
                          const SizedBox(height: AppSpacing.md),
                          _buildSystemInfoCard(),
                        ],
                      ),
                    ),
                  ],
                )
              else
                Column(
                  children: [
                    _buildNotificationSettings(),
                    const SizedBox(height: AppSpacing.md),
                    _buildClinicalDefaults(),
                    const SizedBox(height: AppSpacing.md),
                    _buildSecuritySettings(),
                    const SizedBox(height: AppSpacing.md),
                    _buildSystemInfoCard(),
                  ],
                ),
            ],
          ),
        );
      },
    );

    return profileAsync.when(
      data: (_) => Scaffold(body: content),
      loading: () => const Scaffold(
        body: Center(child: CircularProgressIndicator()),
      ),
      error: (error, _) => Scaffold(
        body: Center(
          child: Text('Could not load settings: $error'),
        ),
      ),
    );
  }

  Widget _buildNotificationSettings() {
    return Material(
      color: AppColors.surfaceContainerLowest,
      shape: RoundedRectangleBorder(
        borderRadius: BorderRadius.circular(AppSpacing.radiusLg),
        side: const BorderSide(color: AppColors.outlineVariant),
      ),
      child: Padding(
        padding: const EdgeInsets.all(AppSpacing.md),
        child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Row(
            children: [
              const Icon(Icons.notifications_active_outlined,
                  color: AppColors.primary, size: 20),
              const SizedBox(width: AppSpacing.xs),
              Expanded(
                child: Text(
                  'Notification Preferences',
                  style: AppTypography.headlineMd,
                  overflow: TextOverflow.ellipsis,
                ),
              ),
            ],
          ),
          const SizedBox(height: AppSpacing.sm),
          const Divider(height: 1),
          SwitchListTile(
            title: Text('Email Alert Digest',
                style:
                    AppTypography.bodyMd.copyWith(fontWeight: FontWeight.w600)),
            subtitle: Text(
                'Receive daily summaries of patient flow & inventory',
                style: AppTypography.bodySm
                    .copyWith(color: AppColors.onSurfaceVariant)),
            value: _emailAlerts,
            activeThumbColor: AppColors.primary,
            onChanged: (val) => setState(() => _emailAlerts = val),
          ),
          SwitchListTile(
            title: Text('Push Notifications',
                style:
                    AppTypography.bodyMd.copyWith(fontWeight: FontWeight.w600)),
            subtitle: Text('Instant alerts for low inventory & urgent triage',
                style: AppTypography.bodySm
                    .copyWith(color: AppColors.onSurfaceVariant)),
            value: _pushNotifications,
            activeThumbColor: AppColors.primary,
            onChanged: (val) => setState(() => _pushNotifications = val),
          ),
        ],
      ),
    ),
  );
  }

  Widget _buildClinicalDefaults() {
    return Material(
      color: AppColors.surfaceContainerLowest,
      shape: RoundedRectangleBorder(
        borderRadius: BorderRadius.circular(AppSpacing.radiusLg),
        side: const BorderSide(color: AppColors.outlineVariant),
      ),
      child: Padding(
        padding: const EdgeInsets.all(AppSpacing.md),
        child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Row(
            children: [
              const Icon(Icons.tune_outlined,
                  color: AppColors.secondary, size: 20),
              const SizedBox(width: AppSpacing.xs),
              Expanded(
                child: Text(
                  'Clinic Defaults',
                  style: AppTypography.headlineMd,
                  overflow: TextOverflow.ellipsis,
                ),
              ),
            ],
          ),
          const SizedBox(height: AppSpacing.sm),
          const Divider(height: 1),
          SwitchListTile(
            title: Text('Auto-Save Clinical Notes',
                style:
                    AppTypography.bodyMd.copyWith(fontWeight: FontWeight.w600)),
            subtitle: Text('Save draft notes every 30 seconds',
                style: AppTypography.bodySm
                    .copyWith(color: AppColors.onSurfaceVariant)),
            value: _autoSaveNotes,
            activeThumbColor: AppColors.secondary,
            onChanged: (val) => setState(() => _autoSaveNotes = val),
          ),
          Padding(
            padding: const EdgeInsets.symmetric(horizontal: 16, vertical: 8),
            child: Row(
              children: [
                Expanded(
                  child: Text(
                    'Default Landing View',
                    style: AppTypography.bodyMd
                        .copyWith(fontWeight: FontWeight.w600),
                  ),
                ),
                const SizedBox(width: AppSpacing.xs),
                DropdownButton<String>(
                  value: _defaultView,
                  items: const [
                    DropdownMenuItem(
                        value: 'Dashboard', child: Text('Dashboard')),
                    DropdownMenuItem(
                        value: 'Patients', child: Text('Patients Hub')),
                    DropdownMenuItem(
                        value: 'Operations', child: Text('Operations')),
                  ],
                  onChanged: (val) {
                    if (val != null) setState(() => _defaultView = val);
                  },
                ),
              ],
            ),
          ),
        ],
      ),
    ),
  );
  }

  Widget _buildSecuritySettings() {
    return Material(
      color: AppColors.surfaceContainerLowest,
      shape: RoundedRectangleBorder(
        borderRadius: BorderRadius.circular(AppSpacing.radiusLg),
        side: const BorderSide(color: AppColors.outlineVariant),
      ),
      child: Padding(
        padding: const EdgeInsets.all(AppSpacing.md),
        child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Row(
            children: [
              const Icon(Icons.lock_outline,
                  color: AppColors.primaryContainer, size: 20),
              const SizedBox(width: AppSpacing.xs),
              Expanded(
                child: Text(
                  'Security & Passwords',
                  style: AppTypography.headlineMd,
                  overflow: TextOverflow.ellipsis,
                ),
              ),
            ],
          ),
          const SizedBox(height: AppSpacing.sm),
          const Divider(height: 1),
          ListTile(
            title: Text('Change Password',
                style:
                    AppTypography.bodyMd.copyWith(fontWeight: FontWeight.w600)),
            subtitle: Text('Update your access password regularly',
                style: AppTypography.bodySm
                    .copyWith(color: AppColors.onSurfaceVariant)),
            trailing: OutlinedButton(
              onPressed: () => _sendPasswordResetEmail(context),
              child: const Text('Update'),
            ),
          ),
        ],
      ),
    ),
  );
  }

  Future<void> _sendPasswordResetEmail(BuildContext context) async {
    final authRepository = ref.read(authRepositoryProvider);
    final email = authRepository.currentUser?.email;
    if (email == null || email.isEmpty) {
      ScaffoldMessenger.of(context).showSnackBar(
        const SnackBar(
            content: Text('No email address is available for this account.')),
      );
      return;
    }

    try {
      await authRepository.resetPasswordForEmail(email);
      if (context.mounted) {
        ScaffoldMessenger.of(context).showSnackBar(
          SnackBar(content: Text('Password reset email sent to $email.')),
        );
      }
    } catch (error) {
      if (context.mounted) {
        ScaffoldMessenger.of(context).showSnackBar(
          SnackBar(
              content: Text('Could not send password reset email: $error')),
        );
      }
    }
  }

  Widget _buildSystemInfoCard() {
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
              const Icon(Icons.info_outline,
                  color: AppColors.outline, size: 20),
              const SizedBox(width: AppSpacing.xs),
              Expanded(
                child: Text(
                  'System & Build Info',
                  style: AppTypography.headlineMd,
                  overflow: TextOverflow.ellipsis,
                ),
              ),
            ],
          ),
          const SizedBox(height: AppSpacing.sm),
          const Divider(height: 1),
          const SizedBox(height: AppSpacing.sm),
          Text('MKES CARE+ Clinical SaaS Edition v2.4.0',
              style:
                  AppTypography.bodyMd.copyWith(fontWeight: FontWeight.bold)),
          Text('Build Status: Production-Ready • Flutter 3.29',
              style: AppTypography.bodySm
                  .copyWith(color: AppColors.onSurfaceVariant)),
        ],
      ),
    );
  }
}
