import 'dart:convert';

import 'package:crypto/crypto.dart';

/// Text this app put on the clipboard as a secret (a Drive recovery phrase):
/// clipboard sync never sends it to other devices, even where the platform
/// has no "sensitive" marker of its own (iOS, Windows, Linux). Only hashes
/// are kept, for a few minutes.
abstract final class ClipboardSecrets {
  static final Map<String, DateTime> _marked = {};
  static const _keep = Duration(minutes: 5);

  static String _hash(String text) =>
      sha256.convert(utf8.encode(text)).toString();

  static void mark(String text) {
    _prune();
    _marked[_hash(text)] = DateTime.now().add(_keep);
  }

  static bool isMarked(String text) {
    _prune();
    return _marked.containsKey(_hash(text));
  }

  static void _prune() {
    final now = DateTime.now();
    _marked.removeWhere((_, until) => until.isBefore(now));
  }
}
