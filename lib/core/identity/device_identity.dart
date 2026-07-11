import 'dart:convert';
import 'dart:io';
import 'dart:typed_data';

import 'package:device_info_plus/device_info_plus.dart';
import 'package:flutter_secure_storage/flutter_secure_storage.dart';
import 'package:shared_preferences/shared_preferences.dart';
import 'package:uuid/uuid.dart';

import '../../src/rust/api/crypto.dart' as rc;
import '../clipboard/clipboard_channel.dart';
import '../constants/protocol.dart';
import '../crypto/e2e_crypto.dart';
import '../network/local_ip.dart';
import '../protocol/device_info.dart';
import '../rust/rust_facade.dart';

/// This device's stable identity: a persistent fingerprint (UUID), a user-editable
/// alias, and a persistent X25519 key pair. Produces the [DeviceInfo] advertised in
/// discovery and returned by `/api/v1/info`.
class DeviceIdentity {
  DeviceIdentity._({
    required this.fingerprint,
    required String alias,
    required this.crypto,
    required this.rustEngine,
    required this.deviceModel,
    required this.deviceType,
    required SharedPreferences prefs,
  }) : _alias = alias,
       _prefs = prefs;

  static const _kFingerprint = 'deviceFingerprint';
  static const _kAlias = 'deviceAlias';
  static const _kPrivateSeed = 'e2ePrivateSeed'; // secure storage

  final String fingerprint;

  /// Pure-Dart engine — public key + fingerprint (interop-tested).
  final E2ECrypto crypto;

  /// Shared Rust engine (same seed) — used for the hot transfer path (ECDH key
  /// derivation + AES-GCM chunk encrypt/decrypt) via FFI.
  final rc.EncryptionEngine rustEngine;

  final String deviceModel;
  final String deviceType;

  /// Derive the AES-256 session key shared with a peer (32 bytes), or null if the
  /// peer key is malformed. Symmetric with the peer's own derivation.
  List<int>? deriveKey(String peerPublicKeyBase64) =>
      rustEngine.deriveSharedKey(peerPublicKeyBase64: peerPublicKeyBase64);

  final SharedPreferences _prefs;
  String _alias;

  String get alias => _alias;

  set alias(String value) {
    _alias = value;
    _prefs.setString(_kAlias, value);
  }

  String get publicKeyBase64 => crypto.publicKeyBase64;

  /// Loads (or lazily creates) the identity from persistent storage.
  static Future<DeviceIdentity> load({
    required SharedPreferences prefs,
    required FlutterSecureStorage secure,
  }) async {
    var fingerprint = prefs.getString(_kFingerprint);
    if (fingerprint == null || fingerprint.isEmpty) {
      fingerprint = const Uuid().v4();
      await prefs.setString(_kFingerprint, fingerprint);
    }

    final alias = prefs.getString(_kAlias) ?? await _defaultAlias();

    // Load or generate the X25519 private seed (32 bytes, base64). Keychain is
    // preferred, but on platforms/signing configs where it is unavailable (e.g.
    // an ad-hoc-signed macOS dev build → error -34018) we degrade to
    // SharedPreferences so startup never crashes.
    Uint8List? seed;
    String? stored;
    try {
      stored = await secure.read(key: _kPrivateSeed);
    } on Object {
      stored = prefs.getString(_kPrivateSeed);
    }
    stored ??= prefs.getString(_kPrivateSeed);
    if (stored != null) {
      try {
        final bytes = base64.decode(stored);
        if (bytes.length == 32) seed = Uint8List.fromList(bytes);
      } on FormatException {
        seed = null;
      }
    }
    final (engine, actualSeed) = await E2ECrypto.create(privateSeed: seed);
    if (seed == null) {
      final encoded = base64.encode(actualSeed);
      try {
        await secure.write(key: _kPrivateSeed, value: encoded);
      } on Object {
        await prefs.setString(_kPrivateSeed, encoded);
      }
    }

    // Same seed → the Rust engine produces the identical X25519 key pair, so ECDH
    // with peers stays consistent regardless of which engine derives.
    final rustEngine = Rust.engineFromSeed(actualSeed)!;

    return DeviceIdentity._(
      fingerprint: fingerprint,
      alias: alias,
      crypto: engine,
      rustEngine: rustEngine,
      deviceModel: _deviceModel(),
      deviceType: _deviceType(),
      prefs: prefs,
    );
  }

  /// Builds the `DeviceInfo` payload. The IP is recomputed every call because it
  /// can change on a network switch without the alias changing.
  Future<DeviceInfo> makeDeviceInfo() async {
    final ip = await LocalIp.resolve();
    return DeviceInfo(
      alias: _alias,
      version: BIShareConfig.version,
      deviceModel: deviceModel,
      deviceType: deviceType,
      fingerprint: fingerprint,
      port: BISharePort.main,
      download: false,
      publicKey: publicKeyBase64,
      supportsBinary: true,
      supportsCompression: true,
      supportsKeepAlive: true,
      // v2.4 capability flags are advertised only once the feature actually
      // ships (PeerCapabilities gates every use on the sender side). Binary
      // clipboard requires a native image-clipboard handler, which only exists
      // on macOS/iOS/Android — advertise it ONLY there (null → the field stays
      // off the wire on Windows/Linux, so peers never announce images to us).
      supportsClipboardBinary: ClipboardImageChannel.isSupported ? true : null,
      ip: ip,
    );
  }

  /// A friendly default device name from `device_info_plus` (macOS computer
  /// name, iOS device name, Android manufacturer+model, …). Falls back to the
  /// hostname, but never "localhost".
  static Future<String> _defaultAlias() async {
    try {
      final info = DeviceInfoPlugin();
      final String candidate;
      if (Platform.isIOS) {
        candidate = (await info.iosInfo).name;
      } else if (Platform.isMacOS) {
        candidate = (await info.macOsInfo).computerName;
      } else if (Platform.isAndroid) {
        final a = await info.androidInfo;
        candidate = '${a.manufacturer} ${a.model}'.trim();
      } else if (Platform.isWindows) {
        candidate = (await info.windowsInfo).computerName;
      } else if (Platform.isLinux) {
        final l = await info.linuxInfo;
        candidate = l.prettyName.isNotEmpty ? l.prettyName : l.name;
      } else {
        candidate = '';
      }
      final cleaned = _cleanAlias(candidate);
      if (cleaned != null) return cleaned;
    } on Object {
      // fall through to hostname
    }
    return _cleanAlias(Platform.localHostname.split('.').first) ??
        'BIShare Device';
  }

  static String? _cleanAlias(String raw) {
    final t = raw.trim();
    if (t.isEmpty || t.toLowerCase() == 'localhost') return null;
    return t;
  }

  static String _deviceModel() {
    if (Platform.isIOS) return 'iphone';
    if (Platform.isAndroid) return 'android';
    if (Platform.isMacOS) return 'mac';
    if (Platform.isWindows) return 'windows';
    if (Platform.isLinux) return 'linux';
    return 'unknown';
  }

  static String _deviceType() {
    if (Platform.isIOS || Platform.isAndroid) return 'mobile';
    return 'desktop';
  }
}
