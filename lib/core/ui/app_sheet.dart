import 'dart:ui';

import 'package:flutter/material.dart';
import 'package:shadcn_ui/shadcn_ui.dart';

import 'app_format.dart';
import 'app_responsive.dart';
import 'app_svg_icon.dart';

/// Presents a premium frosted-glass prompt — the app-wide replacement for
/// Material [AlertDialog]s. Adaptive: a **centered dialog** on wide layouts
/// (desktop / tablet-landscape) and a **bottom sheet** on phones. Blurred
/// translucent surface, optional accent icon, centered title/subtitle, then
/// [builder] content (usually action buttons or an input).
///
/// Returns whatever the content pops via `Navigator.pop(context, value)`.
Future<T?> showAppSheet<T>(
  BuildContext context, {
  required String title,
  String? subtitle,
  String? icon,
  Color? iconColor,
  bool dismissible = true,
  required Widget Function(BuildContext sheetContext) builder,
}) {
  return showGlassModal<T>(
    context,
    dismissible: dismissible,
    builder: (ctx) => _GlassBody(
      title: title,
      subtitle: subtitle,
      icon: icon,
      iconColor: iconColor,
      child: builder(ctx),
    ),
  );
}

/// Lower-level presenter: shows [builder] inside the adaptive frosted-glass
/// container (centered dialog on wide, bottom sheet on phones) with NO generic
/// header — the caller supplies the entire content. Use for bespoke premium
/// modals (e.g. the incoming-transfer prompt).
Future<T?> showGlassModal<T>(
  BuildContext context, {
  required Widget Function(BuildContext modalContext) builder,
  bool dismissible = true,
}) {
  if (context.isWideLayout) {
    return showDialog<T>(
      context: context,
      barrierDismissible: dismissible,
      barrierColor: Colors.black.withValues(alpha: 0.42),
      builder: (ctx) => _GlassDialog(child: builder(ctx)),
    );
  }
  return showModalBottomSheet<T>(
    context: context,
    isScrollControlled: true,
    isDismissible: dismissible,
    enableDrag: dismissible,
    useSafeArea: true,
    backgroundColor: Colors.transparent,
    barrierColor: Colors.black.withValues(alpha: 0.42),
    builder: (ctx) => _GlassSheet(child: builder(ctx)),
  );
}

/// A tappable row for use inside [showAppSheet] content (icon + label), with an
/// optional [destructive] red treatment.
class AppSheetAction extends StatelessWidget {
  const AppSheetAction({
    super.key,
    required this.icon,
    required this.label,
    required this.onTap,
    this.destructive = false,
  });

  final String icon;
  final String label;
  final VoidCallback onTap;
  final bool destructive;

  @override
  Widget build(BuildContext context) {
    final cs = ShadTheme.of(context).colorScheme;
    final color = destructive ? cs.destructive : cs.foreground;
    // (icon is an AppIcons name)
    return InkWell(
      onTap: () {
        tapHaptic();
        onTap();
      },
      borderRadius: BorderRadius.circular(12),
      child: Padding(
        padding: const EdgeInsets.symmetric(horizontal: 8, vertical: 14),
        child: Row(
          children: [
            AppSvgIcon(icon, size: 20, color: color),
            const SizedBox(width: 14),
            Text(
              label,
              style: TextStyle(
                fontSize: 15.5,
                fontWeight: FontWeight.w500,
                color: color,
              ),
            ),
          ],
        ),
      ),
    );
  }
}

/// The shared header (accent icon, title, subtitle) + [child] content used by
/// both the sheet and the dialog.
class _GlassBody extends StatelessWidget {
  const _GlassBody({
    required this.title,
    required this.child,
    this.subtitle,
    this.icon,
    this.iconColor,
  });

  final String title;
  final String? subtitle;
  final String? icon;
  final Color? iconColor;
  final Widget child;

  @override
  Widget build(BuildContext context) {
    final cs = ShadTheme.of(context).colorScheme;
    final accent = iconColor ?? cs.primary;
    return Column(
      mainAxisSize: MainAxisSize.min,
      crossAxisAlignment: CrossAxisAlignment.stretch,
      children: [
        if (icon != null)
          Center(
            child: Container(
              width: 56,
              height: 56,
              margin: const EdgeInsets.only(top: 4, bottom: 4),
              decoration: BoxDecoration(
                color: accent.withValues(alpha: 0.14),
                borderRadius: BorderRadius.circular(18),
              ),
              child: AppSvgIcon(icon!, size: 28, color: accent),
            ),
          ),
        Padding(
          padding: const EdgeInsets.fromLTRB(20, 10, 20, 0),
          child: Text(
            title,
            textAlign: TextAlign.center,
            style: TextStyle(
              fontSize: 19,
              fontWeight: FontWeight.w700,
              color: cs.foreground,
            ),
          ),
        ),
        if (subtitle != null && subtitle!.isNotEmpty)
          Padding(
            padding: const EdgeInsets.fromLTRB(24, 6, 24, 0),
            child: Text(
              subtitle!,
              textAlign: TextAlign.center,
              style: TextStyle(
                fontSize: 14,
                height: 1.35,
                color: cs.mutedForeground,
              ),
            ),
          ),
        Padding(
          padding: const EdgeInsets.fromLTRB(20, 20, 20, 4),
          child: child,
        ),
      ],
    );
  }
}

class _GlassSheet extends StatelessWidget {
  const _GlassSheet({required this.child});

  final Widget child;

  @override
  Widget build(BuildContext context) {
    final cs = ShadTheme.of(context).colorScheme;
    final isDark = Theme.of(context).brightness == Brightness.dark;
    final surface = (isDark ? cs.card : cs.background).withValues(alpha: 0.78);

    return ConstrainedBox(
      // Cap height so tall content scrolls instead of overflowing (which would
      // push the rounded top off-screen and clip the corners).
      constraints: BoxConstraints(
        maxHeight: MediaQuery.sizeOf(context).height * 0.92,
      ),
      child: ClipRRect(
        borderRadius: const BorderRadius.vertical(top: Radius.circular(30)),
        clipBehavior: Clip.antiAliasWithSaveLayer,
        child: BackdropFilter(
          filter: ImageFilter.blur(sigmaX: 28, sigmaY: 28),
          child: Container(
            width: double.infinity,
            decoration: BoxDecoration(
              color: surface,
              borderRadius: const BorderRadius.vertical(top: Radius.circular(30)),
              border: Border(
                top: BorderSide(color: cs.border.withValues(alpha: 0.7)),
              ),
            ),
            child: SafeArea(
              top: false,
              child: Padding(
                padding: EdgeInsets.only(
                  bottom: MediaQuery.of(context).viewInsets.bottom + 12,
                ),
                child: Column(
                  mainAxisSize: MainAxisSize.min,
                  children: [
                    Container(
                      margin: const EdgeInsets.only(top: 10, bottom: 4),
                      width: 40,
                      height: 5,
                      decoration: BoxDecoration(
                        color: cs.mutedForeground.withValues(alpha: 0.35),
                        borderRadius: BorderRadius.circular(3),
                      ),
                    ),
                    Flexible(child: SingleChildScrollView(child: child)),
                  ],
                ),
              ),
            ),
          ),
        ),
      ),
    );
  }
}

class _GlassDialog extends StatelessWidget {
  const _GlassDialog({required this.child});

  final Widget child;

  @override
  Widget build(BuildContext context) {
    final cs = ShadTheme.of(context).colorScheme;
    final isDark = Theme.of(context).brightness == Brightness.dark;
    final surface = (isDark ? cs.card : cs.background).withValues(alpha: 0.88);

    return Center(
      child: Padding(
        padding: EdgeInsets.only(
          left: 24,
          right: 24,
          top: 24,
          bottom: MediaQuery.of(context).viewInsets.bottom + 24,
        ),
        child: ConstrainedBox(
          constraints: BoxConstraints(
            maxWidth: 420,
            maxHeight: MediaQuery.sizeOf(context).height * 0.9,
          ),
          // Shadow on the outer wrapper so it isn't clipped by the ClipRRect.
          child: DecoratedBox(
            decoration: BoxDecoration(
              borderRadius: BorderRadius.circular(24),
              boxShadow: [
                BoxShadow(
                  color: Colors.black.withValues(alpha: 0.18),
                  blurRadius: 40,
                  offset: const Offset(0, 20),
                ),
              ],
            ),
            child: ClipRRect(
              borderRadius: BorderRadius.circular(24),
              clipBehavior: Clip.antiAliasWithSaveLayer,
              child: BackdropFilter(
                filter: ImageFilter.blur(sigmaX: 24, sigmaY: 24),
                child: Container(
                  decoration: BoxDecoration(
                    color: surface,
                    borderRadius: BorderRadius.circular(24),
                    border: Border.all(color: cs.border.withValues(alpha: 0.7)),
                  ),
                  // Tall content scrolls within the capped height, keeping the
                  // rounded corners intact.
                  child: SingleChildScrollView(child: child),
                ),
              ),
            ),
          ),
        ),
      ),
    );
  }
}
