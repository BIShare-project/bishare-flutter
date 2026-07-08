import 'package:easy_localization/easy_localization.dart';
import 'package:equatable/equatable.dart';
import 'package:flutter/material.dart';
import 'package:shadcn_ui/shadcn_ui.dart';

import '../../../core/server/transfer_types.dart';

/// Whether the device advertises itself for discovery.
enum Visibility { everyone, hidden }

/// Outgoing image quality. Non-[original] re-encodes images to JPEG (capped
/// dimension + quality) before sending to save bandwidth.
enum MediaQuality {
  original,
  high,
  medium;

  /// Max long-edge px (0 = keep) and JPEG quality for this level.
  ({int maxDimension, int quality}) get params => switch (this) {
    MediaQuality.original => (maxDimension: 0, quality: 100),
    MediaQuality.high => (maxDimension: 2560, quality: 90),
    MediaQuality.medium => (maxDimension: 1600, quality: 75),
  };

  String get label => switch (this) {
    MediaQuality.original => 'settings.quality_original'.tr(),
    MediaQuality.high => 'settings.quality_high'.tr(),
    MediaQuality.medium => 'settings.quality_medium'.tr(),
  };
}

/// Transport for outgoing transfers. The choice is symmetric — the sender's
/// transport drives the receiver, which runs both a TCP and a QUIC server and
/// accepts whichever stream arrives.
enum TransportMode {
  auto,
  tcp,
  quic;

  String get label => switch (this) {
    TransportMode.auto => 'settings.transport_auto'.tr(),
    TransportMode.tcp => 'TCP', // protocol name — not translated
    TransportMode.quic => 'QUIC', // protocol name — not translated
  };

  /// One-line explanation shown in the settings picker.
  String get description => switch (this) {
    TransportMode.auto => 'settings.transport_desc_auto'.tr(),
    TransportMode.tcp => 'settings.transport_desc_tcp'.tr(),
    TransportMode.quic => 'settings.transport_desc_quic'.tr(),
  };
}

/// User settings. Persisted to SharedPreferences; changes are applied to the
/// running services (identity alias, receiver auto-accept/PIN, discovery
/// advertisement, save location) and drive the app theme.
class Settings extends Equatable {
  const Settings({
    required this.alias,
    this.themeMode = ThemeMode.system,
    this.accent = 'blue',
    this.receiveAccent = 'green',
    this.pinEnabled = false,
    this.pinCode = '',
    this.autoAccept = AutoAcceptMode.alwaysAsk,
    this.visibility = Visibility.everyone,
    this.mediaQuality = MediaQuality.original,
    this.transport = TransportMode.auto,
    this.saveLocation = '',
    this.clipboardSync = false,
  });

  final String alias;
  final ThemeMode themeMode;

  /// Send / primary accent (drives the app theme).
  final String accent;

  /// Receive-side accent (tints incoming-transfer UI).
  final String receiveAccent;
  final bool pinEnabled;
  final String pinCode;
  final AutoAcceptMode autoAccept;
  final Visibility visibility;
  final MediaQuality mediaQuality;
  final TransportMode transport;

  /// Custom save directory ('' = app default Documents/BIShare).
  final String saveLocation;

  /// Universal-clipboard sync over the LAN (opt-in).
  final bool clipboardSync;

  Settings copyWith({
    String? alias,
    ThemeMode? themeMode,
    String? accent,
    String? receiveAccent,
    bool? pinEnabled,
    String? pinCode,
    AutoAcceptMode? autoAccept,
    Visibility? visibility,
    MediaQuality? mediaQuality,
    TransportMode? transport,
    String? saveLocation,
    bool? clipboardSync,
  }) => Settings(
    alias: alias ?? this.alias,
    themeMode: themeMode ?? this.themeMode,
    accent: accent ?? this.accent,
    receiveAccent: receiveAccent ?? this.receiveAccent,
    pinEnabled: pinEnabled ?? this.pinEnabled,
    pinCode: pinCode ?? this.pinCode,
    autoAccept: autoAccept ?? this.autoAccept,
    visibility: visibility ?? this.visibility,
    mediaQuality: mediaQuality ?? this.mediaQuality,
    transport: transport ?? this.transport,
    saveLocation: saveLocation ?? this.saveLocation,
    clipboardSync: clipboardSync ?? this.clipboardSync,
  );

  @override
  List<Object?> get props => [
    alias,
    themeMode,
    accent,
    receiveAccent,
    pinEnabled,
    pinCode,
    autoAccept,
    visibility,
    mediaQuality,
    transport,
    saveLocation,
    clipboardSync,
  ];
}

/// The selectable accents are shadcn_ui color-scheme NAMES
/// (`ShadColorScheme.fromName`). Every swatch / tint is derived straight from the
/// scheme's own `primary` — no hardcoded colors.
class AccentColors {
  AccentColors._();

  /// All shadcn_ui color schemes, in picker order.
  static const List<String> names = [
    'blue',
    'violet',
    'rose',
    'green',
    'orange',
    'red',
    'yellow',
    'slate',
    'gray',
    'zinc',
    'neutral',
    'stone',
  ];

  /// The scheme's primary color for [brightness] — used for the picker swatch
  /// and for accent-tinted UI (e.g. the receive banner).
  static Color of(String name, Brightness brightness) =>
      ShadColorScheme.fromName(name, brightness: brightness).primary;
}
