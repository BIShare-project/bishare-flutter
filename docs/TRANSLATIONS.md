# Translating BIShare 🌍

Help make BIShare speak your language! Translations are one of the easiest and
most valuable ways to contribute — **no app-building required**, just a text
editor. English (`en`) is the source of truth; every other language mirrors its
keys.

## Current languages

Run `dart run tool/check_translations.dart` any time to see live status.

| Code | Language | Status |
|------|----------|:------:|
| `en` | English (source) | ✅ 100% |
| `id` | Bahasa Indonesia | ✅ 100% |
| `ar` | العربية (Arabic, RTL) | ✅ 100% |
| `de` | Deutsch | ✅ 100% |
| `es` | Español | ✅ 100% |
| `fr` | Français | ✅ 100% |
| `hi` | हिन्दी | ✅ 100% |
| `ja` | 日本語 | ✅ 100% |
| `ko` | 한국어 | ✅ 100% |
| `pt-BR` | Português (Brasil) | ✅ 100% |
| `ru` | Русский | ✅ 100% |
| `zh-Hans` | 简体中文 | ✅ 100% |
| `zh-Hant` | 繁體中文 | ✅ 100% |

**Want a language that isn't here?** Add it — see below. Some languages the
community would love: Italian, Portuguese (Portugal), Turkish, Dutch, Polish,
Ukrainian, Vietnamese, Thai, Czech, Swedish, Danish, Norwegian, Finnish, Greek,
Hebrew, Romanian, Hungarian, Filipino, Malay, Persian (Farsi), Bengali… but any
language is welcome.

## Add a new language

It's **3 small edits** (using `it` / Italian as an example):

1. **Create the translation file** — copy `assets/translations/en.json` to
   `assets/translations/it.json` and translate the **values** (keep every key
   exactly as-is). For a region/script variant, use a hyphen in the filename,
   e.g. `pt-PT.json`, `zh-Hant.json`.

2. **Register the locale** in `lib/core/l10n/app_locales.dart` → add it to
   `appLocales`:
   ```dart
   Locale('it'),                 // or: Locale('pt', 'PT') for a region variant
   ```

3. **Add its native name** in the same file → `localeDisplayNames`:
   ```dart
   'it': 'Italiano',             // key is the locale string: 'it' or 'pt_PT'
   ```

## Fix or improve an existing language

Just edit the values in `assets/translations/<code>.json`. Spotted an awkward
phrase or a typo? A one-line PR is very welcome.

## Rules (please follow)

- **Never change the keys** — only translate the string **values**.
- **Keep placeholders verbatim**: `{name}`, `{count}`, `{max}`, `%s`, etc. must
  stay exactly as in English (they're filled in at runtime).
- **Keep product names** untranslated: BIShare, AirDrop, QR Beam, Wi-Fi.
- Aim for **natural, native phrasing** over literal word-for-word translation.
- Match tone: short, friendly, and clear (these are buttons, titles, and hints).

## Verify before you open a PR

```bash
dart run tool/check_translations.dart
```

This prints a completeness table and **fails if any key is missing** — the same
check CI runs on your PR. Green means you're good to go.

Then open a pull request titled e.g. `i18n: add Italian (it)` or
`i18n: improve German translations`. Thank you! 🙏
