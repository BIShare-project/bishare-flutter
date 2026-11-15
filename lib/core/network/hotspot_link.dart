import 'dart:io';

import 'package:device_info_plus/device_info_plus.dart';
import 'package:flutter/foundation.dart';
import 'package:flutter/services.dart';
import 'package:permission_handler/permission_handler.dart';

/// A hotspot another device can join: its network name and password.
class HotspotInfo {
  const HotspotInfo({required this.ssid, required this.pass});

  final String ssid;
  final String pass;
}

/// Why a hotspot could not be started by the app.
enum HotspotFailure { permission, failed }

class HotspotException implements Exception {
  const HotspotException(this.failure);
  final HotspotFailure failure;
}

/// "Hotspot" and "Wi-Fi" on the Send tab: two phones with no network in
/// common. One starts a hotspot and shows a QR code with its name, password
/// and addresses; the other scans it, joins, and reaches the first directly.
///
/// What the systems allow:
///  - Android 13+ starts a local-only hotspot itself ([start]).
///  - Android 10+ joins the hotspot of a scanned code with one system
///    question ([join]).
///  - iOS, and older Android, turn the hotspot on or join in system
///    settings; the app shows what to do.
class HotspotLink {
  HotspotLink._();

  static const _channel = MethodChannel('app.bishare/hotspot');

  /// The hotspot this device started through the app, or null.
  static final hosting = ValueNotifier<HotspotInfo?>(null);

  /// The hotspot this device joined through the app (its name), or null.
  static final joined = ValueNotifier<String?>(null);

  static bool _wired = false;
  static int? _sdk;

  /// Phones and tablets only: a computer is on a network already.
  static bool get offered => !kIsWeb && (Platform.isAndroid || Platform.isIOS);

  static void _wire() {
    if (_wired) return;
    _wired = true;
    _channel.setMethodCallHandler((call) async {
      switch (call.method) {
        case 'stopped':
          hosting.value = null;
        case 'left':
          joined.value = null;
      }
    });
  }

  static Future<int> _androidSdk() async =>
      _sdk ??= (await DeviceInfoPlugin().androidInfo).version.sdkInt;

  /// Whether the app can start the hotspot itself. Before Android 13 that
  /// needs the location permission, which BIShare does not ask for.
  static Future<bool> canStart() async =>
      !kIsWeb && Platform.isAndroid && await _androidSdk() >= 33;

  /// Whether the app can join a hotspot itself.
  static Future<bool> canJoin() async =>
      !kIsWeb && Platform.isAndroid && await _androidSdk() >= 29;

  /// Starts this phone's local-only hotspot (or returns the running one).
  static Future<HotspotInfo> start() async {
    _wire();
    if (!(await Permission.nearbyWifiDevices.request()).isGranted) {
      throw const HotspotException(HotspotFailure.permission);
    }
    try {
      final map = await _channel.invokeMapMethod<String, String>('start');
      final ssid = map?['ssid'] ?? '';
      if (ssid.isEmpty) throw const HotspotException(HotspotFailure.failed);
      return hosting.value = HotspotInfo(ssid: ssid, pass: map?['pass'] ?? '');
    } on PlatformException catch (e) {
      throw HotspotException(
        e.code == 'permission'
            ? HotspotFailure.permission
            : HotspotFailure.failed,
      );
    } on MissingPluginException {
      throw const HotspotException(HotspotFailure.failed);
    }
  }

  static Future<void> stop() async {
    hosting.value = null;
    try {
      await _channel.invokeMethod<void>('stop');
    } on Object {
      // Nothing was running.
    }
  }

  /// Joins [ssid]; the system asks the person once. False when they decline
  /// or the hotspot is not found within a minute.
  static Future<bool> join(String ssid, String pass) async {
    _wire();
    try {
      final ok =
          await _channel.invokeMethod<bool>('join', {
            'ssid': ssid,
            'pass': pass,
          }) ??
          false;
      joined.value = ok ? ssid : null;
      return ok;
    } on Object {
      joined.value = null;
      return false;
    }
  }

  static Future<void> leave() async {
    joined.value = null;
    try {
      await _channel.invokeMethod<void>('leave');
    } on Object {
      // Not joined.
    }
  }
}
