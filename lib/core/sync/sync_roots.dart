/// Portable sync-root paths (Tahap 4).
///
/// A pair's root must survive what absolute paths don't: on iOS the app's data
/// container lives at `/var/mobile/Containers/Data/Application/<UUID>/…` and
/// the UUID CHANGES on every reinstall/App-Store update (the files are
/// migrated, the old path dies). A stored absolute container path therefore
/// breaks every in-container pair on update. Roots are stored PORTABLE instead:
///
///   `@save/<rel>`  — under the received-files save location (live setting)
///   `@docs/<rel>`  — under the app documents directory
///   anything else  — a user-picked external folder, kept absolute
///
/// [resolve] also auto-heals legacy rows that stored a container-absolute path:
/// a path matching the iOS container-Documents shape is re-based onto the
/// CURRENT documents dir, so pairs created before this scheme start working
/// again after an update instead of 403-ing forever.
library;

class SyncRootResolver {
  SyncRootResolver({
    required String Function() saveDirPath,
    required String Function() docsDirPath,
  })  : _saveDir = saveDirPath,
        _docsDir = docsDirPath;

  final String Function() _saveDir;
  final String Function() _docsDir;

  static const String savePrefix = '@save/';
  static const String docsPrefix = '@docs/';

  /// The iOS data-container Documents shape (simulator uses /private/var too).
  static final RegExp _iosContainerDocs = RegExp(
    r'^/(?:private/)?var/mobile/Containers/Data/Application/[^/]+/Documents/(.+)$',
  );

  /// Store-form of [absolute]: portable when under a relocatable base,
  /// untouched otherwise.
  String toPortable(String absolute) {
    final save = _saveDir();
    if (save.isNotEmpty && _isUnder(absolute, save)) {
      return '$savePrefix${_relTo(absolute, save)}';
    }
    final docs = _docsDir();
    if (docs.isNotEmpty && _isUnder(absolute, docs)) {
      return '$docsPrefix${_relTo(absolute, docs)}';
    }
    return absolute;
  }

  /// Filesystem path of a stored root (portable, legacy-container, or plain).
  String resolve(String stored) {
    if (stored.startsWith(savePrefix)) {
      return _join(_saveDir(), stored.substring(savePrefix.length));
    }
    if (stored.startsWith(docsPrefix)) {
      return _join(_docsDir(), stored.substring(docsPrefix.length));
    }
    // Legacy absolute container path from before the portable scheme — or from
    // a previous install: re-base onto the current documents dir (iOS migrates
    // the files; only the UUID path died).
    final legacy = _iosContainerDocs.firstMatch(stored);
    if (legacy != null) {
      final rebased = _join(_docsDir(), legacy.group(1)!);
      if (rebased != stored) return rebased;
    }
    return stored;
  }

  static bool _isUnder(String path, String base) {
    final b = base.endsWith('/') ? base : '$base/';
    return path == base || path.startsWith(b);
  }

  static String _relTo(String path, String base) =>
      path == base ? '' : path.substring(base.length + (base.endsWith('/') ? 0 : 1));

  static String _join(String base, String rel) {
    if (rel.isEmpty) return base;
    final b = base.endsWith('/') ? base.substring(0, base.length - 1) : base;
    return '$b/$rel';
  }
}
