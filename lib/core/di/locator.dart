import 'dart:async';
import 'dart:io';

import 'package:easy_localization/easy_localization.dart';
import 'package:flutter_secure_storage/flutter_secure_storage.dart';
import 'package:get_it/get_it.dart';
import 'package:path_provider/path_provider.dart';
import 'package:shared_preferences/shared_preferences.dart';

import '../storage/save_folder_channel.dart';
import '../storage/android_downloads_channel.dart';
import '../../features/auth/data/auth_service.dart';
import '../../features/auth/data/authed_dio.dart';
import '../../features/auth/data/oauth_service.dart';
import '../../features/auth/data/token_store.dart';
import '../../features/clipboard/data/clipboard_history_store.dart';
import '../../features/drive/data/drive_service.dart';
import '../../features/clipboard/data/clipboard_relay.dart';
import '../../features/clipboard/data/clipboard_service.dart';
import '../../features/clipboard/data/clipboard_token_store.dart';
import '../../features/discovery/data/discovery_service.dart';
import '../../features/favorites/data/favorites_repository.dart';
import '../../features/folder_sync/data/sync_engine.dart';
import '../../features/folder_sync/data/sync_scheduler.dart';
import '../../features/folder_sync/data/sync_transport.dart';
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
import '../sync/manifest_store.dart';
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
    ..favoriteAutoAccepts = favorites.favoriteAutoAccepts;

  // Local notifications on received files (best-effort).
  final notifications = NotificationService();
  await notifications.init();
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

  // Folder sync (Tahap 4 M1): the engine owns pair auth + crypto + diff/apply;
  // the transfer server stays transport-only via the two delegates. Payloads
  // ride the normal transfer pipeline (TCP, E2E) with sync routing fields.
  final transferClient = TransferClient(identity);
  final syncEngine = SyncEngine(
    db.syncDao,
    ManifestStore(db.syncDao, ownFingerprint: identity.fingerprint),
    identity.crypto,
    ownPublicKeyBase64: identity.publicKeyBase64,
    ownFingerprint: identity.fingerprint,
    ownAlias: identity.alias,
    trashRoot: Directory(
      '${supportDir.path}${Platform.pathSeparator}sync-trash',
    ),
    keyStore: SecureSyncKeyStore(secure),
    peerInfo: httpPeerInfoFetcher(),
    poster: httpSyncPoster(),
    payloadSender: transferPayloadSender(transferClient),
  );
  server
    ..onSyncFrame = syncEngine.handleSyncRequest
    ..syncRootFor = syncEngine.rootForPayload;
  // Auto-sync (M2b): folder watchers + peer-online pushes + periodic rescan.
  final syncScheduler = SyncScheduler(
    (pair, peer) =>
        syncEngine.syncNow(pair.id, host: peer.host, port: peer.port),
    db.syncDao,
    deviceStream: discovery.devices,
    currentDevices: () => discovery.current,
  )..start();

  // Magic-link auth + session. TokenStore holds the session in the secure
  // store; AuthedDio (Bearer + silent refresh) is the client Fase B / Drive
  // will make its authenticated calls through.
  final tokenStore = TokenStore(secure);
  final authService = AuthService();
  final authedDio = AuthedDio(tokenStore, authService);
  // Google/Apple sign-in — exchanges a provider id_token for the same session
  // envelope as magic-link verify (see OauthService).
  final oauthService = OauthService(identity);

  getIt
    ..registerSingleton<SharedPreferences>(prefs)
    ..registerSingleton<DeviceIdentity>(identity)
    ..registerSingleton<TokenStore>(tokenStore)
    ..registerSingleton<AuthService>(authService)
    ..registerSingleton<OauthService>(oauthService)
    ..registerSingleton<AuthedDio>(authedDio)
    // Drive (Fase B): cloud file manager over the authenticated Dio (Bearer +
    // silent refresh). Lazy — no work until the Drive tab is opened.
    ..registerLazySingleton<DriveService>(() => DriveService(authedDio.dio))
    ..registerSingleton<AppDatabase>(db)
    ..registerSingleton<HistoryRepository>(history)
    ..registerSingleton<FavoritesRepository>(favorites)
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
    ..registerSingleton<SyncEngine>(syncEngine)
    ..registerSingleton<SyncScheduler>(syncScheduler)
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
