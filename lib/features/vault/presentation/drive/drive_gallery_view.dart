import 'dart:async';
import 'dart:collection';
import 'dart:typed_data';

import 'package:easy_localization/easy_localization.dart';
import 'package:flutter/material.dart';
import 'package:mime/mime.dart';

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
    required this.onLink,
    required this.onSend,
  });

  final VaultPhotoBackup backup;
  final VaultDao dao;

  /// A photo that is only in the Drive: open it, or its actions.
  final void Function(VaultObject) onOpen;
  final void Function(VaultObject) onMore;

  /// From the viewer of a phone photo: its Drive copy as a link, or the
  /// photo to the Send tab.
  final void Function(VaultObject) onLink;
  final void Function(String path) onSend;

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
    // Backed up: its Drive copy can go out as a link. Not yet: back it up now.
    final hash = _backedHashes[a.id];
    final copy = hash == null ? null : await widget.dao.liveFileWithHash(hash);
    if (!mounted) return;
    await showFilePreview(
      context,
      path: got.file.path,
      name: got.name,
      mimeType:
          lookupMimeType(got.name) ?? (a.video ? 'video/mp4' : 'image/jpeg'),
      actions: [
        if (copy != null)
          PreviewAction(
            icon: AppIcons.linkCopy,
            label: 'vault.share_link'.tr(),
            onTap: () => widget.onLink(copy),
          )
        else
          PreviewAction(
            icon: AppIcons.cloudSync,
            label: 'vault.backup_now'.tr(),
            onTap: () => unawaited(_backUpOne(a)),
          ),
        PreviewAction(
          icon: AppIcons.send,
          label: 'home.send'.tr(),
          onTap: () => widget.onSend(got.file.path),
        ),
      ],
    );
  }

  Future<void> _backUpOne(PhotoAsset a) async {
    try {
      await _backup.backUp([a]);
      if (mounted) toast(context, 'vault.backup_added_n'.plural(1));
    } on Object catch (e) {
      debugPrint('[vault] back up one: $e');
      if (mounted) {
        toast(context, 'vault.error_failed'.tr(), type: ToastType.error);
      }
    }
  }

  /// Asset id to content hash of what is backed up (from the latest build).
  Map<String, String> _backedHashes = const {};

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
            _backedHashes = backed;
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
                      count: _selected.length,
                      onClear: () => setState(_selected.clear),
                      actions: [
                        (
                          AppIcons.cloudSync,
                          'vault.backup_now'.tr(),
                          () => unawaited(_backUpChosen(ids)),
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
        if (!noAccess && !waiting && items.isNotEmpty)
          SliverToBoxAdapter(
            child: _Legend(failed: _hasFailed(items, backed, uploads)),
          ),
        if (waiting)
          SliverToBoxAdapter(child: _skeleton())
        else if (items.isEmpty)
          SliverToBoxAdapter(
            child: AppEmptyState(
              icon: AppIcons.image,
              title: 'vault.backup_empty'.tr(),
              message: 'vault.backup_empty_body'.tr(),
            ),
          )
        else
          SliverLayoutBuilder(
            builder: (context, c) {
              // The same grid as the Send tab's gallery: about 104 wide,
              // at least four across, 2 apart, grouped by day.
              final columns = (c.crossAxisExtent / 104).floor().clamp(4, 10);
              final tile = (c.crossAxisExtent - (columns - 1) * 2) / columns;
              final lines = _lines(items, columns, context);
              return SliverPadding(
                padding: const EdgeInsets.only(bottom: 120),
                sliver: SliverList.builder(
                  itemCount: lines.length,
                  itemBuilder: (context, i) => switch (lines[i]) {
                    _DayLine(:final label) => Padding(
                      padding: const EdgeInsetsDirectional.fromSTEB(
                        16,
                        16,
                        16,
                        8,
                      ),
                      child: Text(
                        label,
                        style: AppType.label.copyWith(
                          fontSize: 14,
                          color: context.tokens.text,
                        ),
                      ),
                    ),
                    _TileLine(:final row) => Padding(
                      padding: const EdgeInsets.only(bottom: 2),
                      child: Row(
                        children: [
                          for (var k = 0; k < columns; k++) ...[
                            if (k > 0) const SizedBox(width: 2),
                            SizedBox(
                              width: tile,
                              height: tile,
                              child: k < row.length
                                  ? switch (row[k]) {
                                      _Local(:final asset) => _localTile(
                                        asset,
                                        backed,
                                        uploads,
                                      ),
                                      _Remote(:final object) => _remoteTile(
                                        object,
                                      ),
                                    }
                                  : null,
                            ),
                          ],
                        ],
                      ),
                    ),
                  },
                ),
              );
            },
          ),
      ],
    );
  }

  /// Day headings and rows of [columns] tiles, newest first.
  List<_Line> _lines(List<_Item> items, int columns, BuildContext context) {
    final locale = context.locale.toLanguageTag();
    final lines = <_Line>[];
    var i = 0;
    while (i < items.length) {
      final day = DateTime.fromMillisecondsSinceEpoch(items[i].at);
      var j = i;
      while (j < items.length &&
          _sameDay(DateTime.fromMillisecondsSinceEpoch(items[j].at), day)) {
        j++;
      }
      lines.add(_DayLine(dayLabel(day, locale)));
      for (var k = i; k < j; k += columns) {
        lines.add(_TileLine(items.sublist(k, (k + columns).clamp(0, j))));
      }
      i = j;
    }
    return lines;
  }

  static bool _sameDay(DateTime a, DateTime b) =>
      a.year == b.year && a.month == b.month && a.day == b.day;

  /// Any photo on screen whose upload failed: the legend explains that mark.
  bool _hasFailed(
    List<_Item> items,
    Set<String> backed,
    Map<String, String> uploads,
  ) => items.any(
    (it) =>
        it is _Local &&
        VaultPhotoBackup.stateOf(it.asset.id, backed, uploads) ==
            PhotoBackupState.failed,
  );

  Widget _skeleton() => AppShimmer(
    child: LayoutBuilder(
      builder: (context, c) {
        final columns = (c.maxWidth / 104).floor().clamp(4, 10);
        final tile = (c.maxWidth - (columns - 1) * 2) / columns;
        return Padding(
          padding: const EdgeInsets.only(top: 16),
          child: Wrap(
            spacing: 2,
            runSpacing: 2,
            children: [
              for (var i = 0; i < columns * 5; i++)
                AppSkeletonBox(width: tile, height: tile),
            ],
          ),
        );
      },
    ),
  );

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
      // Every photo says where it stands (owner 2026-10-21 and again
      // 2026-10-28: without a mark, "backed up" and "not yet" look alike).
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

/// One line of the gallery: a day heading or a row of tiles.
sealed class _Line {}

final class _DayLine extends _Line {
  _DayLine(this.label);
  final String label;
}

final class _TileLine extends _Line {
  _TileLine(this.row);
  final List<_Item> row;
}

/// What the marks on the tiles mean.
class _Legend extends StatelessWidget {
  const _Legend({required this.failed});

  /// Some upload failed: its mark is explained too.
  final bool failed;

  @override
  Widget build(BuildContext context) {
    final t = context.tokens;
    Widget item(PhotoBackupState s) => Row(
      mainAxisSize: MainAxisSize.min,
      children: [
        PhotoBackupBadge(state: s),
        const SizedBox(width: 6),
        Text(
          photoBackupStateLabel(s),
          style: AppType.secondary.copyWith(color: t.text2),
        ),
      ],
    );
    return Padding(
      padding: const EdgeInsets.fromLTRB(16, 2, 16, 4),
      child: Wrap(
        spacing: 16,
        runSpacing: 6,
        children: [
          item(PhotoBackupState.backedUp),
          item(PhotoBackupState.notBackedUp),
          if (failed) item(PhotoBackupState.failed),
        ],
      ),
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
    final t = context.tokens;
    final Widget icon = switch (state) {
      PhotoBackupState.backedUp => AppSvgIcon(
        AppIcons.cloudDone,
        size: 14,
        color: t.accent,
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
        color: t.danger,
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

/// No access to the library yet (or it was refused): one line, and the way
/// to allow it.
class _AccessCard extends StatelessWidget {
  const _AccessCard({required this.backup});

  final VaultPhotoBackup backup;

  @override
  Widget build(BuildContext context) {
    final t = context.tokens;
    return _StripShell(
      icon: AppIcons.image,
      iconColor: t.text2,
      title: 'vault.backup_access_title'.tr(),
      subtitle: 'vault.backup_access_body'.tr(),
      subtitleLines: 2,
      trailing: AppButton(
        label: 'vault.backup_allow'.tr(),
        size: AppButtonSize.small,
        onPressed: () => unawaited(backup.refreshAccess(ask: true)),
      ),
      onTap: () => unawaited(backup.library.openSettings()),
    );
  }
}

/// Photo backup as one line over the gallery: where it stands, and
/// "Turn on" while it is off. Tapping it opens the switches (backup, Wi-Fi
/// only) and their explanation in a sheet.
class _BackupCard extends StatelessWidget {
  const _BackupCard({required this.backup, required this.onSwitch});

  final VaultPhotoBackup backup;
  final Future<void> Function(bool) onSwitch;

  @override
  Widget build(BuildContext context) {
    final t = context.tokens;
    final left = backup.left;
    final (String icon, Color color, String title, String sub) = !backup.on
        ? (
            AppIcons.cloudOff,
            t.text2,
            'vault.backup_strip_off'.tr(),
            'vault.backup_strip_off_sub'.tr(),
          )
        : backup.noRoom
        ? (
            AppIcons.circleAlert,
            t.danger,
            'vault.backup_title'.tr(),
            'vault.backup_no_room'.tr(),
          )
        : left == null
        ? (
            AppIcons.cloudSync,
            t.accent,
            'vault.backup_title'.tr(),
            'vault.backup_counting'.tr(),
          )
        : left == 0
        ? (
            AppIcons.cloudDone,
            t.accent,
            'vault.backup_strip_done'.tr(),
            backup.wifiOnly
                ? 'vault.backup_wifi_only'.tr()
                : 'vault.backup_title'.tr(),
          )
        : (
            AppIcons.cloudSync,
            t.accent,
            'vault.backup_title'.tr(),
            'vault.backup_left'.plural(left),
          );
    return _StripShell(
      icon: icon,
      iconColor: color,
      title: title,
      subtitle: sub,
      busy: backup.on && backup.scanning,
      trailing: backup.on
          ? AppSvgIcon(AppIcons.chevronRight, size: 18, color: t.text3)
          : AppButton(
              label: 'vault.backup_turn_on'.tr(),
              size: AppButtonSize.small,
              onPressed: () => unawaited(onSwitch(true)),
            ),
      onTap: () => _settings(context),
    );
  }

  Future<void> _settings(BuildContext context) => showAppSheet<void>(
    context,
    icon: AppIcons.cloudSync,
    title: 'vault.backup_title'.tr(),
    builder: (ctx) => ListenableBuilder(
      listenable: backup,
      builder: (ctx, _) {
        final t = ctx.tokens;
        return Column(
          mainAxisSize: MainAxisSize.min,
          crossAxisAlignment: CrossAxisAlignment.stretch,
          children: [
            Text(
              'vault.backup_explain'.tr(
                namedArgs: {'folder': 'vault.backup_folder'.tr()},
              ),
              style: AppType.secondary.copyWith(color: t.text2),
            ),
            const SizedBox(height: 8),
            AppSwitchRow(
              icon: AppIcons.cloudSync,
              title: 'vault.backup_title'.tr(),
              value: backup.on,
              onChanged: (v) => unawaited(onSwitch(v)),
            ),
            if (backup.on)
              AppSwitchRow(
                icon: AppIcons.wifi,
                title: 'vault.backup_wifi_only'.tr(),
                subtitle: 'vault.backup_wifi_only_body'.tr(),
                value: backup.wifiOnly,
                onChanged: (v) => unawaited(backup.setWifiOnly(v)),
              ),
            if (backup.access == PhotoAccess.limited)
              AppValueRow(
                icon: AppIcons.image,
                title: 'vault.backup_choose_more'.tr(),
                subtitle: 'vault.backup_limited'.tr(),
                onTap: () => unawaited(backup.library.chooseMore()),
              ),
          ],
        );
      },
    ),
  );
}

/// The shared shape of the backup and access lines.
class _StripShell extends StatelessWidget {
  const _StripShell({
    required this.icon,
    required this.iconColor,
    required this.title,
    required this.subtitle,
    required this.trailing,
    required this.onTap,
    this.busy = false,
    this.subtitleLines = 1,
  });

  final String icon;
  final Color iconColor;
  final String title;
  final String subtitle;
  final Widget trailing;
  final VoidCallback onTap;
  final bool busy;
  final int subtitleLines;

  @override
  Widget build(BuildContext context) {
    final t = context.tokens;
    return Material(
      type: MaterialType.transparency,
      child: InkWell(
        onTap: onTap,
        child: Padding(
          padding: const EdgeInsetsDirectional.fromSTEB(16, 10, 12, 10),
          child: Row(
            children: [
              Container(
                width: 36,
                height: 36,
                alignment: Alignment.center,
                decoration: BoxDecoration(
                  color: t.sunken,
                  shape: BoxShape.circle,
                ),
                child: busy
                    ? SizedBox.square(
                        dimension: 16,
                        child: CircularProgressIndicator(
                          strokeWidth: 2,
                          color: iconColor,
                        ),
                      )
                    : AppSvgIcon(icon, size: 19, color: iconColor),
              ),
              const SizedBox(width: 12),
              Expanded(
                child: Column(
                  crossAxisAlignment: CrossAxisAlignment.start,
                  children: [
                    Text(
                      title,
                      maxLines: 1,
                      overflow: TextOverflow.ellipsis,
                      style: AppType.rowStrong.copyWith(color: t.text),
                    ),
                    Text(
                      subtitle,
                      maxLines: subtitleLines,
                      overflow: TextOverflow.ellipsis,
                      style: AppType.secondary.copyWith(color: t.text2),
                    ),
                  ],
                ),
              ),
              const SizedBox(width: 8),
              trailing,
            ],
          ),
        ),
      ),
    );
  }
}
