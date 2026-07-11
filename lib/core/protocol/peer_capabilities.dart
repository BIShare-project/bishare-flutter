import '../constants/protocol.dart';
import 'device_info.dart';

/// The single place a v2.4 capability is decided (plan risk item 6): a feature
/// is usable with a peer only when it advertises the flag AND a new-enough
/// version. Never emit a 0x0C+ frame (or new wire field) to a peer whose
/// `can*` here is false — old decoders drop the connection on an unknown byte,
/// killing basic transfer too.
class PeerCapabilities {
  const PeerCapabilities._({
    required this.canSync,
    required this.canBroadcast,
    required this.canMedia,
    required this.canResumeOffset,
    required this.canClipboardBinary,
  });

  /// Derive the capability set from a peer's advertised [DeviceInfo].
  factory PeerCapabilities.of(DeviceInfo info) => PeerCapabilities._(
    canSync: _gate(info, info.supportsSync, BIShareConfig.syncProtocolMinVersion),
    canBroadcast: _gate(
      info,
      info.supportsBroadcast,
      BIShareConfig.broadcastProtocolMinVersion,
    ),
    canMedia: _gate(info, info.supportsMedia, BIShareConfig.mediaProtocolMinVersion),
    canResumeOffset: _gate(
      info,
      info.supportsResumeOffset,
      BIShareConfig.resumeOffsetMinVersion,
    ),
    canClipboardBinary: _gate(
      info,
      info.supportsClipboardBinary,
      BIShareConfig.clipboardBinaryMinVersion,
    ),
  );

  /// Folder sync / shared folders (frames 0x0C–0x0E).
  final bool canSync;

  /// Broadcast transfer (wrapped content keys).
  final bool canBroadcast;

  /// Remote camera / screen mirroring signaling (frame 0x11).
  final bool canMedia;

  /// Chunk-aligned resume offsets on FileStart/Resume.
  final bool canResumeOffset;

  /// Binary clipboard payloads (frame 0x0F).
  final bool canClipboardBinary;

  static bool _gate(DeviceInfo info, bool? flag, String minVersion) =>
      flag == true && BIShareConfig.versionAtLeast(info.version, minVersion);
}
