import 'package:flutter/material.dart';

import '../theme/app_tokens.dart';
import '../theme/app_type.dart';
import 'app_format.dart';
import 'app_svg_icon.dart';

/// How an [AppButton] is filled.
enum AppButtonVariant {
  /// The main action: the accent fill.
  primary,

  /// "Sending": the BIShare gradient (the accent when it is not blue).
  brand,

  /// A quiet filled action on the sunken surface.
  secondary,

  /// A hairline border, no fill.
  outline,

  /// Text only.
  ghost,

  /// Destructive: the danger fill.
  destructive,
}

/// Heights keep the platform tap targets (44 pt iOS, 48 dp Android).
enum AppButtonSize { small, medium, large }

/// The app-wide button. Solid token fills, no shadows, no layout animation:
/// the press feedback is the ink ripple only (redesign-plan.md "Components").
class AppButton extends StatelessWidget {
  const AppButton({
    super.key,
    required this.label,
    required this.onPressed,
    this.icon,
    this.variant = AppButtonVariant.primary,
    this.size = AppButtonSize.medium,
    this.fullWidth = false,
    this.loading = false,
    this.disabled = false,
  });

  final String label;
  final VoidCallback? onPressed;

  /// An [AppIcons] name shown before the label.
  final String? icon;
  final AppButtonVariant variant;
  final AppButtonSize size;
  final bool fullWidth;

  /// Shows a spinner instead of the label and blocks taps.
  final bool loading;
  final bool disabled;

  bool get _enabled => !disabled && !loading && onPressed != null;

  @override
  Widget build(BuildContext context) {
    final t = context.tokens;
    final (height, pad, font, iconSize) = switch (size) {
      AppButtonSize.small => (40.0, 14.0, 14.0, 16.0),
      AppButtonSize.medium => (48.0, 18.0, 15.0, 18.0),
      AppButtonSize.large => (52.0, 22.0, 16.0, 19.0),
    };
    final (bg, fg, border) = _colors(t);
    final radius = BorderRadius.circular(12);
    final dim = _enabled ? 1.0 : 0.45;

    final content = loading
        ? SizedBox(
            width: iconSize,
            height: iconSize,
            child: CircularProgressIndicator(
              strokeWidth: 2.2,
              valueColor: AlwaysStoppedAnimation(fg),
            ),
          )
        : Row(
            mainAxisSize: MainAxisSize.min,
            children: [
              if (icon != null) ...[
                AppSvgIcon(
                  icon!,
                  size: iconSize,
                  color: fg.withValues(alpha: dim),
                ),
                const SizedBox(width: 8),
              ],
              Flexible(
                child: Text(
                  label,
                  maxLines: 1,
                  overflow: TextOverflow.ellipsis,
                  textAlign: TextAlign.center,
                  style: AppType.rowStrong.copyWith(
                    fontSize: font,
                    color: fg.withValues(alpha: dim),
                    height: 1.15,
                  ),
                ),
              ),
            ],
          );

    final decoration = BoxDecoration(
      color: variant == AppButtonVariant.brand
          ? null
          : bg?.withValues(alpha: (bg.a) * (_enabled ? 1 : 0.5)),
      gradient: variant == AppButtonVariant.brand && _enabled
          ? t.brandSurface
          : null,
      borderRadius: radius,
      border: border == null ? null : Border.all(color: border),
    );

    return Semantics(
      button: true,
      enabled: _enabled,
      child: SizedBox(
        height: height,
        width: fullWidth ? double.infinity : null,
        child: Material(
          type: MaterialType.transparency,
          child: Ink(
            decoration: variant == AppButtonVariant.brand && !_enabled
                ? decoration.copyWith(
                    color: t.accentStrong.withValues(alpha: 0.5),
                  )
                : decoration,
            child: InkWell(
              onTap: _enabled
                  ? () {
                      tapHaptic();
                      onPressed!();
                    }
                  : null,
              borderRadius: radius,
              child: Padding(
                padding: EdgeInsets.symmetric(horizontal: pad),
                child: Center(widthFactor: 1, child: content),
              ),
            ),
          ),
        ),
      ),
    );
  }

  (Color?, Color, Color?) _colors(AppTokens t) => switch (variant) {
    AppButtonVariant.primary => (t.accentStrong, t.onAccent, null),
    AppButtonVariant.brand => (null, Colors.white, null),
    AppButtonVariant.secondary => (t.sunken, t.text, null),
    AppButtonVariant.outline => (Colors.transparent, t.text, t.line),
    AppButtonVariant.ghost => (Colors.transparent, t.accent, null),
    AppButtonVariant.destructive => (t.danger, t.onDanger, null),
  };
}

/// A square icon button with the same variants as [AppButton]. At least
/// 44 by 44 for the tap target, whatever the [size].
class AppIconOnlyButton extends StatelessWidget {
  const AppIconOnlyButton({
    super.key,
    required this.icon,
    required this.onPressed,
    this.variant = AppButtonVariant.ghost,
    this.size = AppButtonSize.medium,
    this.tooltip,
    this.loading = false,
    this.disabled = false,
  });

  final String icon;
  final VoidCallback? onPressed;
  final AppButtonVariant variant;
  final AppButtonSize size;

  /// What the button does: shown on hover and read by screen readers.
  final String? tooltip;
  final bool loading;
  final bool disabled;

  bool get _enabled => !disabled && !loading && onPressed != null;

  @override
  Widget build(BuildContext context) {
    final t = context.tokens;
    final (box, iconSize) = switch (size) {
      AppButtonSize.small => (44.0, 18.0),
      AppButtonSize.medium => (44.0, 20.0),
      AppButtonSize.large => (48.0, 22.0),
    };
    final (Color bg, Color fg) = switch (variant) {
      AppButtonVariant.primary => (t.accentStrong, t.onAccent),
      AppButtonVariant.brand => (t.accentStrong, t.onAccent),
      AppButtonVariant.secondary => (t.sunken, t.text),
      AppButtonVariant.outline => (Colors.transparent, t.text),
      AppButtonVariant.ghost => (Colors.transparent, t.text),
      AppButtonVariant.destructive => (t.danger, t.onDanger),
    };
    final radius = BorderRadius.circular(12);
    Widget button = Semantics(
      button: true,
      enabled: _enabled,
      label: tooltip,
      child: SizedBox.square(
        dimension: box,
        child: Material(
          type: MaterialType.transparency,
          child: Ink(
            decoration: BoxDecoration(
              color: bg,
              borderRadius: radius,
              border: variant == AppButtonVariant.outline
                  ? Border.all(color: t.line)
                  : null,
            ),
            child: InkWell(
              onTap: _enabled
                  ? () {
                      tapHaptic();
                      onPressed!();
                    }
                  : null,
              borderRadius: radius,
              child: Center(
                child: loading
                    ? SizedBox(
                        width: iconSize,
                        height: iconSize,
                        child: CircularProgressIndicator(
                          strokeWidth: 2,
                          valueColor: AlwaysStoppedAnimation(fg),
                        ),
                      )
                    : AppSvgIcon(
                        icon,
                        size: iconSize,
                        color: fg.withValues(alpha: _enabled ? 1 : 0.45),
                      ),
              ),
            ),
          ),
        ),
      ),
    );
    if (tooltip != null) button = Tooltip(message: tooltip!, child: button);
    return button;
  }
}
