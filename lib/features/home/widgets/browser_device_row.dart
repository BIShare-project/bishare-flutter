import 'dart:io';

import 'package:easy_localization/easy_localization.dart';
import 'package:flutter/material.dart';
import 'package:flutter_bloc/flutter_bloc.dart';

import '../../../core/ui/app_ui.dart';
import '../../../core/io/picked_mtime.dart';
import '../../send/presentation/send_selection_cubit.dart';
import '../../web_nearby/data/web_nearby_service.dart';
import '../../web_nearby/presentation/web_nearby_cubit.dart';

/// A browser peer on the HOME device list (the app↔web Nearby bridge) —
/// styled like [DeviceRow] and behaving the same way: tapping sends the staged
/// tray; with an empty tray it opens the file picker. Bytes go browser-ward
/// over WebRTC; results surface as the main-shell toasts.
class BrowserDeviceRow extends StatelessWidget {
  const BrowserDeviceRow({
    super.key,
    required this.peer,
    required this.sending,
  });

  final WebNearbyPeer peer;
  final bool sending;

  Future<void> _send(BuildContext context) async {
    final cubit = context.read<WebNearbyCubit>();
    final selection = context.read<SendSelectionCubit>();
    List<File> files;
    if (selection.state.isNotEmpty) {
      final batch = await selection.materialize();
      files = [for (final f in batch) File(f.path)];
      selection.clear();
    } else {
      final paths = await pickFilePaths();
      if (paths.isEmpty) return;
      files = [for (final p in paths) File(p)];
    }
    await cubit.sendFiles(peer.peerId, files);
  }

  @override
  Widget build(BuildContext context) {
    final t = context.tokens;
    return AppListTile(
      onTap: sending ? null : () => _send(context),
      leading: Container(
        width: 36,
        height: 36,
        alignment: Alignment.center,
        decoration: BoxDecoration(
          color: t.accent.withValues(alpha: 0.10),
          borderRadius: BorderRadius.circular(10),
        ),
        child: Text(peer.emoji, style: const TextStyle(fontSize: 18)),
      ),
      title: Text(peer.alias, maxLines: 1, overflow: TextOverflow.ellipsis),
      subtitle: Text('devices.browser_subtitle'.tr()),
      trailing: sending
          ? const SizedBox(
              width: 18,
              height: 18,
              child: CircularProgressIndicator(strokeWidth: 2),
            )
          : AppSvgIcon(AppIcons.send, size: 18, color: t.accent),
    );
  }
}
