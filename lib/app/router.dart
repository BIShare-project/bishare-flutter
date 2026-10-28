import 'package:flutter/material.dart';
import 'package:go_router/go_router.dart';
import 'package:shared_preferences/shared_preferences.dart';

import '../core/config/feature_flags.dart';
import '../core/desktop/desktop_service.dart';
import '../core/di/locator.dart';
import '../core/platform/tv.dart';
import '../core/storage/app_database.dart';
import '../core/ui/app_ui.dart';
import '../features/clipboard/presentation/clipboard_history_page.dart';
import '../features/devices/presentation/devices_page.dart';
import '../features/file_manager/presentation/file_manager_page.dart';
import '../features/inbox/presentation/image_gallery_page.dart';
import '../features/nearby/presentation/nearby_page.dart';
import '../features/onboarding/presentation/onboarding_page.dart';
import '../features/qr_beam/presentation/qr_beam_page.dart';
import '../features/qr_beam/presentation/qr_beam_receive_page.dart';
import '../features/qr_beam/presentation/qr_beam_send_page.dart';
import '../features/remote/presentation/remote_share_page.dart';
import '../features/scanner/presentation/scanner_page.dart';
import '../features/tv/presentation/tv_shell.dart';
import '../features/vault/presentation/vault_account_page.dart';
import '../features/vault/presentation/drive/drive_plans_page.dart';
import '../features/vault/presentation/drive/drive_storage_page.dart';
import '../features/vault/presentation/drive/drive_transfers_page.dart';
import 'main_shell.dart';

/// Arguments for the image gallery route (passed via `extra`).
typedef GalleryArgs = ({List<TransferRecord> images, int startIndex});

/// A page pushed over the shell: beside the side rail on a computer, with no
/// slide (the rail stays put); the platform's own transition on a phone.
Page<void> _pushed(BuildContext context, GoRouterState state, Widget child) {
  final page = ShellPushedPage(child: child);
  return context.isWideLayout
      ? NoTransitionPage<void>(key: state.pageKey, child: page)
      : MaterialPage<void>(key: state.pageKey, child: page);
}

/// Drive pages open only while the Drive is shown (audit P15).
String? _driveGate(BuildContext context, GoRouterState state) =>
    getIt<FeatureFlags>().vaultVisible ? null : '/';

/// Central app routing. Full-screen pages register here instead of ad-hoc
/// `Navigator.push(MaterialPageRoute(...))`, so navigation stays controlled and
/// tidy. The tab shell ([MainShell]) is the root; pushed pages are its children.
final GoRouter appRouter = GoRouter(
  // Gate first-run: show onboarding until the user finishes it.
  redirect: (context, state) {
    try {
      final atOnboarding = state.matchedLocation == '/onboarding';
      // TV is a remote-driven receiver — skip the touch-oriented onboarding
      // entirely and land straight on the TV shell.
      if (isTvDevice) return atOnboarding ? '/' : null;
      final done = getIt<SharedPreferences>().getBool(kOnboardingDone) ?? false;
      if (!done && !atOnboarding) return '/onboarding';
      if (done && atOnboarding) return '/';
      return null;
    } catch (e) {
      // If there's an error during redirect, don't crash
      debugPrint('Router redirect error: $e');
      return null;
    }
  },
  errorBuilder: (context, state) {
    // If no route matches, just show the main shell - deep links are handled
    // separately by DeepLinkService, not by GoRouter navigation
    debugPrint('No route found for: ${state.uri} - staying on main shell');
    return isTvDevice ? const TvShell() : const MainShell();
  },
  routes: [
    GoRoute(
      path: '/onboarding',
      builder: (context, state) => const OnboardingPage(),
    ),
    GoRoute(
      path: '/',
      builder: (context, state) =>
          isTvDevice ? const TvShell() : const MainShell(),
      routes: [
        GoRoute(
          path: 'files',
          pageBuilder: (context, state) =>
              _pushed(context, state, const FileManagerPage()),
        ),
        GoRoute(
          path: 'gallery',
          pageBuilder: (context, state) => _pushed(
            context,
            state,
            Builder(
              builder: (context) {
                final args = state.extra! as GalleryArgs;
                return ImageGalleryPage(
                  images: args.images,
                  startIndex: args.startIndex,
                );
              },
            ),
          ),
        ),
        GoRoute(
          path: 'scan',
          // Camera QR scanning is mobile-only — never build the scanner on
          // desktop, where the camera plugin has no implementation.
          redirect: (context, state) => supportsCameraScan ? null : '/',
          pageBuilder: (context, state) =>
              _pushed(context, state, const ScannerPage()),
        ),
        GoRoute(
          path: 'remote',
          pageBuilder: (context, state) => _pushed(
            context,
            state,
            RemoteSharePage(
              initialPath: state.extra is String
                  ? state.extra! as String
                  : null,
            ),
          ),
        ),
        GoRoute(
          path: 'nearby',
          pageBuilder: (context, state) =>
              _pushed(context, state, const NearbyPage()),
        ),
        GoRoute(
          path: 'qr-beam',
          pageBuilder: (context, state) =>
              _pushed(context, state, const QrBeamPage()),
          routes: [
            GoRoute(
              path: 'send',
              pageBuilder: (context, state) =>
                  _pushed(context, state, const QrBeamSendPage()),
            ),
            GoRoute(
              path: 'receive',
              // QR Beam receive needs a camera — mobile-only.
              redirect: (context, state) => supportsCameraScan ? null : '/',
              pageBuilder: (context, state) =>
                  _pushed(context, state, const QrBeamReceivePage()),
            ),
          ],
        ),
        GoRoute(
          path: 'devices',
          pageBuilder: (context, state) =>
              _pushed(context, state, const DevicesPage()),
        ),
        GoRoute(
          path: 'clipboard',
          pageBuilder: (context, state) =>
              _pushed(context, state, const ClipboardHistoryPage()),
        ),
        // BIShare Drive (drive-plan.md phase 3); reachable only from the Drive
        // group in Settings, which shows only while vault_enabled allows it.
        // A link to one of these pages leads home while it does not.
        GoRoute(
          path: 'drive-transfers',
          redirect: _driveGate,
          pageBuilder: (context, state) =>
              _pushed(context, state, const DriveTransfersPage()),
        ),
        GoRoute(
          path: 'drive-storage',
          redirect: _driveGate,
          pageBuilder: (context, state) =>
              _pushed(context, state, const DriveStoragePage()),
        ),
        GoRoute(
          path: 'drive-plans',
          redirect: _driveGate,
          pageBuilder: (context, state) =>
              _pushed(context, state, const DrivePlansPage()),
        ),
        GoRoute(
          path: 'drive-account',
          redirect: _driveGate,
          pageBuilder: (context, state) =>
              _pushed(context, state, const VaultAccountPage()),
          routes: [
            GoRoute(
              path: 'scan',
              pageBuilder: (context, state) =>
                  _pushed(context, state, const VaultPairScanPage()),
            ),
          ],
        ),
      ],
    ),
  ],
);
