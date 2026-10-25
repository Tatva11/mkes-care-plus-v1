import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';

import '../../../core/theme/app_colors.dart';
import '../../../core/theme/app_spacing.dart';
import '../../../core/theme/app_typography.dart';
import '../providers/whatsapp_inbox_provider.dart';
import '../repositories/whatsapp_repository.dart';

class WhatsAppAdminSettingsCard extends ConsumerStatefulWidget {
  const WhatsAppAdminSettingsCard({super.key});

  @override
  ConsumerState<WhatsAppAdminSettingsCard> createState() =>
      _WhatsAppAdminSettingsCardState();
}

class _WhatsAppAdminSettingsCardState
    extends ConsumerState<WhatsAppAdminSettingsCard> {
  bool _isSaving = false;

  @override
  Widget build(BuildContext context) {
    final settingsAsync = ref.watch(whatsappSettingsProvider);
    final templatesAsync = ref.watch(whatsappTemplatesProvider);
    final statsAsync = ref.watch(whatsappOutboxStatsProvider);

    return Card(
      elevation: 0,
      shape: RoundedRectangleBorder(
        borderRadius: BorderRadius.circular(AppSpacing.radiusLg),
        side: const BorderSide(color: AppColors.outlineVariant),
      ),
      color: AppColors.surfaceContainerLowest,
      child: Padding(
        padding: const EdgeInsets.all(AppSpacing.lg),
        child: Column(
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            // Header
            Row(
              children: [
                Container(
                  padding: const EdgeInsets.all(8),
                  decoration: BoxDecoration(
                    color: Colors.green.withValues(alpha: 0.15),
                    borderRadius: BorderRadius.circular(8),
                  ),
                  child: const Icon(Icons.chat_bubble_outline,
                      color: Colors.green, size: 24),
                ),
                const SizedBox(width: AppSpacing.sm),
                Expanded(
                  child: Column(
                    crossAxisAlignment: CrossAxisAlignment.start,
                    children: [
                      Text(
                        'WhatsApp & Unified Notification System',
                        style: AppTypography.headlineMd.copyWith(
                          fontSize: 18,
                          fontWeight: FontWeight.bold,
                        ),
                      ),
                      Text(
                        'Daemon configuration, automation controls, templates, and delivery monitoring',
                        style: AppTypography.bodySm.copyWith(
                          color: AppColors.onSurfaceVariant,
                        ),
                      ),
                    ],
                  ),
                ),
                IconButton(
                  icon: const Icon(Icons.refresh),
                  tooltip: 'Refresh Status',
                  onPressed: () {
                    ref.invalidate(whatsappSettingsProvider);
                    ref.invalidate(whatsappTemplatesProvider);
                    ref.invalidate(whatsappOutboxStatsProvider);
                  },
                ),
              ],
            ),
            const SizedBox(height: AppSpacing.lg),

            // Outbox Delivery Statistics
            Text(
              'OUTBOX DELIVERY METRICS',
              style: AppTypography.labelCaps.copyWith(
                color: AppColors.onSurfaceVariant,
                letterSpacing: 1,
              ),
            ),
            const SizedBox(height: AppSpacing.xs),
            statsAsync.when(
              loading: () => const LinearProgressIndicator(),
              error: (e, _) => Text('Error loading stats: $e'),
              data: (stats) {
                return Row(
                  children: [
                    _buildStatCard('Pending', '${stats['pending'] ?? 0}',
                        Colors.orange),
                    const SizedBox(width: AppSpacing.sm),
                    _buildStatCard(
                        'Sent', '${stats['sent'] ?? 0}', Colors.green),
                    const SizedBox(width: AppSpacing.sm),
                    _buildStatCard(
                        'Failed', '${stats['failed'] ?? 0}', AppColors.error),
                    const SizedBox(width: AppSpacing.sm),
                    _buildStatCard(
                        'Cancelled', '${stats['cancelled'] ?? 0}', Colors.grey),
                  ],
                );
              },
            ),
            const SizedBox(height: AppSpacing.lg),

            // Daemon & Automation Controls
            settingsAsync.when(
              loading: () => const Center(child: CircularProgressIndicator()),
              error: (err, _) => Text('Settings load error: $err'),
              data: (settings) {
                final isEnabled = settings?['is_enabled'] as bool? ?? false;
                final sessionStatus =
                    settings?['session_status']?.toString() ?? 'authenticated';
                final dailyLimit = settings?['daily_send_limit'] ?? 500;
                final opHoursStart =
                    settings?['operating_hours_start'] ?? '09:00';
                final opHoursEnd = settings?['operating_hours_end'] ?? '20:00';

                return Column(
                  crossAxisAlignment: CrossAxisAlignment.start,
                  children: [
                    Text(
                      'AUTOMATION CONTROLS',
                      style: AppTypography.labelCaps.copyWith(
                        color: AppColors.onSurfaceVariant,
                        letterSpacing: 1,
                      ),
                    ),
                    const SizedBox(height: AppSpacing.xs),
                    SwitchListTile(
                      contentPadding: EdgeInsets.zero,
                      title: const Text('Master WhatsApp Automation Worker'),
                      subtitle: Text(
                        isEnabled
                            ? 'Daemon active: Scheduled reminders and patient notifications are being processed.'
                            : 'Daemon safe-mode: Unattended automation is DISABLED per clinic safety policy.',
                      ),
                      value: isEnabled,
                      activeTrackColor: Colors.green,
                      onChanged: _isSaving
                          ? null
                          : (val) async {
                              setState(() => _isSaving = true);
                              final repo = ref.read(whatsappRepositoryProvider);
                              await repo.updateSettings({'is_enabled': val});
                              ref.invalidate(whatsappSettingsProvider);
                              setState(() => _isSaving = false);
                            },
                    ),
                    const Divider(height: AppSpacing.md),
                    Row(
                      children: [
                        Expanded(
                          child: _buildInfoItem(
                            'Session Status',
                            sessionStatus.toUpperCase(),
                            sessionStatus == 'authenticated'
                                ? Colors.green
                                : Colors.orange,
                          ),
                        ),
                        Expanded(
                          child: _buildInfoItem(
                            'Operating Window',
                            '$opHoursStart - $opHoursEnd',
                            AppColors.onSurface,
                          ),
                        ),
                        Expanded(
                          child: _buildInfoItem(
                            'Daily Limit',
                            '$dailyLimit msgs',
                            AppColors.onSurface,
                          ),
                        ),
                      ],
                    ),
                  ],
                );
              },
            ),
            const SizedBox(height: AppSpacing.lg),

            // Message Templates
            Text(
              'CLINICAL MESSAGE TEMPLATES',
              style: AppTypography.labelCaps.copyWith(
                color: AppColors.onSurfaceVariant,
                letterSpacing: 1,
              ),
            ),
            const SizedBox(height: AppSpacing.xs),
            templatesAsync.when(
              loading: () => const LinearProgressIndicator(),
              error: (e, _) => Text('Error loading templates: $e'),
              data: (templates) {
                if (templates.isEmpty) {
                  return const Text('No templates configured.');
                }
                return Container(
                  decoration: BoxDecoration(
                    border: Border.all(color: AppColors.outlineVariant),
                    borderRadius: BorderRadius.circular(AppSpacing.radiusMd),
                  ),
                  child: ListView.separated(
                    shrinkWrap: true,
                    physics: const NeverScrollableScrollPhysics(),
                    itemCount: templates.length,
                    separatorBuilder: (_, __) =>
                        const Divider(height: 1, color: AppColors.outlineVariant),
                    itemBuilder: (context, index) {
                      final t = templates[index];
                      final key = t['template_key']?.toString() ?? '';
                      final title = t['title']?.toString() ?? key;
                      final dept = (t['department']?.toString() ?? 'all').toUpperCase();
                      final isActive = t['is_active'] as bool? ?? true;

                      return ListTile(
                        dense: true,
                        leading: CircleAvatar(
                          radius: 14,
                          backgroundColor: AppColors.surfaceContainerHigh,
                          child: Text(
                            dept.substring(0, 1),
                            style: AppTypography.labelCaps.copyWith(fontSize: 10),
                          ),
                        ),
                        title: Text(title, style: AppTypography.bodySm.copyWith(fontWeight: FontWeight.w600)),
                        subtitle: Text(key, style: AppTypography.labelCaps.copyWith(fontSize: 10, color: AppColors.outline)),
                        trailing: Switch(
                          value: isActive,
                          activeTrackColor: AppColors.primary,
                          onChanged: (val) async {
                            final repo = ref.read(whatsappRepositoryProvider);
                            await repo.setTemplateActive(key, val);
                            ref.invalidate(whatsappTemplatesProvider);
                          },
                        ),
                      );
                    },
                  ),
                );
              },
            ),
          ],
        ),
      ),
    );
  }

  Widget _buildStatCard(String label, String value, Color color) {
    return Expanded(
      child: Container(
        padding: const EdgeInsets.symmetric(
            horizontal: AppSpacing.md, vertical: AppSpacing.sm),
        decoration: BoxDecoration(
          color: color.withValues(alpha: 0.1),
          borderRadius: BorderRadius.circular(AppSpacing.radiusMd),
          border: Border.all(color: color.withValues(alpha: 0.3)),
        ),
        child: Column(
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            Text(label, style: AppTypography.labelCaps.copyWith(color: color, fontSize: 10)),
            const SizedBox(height: 2),
            Text(value, style: AppTypography.headlineMd.copyWith(fontSize: 20, color: color, fontWeight: FontWeight.bold)),
          ],
        ),
      ),
    );
  }

  Widget _buildInfoItem(String label, String value, Color color) {
    return Column(
      crossAxisAlignment: CrossAxisAlignment.start,
      children: [
        Text(label, style: AppTypography.labelCaps.copyWith(fontSize: 10, color: AppColors.outline)),
        const SizedBox(height: 2),
        Text(value, style: AppTypography.bodyMd.copyWith(color: color, fontWeight: FontWeight.w600)),
      ],
    );
  }
}
