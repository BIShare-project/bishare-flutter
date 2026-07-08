import 'package:flutter/material.dart';
import 'package:shadcn_ui/shadcn_ui.dart';

class ThemeSegmented extends StatelessWidget {
  const ThemeSegmented({super.key, required this.value, required this.onChanged});
  final ThemeMode value;
  final ValueChanged<ThemeMode> onChanged;

  static const _options = {
    ThemeMode.system: 'Auto',
    ThemeMode.light: 'Light',
    ThemeMode.dark: 'Dark',
  };

  @override
  Widget build(BuildContext context) {
    final cs = ShadTheme.of(context).colorScheme;
    return Container(
      padding: const EdgeInsets.all(3),
      decoration: BoxDecoration(
        color: cs.muted,
        borderRadius: BorderRadius.circular(10),
      ),
      child: Row(
        mainAxisSize: MainAxisSize.min,
        children: [
          for (final e in _options.entries)
            GestureDetector(
              onTap: () => onChanged(e.key),
              child: AnimatedContainer(
                duration: const Duration(milliseconds: 150),
                padding: const EdgeInsets.symmetric(
                  horizontal: 12,
                  vertical: 5,
                ),
                decoration: BoxDecoration(
                  color: value == e.key ? cs.card : Colors.transparent,
                  borderRadius: BorderRadius.circular(8),
                  boxShadow: value == e.key
                      ? [
                          BoxShadow(
                            color: Colors.black.withValues(alpha: 0.08),
                            blurRadius: 4,
                            offset: const Offset(0, 1),
                          ),
                        ]
                      : null,
                ),
                child: Text(
                  e.value,
                  style: TextStyle(
                    fontSize: 12.5,
                    fontWeight: value == e.key
                        ? FontWeight.w700
                        : FontWeight.w500,
                    color: value == e.key ? cs.foreground : cs.mutedForeground,
                  ),
                ),
              ),
            ),
        ],
      ),
    );
  }
}
