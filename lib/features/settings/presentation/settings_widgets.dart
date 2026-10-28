import 'package:easy_localization/easy_localization.dart' hide TextDirection;
import 'package:flutter/material.dart';
import 'package:package_info_plus/package_info_plus.dart';
import 'package:share_plus/share_plus.dart';
import 'package:url_launcher/url_launcher.dart';

import '../../../core/config/feature_flags.dart';
import '../../../core/constants/app_links.dart';
import '../../../core/desktop/desktop_service.dart';
import '../../../core/di/locator.dart';
import '../../../core/identity/device_identity.dart';
import '../../../core/ui/app_ui.dart';
import '../domain/settings.dart' as s;

/// This device at the top of Settings, flat: the avatar, the name and "tap
/// to rename".
class ProfileCard extends StatelessWidget {
  const ProfileCard({super.key, required this.alias, required this.onTap});
  final String alias;
  final VoidCallback onTap;

  @override
  Widget build(BuildContext context) {
    final t = context.tokens;
    final identity = getIt<DeviceIdentity>();
    return AppListTile(
      onTap: onTap,
      padding: const EdgeInsets.fromLTRB(16, 8, 16, 12),
      leading: AppAvatar(
        icon: iconForDevice(identity.deviceType),
        size: 52,
        online: true,
      ),
      title: Text(
        alias,
        maxLines: 1,
        overflow: TextOverflow.ellipsis,
        style: AppType.title.copyWith(fontSize: 19, color: t.text),
      ),
      subtitle: Text('settings.this_device_rename'.tr()),
      trailing: AppSvgIcon(AppIcons.renameEdit, size: 18, color: t.text3),
    );
  }
}

/// A settings row for an accent: the colour and its name; a tap opens the
/// sheet with the 12 swatches.
class AccentRow extends StatelessWidget {
  const AccentRow({
    super.key,
    required this.icon,
    required this.label,
    required this.selected,
    required this.onChanged,
  });

  final String icon;
  final String label;
  final String selected;
  final ValueChanged<String> onChanged;

  @override
  Widget build(BuildContext context) {
    final t = context.tokens;
    final brightness = Theme.of(context).brightness;
    return AppListTile(
      leading: AppGlyph(icon),
      title: Text(label),
      onTap: () => _pick(context),
      trailing: Row(
        mainAxisSize: MainAxisSize.min,
        children: [
          Swatch(
            color: s.AccentColors.of(selected, brightness),
            selected: false,
            size: 16,
          ),
          const SizedBox(width: 8),
          Text(
            accentName(selected),
            style: AppType.secondary.copyWith(fontSize: 14, color: t.text2),
          ),
          const SizedBox(width: 4),
          AppSvgIcon(
            Directionality.of(context) == TextDirection.rtl
                ? AppIcons.chevronLeft
                : AppIcons.chevronRight,
            size: 18,
            color: t.text3,
          ),
        ],
      ),
    );
  }

  Future<void> _pick(BuildContext context) async {
    final picked = await showAppSheet<String>(
      context,
      icon: icon,
      title: label,
      builder: (ctx) => AccentGrid(
        selected: selected,
        onTap: (name) => Navigator.pop(ctx, name),
      ),
    );
    if (picked != null && picked != selected) onChanged(picked);
  }
}

/// The accent's name in this language.
String accentName(String name) => 'accent.$name'.tr();

/// The 12 accents, six to a row, each named under its swatch.
class AccentGrid extends StatelessWidget {
  const AccentGrid({super.key, required this.selected, required this.onTap});

  final String selected;
  final ValueChanged<String> onTap;

  @override
  Widget build(BuildContext context) {
    final t = context.tokens;
    final brightness = Theme.of(context).brightness;
    return Padding(
      padding: const EdgeInsets.only(top: 4, bottom: 8),
      child: GridView.count(
        crossAxisCount: 6,
        shrinkWrap: true,
        physics: const NeverScrollableScrollPhysics(),
        mainAxisSpacing: 10,
        childAspectRatio: 0.78,
        children: [
          for (final name in s.AccentColors.names)
            Semantics(
              button: true,
              selected: name == selected,
              label: accentName(name),
              excludeSemantics: true,
              child: GestureDetector(
                behavior: HitTestBehavior.opaque,
                onTap: () {
                  tapHaptic();
                  onTap(name);
                },
                child: Column(
                  children: [
                    Swatch(
                      color: s.AccentColors.of(name, brightness),
                      selected: name == selected,
                    ),
                    const SizedBox(height: 6),
                    Text(
                      accentName(name),
                      maxLines: 1,
                      overflow: TextOverflow.ellipsis,
                      style: AppType.secondary.copyWith(
                        fontSize: 12,
                        color: name == selected ? t.text : t.text2,
                        fontWeight: name == selected
                            ? FontWeight.w600
                            : FontWeight.w400,
                      ),
                    ),
                  ],
                ),
              ),
            ),
        ],
      ),
    );
  }
}

/// One accent colour: a filled circle, ringed with a check when chosen.
class Swatch extends StatelessWidget {
  const Swatch({
    super.key,
    required this.color,
    required this.selected,
    this.size = 40,
    this.onTap,
  });

  final Color color;
  final bool selected;
  final double size;
  final VoidCallback? onTap;

  @override
  Widget build(BuildContext context) {
    final t = context.tokens;
    final dot = Container(
      width: size,
      height: size,
      padding: EdgeInsets.all(selected ? 3 : 0),
      decoration: BoxDecoration(
        shape: BoxShape.circle,
        border: selected ? Border.all(color: color, width: 2) : null,
      ),
      child: Container(
        alignment: Alignment.center,
        decoration: BoxDecoration(color: color, shape: BoxShape.circle),
        child: selected && size >= 28
            ? AppSvgIcon(AppIcons.check, size: size * 0.4, color: t.bg)
            : null,
      ),
    );
    if (onTap == null) return dot;
    return GestureDetector(
      behavior: HitTestBehavior.opaque,
      onTap: () {
        tapHaptic();
        onTap!();
      },
      child: dot,
    );
  }
}

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
  Widget build(BuildContext context) => AppSwitchRow(
    icon: AppIcons.refreshSync,
    title: 'settings.launch_at_login'.tr(),
    subtitle: 'settings.launch_at_login_subtitle'.tr(),
    value: _on,
    onChanged: _set,
  );
}

/// Settings → About: legal, help, and community links (privacy policy, terms of
/// service, support, rating, sharing). Mirrors the native iOS "About" menu so
/// the Flutter client keeps parity — every row opens the OS browser, mail app,
/// or share sheet.
class AboutSection extends StatelessWidget {
  const AboutSection({super.key});

  @override
  Widget build(BuildContext context) {
    final t = context.tokens;
    return Column(
      crossAxisAlignment: CrossAxisAlignment.start,
      children: [
        AppSectionHeader('settings.about'.tr()),
        AppGroup(
          child: Column(
            children: [
              _row(
                t,
                icon: AppIcons.permissionShield,
                label: 'settings.privacy_policy'.tr(),
                onTap: () => _open(AppLinks.privacy),
              ),
              const AppRowDivider(indent: 58),
              _row(
                t,
                icon: AppIcons.fileDocument,
                label: 'settings.terms_of_service'.tr(),
                onTap: () => _open(AppLinks.terms),
              ),
              const AppRowDivider(indent: 58),
              _row(
                t,
                icon: AppIcons.comment,
                label: 'settings.help_support'.tr(),
                onTap: () => _open(AppLinks.help),
              ),
              const AppRowDivider(indent: 58),
              _row(
                t,
                icon: AppIcons.mailSend,
                label: 'settings.contact_support'.tr(),
                onTap: () => launchUrl(AppLinks.supportMailto),
              ),
              const AppRowDivider(indent: 58),
              _row(
                t,
                icon: AppIcons.starFavorite,
                label: 'settings.rate_app'.tr(),
                onTap: () => _open(AppLinks.rateUrl),
              ),
              const AppRowDivider(indent: 58),
              _row(
                t,
                icon: AppIcons.shareLink,
                label: 'settings.share_app'.tr(),
                external: false,
                onTap: () => SharePlus.instance.share(
                  ShareParams(
                    text: 'settings.share_app_message'.tr(
                      namedArgs: {'url': AppLinks.shareUrl},
                    ),
                  ),
                ),
              ),
            ],
          ),
        ),
      ],
    );
  }

  Widget _row(
    AppTokens t, {
    required String icon,
    required String label,
    required VoidCallback onTap,
    bool external = true,
  }) {
    return AppListTile(
      leading: AppGlyph(icon),
      title: Text(label),
      trailing: AppSvgIcon(
        external ? AppIcons.externalLink : AppIcons.chevronRight,
        size: 18,
        color: t.text3,
      ),
      onTap: onTap,
    );
  }

  static Future<void> _open(String url) =>
      launchUrl(Uri.parse(url), mode: LaunchMode.externalApplication);
}

/// App name, version and licence. Seven taps switch BIShare Drive testing on or off for
/// this device, and only while the server flag is "internal" (drive-plan.md
/// task 3.1); otherwise the taps do nothing.
class VersionFooter extends StatefulWidget {
  const VersionFooter({super.key});

  @override
  State<VersionFooter> createState() => _VersionFooterState();
}

class _VersionFooterState extends State<VersionFooter> {
  /// The app's own version and build (pubspec), e.g. "2.8.0 (280)".
  String _version = '';

  @override
  void initState() {
    super.initState();
    PackageInfo.fromPlatform().then((info) {
      if (!mounted) return;
      setState(() => _version = '${info.version} (${info.buildNumber})');
    }, onError: (Object _) {});
  }

  int _taps = 0;
  DateTime _first = DateTime.fromMillisecondsSinceEpoch(0);

  Future<void> _tap() async {
    final now = DateTime.now();
    if (now.difference(_first) > const Duration(seconds: 3)) {
      _first = now;
      _taps = 0;
    }
    if (++_taps < 7) return;
    _taps = 0;
    final flags = getIt<FeatureFlags>();
    if (!flags.vaultInternal) return;
    final on = !flags.vaultTester;
    await flags.setVaultTester(on);
    if (!mounted) return;
    ScaffoldMessenger.maybeOf(context)?.showSnackBar(
      SnackBar(
        content: Text((on ? 'vault.tester_on' : 'vault.tester_off').tr()),
      ),
    );
  }

  @override
  Widget build(BuildContext context) {
    final t = context.tokens;
    return GestureDetector(
      behavior: HitTestBehavior.opaque,
      onTap: _tap,
      child: Padding(
        padding: const EdgeInsets.fromLTRB(20, 28, 20, 16),
        child: Center(
          child: Column(
            children: [
              Text(
                'BIShare',
                style: AppType.secondary.copyWith(
                  fontSize: 13,
                  fontWeight: FontWeight.w700,
                  color: t.text2,
                ),
              ),
              const SizedBox(height: 2),
              // Empty for the moment it takes to read the version.
              Text(
                _version.isEmpty
                    ? ''
                    : 'settings.version'.tr(namedArgs: {'version': _version}),
                style: AppType.secondary.copyWith(fontSize: 12, color: t.text3),
              ),
              const SizedBox(height: 2),
              Text(
                'settings.license_line'.tr(),
                style: AppType.secondary.copyWith(fontSize: 12, color: t.text3),
              ),
            ],
          ),
        ),
      ),
    );
  }
}
