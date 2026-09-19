import 'package:flutter/material.dart';

import '../../core/theme/app_colors.dart';
import '../../core/theme/app_spacing.dart';
import '../../core/theme/app_typography.dart';

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

class NotificationCenterButton extends StatefulWidget {
  const NotificationCenterButton({super.key});

  @override
  State<NotificationCenterButton> createState() => _NotificationCenterButtonState();
}

class _NotificationCenterButtonState extends State<NotificationCenterButton> {
  final List<NotificationItem> _notifications = [
    NotificationItem(
      id: '1',
      title: 'New Appointment',
      message: 'Sarah Jenkins scheduled an Optometry checkup for 2:30 PM today.',
      time: '5m ago',
      icon: Icons.calendar_today_outlined,
      iconColor: AppColors.primary,
      isRead: false,
    ),
    NotificationItem(
      id: '2',
      title: 'Inventory Alert',
      message: 'Progressive Lens Blanks (CR-39) reached critical low threshold (4 remaining).',
      time: '25m ago',
      icon: Icons.inventory_2_outlined,
      iconColor: AppColors.error,
      isRead: false,
    ),
    NotificationItem(
      id: '3',
      title: 'Staff Leave Request',
      message: 'Dr. Michael Smith submitted a PTO request for Friday, Aug 15.',
      time: '1h ago',
      icon: Icons.event_busy_outlined,
      iconColor: AppColors.secondary,
      isRead: false,
    ),
    NotificationItem(
      id: '4',
      title: 'AI Insight Available',
      message: 'Patient triage flow peak predicted at 11:00 AM. Consider adjusting desk support.',
      time: '2h ago',
      icon: Icons.auto_awesome,
      iconColor: AppColors.primaryContainer,
      isRead: true,
    ),
    NotificationItem(
      id: '5',
      title: 'Patient Registration',
      message: 'New patient profile registered: Robert Wilson (#P-4095).',
      time: '3h ago',
      icon: Icons.person_add_alt_outlined,
      iconColor: AppColors.tertiary,
      isRead: true,
    ),
  ];

  int get _unreadCount => _notifications.where((n) => !n.isRead).length;

  void _showNotificationDialog() {
    showDialog(
      context: context,
      builder: (context) => StatefulBuilder(
        builder: (context, setModalState) {
          return Dialog(
            alignment: Alignment.topRight,
            insetPadding: const EdgeInsets.only(top: 60, right: 16, left: 16),
            shape: RoundedRectangleBorder(
              borderRadius: BorderRadius.circular(AppSpacing.radiusXl),
              side: const BorderSide(color: AppColors.outlineVariant),
            ),
            child: Container(
              width: 400,
              constraints: const BoxConstraints(maxHeight: 520),
              decoration: BoxDecoration(
                color: AppColors.surfaceContainerLowest,
                borderRadius: BorderRadius.circular(AppSpacing.radiusXl),
              ),
              child: Column(
                children: [
                  // Modal Header
                  Padding(
                    padding: const EdgeInsets.all(AppSpacing.md),
                    child: Row(
                      mainAxisAlignment: MainAxisAlignment.spaceBetween,
                      children: [
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
                              if (_unreadCount > 0) ...[
                                const SizedBox(width: AppSpacing.xs),
                                Container(
                                  padding: const EdgeInsets.symmetric(
                                    horizontal: 8,
                                    vertical: 2,
                                  ),
                                  decoration: BoxDecoration(
                                    color: AppColors.primaryContainer,
                                    borderRadius: BorderRadius.circular(12),
                                  ),
                                  child: Text(
                                    '$_unreadCount new',
                                    style: AppTypography.labelCaps.copyWith(
                                      color: AppColors.onPrimaryContainer,
                                      fontSize: 10,
                                    ),
                                  ),
                                ),
                              ],
                            ],
                          ),
                        ),
                        Row(
                          children: [
                            if (_unreadCount > 0)
                              TextButton(
                                onPressed: () {
                                  setState(() {
                                    for (var n in _notifications) {
                                      n.isRead = true;
                                    }
                                  });
                                  setModalState(() {});
                                },
                                child: Text(
                                  'Mark as Read',
                                  style: AppTypography.labelCaps.copyWith(
                                    color: AppColors.primary,
                                  ),
                                ),
                              ),
                            if (_notifications.isNotEmpty)
                              IconButton(
                                icon: const Icon(Icons.delete_outline, size: 20),
                                color: AppColors.onSurfaceVariant,
                                tooltip: 'Clear All',
                                onPressed: () {
                                  setState(() {
                                    _notifications.clear();
                                  });
                                  setModalState(() {});
                                },
                              ),
                          ],
                        ),
                      ],
                    ),
                  ),
                  const Divider(height: 1),
                  // Notification List
                  Expanded(
                    child: _notifications.isEmpty
                        ? Center(
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
                                    'No notifications',
                                    style: AppTypography.bodyMd.copyWith(
                                      color: AppColors.onSurfaceVariant,
                                    ),
                                  ),
                                ],
                              ),
                            ),
                          )
                        : ListView.separated(
                            padding: EdgeInsets.zero,
                            itemCount: _notifications.length,
                            separatorBuilder: (_, __) => const Divider(height: 1),
                            itemBuilder: (context, index) {
                              final item = _notifications[index];
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
                                            fontWeight: item.isRead
                                                ? FontWeight.w500
                                                : FontWeight.w700,
                                          ),
                                          overflow: TextOverflow.ellipsis,
                                        ),
                                      ),
                                      Text(
                                        item.time,
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
                                  onTap: () {
                                    setState(() {
                                      item.isRead = true;
                                    });
                                    setModalState(() {});
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
        },
      ),
    );
  }

  @override
  Widget build(BuildContext context) {
    return Stack(
      alignment: Alignment.center,
      children: [
        IconButton(
          icon: const Icon(Icons.notifications_none),
          color: AppColors.onSurfaceVariant,
          iconSize: 22,
          onPressed: _showNotificationDialog,
        ),
        if (_unreadCount > 0)
          Positioned(
            top: 10,
            right: 10,
            child: Container(
              padding: const EdgeInsets.all(4),
              decoration: const BoxDecoration(
                color: AppColors.error,
                shape: BoxShape.circle,
              ),
              constraints: const BoxConstraints(
                minWidth: 16,
                minHeight: 16,
              ),
              child: Text(
                '$_unreadCount',
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
}
