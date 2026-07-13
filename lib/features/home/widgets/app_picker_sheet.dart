import 'package:easy_localization/easy_localization.dart';
import 'package:flutter/material.dart';
import 'package:shadcn_ui/shadcn_ui.dart';

import '../../../core/apps/installed_apps_channel.dart';
import '../../../core/ui/app_ui.dart';
import '../../send/presentation/tray_cubit.dart';

/// "App Share" picker (Android): search + multi-select the installed launcher
/// apps, then stage their base APKs in the send tray.
Future<void> showAppPicker(BuildContext context, TrayCubit tray) async {
  final picked = await showAppSheet<List<InstalledApp>>(
    context,
    icon: AppIcons.gridView,
    title: 'home.apps'.tr(),
    subtitle: 'home.apps_subtitle'.tr(),
    builder: (ctx) => _AppPickerBody(sheetContext: ctx),
  );
  if (picked == null || picked.isEmpty) return;
  await tray.stageApks(picked);
}

class _AppPickerBody extends StatefulWidget {
  const _AppPickerBody({required this.sheetContext});

  /// The sheet route's context — popping [_AppPickerBody]'s own context after
  /// a rebuild would pop the wrong route.
  final BuildContext sheetContext;

  @override
  State<_AppPickerBody> createState() => _AppPickerBodyState();
}

class _AppPickerBodyState extends State<_AppPickerBody> {
  List<InstalledApp>? _apps;
  final _selected = <String>{}; // package names
  String _query = '';

  @override
  void initState() {
    super.initState();
    InstalledAppsChannel.list().then((apps) {
      if (mounted) setState(() => _apps = apps);
    });
  }

  List<InstalledApp> get _filtered {
    final apps = _apps ?? const [];
    final q = _query.trim().toLowerCase();
    if (q.isEmpty) return apps;
    return apps.where((a) => a.name.toLowerCase().contains(q)).toList();
  }

  @override
  Widget build(BuildContext context) {
    final cs = ShadTheme.of(context).colorScheme;
    final apps = _apps;
    final filtered = _filtered;
    return Column(
      mainAxisSize: MainAxisSize.min,
      children: [
        ShadInput(
          placeholder: Text('home.apps_search'.tr()),
          onChanged: (v) => setState(() => _query = v),
        ),
        const SizedBox(height: 10),
        SizedBox(
          height: 360,
          child: apps == null
              ? const Center(child: CircularProgressIndicator())
              : filtered.isEmpty
                  ? Center(
                      child: Text(
                        'home.apps_empty'.tr(),
                        style: TextStyle(
                          fontSize: 14,
                          color: cs.mutedForeground,
                        ),
                      ),
                    )
                  : ListView.builder(
                      itemCount: filtered.length,
                      itemBuilder: (_, i) => _row(filtered[i]),
                    ),
        ),
        const SizedBox(height: 12),
        AppButton(
          label: 'home.apps_add'.tr(
            namedArgs: {'count': '${_selected.length}'},
          ),
          variant: AppButtonVariant.primary,
          size: AppButtonSize.medium,
          fullWidth: true,
          onPressed: _selected.isEmpty
              ? null
              : () => Navigator.pop(
                    widget.sheetContext,
                    _apps!
                        .where((a) => _selected.contains(a.packageName))
                        .toList(),
                  ),
        ),
      ],
    );
  }

  Widget _row(InstalledApp app) {
    final cs = ShadTheme.of(context).colorScheme;
    final selected = _selected.contains(app.packageName);
    final meta = [
      if (app.version.isNotEmpty) app.version,
      formatBytes(app.sizeBytes),
    ].join(' · ');
    return Material(
      type: MaterialType.transparency,
      child: InkWell(
        onTap: () {
          tapHaptic();
          setState(() {
            selected
                ? _selected.remove(app.packageName)
                : _selected.add(app.packageName);
          });
        },
        borderRadius: BorderRadius.circular(12),
        child: Padding(
          padding: const EdgeInsets.symmetric(horizontal: 6, vertical: 8),
          child: Row(
            children: [
              ClipRRect(
                borderRadius: BorderRadius.circular(9),
                child: app.icon != null
                    ? Image.memory(
                        app.icon!,
                        width: 38,
                        height: 38,
                        gaplessPlayback: true,
                      )
                    : Container(
                        width: 38,
                        height: 38,
                        color: cs.muted,
                        child: AppSvgIcon(
                          AppIcons.gridView,
                          size: 18,
                          color: cs.mutedForeground,
                        ),
                      ),
              ),
              const SizedBox(width: 12),
              Expanded(
                child: Column(
                  crossAxisAlignment: CrossAxisAlignment.start,
                  children: [
                    Text(
                      app.name,
                      maxLines: 1,
                      overflow: TextOverflow.ellipsis,
                      style: TextStyle(
                        fontSize: 14.5,
                        fontWeight: FontWeight.w600,
                        color: cs.foreground,
                      ),
                    ),
                    const SizedBox(height: 2),
                    Row(
                      children: [
                        Flexible(
                          child: Text(
                            meta,
                            maxLines: 1,
                            overflow: TextOverflow.ellipsis,
                            style: TextStyle(
                              fontSize: 12,
                              color: cs.mutedForeground,
                            ),
                          ),
                        ),
                        if (app.isSplit) ...[
                          const SizedBox(width: 6),
                          _splitBadge(),
                        ],
                      ],
                    ),
                  ],
                ),
              ),
              const SizedBox(width: 8),
              Container(
                width: 22,
                height: 22,
                decoration: BoxDecoration(
                  shape: BoxShape.circle,
                  color: selected ? cs.primary : Colors.transparent,
                  border: Border.all(
                    color: selected ? cs.primary : cs.border,
                    width: 1.4,
                  ),
                ),
                child: selected
                    ? Center(
                        child: AppSvgIcon(
                          AppIcons.check,
                          size: 13,
                          color: cs.primaryForeground,
                        ),
                      )
                    : null,
              ),
            ],
          ),
        ),
      ),
    );
  }

  /// Split-APK (App Bundle) installs may not run from just the base APK on the
  /// receiving device — flag them so the sender isn't surprised.
  Widget _splitBadge() {
    const amber = Color(0xFFFF9F0A);
    return Container(
      padding: const EdgeInsets.symmetric(horizontal: 5, vertical: 1.5),
      decoration: BoxDecoration(
        color: amber.withValues(alpha: 0.16),
        borderRadius: BorderRadius.circular(5),
      ),
      child: Text(
        'home.apps_split'.tr(),
        style: const TextStyle(
          fontSize: 10.5,
          fontWeight: FontWeight.w600,
          color: amber,
        ),
      ),
    );
  }
}
