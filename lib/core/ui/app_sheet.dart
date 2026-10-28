import 'package:easy_localization/easy_localization.dart';
import 'package:flutter/material.dart';

import '../theme/app_tokens.dart';
import '../theme/app_type.dart';
import 'app_button.dart';
import 'app_format.dart';
import 'app_responsive.dart';
import 'app_svg_icon.dart';

/// Presents a prompt: the app-wide replacement for Material [AlertDialog]s.
/// Adaptive: a **centered dialog** on wide layouts (desktop /
/// tablet-landscape) and a **bottom sheet** on phones. Solid raised surface
/// (no blur: redesign-plan.md "Performance budget"), a header with an
/// optional glyph (or a [leading] picture, such as a file's thumbnail), the
/// title, the subtitle and a close button, then
/// [builder] content (usually action buttons or an input).
///
/// Returns whatever the content pops via `Navigator.pop(context, value)`.
Future<T?> showAppSheet<T>(
  BuildContext context, {
  required String title,
  String? subtitle,
  String? icon,
  Color? iconColor,
  Widget? leading,
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
      leading: leading,
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

/// A tappable row for use inside [showAppSheet] content, flat like the Send
/// sheet's rows: the glyph, the label and an optional [subtitle];
/// [destructive] turns it red, [selected] marks the option in force.
class AppSheetAction extends StatelessWidget {
  const AppSheetAction({
    super.key,
    this.icon,
    required this.label,
    required this.onTap,
    this.subtitle,
    this.destructive = false,
    this.selected = false,
  });

  /// Null for a plain option (a language, a size): the label alone.
  final String? icon;
  final String label;
  final String? subtitle;
  final VoidCallback onTap;
  final bool destructive;

  /// The option in force (a sort, a filter): accent glyph and a check.
  final bool selected;

  @override
  Widget build(BuildContext context) {
    final t = context.tokens;
    final color = destructive ? t.danger : t.text;
    final glyph = destructive
        ? t.danger
        : selected
        ? t.accent
        : t.text2;
    // Transparent Material so the InkWell has a Material ancestor in a sheet
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
            padding: const EdgeInsets.symmetric(horizontal: 4, vertical: 10),
            child: Row(
              children: [
                if (icon != null) ...[
                  AppSvgIcon(icon!, size: 22, color: glyph),
                  const SizedBox(width: 14),
                ],
                // A long label (a Drive link's name and lifetime) wraps instead
                // of running off the sheet.
                Expanded(
                  child: Column(
                    crossAxisAlignment: CrossAxisAlignment.start,
                    mainAxisSize: MainAxisSize.min,
                    children: [
                      Text(label, style: AppType.row.copyWith(color: color)),
                      if (subtitle != null) ...[
                        const SizedBox(height: 2),
                        Text(
                          subtitle!,
                          style: AppType.secondary.copyWith(
                            fontSize: 13,
                            color: t.text2,
                          ),
                        ),
                      ],
                    ],
                  ),
                ),
                if (selected) ...[
                  const SizedBox(width: 8),
                  AppSvgIcon(AppIcons.check, size: 20, color: t.accent),
                ],
              ],
            ),
          ),
        ),
      ),
    );
  }
}

/// Rows of a sheet with hairlines between them, flat on the sheet. A sheet
/// stacks a few, a hairline apart: what to do, what it is, then delete.
class AppSheetGroup extends StatelessWidget {
  const AppSheetGroup({
    super.key,
    required this.children,
    this.first = false,
    this.indent = 40,
  });

  final List<Widget> children;

  /// The top group: no hairline above it.
  final bool first;

  /// Where the hairline between rows starts: past the glyph, or 4 for rows
  /// without one.
  final double indent;

  @override
  Widget build(BuildContext context) {
    final t = context.tokens;
    if (children.isEmpty) return const SizedBox.shrink();
    Widget line(double indent) => Padding(
      padding: EdgeInsetsDirectional.only(start: indent),
      child: Divider(height: 1, thickness: 1, color: t.line),
    );
    return Column(
      mainAxisSize: MainAxisSize.min,
      crossAxisAlignment: CrossAxisAlignment.stretch,
      children: [
        if (!first) ...[
          const SizedBox(height: 6),
          line(0),
          const SizedBox(height: 6),
        ],
        for (var i = 0; i < children.length; i++) ...[
          if (i > 0) line(indent),
          children[i],
        ],
      ],
    );
  }
}

/// One fact in a sheet: the name, then the value on the end side.
class AppSheetInfo extends StatelessWidget {
  const AppSheetInfo(this.label, this.value, {super.key, this.lines = 1});

  final String label;
  final String value;
  final int lines;

  @override
  Widget build(BuildContext context) {
    final t = context.tokens;
    return Padding(
      padding: const EdgeInsets.symmetric(horizontal: 4, vertical: 9),
      child: Row(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Text(label, style: AppType.body.copyWith(color: t.text2)),
          const SizedBox(width: 16),
          Expanded(
            child: Text(
              value,
              textAlign: TextAlign.end,
              maxLines: lines,
              overflow: TextOverflow.ellipsis,
              style: AppType.body.copyWith(
                color: t.text,
                fontFeatures: const [FontFeature.tabularFigures()],
              ),
            ),
          ),
        ],
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
    this.leading,
  });

  final String title;
  final String? subtitle;
  final String? icon;
  final Color? iconColor;
  final Widget? leading;
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
            crossAxisAlignment: leading != null
                ? CrossAxisAlignment.center
                : CrossAxisAlignment.start,
            children: [
              if (leading != null) ...[
                leading!,
                const SizedBox(width: 12),
              ] else if (icon != null) ...[
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
                      maxLines: leading != null ? 2 : null,
                      overflow: leading != null ? TextOverflow.ellipsis : null,
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

/// Asks before something that cannot be undone. True only when the person
/// confirms; closing the sheet any other way is no.
Future<bool> showAppConfirm(
  BuildContext context, {
  required String title,
  required String message,
  required String confirmLabel,
  bool destructive = true,
}) async {
  final yes = await showAppSheet<bool>(
    context,
    title: title,
    subtitle: message,
    builder: (ctx) => Row(
      children: [
        Expanded(
          child: AppButton(
            label: 'common.cancel'.tr(),
            variant: AppButtonVariant.secondary,
            size: AppButtonSize.large,
            onPressed: () => Navigator.pop(ctx, false),
          ),
        ),
        const SizedBox(width: 10),
        Expanded(
          child: AppButton(
            label: confirmLabel,
            variant: destructive
                ? AppButtonVariant.destructive
                : AppButtonVariant.primary,
            size: AppButtonSize.large,
            onPressed: () => Navigator.pop(ctx, true),
          ),
        ),
      ],
    ),
  );
  return yes ?? false;
}

/// Disposes a sheet's text [controller] once the sheet has finished closing:
/// its field still reads the controller during the exit animation.
void disposeAfterSheet(ChangeNotifier controller) {
  Future<void>.delayed(
    const Duration(milliseconds: 500),
    controller.dispose,
  );
}
