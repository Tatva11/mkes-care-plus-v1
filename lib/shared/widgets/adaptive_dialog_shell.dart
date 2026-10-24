import 'dart:math' as math;
import 'package:flutter/material.dart';

import '../../core/theme/app_breakpoints.dart';
import '../../core/theme/app_colors.dart';
import '../../core/theme/app_spacing.dart';
import '../../core/theme/app_typography.dart';

/// Computes responsive dialog [BoxConstraints] that adjust to available screen size
/// and virtual keyboard [viewInsets].
class AdaptiveDialogConstraints {
  AdaptiveDialogConstraints._();

  static BoxConstraints getConstraints({
    required BuildContext context,
    double maxPhoneWidth = AppBreakpoints.maxDialogWidthMobile,
    double maxTabletWidth = AppBreakpoints.maxDialogWidthTablet,
    double maxDesktopWidth = AppBreakpoints.maxDialogWidthDesktop,
    double minWidth = 280.0,
    double minHeight = 180.0,
  }) {
    final size = MediaQuery.sizeOf(context);
    final viewInsets = MediaQuery.viewInsetsOf(context);
    final screenWidth = size.width;
    final screenHeight = size.height;

    // Pick maximum width based on viewport tier
    final targetMaxWidth = screenWidth < AppBreakpoints.phone
        ? maxPhoneWidth
        : screenWidth < AppBreakpoints.desktop
            ? maxTabletWidth
            : maxDesktopWidth;

    // Ensure at least 16px margin on each side (32px total) on narrow screens
    final maxAvailableWidth = math.max(minWidth, screenWidth - 32.0);
    final effectiveMaxWidth = math.min(targetMaxWidth, maxAvailableWidth);

    // Calculate maximum available height accounting for keyboard insets and dialog padding
    final maxAvailableHeight = math.max(
      minHeight,
      screenHeight - viewInsets.bottom - 48.0,
    );
    // Allow up to 92% of available space on phone, 85% on desktop
    final heightFactor = screenWidth < AppBreakpoints.phone ? 0.92 : 0.85;
    final effectiveMaxHeight = math.min(
      screenHeight * heightFactor,
      maxAvailableHeight,
    );

    return BoxConstraints(
      minWidth: math.min(minWidth, effectiveMaxWidth),
      maxWidth: effectiveMaxWidth,
      minHeight: math.min(minHeight, effectiveMaxHeight),
      maxHeight: effectiveMaxHeight,
    );
  }
}

/// A responsive, mobile-first dialog shell for MKES CARE+.
///
/// Features:
/// - Fits narrow Android viewports (360px+) with safe horizontal margins.
/// - Caps dialog size on tablet and desktop screens.
/// - Respects virtual keyboard insets automatically.
/// - Scrollable content area by default to prevent [RenderFlex] overflows.
/// - Standardized header and action button layouts.
class AdaptiveDialogShell extends StatelessWidget {
  const AdaptiveDialogShell({
    super.key,
    required this.title,
    this.subtitle,
    this.icon,
    this.iconColor,
    required this.content,
    this.actions,
    this.maxPhoneWidth = AppBreakpoints.maxDialogWidthMobile,
    this.maxTabletWidth = AppBreakpoints.maxDialogWidthTablet,
    this.maxDesktopWidth = AppBreakpoints.maxDialogWidthDesktop,
    this.isScrollable = true,
    this.contentPadding = const EdgeInsets.all(AppSpacing.md),
    this.insetPadding =
        const EdgeInsets.symmetric(horizontal: 16, vertical: 24),
    this.onClose,
    this.headerTrailing,
  });

  final String title;
  final String? subtitle;
  final IconData? icon;
  final Color? iconColor;
  final Widget content;
  final List<Widget>? actions;
  final double maxPhoneWidth;
  final double maxTabletWidth;
  final double maxDesktopWidth;
  final bool isScrollable;
  final EdgeInsetsGeometry contentPadding;
  final EdgeInsets insetPadding;
  final VoidCallback? onClose;
  final Widget? headerTrailing;

  /// Convenience helper to compute dialog constraints for standard AlertDialogs and Dialogs.
  static BoxConstraints constraintsFor(
    BuildContext context, {
    double? maxWidth,
    double maxMobileWidth = AppBreakpoints.maxDialogWidthMobile,
    double maxTabletWidth = AppBreakpoints.maxDialogWidthTablet,
    double maxDesktopWidth = AppBreakpoints.maxDialogWidthDesktop,
    double minWidth = 280.0,
    double minHeight = 180.0,
  }) {
    return AdaptiveDialogConstraints.getConstraints(
      context: context,
      maxPhoneWidth: maxWidth != null ? math.min(maxWidth, maxMobileWidth) : maxMobileWidth,
      maxTabletWidth: maxWidth != null ? math.min(maxWidth, maxTabletWidth) : maxTabletWidth,
      maxDesktopWidth: maxWidth ?? maxDesktopWidth,
      minWidth: minWidth,
      minHeight: minHeight,
    );
  }

  @override
  Widget build(BuildContext context) {
    final constraints = AdaptiveDialogConstraints.getConstraints(
      context: context,
      maxPhoneWidth: maxPhoneWidth,
      maxTabletWidth: maxTabletWidth,
      maxDesktopWidth: maxDesktopWidth,
    );

    return Dialog(
      shape: RoundedRectangleBorder(
        borderRadius: BorderRadius.circular(AppSpacing.radiusXl),
      ),
      insetPadding: insetPadding,
      backgroundColor: AppColors.surfaceContainerLowest,
      child: ConstrainedBox(
        constraints: constraints,
        child: Column(
          mainAxisSize: MainAxisSize.min,
          crossAxisAlignment: CrossAxisAlignment.stretch,
          children: [
            // ── Header ──────────────────────────────────────────────
            Container(
              padding: const EdgeInsets.symmetric(
                horizontal: AppSpacing.md,
                vertical: AppSpacing.sm,
              ),
              decoration: const BoxDecoration(
                border: Border(
                  bottom: BorderSide(color: AppColors.outlineVariant),
                ),
              ),
              child: Row(
                children: [
                  if (icon != null) ...[
                    Container(
                      padding: const EdgeInsets.all(AppSpacing.xs),
                      decoration: BoxDecoration(
                        color: (iconColor ?? AppColors.primary)
                            .withValues(alpha: 0.12),
                        borderRadius:
                            BorderRadius.circular(AppSpacing.radiusSm),
                      ),
                      child: Icon(
                        icon,
                        size: 20,
                        color: iconColor ?? AppColors.primary,
                      ),
                    ),
                    const SizedBox(width: AppSpacing.sm),
                  ],
                  Expanded(
                    child: Column(
                      crossAxisAlignment: CrossAxisAlignment.start,
                      mainAxisSize: MainAxisSize.min,
                      children: [
                        Text(
                          title,
                          style: AppTypography.headlineMd.copyWith(
                            fontSize: 18,
                            fontWeight: FontWeight.w700,
                          ),
                          overflow: TextOverflow.ellipsis,
                        ),
                        if (subtitle != null && subtitle!.isNotEmpty) ...[
                          const SizedBox(height: 2),
                          Text(
                            subtitle!,
                            style: AppTypography.bodySm.copyWith(
                              color: AppColors.onSurfaceVariant,
                            ),
                            overflow: TextOverflow.ellipsis,
                          ),
                        ],
                      ],
                    ),
                  ),
                  if (headerTrailing != null) headerTrailing!,
                  IconButton(
                    icon: const Icon(Icons.close, size: 20),
                    tooltip: 'Close',
                    onPressed:
                        onClose ?? () => Navigator.of(context).maybePop(),
                  ),
                ],
              ),
            ),

            // ── Content ─────────────────────────────────────────────
            Flexible(
              child: isScrollable
                  ? SingleChildScrollView(
                      padding: contentPadding,
                      child: content,
                    )
                  : Padding(
                      padding: contentPadding,
                      child: content,
                    ),
            ),

            // ── Actions Footer ──────────────────────────────────────
            if (actions != null && actions!.isNotEmpty)
              Container(
                padding: const EdgeInsets.all(AppSpacing.md),
                decoration: const BoxDecoration(
                  border: Border(
                    top: BorderSide(color: AppColors.outlineVariant),
                  ),
                ),
                child: Row(
                  mainAxisAlignment: MainAxisAlignment.end,
                  children: [
                    for (int i = 0; i < actions!.length; i++) ...[
                      if (i > 0) const SizedBox(width: AppSpacing.sm),
                      actions![i],
                    ],
                  ],
                ),
              ),
          ],
        ),
      ),
    );
  }
}
