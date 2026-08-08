import 'dart:async';
import 'dart:io';

import 'package:flutter/foundation.dart';
import 'package:easy_localization/easy_localization.dart';
import 'package:flutter_secure_storage/flutter_secure_storage.dart';
import 'package:get_it/get_it.dart';
import 'package:path_provider/path_provider.dart';
import 'package:shared_preferences/shared_preferences.dart';

import '../config/feature_flags.dart';
import '../storage/save_folder_channel.dart';
import '../storage/android_downloads_channel.dart';
import '../../features/clipboard/data/clipboard_history_store.dart';
import '../../features/clipboard/data/clipboard_relay.dart';
import '../../features/clipboard/data/clipboard_service.dart';
import '../../features/clipboard/data/clipboard_token_store.dart';
import '../../features/discovery/data/discovery_service.dart';
import '../../features/favorites/data/favorites_repository.dart';
import '../../features/history/data/history_repository.dart';
import '../../features/nearby/data/nearby_service.dart';
import '../../features/remote/data/cloud_config_service.dart';
import '../../features/remote/data/cloud_transfer_service.dart';
import '../../features/remote/data/stream_relay_service.dart';
import '../../features/room/data/local_room_service.dart';
import '../../features/room/data/room_service.dart';
import '../../features/send/data/transfer_client.dart';
import '../deeplink/deep_link_service.dart';
import '../desktop/desktop_service.dart';
import '../devices/device_registry.dart';
import '../identity/device_identity.dart';
import '../identity/pinned_keys.dart';
import '../notifications/notification_service.dart';
import '../relay/relay_channel.dart';
import '../server/browser_share.dart';
import '../server/transfer_server.dart';
import '../storage/app_database.dart';

/// The service locator. The plan targets `injectable`-generated wiring; this
/// hand-written registration is the equivalent for the P0 scaffold and keeps the
/// dependency graph explicit and codegen-free.
final GetIt getIt = GetIt.instance;

Future<void> setupLocator() async {
  final prefs = await SharedPreferences.getInstance();
  const secure = FlutterSecureStorage();
  // Remote feature flags (drive visibility, free cloud-sync period): cached
  // copy applies immediately, the network refresh lands in the background.
  final featureFlags = FeatureFlags(prefs);
  // Best-effort: a failed cache/network read must not abort setup (which would
  // leave getIt unpopulated → blank launch). Defaults apply until refresh lands.
  try {
    await featureFlags.load();
  } on Object catch (e) {
    debugPrint('[locator] feature flags load failed: $e');
  }
  final identity = await DeviceIdentity.load(prefs: prefs, secure: secure);
  final saveDir = await _resolveSaveDirectory();

  final server = TransferServer(identity: identity, saveDirectory: saveDir);
  final db = AppDatabase();
  // Trim roster peers unseen for 90+ days (favorites are never purged) so the
  // Devices list can't grow unbounded. Fire-and-forget: startup never waits on
  // it, and a failure is harmless — the next launch retries.
  unawaited(db.purgeOlderThan(90));
  final history = HistoryRepository(db)..attach(server);
  final favorites = FavoritesRepository(db);
  final pinnedKeys = PinnedKeysStore(prefs);

  // Feed the browser Web-Share file list from the received-files log on disk.
  server.receivedFilesProvider = () async {
    final rows = await db.receivedRecords();
    return [
      for (final r in rows)
        if (r.savedPath != null && File(r.savedPath!).existsSync())
          BrowserFile(
            fileName: r.fileName,
            fileType: r.fileType ?? '',
            path: r.savedPath!,
            size: r.fileSize,
          ),
    ];
  };

  // Let the receiver consult favorites during an incoming prepare.
  server
    ..isFavorite = favorites.isFavorite
    ..favoriteAutoAccepts = favorites.favoriteAutoAccepts
    // P0: gate auto-accept on the sender's pinned key (TOFU pin + change detect).
    ..keyMatchesPinned = pinnedKeys.recordAndMatch;

  // Local notifications on received files (best-effort). The Darwin init +
  // permission request can misbehave on a compat runtime; a failure must not
  // abort setup (getIt would stay empty → blank launch).
  final notifications = NotificationService();
  try {
    await notifications.init();
  } on Object catch (e) {
    debugPrint('[locator] notification init failed: $e');
  }
  notifications.attach(server);

  // Seed the advertise intent from persisted visibility so a device the user set
  // to "Hidden" never leaks a cold-start advertisement before SettingsCubit
  // applies. The 'visibility' pref stores Visibility.name ('everyone'|'hidden').
  final discovery = DiscoveryService(
    identity,
    advertise: prefs.getString('visibility') != 'hidden',
  );

  // Universal-clipboard sync (opt-in via Settings). Announced image bytes are
  // staged in the token store the transfer server serves; synced items land in
  // the drift-backed ring-buffer history; the cloud relay stays dormant until
  // its (OFF-default) setting turns it on. Incoming clipboards post a
  // best-effort local notification.
  final clipboardTokens = ClipboardTokenStore();
  server.clipboardTokens = clipboardTokens;
  final supportDir = await getApplicationSupportDirectory();
  final clipboardHistory = ClipboardHistoryStore(
    db,
    Directory('${supportDir.path}${Platform.pathSeparator}clipboard'),
  );
  final clipboard = ClipboardService(identity, discovery)
    ..tokenStore = clipboardTokens
    ..history = clipboardHistory
    // The factory keeps RelayChannelClient lazy (see its registration below):
    // no Dio/socket until the cloud toggle actually turns the relay on.
    ..relay = ClipboardRelay(() => getIt<RelayChannelClient>(), identity)
    ..onReceived = (sender, _) {
      notifications.notify(
        'notification.clipboard_synced'.tr(),
        'notification.clipboard_from'.tr(namedArgs: {'sender': sender}),
      );
    }
    ..onReceivedImage = (sender) {
      notifications.notify(
        'notification.clipboard_synced'.tr(),
        'notification.clipboard_image_from'.tr(namedArgs: {'sender': sender}),
      );
    };

  // Unified device roster (discovery ∪ favorites ∪ drift KnownDevices) with
  // presence, plus the sighting writer that keeps lastSeen/lastIp fresh.
  final deviceRegistry = PresenceDeviceRegistry(db, discovery, favorites);

  // Transfer client for the LAN send pipeline (TCP, E2E).
  final transferClient = TransferClient(identity);

  getIt
    ..registerSingleton<SharedPreferences>(prefs)
    ..registerSingleton<FeatureFlags>(featureFlags)
    ..registerSingleton<DeviceIdentity>(identity)
    ..registerSingleton<AppDatabase>(db)
    ..registerSingleton<HistoryRepository>(history)
    ..registerSingleton<FavoritesRepository>(favorites)
    ..registerSingleton<PinnedKeysStore>(pinnedKeys)
    ..registerSingleton<DiscoveryService>(discovery)
    ..registerSingleton<PresenceDeviceRegistry>(deviceRegistry)
    ..registerSingleton<TransferServer>(server)
    ..registerSingleton<NotificationService>(notifications)
    ..registerSingleton<ClipboardService>(clipboard)
    ..registerSingleton<ClipboardHistoryStore>(clipboardHistory)
    ..registerSingleton<CloudTransferService>(
      CloudTransferService(server, history),
    )
    // Tier limits from GET /api/v1/config, cached per run (1 GiB fallback).
    // Lazy: no Dio until the remote-share flow first checks the limit.
    ..registerLazySingleton<CloudConfigService>(CloudConfigService.new)
    ..registerSingleton<RoomService>(RoomService(identity, server, history))
    ..registerSingleton<LocalRoomService>(
      LocalRoomService(identity, server, history),
    )
    ..registerSingleton<StreamRelayService>(
      StreamRelayService(server, history),
    )
    ..registerSingleton<DeepLinkService>(DeepLinkService())
    ..registerSingleton<TransferClient>(transferClient)
    ..registerSingleton<NearbyService>(NearbyService())
    ..registerSingleton<DesktopService>(DesktopService(server))
    // Cloud relay WS+REST client (v2.4 premium features). Lazy: it stays
    // dormant — no socket, not even a Dio — until a feature calls connect().
    ..registerLazySingleton<RelayChannelClient>(RelayChannelClient.new);
}

/// Where received files land.
///
/// * **macOS** (sandboxed): if the user picked a custom folder before, re-grant
///   write access via its security-scoped bookmark and save straight there; else
///   the app Documents dir. The Settings "Save location" row changes this.
/// * **Windows / Linux**: the plain custom path (applied by [SettingsCubit]) or
///   the app Documents dir.
/// * **iOS**: the app Documents dir (iOS surfaces it in the Files app).
/// * **Android**: public Downloads directory (visible in Files app + Gallery).
///
/// Files always land in a `BIShare/` subfolder — of the default location AND of
/// any user-picked folder — so a chosen folder (e.g. the Desktop) isn't
/// cluttered with loose received files (mirrors Android/iOS).
Future<Directory> _resolveSaveDirectory() async {
  if (Platform.isMacOS) {
    final picked = await SaveFolderChannel.restore();
    if (picked != null && picked.isNotEmpty && Directory(picked).existsSync()) {
      return SaveFolderChannel.bishareSubdir(picked);
    }
  }
  if (Platform.isAndroid) {
    // Android: use public Downloads (visible in Files app + Gallery)
    // Note: Requires scoped storage (Android 10+), Downloads is always writable
    final downloadsPath = await AndroidDownloadsPath.getPublicDownloads();
    if (downloadsPath != null && downloadsPath.isNotEmpty) {
      final dir = Directory('$downloadsPath${Platform.pathSeparator}BIShare');
      if (!dir.existsSync()) dir.createSync(recursive: true);
      return dir;
    }
    // Fallback to app Documents if channel unavailable
  }
  // iOS, macOS (default), Windows, Linux
  final base = await getApplicationDocumentsDirectory();
  final dir = Directory('${base.path}${Platform.pathSeparator}BIShare');
  if (!dir.existsSync()) dir.createSync(recursive: true);
  return dir;
}
