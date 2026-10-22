import 'dart:io' show Platform;
import 'dart:ui' show Size;

import 'package:easy_localization/easy_localization.dart';
import 'package:flutter/foundation.dart';
import 'package:package_info_plus/package_info_plus.dart';
import 'package:tray_manager/tray_manager.dart'
    show
        ContextMenuTrigger,
        ImageAsset,
        Menu,
        MenuItem,
        MenuItemClickedEvent,
        MenuItemType,
        TrayIcon,
        TrayIconClickedEvent;
import 'package:window_manager/window_manager.dart';

import '../server/transfer_server.dart';
import 'autostart.dart';

/// True on the three desktop platforms (never on web/mobile). Reads
/// [defaultTargetPlatform], which is the host OS in every build; only a test
/// can override it (the store screenshots render the phone UI on a Mac).
bool get isDesktop =>
    !kIsWeb &&
    (defaultTargetPlatform == TargetPlatform.macOS ||
        defaultTargetPlatform == TargetPlatform.windows ||
        defaultTargetPlatform == TargetPlatform.linux);

/// Whether camera-based QR scanning is available. `flutter_zxing` reads the
/// camera on Android and iOS only; on macOS, Windows and Linux it can decode
/// image files but has no camera. Gate every camera-scan entry point on this.
/// QR Beam stays send-only on desktop as a result.
bool get supportsCameraScan =>
    !kIsWeb &&
    (defaultTargetPlatform == TargetPlatform.android ||
        defaultTargetPlatform == TargetPlatform.iOS);

/// Desktop-only polish (macOS · Windows · Linux): a native window with a minimum
/// size that hides to the tray on close (so receiving keeps running in the
/// background), a menu-bar/tray icon with a receiving toggle, and launch-at-login.
class DesktopService with WindowListener {
  DesktopService(this._server);

  final TransferServer _server;
  bool _receiving = true;
  Autostart? _autostart;

  // Held for the app's lifetime: a collected TrayIcon removes the icon.
  TrayIcon? _tray;
  MenuItem? _toggleItem;

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
    try {
      _initTray();
    } on Object catch (e) {
      debugPrint('[desktop] tray init failed: $e');
    }
    try {
      final info = await PackageInfo.fromPlatform();
      _autostart = Autostart(
        appName: info.appName,
        appPath: Platform.resolvedExecutable,
        packageName: info.packageName,
      );
    } on Object catch (e) {
      debugPrint('[desktop] autostart setup failed: $e');
    }
  }

  /// Menu-bar/tray icon: a left click shows the window, a right click opens
  /// Show · Pause/Resume receiving · Quit. (Linux panels report no clicks and
  /// open the menu themselves.)
  void _initTray() {
    final tray = TrayIcon.create();
    final menu = Menu.create();
    if (tray == null || menu == null) throw StateError('no tray support');

    MenuItem item(String label, Future<void> Function() onClick) {
      final it = MenuItem.createWithLabelAndType(label, MenuItemType.normal)!;
      it.addListener((e) async {
        if (e is MenuItemClickedEvent) await onClick();
      });
      menu.addItem(it);
      return it;
    }

    item('tray.show'.tr(), _showWindow);
    _toggleItem = item(_toggleLabel, _toggleReceiving);
    menu.addSeparator();
    item('tray.quit'.tr(), _quit);

    tray
      ..icon = ImageAsset.fromAsset(_iconPng)
      ..setTooltip('BIShare')
      ..setContextMenu(menu)
      ..setContextMenuTrigger(ContextMenuTrigger.rightClicked)
      ..addListener((e) async {
        if (e is TrayIconClickedEvent) await _showWindow();
      })
      ..setVisible(true);
    _tray = tray;
  }

  String get _toggleLabel => (_receiving ? 'tray.pause' : 'tray.resume').tr();

  Future<void> _toggleReceiving() async {
    _receiving = !_receiving;
    if (_receiving) {
      await _server.start();
    } else {
      await _server.stop();
    }
    _toggleItem?.label = _toggleLabel; // updates the open menu in place
  }

  Future<void> _quit() async {
    _tray?.dispose();
    await windowManager.setPreventClose(false);
    await windowManager.destroy();
  }

  // --- Autostart (used by the settings toggle) ---

  Future<bool> isAutostartEnabled() async {
    if (!isDesktop) return false;
    try {
      return await _autostart?.isEnabled() ?? false;
    } on Object {
      return false;
    }
  }

  Future<void> setAutostart(bool on) async {
    if (!isDesktop) return;
    try {
      if (on) {
        await _autostart?.enable();
      } else {
        await _autostart?.disable();
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
}
