import 'package:flutter/material.dart';
import 'package:shadcn_ui/shadcn_ui.dart';

import '../../../../core/ui/app_ui.dart';
import 'glyph.dart';

class SwitchRow extends StatelessWidget {
  const SwitchRow({super.key, 
    required this.icon,
    required this.title,
    required this.subtitle,
    required this.value,
    required this.onChanged,
  });

  final String icon;
  final String title;
  final String subtitle;
  final bool value;
  final ValueChanged<bool> onChanged;

  @override
  Widget build(BuildContext context) {
    return AppListTile(
      leading: Glyph(icon),
      title: Text(title),
      subtitle: Text(subtitle),
      trailing: ShadSwitch(value: value, onChanged: onChanged),
    );
  }
}
