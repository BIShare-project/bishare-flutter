import 'dart:io';

import 'package:flutter_secure_storage/flutter_secure_storage.dart';
import 'package:get_it/get_it.dart';
import 'package:path_provider/path_provider.dart';
import 'package:shared_preferences/shared_preferences.dart';

import '../storage/save_folder_channel.dart';
import '../storage/android_downloads_channel.dart';
import '../../features/clipboard/data/clipboard_service.dart';
import '../../features/discovery/data/discovery_service.dart';
import '../../features/favorites/data/favorites_repository.dart';
import '../../features/history/data/history_repository.dart';
import '../../features/nearby/data/nearby_service.dart';
import '../../features/remote/data/cloud_transfer_service.dart';
import '../../features/remote/data/stream_relay_service.dart';
import '../../features/room/data/local_room_service.dart';
import '../../features/room/data/room_service.dart';
import '../../features/send/data/transfer_client.dart';
import '../deeplink/deep_link_service.dart';
import '../desktop/desktop_service.dart';
import '../identity/device_identity.dart';
import '../notifications/notification_service.dart';
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

  final discovery = DiscoveryService(identity);

  // Universal-clipboard sync (opt-in via Settings). An incoming clipboard posts
  // a best-effort local notification.
  final clipboard = ClipboardService(identity, discovery)
    ..onReceived = (sender, _) =>
        notifications.notify('Clipboard synced', 'Copied from $sender');

  getIt
    ..registerSingleton<SharedPreferences>(prefs)
    ..registerSingleton<DeviceIdentity>(identity)
    ..registerSingleton<AppDatabase>(db)
    ..registerSingleton<HistoryRepository>(history)
    ..registerSingleton<FavoritesRepository>(favorites)
    ..registerSingleton<DiscoveryService>(discovery)
    ..registerSingleton<TransferServer>(server)
    ..registerSingleton<NotificationService>(notifications)
    ..registerSingleton<ClipboardService>(clipboard)
    ..registerSingleton<CloudTransferService>(
      CloudTransferService(server, history),
    )
    ..registerSingleton<RoomService>(RoomService(identity, server, history))
    ..registerSingleton<LocalRoomService>(
      LocalRoomService(identity, server, history),
    )
    ..registerSingleton<StreamRelayService>(
      StreamRelayService(server, history),
    )
    ..registerSingleton<DeepLinkService>(DeepLinkService())
    ..registerSingleton<TransferClient>(TransferClient(identity))
    ..registerSingleton<NearbyService>(NearbyService())
    ..registerSingleton<DesktopService>(DesktopService(server));
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
/// Always kept in a `BIShare/` subfolder for the default location so it doesn't
/// clutter Documents; a user-picked folder is used directly.
Future<Directory> _resolveSaveDirectory() async {
  if (Platform.isMacOS) {
    final picked = await SaveFolderChannel.restore();
    if (picked != null && picked.isNotEmpty) {
      final dir = Directory(picked);
      if (dir.existsSync()) return dir;
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
