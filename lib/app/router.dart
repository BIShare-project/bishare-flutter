import 'package:flutter/foundation.dart';
import 'package:go_router/go_router.dart';
import 'package:shared_preferences/shared_preferences.dart';

import '../core/desktop/desktop_service.dart';
import '../core/di/locator.dart';
import '../core/platform/tv.dart';
import '../core/storage/app_database.dart';
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
import 'main_shell.dart';

/// Arguments for the image gallery route (passed via `extra`).
typedef GalleryArgs = ({List<TransferRecord> images, int startIndex});

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
          builder: (context, state) => const FileManagerPage(),
        ),
        GoRoute(
          path: 'gallery',
          builder: (context, state) {
            final args = state.extra! as GalleryArgs;
            return ImageGalleryPage(
              images: args.images,
              startIndex: args.startIndex,
            );
          },
        ),
        GoRoute(
          path: 'scan',
          // Camera QR scanning isn't available on Windows/Linux — never build
          // the scanner there (constructing it throws MissingPluginException).
          redirect: (context, state) => supportsCameraScan ? null : '/',
          builder: (context, state) => const ScannerPage(),
        ),
        GoRoute(
          path: 'remote',
          builder: (context, state) => const RemoteSharePage(),
        ),
        GoRoute(
          path: 'nearby',
          builder: (context, state) => const NearbyPage(),
        ),
        GoRoute(
          path: 'qr-beam',
          builder: (context, state) => const QrBeamPage(),
          routes: [
            GoRoute(
              path: 'send',
              builder: (context, state) => const QrBeamSendPage(),
            ),
            GoRoute(
              path: 'receive',
              // QR Beam receive needs a camera — unavailable on Windows/Linux.
              redirect: (context, state) => supportsCameraScan ? null : '/',
              builder: (context, state) => const QrBeamReceivePage(),
            ),
          ],
        ),
        GoRoute(
          path: 'devices',
          builder: (context, state) => const DevicesPage(),
        ),
        GoRoute(
          path: 'clipboard',
          builder: (context, state) => const ClipboardHistoryPage(),
        ),
      ],
    ),
  ],
);
