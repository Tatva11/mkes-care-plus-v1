import 'package:flutter/material.dart';

import '../../core/theme/app_breakpoints.dart';
import '../../core/theme/app_colors.dart';
import '../../core/theme/app_spacing.dart';
import '../../core/theme/app_typography.dart';

/// A responsive page header that prevents title crushing and action button overflows.
///
/// Layout Behavior:
/// - Desktop (>= [breakpoint], default 768px): Back button (if any) + Title/Subtitle on left,
///   actions row on right.
/// - Mobile (< [breakpoint]): Back button (if any) + Title/Subtitle on top row;
///   actions wrap cleanly below the title without shrinking the title into a narrow sliver.
class ResponsivePageHeader extends StatelessWidget {
  const ResponsivePageHeader({
    super.key,
    required this.title,
    this.subtitle,
    this.actions = const [],
    this.showBackButton,
    this.onBack,
    this.breakpoint = AppBreakpoints.compact,
    this.titleStyle,
    this.subtitleStyle,
    this.titleMaxLines = 2,
    this.subtitleMaxLines = 3,
    this.spacing = AppSpacing.sm,
    this.padding,
    this.statusBadge,
  });

  /// The main heading text.
  final String title;

  /// Optional secondary subtitle or description text.
  final String? subtitle;

  /// List of action buttons (e.g. Refresh, Add, Filters, Export).
  final List<Widget> actions;

  /// Explicitly control back button visibility. If null, automatically shows
  /// when [Navigator.canPop(context)] is true.
  final bool? showBackButton;

  /// Optional custom callback for back button press.
  final VoidCallback? onBack;

  /// Viewport width breakpoint below which actions move beneath the title. Defaults to 768px.
  final double breakpoint;

  /// Optional text style for the title.
  final TextStyle? titleStyle;

  /// Optional text style for the subtitle.
  final TextStyle? subtitleStyle;

  /// Max lines for title before ellipsis.
  final int titleMaxLines;

  /// Max lines for subtitle before ellipsis.
  final int subtitleMaxLines;

  /// Spacing between header title row and actions in mobile mode.
  final double spacing;

  /// Optional outer padding for the header container.
  final EdgeInsetsGeometry? padding;

  /// Optional status chip or badge displayed beside the title.
  final Widget? statusBadge;

  @override
  Widget build(BuildContext context) {
    final canPop = showBackButton ?? Navigator.of(context).canPop();

    final backButton = canPop
        ? Padding(
            padding: const EdgeInsets.only(right: AppSpacing.sm),
            child: IconButton.filledTonal(
              tooltip: 'Back to previous screen',
              icon: const Icon(Icons.arrow_back),
              onPressed: onBack ?? () => Navigator.of(context).maybePop(),
            ),
          )
        : null;

    return LayoutBuilder(
      builder: (context, constraints) {
        final isNarrow = constraints.maxWidth < breakpoint;

        final titleColumn = Column(
          crossAxisAlignment: CrossAxisAlignment.start,
          mainAxisSize: MainAxisSize.min,
          children: [
            Row(
              mainAxisSize: MainAxisSize.min,
              children: [
                Flexible(
                  child: Text(
                    title,
                    style: titleStyle ??
                        (isNarrow
                            ? AppTypography.headlineMd.copyWith(
                                fontSize: 24,
                                fontWeight: FontWeight.w700,
                              )
                            : AppTypography.displayLg.copyWith(
                                color: AppColors.onBackground,
                              )),
                    maxLines: titleMaxLines,
                    overflow: TextOverflow.ellipsis,
                  ),
                ),
                if (statusBadge != null) ...[
                  const SizedBox(width: AppSpacing.sm),
                  statusBadge!,
                ],
              ],
            ),
            if (subtitle != null && subtitle!.isNotEmpty) ...[
              const SizedBox(height: AppSpacing.base),
              Text(
                subtitle!,
                style: subtitleStyle ??
                    AppTypography.bodyLg.copyWith(
                      color: AppColors.onSurfaceVariant,
                      fontSize: isNarrow ? 14 : 16,
                    ),
                maxLines: subtitleMaxLines,
                overflow: TextOverflow.ellipsis,
              ),
            ],
          ],
        );

        Widget content;

        if (isNarrow) {
          // Mobile: Title row on top, actions wrapped below
          content = Column(
            crossAxisAlignment: CrossAxisAlignment.start,
            mainAxisSize: MainAxisSize.min,
            children: [
              Row(
                crossAxisAlignment: CrossAxisAlignment.center,
                children: [
                  if (backButton != null) backButton,
                  Expanded(child: titleColumn),
                ],
              ),
              if (actions.isNotEmpty) ...[
                SizedBox(height: spacing),
                Wrap(
                  spacing: AppSpacing.sm,
                  runSpacing: AppSpacing.xs,
                  crossAxisAlignment: WrapCrossAlignment.center,
                  children: actions,
                ),
              ],
            ],
          );
        } else {
          // Desktop: Title on left, actions on right in single row
          content = Row(
            crossAxisAlignment: CrossAxisAlignment.start,
            children: [
              if (backButton != null) backButton,
              Expanded(child: titleColumn),
              if (actions.isNotEmpty) ...[
                const SizedBox(width: AppSpacing.md),
                Wrap(
                  spacing: AppSpacing.sm,
                  runSpacing: AppSpacing.xs,
                  crossAxisAlignment: WrapCrossAlignment.center,
                  children: actions,
                ),
              ],
            ],
          );
        }

        if (padding != null) {
          return Padding(padding: padding!, child: content);
        }
        return content;
      },
    );
  }
}
