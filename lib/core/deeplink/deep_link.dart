import '../constants/cloud.dart';
import '../constants/protocol.dart';

/// A parsed BIShare link/QR payload. The dispatcher ([DeepLinkService] +
/// the app-root handler) turns one of these into a concrete action.
sealed class DeepLinkAction {
  const DeepLinkAction();
}

/// `https://bishare.app/transfer/<code>` — download a 24h one-time cloud
/// transfer by its 6-char code.
class CloudTransferLink extends DeepLinkAction {
  const CloudTransferLink(this.code);
  final String code;
}

/// `https://bishare.app/share/<token>` — download an authenticated user
/// share-link (follows the presigned URL the server returns).
class CloudShareLink extends DeepLinkAction {
  const CloudShareLink(this.token);
  final String token;
}

/// A direct LAN instant-share URL — `bishare://download?host&port&token`, or a
/// raw `http://host:port/api/v1/instant?token=…` payload. Downloaded in place.
class LocalInstantLink extends DeepLinkAction {
  const LocalInstantLink(this.url);
  final Uri url;
}

/// `bishare-stream://<code>` / `bishare-remote://<code>` — receive a live
/// stream-relayed transfer (6-char code).
class StreamReceiveLink extends DeepLinkAction {
  const StreamReceiveLink(this.code);
  final String code;
}

/// A bare code typed by hand (no scheme/host to say which kind it is). Ambiguous
/// between a stored 24h cloud transfer and a live stream session, so it's
/// resolved at receive time: try the stored transfer first, then a live stream
/// with the same code. Produced only by manual entry — never by [DeepLink.parse]
/// — so the QR camera's accept-filter never fires on short arbitrary text.
class AmbiguousCodeLink extends DeepLinkAction {
  const AmbiguousCodeLink(this.code);
  final String code;
}

/// `https://bishare.app/request/<code>` — a web file-request page; opened in
/// the system browser.
class OpenExternalLink extends DeepLinkAction {
  const OpenExternalLink(this.url);
  final Uri url;
}

/// `bishare://share` — the OS share-sheet handed us files; re-scan the inbox.
class RescanSharedLink extends DeepLinkAction {
  const RescanSharedLink();
}

/// Parses incoming URIs and raw QR strings into a [DeepLinkAction]. Grounded to
/// the native iOS `handleWebURL` / `handleDeepLink` / QR-scanner dispatch, so
/// links produced by any BIShare client resolve identically.
class DeepLink {
  DeepLink._();

  /// The QR-scanner accept filter: only strings that look like a BIShare link
  /// are acted on (mirrors the native scanner's `metadataOutput` gate).
  static bool looksLikeBiShare(String raw) => parse(raw) != null;

  static DeepLinkAction? parse(String raw) {
    final input = raw.trim();
    if (input.isEmpty) return null;

    // Raw local instant-share URL (already an http link to a device server).
    if (input.contains(BIShareApi.instant)) {
      final u = Uri.tryParse(input);
      if (u != null && u.hasScheme) return LocalInstantLink(u);
    }

    // Scheme-less web payloads from a QR (e.g. "bishare.app/transfer/AB2C3D").
    final hostIdx = input.indexOf('${CloudConfig.webHost}/');
    if (hostIdx >= 0 && !input.contains('://')) {
      return _fromWebPath(input.substring(hostIdx + CloudConfig.webHost.length));
    }

    final uri = Uri.tryParse(input);
    if (uri == null) return null;

    switch (uri.scheme) {
      case CloudConfig.schemeRemote:
      case CloudConfig.schemeStream:
        final code = _code('${uri.host}${uri.path}');
        return code.isEmpty ? null : StreamReceiveLink(code);

      case CloudConfig.scheme: // bishare://
        if (uri.host == 'share') return const RescanSharedLink();
        if (uri.host == 'download') {
          final host = uri.queryParameters['host'];
          final port = uri.queryParameters['port'] ?? '${BISharePort.main}';
          final token = uri.queryParameters['token'];
          if (host == null || token == null) return null;
          return LocalInstantLink(
            Uri.parse('http://$host:$port/api/v1/instant?token=$token'),
          );
        }
        return null;

      case 'http':
      case 'https':
        if (_isWebHost(uri.host)) return _fromWebPath(uri.path);
        // Any other http(s) link that is a device instant URL.
        if (uri.path.contains(BIShareApi.instant)) return LocalInstantLink(uri);
        return null;
    }
    return null;
  }

  static DeepLinkAction? _fromWebPath(String path) {
    final segs = path.split('/').where((s) => s.isNotEmpty).toList();
    if (segs.isEmpty) return null;
    switch (segs[0]) {
      case 'transfer':
        if (segs.length >= 2) return CloudTransferLink(_code(segs[1]));
        return null;
      case 'share':
        if (segs.length >= 2) return CloudShareLink(segs[1]);
        return null;
      case 'request':
        return OpenExternalLink(Uri.parse('${CloudConfig.webBase}/$path'));
    }
    return null;
  }

  static bool _isWebHost(String host) =>
      host == CloudConfig.webHost || host.endsWith('.${CloudConfig.webHost}');

  /// Normalise a code: strip dashes/slashes, uppercase.
  static String _code(String s) =>
      s.replaceAll(RegExp(r'[-/]'), '').toUpperCase();
}
