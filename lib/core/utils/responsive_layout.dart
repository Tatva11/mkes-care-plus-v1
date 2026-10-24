import 'package:flutter/widgets.dart';

import '../theme/app_breakpoints.dart';
import '../theme/app_spacing.dart';

/// Reusable responsive layout helper for MKES CARE+.
///
/// Provides responsive tier queries, layout switching helpers, and margin calculations
/// based on available width rather than device brand or platform.
class ResponsiveLayout {
  ResponsiveLayout._();

  /// Returns true if the screen width is strictly below [AppBreakpoints.phone] (< 600px).
  static bool isPhone(BuildContext context) =>
      MediaQuery.sizeOf(context).width < AppBreakpoints.phone;

  /// Returns true if the screen width is below [AppBreakpoints.compact] (< 768px).
  static bool isCompact(BuildContext context) =>
      MediaQuery.sizeOf(context).width < AppBreakpoints.compact;

  /// Returns true if the screen width is between 600px and 1024px.
  static bool isTablet(BuildContext context) {
    final width = MediaQuery.sizeOf(context).width;
    return width >= AppBreakpoints.phone && width < AppBreakpoints.desktop;
  }

  /// Returns true if the screen width is 1024px or wider.
  static bool isDesktop(BuildContext context) =>
      MediaQuery.sizeOf(context).width >= AppBreakpoints.desktop;

  /// Returns true if the screen width is 1440px or wider.
  static bool isLargeDesktop(BuildContext context) =>
      MediaQuery.sizeOf(context).width >= AppBreakpoints.largeDesktop;

  /// Standard horizontal page padding (16px on phone/compact, 32px on desktop).
  static double horizontalPadding(BuildContext context) =>
      isCompact(context) ? AppSpacing.marginMobile : AppSpacing.marginDesktop;

  /// Width-based query: returns true if [width] is below [AppBreakpoints.phone].
  static bool isPhoneWidth(double width) => width < AppBreakpoints.phone;

  /// Width-based query: returns true if [width] is below [AppBreakpoints.compact].
  static bool isCompactWidth(double width) => width < AppBreakpoints.compact;

  /// Width-based query: returns true if [width] is in tablet range (600px–1024px).
  static bool isTabletWidth(double width) =>
      width >= AppBreakpoints.phone && width < AppBreakpoints.desktop;

  /// Width-based query: returns true if [width] is 1024px or wider.
  static bool isDesktopWidth(double width) => width >= AppBreakpoints.desktop;

  /// Returns true if layout elements should stack vertically because [availableWidth]
  /// is less than [threshold] (defaults to [AppBreakpoints.formRow] = 500px).
  static bool shouldStack(
    double availableWidth, [
    double threshold = AppBreakpoints.formRow,
  ]) =>
      availableWidth < threshold;

  /// Selects a responsive value based on the current viewport width tier.
  static T value<T>({
    required BuildContext context,
    required T phone,
    T? tablet,
    required T desktop,
  }) {
    final width = MediaQuery.sizeOf(context).width;
    if (width < AppBreakpoints.phone) return phone;
    if (width < AppBreakpoints.desktop) return tablet ?? phone;
    return desktop;
  }

  /// Selects a responsive value based on container/constraint [width].
  static T valueForWidth<T>({
    required double width,
    required T phone,
    T? tablet,
    required T desktop,
  }) {
    if (width < AppBreakpoints.phone) return phone;
    if (width < AppBreakpoints.desktop) return tablet ?? phone;
    return desktop;
  }
}
