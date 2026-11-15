import 'package:material_ui/material_ui.dart';

/// Responsive viewport width breakpoints for Phone2Screen layouts.
enum ScreenSize { compact, medium, expanded }

/// Adaptive layout helpers derived from [MediaQuery.sizeOf].
extension ResponsiveContext on BuildContext {
  ScreenSize get screenSize {
    final width = MediaQuery.sizeOf(this).width;
    if (width < 640) return .compact;
    if (width <= 1024) return .medium;
    return .expanded;
  }

  bool get isCompact => screenSize == .compact;
  bool get isMedium => screenSize == .medium;
  bool get isExpanded => screenSize == .expanded;

  double get contentMaxWidth => switch (screenSize) {
    .compact => double.infinity,
    .medium => 840,
    .expanded => 1280,
  };
}
