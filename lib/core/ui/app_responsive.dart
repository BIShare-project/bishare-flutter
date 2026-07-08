import 'package:flutter/widgets.dart';

/// Layout breakpoints. Width ≥ [expanded] gets the desktop / tablet-landscape
/// treatment (side rail + multi-column content); narrower gets the mobile
/// treatment (bottom nav + single column).
abstract final class AppBreakpoints {
  static const double expanded = 760;
}

extension AppResponsive on BuildContext {
  /// True on desktop windows and tablet landscape — use the wide layout.
  bool get isWideLayout =>
      MediaQuery.sizeOf(this).width >= AppBreakpoints.expanded;

  double get screenWidth => MediaQuery.sizeOf(this).width;
}

/// Centers and caps [child] to [maxWidth] on wide layouts so desktop content
/// reads as a comfortable column instead of a stretched phone screen; on narrow
/// layouts it just fills the width.
class AppResponsivePane extends StatelessWidget {
  const AppResponsivePane({
    super.key,
    required this.child,
    this.maxWidth = 960,
  });

  final Widget child;
  final double maxWidth;

  @override
  Widget build(BuildContext context) {
    return Align(
      alignment: Alignment.topCenter,
      child: ConstrainedBox(
        constraints: BoxConstraints(
          maxWidth: context.isWideLayout ? maxWidth : double.infinity,
        ),
        child: child,
      ),
    );
  }
}
