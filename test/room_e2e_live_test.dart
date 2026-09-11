import 'dart:async';
import 'dart:io';

import 'package:bishare/core/identity/device_identity.dart';
import 'package:bishare/core/server/transfer_server.dart';
import 'package:bishare/features/history/data/history_repository.dart';
import 'package:bishare/features/room/data/room_service.dart';
import 'package:bishare/features/room/domain/room_models.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:shared_preferences/shared_preferences.dart';

import 'helpers/rust_test_lib.dart';

/// App ↔ browser in one end-to-end encrypted room, over a real (local) room
/// worker. Runs only when pointed at one, next to the Playwright half
/// (scratch rooms-app-web.mjs), which it coordinates with through marker
/// files in ROOM_LIVE_DIR:
///
///   flutter test test/room_e2e_live_test.dart \
///     --dart-define=BISHARE_API_BASE=http://localhost:8799 \
///     --dart-define=BISHARE_WS_BASE=ws://localhost:8799 \
///     --dart-define=ROOM_LIVE_DIR=/path/to/dir
const _live = bool.hasEnvironment('BISHARE_API_BASE');
const _dir = String.fromEnvironment('ROOM_LIVE_DIR');

class _Identity implements DeviceIdentity {
  _Identity(this.fingerprint, this._alias);
  @override
  final String fingerprint;
  final String _alias;
  @override
  String get alias => _alias;
  @override
  String get deviceType => 'mobile';
  @override
  dynamic noSuchMethod(Invocation i) => super.noSuchMethod(i);
}

class _Server implements TransferServer {
  _Server(this.saveDirectory);
  @override
  final Directory saveDirectory;
  @override
  dynamic noSuchMethod(Invocation i) => super.noSuchMethod(i);
}

class _History implements HistoryRepository {
  @override
  Future<void> recordReceived(dynamic f) async {}
  @override
  dynamic noSuchMethod(Invocation i) => super.noSuchMethod(i);
}

Future<String> _waitFile(String name, {Duration timeout = const Duration(minutes: 3)}) async {
  final f = File('$_dir/$name');
  final end = DateTime.now().add(timeout);
  while (!f.existsSync()) {
    if (DateTime.now().isAfter(end)) throw TimeoutException('waiting for $name');
    await Future<void>.delayed(const Duration(milliseconds: 250));
  }
  return f.readAsStringSync().trim();
}

Future<T> _waitFor<T>(Stream<RoomEvent> events, T? Function(RoomEvent) pick, T? now) async {
  if (now != null) return now;
  return events.map(pick).firstWhere((v) => v != null).then((v) => v as T).timeout(const Duration(seconds: 60));
}

void main() {
  late RoomService rooms;
  late Directory save;

  setUpAll(() async {
    if (!_live) return;
    expect(await initRustForTests(), isTrue, reason: 'BSE2 needs the Rust build');
    SharedPreferences.setMockInitialValues({});
    save = await Directory('$_dir/app-saved').create(recursive: true);
    rooms = RoomService(_Identity('app-fp-live', 'Phone'), _Server(save), _History(), await SharedPreferences.getInstance());
  });

  test('joins a room a browser made: gets the key from the browser, opens and seals files', () async {
    final code = await _waitFile('web-room.txt');
    final (_, _, files) = await rooms.joinRemote(code);

    // The browser holds K; the app must receive it over the hand-off.
    await _waitFor<bool>(
      rooms.events,
      (e) => e is RoomSecurityEvent && e.security == RoomSecurity.encrypted ? true : null,
      rooms.security == RoomSecurity.encrypted ? true : null,
    );

    // The browser's file: listed sealed on join, revealed once K arrived.
    final revealed = await _waitFor<RoomFile>(
      rooms.events,
      (e) => e is RoomFilesRevealedEvent ? e.files.where((f) => f.fileName == 'from-web.txt').firstOrNull : null,
      files.where((f) => f.fileName == 'from-web.txt').firstOrNull,
    );
    expect(revealed.revealed, isTrue);
    final got = await rooms.downloadFile(code, revealed);
    expect(got.readAsBytesSync(), File('$_dir/from-web.txt').readAsBytesSync());

    // The app seals one back for the browser to open.
    final up = await rooms.uploadFile(code, File('$_dir/from-app.txt'), fileName: 'from-app.txt', mimeType: 'text/plain');
    expect(up.enc, isNotNull);
    expect(up.fileName, 'from-app.txt');
    File('$_dir/app-uploaded').writeAsStringSync('1');
    await _waitFile('web-done-1');
    await rooms.leave(code);
  }, skip: !_live);

  test('hosts a room: hands the key to a browser that joins', () async {
    final session = await rooms.createRemote();
    expect(rooms.security, RoomSecurity.encrypted);
    await rooms.uploadFile(session.code, File('$_dir/from-app-2.txt'), fileName: 'from-app-2.txt', mimeType: 'text/plain');
    File('$_dir/app-room.txt').writeAsStringSync(session.code);
    await _waitFile('web-done-2');
    await rooms.close(session.code, session.hostToken!);
  }, skip: !_live);
}
