import 'dart:convert';
import 'dart:io';
import 'dart:typed_data';

import 'package:bishare/core/rust/rust_facade.dart';
import 'package:bishare/src/rust/api/vault.dart';
import 'package:crypto/crypto.dart' as crypto;
import 'package:flutter_test/flutter_test.dart';

import 'helpers/rust_test_lib.dart';

/// The vault vectors (test/fixtures/vault_vectors.json) are written by the
/// Rust tests from the same code this bridge calls; the web checks them with
/// its own implementation. This file proves the Dart→Rust bridge reproduces
/// every value a device needs, opens everything the vectors sealed, and
/// refuses what it must refuse. Sealing with a random nonce is proved by
/// round trip; the sealed bytes themselves are pinned in Rust.
void main() {
  final v = jsonDecode(File('test/fixtures/vault_vectors.json').readAsStringSync())
      as Map<String, dynamic>;
  final vaultId = v['vaultId'] as String;
  final vk = _b64u(v['vaultKey'] as String);
  final file = v['file'] as Map<String, dynamic>;
  final dir = v['dir'] as Map<String, dynamic>;
  final keyCopy = v['keyCopy'] as Map<String, dynamic>;
  final device = v['device'] as Map<String, dynamic>;
  final request = v['request'] as Map<String, dynamic>;
  final grant = v['grant'] as Map<String, dynamic>;
  final dedupe = v['dedupe'] as Map<String, dynamic>;
  final compressed = v['compressed'] as Map<String, dynamic>;
  late bool rust;

  setUpAll(() async {
    rust = await initRustForTests();
  });

  test('ids, key check, meta key and thumb key', () {
    if (!rust) return markTestSkipped(rustUnavailableReason);
    expect(Rust.vaultIsVaultId(vaultId), isTrue);
    expect(Rust.vaultIsVaultId(vaultId.toUpperCase()), isFalse);
    expect(Rust.vaultIsObjectId(file['objectId'] as String), isTrue);
    expect(Rust.vaultIsObjectId('short'), isFalse);
    expect(Rust.vaultGenerateObjectId(), hasLength(22));
    expect(Rust.vaultGenerateKey(), hasLength(32));
    expect(Rust.vaultKeyCheck(vk), v['keyCheck']);
    expect(_enc(Rust.vaultMetaKey(vk)), v['metaKey']);
    expect(_enc(Rust.vaultThumbKey(_b64u(file['fileKey'] as String))), file['thumbKey']);
  });

  test('phrase round-trips and rejects a bad checksum', () {
    if (!rust) return markTestSkipped(rustUnavailableReason);
    final phrase = v['phrase'] as String;
    expect(Rust.vaultPhraseFromKey(vk), phrase);
    expect(Rust.vaultKeyFromPhrase(phrase), vk);
    expect(Rust.vaultKeyFromPhrase('  ${phrase.toUpperCase().replaceAll(' ', '   ')}\n'), vk);
    final words = phrase.split(' ');
    expect(() => Rust.vaultKeyFromPhrase([words[1], words[0], ...words.sublist(2)].join(' ')), throwsA(anything));
    expect(() => Rust.vaultKeyFromPhrase(words.sublist(0, 23).join(' ')), throwsA(anything));
    expect(() => Rust.vaultKeyFromPhrase(['zzzz', ...words.sublist(1)].join(' ')), throwsA(anything));
  });

  test('key copy opens and refuses the wrong half, vault or bytes', () {
    if (!rust) return markTestSkipped(rustUnavailableReason);
    final half = _b64u(keyCopy['serverHalf'] as String);
    final blob = _b64u(keyCopy['blob'] as String);
    expect(Rust.vaultOpenKeyCopy(serverHalf: half, vaultId: vaultId, keyCopy: blob), vk);
    final mine = Rust.vaultSealKeyCopy(serverHalf: half, vaultId: vaultId, vaultKey: vk);
    expect(mine, hasLength(65));
    expect(Rust.vaultOpenKeyCopy(serverHalf: half, vaultId: vaultId, keyCopy: mine), vk);
    final otherVault = 'b${vaultId.substring(1)}';
    expect(() => Rust.vaultOpenKeyCopy(serverHalf: half, vaultId: otherVault, keyCopy: blob), throwsA(anything));
    expect(() => Rust.vaultOpenKeyCopy(serverHalf: Uint8List(32), vaultId: vaultId, keyCopy: blob), throwsA(anything));
    final flipped = Uint8List.fromList(blob)..[40] ^= 1;
    expect(() => Rust.vaultOpenKeyCopy(serverHalf: half, vaultId: vaultId, keyCopy: flipped), throwsA(anything));
    final badMagic = Uint8List.fromList(blob)..[0] = 0x58;
    expect(() => Rust.vaultOpenKeyCopy(serverHalf: half, vaultId: vaultId, keyCopy: badMagic), throwsA(anything));
  });

  test('device key, sign-in nonce and signed request match the vectors', () {
    if (!rust) return markTestSkipped(rustUnavailableReason);
    final seed = _b64u(device['seed'] as String);
    final pub = Rust.vaultDevicePublicKey(seed);
    expect(_enc(pub), device['publicKey']);
    expect(Rust.vaultDeviceId(pub), device['deviceId']);
    expect(Rust.vaultSigninNonce(pub), device['signinNonce']);
    final body = utf8.encode(request['body'] as String);
    final method = request['method'] as String;
    final path = request['pathAndQuery'] as String;
    final ts = request['ts'] as int;
    expect(Rust.vaultRequestMessage(method: method, pathAndQuery: path, ts: ts, body: body), request['message']);
    final sig = Rust.vaultSignRequest(seed: seed, method: method, pathAndQuery: path, ts: ts, body: body);
    expect(sig, request['signature']);
    expect(
      Rust.vaultAuthorization(seed: seed, vaultId: vaultId, method: method, pathAndQuery: path, ts: ts, body: body),
      request['authorization'],
    );
    Rust.vaultVerifyRequest(publicKey: pub, method: method, pathAndQuery: path, ts: ts, body: body, signature: sig);
    expect(() => Rust.vaultVerifyRequest(publicKey: pub, method: 'GET', pathAndQuery: path, ts: ts, body: body, signature: sig), throwsA(anything));
    expect(() => Rust.vaultVerifyRequest(publicKey: pub, method: method, pathAndQuery: path, ts: ts + 1, body: body, signature: sig), throwsA(anything));
    expect(() => Rust.vaultVerifyRequest(publicKey: pub, method: method, pathAndQuery: path, ts: ts, body: utf8.encode('{}'), signature: sig), throwsA(anything));
    final other = Rust.vaultDevicePublicKey(Rust.vaultDeviceKeyGenerate());
    expect(() => Rust.vaultVerifyRequest(publicKey: other, method: method, pathAndQuery: path, ts: ts, body: body, signature: sig), throwsA(anything));
  });

  test('file and folder metadata open from the vectors and round-trip', () {
    if (!rust) return markTestSkipped(rustUnavailableReason);
    final kMeta = Rust.vaultMetaKey(vk);
    final fm = file['meta'] as Map<String, dynamic>;
    final opened = Rust.vaultOpenMeta(
      metaKey: kMeta,
      vaultId: vaultId,
      objectId: file['objectId'] as String,
      encMeta: file['encMeta'] as String,
    );
    expect(opened.kind, 'file');
    expect(opened.name, fm['name']);
    expect(opened.parent, fm['parent']);
    expect(opened.mtimeMs, fm['mtimeMs']);
    expect(opened.size, fm['size']);
    expect(opened.mime, fm['mime']);
    expect(_enc(opened.fileKey!), file['fileKey']);
    expect(_enc(opened.hash!), fm['hash']);
    expect(_enc(crypto.sha256.convert(_b64u(file['plaintext'] as String)).bytes), fm['hash']);
    // Sealed here with a fresh nonce, opened again, and refused elsewhere.
    final sealed = Rust.vaultSealMeta(metaKey: kMeta, vaultId: vaultId, objectId: file['objectId'] as String, meta: opened);
    final again = Rust.vaultOpenMeta(metaKey: kMeta, vaultId: vaultId, objectId: file['objectId'] as String, encMeta: sealed);
    expect(again.name, fm['name']);
    expect(again.size, fm['size']);
    expect(() => Rust.vaultOpenMeta(metaKey: kMeta, vaultId: vaultId, objectId: dir['objectId'] as String, encMeta: sealed), throwsA(anything));
    expect(() => Rust.vaultOpenMeta(metaKey: Uint8List(32), vaultId: vaultId, objectId: file['objectId'] as String, encMeta: sealed), throwsA(anything));
    final flipped = Uint8List.fromList(_b64u(file['encMeta'] as String))..[20] ^= 0x80;
    expect(() => Rust.vaultOpenMeta(metaKey: kMeta, vaultId: vaultId, objectId: file['objectId'] as String, encMeta: _enc(flipped)), throwsA(anything));
    // A file without its hash is refused before anything is sealed.
    expect(
      () => Rust.vaultSealMeta(
        metaKey: kMeta,
        vaultId: vaultId,
        objectId: file['objectId'] as String,
        meta: VaultMeta(kind: 'file', name: 'x', parent: null, mtimeMs: 1, size: 1, mime: 'a/b', fileKey: opened.fileKey, hash: null, compression: null),
      ),
      throwsA(anything),
    );
    final dm = dir['meta'] as Map<String, dynamic>;
    final openedDir = Rust.vaultOpenMeta(metaKey: kMeta, vaultId: vaultId, objectId: dir['objectId'] as String, encMeta: dir['encMeta'] as String);
    expect(openedDir.kind, 'dir');
    expect(openedDir.name, dm['name']);
    expect(openedDir.parent, isNull);
    expect(openedDir.mtimeMs, dm['mtimeMs']);
    expect(openedDir.size, isNull);
  });

  test('dedupe key and tag match the vectors', () {
    if (!rust) return markTestSkipped(rustUnavailableReason);
    final k = Rust.vaultDedupeKey(vk);
    expect(_enc(k), dedupe['dedupeKey']);
    expect(Rust.vaultDedupeTag(dedupeKey: k, plaintextHash: _b64u(dedupe['hash'] as String)), dedupe['tag']);
    expect(Rust.vaultDedupeTag(dedupeKey: k, plaintextHash: Uint8List(32)), isNot(dedupe['tag']));
    expect(Rust.vaultDedupeTag(dedupeKey: Rust.vaultDedupeKey(Uint8List(32)), plaintextHash: _b64u(dedupe['hash'] as String)), isNot(dedupe['tag']));
  });

  test('compressed file: z in the metadata, bytes inflate to the sealed size', () {
    if (!rust) return markTestSkipped(rustUnavailableReason);
    final kMeta = Rust.vaultMetaKey(vk);
    final m = Rust.vaultOpenMeta(metaKey: kMeta, vaultId: vaultId, objectId: compressed['objectId'] as String, encMeta: compressed['encMeta'] as String);
    expect(m.compression, 'deflate');
    final plain = _b64u(compressed['plaintext'] as String);
    expect(m.size, plain.length);
    final deflated = _b64u(compressed['deflated'] as String);
    expect(Rust.vaultInflateRaw(deflated, m.size!), plain);
    expect(_enc(crypto.sha256.convert(plain).bytes), _enc(m.hash!));
    // Dart's own raw inflater reads the same stream (any valid DEFLATE is allowed).
    expect(ZLibDecoder(raw: true).convert(deflated), plain);
    expect(Rust.vaultInflateRaw(Rust.vaultDeflateRaw(plain), plain.length), plain);
    expect(Rust.vaultInflateRaw(ZLibEncoder(raw: true).convert(plain), plain.length), plain);
    expect(() => Rust.vaultInflateRaw(deflated, plain.length - 1), throwsA(anything));
    // The flag survives a seal and open; an unknown one is refused before sealing.
    final sealed = Rust.vaultSealMeta(metaKey: kMeta, vaultId: vaultId, objectId: compressed['objectId'] as String, meta: m);
    expect(Rust.vaultOpenMeta(metaKey: kMeta, vaultId: vaultId, objectId: compressed['objectId'] as String, encMeta: sealed).compression, 'deflate');
    expect(
      () => Rust.vaultSealMeta(
        metaKey: kMeta,
        vaultId: vaultId,
        objectId: compressed['objectId'] as String,
        meta: VaultMeta(kind: 'file', name: 'x', parent: null, mtimeMs: 1, size: 1, mime: 'a/b', fileKey: m.fileKey, hash: m.hash, compression: 'zstd'),
      ),
      throwsA(anything),
    );
  });

  test('thumbnail opens from the vectors and round-trips', () {
    if (!rust) return markTestSkipped(rustUnavailableReason);
    final fileKey = _b64u(file['fileKey'] as String);
    final objectId = file['objectId'] as String;
    expect(
      Rust.vaultOpenThumbnail(fileKey: fileKey, vaultId: vaultId, objectId: objectId, sealed: _b64u(file['encThumbnail'] as String)),
      _b64u(file['thumbnail'] as String),
    );
    final sealed = Rust.vaultSealThumbnail(fileKey: fileKey, vaultId: vaultId, objectId: objectId, jpeg: [1, 2, 3]);
    expect(Rust.vaultOpenThumbnail(fileKey: fileKey, vaultId: vaultId, objectId: objectId, sealed: sealed), [1, 2, 3]);
    expect(() => Rust.vaultOpenThumbnail(fileKey: fileKey, vaultId: vaultId, objectId: dir['objectId'] as String, sealed: sealed), throwsA(anything));
  });

  test('grant opens from the vectors and a fresh one round-trips', () {
    if (!rust) return markTestSkipped(rustUnavailableReason);
    final keyCheck = v['keyCheck'] as String;
    expect(
      Rust.vaultAcceptGrant(
        vaultId: vaultId,
        mineSecret: _b64u(grant['newPriv'] as String),
        granterPub: _b64u(grant['granterPub'] as String),
        boxed: _b64u(grant['box'] as String),
        expectedKeyCheck: keyCheck,
      ),
      vk,
    );
    final newKey = Rust.vaultGrantKeyGenerate();
    final granter = Rust.vaultGrantKeyGenerate();
    expect(newKey.secret, hasLength(32));
    expect(newKey.public, hasLength(32));
    final boxed = Rust.vaultGrant(vaultKey: vk, vaultId: vaultId, mineSecret: granter.secret, newPub: newKey.public);
    expect(Rust.vaultAcceptGrant(vaultId: vaultId, mineSecret: newKey.secret, granterPub: granter.public, boxed: boxed, expectedKeyCheck: keyCheck), vk);
    expect(
      () => Rust.vaultAcceptGrant(vaultId: vaultId, mineSecret: newKey.secret, granterPub: granter.public, boxed: boxed, expectedKeyCheck: Rust.vaultKeyCheck(Uint8List(32))),
      throwsA(anything),
    );
    final stranger = Rust.vaultGrantKeyGenerate();
    expect(
      () => Rust.vaultAcceptGrant(vaultId: vaultId, mineSecret: stranger.secret, granterPub: granter.public, boxed: boxed, expectedKeyCheck: keyCheck),
      throwsA(anything),
    );
    expect(() => Rust.vaultGrant(vaultKey: vk, vaultId: vaultId, mineSecret: granter.secret, newPub: Uint8List(32)), throwsA(anything));
  });
}

Uint8List _b64u(String s) =>
    Uint8List.fromList(base64Url.decode(s.padRight(s.length + (4 - s.length % 4) % 4, '=')));

String _enc(List<int> bytes) => base64Url.encode(bytes).replaceAll('=', '');
