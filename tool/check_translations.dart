// Translation completeness checker for BIShare.
//
//   dart run tool/check_translations.dart
//
// Compares every assets/translations/<locale>.json against en.json (the source
// of truth) and reports missing / extra keys and a completeness percentage.
// Exits non-zero if any locale is missing keys, so CI can guard translations.
//
// Contributors: see docs/TRANSLATIONS.md for how to add or complete a language.
import 'dart:convert';
import 'dart:io';

const source = 'en';
const dir = 'assets/translations';

/// Flatten a nested JSON map into dotted keys: {a:{b:1}} -> {"a.b"}.
Set<String> flatten(Map<String, dynamic> m, [String prefix = '']) {
  final out = <String>{};
  m.forEach((k, v) {
    final key = prefix.isEmpty ? k : '$prefix.$k';
    if (v is Map<String, dynamic>) {
      out.addAll(flatten(v, key));
    } else {
      out.add(key);
    }
  });
  return out;
}

Map<String, dynamic> load(String locale) =>
    jsonDecode(File('$dir/$locale.json').readAsStringSync()) as Map<String, dynamic>;

void main() {
  final srcKeys = flatten(load(source));
  final total = srcKeys.length;

  final files = Directory(dir)
      .listSync()
      .whereType<File>()
      .where((f) => f.path.endsWith('.json'))
      .map((f) => f.uri.pathSegments.last.replaceAll('.json', ''))
      .where((l) => l != source)
      .toList()
    ..sort();

  stdout.writeln('Source: $source.json ($total keys)\n');
  stdout.writeln('${'Locale'.padRight(12)}${'Done'.padRight(10)}%     Missing  Extra');
  stdout.writeln('${'-' * 12}${'-' * 10}${'-' * 6}${'-' * 8}${'-' * 5}');

  var failed = false;
  for (final locale in files) {
    final keys = flatten(load(locale));
    final missing = srcKeys.difference(keys);
    final extra = keys.difference(srcKeys);
    final done = total - missing.length;
    final pct = (done / total * 100);
    final ok = missing.isEmpty && extra.isEmpty;
    if (missing.isNotEmpty) failed = true;

    final mark = ok ? '✅' : (missing.isNotEmpty ? '❌' : '⚠️');
    stdout.writeln(
      '${locale.padRight(12)}${'$done/$total'.padRight(10)}'
      '${pct.toStringAsFixed(0).padRight(6)}${missing.length.toString().padRight(8)}${extra.length}  $mark',
    );
    if (missing.isNotEmpty) {
      final show = missing.take(8).join(', ');
      stdout.writeln('    missing: $show${missing.length > 8 ? ', …(+${missing.length - 8})' : ''}');
    }
    if (extra.isNotEmpty) {
      stdout.writeln('    extra (not in en): ${extra.take(8).join(', ')}');
    }
  }

  stdout.writeln('');
  if (failed) {
    stdout.writeln('❌ Some locales are missing keys. Add them (values may be English placeholders) to reach 100%.');
    exit(1);
  }
  stdout.writeln('✅ All locales cover every source key.');
}
