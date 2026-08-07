import 'package:easy_localization/easy_localization.dart';
import 'package:flutter/foundation.dart';
import 'package:flutter/material.dart';

import 'app/app.dart';
import 'bootstrap.dart';
import 'core/desktop/desktop_service.dart';
import 'core/l10n/app_locales.dart';
import 'core/platform/tv.dart';

Future<void> main() async {
  WidgetsFlutterBinding.ensureInitialized();
  // A widget-build exception must not tear down to a blank window either — log it
  // and keep the tree alive (matters on review/compat runtimes where a plugin
  // may misbehave). Debug still shows the red error box.
  final priorOnError = FlutterError.onError;
  FlutterError.onError = (details) {
    if (kDebugMode) {
      priorOnError?.call(details);
    } else {
      FlutterError.presentError(details);
    }
  };

  await EasyLocalization.ensureInitialized();
  await DesktopService.initWindow(); // native window frame (desktop only)
  isTvDevice = await DeviceChannel.isTv(); // Leanback → TV shell (see router)
  // bootstrap() is internally fault-tolerant, but guard here too: WHATEVER
  // happens during init, we must reach runApp so the window shows content and
  // never fails App Review 2.1(a) ("did not load any content on launch").
  try {
    await bootstrap();
  } on Object catch (e, st) {
    debugPrint('[main] bootstrap failed — launching UI anyway: $e\n$st');
  }
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
