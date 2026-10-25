import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';

import '../../core/theme/app_colors.dart';
import '../../core/theme/app_spacing.dart';
import '../../core/theme/app_typography.dart';
import '../../features/notifications/models/notification_model.dart';
import '../../features/notifications/providers/notifications_provider.dart';
import '../../features/whatsapp/screens/whatsapp_inbox_screen.dart';
import '../../features/dental/screens/dental_lab_screen.dart';
import '../../features/eye/screens/eye_surgery_screen.dart';
import '../../features/inventory/screens/inventory_screen.dart';
import '../../features/staff_portal/screens/staff_tasks_screen.dart';
import '../../features/staff_portal/screens/staff_schedule_screen.dart';
import '../../features/staff_portal/screens/staff_leave_screen.dart';
import '../../features/staff_portal/screens/staff_attendance_screen.dart';

// ---------------------------------------------------------------------------
// Legacy helper class kept for API compatibility.
// ---------------------------------------------------------------------------
class NotificationItem {
  final String id;
  final String title;
  final String message;
  final String time;
  final IconData icon;
  final Color iconColor;
  bool isRead;

  NotificationItem({
    required this.id,
    required this.title,
    required this.message,
    required this.time,
    required this.icon,
    required this.iconColor,
    this.isRead = false,
  });
}

// ---------------------------------------------------------------------------
// The notification bell button — shown in both AdminShell and StaffShell.
// Reads real notifications from Supabase via [notificationsProvider].
// ---------------------------------------------------------------------------
class NotificationCenterButton extends ConsumerWidget {
  const NotificationCenterButton({super.key});

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    final unread = ref.watch(unreadNotificationCountProvider);

    return Stack(
      alignment: Alignment.center,
      children: [
        IconButton(
          icon: const Icon(Icons.notifications_none),
          color: AppColors.onSurfaceVariant,
          iconSize: 22,
          tooltip: 'Notifications',
          onPressed: () => _showNotificationDialog(context, ref),
        ),
        if (unread > 0)
          Positioned(
            top: 10,
            right: 10,
            child: Container(
              padding: const EdgeInsets.all(4),
              decoration: const BoxDecoration(
                color: AppColors.error,
                shape: BoxShape.circle,
              ),
              constraints: const BoxConstraints(minWidth: 16, minHeight: 16),
              child: Text(
                '$unread',
                style: const TextStyle(
                  color: Colors.white,
                  fontSize: 9,
                  fontWeight: FontWeight.bold,
                ),
                textAlign: TextAlign.center,
              ),
            ),
          ),
      ],
    );
  }

  void _showNotificationDialog(BuildContext context, WidgetRef ref) {
    ref.read(notificationsProvider.notifier).fetch();
    showDialog(
      context: context,
      builder: (_) => const _NotificationDialog(),
    );
  }
}

// ---------------------------------------------------------------------------
// The modal dialog that shows notifications from Supabase with routing & filtering.
// ---------------------------------------------------------------------------
class _NotificationDialog extends ConsumerStatefulWidget {
  const _NotificationDialog();

  @override
  ConsumerState<_NotificationDialog> createState() => _NotificationDialogState();
}

class _NotificationDialogState extends ConsumerState<_NotificationDialog> {
  String _selectedCategory = 'all'; // 'all' | 'unread' | 'whatsapp' | 'appointment' | 'clinical'

  @override
  Widget build(BuildContext context) {
    final notifAsync = ref.watch(notificationsProvider);

    return Dialog(
      alignment: Alignment.topRight,
      insetPadding: const EdgeInsets.only(top: 60, right: 16, left: 16),
      shape: RoundedRectangleBorder(
        borderRadius: BorderRadius.circular(AppSpacing.radiusXl),
        side: const BorderSide(color: AppColors.outlineVariant),
      ),
      child: Container(
        width: 440,
        constraints: const BoxConstraints(maxHeight: 600),
        decoration: BoxDecoration(
          color: AppColors.surfaceContainerLowest,
          borderRadius: BorderRadius.circular(AppSpacing.radiusXl),
        ),
        child: Column(
          children: [
            // Header
            Padding(
              padding: const EdgeInsets.all(AppSpacing.md),
              child: Column(
                children: [
                  Row(
                    mainAxisAlignment: MainAxisAlignment.spaceBetween,
                    children: [
                      // Title + unread badge
                      Flexible(
                        child: Row(
                          children: [
                            Flexible(
                              child: Text(
                                'Notifications',
                                style: AppTypography.headlineMd,
                                overflow: TextOverflow.ellipsis,
                              ),
                            ),
                            const SizedBox(width: AppSpacing.xs),
                            notifAsync.when(
                              data: (items) {
                                final unread = items.where((n) => !n.isRead).length;
                                if (unread == 0) return const SizedBox.shrink();
                                return Container(
                                  padding: const EdgeInsets.symmetric(
                                    horizontal: 8,
                                    vertical: 2,
                                  ),
                                  decoration: BoxDecoration(
                                    color: AppColors.primaryContainer,
                                    borderRadius: BorderRadius.circular(12),
                                  ),
                                  child: Text(
                                    '$unread new',
                                    style: AppTypography.labelCaps.copyWith(
                                      color: AppColors.onPrimaryContainer,
                                      fontSize: 10,
                                    ),
                                  ),
                                );
                              },
                              loading: () => const SizedBox.shrink(),
                              error: (_, __) => const SizedBox.shrink(),
                            ),
                          ],
                        ),
                      ),
                      // Actions
                      Row(
                        mainAxisSize: MainAxisSize.min,
                        children: [
                          IconButton(
                            icon: const Icon(Icons.refresh, size: 20),
                            color: AppColors.onSurfaceVariant,
                            tooltip: 'Refresh',
                            onPressed: () =>
                                ref.read(notificationsProvider.notifier).fetch(),
                          ),
                          notifAsync.maybeWhen(
                            data: (items) {
                              final hasUnread = items.any((n) => !n.isRead);
                              if (!hasUnread) return const SizedBox.shrink();
                              return TextButton(
                                onPressed: () => ref
                                    .read(notificationsProvider.notifier)
                                    .markAllRead(),
                                child: Text(
                                  'Mark all read',
                                  style: AppTypography.labelCaps
                                      .copyWith(color: AppColors.primary),
                                ),
                              );
                            },
                            orElse: () => const SizedBox.shrink(),
                          ),
                          notifAsync.maybeWhen(
                            data: (items) {
                              if (items.isEmpty) return const SizedBox.shrink();
                              return IconButton(
                                icon: const Icon(Icons.delete_sweep_outlined, size: 20),
                                color: AppColors.onSurfaceVariant,
                                tooltip: 'Clear all',
                                onPressed: () {
                                  ref
                                      .read(notificationsProvider.notifier)
                                      .deleteAll();
                                  Navigator.of(context).pop();
                                },
                              );
                            },
                            orElse: () => const SizedBox.shrink(),
                          ),
                        ],
                      ),
                    ],
                  ),
                  const SizedBox(height: AppSpacing.xs),
                  // Filter Chips
                  SingleChildScrollView(
                    scrollDirection: Axis.horizontal,
                    child: Row(
                      children: [
                        _buildFilterChip('All', 'all'),
                        const SizedBox(width: AppSpacing.xs),
                        _buildFilterChip('Unread', 'unread'),
                        const SizedBox(width: AppSpacing.xs),
                        _buildFilterChip('WhatsApp', 'whatsapp'),
                        const SizedBox(width: AppSpacing.xs),
                        _buildFilterChip('Appointments', 'appointment'),
                        const SizedBox(width: AppSpacing.xs),
                        _buildFilterChip('Clinical', 'clinical'),
                      ],
                    ),
                  ),
                ],
              ),
            ),
            const Divider(height: 1),
            // Body
            Expanded(
              child: notifAsync.when(
                loading: () =>
                    const Center(child: CircularProgressIndicator()),
                error: (e, _) => Center(
                  child: Padding(
                    padding: const EdgeInsets.all(AppSpacing.md),
                    child: Column(
                      mainAxisSize: MainAxisSize.min,
                      children: [
                        const Icon(Icons.error_outline,
                            color: AppColors.error, size: 36),
                        const SizedBox(height: 8),
                        Text(
                          'Unable to load notifications.',
                          style: AppTypography.bodySm,
                        ),
                        const SizedBox(height: 8),
                        TextButton(
                          onPressed: () => ref
                              .read(notificationsProvider.notifier)
                              .fetch(),
                          child: const Text('Try Again'),
                        ),
                      ],
                    ),
                  ),
                ),
                data: (items) {
                  final filtered = _filterItems(items);

                  if (filtered.isEmpty) {
                    return Center(
                      child: Padding(
                        padding: const EdgeInsets.all(AppSpacing.xl),
                        child: Column(
                          mainAxisSize: MainAxisSize.min,
                          children: [
                            const Icon(
                              Icons.notifications_off_outlined,
                              size: 40,
                              color: AppColors.outline,
                            ),
                            const SizedBox(height: AppSpacing.sm),
                            Text(
                              _selectedCategory == 'all'
                                  ? 'No notifications'
                                  : 'No $_selectedCategory notifications',
                              style: AppTypography.bodyMd.copyWith(
                                color: AppColors.onSurfaceVariant,
                              ),
                            ),
                          ],
                        ),
                      ),
                    );
                  }
                  return RefreshIndicator(
                    onRefresh: () =>
                        ref.read(notificationsProvider.notifier).fetch(),
                    child: ListView.separated(
                      padding: EdgeInsets.zero,
                      itemCount: filtered.length,
                      separatorBuilder: (_, __) => const Divider(height: 1),
                      itemBuilder: (context, index) {
                        final item = filtered[index];
                        return _NotificationTile(item: item);
                      },
                    ),
                  );
                },
              ),
            ),
          ],
        ),
      ),
    );
  }

  Widget _buildFilterChip(String label, String value) {
    final isSelected = _selectedCategory == value;
    return ChoiceChip(
      label: Text(label),
      selected: isSelected,
      labelStyle: TextStyle(
        fontSize: 11,
        fontWeight: isSelected ? FontWeight.w600 : FontWeight.normal,
      ),
      onSelected: (_) {
        setState(() {
          _selectedCategory = value;
        });
      },
    );
  }

  List<NotificationModel> _filterItems(List<NotificationModel> all) {
    switch (_selectedCategory) {
      case 'unread':
        return all.where((n) => !n.isRead).toList();
      case 'whatsapp':
        return all.where((n) => n.type == 'whatsapp_reply').toList();
      case 'appointment':
        return all
            .where((n) =>
                n.type == 'appointment' || n.type == 'appointment_rescheduled')
            .toList();
      case 'clinical':
        return all
            .where((n) =>
                n.type == 'lab_ready' ||
                n.type == 'eye_surgery' ||
                n.type == 'eye_surgery_assigned')
            .toList();
      default:
        return all;
    }
  }
}

class _NotificationTile extends ConsumerWidget {
  const _NotificationTile({required this.item});

  final NotificationModel item;

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    return Container(
      color: item.isRead
          ? Colors.transparent
          : AppColors.surfaceContainerLow.withValues(alpha: 0.5),
      child: ListTile(
        contentPadding: const EdgeInsets.symmetric(
          horizontal: AppSpacing.md,
          vertical: AppSpacing.xs,
        ),
        leading: CircleAvatar(
          backgroundColor: item.iconColor.withValues(alpha: 0.15),
          child: Icon(item.icon, color: item.iconColor, size: 20),
        ),
        title: Row(
          mainAxisAlignment: MainAxisAlignment.spaceBetween,
          children: [
            Expanded(
              child: Text(
                item.title,
                style: AppTypography.bodyMd.copyWith(
                  fontWeight:
                      item.isRead ? FontWeight.w500 : FontWeight.w700,
                ),
                overflow: TextOverflow.ellipsis,
              ),
            ),
            Text(
              item.relativeTime,
              style: AppTypography.bodySm.copyWith(
                color: AppColors.outline,
                fontSize: 11,
              ),
            ),
          ],
        ),
        subtitle: Padding(
          padding: const EdgeInsets.only(top: 4),
          child: Text(
            item.message,
            style: AppTypography.bodySm.copyWith(
              color: AppColors.onSurfaceVariant,
            ),
            maxLines: 2,
            overflow: TextOverflow.ellipsis,
          ),
        ),
        trailing: IconButton(
          icon: const Icon(Icons.close, size: 16),
          color: AppColors.onSurfaceVariant.withValues(alpha: 0.6),
          tooltip: 'Dismiss',
          onPressed: () {
            ref.read(notificationsProvider.notifier).delete(item.id);
          },
        ),
        onTap: () {
          if (!item.isRead) {
            ref.read(notificationsProvider.notifier).markRead(item.id);
          }
          // Dismiss notification modal dialog
          Navigator.of(context).pop();

          // Intelligent navigation routing
          if (item.type == 'whatsapp_reply') {
            Navigator.of(context).push(
              MaterialPageRoute(
                builder: (_) => const WhatsAppInboxScreen(),
              ),
            );
          } else if (item.type == 'lab_ready' || item.type == 'eye_lab_ready') {
            final isEye = item.title.toLowerCase().contains('eye') ||
                item.message.toLowerCase().contains('eye') ||
                item.message.toLowerCase().contains('lens') ||
                item.type == 'eye_lab_ready';
            if (isEye) {
              Navigator.of(context).push(
                MaterialPageRoute(
                  builder: (_) => const EyeSurgeryScreen(),
                ),
              );
            } else {
              Navigator.of(context).push(
                MaterialPageRoute(
                  builder: (_) => const DentalLabScreen(),
                ),
              );
            }
          } else if (item.type == 'eye_surgery' || item.type == 'eye_surgery_assigned') {
            Navigator.of(context).push(
              MaterialPageRoute(
                builder: (_) => const EyeSurgeryScreen(),
              ),
            );
          } else if (item.type == 'inventory_alert' || item.type == 'low_stock') {
            Navigator.of(context).push(
              MaterialPageRoute(
                builder: (_) => const InventoryManagementScreen(),
              ),
            );
          } else if (item.type.startsWith('task_')) {
            Navigator.of(context).push(
              MaterialPageRoute(
                builder: (_) => const StaffTasksScreen(),
              ),
            );
          } else if (item.type == 'appointment' ||
              item.type == 'appointment_rescheduled') {
            Navigator.of(context).push(
              MaterialPageRoute(
                builder: (_) => const StaffScheduleScreen(),
              ),
            );
          } else if (item.type.startsWith('leave_')) {
            Navigator.of(context).push(
              MaterialPageRoute(
                builder: (_) => const StaffLeaveScreen(),
              ),
            );
          } else if (item.type == 'attendance_exception') {
            Navigator.of(context).push(
              MaterialPageRoute(
                builder: (_) => const StaffAttendanceScreen(),
              ),
            );
          }
        },
      ),
    );
  }
}
