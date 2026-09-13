import 'dart:async';
import 'dart:convert';
import 'dart:io';

import 'package:bishare/core/config/feature_flags.dart';
import 'package:bishare/core/identity/device_identity.dart';
import 'package:bishare/core/server/transfer_server.dart';
import 'package:bishare/core/telemetry/telemetry_service.dart';
import 'package:bishare/features/history/data/history_repository.dart';
import 'package:bishare/features/remote/data/cloud_transfer_service.dart';
import 'package:bishare/features/room/data/room_service.dart';
import 'package:bishare/features/room/data/webrtc_signaling.dart';
import 'package:bishare/features/room/domain/room_models.dart';
import 'package:dio/dio.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:shared_preferences/shared_preferences.dart';

import 'helpers/rust_test_lib.dart';

/// The app's real network clients against a local bishare-api worker — the
/// check before an API deploy that the shipped app still works with it. Runs
/// only when pointed at one:
///
///   flutter test test/api_live_client_test.dart \
///     --dart-define=BISHARE_API_BASE=http://127.0.0.1:8799 \
///     --dart-define=BISHARE_WS_BASE=ws://127.0.0.1:8799 \
///     --dart-define=API_LIVE_RESTART="(shell command that restarts the worker)"
///
/// API_LIVE_RESTART is optional; without it the outage tests are skipped.
const _live = bool.hasEnvironment('BISHARE_API_BASE');
const _api = String.fromEnvironment('BISHARE_API_BASE');
const _restart = String.fromEnvironment('API_LIVE_RESTART');

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

/// Every event a service emits, kept so a test can wait for one that already
/// happened.
class _Events {
  _Events(Stream<RoomEvent> stream) {
    _sub = stream.listen(all.add);
  }
  final List<RoomEvent> all = [];
  late final StreamSubscription<RoomEvent> _sub;

  Future<T> waitFor<T extends RoomEvent>([bool Function(T)? where, Duration timeout = const Duration(seconds: 60)]) async {
    final end = DateTime.now().add(timeout);
    var seen = 0;
    while (DateTime.now().isBefore(end)) {
      for (; seen < all.length; seen++) {
        final e = all[seen];
        if (e is T && (where == null || where(e))) return e;
      }
      await Future<void>.delayed(const Duration(milliseconds: 100));
    }
    throw TimeoutException('waiting for $T');
  }

  int count<T extends RoomEvent>() => all.whereType<T>().length;
  Future<void> dispose() => _sub.cancel();
}

final _dio = Dio(BaseOptions(baseUrl: _api, validateStatus: (_) => true));

Future<int> _memberCount(String code) async {
  final res = await _dio.get<Map<String, dynamic>>('/api/v1/rooms/$code/info');
  return ((res.data?['data'] as Map?)?['memberCount'] as num?)?.toInt() ?? -1;
}

Future<bool> _apiUp() async {
  for (var i = 0; i < 90; i++) {
    try {
      final r = await _dio.get<dynamic>('/health');
      if (r.statusCode == 200) return true;
    } on Object {
      // not yet
    }
    await Future<void>.delayed(const Duration(seconds: 1));
  }
  return false;
}

Future<void> _stopApi() => Process.run('pkill', ['-f', 'wrangler dev --local --ip 0.0.0.0 --port 8799']);
Future<void> _startApi() => Process.start('bash', ['-c', _restart], mode: ProcessStartMode.detached);

void main() {
  late SharedPreferences prefs;
  late Directory tmp;

  setUpAll(() async {
    if (!_live) return;
    expect(await initRustForTests(), isTrue, reason: 'BSE2 needs the Rust build');
    SharedPreferences.setMockInitialValues({'telemetryEnabled': true});
    prefs = await SharedPreferences.getInstance();
    tmp = await Directory.systemTemp.createTemp('bishare-api-live');
  });

  RoomService service(String fp, String alias) {
    final save = Directory('${tmp.path}/$fp')..createSync(recursive: true);
    return RoomService(_Identity(fp, alias), _Server(save), _History(), prefs);
  }

  /// Both services share one SharedPreferences; drop the stored room key so the
  /// joiner has to get it over the wire, as a second device would.
  Future<void> forgetStoredKeys() async {
    for (final k in prefs.getKeys().where((k) => k.startsWith('room_key:')).toList()) {
      await prefs.remove(k);
    }
  }

  test('config: feature flags load from GET /api/v1/config', () async {
    final flags = FeatureFlags(prefs);
    await flags.refresh();
    expect(flags.webNearbyEnabled, isTrue);
  }, skip: !_live);

  test('rooms: app ↔ app create, key hand-off, files both ways, idle, leave, close', () async {
    final host = service('live-host-fp', 'Host');
    final guest = service('live-guest-fp', 'Guest');
    final he = _Events(host.events);
    final ge = _Events(guest.events);

    final session = await host.createRemote();
    expect(host.security, RoomSecurity.encrypted);
    final code = session.code;
    await he.waitFor<RoomSyncEvent>();
    await forgetStoredKeys();

    await guest.joinRemote(code);
    await ge.waitFor<RoomSyncEvent>();
    await he.waitFor<RoomMemberJoinedEvent>((e) => e.member.fingerprint == 'live-guest-fp');
    // Guest gets K from the host over key_request → key_grant (hibernating DO).
    await ge.waitFor<RoomSecurityEvent>((e) => e.security == RoomSecurity.encrypted);

    final a = File('${tmp.path}/from-host.txt')..writeAsStringSync('host → guest ${DateTime.now()}');
    await host.uploadFile(code, a, fileName: 'from-host.txt', mimeType: 'text/plain');
    final added = await ge.waitFor<RoomFileAddedEvent>((e) => e.file.fileName == 'from-host.txt');
    final got = await guest.downloadFile(code, added.file);
    expect(got.readAsStringSync(), a.readAsStringSync());

    final b = File('${tmp.path}/from-guest.txt')..writeAsStringSync('guest → host ${DateTime.now()}');
    await guest.uploadFile(code, b, fileName: 'from-guest.txt', mimeType: 'text/plain');
    final back = await he.waitFor<RoomFileAddedEvent>((e) => e.file.fileName == 'from-guest.txt');
    expect((await host.downloadFile(code, back.file)).readAsStringSync(), b.readAsStringSync());

    // Past the 30 s ping timeout with no traffic: both still members.
    await Future<void>.delayed(const Duration(seconds: 36));
    expect(await _memberCount(code), 2);

    await guest.leave(code);
    await he.waitFor<RoomMemberLeftEvent>((e) => e.fingerprint == 'live-guest-fp');
    expect(await _memberCount(code), 1);

    // Guest back in, then the host closes: the guest hears it once and stops.
    final ge2 = _Events(guest.events);
    await guest.joinRemote(code);
    await ge2.waitFor<RoomSyncEvent>();
    await host.close(code, session.hostToken!);
    await ge2.waitFor<RoomClosedEvent>();
    await Future<void>.delayed(const Duration(seconds: 40));
    expect(ge2.count<RoomClosedEvent>(), 1, reason: 'closed room must not be re-announced by reconnects');
    expect((await _dio.get<dynamic>('/api/v1/rooms/$code/info')).statusCode, 404);

    await he.dispose();
    await ge.dispose();
    await ge2.dispose();
  }, skip: !_live, timeout: const Timeout(Duration(minutes: 5)));

  test('rooms: survives an API outage, then a room that died meanwhile ends the session', () async {
    final host = service('outage-host-fp', 'Host');
    final guest = service('outage-guest-fp', 'Guest');
    final ge = _Events(guest.events);
    final session = await host.createRemote();
    await forgetStoredKeys();
    await guest.joinRemote(session.code);
    await ge.waitFor<RoomSyncEvent>();

    // Outage → the guest reconnects on its own once the worker is back.
    final syncsBefore = ge.count<RoomSyncEvent>();
    await _stopApi();
    await Future<void>.delayed(const Duration(seconds: 20));
    await _startApi();
    expect(await _apiUp(), isTrue);
    await ge.waitFor<RoomSyncEvent>((_) => ge.count<RoomSyncEvent>() > syncsBefore, const Duration(seconds: 90));

    // Second outage; the host closes the room while the guest is away. The
    // guest's rejoins now hit a dead room → /info 404 → one RoomClosedEvent.
    await _stopApi();
    await Future<void>.delayed(const Duration(seconds: 8));
    await _startApi();
    expect(await _apiUp(), isTrue);
    final del = await _dio.delete<dynamic>(
      '/api/v1/rooms/${session.code}',
      options: Options(headers: {'X-Host-Token': session.hostToken}),
    );
    expect(del.statusCode, 200);
    await ge.waitFor<RoomClosedEvent>(null, const Duration(seconds: 150));
    await Future<void>.delayed(const Duration(seconds: 35));
    expect(ge.count<RoomClosedEvent>(), 1);
    await ge.dispose();
  }, skip: !_live || _restart.isEmpty, timeout: const Timeout(Duration(minutes: 8)));

  test('nearby signaling: roster, relay, and the full roster callback', () async {
    final code = 'live${DateTime.now().millisecondsSinceEpoch}';
    final aPeers = <SignalPeer>[];
    final bSignals = <IncomingSignal>[];
    final joined = Completer<SignalPeer>();
    final a = WebrtcSignaling(const SignalPeer(peerId: 'app-a', alias: 'A', emoji: 'a', kind: 'app'), code)
      ..onPeers = aPeers.addAll
      ..onPeerJoined = (p) {
        if (!joined.isCompleted) joined.complete(p);
      };
    a.connect();
    await Future<void>.delayed(const Duration(seconds: 1));
    final bRoster = Completer<List<SignalPeer>>();
    final b = WebrtcSignaling(const SignalPeer(peerId: 'app-b', alias: 'B', emoji: 'b', kind: 'app'), code)
      ..onPeers = ((l) => bRoster.complete(l))
      ..onSignal = bSignals.add;
    b.connect();
    final roster = await bRoster.future.timeout(const Duration(seconds: 10));
    expect(roster.map((p) => '${p.peerId}/${p.kind}'), ['app-a/app']);
    expect((await joined.future.timeout(const Duration(seconds: 10))).peerId, 'app-b');
    a.signal('app-b', 'offer', {'sdp': 'x'});
    await Future<void>.delayed(const Duration(seconds: 1));
    expect(bSignals.single.from, 'app-a');
    expect(bSignals.single.payload['sdp'], 'x');

    // Fill to 30, then the 31st hears "full".
    final crowd = <WebrtcSignaling>[];
    for (var i = 0; i < 28; i++) {
      crowd.add(WebrtcSignaling(SignalPeer(peerId: 'crowd-$i', alias: 'c', emoji: 'c'), code)..connect());
      await Future<void>.delayed(const Duration(milliseconds: 80));
    }
    await Future<void>.delayed(const Duration(seconds: 1));
    final full = Completer<void>();
    final extra = WebrtcSignaling(const SignalPeer(peerId: 'extra', alias: 'x', emoji: 'x'), code)
      ..onFull = full.complete;
    extra.connect();
    await full.future.timeout(const Duration(seconds: 10));
    for (final s in [a, b, extra, ...crowd]) {
      s.close();
    }
  }, skip: !_live);

  test('telemetry: the app\'s report is accepted and counted after the flush', () async {
    Future<num> bytesToday() async {
      final today = DateTime.now().toUtc().toIso8601String().substring(0, 10);
      final r = await Process.run('bash', [
        '-c',
        'cd /Users/cakrabudiman/Documents/bishare-project/bishare-api && npx wrangler d1 execute bishare-cloud --local '
            '--persist-to /private/tmp/claude-501/-Users-cakrabudiman-Documents-bishare-project/f7820fe0-fec9-4a00-b3bb-98d1f102ef37/scratchpad/apitest/state '
            '--json --command "SELECT COALESCE(SUM(value),0) v FROM stats_daily WHERE date=\'$today\' AND metric=\'nearby_bytes\'"',
      ]);
      final rows = (jsonDecode(r.stdout as String) as List).first['results'] as List;
      return rows.first['v'] as num;
    }

    final before = await bytesToday();
    TelemetryService(prefs).recordTransfer(bytes: 4242);
    await Future<void>.delayed(const Duration(seconds: 14));
    expect(await bytesToday() - before, 4242);
  }, skip: !_live, timeout: const Timeout(Duration(minutes: 2)));

  test('cloud upload: over the daily quota the app shows a clear message', () async {
    // The worker runs with TRANSFER_DAILY_QUOTA_BYTES=3000 for this suite.
    final svc = CloudTransferService(_Server(tmp), _History());
    final f = File('${tmp.path}/over-quota.bin')..writeAsBytesSync(List.filled(4000, 7));
    Object? error;
    try {
      await svc.uploadTransfer(file: f, fileName: 'over-quota.bin', mimeType: 'text/plain', senderAlias: 'T', encrypt: false);
    } on Object catch (e) {
      error = e;
    }
    expect(error, isNotNull);
    expect(describeDownloadError(error!), contains('Too many uploads'));
  }, skip: !_live);
}
