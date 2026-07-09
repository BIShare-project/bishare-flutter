import 'package:easy_localization/easy_localization.dart';
import 'package:flutter/material.dart';
import 'package:flutter_bloc/flutter_bloc.dart';
import 'package:shadcn_ui/shadcn_ui.dart';
import '../../../core/storage/app_database.dart';
import '../../../core/ui/app_ui.dart';
import '../../discovery/domain/discovered_device.dart';
import '../../favorites/presentation/favorites_cubit.dart';
import '../../send/domain/sendable_file.dart';
import '../../send/presentation/send_cubit.dart';
import '../../send/presentation/tray_cubit.dart';

class DeviceRow extends StatelessWidget {
  const DeviceRow({super.key, required this.device});
  final DiscoveredDevice device;

  @override
  Widget build(BuildContext context) {
    final cs = ShadTheme.of(context).colorScheme;
    return BlocBuilder<FavoritesCubit, Map<String, FavoriteDevice>>(
      builder: (context, favs) {
        final fav = favs[device.fingerprint];
        final favorites = context.read<FavoritesCubit>();
        final name = (fav?.customName?.isNotEmpty ?? false)
            ? fav!.customName!
            : device.alias;
        return AppListTile(
          onTap: () => _send(context),
          onLongPress: fav != null
              ? () => _options(context, favorites, name, fav)
              : null,
          leading: AppSvgIcon(iconForDevice(device.deviceType), size: 36),
          title: Row(
            children: [
              Flexible(
                child: Text(name, maxLines: 1, overflow: TextOverflow.ellipsis),
              ),
              if (fav != null) ...[
                const SizedBox(width: 6),
                const AppSvgIcon(AppIcons.starFavorite, size: 13, color: kAmber),
              ],
            ],
          ),
          subtitle: Text(
            (fav?.autoAccept ?? false)
                ? 'home.auto_accepts_version'.tr(
                    namedArgs: {'version': device.version},
                  )
                : 'home.tap_to_send_version'.tr(
                    namedArgs: {'version': device.version},
                  ),
          ),
          trailing: Row(
            mainAxisSize: MainAxisSize.min,
            children: [
              GestureDetector(
                onTap: () => _requestFiles(context),
                behavior: HitTestBehavior.opaque,
                child: Padding(
                  padding: const EdgeInsets.all(6),
                  child: AppSvgIcon(
                    AppIcons.hand,
                    size: 19,
                    color: Colors.orange.withValues(alpha: 0.75),
                  ),
                ),
              ),
              GestureDetector(
                onTap: () => favorites.toggle(device),
                behavior: HitTestBehavior.opaque,
                child: Padding(
                  padding: const EdgeInsets.all(6),
                  child: AppSvgIcon(
                    AppIcons.starFavorite,
                    size: 20,
                    color: fav != null
                        ? kAmber
                        : cs.mutedForeground.withValues(alpha: 0.5),
                  ),
                ),
              ),
              AppSvgIcon(
                AppIcons.chevronRight,
                size: 18,
                color: cs.mutedForeground.withValues(alpha: 0.6),
              ),
            ],
          ),
        );
      },
    );
  }

  Future<void> _send(BuildContext context) async {
    final tray = context.read<TrayCubit>();
    final files = tray.state;
    if (files.isEmpty) {
      toast(context, 'home.add_files_first'.tr());
      return;
    }
    // Empty the compose tray as the transfer starts — the files are now in
    // flight (SendCubit keeps its own copy for progress + retry).
    final batch = List<SendableFile>.of(files);
    tray.clear();
    await context.read<SendCubit>().sendFiles(batch, device);
  }

  /// Reverse flow: ask this device to send US files (native RequestFileButton).
  Future<void> _requestFiles(BuildContext context) async {
    final cubit = context.read<SendCubit>();
    final controller = TextEditingController();
    final send = await showAppSheet<bool>(
      context,
      icon: AppIcons.hand,
      title: 'home.request_files'.tr(),
      subtitle: 'home.ask_device_files'.tr(namedArgs: {'alias': device.alias}),
      builder: (ctx) {
        void submit() => Navigator.pop(ctx, true);
        return Column(
          mainAxisSize: MainAxisSize.min,
          children: [
            ShadInput(
              controller: controller,
              autofocus: true,
              placeholder: Text('home.message_optional'.tr()),
              onSubmitted: (_) => submit(),
            ),
            const SizedBox(height: 14),
            AppButton(
              label: 'home.send_request'.tr(),
              variant: AppButtonVariant.primary,
              size: AppButtonSize.medium,
              fullWidth: true,
              onPressed: submit,
            ),
          ],
        );
      },
    );
    if (send != true || !context.mounted) return;
    final msg = controller.text.trim();
    toast(
      context,
      'home.requesting_files'.tr(namedArgs: {'alias': device.alias}),
    );
    try {
      final accepted = await cubit.requestFiles(
        device,
        msg.isEmpty ? null : msg,
      );
      if (!context.mounted) return;
      toast(
        context,
        accepted
            ? 'home.device_sending_files'.tr(
                namedArgs: {'alias': device.alias},
              )
            : 'home.device_declined'.tr(namedArgs: {'alias': device.alias}),
        type: accepted ? ToastType.success : ToastType.error,
      );
    } on Object {
      if (context.mounted) {
        toast(context, 'home.request_failed'.tr(), type: ToastType.error);
      }
    }
  }

  Future<void> _options(
    BuildContext context,
    FavoritesCubit favorites,
    String name,
    FavoriteDevice fav,
  ) async {
    await showAppSheet<void>(
      context,
      title: name,
      subtitle: 'home.host_version'.tr(
        namedArgs: {'host': device.host, 'version': device.version},
      ),
      builder: (ctx) => Column(
        mainAxisSize: MainAxisSize.min,
        children: [
          AppSheetAction(
            icon: fav.autoAccept ? AppIcons.successSent : AppIcons.check,
            label: fav.autoAccept
                ? 'home.auto_accept_on'.tr()
                : 'home.turn_on_auto_accept'.tr(),
            onTap: () {
              favorites.setAutoAccept(device.fingerprint, !fav.autoAccept);
              Navigator.pop(ctx);
            },
          ),
          AppSheetAction(
            icon: AppIcons.renameEdit,
            label: 'home.rename'.tr(),
            onTap: () {
              Navigator.pop(ctx);
              _rename(context, favorites, name);
            },
          ),
          AppSheetAction(
            icon: AppIcons.trashDelete,
            label: 'home.remove_favorite'.tr(),
            destructive: true,
            onTap: () {
              favorites.toggle(device);
              Navigator.pop(ctx);
            },
          ),
        ],
      ),
    );
  }

  Future<void> _rename(
    BuildContext context,
    FavoritesCubit favorites,
    String current,
  ) async {
    final controller = TextEditingController(text: current);
    final name = await showAppSheet<String>(
      context,
      icon: AppIcons.renameEdit,
      title: 'home.rename_device'.tr(),
      builder: (ctx) {
        void submit() => Navigator.pop(ctx, controller.text);
        return Column(
          mainAxisSize: MainAxisSize.min,
          children: [
            ShadInput(
              controller: controller,
              autofocus: true,
              placeholder: Text('home.device_name'.tr()),
              onSubmitted: (_) => submit(),
            ),
            const SizedBox(height: 14),
            AppButton(
              label: 'home.save'.tr(),
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
      await favorites.setCustomName(device.fingerprint, name.trim());
    }
  }
}
