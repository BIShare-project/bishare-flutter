import 'package:flutter/material.dart';

import '../theme/app_tokens.dart';
import '../theme/app_type.dart';
import 'app_format.dart';
import 'app_responsive.dart';
import 'app_svg_icon.dart';

/// Presents a prompt: the app-wide replacement for Material [AlertDialog]s.
/// Adaptive: a **centered dialog** on wide layouts (desktop /
/// tablet-landscape) and a **bottom sheet** on phones. Solid raised surface
/// (no blur: redesign-plan.md "Performance budget"), a header with an
/// optional glyph, the title, the subtitle and a close button, then
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
    builder: (ctx) => _SheetBody(
      title: title,
      subtitle: subtitle,
      icon: icon,
      iconColor: iconColor,
      closable: dismissible,
      child: builder(ctx),
    ),
  );
}

/// Lower-level presenter: shows [builder] inside the adaptive container
/// (centered dialog on wide, bottom sheet on phones) with NO generic header;
/// the caller supplies the entire content (e.g. the incoming-transfer prompt).
/// The name is kept from the frosted-glass days so callers need no change.
Future<T?> showGlassModal<T>(
  BuildContext context, {
  required Widget Function(BuildContext modalContext) builder,
  bool dismissible = true,
}) {
  final t = context.tokens;
  if (context.isWideLayout) {
    return showDialog<T>(
      context: context,
      barrierDismissible: dismissible,
      barrierColor: t.scrim,
      builder: (ctx) => _Dialog(child: builder(ctx)),
    );
  }
  return showModalBottomSheet<T>(
    context: context,
    isScrollControlled: true,
    isDismissible: dismissible,
    enableDrag: dismissible,
    useSafeArea: true,
    backgroundColor: Colors.transparent,
    elevation: 0,
    barrierColor: t.scrim,
    builder: (ctx) => _Sheet(child: builder(ctx)),
  );
}

/// A tappable row for use inside [showAppSheet] content (glyph + label), with
/// an optional [destructive] red treatment.
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
    final t = context.tokens;
    final color = destructive ? t.danger : t.text;
    // Transparent Material so the InkWell has a Material ancestor under ShadApp
    // (a bare InkWell throws Material.of on desktop hover).
    return Material(
      type: MaterialType.transparency,
      child: InkWell(
        onTap: () {
          tapHaptic();
          onTap();
        },
        borderRadius: BorderRadius.circular(12),
        child: ConstrainedBox(
          constraints: const BoxConstraints(minHeight: 52),
          child: Padding(
            padding: const EdgeInsets.symmetric(horizontal: 4, vertical: 12),
            child: Row(
              children: [
                AppSvgIcon(
                  icon,
                  size: 21,
                  color: destructive ? t.danger : t.text2,
                ),
                const SizedBox(width: 14),
                // A long label (a Drive link's name and lifetime) wraps instead
                // of running off the sheet.
                Flexible(
                  child: Text(label, style: AppType.row.copyWith(color: color)),
                ),
              ],
            ),
          ),
        ),
      ),
    );
  }
}

/// The shared header (glyph, title, subtitle, close) + [child] content used by
/// both the sheet and the dialog.
class _SheetBody extends StatelessWidget {
  const _SheetBody({
    required this.title,
    required this.child,
    required this.closable,
    this.subtitle,
    this.icon,
    this.iconColor,
  });

  final String title;
  final String? subtitle;
  final String? icon;
  final Color? iconColor;
  final bool closable;
  final Widget child;

  @override
  Widget build(BuildContext context) {
    final t = context.tokens;
    final hasSub = subtitle != null && subtitle!.isNotEmpty;
    return Column(
      mainAxisSize: MainAxisSize.min,
      crossAxisAlignment: CrossAxisAlignment.stretch,
      children: [
        Padding(
          padding: EdgeInsetsDirectional.fromSTEB(20, 8, closable ? 8 : 20, 0),
          child: Row(
            crossAxisAlignment: CrossAxisAlignment.start,
            children: [
              if (icon != null) ...[
                Padding(
                  padding: const EdgeInsets.only(top: 1),
                  child: AppSvgIcon(
                    icon!,
                    size: 24,
                    color: iconColor ?? t.text2,
                  ),
                ),
                const SizedBox(width: 12),
              ],
              Expanded(
                child: Column(
                  crossAxisAlignment: CrossAxisAlignment.start,
                  children: [
                    Text(
                      title,
                      style: AppType.sheetTitle.copyWith(color: t.text),
                    ),
                    if (hasSub) ...[
                      const SizedBox(height: 3),
                      Text(
                        subtitle!,
                        style: AppType.secondary.copyWith(color: t.text2),
                      ),
                    ],
                  ],
                ),
              ),
              if (closable)
                Semantics(
                  button: true,
                  label: MaterialLocalizations.of(context).closeButtonTooltip,
                  child: SizedBox(
                    width: 44,
                    height: 44,
                    child: Material(
                      type: MaterialType.transparency,
                      child: InkWell(
                        customBorder: const CircleBorder(),
                        onTap: () => Navigator.of(context).maybePop(),
                        child: Center(
                          child: AppSvgIcon(
                            AppIcons.close,
                            size: 22,
                            color: t.text2,
                          ),
                        ),
                      ),
                    ),
                  ),
                ),
            ],
          ),
        ),
        Padding(
          padding: const EdgeInsets.fromLTRB(20, 16, 20, 4),
          child: child,
        ),
      ],
    );
  }
}

class _Sheet extends StatelessWidget {
  const _Sheet({required this.child});

  final Widget child;

  @override
  Widget build(BuildContext context) {
    final t = context.tokens;
    const radius = BorderRadius.vertical(top: Radius.circular(22));
    return ConstrainedBox(
      // Cap height so tall content scrolls instead of overflowing (which would
      // push the rounded top off-screen and clip the corners).
      constraints: BoxConstraints(
        maxHeight: MediaQuery.sizeOf(context).height * 0.9,
      ),
      child: DecoratedBox(
        decoration: BoxDecoration(
          color: t.raised,
          borderRadius: radius,
          border: t.isDark ? Border(top: BorderSide(color: t.line)) : null,
          boxShadow: [
            BoxShadow(
              color: Colors.black.withValues(alpha: t.isDark ? 0.5 : 0.16),
              blurRadius: 40,
              offset: const Offset(0, -10),
            ),
          ],
        ),
        child: ClipRRect(
          borderRadius: radius,
          child: SafeArea(
            top: false,
            child: Padding(
              padding: EdgeInsets.only(
                bottom: MediaQuery.viewInsetsOf(context).bottom + 12,
              ),
              child: Column(
                mainAxisSize: MainAxisSize.min,
                children: [
                  Container(
                    margin: const EdgeInsets.only(top: 8, bottom: 6),
                    width: 38,
                    height: 5,
                    decoration: BoxDecoration(
                      color: t.line,
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
    );
  }
}

class _Dialog extends StatelessWidget {
  const _Dialog({required this.child});

  final Widget child;

  @override
  Widget build(BuildContext context) {
    final t = context.tokens;
    final radius = BorderRadius.circular(20);
    return Center(
      child: Padding(
        padding: EdgeInsets.only(
          left: 24,
          right: 24,
          top: 24,
          bottom: MediaQuery.viewInsetsOf(context).bottom + 24,
        ),
        child: ConstrainedBox(
          constraints: BoxConstraints(
            maxWidth: 440,
            maxHeight: MediaQuery.sizeOf(context).height * 0.9,
          ),
          child: DecoratedBox(
            decoration: BoxDecoration(
              color: t.raised,
              borderRadius: radius,
              border: Border.all(color: t.line),
              boxShadow: [
                BoxShadow(
                  color: Colors.black.withValues(alpha: t.isDark ? 0.5 : 0.16),
                  blurRadius: 40,
                  offset: const Offset(0, 18),
                ),
              ],
            ),
            child: ClipRRect(
              borderRadius: radius,
              // Tall content scrolls within the capped height, keeping the
              // rounded corners intact.
              child: Material(
                type: MaterialType.transparency,
                child: SingleChildScrollView(
                  padding: const EdgeInsets.only(top: 12, bottom: 8),
                  child: child,
                ),
              ),
            ),
          ),
        ),
      ),
    );
  }
}
