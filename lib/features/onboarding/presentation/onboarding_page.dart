import 'dart:io' show Platform;

import 'package:app_tracking_transparency/app_tracking_transparency.dart';
import 'package:easy_localization/easy_localization.dart';
import 'package:flutter/material.dart';
import 'package:go_router/go_router.dart';
import 'package:permission_handler/permission_handler.dart';
import 'package:shared_preferences/shared_preferences.dart';

import '../../../core/di/locator.dart';
import '../../../core/notifications/notification_service.dart';
import '../../../core/storage/all_files_access.dart';
import '../../../core/ui/app_ui.dart';
import '../../discovery/data/discovery_service.dart';

/// Preferences key gating first-run onboarding (see the router redirect).
const kOnboardingDone = 'onboardingDone';

typedef _Slide = ({String icon, String title, String body});

/// First-run walkthrough: feature slides (5 on Apple, 4 elsewhere) + a permission-priming page. Mirrors
/// the native `OnboardingView`. Reached via the router redirect while
/// [kOnboardingDone] is false; "Get Started" sets the flag and enters the app.
class OnboardingPage extends StatefulWidget {
  const OnboardingPage({super.key});

  @override
  State<OnboardingPage> createState() => _OnboardingPageState();
}

class _OnboardingPageState extends State<OnboardingPage> {
  final _controller = PageController();
  int _page = 0;

  // Permission grant states.
  bool _network = false;
  bool _notifications = false;
  bool _photos = false;
  bool _camera = false;

  List<_Slide> get _slides => [
    (
      icon: AppIcons.send,
      title: 'onboarding.slide1_title'.tr(),
      body: 'onboarding.slide1_body'.tr(),
    ),
    (
      icon: AppIcons.wifi,
      title: 'onboarding.slide2_title'.tr(),
      body: 'onboarding.slide2_body'.tr(),
    ),
    // Nearby Mode (MultipeerConnectivity) exists only on Apple devices.
    if (_isApple)
      (
        icon: AppIcons.transferP2p,
        title: 'onboarding.slide3_title'.tr(),
        body: 'onboarding.slide3_body'.tr(),
      ),
    (
      icon: AppIcons.permissionShield,
      title: 'onboarding.slide4_title'.tr(),
      body: 'onboarding.slide4_body'.tr(),
    ),
    (
      icon: AppIcons.globePublic,
      title: 'onboarding.slide5_title'.tr(),
      body: 'onboarding.slide5_body'.tr(),
    ),
  ];

  int get _permIndex => _slides.length;
  int get _total => _slides.length + 1;
  bool get _onPermission => _page == _permIndex;
  bool get _isMobile => Platform.isIOS || Platform.isAndroid;

  /// Only iOS and macOS have a Local Network permission to prime; elsewhere the
  /// row would request nothing.
  bool get _isApple => Platform.isIOS || Platform.isMacOS;

  @override
  void initState() {
    super.initState();
    _loadGranted();
  }

  /// Start each permission row from its real status, so a permission granted
  /// earlier (or by a reinstall) is not offered again.
  Future<void> _loadGranted() async {
    final notifications = await getIt<NotificationService>().isPermitted();
    var photos = false;
    var camera = false;
    if (_isMobile) {
      try {
        if (AllFilesAccess.applies) {
          photos = await AllFilesAccess.granted();
        } else {
          final p = await Permission.photos.status;
          photos = p.isGranted || p.isLimited;
        }
        camera = (await Permission.camera.status).isGranted;
      } on Object {
        // best-effort: rows stay "Continue"
      }
    }
    if (!mounted) return;
    setState(() {
      _notifications = _notifications || notifications;
      _photos = _photos || photos;
      _camera = _camera || camera;
    });
  }

  @override
  void dispose() {
    _controller.dispose();
    super.dispose();
  }

  void _next() {
    if (_onPermission) {
      _finish();
    } else {
      _controller.nextPage(
        duration: const Duration(milliseconds: 380),
        curve: Curves.easeOutCubic,
      );
    }
  }

  void _skip() => _controller.animateToPage(
    _permIndex,
    duration: const Duration(milliseconds: 420),
    curve: Curves.easeOutCubic,
  );

  Future<void> _finish() async {
    await _askTracking();
    await getIt<SharedPreferences>().setBool(kOnboardingDone, true);
    if (mounted) context.go('/');
  }

  /// iOS App Tracking Transparency. Prompted once at the end of onboarding, when
  /// the app is guaranteed active. No-op on other platforms / once determined.
  Future<void> _askTracking() async {
    if (!Platform.isIOS) return;
    final status = await AppTrackingTransparency.trackingAuthorizationStatus;
    if (status == TrackingStatus.notDetermined) {
      await AppTrackingTransparency.requestTrackingAuthorization();
    }
  }

  // --- permission requests ---

  void _askNetwork() {
    // iOS/macOS have no explicit "request" API — starting discovery triggers the
    // Local Network system prompt. Mark it primed so the row reflects the tap.
    getIt<DiscoveryService>().restart();
    setState(() => _network = true);
  }

  Future<void> _askNotifications() async {
    final ok = await getIt<NotificationService>().requestPermission();
    if (mounted) setState(() => _notifications = ok);
  }

  /// Android: the one All files access permission the Send tab uses
  /// (AllFilesAccess). iOS: the photo library.
  Future<void> _askPhotos() async {
    if (AllFilesAccess.applies) {
      final ok = await AllFilesAccess.request();
      if (mounted) setState(() => _photos = ok);
      return;
    }
    final ok = await Permission.photos.request();
    if (mounted) setState(() => _photos = ok.isGranted || ok.isLimited);
  }

  Future<void> _askCamera() async {
    final ok = await Permission.camera.request();
    if (mounted) setState(() => _camera = ok.isGranted);
  }

  @override
  Widget build(BuildContext context) {
    final t = context.tokens;
    return Scaffold(
      backgroundColor: t.bg,
      body: SafeArea(
        child: AppResponsivePane(
          maxWidth: 560,
          child: Column(
            children: [
              Expanded(
                child: PageView(
                  controller: _controller,
                  onPageChanged: (i) => setState(() => _page = i),
                  children: [
                    for (final s in _slides)
                      _SlideView(icon: s.icon, title: s.title, body: s.body),
                    _permissionPage(),
                  ],
                ),
              ),
              _dots(t),
              const SizedBox(height: 24),
              Padding(
                padding: const EdgeInsets.symmetric(horizontal: 28),
                child: AppButton(
                  label: _onPermission
                      ? 'onboarding.get_started'.tr()
                      : 'onboarding.next'.tr(),
                  variant: AppButtonVariant.brand,
                  size: AppButtonSize.large,
                  fullWidth: true,
                  onPressed: _next,
                ),
              ),
              SizedBox(
                height: 52,
                child: _onPermission
                    ? null
                    : Center(
                        child: AppButton(
                          label: 'onboarding.skip'.tr(),
                          variant: AppButtonVariant.ghost,
                          size: AppButtonSize.small,
                          onPressed: _skip,
                        ),
                      ),
              ),
            ],
          ),
        ),
      ),
    );
  }

  Widget _dots(AppTokens t) {
    return Row(
      mainAxisAlignment: MainAxisAlignment.center,
      children: [
        for (var i = 0; i < _total; i++)
          AnimatedContainer(
            duration: AppMotion.select,
            margin: const EdgeInsets.symmetric(horizontal: 4),
            width: i == _page ? 22 : 7,
            height: 7,
            decoration: BoxDecoration(
              color: i == _page ? t.accent : t.line,
              borderRadius: BorderRadius.circular(4),
            ),
          ),
      ],
    );
  }

  Widget _permissionPage() {
    final t = context.tokens;
    final rows = <Widget>[
      if (_isApple)
        _PermissionRow(
          icon: AppIcons.wifi,
          title: 'onboarding.perm_local_network'.tr(),
          subtitle: 'onboarding.perm_local_network_sub'.tr(),
          granted: _network,
          onAllow: _askNetwork,
        ),
      _PermissionRow(
        icon: AppIcons.notification,
        title: 'onboarding.perm_notifications'.tr(),
        subtitle: 'onboarding.perm_notifications_sub'.tr(),
        granted: _notifications,
        onAllow: _askNotifications,
      ),
      if (_isMobile) ...[
        _PermissionRow(
          icon: AppIcons.image,
          title: AllFilesAccess.applies
              ? 'onboarding.perm_files'.tr()
              : 'onboarding.perm_photos'.tr(),
          subtitle: AllFilesAccess.applies
              ? 'onboarding.perm_files_sub'.tr()
              : 'onboarding.perm_photos_sub'.tr(),
          granted: _photos,
          onAllow: _askPhotos,
        ),
        _PermissionRow(
          icon: AppIcons.qrShare,
          title: 'onboarding.perm_camera'.tr(),
          subtitle: 'onboarding.perm_camera_sub'.tr(),
          granted: _camera,
          onAllow: _askCamera,
        ),
      ],
    ];
    return SingleChildScrollView(
      padding: const EdgeInsets.symmetric(horizontal: 12),
      child: Column(
        children: [
          const SizedBox(height: 24),
          const _Emblem(icon: AppIcons.hand, size: 88),
          const SizedBox(height: 22),
          Padding(
            padding: const EdgeInsets.symmetric(horizontal: 16),
            child: Column(
              children: [
                Text(
                  'onboarding.perm_title'.tr(),
                  textAlign: TextAlign.center,
                  style: AppType.title.copyWith(color: t.text),
                ),
                const SizedBox(height: 8),
                Text(
                  'onboarding.perm_subtitle'.tr(),
                  textAlign: TextAlign.center,
                  style: AppType.body.copyWith(color: t.text2),
                ),
              ],
            ),
          ),
          const SizedBox(height: 18),
          for (var i = 0; i < rows.length; i++) ...[
            if (i > 0) const AppRowDivider(indent: 52),
            rows[i],
          ],
          const SizedBox(height: 8),
        ],
      ),
    );
  }
}

/// The app's glyph on a soft accent disc: the one picture on a slide.
class _Emblem extends StatelessWidget {
  const _Emblem({required this.icon, this.size = 112});

  final String icon;
  final double size;

  @override
  Widget build(BuildContext context) {
    final t = context.tokens;
    return Container(
      width: size,
      height: size,
      decoration: BoxDecoration(color: t.accentSoft, shape: BoxShape.circle),
      child: AppSvgIcon(icon, size: size * 0.44, color: t.accent),
    );
  }
}

/// One slide: the emblem, the title and one sentence.
class _SlideView extends StatelessWidget {
  const _SlideView({
    required this.icon,
    required this.title,
    required this.body,
  });

  final String icon;
  final String title;
  final String body;

  @override
  Widget build(BuildContext context) {
    final t = context.tokens;
    return Padding(
      padding: const EdgeInsets.symmetric(horizontal: 28),
      child: Column(
        mainAxisAlignment: MainAxisAlignment.center,
        children: [
          _Emblem(icon: icon),
          const SizedBox(height: 32),
          Text(
            title,
            textAlign: TextAlign.center,
            style: AppType.title.copyWith(fontSize: 26, color: t.text),
          ),
          const SizedBox(height: 12),
          ConstrainedBox(
            constraints: const BoxConstraints(maxWidth: 340),
            child: Text(
              body,
              textAlign: TextAlign.center,
              style: AppType.body.copyWith(height: 1.45, color: t.text2),
            ),
          ),
        ],
      ),
    );
  }
}

/// A permission row, flat: the glyph, the name and why, then "Continue"
/// until granted, a check after. The button deliberately does NOT say
/// "Allow": App Review (guideline 5.1.1(iv)) rejects pre-permission UI whose
/// button mirrors the system prompt's consent wording.
class _PermissionRow extends StatelessWidget {
  const _PermissionRow({
    required this.icon,
    required this.title,
    required this.subtitle,
    required this.granted,
    required this.onAllow,
  });

  final String icon;
  final String title;
  final String subtitle;
  final bool granted;
  final VoidCallback onAllow;

  @override
  Widget build(BuildContext context) {
    final t = context.tokens;
    return AppListTile(
      leading: AppGlyph(icon, color: granted ? t.ok : null),
      title: Text(title),
      subtitle: Text(subtitle),
      trailing: granted
          ? AppSvgIcon(AppIcons.verifiedCheck, size: 24, color: t.ok)
          : AppButton(
              label: 'onboarding.perm_continue'.tr(),
              variant: AppButtonVariant.secondary,
              size: AppButtonSize.small,
              onPressed: onAllow,
            ),
    );
  }
}
