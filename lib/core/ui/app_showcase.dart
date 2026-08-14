import 'package:flutter/material.dart';
import 'package:shadcn_ui/shadcn_ui.dart';
import 'package:shared_preferences/shared_preferences.dart';
import 'package:showcaseview/showcaseview.dart';

import '../di/locator.dart';
import '../platform/tv.dart';

/// First-run feature tours (coach marks). One short tour per screen, each
/// shown exactly once and remembered in [SharedPreferences]: Home on the
/// first launch after onboarding, Inbox/Rooms the first time their tab opens.
class ShowcaseIds {
  static const home = 'showcase_home_v1';
  static const inbox = 'showcase_inbox_v1';
  static const rooms = 'showcase_rooms_v1';
}

/// The showcaseview scope owned by the tab shell.
const kShowcaseScope = 'shell';

/// GlobalKeys identifying every showcase target. In showcaseview 5.x these
/// are registry identifiers (not element keys), so a key existing here says
/// nothing about being built — [maybeStartShowcase] checks isTargetRendered.
class ShowcaseKeys {
  static final homeDevice = GlobalKey();
  static final homeTray = GlobalKey();
  static final homeNearby = GlobalKey();
  static final homeActions = GlobalKey();
  static final homeNav = GlobalKey();
  static final inboxFiles = GlobalKey();
  static final inboxWeb = GlobalKey();
  static final roomCreate = GlobalKey();
  static final roomJoin = GlobalKey();
}

/// Registers the shell's showcase scope. Call once in the shell's initState
/// (before the first build mounts any [AppShowcase]); unregister on dispose.
ShowcaseView registerAppShowcase() => ShowcaseView.register(
      scope: kShowcaseScope,
      // Tour lists are fixed; whatever isn't on screen (empty states, an
      // active room instead of the lobby) is skipped, not crashed on.
      skipIfTargetNotPresent: true,
      disableMovingAnimation: true,
    );

/// A [Showcase] styled for BIShare — dark card tooltip, soft radii. Tap
/// anywhere to advance.
class AppShowcase extends StatelessWidget {
  const AppShowcase({
    super.key,
    required this.showcaseKey,
    required this.title,
    required this.description,
    required this.child,
    this.targetRadius = 18,
    this.targetPadding = EdgeInsets.zero,
  });

  final GlobalKey showcaseKey;
  final String title;
  final String description;
  final Widget child;
  final double targetRadius;
  final EdgeInsets targetPadding;

  @override
  Widget build(BuildContext context) {
    final cs = ShadTheme.of(context).colorScheme;
    return Showcase(
      key: showcaseKey,
      scope: kShowcaseScope,
      title: title,
      description: description,
      titleTextStyle: TextStyle(
        fontSize: 15,
        fontWeight: FontWeight.w700,
        color: cs.foreground,
      ),
      descTextStyle: TextStyle(
        fontSize: 13,
        height: 1.35,
        color: cs.mutedForeground,
      ),
      tooltipBackgroundColor: cs.card,
      tooltipBorderRadius: BorderRadius.circular(14),
      tooltipPadding: const EdgeInsets.fromLTRB(14, 12, 14, 12),
      targetBorderRadius: BorderRadius.circular(targetRadius),
      targetPadding: targetPadding,
      overlayOpacity: 0.78,
      disableMovingAnimation: true,
      child: child,
    );
  }
}

/// Starts the [id] tour once. Skips: TV (remote-driven UI), tours already
/// seen, and targets that aren't rendered right now. If *nothing* from the
/// tour is on screen, the seen-flag is left unset so the tour can try again
/// on a later visit; once it actually starts, it never re-runs (set-on-start,
/// so a mid-tour app kill doesn't nag on relaunch).
Future<void> maybeStartShowcase({
  required String id,
  required List<GlobalKey> keys,
}) async {
  if (isTvDevice) return;
  final prefs = getIt<SharedPreferences>();
  if (prefs.getBool(id) ?? false) return;
  final view = ShowcaseView.getNamed(kShowcaseScope);
  final rendered = keys.where(view.isTargetRendered).toList();
  if (rendered.isEmpty) return;
  await prefs.setBool(id, true);
  view.startShowCase(rendered, delay: const Duration(milliseconds: 250));
}
