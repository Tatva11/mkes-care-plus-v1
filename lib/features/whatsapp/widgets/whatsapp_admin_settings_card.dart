import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';

import '../../../core/theme/app_colors.dart';
import '../../../core/theme/app_spacing.dart';
import '../../../core/theme/app_typography.dart';
import '../../patients/providers/patients_provider.dart';
import '../providers/whatsapp_inbox_provider.dart';
import '../repositories/whatsapp_repository.dart';
import '../screens/whatsapp_inbox_screen.dart';

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
                final totalSent = (stats['sent'] ?? 0) +
                    (stats['delivered'] ?? 0) +
                    (stats['read'] ?? 0);
                final failedCount = stats['failed'] ?? 0;
                return Column(
                  crossAxisAlignment: CrossAxisAlignment.start,
                  children: [
                    Row(
                      children: [
                        _buildStatCard('Pending', '${stats['pending'] ?? 0}',
                            Colors.orange),
                        const SizedBox(width: AppSpacing.sm),
                        _buildStatCard('Sent', '$totalSent', Colors.green),
                        const SizedBox(width: AppSpacing.sm),
                        _buildStatCard(
                          'Failed',
                          '$failedCount',
                          AppColors.error,
                          onTap: () => _showFailedMessagesDialog(context),
                        ),
                        const SizedBox(width: AppSpacing.sm),
                        _buildStatCard(
                            'Cancelled', '${stats['cancelled'] ?? 0}', Colors.grey),
                      ],
                    ),
                    const SizedBox(height: AppSpacing.sm),
                    // Quick Action Buttons
                    Wrap(
                      spacing: AppSpacing.sm,
                      runSpacing: AppSpacing.xs,
                      children: [
                        FilledButton.tonalIcon(
                          icon: const Icon(Icons.forum_outlined, size: 16),
                          label: const Text('Shared Patient Inbox'),
                          onPressed: () {
                            Navigator.of(context).push(
                              MaterialPageRoute(
                                builder: (_) => const WhatsAppInboxScreen(),
                              ),
                            );
                          },
                        ),
                        OutlinedButton.icon(
                          icon: const Icon(Icons.person_off_outlined, size: 16),
                          label: const Text('Opt-Out Manager'),
                          onPressed: () => _showOptOutManagementDialog(context),
                        ),
                        if (failedCount > 0)
                          FilledButton.icon(
                            style: FilledButton.styleFrom(
                              backgroundColor: AppColors.error,
                            ),
                            icon: const Icon(Icons.warning_amber_rounded, size: 16),
                            label: Text('Inspect $failedCount Failed Messages'),
                            onPressed: () => _showFailedMessagesDialog(context),
                          ),
                      ],
                    ),
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

  void _showFailedMessagesDialog(BuildContext context) {
    showDialog(
      context: context,
      builder: (dialogCtx) {
        return StatefulBuilder(
          builder: (context, setDialogState) {
            final repo = ref.read(whatsappRepositoryProvider);
            return AlertDialog(
              title: Row(
                children: [
                  const Icon(Icons.error_outline, color: AppColors.error),
                  const SizedBox(width: AppSpacing.sm),
                  const Expanded(
                    child: Text('Failed WhatsApp Messages'),
                  ),
                  IconButton(
                    icon: const Icon(Icons.refresh, size: 20),
                    tooltip: 'Refresh',
                    onPressed: () {
                      setDialogState(() {});
                    },
                  ),
                ],
              ),
              content: SizedBox(
                width: 650,
                height: 450,
                child: FutureBuilder<List<Map<String, dynamic>>>(
                  future: repo.fetchFailedOutboxMessages(),
                  builder: (context, snapshot) {
                    if (snapshot.connectionState == ConnectionState.waiting) {
                      return const Center(child: CircularProgressIndicator());
                    }
                    if (snapshot.hasError) {
                      return Center(child: Text('Error loading failed messages: ${snapshot.error}'));
                    }
                    final items = snapshot.data ?? [];
                    if (items.isEmpty) {
                      return Center(
                        child: Column(
                          mainAxisSize: MainAxisSize.min,
                          children: [
                            const Icon(Icons.check_circle_outline, size: 48, color: Colors.green),
                            const SizedBox(height: AppSpacing.sm),
                            Text('No failed messages found in outbox.',
                                style: AppTypography.bodyMd.copyWith(fontWeight: FontWeight.w600)),
                            const SizedBox(height: AppSpacing.xs),
                            Text('All queued notifications delivered successfully.',
                                style: AppTypography.bodySm.copyWith(color: AppColors.onSurfaceVariant)),
                          ],
                        ),
                      );
                    }
                    return ListView.separated(
                      itemCount: items.length,
                      separatorBuilder: (_, __) => const Divider(height: 1),
                      itemBuilder: (context, idx) {
                        final m = items[idx];
                        final id = m['id']?.toString() ?? '';
                        final phone = m['recipient_phone']?.toString() ?? '';
                        final dept = (m['department']?.toString() ?? 'clinic').toUpperCase();
                        final error = m['last_error']?.toString() ?? 'Unknown delivery failure';
                        final retries = m['retry_count'] ?? 0;
                        final maxRetries = m['max_retries'] ?? 3;
                        final patientName = (m['patients'] is Map) ? m['patients']['name']?.toString() : null;

                        return Padding(
                          padding: const EdgeInsets.symmetric(vertical: AppSpacing.sm),
                          child: Column(
                            crossAxisAlignment: CrossAxisAlignment.start,
                            children: [
                              Row(
                                children: [
                                  Container(
                                    padding: const EdgeInsets.symmetric(horizontal: 6, vertical: 2),
                                    decoration: BoxDecoration(
                                      color: AppColors.surfaceContainerHigh,
                                      borderRadius: BorderRadius.circular(4),
                                    ),
                                    child: Text(dept, style: AppTypography.labelCaps.copyWith(fontSize: 9, fontWeight: FontWeight.bold)),
                                  ),
                                  const SizedBox(width: AppSpacing.xs),
                                  Expanded(
                                    child: Text(
                                      patientName != null ? '$patientName ($phone)' : phone,
                                      style: AppTypography.bodySm.copyWith(fontWeight: FontWeight.bold),
                                    ),
                                  ),
                                  Text(
                                    'Retries: $retries/$maxRetries',
                                    style: AppTypography.labelCaps.copyWith(fontSize: 10, color: AppColors.outline),
                                  ),
                                ],
                              ),
                              const SizedBox(height: 4),
                              Text(
                                'Error: $error',
                                style: AppTypography.bodySm.copyWith(color: AppColors.error, fontSize: 11),
                              ),
                              const SizedBox(height: 4),
                              Row(
                                mainAxisAlignment: MainAxisAlignment.end,
                                children: [
                                  TextButton.icon(
                                    icon: const Icon(Icons.cancel_outlined, size: 14),
                                    label: const Text('Cancel', style: TextStyle(fontSize: 12)),
                                    onPressed: () async {
                                      final res = await repo.cancelPendingMessage(id);
                                      if (context.mounted) {
                                        ScaffoldMessenger.of(context).showSnackBar(
                                          SnackBar(
                                            content: Text(res['message']?.toString() ?? 'Message cancelled'),
                                            backgroundColor: res['success'] == true ? Colors.grey : AppColors.error,
                                          ),
                                        );
                                        setDialogState(() {});
                                        ref.invalidate(whatsappOutboxStatsProvider);
                                      }
                                    },
                                  ),
                                  const SizedBox(width: AppSpacing.xs),
                                  FilledButton.tonalIcon(
                                    icon: const Icon(Icons.refresh, size: 14),
                                    label: const Text('Retry Now', style: TextStyle(fontSize: 12)),
                                    onPressed: () async {
                                      final res = await repo.retryFailedMessage(id);
                                      if (context.mounted) {
                                        ScaffoldMessenger.of(context).showSnackBar(
                                          SnackBar(
                                            content: Text(res['message']?.toString() ?? 'Queued for retry'),
                                            backgroundColor: res['success'] == true ? Colors.green : AppColors.error,
                                          ),
                                        );
                                        setDialogState(() {});
                                        ref.invalidate(whatsappOutboxStatsProvider);
                                      }
                                    },
                                  ),
                                ],
                              ),
                            ],
                          ),
                        );
                      },
                    );
                  },
                ),
              ),
              actions: [
                TextButton(
                  onPressed: () => Navigator.of(dialogCtx).pop(),
                  child: const Text('Close'),
                ),
              ],
            );
          },
        );
      },
    );
  }

  void _showOptOutManagementDialog(BuildContext context) {
    showDialog(
      context: context,
      builder: (dialogCtx) {
        String searchQuery = '';
        return StatefulBuilder(
          builder: (context, setDialogState) {
            final repo = ref.read(whatsappRepositoryProvider);
            final patientsAsync = ref.watch(patientsProvider);

            return AlertDialog(
              title: Row(
                children: [
                  const Icon(Icons.person_off_outlined, color: AppColors.primary),
                  const SizedBox(width: AppSpacing.sm),
                  const Expanded(
                    child: Text('WhatsApp Opt-Out Manager'),
                  ),
                ],
              ),
              content: SizedBox(
                width: 600,
                height: 450,
                child: Column(
                  children: [
                    TextField(
                      decoration: const InputDecoration(
                        hintText: 'Search patients by name or phone...',
                        prefixIcon: Icon(Icons.search, size: 20),
                        isDense: true,
                        border: OutlineInputBorder(),
                      ),
                      onChanged: (val) {
                        setDialogState(() {
                          searchQuery = val.trim().toLowerCase();
                        });
                      },
                    ),
                    const SizedBox(height: AppSpacing.sm),
                    Text(
                      'Patients who texted STOP or requested opt-out are excluded from automated messages.',
                      style: AppTypography.bodySm.copyWith(color: AppColors.onSurfaceVariant, fontSize: 11),
                    ),
                    const Divider(height: AppSpacing.md),
                    Expanded(
                      child: patientsAsync.when(
                        loading: () => const Center(child: CircularProgressIndicator()),
                        error: (err, _) => Center(child: Text('Error loading patients: $err')),
                        data: (patients) {
                          final filtered = patients.where((p) {
                            if (searchQuery.isEmpty) return true;
                            return p.name.toLowerCase().contains(searchQuery) ||
                                (p.mobile != null && p.mobile!.contains(searchQuery));
                          }).toList();

                          if (filtered.isEmpty) {
                            return const Center(child: Text('No matching patients found.'));
                          }

                          return ListView.separated(
                            itemCount: filtered.length,
                            separatorBuilder: (_, __) => const Divider(height: 1),
                            itemBuilder: (context, idx) {
                              final patient = filtered[idx];
                              final isOptedOut = patient.whatsappOptOut;

                              return ListTile(
                                dense: true,
                                contentPadding: EdgeInsets.zero,
                                leading: CircleAvatar(
                                  radius: 14,
                                  backgroundColor: isOptedOut
                                      ? AppColors.error.withValues(alpha: 0.15)
                                      : Colors.green.withValues(alpha: 0.15),
                                  child: Icon(
                                    isOptedOut ? Icons.block : Icons.check,
                                    size: 14,
                                    color: isOptedOut ? AppColors.error : Colors.green,
                                  ),
                                ),
                                title: Text(patient.name, style: AppTypography.bodySm.copyWith(fontWeight: FontWeight.w600)),
                                subtitle: Text(
                                  '${patient.mobile ?? "No phone"} • ${patient.department ?? "General"}',
                                  style: AppTypography.labelCaps.copyWith(fontSize: 10, color: AppColors.outline),
                                ),
                                trailing: Switch(
                                  value: isOptedOut,
                                  activeTrackColor: AppColors.error,
                                  inactiveThumbColor: Colors.green,
                                  inactiveTrackColor: Colors.green.withValues(alpha: 0.3),
                                  onChanged: (val) async {
                                    final success = await repo.setPatientOptOut(patient.id, val);
                                    if (context.mounted) {
                                      ScaffoldMessenger.of(context).showSnackBar(
                                        SnackBar(
                                          content: Text(success
                                              ? '${patient.name} opt-out updated: ${val ? "Opted Out" : "Subscribed"}'
                                              : 'Failed to update opt-out status'),
                                          backgroundColor: success ? (val ? AppColors.error : Colors.green) : AppColors.error,
                                        ),
                                      );
                                    }
                                    ref.invalidate(patientsProvider);
                                    setDialogState(() {});
                                  },
                                ),
                              );
                            },
                          );
                        },
                      ),
                    ),
                  ],
                ),
              ),
              actions: [
                TextButton(
                  onPressed: () => Navigator.of(dialogCtx).pop(),
                  child: const Text('Close'),
                ),
              ],
            );
          },
        );
      },
    );
  }

  Widget _buildStatCard(String label, String value, Color color, {VoidCallback? onTap}) {
    return Expanded(
      child: InkWell(
        onTap: onTap,
        borderRadius: BorderRadius.circular(AppSpacing.radiusMd),
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
              Row(
                mainAxisAlignment: MainAxisAlignment.spaceBetween,
                children: [
                  Text(label, style: AppTypography.labelCaps.copyWith(color: color, fontSize: 10)),
                  if (onTap != null)
                    Icon(Icons.open_in_new, size: 11, color: color),
                ],
              ),
              const SizedBox(height: 2),
              Text(value, style: AppTypography.headlineMd.copyWith(fontSize: 20, color: color, fontWeight: FontWeight.bold)),
            ],
          ),
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

