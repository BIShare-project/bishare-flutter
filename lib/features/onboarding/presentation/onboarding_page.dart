import 'dart:io' show Platform;

import 'package:app_tracking_transparency/app_tracking_transparency.dart';
import 'package:easy_localization/easy_localization.dart';
import 'package:flutter/material.dart';
import 'package:go_router/go_router.dart';
import 'package:permission_handler/permission_handler.dart';
import 'package:shadcn_ui/shadcn_ui.dart';
import 'package:shared_preferences/shared_preferences.dart';

import '../../../core/di/locator.dart';
import '../../../core/notifications/notification_service.dart';
import '../../../core/ui/app_ui.dart';
import '../../discovery/data/discovery_service.dart';
import 'widgets/onboarding_slide.dart';
import 'widgets/permission_row.dart';

/// Preferences key gating first-run onboarding (see the router redirect).
const kOnboardingDone = 'onboardingDone';

typedef _Slide = ({String icon, String title, String body, Color color});

/// First-run walkthrough: 5 feature slides + a permission-priming page. Mirrors
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
      color: const Color(0xFF2563EB),
    ),
    (
      icon: AppIcons.wifi,
      title: 'onboarding.slide2_title'.tr(),
      body: 'onboarding.slide2_body'.tr(),
      color: const Color(0xFF16A34A),
    ),
    (
      icon: AppIcons.transferP2p,
      title: 'onboarding.slide3_title'.tr(),
      body: 'onboarding.slide3_body'.tr(),
      color: const Color(0xFFEA580C),
    ),
    (
      icon: AppIcons.permissionShield,
      title: 'onboarding.slide4_title'.tr(),
      body: 'onboarding.slide4_body'.tr(),
      color: const Color(0xFF7C3AED),
    ),
    (
      icon: AppIcons.globePublic,
      title: 'onboarding.slide5_title'.tr(),
      body: 'onboarding.slide5_body'.tr(),
      color: const Color(0xFF0891B2),
    ),
  ];

  int get _permIndex => _slides.length;
  int get _total => _slides.length + 1;
  bool get _onPermission => _page == _permIndex;
  bool get _isMobile => Platform.isIOS || Platform.isAndroid;

  Color get _accent => _onPermission ? const Color(0xFF4F46E5) : _slides[_page].color;

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

  Future<void> _askPhotos() async {
    final ok = await Permission.photos.request();
    if (mounted) setState(() => _photos = ok.isGranted || ok.isLimited);
  }

  Future<void> _askCamera() async {
    final ok = await Permission.camera.request();
    if (mounted) setState(() => _camera = ok.isGranted);
  }

  @override
  Widget build(BuildContext context) {
    final cs = ShadTheme.of(context).colorScheme;
    return Scaffold(
      backgroundColor: cs.background,
      body: Stack(
        children: [
          // Ambient glow that shifts to the active page's color.
          AnimatedContainer(
            duration: const Duration(milliseconds: 400),
            height: 380,
            decoration: BoxDecoration(
              gradient: RadialGradient(
                center: Alignment.topCenter,
                radius: 0.85,
                colors: [_accent.withValues(alpha: 0.14), _accent.withValues(alpha: 0)],
              ),
            ),
          ),
          SafeArea(
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
                          OnboardingSlide(
                            icon: s.icon,
                            title: s.title,
                            description: s.body,
                            color: s.color,
                          ),
                        _permissionPage(),
                      ],
                    ),
                  ),
                  _dots(cs),
                  const SizedBox(height: 24),
                  _cta(),
                  SizedBox(
                    height: 48,
                    child: _onPermission
                        ? null
                        : Center(
                            child: GestureDetector(
                              onTap: _skip,
                              child: Text(
                                'onboarding.skip'.tr(),
                                style: TextStyle(
                                  fontSize: 14,
                                  fontWeight: FontWeight.w600,
                                  color: cs.mutedForeground,
                                ),
                              ),
                            ),
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

  Widget _dots(ShadColorScheme cs) {
    return Row(
      mainAxisAlignment: MainAxisAlignment.center,
      children: [
        for (var i = 0; i < _total; i++)
          AnimatedContainer(
            duration: const Duration(milliseconds: 300),
            margin: const EdgeInsets.symmetric(horizontal: 4),
            width: i == _page ? 22 : 7,
            height: 7,
            decoration: BoxDecoration(
              color: i == _page ? _accent : cs.mutedForeground.withValues(alpha: 0.3),
              borderRadius: BorderRadius.circular(4),
            ),
          ),
      ],
    );
  }

  Widget _cta() {
    return Padding(
      padding: const EdgeInsets.symmetric(horizontal: 28),
      child: SizedBox(
        width: double.infinity,
        height: 54,
        child: Material(
          color: Colors.transparent,
          child: InkWell(
            borderRadius: BorderRadius.circular(16),
            onTap: _next,
            child: Ink(
              decoration: BoxDecoration(
                borderRadius: BorderRadius.circular(16),
                gradient: LinearGradient(
                  begin: Alignment.topLeft,
                  end: Alignment.bottomRight,
                  colors: [
                    Color.lerp(_accent, Colors.white, 0.12)!,
                    _accent,
                  ],
                ),
                boxShadow: [
                  BoxShadow(
                    color: _accent.withValues(alpha: 0.4),
                    blurRadius: 16,
                    offset: const Offset(0, 8),
                  ),
                ],
              ),
              child: Center(
                child: Text(
                  _onPermission
                      ? 'onboarding.get_started'.tr()
                      : 'onboarding.next'.tr(),
                  style: const TextStyle(
                    color: Colors.white,
                    fontSize: 16,
                    fontWeight: FontWeight.w700,
                    letterSpacing: 0.3,
                  ),
                ),
              ),
            ),
          ),
        ),
      ),
    );
  }

  Widget _permissionPage() {
    final cs = ShadTheme.of(context).colorScheme;
    return SingleChildScrollView(
      padding: const EdgeInsets.symmetric(horizontal: 28),
      child: Column(
        children: [
          const SizedBox(height: 12),
          Container(
            width: 96,
            height: 96,
            decoration: BoxDecoration(
              shape: BoxShape.circle,
              gradient: LinearGradient(
                begin: Alignment.topLeft,
                end: Alignment.bottomRight,
                colors: [
                  Color.lerp(_accent, Colors.white, 0.16)!,
                  _accent,
                ],
              ),
              boxShadow: [
                BoxShadow(color: _accent.withValues(alpha: 0.35), blurRadius: 24),
              ],
            ),
            child: const AppSvgIcon(AppIcons.hand, size: 42, color: Colors.white),
          ),
          const SizedBox(height: 22),
          Text(
            'onboarding.perm_title'.tr(),
            textAlign: TextAlign.center,
            style: TextStyle(
              fontSize: 24,
              fontWeight: FontWeight.w800,
              color: cs.foreground,
            ),
          ),
          const SizedBox(height: 8),
          Text(
            'onboarding.perm_subtitle'.tr(),
            textAlign: TextAlign.center,
            style: TextStyle(fontSize: 13.5, height: 1.4, color: cs.mutedForeground),
          ),
          const SizedBox(height: 22),
          PermissionRow(
            icon: AppIcons.wifi,
            title: 'onboarding.perm_local_network'.tr(),
            subtitle: 'onboarding.perm_local_network_sub'.tr(),
            granted: _network,
            onAllow: _askNetwork,
          ),
          const SizedBox(height: 10),
          PermissionRow(
            icon: AppIcons.notification,
            title: 'onboarding.perm_notifications'.tr(),
            subtitle: 'onboarding.perm_notifications_sub'.tr(),
            granted: _notifications,
            onAllow: _askNotifications,
          ),
          if (_isMobile) ...[
            const SizedBox(height: 10),
            PermissionRow(
              icon: AppIcons.image,
              title: 'onboarding.perm_photos'.tr(),
              subtitle: 'onboarding.perm_photos_sub'.tr(),
              granted: _photos,
              onAllow: _askPhotos,
            ),
            const SizedBox(height: 10),
            PermissionRow(
              icon: AppIcons.qrShare,
              title: 'onboarding.perm_camera'.tr(),
              subtitle: 'onboarding.perm_camera_sub'.tr(),
              granted: _camera,
              onAllow: _askCamera,
            ),
          ],
          const SizedBox(height: 8),
        ],
      ),
    );
  }
}
