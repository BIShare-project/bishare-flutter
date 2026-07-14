import 'dart:async';

import 'package:app_links/app_links.dart';
import 'package:flutter/foundation.dart';

import 'deep_link.dart';

/// Bridges incoming OS links (custom schemes + universal / app links) and QR
/// scans into a single stream of [DeepLinkAction]s. The app-root handler
/// (MainShell) subscribes and dispatches. Subscribe BEFORE calling [start] so
/// the cold-start initial link isn't missed.
class DeepLinkService {
  DeepLinkService();

  final AppLinks _appLinks = AppLinks();
  final StreamController<DeepLinkAction> _controller =
      StreamController<DeepLinkAction>.broadcast();
  StreamSubscription<Uri>? _sub;
  bool _started = false;

  /// Last payload + when it was dispatched — used to drop the duplicate that
  /// iOS delivers on BOTH `uriLinkStream` and `getInitialLink()` at cold start
  /// (which otherwise fires a one-time download twice → the loser's 410 deletes
  /// the winner's file → "download failed" on iOS only).
  String? _lastPayload;
  DateTime? _lastAt;

  Stream<DeepLinkAction> get actions => _controller.stream;

  /// Begin listening for links + replay the launch link (if any).
  Future<void> start() async {
    if (_started) return;
    _started = true;

    _sub = _appLinks.uriLinkStream.listen(
      (uri) {
        debugPrint('Deep link received: $uri');
        _dispatch(uri.toString());
      },
      onError: (Object error) {
        debugPrint('Deep link stream error: $error');
      },
    );

    try {
      final initial = await _appLinks.getInitialLink();
      if (initial != null) {
        debugPrint('Initial deep link: $initial');
        _dispatch(initial.toString());
      }
    } on Object catch (e) {
      debugPrint('Error getting initial link: $e');
      // no launch link
    }
  }

  /// Feed a raw QR-scanner payload through the same dispatch path.
  void submit(String raw) => _dispatch(raw);

  /// Dispatch a manually-typed bare code. Unlike [submit] this bypasses
  /// [DeepLink.parse] — a short code isn't a valid link — and resolves at
  /// receive time (stored transfer first, then a live stream). See
  /// [AmbiguousCodeLink].
  void submitCode(String code) {
    final normalized = code.replaceAll(RegExp(r'[-/\s]'), '').toUpperCase();
    if (normalized.isEmpty) return;
    _controller.add(AmbiguousCodeLink(normalized));
  }

  void _dispatch(String payload) {
    final now = DateTime.now();
    // Drop an identical payload seen within a short window (the cold-start
    // double-delivery, or an accidental double scan/tap).
    if (_lastPayload == payload &&
        _lastAt != null &&
        now.difference(_lastAt!) < const Duration(seconds: 3)) {
      return;
    }
    _lastPayload = payload;
    _lastAt = now;
    final action = DeepLink.parse(payload);
    if (action != null) _controller.add(action);
  }

  Future<void> dispose() async {
    await _sub?.cancel();
    await _controller.close();
  }
}
