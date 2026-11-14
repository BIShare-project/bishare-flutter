import 'dart:convert';
import 'dart:io';
import '../../../core/di/locator.dart';
import '../../../core/storage/app_database.dart';

import 'package:flutter/material.dart' show ThemeMode;
import 'package:flutter_bloc/flutter_bloc.dart';
import 'package:shared_preferences/shared_preferences.dart';

import '../../../core/identity/device_identity.dart';
import '../../../core/server/receive_folders.dart';
import '../../../core/server/transfer_server.dart';
import '../../../core/server/transfer_types.dart';
import '../../../core/storage/all_files_access.dart';
import '../../../core/storage/save_folder_channel.dart';
import '../../clipboard/data/clipboard_service.dart';
import '../../discovery/data/discovery_service.dart';
import '../../send/data/transfer_client.dart';
import '../domain/settings.dart';

/// Owns user [Settings]: loads from SharedPreferences, applies every change to
/// the running services (identity alias, receiver auto-accept/PIN/visibility),
/// and drives the app theme.
class SettingsCubit extends Cubit<Settings> {
  SettingsCubit(
    this._prefs,
    this._identity,
    this._server,
    this._discovery,
    this._clipboard,
    this._client,
  ) : super(_load(_prefs, _identity)) {
    _apply(state); // apply persisted settings to services at startup
    // The ACTUAL save dir is only known after _apply resolves it — and on macOS
    // after the startup security-scoped bookmark restore in the locator (which
    // runs before this cubit). Surface _server.saveDirectory.path so the
    // "Save location" row shows where files really land, not the (possibly
    // empty/stale) persisted base path.
    emit(state.copyWith(resolvedSaveDir: _server.saveDirectory.path));
  }

  final SharedPreferences _prefs;
  final DeviceIdentity _identity;
  final TransferServer _server;
  final DiscoveryService _discovery;
  final ClipboardService _clipboard;
  final TransferClient _client;

  static const _kTheme = 'themeMode';
  static const _kAccent = 'accent';
  static const _kPinEnabled = 'pinEnabled';
  static const _kPinCode = 'pinCode';
  static const _kAutoAccept = 'autoAccept';
  static const _kVisibility = 'visibility';
  static const _kReceiveAccent = 'receiveAccent';
  static const _kMediaQuality = 'mediaQuality';
  static const _kTransport = 'transport';
  static const _kSaveLocation = 'saveLocation';
  static const _kBrowserUpload = 'browserUpload';
  static const _kBrowserUploadMaxGb = 'browserUploadMaxGb';
  static const _kNameWithSender = 'nameWithSender';
  static const _kNameClash = 'nameClash';
  static const _kSortByType = 'sortByType';
  static const _kTypeFolders = 'typeFolders';
  static const kSendLivePhotos = 'sendLivePhotos';
  static const _kTelemetry = 'telemetryEnabled';
  static const _kClipboardSync = 'clipboardSync';
  static const _kClipboardImages = 'clipboardImages';
  static const _kClipboardMaxSizeMb = 'clipboardMaxSizeMb';
  static const _kClipboardCloud = 'clipboardCloud';
  static const _kFolderCloudSync = 'folderCloudSync';

  static Settings _load(SharedPreferences p, DeviceIdentity id) => Settings(
    alias: id.alias,
    themeMode:
        ThemeMode.values.asNameMap()[p.getString(_kTheme)] ?? ThemeMode.system,
    accent: p.getString(_kAccent) ?? 'blue',
    receiveAccent: p.getString(_kReceiveAccent) ?? 'green',
    pinEnabled: p.getBool(_kPinEnabled) ?? false,
    pinCode: p.getString(_kPinCode) ?? '',
    autoAccept:
        AutoAcceptMode.values.asNameMap()[p.getString(_kAutoAccept)] ??
        AutoAcceptMode.alwaysAsk,
    visibility:
        Visibility.values.asNameMap()[p.getString(_kVisibility)] ??
        Visibility.everyone,
    mediaQuality:
        MediaQuality.values.asNameMap()[p.getString(_kMediaQuality)] ??
        MediaQuality.original,
    transport:
        TransportMode.values.asNameMap()[p.getString(_kTransport)] ??
        TransportMode.auto,
    saveLocation: p.getString(_kSaveLocation) ?? '',
    browserUpload: p.getBool(_kBrowserUpload) ?? true,
    browserUploadMaxGb: p.getInt(_kBrowserUploadMaxGb) ?? 0,
    nameWithSender: p.getBool(_kNameWithSender) ?? false,
    nameClash:
        NameClash.values.asNameMap()[p.getString(_kNameClash)] ??
        NameClash.keepBoth,
    sortByType: p.getBool(_kSortByType) ?? true,
    typeFolders: _decodeTypeFolders(p.getString(_kTypeFolders)),
    sendLivePhotos: p.getBool(kSendLivePhotos) ?? true,
    telemetryEnabled: p.getBool(_kTelemetry) ?? true,
    clipboardSync: p.getBool(_kClipboardSync) ?? false,
    folderCloudSync: p.getBool(_kFolderCloudSync) ?? false,
    clipboardImages: p.getBool(_kClipboardImages) ?? true,
    clipboardMaxSizeMb: p.getInt(_kClipboardMaxSizeMb) ?? 5,
    clipboardCloud: p.getBool(_kClipboardCloud) ?? false,
  );

  void _apply(Settings s) {
    _identity.alias = s.alias; // persists to prefs 'deviceAlias'
    _server.autoAccept = s.autoAccept;
    _server.pin = s.pinEnabled && s.pinCode.isNotEmpty ? s.pinCode : null;
    _server.hidden = s.visibility == Visibility.hidden;
    _server.browserUploadEnabled = s.browserUpload;
    _server.browserUploadMaxBytes = s.browserUploadMaxGb * 1024 * 1024 * 1024;
    _server.nameWithSender = s.nameWithSender;
    _server.nameClash = s.nameClash;
    ReceiveFolders.sortByType = s.sortByType;
    ReceiveFolders.custom = SaveFolderChannel.supportsTypeFolders
        ? s.typeFolders
        : const {};
    _discovery.setAdvertising(s.visibility == Visibility.everyone);
    // On macOS the save dir is resolved at startup via the security-scoped
    // bookmark (see _resolveSaveDirectory) — re-applying the bare prefs path here
    // would point at a folder we no longer hold write access to.
    if (!Platform.isMacOS && s.saveLocation.isNotEmpty) {
      // Files go into a BIShare/ subfolder of the chosen folder (not loose in
      // it). On Android the folder is only usable while All files access is
      // granted; if it was revoked, keep the default rather than fail every
      // transfer.
      final dir = SaveFolderChannel.bishareSubdir(s.saveLocation);
      if (!Platform.isAndroid || SaveFolderChannel.isWritable(dir.path)) {
        _server.saveDirectory = dir;
      }
    }
    _clipboard
      ..configure(
        includeImages: s.clipboardImages,
        maxImageBytes: s.clipboardMaxSizeMb * 1024 * 1024,
        cloudSync: s.clipboardCloud,
      )
      ..setEnabled(s.clipboardSync);
    _client.preferredTransport = s.transport;
  }

  Future<void> setAlias(String alias) async {
    final trimmed = alias.trim();
    if (trimmed.isEmpty) return;
    _identity.alias = trimmed;
    await _discovery.restart(); // re-advertise under the new name
    emit(state.copyWith(alias: trimmed));
  }

  Future<void> setThemeMode(ThemeMode mode) async {
    await _prefs.setString(_kTheme, mode.name);
    emit(state.copyWith(themeMode: mode));
  }

  Future<void> setAccent(String accent) async {
    await _prefs.setString(_kAccent, accent);
    emit(state.copyWith(accent: accent));
  }

  Future<void> setAutoAccept(AutoAcceptMode mode) async {
    await _prefs.setString(_kAutoAccept, mode.name);
    _server.autoAccept = mode;
    emit(state.copyWith(autoAccept: mode));
  }

  Future<void> setPin({required bool enabled, String? code}) async {
    final newCode = code ?? state.pinCode;
    await _prefs.setBool(_kPinEnabled, enabled);
    if (code != null) await _prefs.setString(_kPinCode, code);
    _server.pin = enabled && newCode.isNotEmpty ? newCode : null;
    emit(state.copyWith(pinEnabled: enabled, pinCode: newCode));
  }

  Future<void> setVisibility(Visibility v) async {
    await _prefs.setString(_kVisibility, v.name);
    _server.hidden = v == Visibility.hidden;
    await _discovery.setAdvertising(v == Visibility.everyone);
    emit(state.copyWith(visibility: v));
  }

  Future<void> setReceiveAccent(String accent) async {
    await _prefs.setString(_kReceiveAccent, accent);
    emit(state.copyWith(receiveAccent: accent));
  }

  Future<void> setMediaQuality(MediaQuality q) async {
    await _prefs.setString(_kMediaQuality, q.name);
    emit(state.copyWith(mediaQuality: q));
  }

  Future<void> setTransport(TransportMode t) async {
    await _prefs.setString(_kTransport, t.name);
    _client.preferredTransport = t;
    emit(state.copyWith(transport: t));
  }

  Future<void> setNameWithSender(bool on) async {
    await _prefs.setBool(_kNameWithSender, on);
    _server.nameWithSender = on;
    emit(state.copyWith(nameWithSender: on));
  }

  Future<void> setNameClash(NameClash mode) async {
    await _prefs.setString(_kNameClash, mode.name);
    _server.nameClash = mode;
    emit(state.copyWith(nameClash: mode));
  }

  /// Sort received files into a subfolder per type, or keep them together.
  Future<void> setSortByType(bool on) async {
    await _prefs.setBool(_kSortByType, on);
    ReceiveFolders.sortByType = on;
    emit(state.copyWith(sortByType: on));
  }

  /// Let the person choose the folder for files of [category]. The result
  /// says what happened (cancelled, no permission, a folder the app cannot
  /// write to), so the page can tell them why nothing changed.
  Future<TypeFolderResult> pickTypeFolder(String category) async {
    if (!SaveFolderChannel.supportsTypeFolders) {
      return TypeFolderResult.unsupported;
    }
    if (AllFilesAccess.applies && !await AllFilesAccess.request()) {
      return TypeFolderResult.noPermission;
    }
    final path = await SaveFolderChannel.pick();
    if (path == null || path.isEmpty) return TypeFolderResult.cancelled;
    if (!SaveFolderChannel.isWritable(path)) {
      return TypeFolderResult.notWritable;
    }
    await _setTypeFolders({...state.typeFolders, category: path});
    return TypeFolderResult.changed;
  }

  /// Files of [category] go back to their subfolder of the save folder.
  Future<void> resetTypeFolder(String category) =>
      _setTypeFolders({...state.typeFolders}..remove(category));

  Future<void> _setTypeFolders(Map<String, String> folders) async {
    await _prefs.setString(_kTypeFolders, jsonEncode(folders));
    ReceiveFolders.custom = folders;
    emit(state.copyWith(typeFolders: folders));
  }

  static Map<String, String> _decodeTypeFolders(String? raw) {
    if (raw == null || raw.isEmpty) return const {};
    try {
      final m = jsonDecode(raw);
      if (m is! Map) return const {};
      return {
        for (final e in m.entries)
          if (e.key is String &&
              e.value is String &&
              ReceiveFolders.categories.contains(e.key))
            e.key as String: e.value as String,
      };
    } on FormatException {
      return const {};
    }
  }

  Future<void> setSendLivePhotos(bool on) async {
    await _prefs.setBool(kSendLivePhotos, on);
    emit(state.copyWith(sendLivePhotos: on));
  }

  Future<void> setBrowserUpload(bool on) async {
    await _prefs.setBool(_kBrowserUpload, on);
    _server.browserUploadEnabled = on;
    emit(state.copyWith(browserUpload: on));
  }

  /// Toggle anonymous usage telemetry. The key is shared with TelemetryService,
  /// which reads it directly when deciding whether to report a transfer.
  Future<void> setTelemetry(bool on) async {
    await _prefs.setBool(_kTelemetry, on);
    emit(state.copyWith(telemetryEnabled: on));
  }

  Future<void> setBrowserUploadMaxGb(int gb) async {
    await _prefs.setInt(_kBrowserUploadMaxGb, gb);
    _server.browserUploadMaxBytes = gb * 1024 * 1024 * 1024;
    emit(state.copyWith(browserUploadMaxGb: gb));
  }

  Future<void> setClipboardSync(bool on) async {
    await _prefs.setBool(_kClipboardSync, on);
    await _clipboard.setEnabled(on);
    emit(state.copyWith(clipboardSync: on));
  }

  Future<void> setClipboardImages(bool on) async {
    await _prefs.setBool(_kClipboardImages, on);
    _applyClipboardConfig(state.copyWith(clipboardImages: on));
  }

  Future<void> setClipboardMaxSizeMb(int mb) async {
    await _prefs.setInt(_kClipboardMaxSizeMb, mb);
    _applyClipboardConfig(state.copyWith(clipboardMaxSizeMb: mb));
  }

  /// Folder Sync cloud master switch: persists the pref, flips EVERY existing
  /// pair's mode, and (via the engine's default) applies to new pairs. Pro
  /// gating happens at the call site with the live tier.
  Future<void> setFolderCloudSync(bool on) async {
    await _prefs.setBool(_kFolderCloudSync, on);
    final dao = getIt<AppDatabase>().syncDao;
    for (final pair in await dao.allPairs()) {
      await dao.setMode(pair.id, on ? 'lanCloud' : 'lanOnly');
    }
    emit(state.copyWith(folderCloudSync: on));
  }

  Future<void> setClipboardCloud(bool on) async {
    await _prefs.setBool(_kClipboardCloud, on);
    _applyClipboardConfig(state.copyWith(clipboardCloud: on));
  }

  /// Whether this platform can sync clipboard images (drives the sub-option
  /// rows' visibility).
  bool get clipboardImagesSupported => ClipboardService.imagesSupported;

  void _applyClipboardConfig(Settings s) {
    _clipboard.configure(
      includeImages: s.clipboardImages,
      maxImageBytes: s.clipboardMaxSizeMb * 1024 * 1024,
      cloudSync: s.clipboardCloud,
    );
    emit(s);
  }

  Future<void> setSaveLocation(String path) async {
    await _prefs.setString(_kSaveLocation, path);
    if (path.isNotEmpty) {
      // Save into a BIShare/ subfolder of the picked folder, not loose in it.
      _server.saveDirectory = SaveFolderChannel.bishareSubdir(path);
    } else {
      // "Use default": also forget the macOS security-scoped bookmark, else the
      // old custom folder is silently restored on the next launch.
      await SaveFolderChannel.clear();
      _server.resetSaveDirectory();
    }
    // Keep resolvedSaveDir in lockstep with the actual server dir (the base path
    // alone is unreliable on macOS, and both branches above just changed it).
    emit(
      state.copyWith(
        saveLocation: path,
        resolvedSaveDir: _server.saveDirectory.path,
      ),
    );
  }

  /// Whether a custom save folder can be chosen on this platform (desktop only).
  bool get canPickSaveFolder => SaveFolderChannel.isSupported;

  /// The folder received files currently land in (custom or default).
  String get currentSaveDir => _server.saveDirectory.path;

  /// Prompt the user for a save folder. On macOS this also persists a
  /// security-scoped bookmark so access survives restarts.
  Future<TypeFolderResult> pickSaveLocation() async {
    // Android writes outside Downloads only with All files access.
    if (AllFilesAccess.applies && !await AllFilesAccess.request()) {
      return TypeFolderResult.noPermission;
    }
    final path = await SaveFolderChannel.pick();
    if (path == null || path.isEmpty) return TypeFolderResult.cancelled;
    if (!SaveFolderChannel.isWritable(path)) {
      return TypeFolderResult.notWritable;
    }
    await setSaveLocation(path);
    return TypeFolderResult.changed;
  }

  /// Whether the save folder can be opened in a file browser from here.
  bool get canRevealSaveFolder => SaveFolderChannel.canReveal;

  /// Whether a folder can be chosen per file type on this platform.
  bool get canPickTypeFolders => SaveFolderChannel.supportsTypeFolders;

  /// Open the current save folder in the system file browser.
  Future<void> revealSaveLocation() =>
      SaveFolderChannel.reveal(_server.saveDirectory.path);
}

/// What came of choosing a folder.
enum TypeFolderResult {
  changed,
  cancelled,
  noPermission,
  notWritable,
  unsupported,
}
