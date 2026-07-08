import 'dart:async';
import 'dart:convert';
import 'dart:io';

import 'package:flutter/services.dart';

import '../../../core/constants/protocol.dart';
import '../../../core/identity/device_identity.dart';
import '../../discovery/data/discovery_service.dart';

/// Universal-clipboard-style sync over UDP (opt-in). When enabled, plain-text
/// clipboard changes are broadcast to discovered peers, and incoming clipboards
/// replace the local one. Uses [BISharePort.quic] (58318) — QUIC is a stub in
/// this client so the port is free, matching native.
class ClipboardService {
  ClipboardService(this._identity, this._discovery);

  final DeviceIdentity _identity;
  final DiscoveryService _discovery;

  RawDatagramSocket? _socket;
  Timer? _poll;
  String? _lastText;
  bool _enabled = false;

  /// Called on an incoming clipboard: (senderAlias, text).
  void Function(String senderAlias, String text)? onReceived;

  bool get isEnabled => _enabled;

  Future<void> setEnabled(bool on) async {
    if (on == _enabled) return;
    if (on) {
      await _start();
    } else {
      _stop();
    }
  }

  Future<void> _start() async {
    try {
      _socket = await RawDatagramSocket.bind(
        InternetAddress.anyIPv4,
        BISharePort.quic,
        reuseAddress: true,
      );
      _socket!
        ..broadcastEnabled = true
        ..listen(_onData);
      // Seed with the current clipboard so we don't broadcast pre-existing text.
      _lastText = (await Clipboard.getData(Clipboard.kTextPlain))?.text;
      _poll = Timer.periodic(
        const Duration(milliseconds: 1500),
        (_) => _pollClipboard(),
      );
      _enabled = true;
    } on Object {
      _enabled = false;
      _stop();
    }
  }

  void _stop() {
    _enabled = false;
    _poll?.cancel();
    _poll = null;
    _socket?.close();
    _socket = null;
  }

  Future<void> _pollClipboard() async {
    final text = (await Clipboard.getData(Clipboard.kTextPlain))?.text;
    if (text == null || text.isEmpty || text == _lastText) return;
    _lastText = text;
    _broadcast(text);
  }

  void _broadcast(String text) {
    final socket = _socket;
    if (socket == null) return;
    final data = utf8.encode(
      jsonEncode({
        'type': 'clipboard',
        'text': text,
        'sender': _identity.fingerprint,
        'alias': _identity.alias,
      }),
    );
    for (final d in _discovery.current) {
      try {
        socket.send(data, InternetAddress(d.host), BISharePort.quic);
      } on Object {
        // unreachable host — skip
      }
    }
  }

  void _onData(RawSocketEvent event) {
    if (event != RawSocketEvent.read) return;
    final dg = _socket?.receive();
    if (dg == null) return;
    try {
      final map = jsonDecode(utf8.decode(dg.data)) as Map<String, dynamic>;
      if (map['type'] != 'clipboard') return;
      if (map['sender'] == _identity.fingerprint) return; // ignore our own
      final text = map['text'] as String? ?? '';
      if (text.isEmpty) return;
      _lastText = text; // don't echo it straight back
      Clipboard.setData(ClipboardData(text: text));
      onReceived?.call(map['alias'] as String? ?? 'A device', text);
    } on Object {
      // malformed datagram — ignore
    }
  }

  Future<void> dispose() async {
    _stop();
  }
}
