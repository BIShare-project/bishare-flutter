import 'dart:async';
import 'dart:io';

import 'package:easy_localization/easy_localization.dart';
import 'package:flutter/material.dart';
import 'package:flutter_bloc/flutter_bloc.dart';
import 'package:shadcn_ui/shadcn_ui.dart';
import 'package:url_launcher/url_launcher.dart';

import '../core/deeplink/deep_link.dart';
import '../core/deeplink/deep_link_service.dart';
import '../core/di/locator.dart';
import '../core/share/share_intent_service.dart';
import '../core/storage/app_database.dart';
import '../core/ui/app_ui.dart';
import '../features/history/presentation/history_page.dart';
import '../features/home/home_page.dart';
import '../features/inbox/presentation/inbox_cubit.dart';
import '../features/inbox/presentation/inbox_page.dart';
import '../features/remote/data/cloud_transfer_service.dart';
import '../features/remote/data/stream_relay_service.dart';
import '../features/remote/presentation/remote_download.dart';
import '../features/room/presentation/room_page.dart';
import '../features/send/presentation/tray_cubit.dart';
import '../features/settings/presentation/settings_page.dart';

/// The root tab shell (mirrors native iOS: Share · Inbox · Settings). Tabs are
/// kept alive in an [IndexedStack] so discovery and the receiver never restart
/// on a tab switch. Rooms + Stats tabs arrive with those P2 features.
class MainShell extends StatefulWidget {
  const MainShell({super.key});

  @override
  State<MainShell> createState() => _MainShellState();
}

class _MainShellState extends State<MainShell> {
  int _index = 0;
  StreamSubscription<DeepLinkAction>? _linkSub;
  StreamSubscription<List<String>>? _shareSub;
  ShareIntentService? _share;

  static const _pages = [
    HomePage(),
    InboxPage(),
    RoomPage(),
    HistoryPage(),
    SettingsPage(),
  ];

  @override
  void initState() {
    super.initState();
    // Subscribe BEFORE start() so the cold-start launch link is delivered.
    final links = getIt<DeepLinkService>();
    _linkSub = links.actions.listen((action) {
      // Ensure the widget is fully built before handling deep links
      WidgetsBinding.instance.addPostFrameCallback((_) {
        _dispatch(action);
      });
    });
    links.start();
    _initShareIntent();
  }

  /// Files shared into BIShare from another app's share sheet (mobile only) land
  /// in the compose tray, ready to send.
  void _initShareIntent() {
    // iOS handles sharing entirely inside its native Share Extension, so the
    // app is never involved there. Android routes shared files here.
    if (!Platform.isAndroid) return;
    final share = _share = ShareIntentService();
    _shareSub = share.onShare.listen(_onShared);
    share.getInitial().then(_onShared);
  }

  void _onShared(List<String> shared) {
    final paths = shared.where((p) => p.isNotEmpty).toList();
    if (!mounted || paths.isEmpty) return;
    context.read<TrayCubit>().addDropped(paths);
    _select(0); // jump to the Share tab
    toast(context, 'nav.added_files_to_send'.plural(paths.length));
  }

  @override
  void dispose() {
    _linkSub?.cancel();
    _shareSub?.cancel();
    _share?.dispose();
    super.dispose();
  }

  /// Route a parsed link/QR payload to the right action.
  void _dispatch(DeepLinkAction action) {
    if (!mounted) return;

    try {
      final cloud = getIt<CloudTransferService>();
      switch (action) {
        case CloudTransferLink(:final code):
          showRemoteDownload(
            context,
            label: 'nav.transfer_code'.tr(namedArgs: {'code': code}),
            run: (p, c) => cloud.downloadTransfer(code, onProgress: p, cancel: c),
          );
        case CloudShareLink(:final token):
          showRemoteDownload(
            context,
            label: 'nav.shared_file'.tr(),
            run: (p, c) => cloud.downloadShare(token, onProgress: p, cancel: c),
          );
        case LocalInstantLink(:final url):
          showRemoteDownload(
            context,
            label: url.host,
            run: (p, c) => cloud.downloadDirect(url, onProgress: p, cancel: c),
          );
        case StreamReceiveLink(:final code):
          showRemoteDownload(
            context,
            label: 'nav.live_transfer'.tr(),
            run: (p, c) =>
                getIt<StreamRelayService>().receive(code, onProgress: p, cancel: c),
          );
        case OpenExternalLink(:final url):
          launchUrl(url, mode: LaunchMode.externalApplication);
        case RescanSharedLink():
          _select(0); // jump to the Share tab
      }
    } catch (e) {
      // Log error but don't crash the app
      debugPrint('Error handling deep link: $e');
      // Optionally show error to user
      if (mounted) {
        toast(context, 'nav.error_processing_link'.tr());
      }
    }
  }

  List<AppNavItem> _items(int inboxCount) => [
    AppNavItem(icon: AppIcons.shareLink, label: 'nav.tab_share'.tr()),
    AppNavItem(
      icon: AppIcons.notification,
      label: 'nav.tab_inbox'.tr(),
      badge: inboxCount,
    ),
    AppNavItem(icon: AppIcons.teamGroup, label: 'nav.tab_rooms'.tr()),
    AppNavItem(icon: AppIcons.history, label: 'nav.tab_history'.tr()),
    AppNavItem(icon: AppIcons.settings, label: 'nav.tab_settings'.tr()),
  ];

  void _select(int i) => setState(() => _index = i);

  @override
  Widget build(BuildContext context) {
    final cs = ShadTheme.of(context).colorScheme;
    final wide = context.isWideLayout;
    final content = IndexedStack(index: _index, children: _pages);

    // Wide (desktop / tablet-landscape): a side rail + content pane. Narrow
    // (phone): a bottom tab bar. Mirrors native iOS (sidebar vs TabView).
    return BlocBuilder<InboxCubit, List<TransferRecord>>(
      builder: (context, items) {
        if (wide) {
          return Scaffold(
            backgroundColor: cs.background,
            body: Row(
              children: [
                AppNavRail(
                  items: _items(items.length),
                  currentIndex: _index,
                  onTap: _select,
                ),
                Expanded(child: content),
              ],
            ),
          );
        }
        return Scaffold(
          backgroundColor: cs.background,
          body: content,
          bottomNavigationBar: AppBottomNav(
            items: _items(items.length),
            currentIndex: _index,
            onTap: _select,
          ),
        );
      },
    );
  }
}
