import 'dart:async';
import 'dart:io';

import 'package:dio/dio.dart';
import 'package:easy_localization/easy_localization.dart';
import 'package:flutter/material.dart';
import 'package:flutter_bloc/flutter_bloc.dart';
import 'package:shadcn_ui/shadcn_ui.dart';
import 'package:showcaseview/showcaseview.dart';
import 'package:url_launcher/url_launcher.dart';

import '../core/config/feature_flags.dart';
import '../core/deeplink/deep_link.dart';
import '../core/deeplink/deep_link_service.dart';
import '../core/di/locator.dart';
import '../core/share/share_intent_service.dart';
import '../core/storage/app_database.dart';
import '../core/ui/app_showcase.dart';
import '../core/ui/app_ui.dart';
import '../features/home/home_page.dart';
import '../features/home/widgets/floating_transfers.dart';
import '../features/inbox/presentation/inbox_cubit.dart';
import '../features/inbox/presentation/inbox_tab.dart';
import '../features/receive/presentation/incoming_transfer_sheet.dart';
import '../features/remote/data/cloud_transfer_service.dart';
import '../features/remote/data/stream_relay_service.dart';
import '../features/remote/presentation/remote_download.dart';
import '../features/room/presentation/room_page.dart';
import '../features/send/presentation/tray_cubit.dart';
import '../features/settings/presentation/settings_page.dart';
import '../features/vault/presentation/drive/drive_page.dart';
import '../features/web_nearby/data/web_nearby_service.dart';
import '../core/constants/app_links.dart';
import '../core/review/review_prompter.dart';
import '../core/ui/shell_tab.dart';

/// The root tab shell: Send, Inbox, Drive (while the vault flag shows it),
/// Rooms, Settings. Tabs are kept alive in an [IndexedStack] so
/// discovery and the receiver never restart on a tab switch; tabs are named,
/// not numbered, so Drive appearing or leaving never shifts the others.
class MainShell extends StatefulWidget {
  const MainShell({super.key});

  @override
  State<MainShell> createState() => _MainShellState();
}

class _MainShellState extends State<MainShell> {
  ShellTabId _tab = ShellTabId.send;
  final FeatureFlags _flags = getIt<FeatureFlags>();
  StreamSubscription<DeepLinkAction>? _linkSub;
  StreamSubscription<WebNearbyEvent>? _webNearbySub;
  StreamSubscription<List<String>>? _shareSub;
  ShareIntentService? _share;
  late final ShowcaseView _showcase;

  static const Map<ShellTabId, Widget> _pages = {
    ShellTabId.send: HomePage(),
    ShellTabId.inbox: InboxTab(),
    ShellTabId.drive: DrivePage(),
    ShellTabId.rooms: RoomPage(),
    ShellTabId.settings: SettingsPage(),
  };

  /// The tabs on the bar now: Drive only while the flag shows it.
  List<ShellTabId> get _tabs => [
    for (final t in ShellTabId.values)
      if (t != ShellTabId.drive || _flags.vaultVisible) t,
  ];

  @override
  void initState() {
    super.initState();
    // Register the showcase scope before the first build mounts any target;
    // kick off the Home tour (first run only) after the first frame.
    _showcase = registerAppShowcase();
    WidgetsBinding.instance.addPostFrameCallback(
      (_) => _maybeTour(ShellTabId.send),
    );
    _flags.addListener(_flagsChanged);
    shellTabRequest.addListener(_tabRequested);
    // Subscribe BEFORE start() so the cold-start launch link is delivered.
    final links = getIt<DeepLinkService>();
    _linkSub = links.actions.listen((action) {
      // Ensure the widget is fully built before handling deep links
      WidgetsBinding.instance.addPostFrameCallback((_) {
        _dispatch(action);
      });
    });
    links.start();
    getIt<ReviewPrompter>().onWindowsAsk = _askWindowsRating;
    _initShareIntent();
    _initWebNearby();
  }

  /// Browser peers (the app↔web Nearby bridge): surface incoming offers as a
  /// global accept sheet and settle sends/receives with toasts, whatever tab
  /// is open.
  void _initWebNearby() {
    _webNearbySub = getIt<WebNearbyService>().events.listen((event) {
      if (!mounted) return;
      switch (event) {
        case WebNearbyIncoming(:final request):
          _showWebNearbyOffer(request);
        case WebNearbySendDone(:final name):
          noteTransferSuccess();
          toast(
            context,
            'web_nearby.sent'.tr(namedArgs: {'name': name}),
            type: ToastType.success,
          );
        case WebNearbySendError(:final name, :final message):
          toast(
            context,
            message == 'declined'
                ? 'web_nearby.declined'.tr(namedArgs: {'name': name})
                : 'web_nearby.send_failed'.tr(namedArgs: {'name': name}),
            type: ToastType.error,
          );
        case WebNearbyReceiveDone(:final file):
          noteTransferSuccess();
          // Inbox watches the history DB — the new row appears on its own.
          toast(
            context,
            'web_nearby.received'.tr(namedArgs: {'name': file.fileName}),
            type: ToastType.success,
          );
        default:
          break;
      }
    });
  }

  /// A browser on this network offers a file: the same sheet as a nearby
  /// device (4.5). Closing it declines, so the browser is not left waiting.
  Future<void> _showWebNearbyOffer(WebNearbyIncomingRequest request) async {
    final ok = await showOffer(
      context,
      IncomingOffer(
        alias: request.fromAlias,
        icon: AppIcons.globePublic,
        files: [
          (
            name: request.name,
            size: request.size,
            type: request.mime,
            thumb: null,
          ),
        ],
      ),
    );
    ok ? request.accept() : request.decline();
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
    _select(ShellTabId.send); // jump to the Send tab
    toast(context, 'nav.added_files_to_send'.plural(paths.length));
  }

  @override
  void dispose() {
    getIt<ReviewPrompter>().onWindowsAsk = null;
    _flags.removeListener(_flagsChanged);
    shellTabRequest.removeListener(_tabRequested);
    _showcase.unregister();
    _linkSub?.cancel();
    _webNearbySub?.cancel();
    _shareSub?.cancel();
    _share?.dispose();
    super.dispose();
  }

  /// One-time coach-mark tours: Home right after first launch, Inbox/Rooms on
  /// their first visit. [maybeStartShowcase] owns the seen-flags and skips
  /// anything not on screen.
  void _maybeTour(ShellTabId tab) {
    if (!mounted) return;
    switch (tab) {
      case ShellTabId.send:
        maybeStartShowcase(
          id: ShowcaseIds.home,
          keys: [
            ShowcaseKeys.homeDevice,
            ShowcaseKeys.homeTray,
            ShowcaseKeys.homeNearby,
            ShowcaseKeys.homeActions,
            ShowcaseKeys.homeNav,
          ],
        );
      case ShellTabId.inbox:
        maybeStartShowcase(
          id: ShowcaseIds.inbox,
          // Browse files and Browser access both live in the menu now.
          keys: [ShowcaseKeys.inboxFiles],
        );
      case ShellTabId.rooms:
        maybeStartShowcase(
          id: ShowcaseIds.rooms,
          keys: [ShowcaseKeys.roomCreate, ShowcaseKeys.roomJoin],
        );
      case ShellTabId.drive:
      case ShellTabId.settings:
        break;
    }
  }

  /// Route a parsed link/QR payload to the right action.
  void _dispatch(DeepLinkAction action) {
    if (!mounted) return;

    try {
      final cloud = getIt<CloudTransferService>();
      switch (action) {
        case CloudTransferLink(:final code, :final key):
          showRemoteDownload(
            context,
            label: 'nav.transfer_code'.tr(namedArgs: {'code': code}),
            run: (p, c) => cloud.downloadTransfer(
              code,
              key: key,
              onProgress: p,
              cancel: c,
            ),
          );
        case LocalInstantLink(:final url):
          showRemoteDownload(
            context,
            label: url.host,
            run: (p, c) => cloud.downloadDirect(url, onProgress: p, cancel: c),
          );
        case StreamReceiveLink(:final code, :final key):
          showRemoteDownload(
            context,
            label: 'nav.live_transfer'.tr(),
            run: (p, c) => getIt<StreamRelayService>().receive(
              code,
              key: key,
              onProgress: p,
              cancel: c,
            ),
          );
        case AmbiguousCodeLink(:final code):
          // A hand-typed code carries no hint of its kind, so try both paths:
          // the stored 24h transfer first (fails fast with a 404), then — only
          // if there's genuinely no such transfer — a live stream with the same
          // code. 410 (already downloaded), 403, cancels and network errors are
          // surfaced as-is, never masked by the stream attempt.
          showRemoteDownload(
            context,
            label: 'nav.transfer_code'.tr(namedArgs: {'code': code}),
            run: (p, c) async {
              try {
                return await cloud.downloadTransfer(
                  code,
                  onProgress: p,
                  cancel: c,
                );
              } on Object catch (e) {
                if (!_isMissingTransfer(e)) rethrow;
                // Not a stored transfer — try a live stream with the same code.
                var streamStarted = false;
                try {
                  return await getIt<StreamRelayService>().receive(
                    code,
                    onProgress: (r, t) {
                      // receive() fires this once on join (file-info) before any
                      // bytes ⇒ a real session was reached.
                      streamStarted = true;
                      p(r, t);
                    },
                    cancel: c,
                  );
                } on Object catch (streamErr) {
                  // A session that started and then failed (declined mid-way,
                  // verification, stall) has a truthful message of its own —
                  // surface it. Only "nothing answered this code" becomes the
                  // friendly not-found hint.
                  if (streamStarted) rethrow;
                  if (streamErr is DioException &&
                      CancelToken.isCancel(streamErr)) {
                    rethrow; // user cancelled — keep it silent
                  }
                  throw CloudDownloadException('nav.code_not_found'.tr());
                }
              }
            },
          );
        case RescanSharedLink():
          _select(ShellTabId.send); // jump to the Send tab
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

  /// The Microsoft Store has no in-app rating dialog for this plugin, so a
  /// Store install on Windows gets this banner when [ReviewPrompter] says it
  /// is time; the button opens the Store's own rating page.
  bool _askWindowsRating() {
    if (!mounted) return false;
    final messenger = ScaffoldMessenger.maybeOf(context);
    if (messenger == null) return false;
    messenger.showSnackBar(
      SnackBar(
        content: Text('review.windows_ask'.tr()),
        duration: const Duration(seconds: 12),
        action: SnackBarAction(
          label: 'review.rate'.tr(),
          onPressed: () => launchUrl(Uri.parse(AppLinks.windowsReview)),
        ),
      ),
    );
    return true;
  }

  /// True only when the transfer *lookup* found no such stored transfer — the
  /// one case where falling back to a live stream is right. Anything else (410
  /// already-downloaded, 403, a mid-download 404, a user cancel, a network
  /// error) must surface instead of triggering the stream attempt.
  static bool _isMissingTransfer(Object e) => e is TransferNotFoundException;

  void _select(ShellTabId tab) {
    setState(() => _tab = tab);
    shellTabCurrent.value = tab;
    WidgetsBinding.instance.addPostFrameCallback((_) => _maybeTour(tab));
  }

  void _tabRequested() {
    final t = shellTabRequest.value;
    if (t == null || !mounted) return;
    shellTabRequest.value = null;
    if (_tabs.contains(t)) _select(t);
  }

  /// Drive left the bar while it was open: fall back to the Inbox.
  void _flagsChanged() {
    if (!mounted) return;
    setState(() {
      if (!_tabs.contains(_tab)) _tab = ShellTabId.inbox;
    });
    shellTabCurrent.value = _tab;
  }

  @override
  Widget build(BuildContext context) {
    final cs = ShadTheme.of(context).colorScheme;
    final wide = context.isWideLayout;
    // Every tab stays alive (discovery and the receiver never restart on a
    // switch), but only the visible one may tick: a hidden tab's spinners,
    // pulses and progress stop drawing frames (redesign-plan.md 1.4).
    final tabs = _tabs;
    final index = tabs.indexOf(_tab).clamp(0, tabs.length - 1);
    final content = Stack(
      fit: StackFit.expand,
      children: [
        IndexedStack(
          index: index,
          children: [
            for (final t in tabs)
              KeyedSubtree(
                key: ValueKey(t),
                child: TickerMode(
                  enabled: t == _tab,
                  child: ShellTab(active: t == _tab, child: _pages[t]!),
                ),
              ),
          ],
        ),
        // Live transfers float above every tab, not only Send (4.2).
        Positioned(
          left: 0,
          right: 0,
          bottom: 0,
          child: FloatingTransfers(onSendTab: _tab == ShellTabId.send),
        ),
      ],
    );

    Widget nav(Widget Function(List<AppNavItem> items) build) => AppShowcase(
      showcaseKey: ShowcaseKeys.homeNav,
      title: 'showcase.home_nav_title'.tr(),
      description: 'showcase.home_nav_body'.tr(),
      targetRadius: 0,
      child: ShellNavItems(tabs: tabs, current: _tab, builder: build),
    );

    // Wide (desktop / tablet-landscape): a side rail + content pane. Narrow
    // (phone): a bottom tab bar. The nav showcase key is shared by the two
    // variants; only one is ever mounted (wide XOR narrow).
    if (wide) {
      return Scaffold(
        backgroundColor: cs.background,
        body: Row(
          children: [
            nav(
              (items) => AppNavRail(
                items: items,
                currentIndex: index,
                onTap: (i) => _select(tabs[i]),
              ),
            ),
            Expanded(child: content),
          ],
        ),
      );
    }
    return Scaffold(
      backgroundColor: cs.background,
      body: content,
      bottomNavigationBar: nav(
        (items) => AppBottomNav(
          items: items,
          currentIndex: index,
          onTap: (i) => _select(tabs[i]),
        ),
      ),
    );
  }
}


/// The bar's items for [tabs], with the Inbox count: what arrived since the
/// Inbox was last left, none while it is open. Only this rebuilds when a
/// file arrives, not the whole shell.
class ShellNavItems extends StatelessWidget {
  const ShellNavItems({
    super.key,
    required this.tabs,
    required this.current,
    required this.builder,
  });

  final List<ShellTabId> tabs;
  final ShellTabId current;
  final Widget Function(List<AppNavItem> items) builder;

  /// The tabs on the bar now: Drive only while the flag shows it.
  static List<ShellTabId> visibleTabs() => [
    for (final t in ShellTabId.values)
      if (t != ShellTabId.drive || getIt<FeatureFlags>().vaultVisible) t,
  ];

  @override
  Widget build(BuildContext context) => ValueListenableBuilder<DateTime>(
    valueListenable: context.read<InboxCubit>().seenAt,
    builder: (context, seenAt, _) =>
        BlocSelector<InboxCubit, List<TransferRecord>, int>(
          selector: (items) => current == ShellTabId.inbox
              ? 0
              : items.where((r) => r.timestamp.isAfter(seenAt)).length,
          builder: (context, count) => builder([
            for (final t in tabs)
              switch (t) {
                ShellTabId.send => AppNavItem(
                  icon: AppIcons.send,
                  label: 'nav.tab_share'.tr(),
                ),
                ShellTabId.inbox => AppNavItem(
                  icon: AppIcons.notification,
                  label: 'nav.tab_inbox'.tr(),
                  badge: count,
                ),
                ShellTabId.drive => AppNavItem(
                  icon: AppIcons.cloudSync,
                  label: 'vault.title'.tr(),
                ),
                ShellTabId.rooms => AppNavItem(
                  icon: AppIcons.teamGroup,
                  label: 'nav.tab_rooms'.tr(),
                ),
                ShellTabId.settings => AppNavItem(
                  icon: AppIcons.settings,
                  label: 'nav.tab_settings'.tr(),
                ),
              },
          ]),
        ),
  );
}

/// A page pushed over the shell, on a computer: the shell's side rail
/// (the tab it came from selected) and the page beside it, so a page like
/// Secure Link sits where the tabs do. Choosing a tab closes the page.
/// On a phone, the page alone.
class ShellPushedPage extends StatelessWidget {
  const ShellPushedPage({super.key, required this.child});

  final Widget child;

  @override
  Widget build(BuildContext context) {
    if (!context.isWideLayout) return child;
    final tabs = ShellNavItems.visibleTabs();
    final current = shellTabCurrent.value;
    return Scaffold(
      backgroundColor: context.tokens.bg,
      body: Row(
        children: [
          ShellNavItems(
            tabs: tabs,
            current: current,
            builder: (items) => AppNavRail(
              items: items,
              currentIndex: tabs.indexOf(current).clamp(0, tabs.length - 1),
              onTap: (i) {
                final nav = Navigator.of(context, rootNavigator: true);
                nav.popUntil((r) => r.isFirst);
                shellTabRequest.value = tabs[i];
              },
            ),
          ),
          Expanded(child: child),
        ],
      ),
    );
  }
}
