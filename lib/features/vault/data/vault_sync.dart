import 'dart:async';
import 'dart:convert';
import 'dart:math';

import 'package:drift/drift.dart' show Value;
import 'package:flutter/foundation.dart';
import 'package:web_socket_channel/web_socket_channel.dart';

import '../../../core/rust/rust_facade.dart';
import '../../../core/storage/app_database.dart';
import '../../../core/storage/vault_tables.dart';
import 'vault_api.dart';
import 'vault_keys.dart';

/// The local index of the Drive (drive-plan.md task 4.3): pulls `changes`
/// page by page, opens each `enc_meta` with `K_meta`, and keeps
/// [VaultObjects] in step; a WebSocket says when the server's sequence moves,
/// so another device's change shows up without polling.
///
/// The server never sees a name; this is the only place they exist, opened.
/// An `enc_meta` that does not open (another vault's, or tampered with) is
/// left out of the index and logged, never shown half-read.
class VaultSync extends ChangeNotifier {
  VaultSync({
    required VaultApi api,
    required VaultKeyStore keys,
    required VaultDao dao,
    WebSocketChannel Function(Uri uri)? connect,
  }) : _api = api,
       _keys = keys,
       _dao = dao,
       _connect = connect ?? WebSocketChannel.connect;

  final VaultApi _api;
  final VaultKeyStore _keys;
  final VaultDao _dao;
  final WebSocketChannel Function(Uri uri) _connect;

  static const _kSeq = 'seq';
  static const _kVault = 'vaultId';

  Future<void>? _pulling;
  bool _again = false;
  bool _running = false;
  WebSocketChannel? _ws;
  StreamSubscription<dynamic>? _wsSub;
  Timer? _retry;
  int _backoff = 0;

  /// The sequence the index is at, once a pull has run on this start.
  int _known = -1;

  bool _syncing = false;
  bool get syncing => _syncing;

  /// Pull until the index has everything up to the server's sequence. Calls
  /// made while a pull runs join it, and one more pull follows, so a change
  /// announced mid-pull is never missed.
  Future<void> pull() {
    if (_pulling != null) {
      _again = true;
      return _pulling!;
    }
    final run = _pullLoop().whenComplete(() => _pulling = null);
    _pulling = run;
    return run;
  }

  Future<void> _pullLoop() async {
    _syncing = true;
    notifyListeners();
    try {
      do {
        _again = false;
        await _pullOnce();
      } while (_again);
    } finally {
      _syncing = false;
      notifyListeners();
    }
  }

  Future<void> _pullOnce() async {
    final vaultId = await _keys.vaultId();
    final vk = await _keys.vaultKey();
    if (vaultId == null || vk == null) return;
    // The index belongs to one vault: a different one on this device (another
    // account) starts from nothing.
    if (await _dao.stateValue(_kVault) != vaultId) {
      await _dao.clearAll();
      await _dao.setStateValue(_kVault, vaultId);
    }
    final metaKey = Rust.vaultMetaKey(vk);
    var since = int.tryParse(await _dao.stateValue(_kSeq) ?? '') ?? 0;
    while (true) {
      final page = await _api.changes(vaultId, since);
      await _dao.transaction(() async {
        if (page.resync) await _dao.clearIndex();
        await _apply(vaultId, metaKey, page.objects);
        await _dao.setStateValue(_kSeq, '${page.seq}');
      });
      since = page.seq;
      _known = since;
      if (!page.more) break;
    }
  }

  Future<void> _apply(
    String vaultId,
    Uint8List metaKey,
    List<VaultChange> objects,
  ) async {
    final gone = <String>[];
    final rows = <VaultObjectsCompanion>[];
    for (final o in objects) {
      final enc = o.encMeta;
      if (o.deleted || enc == null) {
        gone.add(o.id);
        continue;
      }
      final row = openRow(vaultId, metaKey, o);
      if (row == null) {
        gone.add(o.id);
        continue;
      }
      rows.add(row);
    }
    if (gone.isNotEmpty) await _dao.deleteObjects(gone);
    if (rows.isNotEmpty) await _dao.upsertObjects(rows);
  }

  /// The index row for one change, or null when its metadata does not open.
  @visibleForTesting
  static VaultObjectsCompanion? openRow(
    String vaultId,
    Uint8List metaKey,
    VaultChange o,
  ) {
    try {
      final m = Rust.vaultOpenMeta(
        metaKey: metaKey,
        vaultId: vaultId,
        objectId: o.id,
        encMeta: o.encMeta!,
      );
      final hash = m.hash;
      return VaultObjectsCompanion.insert(
        id: o.id,
        parent: Value(m.parent),
        name: m.name,
        kind: m.kind,
        size: Value(m.size),
        mtime: m.mtimeMs,
        mime: Value(m.mime),
        hash: Value(
          hash == null ? null : base64Url.encode(hash).replaceAll('=', ''),
        ),
        blobId: Value(o.blobId),
        blobSize: Value(o.size),
        hasThumb: Value(o.hasThumb),
        seq: o.seq,
        createdAt: o.createdAt,
        trashedAt: Value(o.trashedAt),
        encMeta: o.encMeta!,
      );
    } on Object catch (e) {
      debugPrint('[vault] metadata of ${o.id} does not open: $e');
      return null;
    }
  }

  // ---- live updates ---------------------------------------------------------------

  /// Pull now, then follow the WebSocket until [stop]. Reconnects with a
  /// growing pause (up to a minute) when the socket drops.
  Future<void> start() async {
    if (_running) return;
    _running = true;
    unawaited(_safePull());
    await _open();
  }

  Future<void> stop() async {
    _running = false;
    _retry?.cancel();
    _retry = null;
    await _wsSub?.cancel();
    _wsSub = null;
    await _ws?.sink.close();
    _ws = null;
  }

  Future<void> _safePull() async {
    try {
      await pull();
    } on Object catch (e) {
      debugPrint('[vault] pull failed: $e');
    }
  }

  Future<void> _open() async {
    if (!_running) return;
    final vaultId = await _keys.vaultId();
    if (vaultId == null) return;
    try {
      final ws = _connect(await _api.wsUri(vaultId));
      _ws = ws;
      _wsSub = ws.stream.listen(
        (msg) {
          _backoff = 0;
          _onMessage(msg);
        },
        onDone: _reconnect,
        onError: (_) => _reconnect(),
        cancelOnError: true,
      );
    } on Object catch (e) {
      debugPrint('[vault] socket failed: $e');
      _reconnect();
    }
  }

  void _onMessage(Object? msg) {
    if (msg is! String) return;
    try {
      final j = jsonDecode(msg) as Map<String, dynamic>;
      // "seq": the index moved (skip it when this device is already there);
      // "vault": plan or devices changed.
      final seq = (j['seq'] as num?)?.toInt();
      if (j['type'] == 'seq' && seq != null && seq <= _known) return;
      if (j['type'] == 'seq' || j['type'] == 'vault') unawaited(_safePull());
    } on Object {
      // Not ours.
    }
  }

  void _reconnect() {
    if (!_running) return;
    _wsSub = null;
    _ws = null;
    _retry?.cancel();
    final secs = min(60, 1 << min(_backoff++, 6));
    _retry = Timer(Duration(seconds: secs), () async {
      await _safePull();
      await _open();
    });
  }

  @override
  void dispose() {
    unawaited(stop());
    super.dispose();
  }
}
