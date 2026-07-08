import 'dart:io';

/// Resolves this device's own LAN IPv4 address to self-report in discovery and
/// `/api/v1/info`. This is the cross-platform port of the native `localIPAddress()`
/// and the crux of the discovery fix: peers must reach us at a routable IPv4, never
/// a loopback or link-local (169.254.x / AWDL IPv6) address.
class LocalIp {
  LocalIp._();

  /// Preferred physical interface names, in priority order.
  static const List<String> _preferred = [
    'en0',
    'en1',
    'wlan0',
    'eth0',
    'Wi-Fi',
    'Ethernet',
  ];

  /// Returns the best-guess LAN IPv4, or `127.0.0.1` if none is found.
  static Future<String> resolve() async {
    final candidates = <_Candidate>[];
    final interfaces = await NetworkInterface.list(
      type: InternetAddressType.IPv4,
      includeLoopback: false,
      includeLinkLocal: false,
    );
    for (final iface in interfaces) {
      for (final addr in iface.addresses) {
        if (_isUsableIPv4(addr.address)) {
          candidates.add(_Candidate(iface.name, addr.address));
        }
      }
    }
    if (candidates.isEmpty) return '127.0.0.1';

    // Prefer a known physical interface, then a private (192.168/10/172.16-31)
    // address, then anything usable.
    candidates.sort((a, b) {
      final ap = _priority(a);
      final bp = _priority(b);
      return ap.compareTo(bp);
    });
    return candidates.first.ip;
  }

  static int _priority(_Candidate c) {
    var score = 100;
    final idx = _preferred.indexOf(c.name);
    if (idx >= 0) score -= (10 - idx);
    if (_isPrivate(c.ip)) score -= 20;
    return score;
  }

  static bool _isUsableIPv4(String ip) {
    if (ip.isEmpty || ip.contains(':')) return false;
    if (ip == '127.0.0.1' || ip == '0.0.0.0') return false;
    if (ip.startsWith('169.254.')) return false; // link-local
    final parts = ip.split('.');
    if (parts.length != 4) return false;
    return parts.every((p) {
      final n = int.tryParse(p);
      return n != null && n >= 0 && n <= 255;
    });
  }

  static bool _isPrivate(String ip) =>
      ip.startsWith('192.168.') ||
      ip.startsWith('10.') ||
      RegExp(r'^172\.(1[6-9]|2\d|3[01])\.').hasMatch(ip);
}

class _Candidate {
  const _Candidate(this.name, this.ip);
  final String name;
  final String ip;
}
