import 'package:flutter/material.dart';
import 'package:shadcn_ui/shadcn_ui.dart';

import '../../domain/settings.dart' as s;
import 'glyph.dart';
import 'swatch.dart';

class AccentRow extends StatelessWidget {
  const AccentRow({super.key, 
    required this.icon,
    required this.label,
    required this.selected,
    required this.onChanged,
  });

  final String icon;
  final String label;
  final String selected;
  final ValueChanged<String> onChanged;

  @override
  Widget build(BuildContext context) {
    final theme = ShadTheme.of(context);
    final cs = theme.colorScheme;
    final brightness = theme.brightness;
    return Padding(
      padding: const EdgeInsets.fromLTRB(14, 12, 14, 14),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Row(
            children: [
              Glyph(icon),
              const SizedBox(width: 14),
              Text(
                label,
                style: TextStyle(
                  fontSize: 15.5,
                  fontWeight: FontWeight.w600,
                  color: cs.foreground,
                ),
              ),
            ],
          ),
          const SizedBox(height: 13),
          // All shadcn accents on one tidy, full-width row.
          Row(
            mainAxisAlignment: MainAxisAlignment.spaceBetween,
            children: [
              for (final name in s.AccentColors.names)
                Swatch(
                  color: s.AccentColors.of(name, brightness),
                  selected: selected == name,
                  onTap: () => onChanged(name),
                ),
            ],
          ),
        ],
      ),
    );
  }
}
