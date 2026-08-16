import 'dart:io' show Platform;
import 'dart:ui' show Size;

import 'package:easy_localization/easy_localization.dart';
import 'package:flutter/foundation.dart';
import 'package:launch_at_startup/launch_at_startup.dart';
import 'package:package_info_plus/package_info_plus.dart';
import 'package:tray_manager/tray_manager.dart';
import 'package:window_manager/window_manager.dart';

import '../server/transfer_server.dart';

/// True on the three desktop platforms (never on web/mobile).
bool get isDesktop =>
    !kIsWeb && (Platform.isMacOS || Platform.isWindows || Platform.isLinux);

/// Whether camera-based QR scanning is available. `mobile_scanner` ships an
/// implementation on Android, iOS, and macOS — but NOT on Windows or Linux.
/// Gate every camera-scan entry point on this so the Windows/Linux builds never
/// construct a `MobileScannerController` (which throws `MissingPluginException`).
/// QR Beam stays send-only on Windows/Linux as a result.
bool get supportsCameraScan =>
    !kIsWeb && !(Platform.isWindows || Platform.isLinux);

/// Desktop-only polish (macOS · Windows · Linux): a native window with a minimum
/// size that hides to the tray on close (so receiving keeps running in the
/// background), a menu-bar/tray icon with a receiving toggle, and launch-at-login.
class DesktopService with WindowListener, TrayListener {
  DesktopService(this._server);

  final TransferServer _server;
  bool _receiving = true;

  static const _iconPng = 'assets/icon/bishare_icon.png';

  /// Configure the window frame. Call from `main()` BEFORE `runApp`.
  static Future<void> initWindow() async {
    if (!isDesktop) return;
    await windowManager.ensureInitialized();
    // Landscape (≥760 wide → the desktop side-rail layout), locked to a fixed
    // size (min == max + non-resizable).
    const size = Size(1000, 680);
    const opts = WindowOptions(
      size: size,
      minimumSize: size,
      maximumSize: size,
      center: true,
      title: 'BIShare',
      titleBarStyle: TitleBarStyle.normal,
    );
    await windowManager.waitUntilReadyToShow(opts, () async {
      await windowManager.show();
      await windowManager.focus();
    });
    await windowManager.setResizable(false); // lock the window size
    // Intercept the close button → hide to tray instead of quitting.
    await windowManager.setPreventClose(true);
  }

  /// Wire the tray + window/tray listeners + autostart. Call after DI is ready.
  Future<void> start() async {
    if (!isDesktop) return;
    windowManager.addListener(this);
    trayManager.addListener(this);
    try {
      await trayManager.setIcon(_iconPng);
      await trayManager.setToolTip('BIShare');
      await _refreshMenu();
    } on Object catch (e) {
      debugPrint('[desktop] tray init failed: $e');
    }
    try {
      final info = await PackageInfo.fromPlatform();
      launchAtStartup.setup(
        appName: info.appName,
        appPath: Platform.resolvedExecutable,
        packageName: info.packageName,
      );
    } on Object catch (e) {
      debugPrint('[desktop] autostart setup failed: $e');
    }
  }

  Future<void> _refreshMenu() => trayManager.setContextMenu(
    Menu(
      items: [
        MenuItem(key: 'show', label: 'tray.show'.tr()),
        MenuItem(
          key: 'toggle',
          label: (_receiving ? 'tray.pause' : 'tray.resume').tr(),
        ),
        MenuItem.separator(),
        MenuItem(key: 'quit', label: 'tray.quit'.tr()),
      ],
    ),
  );

  // --- Autostart (used by the settings toggle) ---

  Future<bool> isAutostartEnabled() async {
    if (!isDesktop) return false;
    try {
      return await launchAtStartup.isEnabled();
    } on Object {
      return false;
    }
  }

  Future<void> setAutostart(bool on) async {
    if (!isDesktop) return;
    try {
      if (on) {
        await launchAtStartup.enable();
      } else {
        await launchAtStartup.disable();
      }
    } on Object catch (e) {
      debugPrint('[desktop] autostart toggle failed: $e');
    }
  }

  Future<void> _showWindow() async {
    await windowManager.show();
    await windowManager.focus();
  }

  // --- WindowListener ---

  @override
  void onWindowClose() async {
    if (await windowManager.isPreventClose()) await windowManager.hide();
  }

  // --- TrayListener ---

  @override
  void onTrayIconMouseDown() => _showWindow();

  @override
  void onTrayIconRightMouseDown() => trayManager.popUpContextMenu();

  @override
  void onTrayMenuItemClick(MenuItem menuItem) async {
    switch (menuItem.key) {
      case 'show':
        await _showWindow();
      case 'toggle':
        _receiving = !_receiving;
        if (_receiving) {
          await _server.start();
        } else {
          await _server.stop();
        }
        await _refreshMenu();
      case 'quit':
        await windowManager.setPreventClose(false);
        await windowManager.destroy();
    }
  }
}
