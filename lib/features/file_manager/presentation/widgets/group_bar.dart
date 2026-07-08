import 'package:flutter/material.dart';
import 'package:shadcn_ui/shadcn_ui.dart';

import '../../domain/managed_file.dart';

class GroupBar extends StatelessWidget {
  const GroupBar({super.key, required this.value, required this.onChanged});
  final GroupMode value;
  final ValueChanged<GroupMode> onChanged;

  @override
  Widget build(BuildContext context) {
    final cs = ShadTheme.of(context).colorScheme;
    return Padding(
      padding: const EdgeInsets.fromLTRB(14, 10, 14, 2),
      child: Container(
        padding: const EdgeInsets.all(3),
        decoration: BoxDecoration(
          color: cs.muted,
          borderRadius: BorderRadius.circular(10),
        ),
        child: Row(
          children: [
            for (final g in GroupMode.values)
              Expanded(
                child: GestureDetector(
                  onTap: () => onChanged(g),
                  child: AnimatedContainer(
                    duration: const Duration(milliseconds: 150),
                    padding: const EdgeInsets.symmetric(vertical: 7),
                    alignment: Alignment.center,
                    decoration: BoxDecoration(
                      color: value == g ? cs.card : Colors.transparent,
                      borderRadius: BorderRadius.circular(8),
                    ),
                    child: Text(
                      g.label,
                      style: TextStyle(
                        fontSize: 13,
                        fontWeight: value == g
                            ? FontWeight.w700
                            : FontWeight.w500,
                        color: value == g ? cs.foreground : cs.mutedForeground,
                      ),
                    ),
                  ),
                ),
              ),
          ],
        ),
      ),
    );
  }
}
