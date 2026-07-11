import 'dart:async';
import 'dart:convert';

import 'package:flutter/foundation.dart';

import '../../../core/identity/device_identity.dart';
import '../../../core/relay/relay_channel.dart';

/// Cloud path for Universal Clipboard (plan §1 phase 3) — forwards small
/// clipboard payloads between this user's devices when they are NOT on the
/// same LAN. Client-side only in this wave; the LAN flow never depends on it
/// (every call here is fire-and-forget best-effort), and it is OFF by default
/// (Settings → "Sync via cloud").
///
/// ## Expected backend contract (deferred — for the Workers implementation)
///
/// * **Transport**: the shared [RelayChannelClient] WebSocket at
///   `CloudConfig.wsBase + /api/v1/channel/{channelId}/ws`
///   ([RelayChannelClient.channelWs]), `sync` lane. Envelope:
///   `{"channel":"sync","payload":{…}}`.
/// * **Channel id**: ONE channel per signed-in account, so all of a user's
///   devices meet on it. Accounts don't exist in the app yet, so until they
///   ship the client uses a per-device placeholder (`clip-<fingerprint>`)
///   — the toggle and plumbing work end-to-end, pairing arrives with the
///   backend.
/// * **Server behavior**: fan out each payload verbatim to every OTHER socket
///   on the channel (sender excluded or filtered client-side via `sender`),
///   no persistence required. Payloads are ≤ [maxPayloadBytes] (1 MB); the
///   server may drop larger ones.
/// * **Payload**: the wire `ClipboardPayload` JSON
///   (`{type:'clipboard', text, sender, alias, kind?, mime?, size?}`) plus a
///   client extension `data` — base64 image bytes for `kind == 'image'`,
///   because the LAN pull-token is meaningless across networks. Larger images
///   stay LAN-only in this phase (plan: "payload biner besar tetap LAN-only").
class ClipboardRelay {
  ClipboardRelay(this._clientFactory, this._identity);

  /// Resolved lazily so registering this class doesn't wake the (deliberately
  /// dormant) relay client — no Dio, no socket until the toggle goes ON.
  final RelayChannelClient Function() _clientFactory;
  final DeviceIdentity _identity;

  /// Relay forwards at most this much (the backend contract's cap).
  static const int maxPayloadBytes = 1024 * 1024;

  RelayChannelClient? _client;
  StreamSubscription<Map<String, dynamic>>? _sub;
  bool _enabled = false;

  /// Incoming clipboard payloads from the user's other devices (already
  /// filtered: `type == 'clipboard'`, not our own). Wired to
  /// `ClipboardService.applyRelayPayload`.
  void Function(Map<String, dynamic> payload)? onPayload;

  bool get isEnabled => _enabled;

  /// Connect/disconnect the relay channel. NOTE: [RelayChannelClient] is the
  /// app-wide shared relay socket; today the clipboard is its only user, so
  /// closing it here is safe — revisit when another feature attaches a lane.
  void setEnabled(bool on) {
    if (on == _enabled) return;
    _enabled = on;
    if (on) {
      final client = _client ??= _clientFactory();
      _sub ??= client.sync.incoming.listen(_onIncoming);
      client.connect('clip-${_identity.fingerprint}');
    } else {
      unawaited(_sub?.cancel());
      _sub = null;
      final client = _client;
      if (client != null) unawaited(client.close());
    }
  }

  /// Forward a clipboard payload to the user's other devices. Best-effort:
  /// dropped when disabled, disconnected, or larger than [maxPayloadBytes].
  void forward(Map<String, dynamic> payload) {
    if (!_enabled) return;
    final client = _client;
    if (client == null || client.state != RelayConnectionState.connected) {
      return;
    }
    // The 1 MB cap is on the encoded payload (text + any inline image data).
    if (utf8.encode(jsonEncode(payload)).length > maxPayloadBytes) return;
    try {
      client.sync.send(payload);
    } on Object catch (e) {
      debugPrint('[ClipboardRelay] forward failed: $e'); // never block LAN
    }
  }

  void _onIncoming(Map<String, dynamic> payload) {
    if (!_enabled) return;
    if (payload['type'] != 'clipboard') return;
    if (payload['sender'] == _identity.fingerprint) return; // our own echo
    onPayload?.call(payload);
  }

  Future<void> dispose() async {
    setEnabled(false);
  }
}
