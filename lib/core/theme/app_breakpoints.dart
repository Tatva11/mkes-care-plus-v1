/// Defines standard responsive breakpoint values and dialog/touch sizing constants
/// for the MKES CARE+ design system.
abstract final class AppBreakpoints {
  /// Mobile breakpoint: viewports narrower than 600 logical pixels.
  static const double phone = 600.0;

  /// Compact/Tablet breakpoint: viewports narrower than 768 logical pixels.
  /// Used for collapsing sidebars to bottom bars and switching multi-action headers.
  static const double compact = 768.0;

  /// Desktop breakpoint: viewports 1024 logical pixels and wider.
  static const double desktop = 1024.0;

  /// Large desktop breakpoint: viewports 1440 logical pixels and wider.
  static const double largeDesktop = 1440.0;

  /// Breakpoint below which multi-field form rows stack vertically into a single column.
  static const double formRow = 500.0;

  /// Standard maximum dialog widths by device tier.
  static const double maxDialogWidthMobile = 420.0;
  static const double maxDialogWidthTablet = 560.0;
  static const double maxDialogWidthDesktop = 680.0;

  /// Recommended minimum touch target dimension (48x48 logical pixels) for mobile accessibility.
  static const double minTouchTarget = 48.0;
}
