import 'package:easy_localization/easy_localization.dart';
import 'package:flutter/material.dart';

import '../../../../core/desktop/desktop_service.dart';
import '../../../../core/di/locator.dart';
import '../../../../core/ui/app_ui.dart';
import 'switch_row.dart';

/// Desktop-only "Launch at login" toggle. Reads/sets the OS autostart state via
/// [DesktopService]; self-manages its value since it isn't part of [Settings].
class AutostartRow extends StatefulWidget {
  const AutostartRow({super.key});

  @override
  State<AutostartRow> createState() => _AutostartRowState();
}

class _AutostartRowState extends State<AutostartRow> {
  bool _on = false;

  @override
  void initState() {
    super.initState();
    _load();
  }

  Future<void> _load() async {
    final on = await getIt<DesktopService>().isAutostartEnabled();
    if (mounted) setState(() => _on = on);
  }

  Future<void> _set(bool v) async {
    await getIt<DesktopService>().setAutostart(v);
    final now = await getIt<DesktopService>().isAutostartEnabled();
    if (mounted) setState(() => _on = now);
  }

  @override
  Widget build(BuildContext context) => SwitchRow(
    icon: AppIcons.refreshSync,
    title: 'settings.launch_at_login'.tr(),
    subtitle: 'settings.launch_at_login_subtitle'.tr(),
    value: _on,
    onChanged: _set,
  );
}
