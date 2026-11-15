import 'dart:io';

import 'package:easy_localization/easy_localization.dart';
import 'package:flutter/material.dart';
import 'package:flutter/services.dart';
import 'package:go_router/go_router.dart';
import 'package:shared_preferences/shared_preferences.dart';

import '../../../core/deeplink/deep_link.dart';
import '../../../core/di/locator.dart';
import '../../../core/identity/device_identity.dart';
import '../../../core/network/hotspot_link.dart';
import '../../../core/network/local_ip.dart';
import '../../../core/ui/app_ui.dart';

/// The Send tab's "connect without a network": Hotspot on one phone, Wi-Fi on
/// the other (HotspotLink).
Future<void> showConnectSheet(BuildContext context) async {
  final choice = await showAppSheet<String>(
    context,
    icon: AppIcons.wifi,
    title: 'hotspot.title'.tr(),
    subtitle: 'hotspot.subtitle'.tr(),
    builder: (ctx) => Column(
      mainAxisSize: MainAxisSize.min,
      children: [
        AppSheetAction(
          icon: AppIcons.qrShare,
          label: 'hotspot.host'.tr(),
          subtitle: 'hotspot.host_subtitle'.tr(),
          onTap: () => Navigator.pop(ctx, 'host'),
        ),
        AppSheetAction(
          icon: AppIcons.scanDocument,
          label: 'hotspot.join'.tr(),
          subtitle: 'hotspot.join_subtitle'.tr(),
          onTap: () => Navigator.pop(ctx, 'join'),
        ),
        ValueListenableBuilder<String?>(
          valueListenable: HotspotLink.joined,
          builder: (_, ssid, _) => ssid == null
              ? const SizedBox.shrink()
              : AppSheetAction(
                  icon: AppIcons.close,
                  label: 'hotspot.leave'.tr(namedArgs: {'name': ssid}),
                  destructive: true,
                  onTap: () => Navigator.pop(ctx, 'leave'),
                ),
        ),
      ],
    ),
  );
  if (!context.mounted) return;
  switch (choice) {
    case 'host':
      await showAppSheet<void>(
        context,
        icon: AppIcons.qrShare,
        title: 'hotspot.host'.tr(),
        builder: (_) => const _Host(),
      );
    case 'join':
      await context.push('/scan');
    case 'leave':
      await HotspotLink.leave();
  }
}

/// The second phone, after scanning a hotspot code: join [ssid]. Where the
/// app cannot join by itself (iOS, Android before 10) the name and password
/// are shown to enter in system settings. False when the person gives up.
Future<bool> joinHotspot(
  BuildContext context, {
  required String ssid,
  required String pass,
}) async {
  if (await HotspotLink.canJoin()) return HotspotLink.join(ssid, pass);
  if (!context.mounted) return false;
  final done = await showAppSheet<bool>(
    context,
    icon: AppIcons.wifi,
    title: 'hotspot.join_manual_title'.tr(),
    subtitle: 'hotspot.join_manual_body'.tr(),
    builder: (ctx) => Column(
      mainAxisSize: MainAxisSize.min,
      crossAxisAlignment: CrossAxisAlignment.stretch,
      children: [
        _Credentials(ssid: ssid, pass: pass),
        const SizedBox(height: 14),
        AppButton(
          label: 'hotspot.join_manual_done'.tr(),
          fullWidth: true,
          onPressed: () => Navigator.pop(ctx, true),
        ),
      ],
    ),
  );
  return done ?? false;
}

const _kSsid = 'hotspotSsid';
const _kPass = 'hotspotPass';

class _Host extends StatefulWidget {
  const _Host();

  @override
  State<_Host> createState() => _HostState();
}

class _HostState extends State<_Host> {
  /// Whether the app starts the hotspot itself (Android 13+); null while
  /// that is being found out.
  bool? _auto;
  HotspotInfo? _info;
  List<String> _hosts = const [];
  HotspotFailure? _failure;

  final _ssid = TextEditingController();
  final _pass = TextEditingController();

  @override
  void initState() {
    super.initState();
    HotspotLink.hosting.addListener(_stoppedOutside);
    _begin();
  }

  @override
  void dispose() {
    HotspotLink.hosting.removeListener(_stoppedOutside);
    _ssid.dispose();
    _pass.dispose();
    super.dispose();
  }

  /// The system ended the hotspot (the person turned it off, or Wi-Fi was
  /// needed elsewhere): the code on screen no longer works.
  void _stoppedOutside() {
    if (_auto == true && HotspotLink.hosting.value == null && mounted) {
      Navigator.of(context).maybePop();
    }
  }

  Future<void> _begin() async {
    final auto = await HotspotLink.canStart();
    if (!mounted) return;
    setState(() => _auto = auto);
    return auto ? _start() : _own();
  }

  /// The person's own hotspot, turned on in system settings: the name and
  /// password they gave last time.
  Future<void> _own() async {
    final prefs = await SharedPreferences.getInstance();
    if (!mounted) return;
    setState(() => _auto = false);
    _ssid.text = prefs.getString(_kSsid) ?? '';
    _pass.text = prefs.getString(_kPass) ?? '';
  }

  Future<void> _start() async {
    setState(() => _failure = null);
    final before = (await LocalIp.all(max: 8)).toSet();
    try {
      final info = await HotspotLink.start();
      final hosts = await _addresses(before);
      if (mounted) {
        setState(() {
          _info = info;
          _hosts = hosts;
        });
      }
    } on HotspotException catch (e) {
      if (mounted) setState(() => _failure = e.failure);
    }
  }

  /// This phone's addresses with the hotspot's own first. The hotspot's
  /// interface takes a moment to get its address, so wait for a new one.
  Future<List<String>> _addresses(Set<String> before) async {
    for (var i = 0; i < 12; i++) {
      final now = await LocalIp.all(max: 8);
      final fresh = now.where((ip) => !before.contains(ip)).toList();
      if (fresh.isNotEmpty) {
        return [...fresh, ...now.where(before.contains)].take(4).toList();
      }
      await Future<void>.delayed(const Duration(milliseconds: 300));
    }
    return LocalIp.all(max: 4);
  }

  Future<void> _showManual() async {
    final ssid = _ssid.text.trim();
    if (ssid.isEmpty) return;
    final prefs = await SharedPreferences.getInstance();
    await prefs.setString(_kSsid, ssid);
    await prefs.setString(_kPass, _pass.text);
    final hosts = await LocalIp.all(max: 4);
    if (mounted) {
      setState(() {
        _info = HotspotInfo(ssid: ssid, pass: _pass.text);
        _hosts = hosts;
      });
    }
  }

  @override
  Widget build(BuildContext context) {
    final t = context.tokens;
    final info = _info;
    if (info != null) return _code(context, info);
    if (_auto == null) return const SizedBox(height: 120);
    if (_auto!) {
      final failure = _failure;
      if (failure == null) {
        return Padding(
          padding: const EdgeInsets.symmetric(vertical: 28),
          child: Column(
            mainAxisSize: MainAxisSize.min,
            children: [
              const SizedBox(
                width: 28,
                height: 28,
                child: CircularProgressIndicator(strokeWidth: 2.5),
              ),
              const SizedBox(height: 14),
              Text(
                'hotspot.starting'.tr(),
                style: AppType.secondary.copyWith(color: t.text2),
              ),
            ],
          ),
        );
      }
      return Column(
        mainAxisSize: MainAxisSize.min,
        crossAxisAlignment: CrossAxisAlignment.stretch,
        children: [
          Text(
            (failure == HotspotFailure.permission
                    ? 'hotspot.need_permission'
                    : 'hotspot.start_failed')
                .tr(),
            style: AppType.secondary.copyWith(color: t.text2),
          ),
          const SizedBox(height: 14),
          AppButton(
            label: 'hotspot.try_again'.tr(),
            fullWidth: true,
            onPressed: _start,
          ),
          const SizedBox(height: 8),
          AppButton(
            label: 'hotspot.use_own'.tr(),
            variant: AppButtonVariant.secondary,
            fullWidth: true,
            onPressed: _own,
          ),
        ],
      );
    }
    // The person turns the hotspot on in system settings and tells the app
    // its name and password once; they are kept for next time.
    return Column(
      mainAxisSize: MainAxisSize.min,
      crossAxisAlignment: CrossAxisAlignment.stretch,
      children: [
        Text(
          (Platform.isIOS ? 'hotspot.manual_ios' : 'hotspot.manual_android')
              .tr(),
          style: AppType.secondary.copyWith(color: t.text2),
        ),
        const SizedBox(height: 14),
        AppTextField(
          controller: _ssid,
          hint: 'hotspot.network_hint'.tr(),
          autocorrect: false,
          enableSuggestions: false,
        ),
        const SizedBox(height: 10),
        AppTextField(
          controller: _pass,
          hint: 'hotspot.password_hint'.tr(),
          autocorrect: false,
          enableSuggestions: false,
          onSubmitted: (_) => _showManual(),
        ),
        const SizedBox(height: 14),
        AppButton(
          label: 'hotspot.show_code'.tr(),
          fullWidth: true,
          onPressed: _showManual,
        ),
      ],
    );
  }

  Widget _code(BuildContext context, HotspotInfo info) {
    final t = context.tokens;
    final identity = getIt<DeviceIdentity>();
    return Column(
      mainAxisSize: MainAxisSize.min,
      crossAxisAlignment: CrossAxisAlignment.stretch,
      children: [
        Text(
          'hotspot.scan_hint'.tr(),
          textAlign: TextAlign.center,
          style: AppType.secondary.copyWith(color: t.text2),
        ),
        const SizedBox(height: 14),
        Center(
          child: BiShareQr(
            data: ConnectLink.uriFor(
              hosts: _hosts,
              fingerprint: identity.fingerprint,
              name: identity.alias,
              ssid: info.ssid,
              pass: info.pass,
            ),
          ),
        ),
        const SizedBox(height: 14),
        _Credentials(ssid: info.ssid, pass: info.pass),
        const SizedBox(height: 14),
        if (_auto == true)
          AppButton(
            label: 'hotspot.stop'.tr(),
            variant: AppButtonVariant.secondary,
            fullWidth: true,
            onPressed: () async {
              final navigator = Navigator.of(context);
              await HotspotLink.stop();
              navigator.maybePop();
            },
          )
        else
          AppButton(
            label: 'hotspot.change'.tr(),
            variant: AppButtonVariant.secondary,
            fullWidth: true,
            onPressed: () => setState(() => _info = null),
          ),
      ],
    );
  }
}

/// The network name and its password, each copied with a tap: for a device
/// that has to enter them by hand.
class _Credentials extends StatelessWidget {
  const _Credentials({required this.ssid, required this.pass});

  final String ssid;
  final String pass;

  @override
  Widget build(BuildContext context) => Column(
    mainAxisSize: MainAxisSize.min,
    children: [
      _row(context, 'hotspot.network'.tr(), ssid),
      if (pass.isNotEmpty) _row(context, 'hotspot.password'.tr(), pass),
    ],
  );

  Widget _row(BuildContext context, String label, String value) {
    final t = context.tokens;
    return Material(
      type: MaterialType.transparency,
      child: InkWell(
        borderRadius: BorderRadius.circular(12),
        onTap: () async {
          await Clipboard.setData(ClipboardData(text: value));
          if (context.mounted) toast(context, 'hotspot.copied'.tr());
        },
        child: Padding(
          padding: const EdgeInsets.symmetric(horizontal: 4, vertical: 10),
          child: Row(
            children: [
              Text(label, style: AppType.secondary.copyWith(color: t.text2)),
              const SizedBox(width: 12),
              Expanded(
                child: Text(
                  value,
                  textAlign: TextAlign.end,
                  style: AppType.secondary.copyWith(color: t.text),
                ),
              ),
              const SizedBox(width: 10),
              AppSvgIcon(AppIcons.copyDuplicate, size: 18, color: t.text3),
            ],
          ),
        ),
      ),
    );
  }
}
