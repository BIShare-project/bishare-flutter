import 'package:easy_localization/easy_localization.dart';
import 'package:flutter/material.dart';

import 'app/app.dart';
import 'bootstrap.dart';
import 'core/desktop/desktop_service.dart';
import 'core/l10n/app_locales.dart';

Future<void> main() async {
  WidgetsFlutterBinding.ensureInitialized();
  await EasyLocalization.ensureInitialized();
  await DesktopService.initWindow(); // native window frame (desktop only)
  await bootstrap();
  runApp(
    EasyLocalization(
      supportedLocales: appLocales,
      path: 'assets/translations',
      fallbackLocale: appFallbackLocale,
      useFallbackTranslations: true,
      child: const BIShareApp(),
    ),
  );
}
