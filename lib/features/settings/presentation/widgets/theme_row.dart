import 'package:flutter/material.dart';
import 'package:shadcn_ui/shadcn_ui.dart';

import '../../../../core/ui/app_svg_icon.dart';
import 'glyph.dart';
import 'theme_segmented.dart';

class ThemeRow extends StatelessWidget {
  const ThemeRow({super.key, required this.value, required this.onChanged});
  final ThemeMode value;
  final ValueChanged<ThemeMode> onChanged;

  @override
  Widget build(BuildContext context) {
    final cs = ShadTheme.of(context).colorScheme;
    return Padding(
      padding: const EdgeInsets.fromLTRB(14, 11, 14, 11),
      child: Row(
        children: [
          const Glyph(AppIcons.sunMoon),
          const SizedBox(width: 14),
          Text(
            'Theme',
            style: TextStyle(
              fontSize: 15.5,
              fontWeight: FontWeight.w600,
              color: cs.foreground,
            ),
          ),
          const Spacer(),
          ThemeSegmented(value: value, onChanged: onChanged),
        ],
      ),
    );
  }
}
