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

/// A tappable row for use inside [showAppSheet] content: the glyph on a
/// small tile, the label and an optional [subtitle]; [destructive] turns it
/// red. Inside an [AppSheetGroup] the rows sit on one card.
class AppSheetAction extends StatelessWidget {
  const AppSheetAction({
    super.key,
    required this.icon,
    required this.label,
    required this.onTap,
    this.subtitle,
    this.destructive = false,
    this.selected = false,
  });

  final String icon;
  final String label;
  final String? subtitle;
  final VoidCallback onTap;
  final bool destructive;

  /// The option in force (a sort, a filter): an accent tile and a check.
  final bool selected;

  @override
  Widget build(BuildContext context) {
    final t = context.tokens;
    final color = destructive ? t.danger : t.text;
    final tile = destructive
        ? t.danger.withValues(alpha: 0.14)
        : selected
        ? t.accentSoft
        : t.sunken;
    final glyph = destructive
        ? t.danger
        : selected
        ? t.accent
        : t.text;
    // Transparent Material so the InkWell has a Material ancestor under ShadApp
    // (a bare InkWell throws Material.of on desktop hover).
    return Material(
      type: MaterialType.transparency,
      child: InkWell(
        onTap: () {
          tapHaptic();
          onTap();
        },
        borderRadius: BorderRadius.circular(14),
        child: ConstrainedBox(
          constraints: const BoxConstraints(minHeight: 52),
          child: Padding(
            padding: const EdgeInsetsDirectional.fromSTEB(12, 9, 14, 9),
            child: Row(
              children: [
                Container(
                  width: 32,
                  height: 32,
                  alignment: Alignment.center,
                  decoration: BoxDecoration(
                    color: tile,
                    borderRadius: BorderRadius.circular(9),
                  ),
                  child: AppSvgIcon(icon, size: 18, color: glyph),
                ),
                const SizedBox(width: 12),
                // A long label (a Drive link's name and lifetime) wraps instead
                // of running off the sheet.
                Expanded(
                  child: Column(
                    crossAxisAlignment: CrossAxisAlignment.start,
                    mainAxisSize: MainAxisSize.min,
                    children: [
                      Text(label, style: AppType.row.copyWith(color: color)),
                      if (subtitle != null) ...[
                        const SizedBox(height: 1),
                        Text(
                          subtitle!,
                          style: AppType.secondary.copyWith(
                            fontSize: 12.5,
                            color: t.text2,
                          ),
                        ),
                      ],
                    ],
                  ),
                ),
                if (selected) ...[
                  const SizedBox(width: 8),
                  AppSvgIcon(AppIcons.check, size: 18, color: t.accent),
                ],
              ],
            ),
          ),
        ),
      ),
    );
  }
}

/// Rows of a sheet on one rounded card, hairlines between them. A sheet
/// stacks a few: what to do, what it is, and apart from them, delete.
class AppSheetGroup extends StatelessWidget {
  const AppSheetGroup({
    super.key,
    required this.children,
    this.margin = const EdgeInsets.only(bottom: 10),
  });

  final List<Widget> children;
  final EdgeInsetsGeometry margin;

  @override
  Widget build(BuildContext context) {
    final t = context.tokens;
    final rows = children;
    if (rows.isEmpty) return const SizedBox.shrink();
    return Container(
      margin: margin,
      decoration: BoxDecoration(
        color: t.sheetCard,
        borderRadius: BorderRadius.circular(14),
      ),
      clipBehavior: Clip.antiAlias,
      child: Column(
        mainAxisSize: MainAxisSize.min,
        crossAxisAlignment: CrossAxisAlignment.stretch,
        children: [
          for (var i = 0; i < rows.length; i++) ...[
            if (i > 0)
              Padding(
                padding: const EdgeInsetsDirectional.only(start: 56),
                child: Divider(height: 1, thickness: 1, color: t.line),
              ),
            rows[i],
          ],
        ],
      ),
    );
  }
}

/// One fact in a sheet's [AppSheetGroup]: the name, then the value on the
/// end side.
class AppSheetInfo extends StatelessWidget {
  const AppSheetInfo(this.label, this.value, {super.key, this.lines = 1});

  final String label;
  final String value;
  final int lines;

  @override
  Widget build(BuildContext context) {
    final t = context.tokens;
    return Padding(
      padding: const EdgeInsets.symmetric(horizontal: 14, vertical: 12),
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

/// A file sheet's main actions as a row of big buttons under the header
/// (open, share, save...). The first can be [AppSheetQuick.primary].
class AppSheetQuickRow extends StatelessWidget {
  const AppSheetQuickRow({super.key, required this.actions});

  final List<AppSheetQuick> actions;

  @override
  Widget build(BuildContext context) {
    return Padding(
      padding: const EdgeInsets.only(bottom: 14),
      child: Row(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          for (var i = 0; i < actions.length; i++) ...[
            if (i > 0) const SizedBox(width: 8),
            Expanded(child: actions[i]),
          ],
        ],
      ),
    );
  }
}

class AppSheetQuick extends StatelessWidget {
  const AppSheetQuick({
    super.key,
    required this.icon,
    required this.label,
    required this.onTap,
    this.primary = false,
  });

  final String icon;
  final String label;
  final VoidCallback onTap;
  final bool primary;

  @override
  Widget build(BuildContext context) {
    final t = context.tokens;
    return Semantics(
      button: true,
      label: label,
      excludeSemantics: true,
      child: Material(
        color: primary ? t.accent : t.sheetCard,
        borderRadius: BorderRadius.circular(14),
        child: InkWell(
          borderRadius: BorderRadius.circular(14),
          onTap: () {
            tapHaptic();
            onTap();
          },
          child: Padding(
            padding: const EdgeInsets.fromLTRB(4, 12, 4, 10),
            child: Column(
              mainAxisSize: MainAxisSize.min,
              children: [
                AppSvgIcon(
                  icon,
                  size: 22,
                  color: primary ? t.onAccent : t.text,
                ),
                const SizedBox(height: 6),
                Text(
                  label,
                  maxLines: 1,
                  overflow: TextOverflow.ellipsis,
                  textAlign: TextAlign.center,
                  style: AppType.secondary.copyWith(
                    fontSize: 12.5,
                    fontWeight: FontWeight.w500,
                    color: primary ? t.onAccent : t.text,
                  ),
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
          color: t.sheetBg,
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
              color: t.sheetBg,
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
