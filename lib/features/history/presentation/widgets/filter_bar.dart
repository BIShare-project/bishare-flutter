import 'package:flutter/material.dart';
import 'package:shadcn_ui/shadcn_ui.dart';

import '../history_cubit.dart';

class FilterBar extends StatelessWidget {
  const FilterBar({super.key, required this.value, required this.onChanged});
  final HistoryFilter value;
  final ValueChanged<HistoryFilter> onChanged;

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
            for (final f in HistoryFilter.values)
              Expanded(
                child: GestureDetector(
                  onTap: () => onChanged(f),
                  child: AnimatedContainer(
                    duration: const Duration(milliseconds: 150),
                    padding: const EdgeInsets.symmetric(vertical: 7),
                    alignment: Alignment.center,
                    decoration: BoxDecoration(
                      color: value == f ? cs.card : Colors.transparent,
                      borderRadius: BorderRadius.circular(8),
                      boxShadow: value == f
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
                      f.label,
                      style: TextStyle(
                        fontSize: 13,
                        fontWeight: value == f
                            ? FontWeight.w700
                            : FontWeight.w500,
                        color: value == f ? cs.foreground : cs.mutedForeground,
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
