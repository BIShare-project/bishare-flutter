import 'dart:async';
import 'dart:collection';
import 'dart:typed_data';

import 'package:easy_localization/easy_localization.dart';
import 'package:flutter/material.dart';
import 'package:mime/mime.dart';
import 'package:shadcn_ui/shadcn_ui.dart';

import '../../../../core/storage/app_database.dart';
import '../../../../core/storage/vault_tables.dart';
import '../../../../core/ui/app_ui.dart';
import '../../data/vault_photo_backup.dart';
import '../../data/vault_photo_library.dart';
import 'drive_widgets.dart';

/// One picture of the gallery: on this phone, or only in the Drive.
sealed class _Item {
  int get at;
}

class _Local extends _Item {
  _Local(this.asset);
  final PhotoAsset asset;
  @override
  int get at => asset.taken.millisecondsSinceEpoch;
}

class _Remote extends _Item {
  _Remote(this.object);
  final VaultObject object;
  @override
  int get at => object.mtime;
}

/// Photos and videos on a phone (drive-plan.md task 5.8, owner 2026-10-21:
/// "buat drive UI nya seperti galery ... ada icon cloud di setiap foto atau
/// video"): the phone's own library and the Drive's photos from other
/// devices in one timeline, newest first. Every photo of the phone has a
/// cloud on it: crossed out until it is in the Drive, in the theme colour
/// once it is. The backup switch and "Wi-Fi only" sit on top; chosen photos
/// go up at once with "Back up now".
class DriveGalleryView extends StatefulWidget {
  const DriveGalleryView({
    super.key,
    required this.backup,
    required this.dao,
    required this.onOpen,
    required this.onMore,
  });

  final VaultPhotoBackup backup;
  final VaultDao dao;

  /// A photo that is only in the Drive: open it, or its actions.
  final void Function(VaultObject) onOpen;
  final void Function(VaultObject) onMore;

  @override
  State<DriveGalleryView> createState() => _DriveGalleryViewState();
}

class _DriveGalleryViewState extends State<DriveGalleryView> {
  static const _pageSize = 120;

  VaultPhotoBackup get _backup => widget.backup;
  PhotoLibrary get _library => widget.backup.library;

  final List<PhotoAsset> _assets = [];
  final Set<String> _selected = {};
  final ScrollController _scroll = ScrollController();
  late final Stream<Map<String, String>> _backed = widget.dao
      .watchBackedUpAssets();
  late final Stream<Map<String, String>> _uploads = widget.dao
      .watchAssetUploads();
  late final Stream<List<VaultObject>> _drive = widget.dao.watchFilesOfType(
    prefixes: ['image/', 'video/'],
  );
  StreamSubscription<void>? _changes;
  AppLifecycleListener? _lifecycle;

  /// Pages read so far; null before the first read (and after access went).
  int? _pages;
  bool _end = false;
  bool _loading = false;
  PhotoAccess? _shownFor;

  /// Thumbnails, the most recent few hundred (a gallery scrolls a lot).
  final LinkedHashMap<String, Future<Uint8List?>> _thumbs = LinkedHashMap();

  @override
  void initState() {
    super.initState();
    _backup.addListener(_onBackup);
    _scroll.addListener(_onScroll);
    _changes = _library.changes.listen((_) => unawaited(_reload()));
    // Back from the system settings: the access may be different now.
    _lifecycle = AppLifecycleListener(
      onResume: () => unawaited(_backup.refreshAccess()),
    );
    _shownFor = _backup.access;
    unawaited(_reload());
    unawaited(_backup.refreshAccess());
  }

  @override
  void dispose() {
    _backup.removeListener(_onBackup);
    _scroll.dispose();
    unawaited(_changes?.cancel());
    _lifecycle?.dispose();
    super.dispose();
  }

  void _onBackup() {
    if (!mounted) return;
    if (_backup.access != _shownFor) {
      _shownFor = _backup.access;
      unawaited(_reload());
    }
    setState(() {});
  }

  void _onScroll() {
    if (_scroll.position.extentAfter < 900) unawaited(_more());
  }

  /// The pages read so far again (the library changed, or the access).
  Future<void> _reload() async {
    if (_backup.access == PhotoAccess.none) {
      if (!mounted) return;
      setState(() {
        _assets.clear();
        _selected.clear();
        _pages = null;
        _end = false;
      });
      return;
    }
    final pages = (_pages ?? 1).clamp(1, 1000);
    final fresh = <PhotoAsset>[];
    var end = false;
    try {
      for (var p = 0; p < pages; p++) {
        final page = await _library.page(p, _pageSize);
        fresh.addAll(page);
        if (page.length < _pageSize) {
          end = true;
          break;
        }
      }
    } on Object catch (e) {
      debugPrint('[vault] photo library: $e');
      end = true;
    }
    if (!mounted) return;
    final ids = {for (final a in fresh) a.id};
    setState(() {
      _assets
        ..clear()
        ..addAll(fresh);
      _selected.retainAll(ids);
      _pages = pages;
      _end = end;
    });
  }

  Future<void> _more() async {
    final pages = _pages;
    if (_loading || _end || pages == null) return;
    _loading = true;
    try {
      final page = await _library.page(pages, _pageSize);
      if (!mounted) return;
      setState(() {
        _assets.addAll(page);
        _pages = pages + 1;
        _end = page.length < _pageSize;
      });
    } finally {
      _loading = false;
    }
  }

  /// The phone's pictures and the Drive's others, newest first. While the
  /// library is still being paged, Drive pictures older than the last one
  /// read wait for the next page, so the two stay in date order.
  List<_Item> _timeline(List<VaultObject> drive, Set<String> onPhone) {
    final remote = [
      for (final o in drive)
        if (o.hash == null || !onPhone.contains(o.hash)) o,
    ]..sort((a, b) => b.mtime.compareTo(a.mtime));
    final all = _end || _assets.isEmpty;
    final oldest = all ? null : _assets.last.taken.millisecondsSinceEpoch;
    final out = <_Item>[];
    var r = 0;
    for (final a in _assets) {
      final at = a.taken.millisecondsSinceEpoch;
      while (r < remote.length && remote[r].mtime > at) {
        out.add(_Remote(remote[r++]));
      }
      out.add(_Local(a));
    }
    while (r < remote.length && (oldest == null || remote[r].mtime >= oldest)) {
      out.add(_Remote(remote[r++]));
    }
    return out;
  }

  Future<Uint8List?> _thumb(PhotoAsset a) {
    final had = _thumbs.remove(a.id);
    final f = had ?? _library.thumbnail(a, 240);
    _thumbs[a.id] = f;
    if (_thumbs.length > 400) _thumbs.remove(_thumbs.keys.first);
    return f;
  }

  void _toggle(PhotoAsset a) {
    tapHaptic();
    setState(() {
      _selected.contains(a.id) ? _selected.remove(a.id) : _selected.add(a.id);
    });
  }

  /// A photo of the phone, full screen.
  Future<void> _view(PhotoAsset a) async {
    final got = await _library.original(a);
    if (got == null || !mounted) return;
    await showFilePreview(
      context,
      path: got.file.path,
      name: got.name,
      mimeType:
          lookupMimeType(got.name) ?? (a.video ? 'video/mp4' : 'image/jpeg'),
    );
  }

  Future<void> _backUpChosen(Set<String> backed) async {
    final chosen = [
      for (final a in _assets)
        if (_selected.contains(a.id) && !backed.contains(a.id)) a,
    ];
    setState(_selected.clear);
    if (chosen.isEmpty) {
      toast(context, 'vault.backup_all_there'.tr());
      return;
    }
    try {
      await _backup.backUp(chosen);
      if (mounted) toast(context, 'vault.backup_added_n'.plural(chosen.length));
    } on Object catch (e) {
      debugPrint('[vault] back up now: $e');
      if (mounted) {
        toast(context, 'vault.error_failed'.tr(), type: ToastType.error);
      }
    }
  }

  Future<void> _switch(bool on) async {
    final ok = await _backup.setOn(on);
    if (!ok && mounted) {
      toast(context, 'vault.backup_access_denied'.tr(), type: ToastType.error);
    }
  }

  @override
  Widget build(BuildContext context) {
    return StreamBuilder<Map<String, String>>(
      stream: _backed,
      builder: (context, backedSnap) => StreamBuilder<Map<String, String>>(
        stream: _uploads,
        builder: (context, uploadsSnap) => StreamBuilder<List<VaultObject>>(
          stream: _drive,
          builder: (context, driveSnap) {
            final backed = backedSnap.data ?? const <String, String>{};
            final uploads = uploadsSnap.data ?? const <String, String>{};
            final ids = backed.keys.toSet();
            final items = _timeline(
              driveSnap.data ?? const [],
              backed.values.toSet(),
            );
            return PopScope(
              canPop: _selected.isEmpty,
              onPopInvokedWithResult: (didPop, _) {
                if (!didPop) setState(_selected.clear);
              },
              child: Column(
                children: [
                  Expanded(child: _body(items, ids, uploads)),
                  if (_selected.isNotEmpty)
                    DriveSelectionBar(
                      actions: [
                        (
                          AppIcons.cloudSync,
                          'vault.backup_now'.tr(),
                          () => unawaited(_backUpChosen(ids)),
                          false,
                        ),
                        (
                          AppIcons.close,
                          'vault.cancel'.tr(),
                          () => setState(_selected.clear),
                          false,
                        ),
                      ],
                    ),
                ],
              ),
            );
          },
        ),
      ),
    );
  }

  Widget _body(
    List<_Item> items,
    Set<String> backed,
    Map<String, String> uploads,
  ) {
    final noAccess = _backup.access == PhotoAccess.none;
    final waiting = !noAccess && _pages == null;
    return CustomScrollView(
      controller: _scroll,
      physics: const AlwaysScrollableScrollPhysics(),
      slivers: [
        SliverToBoxAdapter(
          child: noAccess
              ? _AccessCard(backup: _backup)
              : _BackupCard(backup: _backup, onSwitch: _switch),
        ),
        if (waiting)
          const SliverToBoxAdapter(
            child: Padding(
              padding: EdgeInsets.all(32),
              child: Center(child: CircularProgressIndicator()),
            ),
          )
        else if (items.isEmpty)
          SliverToBoxAdapter(
            child: AppEmptyState(
              icon: AppIcons.image,
              title: 'vault.backup_empty'.tr(),
              message: 'vault.backup_empty_body'.tr(),
            ),
          )
        else
          SliverPadding(
            padding: const EdgeInsets.fromLTRB(3, 2, 3, 24),
            sliver: SliverGrid.builder(
              gridDelegate: SliverGridDelegateWithMaxCrossAxisExtent(
                maxCrossAxisExtent: context.isWideLayout ? 170 : 128,
                mainAxisSpacing: 3,
                crossAxisSpacing: 3,
              ),
              itemCount: items.length,
              itemBuilder: (context, i) => switch (items[i]) {
                _Local(:final asset) => _localTile(asset, backed, uploads),
                _Remote(:final object) => _remoteTile(object),
              },
            ),
          ),
      ],
    );
  }

  Widget _localTile(
    PhotoAsset a,
    Set<String> backed,
    Map<String, String> uploads,
  ) {
    final state = VaultPhotoBackup.stateOf(a.id, backed, uploads);
    final selecting = _selected.isNotEmpty;
    return DriveMediaTile(
      image: _Thumb(future: _thumb(a)),
      video: a.video,
      durationS: a.video ? a.durationS : null,
      selected: _selected.contains(a.id),
      selecting: selecting,
      onTap: () => selecting ? _toggle(a) : unawaited(_view(a)),
      onLongPress: () => _toggle(a),
      badge: PhotoBackupBadge(state: state),
      label: photoBackupStateLabel(state),
    );
  }

  /// A Drive photo from another device: in the cloud, not on this phone.
  Widget _remoteTile(VaultObject o) {
    return DriveMediaTile(
      image: LayoutBuilder(
        builder: (context, c) => o.hasThumb
            ? DriveThumb(object: o, size: c.biggest.shortestSide, radius: 0)
            : Center(
                child: DriveThumb(
                  object: o,
                  size: c.biggest.shortestSide * 0.4,
                ),
              ),
      ),
      video: (o.mime ?? '').startsWith('video/'),
      selected: false,
      selecting: false,
      onTap: () {
        if (_selected.isEmpty) widget.onOpen(o);
      },
      onLongPress: () => widget.onMore(o),
      badge: const PhotoBackupBadge(state: PhotoBackupState.backedUp),
      label: o.name,
    );
  }
}

class _Thumb extends StatelessWidget {
  const _Thumb({required this.future});

  final Future<Uint8List?> future;

  @override
  Widget build(BuildContext context) => FutureBuilder<Uint8List?>(
    future: future,
    builder: (context, snap) {
      final jpeg = snap.data;
      if (jpeg == null) return const SizedBox.expand();
      return Image.memory(
        jpeg,
        fit: BoxFit.cover,
        gaplessPlayback: true,
        width: double.infinity,
        height: double.infinity,
      );
    },
  );
}

/// The cloud on a photo: crossed out until it is in the Drive, in the
/// theme's colour once it is.
class PhotoBackupBadge extends StatelessWidget {
  const PhotoBackupBadge({super.key, required this.state});

  final PhotoBackupState state;

  @override
  Widget build(BuildContext context) {
    final cs = ShadTheme.of(context).colorScheme;
    final Widget icon = switch (state) {
      PhotoBackupState.backedUp => AppSvgIcon(
        AppIcons.cloudDone,
        size: 14,
        color: cs.primary,
      ),
      PhotoBackupState.notBackedUp => const AppSvgIcon(
        AppIcons.cloudOff,
        size: 14,
        color: Colors.white,
      ),
      PhotoBackupState.waiting => const AppSvgIcon(
        AppIcons.cloudSync,
        size: 14,
        color: Colors.white,
      ),
      PhotoBackupState.uploading => const SizedBox(
        width: 12,
        height: 12,
        child: CircularProgressIndicator(strokeWidth: 1.8, color: Colors.white),
      ),
      PhotoBackupState.failed => AppSvgIcon(
        AppIcons.circleAlert,
        size: 14,
        color: cs.destructive,
      ),
    };
    return Container(
      width: 22,
      height: 22,
      alignment: Alignment.center,
      decoration: BoxDecoration(
        color: state == PhotoBackupState.backedUp
            ? Colors.white.withValues(alpha: 0.92)
            : Colors.black.withValues(alpha: 0.45),
        shape: BoxShape.circle,
      ),
      child: icon,
    );
  }
}

String photoBackupStateLabel(PhotoBackupState s) => switch (s) {
  PhotoBackupState.backedUp => 'vault.backup_state_done',
  PhotoBackupState.notBackedUp => 'vault.backup_state_not',
  PhotoBackupState.waiting => 'vault.backup_state_waiting',
  PhotoBackupState.uploading => 'vault.backup_state_uploading',
  PhotoBackupState.failed => 'vault.backup_state_failed',
}.tr();

/// No access to the library yet (or it was refused): what backup does, and
/// the way to allow it.
class _AccessCard extends StatelessWidget {
  const _AccessCard({required this.backup});

  final VaultPhotoBackup backup;

  @override
  Widget build(BuildContext context) {
    final cs = ShadTheme.of(context).colorScheme;
    return AppCard(
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Row(
            children: [
              AppSvgIcon(AppIcons.image, size: 20, color: cs.primary),
              const SizedBox(width: 10),
              Expanded(
                child: Text(
                  'vault.backup_access_title'.tr(),
                  style: TextStyle(
                    fontSize: 15,
                    fontWeight: FontWeight.w700,
                    color: cs.foreground,
                  ),
                ),
              ),
            ],
          ),
          const SizedBox(height: 8),
          Text(
            'vault.backup_access_body'.tr(),
            style: TextStyle(
              fontSize: 13,
              height: 1.4,
              color: cs.mutedForeground,
            ),
          ),
          const SizedBox(height: 12),
          Wrap(
            spacing: 8,
            runSpacing: 8,
            children: [
              ShadButton(
                size: ShadButtonSize.sm,
                onPressed: () => unawaited(backup.refreshAccess(ask: true)),
                child: Text('vault.backup_allow'.tr()),
              ),
              ShadButton.outline(
                size: ShadButtonSize.sm,
                onPressed: () => unawaited(backup.library.openSettings()),
                child: Text('vault.backup_open_settings'.tr()),
              ),
            ],
          ),
        ],
      ),
    );
  }
}

/// The switch, "Wi-Fi only", and how much is left.
class _BackupCard extends StatelessWidget {
  const _BackupCard({required this.backup, required this.onSwitch});

  final VaultPhotoBackup backup;
  final Future<void> Function(bool) onSwitch;

  String get _status {
    if (!backup.on) {
      return 'vault.backup_off_body'.tr(
        namedArgs: {'folder': 'vault.backup_folder'.tr()},
      );
    }
    final left = backup.left;
    if (left == null) return 'vault.backup_counting'.tr();
    return 'vault.backup_left'.plural(left);
  }

  @override
  Widget build(BuildContext context) {
    final cs = ShadTheme.of(context).colorScheme;
    final muted = TextStyle(
      fontSize: 12.5,
      height: 1.35,
      color: cs.mutedForeground,
    );
    return AppCard(
      margin: const EdgeInsets.fromLTRB(14, 4, 14, 8),
      padding: const EdgeInsets.fromLTRB(14, 12, 10, 10),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Row(
            children: [
              AppSvgIcon(
                backup.on ? AppIcons.cloudDone : AppIcons.cloudOff,
                size: 20,
                color: backup.on ? cs.primary : cs.mutedForeground,
              ),
              const SizedBox(width: 10),
              Expanded(
                child: Column(
                  crossAxisAlignment: CrossAxisAlignment.start,
                  children: [
                    Text(
                      'vault.backup_title'.tr(),
                      style: TextStyle(
                        fontSize: 14.5,
                        fontWeight: FontWeight.w700,
                        color: cs.foreground,
                      ),
                    ),
                    const SizedBox(height: 2),
                    Text(_status, style: muted),
                  ],
                ),
              ),
              if (backup.scanning && backup.on)
                const Padding(
                  padding: EdgeInsets.only(right: 8),
                  child: SizedBox(
                    width: 14,
                    height: 14,
                    child: CircularProgressIndicator(strokeWidth: 2),
                  ),
                ),
              ShadSwitch(
                value: backup.on,
                onChanged: (v) => unawaited(onSwitch(v)),
              ),
            ],
          ),
          if (backup.on) ...[
            const SizedBox(height: 10),
            Divider(height: 1, color: cs.border),
            const SizedBox(height: 8),
            Row(
              children: [
                AppSvgIcon(AppIcons.wifi, size: 18, color: cs.mutedForeground),
                const SizedBox(width: 12),
                Expanded(
                  child: Column(
                    crossAxisAlignment: CrossAxisAlignment.start,
                    children: [
                      Text(
                        'vault.backup_wifi_only'.tr(),
                        style: TextStyle(
                          fontSize: 13.5,
                          fontWeight: FontWeight.w600,
                          color: cs.foreground,
                        ),
                      ),
                      Text('vault.backup_wifi_only_body'.tr(), style: muted),
                    ],
                  ),
                ),
                ShadSwitch(
                  value: backup.wifiOnly,
                  onChanged: (v) => unawaited(backup.setWifiOnly(v)),
                ),
              ],
            ),
          ],
          if (backup.access == PhotoAccess.limited) ...[
            const SizedBox(height: 8),
            Divider(height: 1, color: cs.border),
            const SizedBox(height: 6),
            Row(
              children: [
                Expanded(
                  child: Text('vault.backup_limited'.tr(), style: muted),
                ),
                ShadButton.ghost(
                  size: ShadButtonSize.sm,
                  onPressed: () => unawaited(backup.library.chooseMore()),
                  child: Text('vault.backup_choose_more'.tr()),
                ),
              ],
            ),
          ],
        ],
      ),
    );
  }
}
