import 'dart:io';

import 'package:flutter/services.dart';
import 'package:win32_registry/win32_registry.dart';

/// Launch-at-login for the three desktop platforms.
///
/// Replaces `launch_at_startup` 0.5.1, whose last release (2025) pins
/// `win32_registry` 2 and with it `win32` 5 — that alone held file_picker,
/// share_plus, package_info_plus, device_info_plus and flutter_secure_storage
/// on old majors. Same behaviour, same storage locations, so a choice made
/// with the old package is still read correctly:
///
/// * **Windows**: the `HKCU\…\Run` value plus its `StartupApproved` flag; under
///   MSIX (no registry writes that survive) a Startup-folder shortcut.
/// * **macOS**: the `launch_at_startup` method channel.
/// * **Linux**: `~/.config/autostart/<appName>.desktop`.
abstract class Autostart {
  factory Autostart({
    required String appName,
    required String appPath,
    required String packageName,
  }) {
    if (Platform.isWindows) {
      return _isMsix(packageName)
          ? _WindowsMsixAutostart(appName, appPath)
          : _WindowsAutostart(appName, appPath);
    }
    if (Platform.isMacOS) return _MacAutostart();
    if (Platform.isLinux) return _LinuxAutostart(appName, appPath);
    return _NoAutostart();
  }

  Future<bool> isEnabled();
  Future<void> enable();
  Future<void> disable();

  static bool _isMsix(String packageName) {
    final exe = Platform.resolvedExecutable;
    return exe.contains('WindowsApps') && exe.contains(packageName);
  }
}

class _WindowsAutostart implements Autostart {
  _WindowsAutostart(this._name, this._value);

  final String _name;
  final String _value;

  static const _runPath = r'Software\Microsoft\Windows\CurrentVersion\Run';
  static const _approvedPath =
      r'Software\Microsoft\Windows\CurrentVersion\Explorer\StartupApproved\Run';

  /// Explorer's "Startup apps" switch: first byte even = allowed, odd = off.
  static const _approvedLength = 12;

  T _withKey<T>(String path, T Function(RegistryKey key) body) {
    final key = CURRENT_USER.create(path);
    try {
      return body(key);
    } finally {
      key.close();
    }
  }

  @override
  Future<bool> isEnabled() async {
    final value = _withKey(_runPath, (k) => k.getString(_name));
    if (value != _value) return false;
    final approved = _withKey(_approvedPath, (k) => k.getBinary(_name));
    return approved == null || approved.isEmpty || approved[0].isEven;
  }

  @override
  Future<void> enable() async {
    _withKey(_runPath, (k) => k.setValue(_name, RegistryValue.string(_value)));
    final approved = Uint8List(_approvedLength)..[0] = 2;
    _withKey(
      _approvedPath,
      (k) => k.setValue(_name, RegistryValue.binary(approved)),
    );
  }

  @override
  Future<void> disable() async {
    for (final path in [_runPath, _approvedPath]) {
      _withKey(path, (k) {
        if (k.getValue(_name) != null) k.removeValue(_name);
      });
    }
  }
}

class _WindowsMsixAutostart implements Autostart {
  _WindowsMsixAutostart(this._name, this._exe);

  final String _name;
  final String _exe;

  File get _shortcut => File(
    '${Platform.environment['APPDATA']}\\Microsoft\\Windows\\Start Menu'
    '\\Programs\\Startup\\$_name.lnk',
  );

  @override
  Future<bool> isEnabled() async => _shortcut.existsSync();

  @override
  Future<void> enable() async {
    final script = '''
\$Shortcut = (New-Object -ComObject WScript.Shell).CreateShortcut("${_shortcut.path}")
\$Shortcut.TargetPath = "$_exe"
\$Shortcut.Save()
''';
    final result = await Process.run('powershell', ['-Command', script]);
    if ('${result.stderr}'.isNotEmpty) {
      throw ProcessException('powershell', const [], '${result.stderr}');
    }
  }

  @override
  Future<void> disable() async {
    if (_shortcut.existsSync()) await _shortcut.delete();
  }
}

class _MacAutostart implements Autostart {
  static const _channel = MethodChannel('launch_at_startup');

  @override
  Future<bool> isEnabled() async =>
      await _channel.invokeMethod<bool>('launchAtStartupIsEnabled') ?? false;

  @override
  Future<void> enable() => _set(true);

  @override
  Future<void> disable() => _set(false);

  Future<void> _set(bool on) async {
    if (await isEnabled() == on) return;
    await _channel.invokeMethod('launchAtStartupSetEnabled', {
      'setEnabledValue': on,
    });
  }
}

class _LinuxAutostart implements Autostart {
  _LinuxAutostart(this._name, this._exe);

  final String _name;
  final String _exe;

  File get _desktopFile =>
      File('${Platform.environment['HOME']}/.config/autostart/$_name.desktop');

  @override
  Future<bool> isEnabled() async => _desktopFile.existsSync();

  @override
  Future<void> enable() async {
    await _desktopFile.parent.create(recursive: true);
    await _desktopFile.writeAsString('''
[Desktop Entry]
Type=Application
Name=$_name
Comment=$_name startup script
Exec=$_exe
StartupNotify=false
Terminal=false
''');
  }

  @override
  Future<void> disable() async {
    if (_desktopFile.existsSync()) await _desktopFile.delete();
  }
}

class _NoAutostart implements Autostart {
  @override
  Future<bool> isEnabled() async => false;

  @override
  Future<void> enable() async {}

  @override
  Future<void> disable() async {}
}
