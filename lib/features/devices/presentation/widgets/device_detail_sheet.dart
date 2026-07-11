import 'package:easy_localization/easy_localization.dart';
import 'package:flutter/material.dart';
import 'package:flutter_bloc/flutter_bloc.dart';
import 'package:shadcn_ui/shadcn_ui.dart';

import '../../../../core/devices/device_registry.dart';
import '../../../../core/storage/app_database.dart';
import '../../../../core/ui/app_ui.dart';
import '../../../favorites/presentation/favorites_cubit.dart';
import '../devices_cubit.dart';
import 'last_seen.dart';

/// The per-device sheet on the Devices dashboard: transfer statistics with
/// this peer (from history, matched by fingerprint) and the management
/// actions — rename, favorite toggle, auto-accept toggle, and forget.
Future<void> showDeviceDetailSheet(
  BuildContext context,
  KnownDeviceView device,
) {
  final devices = context.read<DevicesCubit>();
  final favorites = context.read<FavoritesCubit>();
  return showAppSheet<void>(
    context,
    icon: iconForDevice(device.deviceType ?? 'mobile'),
    title: device.displayName,
    subtitle: _subtitle(device),
    builder: (ctx) => _DeviceDetailBody(
      device: device,
      devices: devices,
      favorites: favorites,
      rootContext: context,
    ),
  );
}

String _subtitle(KnownDeviceView d) {
  final presence = d.isOnline
      ? 'devices.online'.tr()
      : 'devices.last_seen'.tr(namedArgs: {'when': relativeLastSeen(d.lastSeen)});
  return [
    if (d.deviceModel != null && d.deviceModel!.isNotEmpty) d.deviceModel!,
    if (d.lastIp != null && d.lastIp!.isNotEmpty) d.lastIp!,
    presence,
  ].join(' · ');
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

  /// The page context that opened the sheet — used for follow-up prompts and
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
          children: [
            _StatsCard(stats: _stats),
            const SizedBox(height: 10),
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
              onTap: () => widget.favorites.setAutoAcceptFingerprint(
                d.fingerprint,
                !autoAccept,
                name: d.displayName,
              ),
            ),
            // A device that is online would reappear on the next discovery
            // sighting anyway, so forgetting is only offered when it is gone.
            if (!d.isOnline)
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
            ShadInput(
              controller: controller,
              autofocus: true,
              placeholder: Text('devices.device_name'.tr()),
              onSubmitted: (_) => submit(),
            ),
            const SizedBox(height: 14),
            AppButton(
              label: 'devices.save'.tr(),
              variant: AppButtonVariant.primary,
              size: AppButtonSize.medium,
              fullWidth: true,
              onPressed: submit,
            ),
          ],
        );
      },
    );
    if (name != null && name.trim().isNotEmpty) {
      await widget.favorites.rename(widget.device.fingerprint, name.trim());
    }
  }
}

/// Sent/received totals + the last transfer with this peer.
class _StatsCard extends StatelessWidget {
  const _StatsCard({required this.stats});
  final Future<DeviceTransferStats> stats;

  @override
  Widget build(BuildContext context) {
    final cs = ShadTheme.of(context).colorScheme;
    return FutureBuilder<DeviceTransferStats>(
      future: stats,
      builder: (context, snap) {
        final s = snap.data;
        if (s == null) return const SizedBox(height: 24);
        if (s.isEmpty) {
          return Padding(
            padding: const EdgeInsets.symmetric(vertical: 8),
            child: Text(
              'devices.no_transfers'.tr(),
              style: TextStyle(fontSize: 13, color: cs.mutedForeground),
            ),
          );
        }
        return Container(
          width: double.infinity,
          padding: const EdgeInsets.symmetric(horizontal: 14, vertical: 12),
          decoration: BoxDecoration(
            color: cs.muted.withValues(alpha: 0.55),
            borderRadius: BorderRadius.circular(14),
          ),
          child: Column(
            children: [
              _statLine(
                cs,
                icon: AppIcons.arrowUp,
                label: 'devices.stat_sent'.tr(),
                value:
                    '${'devices.files_count'.plural(s.sentCount)} · '
                    '${formatBytes(s.sentBytes)}',
              ),
              const SizedBox(height: 8),
              _statLine(
                cs,
                icon: AppIcons.arrowDown,
                label: 'devices.stat_received'.tr(),
                value:
                    '${'devices.files_count'.plural(s.receivedCount)} · '
                    '${formatBytes(s.receivedBytes)}',
              ),
              if (s.lastTransfer != null) ...[
                const SizedBox(height: 8),
                _statLine(
                  cs,
                  icon: AppIcons.clock,
                  label: 'devices.last_transfer'.tr(),
                  value:
                      '${s.lastTransfer!.fileName} · '
                      '${relativeLastSeen(s.lastTransfer!.timestamp)}',
                ),
              ],
            ],
          ),
        );
      },
    );
  }

  Widget _statLine(
    ShadColorScheme cs, {
    required String icon,
    required String label,
    required String value,
  }) => Row(
    children: [
      AppSvgIcon(icon, size: 14, color: cs.mutedForeground),
      const SizedBox(width: 8),
      Text(
        label,
        style: TextStyle(
          fontSize: 12.5,
          fontWeight: FontWeight.w600,
          color: cs.mutedForeground,
        ),
      ),
      const SizedBox(width: 12),
      Expanded(
        child: Text(
          value,
          textAlign: TextAlign.right,
          maxLines: 1,
          overflow: TextOverflow.ellipsis,
          style: TextStyle(
            fontSize: 12.5,
            fontWeight: FontWeight.w600,
            color: cs.foreground,
          ),
        ),
      ),
    ],
  );
}
