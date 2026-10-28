import 'dart:async';
import 'dart:io';

import 'package:desktop_drop/desktop_drop.dart';
import 'package:easy_localization/easy_localization.dart';
import 'package:flutter/material.dart';
import 'package:flutter/services.dart';
import 'package:go_router/go_router.dart';
import 'package:shadcn_ui/shadcn_ui.dart';
import 'package:shared_preferences/shared_preferences.dart';

import '../../../../core/di/locator.dart';
import '../../../../core/storage/app_database.dart';
import '../../../../core/storage/vault_tables.dart';
import '../../../../core/ui/app_ui.dart';
import '../../../../core/ui/shell_tab.dart';
import '../../../settings/presentation/widgets/glyph.dart';
import '../../data/vault_account.dart';
import '../../data/vault_background.dart';
import '../../data/vault_api.dart';
import '../../data/vault_downloads.dart';
import '../../data/vault_photo_backup.dart';
import '../../data/vault_sync.dart';
import '../../data/vault_upload_batch.dart';
import '../../data/vault_uploader.dart';
import '../vault_sign_in_buttons.dart';
import 'drive_actions.dart';
import 'drive_controller.dart';
import 'drive_format.dart';
import 'drive_gallery_view.dart';
import 'drive_plans_page.dart';
import 'drive_widgets.dart';

/// BIShare Drive's file manager (drive-plan.md tasks 4.7, 4.8, 4.10): the
/// Drive's folders and the views across it (Recent, Photos and videos,
/// Documents, Audio, Trash), search, sort, list or grid, selection with
/// actions for many items at once, uploads of files, photos and whole
/// folders, drag and drop and keyboard shortcuts on computers. Lives in the
/// Inbox tab as its second segment ([segment]).
class DrivePage extends StatefulWidget {
  const DrivePage({super.key, this.segment});

  final Widget? segment;

  @override
  State<DrivePage> createState() => _DrivePageState();
}

class _DrivePageState extends State<DrivePage>
    with SingleTickerProviderStateMixin {
  final VaultAccount _account = getIt<VaultAccount>();
  final VaultDao _dao = getIt<AppDatabase>().vaultDao;
  final VaultSync _sync = getIt<VaultSync>();
  final VaultUploader _uploader = getIt<VaultUploader>();
  final VaultDownloads _downloads = getIt<VaultDownloads>();

  /// Photo backup, on phones and tablets with a photo library.
  final VaultPhotoBackup? _photos = getIt.isRegistered<VaultPhotoBackup>()
      ? getIt<VaultPhotoBackup>()
      : null;
  late final DriveController _ctrl = DriveController(
    _dao,
    prefs: getIt<SharedPreferences>(),
  );
  late final DriveActions _act = DriveActions(context, _ctrl);
  final TextEditingController _search = TextEditingController();
  final FocusNode _searchFocus = FocusNode();
  final FocusNode _focus = FocusNode(debugLabel: 'drive');

  List<VaultObject> _visible = const [];
  Stream<List<VaultObject>>? _items;
  String? _itemsKey;
  late final Stream<Map<String?, int>> _counts = _dao.watchChildCounts();
  late final Stream<List<VaultObject>> _live = _dao.watchLive();
  late final Stream<List<VaultObject>> _trash = _dao.watchTrash();
  late final Stream<List<VaultTransfer>> _transfers = _dao.watchTransfers();
  Map<String, String> _folderNames = const {};
  VaultStatus? _started;
  bool _dragging = false;

  /// The Inbox tab is on screen (with Drive chosen, or this page would not
  /// exist): drops, "back" and the shortcuts are only this page's then.
  bool _active = true;

  /// The folders of the open path, followed: one trashed or deleted on
  /// another device closes the path down to what is left.
  StreamSubscription<List<VaultObject>>? _pathSub;
  String _pathKey = '';

  /// A photo library to back up (iOS, Android).
  bool get _library => _photos?.available ?? false;

  /// Photos and videos on a phone: the phone's own library with the Drive's
  /// photos from other devices, as one gallery (task 5.8).
  bool get _phoneGallery =>
      _library && _ctrl.view == DriveView.media && !_ctrl.searching;

  static bool get _desktop =>
      Platform.isMacOS || Platform.isWindows || Platform.isLinux;

  /// Drive's own sidebar needs this much room next to the app's.
  static const _sidebarMinWidth = 720.0;

  /// The storage line follows uploads (VaultAccount.followUsage).
  StreamSubscription<Object?>? _usage;

  /// The four tabs of a phone (redesign-plan.md 6.1): Photos, Files,
  /// Recent, Trash. Documents and Audio are chips inside Files.
  static const _tabViews = [
    DriveView.media,
    DriveView.files,
    DriveView.recent,
    DriveView.trash,
  ];

  static int _tabOf(DriveView v) => switch (v) {
    DriveView.media => 0,
    DriveView.files || DriveView.documents || DriveView.audio => 1,
    DriveView.recent => 2,
    DriveView.trash => 3,
  };

  late final TabController _tabs = TabController(
    length: _tabViews.length,
    vsync: this,
    initialIndex: _tabOf(_ctrl.view),
  );

  @override
  void initState() {
    super.initState();
    // A phone opens on its photos, as the redesign's Drive does.
    if (_library) _ctrl.setView(DriveView.media);
    _account.addListener(_onAccount);
    unawaited(_account.load().then((_) => _onAccount()));
    _usage = _account.followUsage();
    _ctrl.addListener(_onCtrl);
    _searchFocus.addListener(_onSearchFocus);
  }

  @override
  void didChangeDependencies() {
    super.didChangeDependencies();
    // The words background runs use, in this language (also after a change).
    unawaited(VaultBackground.saveTexts(getIt<SharedPreferences>()));
    final active = ShellTab.isActive(context);
    if (active == _active) return;
    _active = active;
    // Back on screen: the keyboard shortcuts follow this page again.
    if (active && _desktop && !_searchFocus.hasFocus) _focus.requestFocus();
  }

  @override
  void dispose() {
    unawaited(_pathSub?.cancel());
    unawaited(_usage?.cancel());
    _account.removeListener(_onAccount);
    _ctrl
      ..removeListener(_onCtrl)
      ..dispose();
    _tabs.dispose();
    _searchFocus.removeListener(_onSearchFocus);
    _search.dispose();
    _searchFocus.dispose();
    _focus.dispose();
    super.dispose();
  }

  void _onCtrl() {
    if (_search.text != _ctrl.query) _search.text = _ctrl.query;
    final tab = _tabOf(_ctrl.view);
    if (_tabs.index != tab) _tabs.animateTo(tab);
    final ids = [for (final o in _ctrl.path) o.id];
    final key = ids.join('/');
    if (key != _pathKey) {
      _pathKey = key;
      unawaited(_pathSub?.cancel());
      _pathSub = ids.isEmpty
          ? null
          : _dao.watchObjects(ids).skip(1).listen((_) => _ctrl.prune());
    }
    if (mounted) setState(() {});
  }

  /// Typing in the search box: the page's shortcuts step aside.
  void _onSearchFocus() {
    if (mounted) setState(() {});
  }

  /// Once the device has the key: follow the server, resume uploads, fetch
  /// the quota. Once per change of status.
  void _onAccount() {
    final notice = _account.removedNotice;
    if (notice != null && mounted) {
      _account.removedNotice = null;
      toast(
        context,
        (notice == 'VAULT_NOT_FOUND'
                ? 'vault.account_gone'
                : 'vault.removed_here')
            .tr(),
        type: ToastType.warning,
      );
    }
    final status = _account.status;
    if (status == _started) return;
    _started = status;
    // Signed out, or another account: nothing of the old path or selection.
    if (status != VaultStatus.ready) _ctrl.reset();
    // Ready on a phone: open on its photos, as the redesign's Drive does.
    if (status == VaultStatus.ready && _library) {
      _ctrl.setView(DriveView.media);
    }
    if (mounted) setState(() {});
    if (status != VaultStatus.ready) return;
    unawaited(_sync.start());
    unawaited(_uploader.run());
    unawaited(_refreshInfo());
  }

  Future<void> _refreshInfo() async {
    try {
      await _account.refreshInfo();
    } on VaultApiException catch (e) {
      debugPrint('[vault] info: $e');
    }
  }

  Future<void> _refresh() async {
    // Uploads stopped by a lost connection start again with a pull down.
    unawaited(_uploader.run());
    try {
      await _sync.pull();
      await _ctrl.prune();
    } on Object catch (e) {
      debugPrint('[vault] refresh: $e');
      if (mounted) {
        toast(context, 'vault.error_network'.tr(), type: ToastType.error);
      }
    }
    await _refreshInfo();
  }

  Stream<List<VaultObject>> _itemsStream() {
    final key =
        '${_ctrl.view}|${_ctrl.folder}|${_ctrl.query}|${_ctrl.sort}|${_ctrl.ascending}';
    if (key != _itemsKey || _items == null) {
      _itemsKey = key;
      _items = _ctrl.items();
    }
    return _items!;
  }

  // ---- taps -------------------------------------------------------------------------

  void _tap(VaultObject o) {
    final keys = HardwareKeyboard.instance;
    if (_desktop && keys.isShiftPressed) {
      _ctrl.selectRange(_visible, o.id);
      return;
    }
    if (_desktop && (keys.isMetaPressed || keys.isControlPressed)) {
      _ctrl.toggle(o.id);
      return;
    }
    if (_ctrl.selecting) {
      _ctrl.toggle(o.id);
      return;
    }
    unawaited(_act.open(o));
  }

  void _longPress(VaultObject o) {
    HapticFeedback.selectionClick();
    _ctrl.toggle(o.id);
  }

  List<VaultObject> get _selection => [
    for (final o in _visible)
      if (_ctrl.isSelected(o.id)) o,
  ];

  bool get _phone => Platform.isAndroid || Platform.isIOS;

  List<AppMenuAction> _itemActions(VaultObject o) {
    // Search in Trash looks only at what is in the trash.
    if (_ctrl.view == DriveView.trash) {
      return [
        AppMenuAction(
          icon: AppIcons.refreshSync,
          label: 'vault.restore'.tr(),
          onTap: () => _act.restore([o]),
        ),
        AppMenuAction(
          icon: AppIcons.eyePreview,
          label: 'vault.details'.tr(),
          onTap: () => _act.details(o),
        ),
        AppMenuAction(
          icon: AppIcons.trashDelete,
          label: 'vault.delete_for_good'.tr(),
          destructive: true,
          onTap: () => _act.deleteForGood([o]),
        ),
      ];
    }
    final file = o.kind == 'file';
    final elsewhere = _ctrl.view != DriveView.files || _ctrl.searching;
    return [
      AppMenuAction(
        icon: file ? AppIcons.eyePreview : AppIcons.folderOpen,
        label: 'vault.open'.tr(),
        onTap: () => _act.open(o),
      ),
      if (elsewhere)
        AppMenuAction(
          icon: AppIcons.folder,
          label: 'vault.show_in_folder'.tr(),
          onTap: () => _ctrl.reveal(o.parent),
        ),
      if (file && _phone)
        AppMenuAction(
          icon: AppIcons.shareLink,
          label: 'vault.share_file'.tr(),
          onTap: () => _act.share([o]),
        ),
      if (file && _phone && isMedia(o.mime))
        AppMenuAction(
          icon: AppIcons.imageDown,
          label: 'vault.save_to_photos'.tr(),
          onTap: () => _act.saveToPhotos([o]),
        ),
      if (!_phone) ...[
        AppMenuAction(
          icon: AppIcons.downloadFile,
          label: 'vault.download'.tr(),
          onTap: () => _act.download([o]),
        ),
        AppMenuAction(
          icon: AppIcons.folderOpen,
          label: 'vault.download_to'.tr(),
          onTap: () => _act.download([o], choose: true),
        ),
      ],
      AppMenuAction(
        icon: AppIcons.linkCopy,
        label: 'vault.share_link'.tr(),
        onTap: () => _act.shareLink(o),
      ),
      AppMenuAction(
        icon: AppIcons.renameEdit,
        label: 'vault.rename'.tr(),
        onTap: () => _act.rename(o),
      ),
      AppMenuAction(
        icon: AppIcons.moveFile,
        label: 'vault.move'.tr(),
        onTap: () => _act.moveOrCopy([o], copy: false),
      ),
      AppMenuAction(
        icon: AppIcons.copyDuplicate,
        label: 'vault.copy'.tr(),
        onTap: () => _act.moveOrCopy([o], copy: true),
      ),
      AppMenuAction(
        icon: AppIcons.storageUsage,
        label: 'vault.details'.tr(),
        onTap: () => _act.details(o),
      ),
      AppMenuAction(
        icon: AppIcons.trashDelete,
        label: 'vault.trash'.tr(),
        destructive: true,
        onTap: () => _act.trash([o]),
      ),
    ];
  }

  void _more(VaultObject o) => showActionSheet(
    context,
    title: o.name,
    subtitle: o.kind == 'dir' ? 'vault.folder'.tr() : kindLabel(o),
    actions: _itemActions(o),
  );

  Future<void> _pageMenu() => showActionSheet(
    context,
    title: 'vault.drive'.tr(),
    actions: [
      AppMenuAction(
        icon: AppIcons.refreshSync,
        label: 'vault.refresh'.tr(),
        onTap: _refresh,
      ),
      // While searching, the screen shows only the matches: emptying the
      // trash is offered on the whole trash only.
      if (_ctrl.view == DriveView.trash &&
          !_ctrl.searching &&
          _visible.isNotEmpty)
        AppMenuAction(
          icon: AppIcons.trashDelete,
          label: 'vault.empty_trash'.tr(),
          destructive: true,
          onTap: () => _act.deleteForGood(_visible, all: true),
        ),
      AppMenuAction(
        icon: AppIcons.linkCopy,
        label: 'vault.links_title'.tr(),
        onTap: _act.manageLinks,
      ),
      AppMenuAction(
        icon: AppIcons.transferP2p,
        label: 'vault.transfers'.tr(),
        onTap: () => context.push('/drive-transfers'),
      ),
      AppMenuAction(
        icon: AppIcons.storageUsage,
        label: 'vault.storage'.tr(),
        onTap: () => context.push('/drive-storage'),
      ),
      AppMenuAction(
        icon: AppIcons.settings,
        label: 'vault.account_title'.tr(),
        onTap: () => context.push('/drive-account'),
      ),
    ],
  );

  List<(String, String, VoidCallback, bool)> _selectionActions() {
    final items = _selection;
    if (_ctrl.view == DriveView.trash) {
      return [
        (
          AppIcons.refreshSync,
          'vault.restore'.tr(),
          () => _act.restore(items),
          false,
        ),
        (
          AppIcons.trashDelete,
          'vault.delete_for_good'.tr(),
          () => _act.deleteForGood(items),
          true,
        ),
      ];
    }
    return [
      if (_phone)
        (
          AppIcons.shareLink,
          'vault.share_file'.tr(),
          () => _act.share(items),
          false,
        )
      else
        (
          AppIcons.downloadFile,
          'vault.download'.tr(),
          () => _act.download(items),
          false,
        ),
      (
        AppIcons.moveFile,
        'vault.move'.tr(),
        () => _act.moveOrCopy(items, copy: false),
        false,
      ),
      (
        AppIcons.copyDuplicate,
        'vault.copy'.tr(),
        () => _act.moveOrCopy(items, copy: true),
        false,
      ),
      (AppIcons.trashDelete, 'vault.trash'.tr(), () => _act.trash(items), true),
    ];
  }

  // ---- keyboard (computers) ----------------------------------------------------------

  Map<ShortcutActivator, VoidCallback> get _shortcuts {
    final mac = Platform.isMacOS;
    SingleActivator cmd(LogicalKeyboardKey k, {bool shift = false}) =>
        SingleActivator(k, meta: mac, control: !mac, shift: shift);
    void one(void Function(VaultObject) f) {
      final s = _selection;
      if (s.length == 1) f(s.single);
    }

    void removeSelected() {
      final s = _selection;
      if (s.isEmpty) return;
      if (_ctrl.view == DriveView.trash) {
        unawaited(_act.deleteForGood(s));
      } else {
        unawaited(_act.trash(s));
      }
    }

    return {
      cmd(LogicalKeyboardKey.keyA): () => _ctrl.selectAll(_visible),
      cmd(LogicalKeyboardKey.keyF): _searchFocus.requestFocus,
      cmd(LogicalKeyboardKey.keyN, shift: true): () {
        if (_ctrl.canAdd) unawaited(_act.newFolder());
      },
      cmd(LogicalKeyboardKey.keyU): () {
        if (_ctrl.canAdd) unawaited(_act.addFiles());
      },
      const SingleActivator(LogicalKeyboardKey.escape): () => _ctrl.up(),
      const SingleActivator(LogicalKeyboardKey.delete): removeSelected,
      SingleActivator(LogicalKeyboardKey.backspace, meta: mac, control: !mac):
          removeSelected,
      const SingleActivator(LogicalKeyboardKey.f2): () => one(_act.rename),
      const SingleActivator(LogicalKeyboardKey.enter): () => one(_act.open),
      const SingleActivator(LogicalKeyboardKey.space): () => one(_act.details),
    };
  }

  /// While the search box has the keyboard: every key types, Escape leaves.
  Map<ShortcutActivator, VoidCallback> get _searchShortcuts => {
    const SingleActivator(LogicalKeyboardKey.escape): () {
      if (_ctrl.searching) _ctrl.setQuery('');
      _focus.requestFocus();
    },
  };

  // ---- build -------------------------------------------------------------------------

  @override
  Widget build(BuildContext context) {
    final cs = ShadTheme.of(context).colorScheme;
    final ready = _account.status == VaultStatus.ready;
    return LayoutBuilder(
      builder: (context, box) =>
          _page(cs, ready, wide: box.maxWidth >= _sidebarMinWidth),
    );
  }

  Widget _page(ShadColorScheme cs, bool ready, {required bool wide}) {
    Widget body;
    if (!ready) {
      body = Column(
        children: [
          AppScreenHeader(title: 'vault.drive'.tr()),
          ?widget.segment,
          Expanded(
            child: _account.status == VaultStatus.signedOut
                ? const _Intro()
                : const _WaitingForKey(),
          ),
        ],
      );
    } else if (wide) {
      body = _wide(cs);
    } else {
      body = _narrow(cs);
    }
    if (_desktop) {
      // A click anywhere on the page gives the shortcuts the keyboard back
      // (the search box takes it again when it is the thing clicked).
      body = Listener(
        onPointerDown: (_) {
          if (!_focus.hasFocus && !_searchFocus.hasFocus) _focus.requestFocus();
        },
        child: body,
      );
    }
    return PopScope(
      // Hidden behind another tab, "back" is not this page's to take.
      canPop:
          !_active ||
          !ready ||
          (!_ctrl.selecting &&
              !_ctrl.searching &&
              _ctrl.path.isEmpty &&
              _ctrl.view == DriveView.files),
      onPopInvokedWithResult: (didPop, _) {
        if (!didPop) _ctrl.up();
      },
      child: Scaffold(
        backgroundColor: cs.background,
        body: SafeArea(
          bottom: false,
          child: CallbackShortcuts(
            bindings: !ready || !_active
                ? const {}
                : _searchFocus.hasFocus
                ? _searchShortcuts
                : _shortcuts,
            child: Focus(focusNode: _focus, autofocus: _desktop, child: body),
          ),
        ),
      ),
    );
  }

  String get _title {
    if (_ctrl.selecting) {
      return 'vault.n_selected'.tr(
        namedArgs: {'count': '${_ctrl.selected.length}'},
      );
    }
    if (_ctrl.searching) return 'vault.search_results'.tr();
    if (_ctrl.path.isNotEmpty) return _ctrl.path.last.name;
    return _ctrl.view == DriveView.files
        ? 'vault.drive'.tr()
        : driveViewLabel(_ctrl.view);
  }

  String? get _subtitle {
    if (_ctrl.selecting) return null;
    if (_ctrl.view == DriveView.trash && !_ctrl.searching) {
      return 'vault.trash_subtitle'.tr();
    }
    final used = _account.usedBytes;
    final quota = _account.quotaBytes;
    if (used == null || quota == null || quota <= 0) return null;
    return 'vault.quota_line'.tr(
      namedArgs: {'used': decimalBytes(used), 'quota': decimalBytes(quota)},
    );
  }

  List<Widget> _headerActions({required bool wide}) {
    if (_ctrl.selecting) {
      return [
        AppIconButton(
          icon: AppIcons.squareCheck,
          onPressed: () => _ctrl.selectAll(_visible),
        ),
        AppIconButton(icon: AppIcons.close, onPressed: _ctrl.clearSelection),
      ];
    }
    return [
      if (_ctrl.canAdd && !wide)
        AppIconButton(
          icon: AppIcons.uploadFile,
          onPressed: () => _act.addMenu(),
        ),
      if (!wide && !_phoneGallery)
        AppIconButton(
          icon: AppIcons.squareCheck,
          onPressed: () {
            if (_visible.isNotEmpty) _ctrl.toggle(_visible.first.id);
          },
        ),
      AppIconButton(icon: AppIcons.moreMenu, onPressed: _pageMenu),
    ];
  }

  Widget _narrow(ShadColorScheme cs) {
    final tab = _tabOf(_ctrl.view);
    return Column(
      children: [
        if (_ctrl.selecting)
          AppScreenHeader(
            title: _title,
            onBack: _ctrl.clearSelection,
            actions: _headerActions(wide: false),
          )
        else
          _phoneHeader(),
        if (!_ctrl.selecting && _ctrl.path.isEmpty) ?widget.segment,
        if (!_ctrl.selecting)
          SizedBox(
            width: double.infinity,
            child: AppTabBar(
              controller: _tabs,
              tabs: [
                AppTab('vault.tab_photos'.tr()),
                AppTab('vault.tab_files'.tr()),
                AppTab(driveViewLabel(DriveView.recent)),
                AppTab(driveViewLabel(DriveView.trash)),
              ],
              onTap: (i) => _ctrl.setView(_tabViews[i]),
            ),
          ),
        if (!_phoneGallery)
          DriveToolbar(
            ctrl: _ctrl,
            search: _search,
            searchFocus: _searchFocus,
            trailing: [
              if (tab == 1 && !_ctrl.selecting)
                AppIconButton(
                  icon: AppIcons.squareCheck,
                  tooltip: 'compose.select'.tr(),
                  onPressed: () {
                    if (_visible.isNotEmpty) _ctrl.toggle(_visible.first.id);
                  },
                ),
            ],
          ),
        if (tab == 1 && _ctrl.path.isEmpty && !_ctrl.searching)
          DriveKindChips(ctrl: _ctrl),
        DriveBreadcrumb(ctrl: _ctrl),
        Expanded(child: _queueAndContent()),
        if (_ctrl.selecting) DriveSelectionBar(actions: _selectionActions()),
      ],
    );
  }

  /// "Drive" with Upload, Account and the page menu; under it, across the
  /// whole width, the quota meter (it opens the account).
  Widget _phoneHeader() {
    final t = context.tokens;
    final used = _account.usedBytes;
    final quota = _account.quotaBytes;
    return Padding(
      padding: const EdgeInsetsDirectional.fromSTEB(18, 8, 8, 4),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Row(
            children: [
              Expanded(
                child: Semantics(
                  header: true,
                  child: Text(
                    'vault.drive'.tr(),
                    style: AppType.title.copyWith(color: t.text),
                  ),
                ),
              ),
              AppIconButton(
                icon: AppIcons.uploadFile,
                tooltip: 'vault.upload'.tr(),
                onPressed: () => _act.addMenu(),
              ),
              AppIconButton(
                icon: AppIcons.user,
                tooltip: 'vault.account_title'.tr(),
                onPressed: () => context.push('/drive-account'),
              ),
              AppIconButton(
                icon: AppIcons.moreMenu,
                tooltip: 'inbox.more'.tr(),
                onPressed: _pageMenu,
              ),
            ],
          ),
          if (used != null && quota != null && quota > 0)
            DriveQuotaLine(
              used: used,
              quota: quota,
              onTap: () => context.push('/drive-account'),
            ),
        ],
      ),
    );
  }

  Widget _wide(ShadColorScheme cs) {
    return Column(
      children: [
        ?widget.segment,
        Expanded(
          child: Row(
            crossAxisAlignment: CrossAxisAlignment.stretch,
            children: [
              ListenableBuilder(
                listenable: Listenable.merge([_downloads, _uploader]),
                builder: (context, _) => DriveSidebar(
                  ctrl: _ctrl,
                  storage: _storageCard(),
                  transfersBusy: _downloads.busy,
                  onTransfers: () => context.push('/drive-transfers'),
                  onAccount: () => context.push('/drive-account'),
                ),
              ),
              VerticalDivider(width: 1, color: cs.border),
              Expanded(
                child: Column(
                  children: [
                    AppScreenHeader(
                      title: _title,
                      subtitle: _subtitle,
                      actions: [
                        if (_ctrl.canAdd && !_ctrl.selecting) ...[
                          ShadButton.outline(
                            size: ShadButtonSize.sm,
                            onPressed: () => _act.newFolder(),
                            leading: const AppSvgIcon(
                              AppIcons.newFolder,
                              size: 15,
                            ),
                            child: Text('vault.new_folder'.tr()),
                          ),
                          const SizedBox(width: 8),
                          ShadButton(
                            size: ShadButtonSize.sm,
                            onPressed: () => _act.addMenu(),
                            leading: const AppSvgIcon(
                              AppIcons.uploadFile,
                              size: 15,
                              color: Colors.white,
                            ),
                            child: Text('vault.upload'.tr()),
                          ),
                          const SizedBox(width: 4),
                        ],
                        ..._headerActions(wide: true),
                      ],
                    ),
                    if (!_phoneGallery) ...[
                      DriveBreadcrumb(ctrl: _ctrl),
                      DriveToolbar(
                        ctrl: _ctrl,
                        search: _search,
                        searchFocus: _searchFocus,
                      ),
                    ],
                    Expanded(child: _queueAndContent()),
                    if (_ctrl.selecting)
                      DriveSelectionBar(actions: _selectionActions()),
                  ],
                ),
              ),
            ],
          ),
        ),
      ],
    );
  }

  Widget _storageCard() => StreamBuilder<List<VaultObject>>(
    stream: _live,
    builder: (context, live) => StreamBuilder<List<VaultObject>>(
      stream: _trash,
      builder: (context, trash) => ListenableBuilder(
        listenable: _account,
        builder: (context, _) => DriveStorageCard(
          used: _account.usedBytes,
          quota: _account.quotaBytes,
          byKind: storageByKind(live.data ?? const [], trash.data ?? const []),
          onTap: () => context.push('/drive-storage'),
        ),
      ),
    ),
  );

  Widget _queueAndContent() {
    Widget content = Column(
      children: [
        DrivePlanNotice(account: _account),
        _UploadStrip(uploader: _uploader, transfers: _transfers),
        Expanded(
          child: _phoneGallery
              ? DriveGalleryView(
                  backup: _photos!,
                  dao: _dao,
                  onOpen: (o) => unawaited(_act.open(o)),
                  onMore: _more,
                )
              : _content(),
        ),
      ],
    );
    if (_desktop) {
      content = DropTarget(
        // Every tab is laid out at once: only the one on screen takes drops.
        enable: _active,
        onDragEntered: (_) => setState(() => _dragging = true),
        onDragExited: (_) => setState(() => _dragging = false),
        onDragDone: (d) {
          setState(() => _dragging = false);
          unawaited(_act.dropped([for (final f in d.files) f.path]));
        },
        child: Stack(
          children: [
            content,
            if (_dragging)
              _DropHint(
                text: _ctrl.canAdd
                    ? 'vault.drop_here'.tr(
                        namedArgs: {
                          'folder': _ctrl.path.isEmpty
                              ? 'vault.drive'.tr()
                              : _ctrl.path.last.name,
                        },
                      )
                    : 'vault.drop_only_in_folders'.tr(),
              ),
          ],
        ),
      );
    }
    return content;
  }

  Widget _content() {
    return StreamBuilder<List<VaultObject>>(
      stream: _itemsStream(),
      builder: (context, snap) {
        if (!snap.hasData) {
          return const Center(child: CircularProgressIndicator());
        }
        final items = snap.data!;
        _visible = items;
        WidgetsBinding.instance.addPostFrameCallback((_) {
          if (mounted) _ctrl.keepSelected(items.map((o) => o.id));
        });
        if (items.isEmpty) {
          return RefreshIndicator(onRefresh: _refresh, child: _empty());
        }
        return StreamBuilder<Map<String?, int>>(
          stream: _counts,
          builder: (context, counts) {
            final c = counts.data ?? const <String?, int>{};
            unawaited(_loadFolderNames(c));
            return RefreshIndicator(
              onRefresh: _refresh,
              child: _ctrl.grid ? _grid(items, c) : _list(items, c),
            );
          },
        );
      },
    );
  }

  Map<String?, int>? _namesFor;

  /// Folder names for the "where is it" line of Search and the views.
  Future<void> _loadFolderNames(Map<String?, int> counts) async {
    if (identical(counts, _namesFor)) return;
    _namesFor = counts;
    final names = {for (final f in await _dao.liveFolders()) f.id: f.name};
    if (mounted) setState(() => _folderNames = names);
  }

  String? _location(VaultObject o) {
    if (_ctrl.view == DriveView.files && !_ctrl.searching) return null;
    final trashed = o.trashedAt;
    if (_ctrl.view == DriveView.trash && trashed != null) {
      // The server purges the trash 30 days after each item went in.
      final left =
          30 -
          DateTime.now()
              .difference(DateTime.fromMillisecondsSinceEpoch(trashed))
              .inDays;
      return 'vault.days_left'.plural(left.clamp(0, 30));
    }
    return o.parent == null
        ? 'vault.drive'.tr()
        : (_folderNames[o.parent] ?? '…');
  }

  Widget _row(VaultObject o, Map<String?, int> counts) {
    final row = DriveListRow(
      object: o,
      selected: _ctrl.isSelected(o.id),
      selecting: _ctrl.selecting,
      items: o.kind == 'dir' ? (counts[o.id] ?? 0) : null,
      location: _location(o),
      onTap: () => _tap(o),
      onLongPress: () => _longPress(o),
      onMore: () => _more(o),
    );
    return context.isWideLayout
        ? AppRowMenu(title: o.name, actions: _itemActions(o), child: row)
        : row;
  }

  /// Flat rows, as in the Inbox: a hairline between them past the thumb.
  Widget _list(List<VaultObject> items, Map<String?, int> counts) {
    return CustomScrollView(
      physics: const AlwaysScrollableScrollPhysics(),
      slivers: [
        SliverPadding(
          padding: const EdgeInsets.only(top: 2, bottom: 120),
          sliver: SliverList.builder(
            itemCount: items.length,
            itemBuilder: (context, i) => Column(
              mainAxisSize: MainAxisSize.min,
              children: [
                if (i > 0) const AppRowDivider(indent: 70),
                _row(items[i], counts),
              ],
            ),
          ),
        ),
      ],
    );
  }

  Widget _grid(List<VaultObject> items, Map<String?, int> counts) {
    // Only photos and videos (a camera folder, the Photos view): a gallery,
    // picture to picture. Anything else keeps its name on a card.
    if (items.every((o) => o.kind == 'file' && isMedia(o.mime))) {
      return _gallery(items);
    }
    return GridView.builder(
      physics: const AlwaysScrollableScrollPhysics(),
      padding: const EdgeInsets.fromLTRB(10, 2, 10, 24),
      gridDelegate: SliverGridDelegateWithMaxCrossAxisExtent(
        maxCrossAxisExtent: context.isWideLayout ? 160 : 140,
        mainAxisSpacing: 8,
        crossAxisSpacing: 8,
        childAspectRatio: 0.84,
      ),
      itemCount: items.length,
      itemBuilder: (context, i) {
        final o = items[i];
        final card = DriveGridCard(
          object: o,
          selected: _ctrl.isSelected(o.id),
          selecting: _ctrl.selecting,
          items: o.kind == 'dir' ? (counts[o.id] ?? 0) : null,
          onTap: () => _tap(o),
          onLongPress: () => _longPress(o),
          onMore: () => _more(o),
        );
        return context.isWideLayout
            ? AppRowMenu(title: o.name, actions: _itemActions(o), child: card)
            : card;
      },
    );
  }

  Widget _gallery(List<VaultObject> items) {
    return GridView.builder(
      physics: const AlwaysScrollableScrollPhysics(),
      padding: const EdgeInsets.fromLTRB(3, 2, 3, 24),
      gridDelegate: SliverGridDelegateWithMaxCrossAxisExtent(
        maxCrossAxisExtent: context.isWideLayout ? 170 : 128,
        mainAxisSpacing: 3,
        crossAxisSpacing: 3,
      ),
      itemCount: items.length,
      itemBuilder: (context, i) {
        final o = items[i];
        final tile = DriveMediaTile(
          image: LayoutBuilder(
            builder: (context, c) {
              final side = c.biggest.shortestSide;
              return o.hasThumb
                  ? DriveThumb(object: o, size: side, radius: 0)
                  : Center(
                      child: DriveThumb(object: o, size: side * 0.4),
                    );
            },
          ),
          video: (o.mime ?? '').startsWith('video/'),
          selected: _ctrl.isSelected(o.id),
          selecting: _ctrl.selecting,
          onTap: () => _tap(o),
          onLongPress: () => _longPress(o),
          label: o.name,
        );
        return context.isWideLayout
            ? AppRowMenu(title: o.name, actions: _itemActions(o), child: tile)
            : tile;
      },
    );
  }

  Widget _empty() {
    final (icon, title, body) = _ctrl.searching
        ? (
            AppIcons.search,
            'vault.search_none'.tr(namedArgs: {'q': _ctrl.query.trim()}),
            'vault.search_none_body'.tr(),
          )
        : switch (_ctrl.view) {
            DriveView.files when _ctrl.path.isNotEmpty => (
              AppIcons.folderOpen,
              'vault.empty_folder_title'.tr(),
              'vault.empty_body'.tr(),
            ),
            DriveView.files => (
              AppIcons.folderOpen,
              'vault.empty_title'.tr(),
              'vault.empty_body'.tr(),
            ),
            DriveView.recent => (
              AppIcons.clock,
              'vault.empty_recent'.tr(),
              'vault.empty_view_body'.tr(),
            ),
            DriveView.media => (
              AppIcons.image,
              'vault.empty_media'.tr(),
              'vault.empty_view_body'.tr(),
            ),
            DriveView.documents => (
              AppIcons.fileDocument,
              'vault.empty_documents'.tr(),
              'vault.empty_view_body'.tr(),
            ),
            DriveView.audio => (
              AppIcons.fileAudio,
              'vault.empty_audio'.tr(),
              'vault.empty_view_body'.tr(),
            ),
            DriveView.trash => (
              AppIcons.trashDelete,
              'vault.trash_empty_title'.tr(),
              'vault.trash_empty_body'.tr(),
            ),
          };
    return ListView(
      physics: const AlwaysScrollableScrollPhysics(),
      children: [
        SizedBox(
          height: 360,
          child: AppEmptyState(icon: icon, title: title, message: body),
        ),
        if (_ctrl.canAdd)
          Center(
            child: ShadButton.outline(
              onPressed: () => _act.addMenu(),
              leading: const AppSvgIcon(AppIcons.uploadFile, size: 15),
              child: Text('vault.upload'.tr()),
            ),
          ),
      ],
    );
  }
}

/// Stored bytes by kind, each stored blob counted once, for the storage
/// bar. Trash counts only blobs no live file still uses.
Map<String, int> storageByKind(
  List<VaultObject> live,
  List<VaultObject> trash,
) {
  final out = <String, int>{
    'media': 0,
    'documents': 0,
    'audio': 0,
    'other': 0,
    'trash': 0,
  };
  final seen = <String>{};
  for (final o in live) {
    final blob = o.blobId;
    if (o.kind != 'file' || blob == null || !seen.add(blob)) continue;
    final mime = o.mime ?? '';
    final kind = isMedia(mime)
        ? 'media'
        : mime.startsWith('audio/')
        ? 'audio'
        : mime.startsWith('text/') || driveDocumentTypes.contains(mime)
        ? 'documents'
        : 'other';
    out[kind] = out[kind]! + (o.blobSize ?? 0);
  }
  for (final o in trash) {
    final blob = o.blobId;
    if (o.kind != 'file' || blob == null || !seen.add(blob)) continue;
    out['trash'] = out['trash']! + (o.blobSize ?? 0);
  }
  return out;
}

/// The uploads still going, above the files.
class _UploadStrip extends StatefulWidget {
  const _UploadStrip({required this.uploader, required this.transfers});

  final VaultUploader uploader;
  final Stream<List<VaultTransfer>> transfers;

  @override
  State<_UploadStrip> createState() => _UploadStripState();
}

class _UploadStripState extends State<_UploadStrip> {
  final OneWayProgress _bar = OneWayProgress();

  @override
  Widget build(BuildContext context) {
    final cs = ShadTheme.of(context).colorScheme;
    return StreamBuilder<List<VaultTransfer>>(
      stream: widget.transfers,
      builder: (context, snap) {
        final all = snap.data ?? const <VaultTransfer>[];
        return ListenableBuilder(
          listenable: widget.uploader,
          builder: (context, _) {
            final batch = UploadBatch.of(all, widget.uploader);
            final bar = _bar.of(batch);
            if (batch == null) return const SizedBox.shrink();
            final running = batch.running;
            final failed = batch.stopped;
            final now = batch.current;
            final label = running.isEmpty
                ? 'vault.uploads_stopped'.plural(failed)
                : 'vault.uploading_n'.plural(running.length);
            return InkWell(
              onTap: () => context.push('/drive-transfers'),
              child: Container(
                margin: const EdgeInsets.fromLTRB(14, 2, 14, 8),
                padding: const EdgeInsets.fromLTRB(12, 10, 12, 10),
                decoration: BoxDecoration(
                  color: cs.card,
                  borderRadius: BorderRadius.circular(14),
                  border: Border.all(
                    color: failed > 0 && running.isEmpty
                        ? cs.destructive
                        : cs.border,
                  ),
                ),
                child: Row(
                  children: [
                    AppSvgIcon(
                      AppIcons.uploadFile,
                      size: 18,
                      color: cs.primary,
                    ),
                    const SizedBox(width: 10),
                    Expanded(
                      child: Column(
                        crossAxisAlignment: CrossAxisAlignment.start,
                        children: [
                          Text(
                            now == null ? label : '$label · ${now.name}',
                            maxLines: 1,
                            overflow: TextOverflow.ellipsis,
                            style: TextStyle(
                              fontSize: 13,
                              fontWeight: FontWeight.w600,
                              color: cs.foreground,
                            ),
                          ),
                          if (running.isNotEmpty) ...[
                            const SizedBox(height: 6),
                            LinearProgressIndicator(value: bar, minHeight: 3),
                          ],
                        ],
                      ),
                    ),
                    const SizedBox(width: 6),
                    AppSvgIcon(
                      AppIcons.chevronRight,
                      size: 16,
                      color: cs.mutedForeground,
                    ),
                  ],
                ),
              ),
            );
          },
        );
      },
    );
  }
}

class _DropHint extends StatelessWidget {
  const _DropHint({required this.text});
  final String text;

  @override
  Widget build(BuildContext context) {
    final cs = ShadTheme.of(context).colorScheme;
    return Positioned.fill(
      child: IgnorePointer(
        child: Container(
          margin: const EdgeInsets.all(10),
          decoration: BoxDecoration(
            color: cs.primary.withValues(alpha: 0.08),
            borderRadius: BorderRadius.circular(18),
            border: Border.all(color: cs.primary, width: 2),
          ),
          alignment: Alignment.center,
          padding: const EdgeInsets.all(24),
          child: Text(
            text,
            textAlign: TextAlign.center,
            style: TextStyle(
              fontSize: 16,
              fontWeight: FontWeight.w600,
              color: cs.primary,
            ),
          ),
        ),
      ),
    );
  }
}

/// Signed out: what Drive is, and the sign-in buttons.
class _Intro extends StatelessWidget {
  const _Intro();

  @override
  Widget build(BuildContext context) {
    final theme = ShadTheme.of(context);
    return ListView(
      padding: const EdgeInsets.fromLTRB(24, 32, 24, 28),
      children: [
        const Center(child: Glyph(AppIcons.passwordLock)),
        const SizedBox(height: 16),
        Text(
          'vault.intro_title'.tr(),
          textAlign: TextAlign.center,
          style: theme.textTheme.h4,
        ),
        const SizedBox(height: 8),
        Text(
          'vault.intro_body'.tr(),
          textAlign: TextAlign.center,
          style: theme.textTheme.muted,
        ),
        const SizedBox(height: 18),
        Center(
          child: ConstrainedBox(
            constraints: const BoxConstraints(maxWidth: 360),
            child: const VaultSignInButtons(),
          ),
        ),
      ],
    );
  }
}

/// Signed in, but the key is not on this device yet.
class _WaitingForKey extends StatelessWidget {
  const _WaitingForKey();

  @override
  Widget build(BuildContext context) {
    final theme = ShadTheme.of(context);
    return ListView(
      padding: const EdgeInsets.fromLTRB(24, 32, 24, 28),
      children: [
        const Center(child: Glyph(AppIcons.passwordLock)),
        const SizedBox(height: 16),
        Text(
          'vault.needs_key'.tr(),
          textAlign: TextAlign.center,
          style: theme.textTheme.muted,
        ),
        const SizedBox(height: 18),
        Center(
          child: ConstrainedBox(
            constraints: const BoxConstraints(maxWidth: 360),
            child: AppButton(
              label: 'vault.get_key'.tr(),
              fullWidth: true,
              onPressed: () => context.push('/drive-account'),
            ),
          ),
        ),
      ],
    );
  }
}
