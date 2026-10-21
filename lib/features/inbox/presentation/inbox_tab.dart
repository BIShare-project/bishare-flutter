import 'package:easy_localization/easy_localization.dart';
import 'package:flutter/material.dart';
import 'package:shadcn_ui/shadcn_ui.dart';

import '../../../core/config/feature_flags.dart';
import '../../../core/di/locator.dart';
import '../../../core/ui/app_ui.dart';
import '../../vault/presentation/drive/drive_page.dart';
import 'inbox_page.dart';

/// The Inbox tab. With Drive off for this device (the vault_enabled flag) it
/// is the Inbox page and nothing else, exactly as before. With Drive on, a
/// switch under the title chooses between "On this device" (the Inbox) and
/// "Drive" (drive-plan.md "Product shape": the tab bar keeps its five tabs).
class InboxTab extends StatefulWidget {
  const InboxTab({super.key});

  @override
  State<InboxTab> createState() => _InboxTabState();
}

class _InboxTabState extends State<InboxTab> {
  bool _drive = false;

  @override
  Widget build(BuildContext context) {
    final flags = getIt<FeatureFlags>();
    return ListenableBuilder(
      listenable: flags,
      builder: (context, _) {
        if (!flags.vaultVisible) return const InboxPage();
        final segment = _Segment(
          drive: _drive,
          onChanged: (d) => setState(() => _drive = d),
        );
        return _drive
            ? DrivePage(segment: segment)
            : InboxPage(segment: segment);
      },
    );
  }
}

class _Segment extends StatelessWidget {
  const _Segment({required this.drive, required this.onChanged});

  final bool drive;
  final ValueChanged<bool> onChanged;

  @override
  Widget build(BuildContext context) {
    final cs = ShadTheme.of(context).colorScheme;
    Widget option(String label, bool value) {
      final on = drive == value;
      return Expanded(
        child: GestureDetector(
          behavior: HitTestBehavior.opaque,
          onTap: () {
            if (on) return;
            tapHaptic();
            onChanged(value);
          },
          child: AnimatedContainer(
            duration: const Duration(milliseconds: 180),
            padding: const EdgeInsets.symmetric(vertical: 8),
            decoration: BoxDecoration(
              color: on ? cs.card : Colors.transparent,
              borderRadius: BorderRadius.circular(9),
              border: on ? Border.all(color: cs.border) : null,
            ),
            alignment: Alignment.center,
            child: Text(
              label,
              style: TextStyle(
                fontSize: 13.5,
                fontWeight: on ? FontWeight.w600 : FontWeight.w500,
                color: on ? cs.foreground : cs.mutedForeground,
              ),
            ),
          ),
        ),
      );
    }

    return Padding(
      padding: const EdgeInsets.fromLTRB(16, 2, 16, 8),
      child: Container(
        padding: const EdgeInsets.all(3),
        decoration: BoxDecoration(
          color: cs.muted.withValues(alpha: 0.5),
          borderRadius: BorderRadius.circular(12),
        ),
        child: Row(
          children: [
            option('inbox.segment_device'.tr(), false),
            option('inbox.segment_drive'.tr(), true),
          ],
        ),
      ),
    );
  }
}
