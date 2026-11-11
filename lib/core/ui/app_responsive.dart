import 'package:flutter/foundation.dart';
import 'package:flutter/widgets.dart';

/// Layout breakpoints. A screen at least [expanded] wide gets the desktop /
/// tablet treatment (side rail + multi-column content), and so does an open
/// foldable ([isFoldableSize]); anything else gets the mobile treatment
/// (bottom nav + single column).
abstract final class AppBreakpoints {
  static const double expanded = 760;
}

/// An open iPhone Duo: iOS with a shortest side between 600 and 700 pt (the
/// inner display is 669 × 951 pt either way up). No iPhone reaches 600, and
/// the smallest iPad (mini, 744) is above 700, so iPhones, iPads, Android and
/// computers keep their layouts. Here the rail is compact and Send shows the
/// destinations beside the library (Apple's two-column guidance for the
/// inner display).
bool isFoldableSize(Size size) =>
    defaultTargetPlatform == TargetPlatform.iOS &&
    size.shortestSide >= 600 &&
    size.shortestSide < 700;

/// Whether [size] gets the wide layout (see [AppBreakpoints]).
bool isWideSize(Size size) =>
    size.width >= AppBreakpoints.expanded || isFoldableSize(size);

/// The physical screen edge that holds the system's vertical control strip.
enum SideStrip { left, right }

/// Where iOS put its controls in a column beside the content instead of bars
/// above and below it: the iPhone Duo outer display, closed, keeps the status
/// bar and Dynamic Island in a strip on its right, and Apple moves tab bars
/// and toolbars into that strip too. Detected from the screen itself, not the
/// device name: an iPhone-sized (not wide) layout, upright, with a side inset
/// of at least 40 pt. No other phone, tablet or computer has that, so the rest
/// keep the bottom bar or the side rail.
SideStrip? sideStripOf(BuildContext context) {
  if (defaultTargetPlatform != TargetPlatform.iOS) return null;
  final size = MediaQuery.sizeOf(context);
  if (isWideSize(size) || size.height <= size.width) return null;
  final pad = MediaQuery.viewPaddingOf(context);
  if (pad.right >= 40 && pad.right > pad.left) return SideStrip.right;
  if (pad.left >= 40 && pad.left > pad.right) return SideStrip.left;
  return null;
}

extension AppResponsive on BuildContext {
  /// True on desktop windows, tablets and open foldables — use the wide layout.
  bool get isWideLayout => isWideSize(MediaQuery.sizeOf(this));

  /// True on an open iPhone Duo (see [isFoldableSize]).
  bool get isFoldableOpen => isFoldableSize(MediaQuery.sizeOf(this));

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
