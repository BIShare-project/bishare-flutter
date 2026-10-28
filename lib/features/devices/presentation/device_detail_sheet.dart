import 'package:easy_localization/easy_localization.dart';
import 'package:flutter/material.dart';
import 'package:flutter_bloc/flutter_bloc.dart';

import '../../../core/devices/device_registry.dart';
import '../../../core/storage/app_database.dart';
import '../../../core/ui/app_ui.dart';
import '../../favorites/presentation/favorites_cubit.dart';
import 'devices_cubit.dart';

/// A localized relative sighting time: "just now", "5 minutes ago",
/// "2 hours ago", "3 days ago", then a plain date for anything older.
/// [now] is injectable for tests.
String relativeLastSeen(DateTime lastSeen, {DateTime? now}) {
  final diff = (now ?? DateTime.now()).difference(lastSeen);
  if (diff.inMinutes < 1) return 'devices.just_now'.tr();
  if (diff.inHours < 1) return 'devices.minutes_ago'.plural(diff.inMinutes);
  if (diff.inDays < 1) return 'devices.hours_ago'.plural(diff.inHours);
  if (diff.inDays < 7) return 'devices.days_ago'.plural(diff.inDays);
  String p(int v) => v.toString().padLeft(2, '0');
  return '${lastSeen.year}-${p(lastSeen.month)}-${p(lastSeen.day)}';
}

/// "Model · online" or "Model · last seen 5 minutes ago".
String deviceSubtitle(KnownDeviceView d) {
  final presence = d.isOnline
      ? 'devices.online'.tr()
      : 'devices.last_seen'.tr(
          namedArgs: {'when': relativeLastSeen(d.lastSeen)},
        );
  final model = d.deviceModel;
  return (model == null || model.isEmpty) ? presence : '$model · $presence';
}

/// The per-device sheet, flat like the other sheets: what to do (rename,
/// favorite, auto-accept), what this device is (address, transfers with it,
/// from history by fingerprint), then forget.
Future<void> showDeviceDetailSheet(
  BuildContext context,
  KnownDeviceView device,
) {
  final devices = context.read<DevicesCubit>();
  final favorites = context.read<FavoritesCubit>();
  return showAppSheet<void>(
    context,
    leading: AppAvatar(
      icon: iconForDevice(device.deviceType ?? 'mobile'),
      size: 48,
      online: device.isOnline,
    ),
    title: device.displayName,
    subtitle: deviceSubtitle(device),
    builder: (ctx) => _DeviceDetailBody(
      device: device,
      devices: devices,
      favorites: favorites,
      rootContext: context,
    ),
  );
}

class _DeviceDetailBody extends StatefulWidget {
  const _DeviceDetailBody({
    required this.device,
    required this.devices,
    required this.favorites,
    required this.rootContext,
  });

  final KnownDeviceView device;
  final DevicesCubit devices;
  final FavoritesCubit favorites;

  /// The page context that opened the sheet, for follow-up prompts and
  /// toasts after this sheet pops.
  final BuildContext rootContext;

  @override
  State<_DeviceDetailBody> createState() => _DeviceDetailBodyState();
}

class _DeviceDetailBodyState extends State<_DeviceDetailBody> {
  // Memoized so the FutureBuilder doesn't refetch on every rebuild.
  late final Future<DeviceTransferStats> _stats = widget.devices.statsFor(
    widget.device.fingerprint,
  );

  @override
  Widget build(BuildContext context) {
    final d = widget.device;
    return BlocBuilder<FavoritesCubit, Map<String, FavoriteDevice>>(
      bloc: widget.favorites,
      builder: (context, favs) {
        final fav = favs[d.fingerprint];
        final autoAccept = fav?.autoAccept ?? false;
        return Column(
          mainAxisSize: MainAxisSize.min,
          crossAxisAlignment: CrossAxisAlignment.stretch,
          children: [
            AppSheetGroup(
              first: true,
              children: [
                AppSheetAction(
                  icon: AppIcons.renameEdit,
                  label: 'devices.rename'.tr(),
                  onTap: () {
                    Navigator.pop(context);
                    _rename(d.displayName);
                  },
                ),
                AppSheetAction(
                  icon: AppIcons.starFavorite,
                  label: fav != null
                      ? 'devices.remove_favorite'.tr()
                      : 'devices.add_favorite'.tr(),
                  onTap: () => widget.favorites.toggleFingerprint(
                    d.fingerprint,
                    name: d.displayName,
                  ),
                ),
                AppSheetAction(
                  icon: autoAccept ? AppIcons.successSent : AppIcons.check,
                  label: autoAccept
                      ? 'devices.auto_accept_on'.tr()
                      : 'devices.turn_on_auto_accept'.tr(),
                  selected: autoAccept,
                  onTap: () => widget.favorites.setAutoAcceptFingerprint(
                    d.fingerprint,
                    !autoAccept,
                    name: d.displayName,
                  ),
                ),
              ],
            ),
            _Stats(stats: _stats, ip: d.lastIp),
            // A device that is online would reappear on the next discovery
            // sighting anyway, so forgetting is only offered when it is gone.
            if (!d.isOnline)
              AppSheetGroup(
                children: [
                  AppSheetAction(
                    icon: AppIcons.trashDelete,
                    label: 'devices.remove_device'.tr(),
                    destructive: true,
                    onTap: () {
                      Navigator.pop(context);
                      widget.devices.remove(d.fingerprint);
                      if (widget.rootContext.mounted) {
                        toast(
                          widget.rootContext,
                          'devices.device_removed'.tr(),
                        );
                      }
                    },
                  ),
                ],
              ),
          ],
        );
      },
    );
  }

  /// The same rename prompt as the Home device row, but by fingerprint so it
  /// also works for peers that are offline right now.
  Future<void> _rename(String current) async {
    final context = widget.rootContext;
    if (!context.mounted) return;
    final controller = TextEditingController(text: current);
    final name = await showAppSheet<String>(
      context,
      icon: AppIcons.renameEdit,
      title: 'devices.rename_device'.tr(),
      builder: (ctx) {
        void submit() => Navigator.pop(ctx, controller.text);
        return Column(
          mainAxisSize: MainAxisSize.min,
          children: [
            AppTextField(
              controller: controller,
              autofocus: true,
              hint: 'devices.device_name'.tr(),
              onSubmitted: (_) => submit(),
            ),
            const SizedBox(height: 14),
            AppButton(
              label: 'devices.save'.tr(),
              fullWidth: true,
              onPressed: submit,
            ),
          ],
        );
      },
    );
    controller.dispose();
    if (name != null && name.trim().isNotEmpty) {
      await widget.favorites.rename(widget.device.fingerprint, name.trim());
    }
  }
}

/// The facts: the last address, sent and received totals, and the last
/// transfer with this peer.
class _Stats extends StatelessWidget {
  const _Stats({required this.stats, required this.ip});
  final Future<DeviceTransferStats> stats;
  final String? ip;

  @override
  Widget build(BuildContext context) {
    final t = context.tokens;
    return FutureBuilder<DeviceTransferStats>(
      future: stats,
      builder: (context, snap) {
        final s = snap.data;
        final hasIp = ip != null && ip!.isNotEmpty;
        return AppSheetGroup(
          children: [
            if (hasIp) AppSheetInfo('devices.address'.tr(), ip!),
            if (s == null)
              const SizedBox(height: 40)
            else if (s.isEmpty)
              Padding(
                padding: const EdgeInsets.symmetric(horizontal: 4, vertical: 9),
                child: Text(
                  'devices.no_transfers'.tr(),
                  style: AppType.body.copyWith(color: t.text2),
                ),
              )
            else ...[
              AppSheetInfo(
                'devices.stat_sent'.tr(),
                '${'devices.files_count'.plural(s.sentCount)} · '
                '${formatBytes(s.sentBytes)}',
              ),
              AppSheetInfo(
                'devices.stat_received'.tr(),
                '${'devices.files_count'.plural(s.receivedCount)} · '
                '${formatBytes(s.receivedBytes)}',
              ),
              if (s.lastTransfer != null)
                AppSheetInfo(
                  'devices.last_transfer'.tr(),
                  '${s.lastTransfer!.fileName} · '
                  '${relativeLastSeen(s.lastTransfer!.timestamp)}',
                ),
            ],
          ],
        );
      },
    );
  }
}
