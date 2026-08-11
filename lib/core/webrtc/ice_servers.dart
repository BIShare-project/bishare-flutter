import 'dart:convert';
import 'dart:io';
import 'dart:math';

import '../constants/cloud.dart';

/// Direct-only fallback when the TURN mint is unreachable — the pre-TURN
/// behaviour, so a failure never blocks a connection attempt.
const stunFallbackIceServers = <Map<String, dynamic>>[
  {'urls': 'stun:stun.cloudflare.com:3478'},
];

List<Map<String, dynamic>>? _cachedIce;
DateTime? _iceExpiresAt;

/// Cached short-lived TURN credentials from GET /api/v1/webrtc/ice (the same
/// source the web client uses). TURN matters even on one Wi-Fi: the browser
/// peer hides its host candidates behind mDNS and many routers refuse NAT
/// hairpinning, so app↔web pairs often need the relay. Refreshed with a
/// 5-minute margin before the server-reported TTL; any failure returns the
/// last-known list or STUN-only — never throws.
Future<List<Map<String, dynamic>>> fetchWebrtcIceServers() async {
  final cached = _cachedIce;
  final expires = _iceExpiresAt;
  if (cached != null && expires != null && DateTime.now().isBefore(expires)) {
    return cached;
  }
  try {
    final client = HttpClient();
    try {
      final req = await client
          .getUrl(Uri.parse('${CloudConfig.apiBase}/api/v1/webrtc/ice'));
      final res = await req.close().timeout(const Duration(seconds: 8));
      final body = await res.transform(utf8.decoder).join();
      final json = jsonDecode(body) as Map<String, dynamic>;
      final data = json['data'] as Map<String, dynamic>?;
      final servers = (data?['iceServers'] as List?)
          ?.whereType<Map<String, dynamic>>()
          .toList();
      if (res.statusCode == 200 && servers != null && servers.isNotEmpty) {
        final ttl = (data?['ttl'] as num?)?.toInt() ?? 3600;
        _cachedIce = servers;
        _iceExpiresAt =
            DateTime.now().add(Duration(seconds: max(300, ttl - 300)));
        return servers;
      }
    } finally {
      client.close(force: true);
    }
  } on Object {
    // fall through to the STUN-only default
  }
  return _cachedIce ?? stunFallbackIceServers;
}
