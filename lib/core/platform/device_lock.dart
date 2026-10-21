import 'dart:io' show Platform;

import 'package:flutter/foundation.dart';
import 'package:flutter/services.dart';
import 'package:local_auth_platform_interface/local_auth_platform_interface.dart';

enum DeviceLockResult {
  /// The person unlocked: Face ID, Touch ID, fingerprint, PIN, Windows Hello.
  ok,

  /// The person closed the prompt.
  cancelled,

  /// This device has no screen lock, so there is nothing to ask for.
  noLock,

  /// No way to ask on this platform (Linux).
  unavailable,

  /// The device has a lock, but asking failed (locked out after too many
  /// tries, another prompt open): show nothing, try again later.
  failed,
}

/// Ask the person to unlock with the device's own lock before something
/// sensitive is shown (the Drive recovery phrase, drive-plan.md task 3.7).
///
/// iOS, macOS and Windows use the local_auth implementations directly.
/// Android does not: local_auth's Android part needs the activity to be a
/// FlutterFragmentActivity with an AppCompat theme, an app-wide change, so
/// MainActivity asks KeyguardManager for the lock screen confirmation instead.
class DeviceLock {
  const DeviceLock._();

  static const MethodChannel _channel = MethodChannel('app.bishare/device');

  static Future<DeviceLockResult> confirm({
    required String title,
    required String reason,
  }) async {
    if (kIsWeb) return DeviceLockResult.unavailable;
    if (Platform.isAndroid) {
      try {
        final r = await _channel.invokeMethod<String>('confirmDeviceLock', {
          'title': title,
          'reason': reason,
        });
        return switch (r) {
          'ok' => DeviceLockResult.ok,
          'none' => DeviceLockResult.noLock,
          'cancelled' => DeviceLockResult.cancelled,
          _ => DeviceLockResult.unavailable,
        };
      } on Object catch (e) {
        debugPrint('[DeviceLock] Android confirm failed: $e');
        return DeviceLockResult.failed;
      }
    }
    if (Platform.isIOS || Platform.isMacOS || Platform.isWindows) {
      try {
        final ok = await LocalAuthPlatform.instance.authenticate(
          localizedReason: reason,
          authMessages: const [],
        );
        return ok ? DeviceLockResult.ok : DeviceLockResult.cancelled;
      } on LocalAuthException catch (e) {
        return switch (e.code) {
          LocalAuthExceptionCode.noCredentialsSet => DeviceLockResult.noLock,
          LocalAuthExceptionCode.userCanceled ||
          LocalAuthExceptionCode.systemCanceled ||
          LocalAuthExceptionCode.timeout => DeviceLockResult.cancelled,
          LocalAuthExceptionCode.noBiometricHardware ||
          LocalAuthExceptionCode.noBiometricsEnrolled =>
            DeviceLockResult.unavailable,
          _ => DeviceLockResult.failed,
        };
      } on Object catch (e) {
        debugPrint('[DeviceLock] confirm failed: $e');
        return DeviceLockResult.failed;
      }
    }
    return DeviceLockResult.unavailable;
  }
}
