import 'package:flutter/material.dart';

import '../../core/theme/app_colors.dart';
import '../../core/theme/app_spacing.dart';
import '../../core/theme/app_typography.dart';

class MkesSecondaryButton extends StatelessWidget {
  const MkesSecondaryButton({
    super.key,
    required this.label,
    this.icon,
    this.onPressed,
    this.isFullWidth = true,
    this.width,
    this.isLoading = false,
  });

  final String label;
  final IconData? icon;
  final VoidCallback? onPressed;

  /// Whether the button should stretch to fill the available horizontal width.
  /// Defaults to `true` to preserve backward compatibility for existing screens.
  /// Set to `false` when placing inside unconstrained layouts like [Row] or [Wrap].
  final bool isFullWidth;

  /// Optional explicit width override.
  final double? width;

  /// Shows a centered loading indicator and disables the button when true.
  final bool isLoading;

  @override
  Widget build(BuildContext context) {
    final effectiveOnPressed = isLoading ? null : onPressed;

    final childWidget = isLoading
        ? const SizedBox(
            width: 20,
            height: 20,
            child: CircularProgressIndicator(
              strokeWidth: 2,
              color: AppColors.primary,
            ),
          )
        : Row(
            mainAxisSize: isFullWidth && width == null
                ? MainAxisSize.max
                : MainAxisSize.min,
            mainAxisAlignment: MainAxisAlignment.center,
            children: [
              if (icon != null) ...[
                Icon(icon, size: 20, color: AppColors.secondary),
                const SizedBox(width: AppSpacing.xs),
              ],
              Text(label, style: AppTypography.labelCaps),
            ],
          );

    final button = OutlinedButton(
      onPressed: effectiveOnPressed,
      style: OutlinedButton.styleFrom(
        backgroundColor: AppColors.surfaceContainerLow,
        foregroundColor: AppColors.onSurface,
        minimumSize: const Size(64, 48),
        padding: const EdgeInsets.symmetric(
          horizontal: AppSpacing.md,
          vertical: AppSpacing.sm,
        ),
        side: const BorderSide(color: AppColors.outlineVariant),
        shape: RoundedRectangleBorder(
          borderRadius: BorderRadius.circular(AppSpacing.radiusMd),
        ),
      ),
      child: childWidget,
    );

    if (width != null) {
      return SizedBox(width: width, child: button);
    }
    if (isFullWidth) {
      return SizedBox(width: double.infinity, child: button);
    }
    return button;
  }
}
