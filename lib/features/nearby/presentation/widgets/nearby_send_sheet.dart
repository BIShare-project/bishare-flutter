import 'package:easy_localization/easy_localization.dart';
import 'package:flutter/material.dart';
import 'package:flutter_bloc/flutter_bloc.dart';
import 'package:shadcn_ui/shadcn_ui.dart';

import '../../../../core/ui/app_ui.dart';
import '../../../home/widgets/source_grid.dart';
import '../../../home/widgets/tray_chip.dart';
import '../../../send/domain/sendable_file.dart';
import '../../../send/presentation/tray_cubit.dart';
import '../../domain/nearby_peer.dart';

/// Shown when a peer is tapped on the Nearby radar: pick sources (reusing the
/// SAME tray + source grid as the Share compose) and send the selection straight
/// to [peer] over MPC — no pre-staging on another screen. Any files already in
/// the tray are pre-filled, so it doubles as a quick "send my tray here".
Future<void> showNearbySendSheet(
  BuildContext context, {
  required NearbyPeer peer,
  required void Function(List<SendableFile>) onSend,
}) {
  return showAppSheet<void>(
    context,
    icon: AppIcons.send,
    title: 'nearby.send_to'.tr(namedArgs: {'alias': peer.alias}),
    subtitle: 'nearby.pick_to_share'.tr(),
    builder: (ctx) => _NearbySendBody(onSend: onSend),
  );
}

class _NearbySendBody extends StatelessWidget {
  const _NearbySendBody({required this.onSend});
  final void Function(List<SendableFile>) onSend;

  @override
  Widget build(BuildContext context) {
    final cs = ShadTheme.of(context).colorScheme;
    return BlocBuilder<TrayCubit, List<SendableFile>>(
      builder: (context, items) {
        final tray = context.read<TrayCubit>();
        return Column(
          mainAxisSize: MainAxisSize.min,
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            const SourceGrid(),
            if (items.isNotEmpty) ...[
              Padding(
                padding: const EdgeInsets.only(top: 14, bottom: 2),
                child: Row(
                  children: [
                    Text(
                      'home.tray_summary'.plural(
                        items.length,
                        namedArgs: {'size': formatBytes(tray.totalBytes)},
                      ),
                      style: TextStyle(
                        fontSize: 12.5,
                        fontWeight: FontWeight.w600,
                        color: cs.mutedForeground,
                      ),
                    ),
                    const Spacer(),
                    GestureDetector(
                      onTap: tray.clear,
                      child: Text(
                        'home.clear'.tr(),
                        style: TextStyle(
                          fontSize: 12.5,
                          fontWeight: FontWeight.w600,
                          color: cs.primary,
                        ),
                      ),
                    ),
                  ],
                ),
              ),
              SizedBox(
                height: 52,
                child: ListView.separated(
                  scrollDirection: Axis.horizontal,
                  padding: const EdgeInsets.only(top: 6),
                  itemCount: items.length,
                  separatorBuilder: (_, _) => const SizedBox(width: 8),
                  itemBuilder: (context, i) => TrayChip(
                    file: items[i],
                    onRemove: () => tray.remove(items[i]),
                    onTap: () => showFilePreview(
                      context,
                      path: items[i].path,
                      name: items[i].name,
                      mimeType: items[i].mimeType,
                      size: items[i].size,
                    ),
                  ),
                ),
              ),
            ],
            const SizedBox(height: 16),
            SizedBox(
              width: double.infinity,
              child: ShadButton(
                onPressed: items.isEmpty
                    ? null
                    : () {
                        onSend(List.of(items));
                        Navigator.of(context).pop();
                      },
                child: Text(
                  items.isEmpty
                      ? 'nearby.pick_files'.tr()
                      : 'nearby.send_n'.plural(items.length),
                ),
              ),
            ),
          ],
        );
      },
    );
  }
}
