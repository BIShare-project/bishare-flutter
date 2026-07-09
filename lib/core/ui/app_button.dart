import 'package:flutter/material.dart';
import 'package:shadcn_ui/shadcn_ui.dart';

import 'app_format.dart';
import 'app_svg_icon.dart';

/// BIShare button variants — matches shadcn_ui conventions.
enum AppButtonVariant {
  /// Filled primary brand color with premium gradient (default call-to-action)
  primary,

  /// Filled secondary/neutral color (less prominent actions)
  secondary,

  /// Transparent with border (outline style)
  outline,

  /// Ghost button (no background, hover effects only)
  ghost,

  /// Destructive red for dangerous actions (delete, remove)
  destructive,
}

/// BIShare button sizes — consistent spacing and type scale.
enum AppButtonSize {
  /// Compact 32px height for tight spaces
  small,

  /// Default 40px height for most use cases
  medium,

  /// Large 48px height for prominent actions
  large,
}

/// A premium BIShare button with consistent styling, haptic feedback, and
/// multiple variants/sizes. Replaces raw ElevatedButton/TextButton use.
///
/// Example:
/// ```dart
/// AppButton(
///   label: 'Send Files',
///   icon: AppIcons.send,
///   variant: AppButtonVariant.primary,
///   onPressed: _handleSend,
/// )
/// ```
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

  /// The button text label.
  final String label;

  /// Callback when the button is pressed.
  final VoidCallback? onPressed;

  /// Optional [AppIcons] name rendered to the left of the label.
  final String? icon;

  /// Visual style variant.
  final AppButtonVariant variant;

  /// Button size affecting height, padding, and font size.
  final AppButtonSize size;

  /// If true, expands to fill the parent width.
  final bool fullWidth;

  /// Shows a loading spinner and disables interaction.
  final bool loading;

  /// Disables the button without loading state.
  final bool disabled;

  bool get _enabled => !disabled && !loading && onPressed != null;

  @override
  Widget build(BuildContext context) {
    final cs = ShadTheme.of(context).colorScheme;

    // Size configuration with premium spacing
    final height = switch (size) {
      AppButtonSize.small => 36.0,
      AppButtonSize.medium => 44.0,
      AppButtonSize.large => 52.0,
    };

    final horizontalPadding = switch (size) {
      AppButtonSize.small => 14.0,
      AppButtonSize.medium => 18.0,
      AppButtonSize.large => 22.0,
    };

    final fontSize = switch (size) {
      AppButtonSize.small => 13.0,
      AppButtonSize.medium => 15.0,
      AppButtonSize.large => 16.0,
    };

    final letterSpacing = switch (size) {
      AppButtonSize.small => 0.2,
      AppButtonSize.medium => 0.3,
      AppButtonSize.large => 0.4,
    };

    final iconSize = switch (size) {
      AppButtonSize.small => 15.0,
      AppButtonSize.medium => 17.0,
      AppButtonSize.large => 19.0,
    };

    // Premium border radius - slightly more modern squircle
    final borderRadius = BorderRadius.circular(13);

    // Variant styling with gradients and shadows
    final primaryGradient = LinearGradient(
      begin: Alignment(-1.0, -0.5),
      end: Alignment(1.0, 0.5),
      colors: [
        cs.primary.withValues(alpha: 0.98),
        cs.primary.withValues(alpha: 0.92),
      ],
      stops: const [0.0, 1.0],
    );

    final bgColor = switch (variant) {
      AppButtonVariant.primary => null, // Handled by gradient
      AppButtonVariant.secondary => cs.muted,
      AppButtonVariant.outline => Colors.transparent,
      AppButtonVariant.ghost => Colors.transparent,
      AppButtonVariant.destructive => cs.destructive,
    };

    final fgColor = switch (variant) {
      AppButtonVariant.primary => cs.primaryForeground,
      AppButtonVariant.secondary => cs.mutedForeground,
      AppButtonVariant.outline => cs.foreground,
      AppButtonVariant.ghost => cs.foreground,
      AppButtonVariant.destructive => cs.destructiveForeground,
    };

    final borderColor = switch (variant) {
      AppButtonVariant.primary => Colors.transparent,
      AppButtonVariant.secondary => Colors.transparent,
      AppButtonVariant.outline => cs.border.withValues(alpha: 0.65),
      AppButtonVariant.ghost => Colors.transparent,
      AppButtonVariant.destructive => Colors.transparent,
    };

    // Premium shadow elevation
    final shadow = switch (variant) {
      AppButtonVariant.primary => [
          BoxShadow(
            color: cs.primary.withValues(alpha: 0.18),
            blurRadius: 12,
            offset: const Offset(0, 4),
            spreadRadius: -2,
          ),
          BoxShadow(
            color: Colors.black.withValues(alpha: 0.04),
            blurRadius: 6,
            offset: const Offset(0, 2),
          ),
        ],
      AppButtonVariant.destructive => [
          BoxShadow(
            color: cs.destructive.withValues(alpha: 0.15),
            blurRadius: 10,
            offset: const Offset(0, 3),
          ),
        ],
      _ => null,
    };

    final button = AnimatedScale(
      duration: const Duration(milliseconds: 180),
      curve: Curves.easeOutCubic,
      scale: _enabled ? 1.0 : 0.97,
      child: AnimatedContainer(
        duration: const Duration(milliseconds: 180),
        curve: Curves.easeOutCubic,
        height: height,
        width: fullWidth ? double.infinity : null,
        child: Material(
          color: Colors.transparent,
          child: InkWell(
            onTap: _enabled
                ? () {
                    tapHaptic();
                    onPressed!();
                  }
                : null,
            borderRadius: borderRadius,
            splashColor: cs.primary.withValues(alpha: 0.12),
            highlightColor: cs.primary.withValues(alpha: 0.08),
            child: AnimatedContainer(
              duration: const Duration(milliseconds: 200),
              curve: Curves.easeOut,
              padding: EdgeInsets.symmetric(horizontal: horizontalPadding),
              decoration: BoxDecoration(
                gradient: variant == AppButtonVariant.primary && _enabled
                    ? primaryGradient
                    : null,
                color: variant != AppButtonVariant.primary || !_enabled
                    ? (_enabled ? bgColor : cs.muted.withValues(alpha: 0.45))
                    : null,
                borderRadius: borderRadius,
                border: borderColor != Colors.transparent
                    ? Border.all(color: borderColor, width: 1.2)
                    : null,
                boxShadow: _enabled ? shadow : null,
              ),
              child: Center(
                child: loading
                    ? SizedBox(
                        width: iconSize * 1.4,
                        height: iconSize * 1.4,
                        child: CircularProgressIndicator(
                          strokeWidth: 2.2,
                          valueColor: AlwaysStoppedAnimation(
                            fgColor.withValues(alpha: 0.9),
                          ),
                        ),
                      )
                    : Row(
                        mainAxisSize: MainAxisSize.min,
                        mainAxisAlignment: MainAxisAlignment.center,
                        crossAxisAlignment: CrossAxisAlignment.center,
                        children: [
                          if (icon != null) ...[
                            AppSvgIcon(icon!, size: iconSize, color: fgColor),
                            const SizedBox(width: 10),
                          ],
                          Text(
                            label,
                            style: TextStyle(
                              fontSize: fontSize,
                              fontWeight: FontWeight.w600,
                              color: fgColor,
                              height: 1.15,
                              letterSpacing: letterSpacing,
                            ),
                            textAlign: TextAlign.center,
                          ),
                        ],
                      ),
              ),
            ),
          ),
        ),
      ),
    );

    if (fullWidth) {
      return button;
    }

    return button;
  }
}

/// An icon-only button for compact actions (e.g. close, add, remove).
///
/// Unlike [AppIconButton] (ghost style), this supports filled variants and
/// consistent sizing with [AppButton].
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

  /// An [AppIcons] name rendered with [AppSvgIcon].
  final String icon;
  final VoidCallback? onPressed;
  final AppButtonVariant variant;
  final AppButtonSize size;
  final String? tooltip;

  /// Shows a loading spinner and disables interaction.
  final bool loading;

  /// Disables the button without loading state.
  final bool disabled;

  bool get _enabled => !disabled && !loading && onPressed != null;

  @override
  Widget build(BuildContext context) {
    final cs = ShadTheme.of(context).colorScheme;

    final buttonSize = switch (size) {
      AppButtonSize.small => 32.0,
      AppButtonSize.medium => 40.0,
      AppButtonSize.large => 48.0,
    };

    final iconSize = switch (size) {
      AppButtonSize.small => 14.0,
      AppButtonSize.medium => 16.0,
      AppButtonSize.large => 18.0,
    };

    final bgColor = switch (variant) {
      AppButtonVariant.primary => cs.primary,
      AppButtonVariant.secondary => cs.muted,
      AppButtonVariant.outline => Colors.transparent,
      AppButtonVariant.ghost => Colors.transparent,
      AppButtonVariant.destructive => cs.destructive,
    };

    final fgColor = switch (variant) {
      AppButtonVariant.primary => cs.primaryForeground,
      AppButtonVariant.secondary => cs.mutedForeground,
      AppButtonVariant.outline => cs.foreground,
      AppButtonVariant.ghost => cs.foreground,
      AppButtonVariant.destructive => cs.destructiveForeground,
    };

    final borderColor = variant == AppButtonVariant.outline ? cs.border : null;

    final button = SizedBox.square(
      dimension: buttonSize,
      child: Material(
        color: Colors.transparent,
        child: InkWell(
          onTap: _enabled
              ? () {
                  tapHaptic();
                  onPressed!();
                }
              : null,
          borderRadius: BorderRadius.circular(10),
          child: Container(
            decoration: BoxDecoration(
              color: _enabled ? bgColor : cs.muted.withValues(alpha: 0.5),
              borderRadius: BorderRadius.circular(10),
              border: borderColor != null
                  ? Border.all(color: borderColor)
                  : null,
            ),
            child: Center(
              child: loading
                  ? SizedBox(
                      width: iconSize,
                      height: iconSize,
                      child: CircularProgressIndicator(
                        strokeWidth: 2,
                        valueColor: AlwaysStoppedAnimation(fgColor),
                      ),
                    )
                  : AppSvgIcon(icon, size: iconSize, color: fgColor),
            ),
          ),
        ),
      ),
    );

    if (tooltip != null) {
      return Tooltip(message: tooltip!, child: button);
    }

    return button;
  }
}
