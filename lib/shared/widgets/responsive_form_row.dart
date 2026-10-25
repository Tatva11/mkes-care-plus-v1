import 'package:flutter/material.dart';

import '../../core/theme/app_breakpoints.dart';
import '../../core/theme/app_spacing.dart';

/// A responsive form-row helper that renders input fields side-by-side on wide viewports
/// and stacks them vertically on narrow mobile viewports.
///
/// Ensures inputs do not get crushed horizontally below [breakpoint] (defaults to 500px).
/// Preserves controllers, focus nodes, validation states, and callbacks unmodified.
class ResponsiveFormRow extends StatelessWidget {
  const ResponsiveFormRow({
    super.key,
    required this.children,
    this.spacing = AppSpacing.md,
    this.runSpacing = AppSpacing.sm,
    this.breakpoint = AppBreakpoints.formRow,
    this.crossAxisAlignment = CrossAxisAlignment.start,
    this.flexes,
  }) : assert(
          flexes == null || flexes.length == children.length,
          'When provided, flexes length must match children length',
        );

  /// The list of form field widgets to lay out.
  final List<Widget> children;

  /// Horizontal spacing between items when in row mode.
  final double spacing;

  /// Vertical spacing between items when stacked in column mode.
  final double runSpacing;

  /// Width below which items stack vertically (defaults to 500px).
  final double breakpoint;

  /// Vertical cross-axis alignment for items in row mode.
  final CrossAxisAlignment crossAxisAlignment;

  /// Optional flex values for children in row mode. Defaults to 1 for all items.
  final List<int>? flexes;

  @override
  Widget build(BuildContext context) {
    if (children.isEmpty) return const SizedBox.shrink();
    if (children.length == 1) return children.first;

    return LayoutBuilder(
      builder: (context, constraints) {
        final shouldStack = constraints.maxWidth < breakpoint;

        if (shouldStack) {
          return Column(
            crossAxisAlignment: CrossAxisAlignment.stretch,
            mainAxisSize: MainAxisSize.min,
            children: [
              for (int i = 0; i < children.length; i++) ...[
                if (i > 0) SizedBox(height: runSpacing),
                children[i],
              ],
            ],
          );
        }

        return Row(
          crossAxisAlignment: crossAxisAlignment,
          children: [
            for (int i = 0; i < children.length; i++) ...[
              if (i > 0) SizedBox(width: spacing),
              Expanded(
                flex: flexes != null ? flexes![i] : 1,
                child: children[i],
              ),
            ],
          ],
        );
      },
    );
  }
}
