import 'package:flutter/material.dart';

import '../theme/app_tokens.dart';
import '../theme/app_type.dart';
import 'app_list_tile.dart';
import 'app_sheet.dart';
import 'app_svg_icon.dart';

/// The leading glyph of a row: the icon alone in the secondary colour, no
/// tile behind it (redesign-plan.md "Cards").
class AppGlyph extends StatelessWidget {
  const AppGlyph(this.icon, {super.key, this.color});

  final String icon;
  final Color? color;

  @override
  Widget build(BuildContext context) =>
      AppSvgIcon(icon, size: 22, color: color ?? context.tokens.text2);
}

/// A row with a switch: the glyph, the title, an optional subtitle and the
/// switch. The whole row toggles, not only the switch.
class AppSwitchRow extends StatelessWidget {
  const AppSwitchRow({
    super.key,
    this.icon,
    required this.title,
    this.subtitle,
    required this.value,
    required this.onChanged,
  });

  final String? icon;
  final String title;
  final String? subtitle;
  final bool value;

  /// Null disables the row.
  final ValueChanged<bool>? onChanged;

  @override
  Widget build(BuildContext context) {
    return MergeSemantics(
      child: AppListTile(
        leading: icon == null ? null : AppGlyph(icon!),
        title: Text(title),
        subtitle: subtitle == null || subtitle!.isEmpty
            ? null
            : Text(subtitle!),
        onTap: onChanged == null ? null : () => onChanged!(!value),
        trailing: AppSwitch(value: value, onChanged: onChanged),
      ),
    );
  }
}

/// A row that shows a current value and opens something on tap: the glyph,
/// the title, the value in the secondary colour, a chevron.
class AppValueRow extends StatelessWidget {
  const AppValueRow({
    super.key,
    this.icon,
    required this.title,
    this.subtitle,
    this.value,
    this.onTap,
    this.chevron = true,
    this.destructive = false,
  });

  final String? icon;
  final String title;
  final String? subtitle;
  final String? value;
  final VoidCallback? onTap;
  final bool chevron;
  final bool destructive;

  @override
  Widget build(BuildContext context) {
    final t = context.tokens;
    return AppListTile(
      leading: icon == null
          ? null
          : AppGlyph(icon!, color: destructive ? t.danger : null),
      title: Text(
        title,
        style: destructive ? TextStyle(color: t.danger) : null,
      ),
      subtitle: subtitle == null || subtitle!.isEmpty ? null : Text(subtitle!),
      onTap: onTap,
      trailing: (value == null && !chevron)
          ? null
          : Row(
              mainAxisSize: MainAxisSize.min,
              children: [
                if (value != null)
                  ConstrainedBox(
                    constraints: const BoxConstraints(maxWidth: 170),
                    child: Text(
                      value!,
                      maxLines: 1,
                      overflow: TextOverflow.ellipsis,
                      style: AppType.secondary.copyWith(
                        fontSize: 14,
                        color: t.text2,
                      ),
                    ),
                  ),
                if (chevron && onTap != null) ...[
                  const SizedBox(width: 4),
                  AppSvgIcon(
                    Directionality.of(context) == TextDirection.rtl
                        ? AppIcons.chevronLeft
                        : AppIcons.chevronRight,
                    size: 18,
                    color: t.text3,
                  ),
                ],
              ],
            ),
    );
  }
}

/// A row that shows its current value; a tap opens a sheet with
/// every option, the one in force checked.
class AppSelectRow<T> extends StatelessWidget {
  const AppSelectRow({
    super.key,
    required this.icon,
    required this.title,
    required this.value,
    required this.values,
    required this.label,
    required this.onChanged,
    this.description,
  });

  final String icon;
  final String title;
  final T value;
  final List<T> values;
  final String Function(T) label;
  final ValueChanged<T> onChanged;

  /// Optional one-line explanation under each option in the sheet, so the
  /// user understands the choice while picking (e.g. what each Transport does).
  final String Function(T)? description;

  Future<void> _pick(BuildContext context) async {
    final picked = await showAppSheet<T>(
      context,
      icon: icon,
      title: title,
      builder: (ctx) => AppSheetGroup(
        first: true,
        indent: 4,
        children: [
          for (final o in values)
            AppSheetAction(
              label: label(o),
              subtitle: description?.call(o),
              selected: o == value,
              onTap: () => Navigator.pop(ctx, o),
            ),
        ],
      ),
    );
    if (picked != null && picked != value) onChanged(picked);
  }

  @override
  Widget build(BuildContext context) => AppValueRow(
    icon: icon,
    title: title,
    value: label(value),
    onTap: () => _pick(context),
  );
}

/// The app's switch: the accent track when on, the sunken colour when off,
/// a white thumb. Null [onChanged] disables it.
class AppSwitch extends StatelessWidget {
  const AppSwitch({super.key, required this.value, required this.onChanged});

  final bool value;
  final ValueChanged<bool>? onChanged;

  @override
  Widget build(BuildContext context) {
    final t = context.tokens;
    return Switch(
      value: value,
      onChanged: onChanged,
      materialTapTargetSize: MaterialTapTargetSize.shrinkWrap,
      activeThumbColor: Colors.white,
      activeTrackColor: t.accent,
      inactiveThumbColor: Colors.white,
      inactiveTrackColor: t.sunken,
      trackOutlineColor: WidgetStatePropertyAll(
        value ? Colors.transparent : t.line,
      ),
    );
  }
}
