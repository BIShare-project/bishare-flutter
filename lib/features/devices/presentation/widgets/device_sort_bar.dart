import 'package:flutter/material.dart';
import 'package:shadcn_ui/shadcn_ui.dart';

import '../devices_cubit.dart';

/// The Devices sort control — the same segmented pill style as the History
/// filter bar, over the three roster orders.
class DeviceSortBar extends StatelessWidget {
  const DeviceSortBar({super.key, required this.value, required this.onChanged});
  final DeviceSort value;
  final ValueChanged<DeviceSort> onChanged;

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
            for (final s in DeviceSort.values)
              Expanded(
                child: GestureDetector(
                  onTap: () => onChanged(s),
                  child: AnimatedContainer(
                    duration: const Duration(milliseconds: 150),
                    padding: const EdgeInsets.symmetric(vertical: 7),
                    alignment: Alignment.center,
                    decoration: BoxDecoration(
                      color: value == s ? cs.card : Colors.transparent,
                      borderRadius: BorderRadius.circular(8),
                      boxShadow: value == s
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
                      s.label,
                      style: TextStyle(
                        fontSize: 13,
                        fontWeight: value == s
                            ? FontWeight.w700
                            : FontWeight.w500,
                        color: value == s ? cs.foreground : cs.mutedForeground,
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
