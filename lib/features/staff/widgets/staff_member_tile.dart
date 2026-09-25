import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';

import '../../../core/theme/app_colors.dart';
import '../../../core/theme/app_spacing.dart';
import '../../../core/theme/app_typography.dart';
import '../../admin/models/user_profile.dart';
import '../../admin/providers/users_provider.dart';
import '../../admin/screens/user_form_dialog.dart';

enum StaffStatus { present, onLeave, offDuty }

/// A single row in the Staff Roster.
///
/// Displays the staff member's avatar, name, role, status badge, and two
/// direct action buttons:
///   • **Modify** — opens [UserFormDialog] to edit profile fields.
///   • **Activate / Deactivate** — shows a confirmation dialog then calls
///     [UsersNotifier.toggleStatus] directly, without opening the Modify form.
class StaffMemberTile extends ConsumerStatefulWidget {
  const StaffMemberTile({
    super.key,
    required this.user,
    this.showDivider = true,
  });

  final UserProfile user;
  final bool showDivider;

  @override
  ConsumerState<StaffMemberTile> createState() => _StaffMemberTileState();
}

class _StaffMemberTileState extends ConsumerState<StaffMemberTile> {
  bool _statusLoading = false;

  static const _errorContainer = Color(0xFFFFDAD6);
  static const _secondaryFixed = Color(0xFFFFD8EB);

  // ── Status helpers ────────────────────────────────────────────────────────

  StaffStatus get _status =>
      widget.user.isActive ? StaffStatus.present : StaffStatus.offDuty;

  Color get _statusBg {
    switch (_status) {
      case StaffStatus.present:
        return AppColors.surfaceContainerLow;
      case StaffStatus.onLeave:
        return _errorContainer.withValues(alpha: 0.25);
      case StaffStatus.offDuty:
        return AppColors.surfaceContainerHigh;
    }
  }

  Color get _statusTextColor {
    switch (_status) {
      case StaffStatus.present:
        return AppColors.primaryContainer;
      case StaffStatus.onLeave:
        return AppColors.secondary;
      case StaffStatus.offDuty:
        return AppColors.onSurfaceVariant;
    }
  }

  Color get _statusDotColor {
    switch (_status) {
      case StaffStatus.present:
        return AppColors.primaryContainer;
      case StaffStatus.onLeave:
        return AppColors.secondary;
      case StaffStatus.offDuty:
        return AppColors.onSurfaceVariant;
    }
  }

  String get _statusLabel {
    switch (_status) {
      case StaffStatus.present:
        return 'Active';
      case StaffStatus.onLeave:
        return 'On Leave';
      case StaffStatus.offDuty:
        return 'Inactive';
    }
  }

  Color get _avatarBg {
    switch (widget.user.departmentName ?? widget.user.department) {
      case 'Dental':
        return _secondaryFixed.withValues(alpha: 0.5);
      case 'OPD':
        return AppColors.primaryContainer.withValues(alpha: 0.15);
      default:
        return const Color(0xFFE5E2E1);
    }
  }

  Color get _avatarTextColor {
    switch (widget.user.departmentName ?? widget.user.department) {
      case 'Dental':
        return AppColors.secondary;
      case 'OPD':
        return AppColors.primaryContainer;
      default:
        return AppColors.onSurfaceVariant;
    }
  }

  // ── Actions ───────────────────────────────────────────────────────────────

  void _openModify() {
    showDialog<void>(
      context: context,
      barrierDismissible: false,
      builder: (_) => UserFormDialog(user: widget.user),
    );
  }

  Future<void> _confirmToggleStatus() async {
    final isCurrentlyActive = widget.user.isActive;
    final action = isCurrentlyActive ? 'Deactivate' : 'Activate';
    final name = widget.user.fullName;

    final confirmed = await showDialog<bool>(
      context: context,
      builder: (ctx) => AlertDialog(
        title: Text('$action $name?'),
        content: Text(
          isCurrentlyActive
              ? '$name will be marked inactive and will lose access to the staff portal.'
              : '$name will be reactivated and can log in to the staff portal again.',
        ),
        actions: [
          TextButton(
            onPressed: () => Navigator.of(ctx).pop(false),
            child: const Text('Cancel'),
          ),
          FilledButton(
            onPressed: () => Navigator.of(ctx).pop(true),
            style: isCurrentlyActive
                ? FilledButton.styleFrom(backgroundColor: AppColors.error)
                : null,
            child: Text(action),
          ),
        ],
      ),
    );

    if (confirmed != true) return;
    if (!mounted) return;

    setState(() => _statusLoading = true);
    try {
      await ref
          .read(usersProvider.notifier)
          .toggleStatus(widget.user.id, !isCurrentlyActive);
      // List is refreshed by the notifier; no extra setState needed.
    } catch (e) {
      if (!mounted) return;
      ScaffoldMessenger.of(context).showSnackBar(
        SnackBar(
          content: Text('Failed to $action ${widget.user.fullName}: $e'),
          backgroundColor: AppColors.error,
        ),
      );
    } finally {
      if (mounted) setState(() => _statusLoading = false);
    }
  }

  // ── Build ─────────────────────────────────────────────────────────────────

  @override
  Widget build(BuildContext context) {
    final initials = widget.user.fullName
        .split(' ')
        .map((w) => w.isNotEmpty ? w[0] : '')
        .take(2)
        .join()
        .toUpperCase();

    return Column(
      children: [
        Padding(
          padding: const EdgeInsets.symmetric(
            vertical: AppSpacing.xs,
            horizontal: AppSpacing.xs,
          ),
          child: Row(
            crossAxisAlignment: CrossAxisAlignment.center,
            children: [
              // ── Avatar ───────────────────────────────────────────────────
              Container(
                width: 40,
                height: 40,
                decoration: BoxDecoration(
                  color: _avatarBg,
                  shape: BoxShape.circle,
                  border: Border.all(
                    color: AppColors.outlineVariant.withValues(alpha: 0.5),
                  ),
                ),
                child: Center(
                  child: Text(
                    initials,
                    style: AppTypography.labelCaps.copyWith(
                      color: _avatarTextColor,
                      fontWeight: FontWeight.w700,
                    ),
                  ),
                ),
              ),
              const SizedBox(width: AppSpacing.sm),

              // ── Name + role + contact ─────────────────────────────────────
              Expanded(
                child: Column(
                  crossAxisAlignment: CrossAxisAlignment.start,
                  children: [
                    Text(
                      widget.user.fullName,
                      style: AppTypography.bodyMd
                          .copyWith(fontWeight: FontWeight.w600),
                      overflow: TextOverflow.ellipsis,
                      maxLines: 1,
                    ),
                    Text(
                      '${widget.user.designation ?? widget.user.role.toUpperCase()} '
                      '• ${widget.user.departmentName ?? widget.user.department ?? '—'}',
                      style: AppTypography.bodySm,
                      overflow: TextOverflow.ellipsis,
                      maxLines: 1,
                    ),
                    Text(
                      widget.user.email,
                      style:
                          AppTypography.bodySm.copyWith(fontSize: 11),
                      overflow: TextOverflow.ellipsis,
                      maxLines: 1,
                    ),
                  ],
                ),
              ),
              const SizedBox(width: AppSpacing.xs),

              // ── Status badge + action buttons ────────────────────────────
              Column(
                crossAxisAlignment: CrossAxisAlignment.end,
                mainAxisSize: MainAxisSize.min,
                children: [
                  // Status badge
                  Container(
                    padding: const EdgeInsets.symmetric(
                      horizontal: AppSpacing.xs,
                      vertical: AppSpacing.base,
                    ),
                    decoration: BoxDecoration(
                      color: _statusBg,
                      borderRadius:
                          BorderRadius.circular(AppSpacing.radiusSm),
                    ),
                    child: Row(
                      mainAxisSize: MainAxisSize.min,
                      children: [
                        Container(
                          width: 6,
                          height: 6,
                          decoration: BoxDecoration(
                            color: _statusDotColor,
                            shape: BoxShape.circle,
                          ),
                        ),
                        const SizedBox(width: AppSpacing.base),
                        Text(
                          _statusLabel,
                          style: AppTypography.labelCaps
                              .copyWith(color: _statusTextColor),
                        ),
                      ],
                    ),
                  ),
                  const SizedBox(height: AppSpacing.xs),

                  // Action buttons row
                  Row(
                    mainAxisSize: MainAxisSize.min,
                    children: [
                      // Modify button
                      _ActionChip(
                        label: 'Modify',
                        icon: Icons.edit_outlined,
                        onTap: _openModify,
                        foreground: AppColors.primary,
                        background: AppColors.primaryFixed
                            .withValues(alpha: 0.5),
                      ),
                      const SizedBox(width: AppSpacing.base),

                      // Activate / Deactivate button
                      _statusLoading
                          ? const SizedBox(
                              width: 20,
                              height: 20,
                              child: CircularProgressIndicator(
                                strokeWidth: 2,
                              ),
                            )
                          : _ActionChip(
                              label: widget.user.isActive
                                  ? 'Deactivate'
                                  : 'Activate',
                              icon: widget.user.isActive
                                  ? Icons.block_outlined
                                  : Icons.check_circle_outline,
                              onTap: _confirmToggleStatus,
                              foreground: widget.user.isActive
                                  ? AppColors.error
                                  : AppColors.primaryContainer,
                              background: widget.user.isActive
                                  ? _errorContainer.withValues(alpha: 0.5)
                                  : AppColors.surfaceContainerLow,
                            ),
                    ],
                  ),
                ],
              ),
            ],
          ),
        ),
        if (widget.showDivider)
          Divider(
            height: 1,
            thickness: 1,
            color: AppColors.outlineVariant.withValues(alpha: 0.4),
            indent: AppSpacing.xs,
            endIndent: AppSpacing.xs,
          ),
      ],
    );
  }
}

// ── _ActionChip ────────────────────────────────────────────────────────────────

/// Small pill-shaped tappable chip used for Modify and Activate/Deactivate.
class _ActionChip extends StatelessWidget {
  const _ActionChip({
    required this.label,
    required this.icon,
    required this.onTap,
    required this.foreground,
    required this.background,
  });

  final String label;
  final IconData icon;
  final VoidCallback onTap;
  final Color foreground;
  final Color background;

  @override
  Widget build(BuildContext context) {
    return Material(
      color: background,
      borderRadius: BorderRadius.circular(AppSpacing.radiusSm),
      child: InkWell(
        onTap: onTap,
        borderRadius: BorderRadius.circular(AppSpacing.radiusSm),
        child: Padding(
          padding: const EdgeInsets.symmetric(
            horizontal: AppSpacing.xs,
            vertical: AppSpacing.base,
          ),
          child: Row(
            mainAxisSize: MainAxisSize.min,
            children: [
              Icon(icon, size: 12, color: foreground),
              const SizedBox(width: 3),
              Text(
                label,
                style: AppTypography.labelCaps.copyWith(
                  color: foreground,
                  fontSize: 10,
                ),
              ),
            ],
          ),
        ),
      ),
    );
  }
}
