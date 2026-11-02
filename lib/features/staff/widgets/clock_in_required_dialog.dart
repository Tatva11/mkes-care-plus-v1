import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';

import '../../../core/theme/app_colors.dart';
import '../../../core/theme/app_spacing.dart';
import '../../../core/theme/app_typography.dart';
import '../../staff_portal/screens/staff_dashboard_screen.dart';
import '../../staff_portal/widgets/staff_shell.dart';
import '../providers/attendance_provider.dart';

/// Shows the mandatory clock-in required dialog.
Future<void> showClockInRequiredDialog(
    BuildContext context, WidgetRef ref) async {
  return showDialog<void>(
    context: context,
    barrierDismissible: true,
    builder: (dialogCtx) => ClockInRequiredDialog(parentRef: ref),
  );
}

/// Dialog displayed when unclocked staff attempts an operational activity.
class ClockInRequiredDialog extends StatelessWidget {
  final WidgetRef? parentRef;

  const ClockInRequiredDialog({super.key, this.parentRef});

  @override
  Widget build(BuildContext context) {
    return AlertDialog(
      shape: RoundedRectangleBorder(
        borderRadius: BorderRadius.circular(AppSpacing.radiusMd),
      ),
      title: Row(
        children: [
          Icon(Icons.access_time_filled, color: AppColors.error, size: 24),
          const SizedBox(width: AppSpacing.sm),
          const Text('Clock-In Required'),
        ],
      ),
      content: const Text(
        'You must clock in before performing any clinic operations. Please clock in to continue.',
        style: TextStyle(fontSize: 14),
      ),
      actions: [
        TextButton(
          onPressed: () => Navigator.of(context).pop(),
          child: const Text('Cancel'),
        ),
        Consumer(
          builder: (context, ref, _) {
            final effectiveRef = parentRef ?? ref;
            return FilledButton.icon(
              key: const Key('clock_in_now_button'),
              style: FilledButton.styleFrom(
                backgroundColor: AppColors.primary,
              ),
              onPressed: () {
                Navigator.of(context).pop();
                try {
                  effectiveRef.read(staffNavProvider.notifier).state =
                      StaffNavItem.attendance;
                } catch (_) {}
                if (Navigator.of(context).canPop()) {
                  Navigator.of(context).popUntil((route) => route.isFirst);
                }
              },
              icon: const Icon(Icons.login, size: 16),
              label: const Text('Clock In Now'),
            );
          },
        ),
      ],
    );
  }
}

/// Compact, responsive top notification banner alerting staff that clock-in is required.
class ClockInRequiredBanner extends ConsumerWidget {
  const ClockInRequiredBanner({super.key});

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    final statusAsync = ref.watch(staffClockInStatusProvider);

    return statusAsync.when(
      data: (isClockedIn) {
        if (isClockedIn) return const SizedBox.shrink();

        void onClockIn() {
          ref.read(staffNavProvider.notifier).state = StaffNavItem.attendance;
          if (Navigator.of(context).canPop()) {
            Navigator.of(context).popUntil((route) => route.isFirst);
          }
        }

        return LayoutBuilder(
          builder: (context, constraints) {
            final isNarrow = constraints.maxWidth < 420;
            final isExtraNarrow = constraints.maxWidth < 350;

            if (isNarrow) {
              return Container(
                key: const Key('clock_in_required_banner'),
                margin: const EdgeInsets.only(bottom: AppSpacing.sm),
                padding: const EdgeInsets.symmetric(
                  horizontal: AppSpacing.sm,
                  vertical: AppSpacing.xs + 2,
                ),
                decoration: BoxDecoration(
                  color: AppColors.errorContainer.withValues(alpha: 0.12),
                  borderRadius: BorderRadius.circular(AppSpacing.radiusSm),
                  border:
                      Border.all(color: AppColors.error.withValues(alpha: 0.45)),
                ),
                child: Row(
                  crossAxisAlignment: CrossAxisAlignment.center,
                  children: [
                    const Icon(
                      Icons.warning_amber_rounded,
                      color: AppColors.error,
                      size: 20,
                    ),
                    const SizedBox(width: AppSpacing.xs),
                    Expanded(
                      child: Column(
                        crossAxisAlignment: CrossAxisAlignment.start,
                        mainAxisSize: MainAxisSize.min,
                        children: [
                          Text(
                            'Clock-In Required',
                            style: AppTypography.bodySm.copyWith(
                              fontWeight: FontWeight.bold,
                              color: AppColors.error,
                              fontSize: 12.5,
                            ),
                          ),
                          Text(
                            'You must clock in before you can make any changes.',
                            style: AppTypography.bodySm.copyWith(
                              color: AppColors.onSurface,
                              fontSize: 11.0,
                            ),
                            maxLines: 2,
                            overflow: TextOverflow.ellipsis,
                          ),
                        ],
                      ),
                    ),
                    const SizedBox(width: AppSpacing.xs),
                    FilledButton.icon(
                      key: const Key('banner_clock_in_now_button'),
                      onPressed: onClockIn,
                      style: FilledButton.styleFrom(
                        backgroundColor: AppColors.error,
                        foregroundColor: Colors.white,
                        visualDensity: VisualDensity.compact,
                        padding: const EdgeInsets.symmetric(
                          horizontal: 8,
                          vertical: 4,
                        ),
                        minimumSize: const Size(0, 32),
                      ),
                      icon: const Icon(Icons.login, size: 14),
                      label: Text(
                        isExtraNarrow ? 'Clock In' : 'Clock In Now',
                        style: const TextStyle(
                          fontSize: 11.0,
                          fontWeight: FontWeight.bold,
                        ),
                      ),
                    ),
                  ],
                ),
              );
            }

            return Container(
              key: const Key('clock_in_required_banner'),
              margin: const EdgeInsets.only(bottom: AppSpacing.sm),
              padding: const EdgeInsets.symmetric(
                horizontal: AppSpacing.md,
                vertical: AppSpacing.sm,
              ),
              decoration: BoxDecoration(
                color: AppColors.errorContainer.withValues(alpha: 0.12),
                borderRadius: BorderRadius.circular(AppSpacing.radiusMd),
                border: Border.all(color: AppColors.error.withValues(alpha: 0.5)),
              ),
              child: Row(
                crossAxisAlignment: CrossAxisAlignment.center,
                children: [
                  const Icon(
                    Icons.warning_amber_rounded,
                    color: AppColors.error,
                    size: 22,
                  ),
                  const SizedBox(width: AppSpacing.sm),
                  Expanded(
                    child: Column(
                      crossAxisAlignment: CrossAxisAlignment.start,
                      mainAxisSize: MainAxisSize.min,
                      children: [
                        Text(
                          'Clock-In Required',
                          style: AppTypography.bodyMd.copyWith(
                            fontWeight: FontWeight.bold,
                            color: AppColors.error,
                          ),
                        ),
                        const SizedBox(height: 2),
                        Text(
                          'You must clock in before you can make any changes.',
                          style: AppTypography.bodySm.copyWith(
                            color: AppColors.onSurface,
                          ),
                        ),
                      ],
                    ),
                  ),
                  const SizedBox(width: AppSpacing.md),
                  FilledButton.icon(
                    key: const Key('banner_clock_in_now_button'),
                    onPressed: onClockIn,
                    style: FilledButton.styleFrom(
                      backgroundColor: AppColors.error,
                      foregroundColor: Colors.white,
                      padding: const EdgeInsets.symmetric(
                        horizontal: 14,
                        vertical: 8,
                      ),
                    ),
                    icon: const Icon(Icons.login, size: 16),
                    label: const Text('Clock In Now'),
                  ),
                ],
              ),
            );
          },
        );
      },
      loading: () => const SizedBox.shrink(),
      error: (_, __) => const SizedBox.shrink(),
    );
  }
}

