import 'package:flutter/widgets.dart';

/// The language the app shows now (a BCP 47 tag), for what is written
/// outside a widget, such as the Drive reminders' dates; set by the app as it
/// builds, so listeners hear a change of language.
final ValueNotifier<String?> appLocaleTag = ValueNotifier(null);

/// The 13 supported app locales — `en` is the source & fallback. Region/script
/// variants (`pt-BR`, `zh-Hans`, `zh-Hant`) map to matching JSON files under
/// `assets/translations/`.
const List<Locale> appLocales = [
  Locale('en'),
  Locale('id'),
  Locale('ar'), // RTL
  Locale('de'),
  Locale('es'),
  Locale('fr'),
  Locale('hi'),
  Locale('ja'),
  Locale('ko'),
  Locale('pt', 'BR'),
  Locale('ru'),
  Locale('zh', 'Hans'),
  Locale('zh', 'Hant'),
];

const Locale appFallbackLocale = Locale('en');

/// Native display name for each locale, keyed by `easy_localization`'s locale
/// string (`languageCode` or `languageCode_COUNTRY`). Used by the settings picker.
const Map<String, String> localeDisplayNames = {
  'en': 'English',
  'id': 'Bahasa Indonesia',
  'ar': 'العربية',
  'de': 'Deutsch',
  'es': 'Español',
  'fr': 'Français',
  'hi': 'हिन्दी',
  'ja': '日本語',
  'ko': '한국어',
  'pt_BR': 'Português (Brasil)',
  'ru': 'Русский',
  'zh_Hans': '简体中文',
  'zh_Hant': '繁體中文',
};

/// Human name for a [Locale] (falls back to its language code).
String localeName(Locale l) =>
    localeDisplayNames[l.countryCode == null
        ? l.languageCode
        : '${l.languageCode}_${l.countryCode}'] ??
    l.languageCode;
