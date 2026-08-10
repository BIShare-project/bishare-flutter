import 'dart:async';

import 'package:easy_localization/easy_localization.dart';
import 'package:flutter/material.dart';
import 'package:flutter_bloc/flutter_bloc.dart';
import 'package:shadcn_ui/shadcn_ui.dart';

import '../core/di/locator.dart';
import '../core/theme/app_theme.dart';
import '../features/clipboard/presentation/clipboard_cubit.dart';
import '../features/devices/presentation/devices_cubit.dart';
import '../features/discovery/data/discovery_service.dart';
import '../features/discovery/presentation/discovery_cubit.dart';
import '../features/favorites/presentation/favorites_cubit.dart';
import '../features/history/presentation/history_cubit.dart';
import '../features/inbox/presentation/inbox_cubit.dart';
import '../features/nearby/presentation/nearby_cubit.dart';
import '../features/room/presentation/room_cubit.dart';
import 'router.dart';
import '../features/receive/presentation/receive_cubit.dart';
import '../features/send/data/transfer_client.dart';
import '../features/send/presentation/send_cubit.dart';
import '../features/send/presentation/tray_cubit.dart';
import '../features/settings/domain/settings.dart';
import '../features/settings/presentation/settings_cubit.dart';

/// Root widget. Provides the app-scoped BLoCs, the shadcn-themed [ShadApp]
/// (theme + accent driven by [SettingsCubit]), and drives discovery on the app
/// lifecycle (refresh on resume, announce goodbye on background/terminate).
class BIShareApp extends StatefulWidget {
  const BIShareApp({super.key});

  @override
  State<BIShareApp> createState() => _BIShareAppState();
}

class _BIShareAppState extends State<BIShareApp> with WidgetsBindingObserver {
  @override
  void initState() {
    super.initState();
    WidgetsBinding.instance.addObserver(this);
  }

  @override
  void dispose() {
    WidgetsBinding.instance.removeObserver(this);
    _announceGoodbye();
    super.dispose();
  }

  @override
  void didChangeAppLifecycleState(AppLifecycleState state) {
    switch (state) {
      case AppLifecycleState.resumed:
        unawaited(getIt<DiscoveryService>().restart());
      case AppLifecycleState.paused:
      case AppLifecycleState.detached:
        _announceGoodbye();
      case AppLifecycleState.inactive:
      case AppLifecycleState.hidden:
        break;
    }
  }

  void _announceGoodbye() {
    final client = getIt<TransferClient>();
    for (final device in getIt<DiscoveryService>().current) {
      unawaited(client.sendGoodbye(device));
    }
  }

  @override
  Widget build(BuildContext context) {
    return MultiBlocProvider(
      providers: [
        BlocProvider(create: (_) => DiscoveryCubit(getIt())),
        BlocProvider(create: (_) => ReceiveCubit(getIt())),
        BlocProvider(create: (_) => SendCubit(getIt(), getIt(), getIt())),
        BlocProvider(create: (_) => TrayCubit(getIt())),
        BlocProvider(create: (_) => FavoritesCubit(getIt())),
        BlocProvider(create: (_) => DevicesCubit(getIt(), getIt(), getIt())),
        BlocProvider(create: (_) => ClipboardCubit(getIt(), getIt())),
        BlocProvider(create: (_) => InboxCubit(getIt())),
        BlocProvider(create: (_) => HistoryCubit(getIt())),
        BlocProvider(create: (_) => RoomCubit(getIt(), getIt())),
        BlocProvider(create: (_) => NearbyCubit(getIt(), getIt(), getIt())),
        BlocProvider(
          create: (_) => SettingsCubit(
            getIt(),
            getIt(),
            getIt(),
            getIt(),
            getIt(),
            getIt(),
          ),
        ),
      ],
      child: BlocBuilder<SettingsCubit, Settings>(
        builder: (context, settings) => ShadApp.router(
          title: 'BIShare',
          debugShowCheckedModeBanner: false,
          // easy_localization: delegates + supported locales + active locale.
          localizationsDelegates: context.localizationDelegates,
          supportedLocales: context.supportedLocales,
          locale: context.locale,
          theme: AppTheme.light(settings.accent),
          darkTheme: AppTheme.dark(settings.accent),
          themeMode: settings.themeMode,
          // Apply IBM Plex Sans to raw Material text too (not just shadcn).
          materialThemeBuilder: (context, theme) => theme.copyWith(
            textTheme: theme.textTheme.apply(fontFamily: AppTheme.fontFamily),
          ),
          routerConfig: appRouter,
        ),
      ),
    );
  }
}
