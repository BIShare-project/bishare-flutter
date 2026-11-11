import 'package:easy_localization/easy_localization.dart';
import 'package:flutter/material.dart';

import '../io/picked_mtime.dart';

/// "Preparing…" over the app while the system picker hands over the files
/// just chosen (Android copies each one first: seconds for a large video),
/// so the app does not look stuck between the picker closing and the files
/// showing up.
class PickingOverlay extends StatelessWidget {
  const PickingOverlay({super.key, required this.child});

  final Widget child;

  @override
  Widget build(BuildContext context) {
    return Stack(
      children: [
        child,
        ValueListenableBuilder<bool>(
          valueListenable: filePickerBusy,
          builder: (context, busy, _) {
            if (!busy) return const SizedBox.shrink();
            final scheme = Theme.of(context).colorScheme;
            return Positioned.fill(
              child: ColoredBox(
                color: scheme.scrim.withValues(alpha: 0.32),
                child: Center(
                  child: Material(
                    color: scheme.surfaceContainerHigh,
                    borderRadius: BorderRadius.circular(16),
                    child: Padding(
                      padding: const EdgeInsets.symmetric(
                        horizontal: 24,
                        vertical: 20,
                      ),
                      child: Row(
                        mainAxisSize: MainAxisSize.min,
                        children: [
                          SizedBox.square(
                            dimension: 22,
                            child: CircularProgressIndicator(
                              strokeWidth: 2.5,
                              color: scheme.primary,
                            ),
                          ),
                          const SizedBox(width: 16),
                          Text(
                            'home.preparing'.tr(),
                            style: Theme.of(context).textTheme.bodyLarge,
                          ),
                        ],
                      ),
                    ),
                  ),
                ),
              ),
            );
          },
        ),
      ],
    );
  }
}
