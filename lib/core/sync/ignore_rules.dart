/// Ignore matching for a sync pair (§8.3). A practical gitignore subset:
/// `*` and `?` wildcards (never crossing `/`), a leading `/` to anchor at the
/// root, a trailing `/` to match directories only, and any-level matching for
/// patterns without a slash. NOT supported in v1 (documented non-goals): `**`,
/// `!` negation, and character classes — enough for the built-in defaults and
/// typical `.bishareignore` files, and honest about the rest.
///
/// A path is ignored if it matches a pattern OR any of its ancestor directories
/// does (subtree prune) — so `.bishare-trash/` drops the whole folder.
library;

class _Pattern {
  _Pattern(this.regex, {required this.anchored, required this.dirOnly, required this.hasSlash});
  final RegExp regex;
  final bool anchored;
  final bool dirOnly;
  final bool hasSlash;
}

class IgnoreRules {
  IgnoreRules._(this._patterns);

  final List<_Pattern> _patterns;

  /// Built-in patterns that are always active and cannot be disabled (§8.3):
  /// OS cruft, editor temp/lock files, our own trash + conflict copies (so a
  /// conflict copy is never itself synced back).
  static const List<String> builtinDefaults = [
    '.DS_Store',
    'Thumbs.db',
    'desktop.ini',
    '*.tmp',
    '*.part',
    r'~$*',
    '.bishare-trash/',
    '*.sync-conflict-*',
  ];

  /// The defaults only. Use [withUserPatterns] to layer a `.bishareignore`.
  factory IgnoreRules.defaults() => IgnoreRules._(_compileAll(builtinDefaults));

  /// Defaults plus the lines of a `.bishareignore` (blank lines and `#`
  /// comments skipped). User patterns can only ADD ignores in v1 (no `!`).
  factory IgnoreRules.withUserPatterns(Iterable<String> lines) {
    final user = lines
        .map((l) => l.trim())
        .where((l) => l.isNotEmpty && !l.startsWith('#'))
        // '!' negation is unsupported (v1); drop the line rather than mis-honor it.
        .where((l) => !l.startsWith('!'));
    return IgnoreRules._(_compileAll([...builtinDefaults, ...user]));
  }

  static List<_Pattern> _compileAll(Iterable<String> globs) =>
      globs.map(_compile).whereType<_Pattern>().toList(growable: false);

  static _Pattern? _compile(String raw) {
    var glob = raw.trim();
    if (glob.isEmpty) return null;
    final anchored = glob.startsWith('/');
    if (anchored) glob = glob.substring(1);
    final dirOnly = glob.endsWith('/');
    if (dirOnly) glob = glob.substring(0, glob.length - 1);
    if (glob.isEmpty) return null;
    final hasSlash = glob.contains('/');
    return _Pattern(
      RegExp(_globToRegex(glob)),
      anchored: anchored,
      dirOnly: dirOnly,
      hasSlash: hasSlash,
    );
  }

  static String _globToRegex(String glob) {
    final sb = StringBuffer('^');
    for (final c in glob.split('')) {
      switch (c) {
        case '*':
          sb.write('[^/]*'); // single star never crosses a path separator
        case '?':
          sb.write('[^/]');
        case '.':
        case '(':
        case ')':
        case '[':
        case ']':
        case '{':
        case '}':
        case '+':
        case '^':
        case r'$':
        case '|':
        case r'\':
          sb.write('\\$c');
        default:
          sb.write(c);
      }
    }
    return (sb..write(r'$')).toString();
  }

  /// Whether [relPath] (relative to the pair root, any separator) is ignored.
  /// Pass [isDir] for directories so directory-only patterns apply; ancestors
  /// are always treated as directories (subtree prune).
  bool isIgnored(String relPath, {bool isDir = false}) {
    final norm = relPath.replaceAll('\\', '/').replaceAll(RegExp('^/+|/+\$'), '');
    if (norm.isEmpty) return false;
    final segs = norm.split('/');
    for (var i = 0; i < segs.length; i++) {
      final isLast = i == segs.length - 1;
      final prefix = segs.sublist(0, i + 1).join('/');
      // Every ancestor is a directory; only the final segment's dir-ness is
      // caller-supplied.
      if (_matches(prefix, segs[i], isLast ? isDir : true)) return true;
    }
    return false;
  }

  bool _matches(String path, String basename, bool isDir) {
    for (final p in _patterns) {
      if (p.dirOnly && !isDir) continue;
      final target = (p.anchored || p.hasSlash) ? path : basename;
      if (p.regex.hasMatch(target)) return true;
    }
    return false;
  }
}
