import 'package:flutter/widgets.dart';

/// The tabs of the app, in bar order (redesign-plan.md 2.1).
enum ShellTabId { send, inbox, drive, rooms, settings }

/// Asks the tab shell to show a tab (e.g. the Send sheet's Rooms row opens
/// the Rooms tab). The shell listens and resets it to null.
final ValueNotifier<ShellTabId?> shellTabRequest = ValueNotifier(null);

/// Whether the tab around a page is the one on screen. MainShell keeps every
/// tab alive in an IndexedStack, so a hidden tab is still laid out: a page
/// that takes drops from the desktop, catches "back" or listens to the
/// keyboard checks this first.
class ShellTab extends InheritedWidget {
  const ShellTab({super.key, required this.active, required super.child});

  final bool active;

  /// True outside MainShell (a pushed page, a test).
  static bool isActive(BuildContext context) =>
      context.dependOnInheritedWidgetOfExactType<ShellTab>()?.active ?? true;

  @override
  bool updateShouldNotify(ShellTab oldWidget) => oldWidget.active != active;
}
