import 'dart:async';
import 'dart:io';

import 'package:easy_localization/easy_localization.dart';
import 'package:flutter/material.dart';
import 'package:flutter/rendering.dart';
import 'package:flutter_bloc/flutter_bloc.dart';
import 'package:photo_manager/photo_manager.dart';

import '../../../core/config/feature_flags.dart';
import '../../../core/di/locator.dart';
import '../../../core/ui/app_ui.dart';
import '../../send/data/send_media_library.dart';
import '../../send/presentation/send_selection_cubit.dart';
import '../../send/presentation/tray_cubit.dart';

/// The Photos and Videos tabs of the Send tab (redesign-plan.md 3.3): the library as a
/// lazy grid, grouped by day for photos, with an album sheet, the permission
/// and limited-access states, and selecting by tap, a day's "Select", or a
/// long press dragged across the grid.
///
/// Performance: one [SliverList] builder of rows (a day header, or one row of
/// tiles), thumbnails through the image cache at display size, pages of 120
/// fetched as the end comes near, and each tile rebuilding only when its own
/// selection order changes.
class SendMediaTab extends StatefulWidget {
  const SendMediaTab({super.key, required this.kind});

  final SendMediaKind kind;

  @override
  State<SendMediaTab> createState() => _SendMediaTabState();
}

sealed class _Row {}

final class _DayRow extends _Row {
  _DayRow(this.label, this.assets);
  final String label;
  final List<AssetEntity> assets;
}

final class _TilesRow extends _Row {
  _TilesRow(this.assets);
  final List<AssetEntity> assets;
}

class _SendMediaTabState extends State<SendMediaTab>
    with AutomaticKeepAliveClientMixin {
  static const _pageSize = 120;
  final _lib = SendMediaLibrary.instance;

  SendMediaAccess _access = SendMediaAccess.unknown;
  List<SendAlbum> _albums = const [];
  SendAlbum? _album;
  final List<AssetEntity> _assets = [];
  int _page = 0;
  bool _loading = false;
  bool _end = false;
  StreamSubscription<void>? _changes;

  // drag-to-select
  bool? _dragOn;
  final _gridKey = GlobalKey();

  bool get _photos => widget.kind == SendMediaKind.photo;
  SendKind get _sendKind => _photos ? SendKind.photo : SendKind.video;

  /// Android store builds keep the system picker until Play approves the
  /// updated declaration (redesign-plan.md D3).
  bool get _gridAllowed =>
      !Platform.isAndroid || getIt<FeatureFlags>().sendGalleryAndroid;

  @override
  bool get wantKeepAlive => true;

  @override
  void initState() {
    super.initState();
    if (SendMediaLibrary.available && _gridAllowed) {
      unawaited(_check(ask: false));
    }
  }

  @override
  void dispose() {
    _changes?.cancel();
    super.dispose();
  }

  Future<void> _check({required bool ask}) async {
    final a = await _lib.access(widget.kind, ask: ask);
    if (!mounted) return;
    setState(() => _access = a);
    if (a == SendMediaAccess.full || a == SendMediaAccess.limited) {
      await _loadAlbums();
      _changes ??= _lib.changes.listen((_) => _reload());
    }
  }

  Future<void> _loadAlbums() async {
    final albums = await _lib.albums(widget.kind);
    if (!mounted) return;
    setState(() {
      _albums = albums;
      _album =
          albums.where((a) => a.id == _album?.id).firstOrNull ??
          albums.firstOrNull;
    });
    await _reset();
  }

  Future<void> _reload() async {
    if (!mounted) return;
    await _loadAlbums();
  }

  Future<void> _reset() async {
    _assets.clear();
    _page = 0;
    _end = false;
    await _more();
  }

  Future<void> _more() async {
    final album = _album;
    if (album == null || _loading || _end) return;
    _loading = true;
    final got = await _lib.page(album, _page, _pageSize);
    _loading = false;
    if (!mounted) return;
    setState(() {
      _page++;
      _assets.addAll(got);
      if (got.length < _pageSize) _end = true;
    });
  }

  String _dayLabel(DateTime d) {
    final now = DateTime.now();
    final day = DateTime(d.year, d.month, d.day);
    final today = DateTime(now.year, now.month, now.day);
    final diff = today.difference(day).inDays;
    if (diff == 0) return 'compose.today'.tr();
    if (diff == 1) return 'compose.yesterday'.tr();
    final locale = context.locale.toLanguageTag();
    return d.year == now.year
        ? DateFormat.MMMEd(locale).format(d)
        : DateFormat.yMMMEd(locale).format(d);
  }

  List<_Row> _rows(int columns) {
    final rows = <_Row>[];
    if (!_photos) {
      for (var i = 0; i < _assets.length; i += columns) {
        rows.add(
          _TilesRow(_assets.sublist(i, (i + columns).clamp(0, _assets.length))),
        );
      }
      return rows;
    }
    var i = 0;
    while (i < _assets.length) {
      final d = _assets[i].createDateTime;
      var j = i;
      while (j < _assets.length && _sameDay(_assets[j].createDateTime, d)) {
        j++;
      }
      final day = _assets.sublist(i, j);
      rows.add(_DayRow(_dayLabel(d), day));
      for (var k = 0; k < day.length; k += columns) {
        rows.add(_TilesRow(day.sublist(k, (k + columns).clamp(0, day.length))));
      }
      i = j;
    }
    return rows;
  }

  static bool _sameDay(DateTime a, DateTime b) =>
      a.year == b.year && a.month == b.month && a.day == b.day;

  // ---- drag to select -------------------------------------------------------

  AssetEntity? _assetAt(Offset global) {
    final box = _gridKey.currentContext?.findRenderObject() as RenderBox?;
    if (box == null) return null;
    final result = BoxHitTestResult();
    box.hitTest(result, position: box.globalToLocal(global));
    for (final e in result.path) {
      final t = e.target;
      if (t is RenderMetaData && t.metaData is AssetEntity) {
        return t.metaData as AssetEntity;
      }
    }
    return null;
  }

  void _dragStart(LongPressStartDetails d) {
    final a = _assetAt(d.globalPosition);
    if (a == null) return;
    final sel = context.read<SendSelectionCubit>();
    _dragOn = !sel.state.contains('a:${a.id}');
    sel.setAssets([a], _sendKind, _dragOn!);
    tapHaptic();
  }

  void _dragMove(LongPressMoveUpdateDetails d) {
    final on = _dragOn;
    if (on == null) return;
    final a = _assetAt(d.globalPosition);
    if (a == null) return;
    final sel = context.read<SendSelectionCubit>();
    if (sel.state.contains('a:${a.id}') != on) {
      sel.setAssets([a], _sendKind, on);
      tapHaptic();
    }
  }

  // ---- UI -------------------------------------------------------------------

  @override
  Widget build(BuildContext context) {
    super.build(context);
    final t = context.tokens;
    if (!SendMediaLibrary.available || !_gridAllowed) return _pickerFallback();
    switch (_access) {
      case SendMediaAccess.unknown:
        return _skeleton();
      case SendMediaAccess.none:
        return _askAccess();
      case SendMediaAccess.limited:
      case SendMediaAccess.full:
        break;
    }
    if (_album == null && _albums.isEmpty) {
      return ListView(
        children: [
          AppEmptyState(
            icon: _photos ? AppIcons.image : AppIcons.fileVideo,
            title: 'compose.library_empty'.tr(),
            message: 'compose.library_empty_body'.tr(),
          ),
        ],
      );
    }
    return LayoutBuilder(
      builder: (context, box) {
        final columns = _photos
            ? (box.maxWidth / 104).floor().clamp(4, 10)
            : (box.maxWidth / 138).floor().clamp(3, 8);
        final tile = (box.maxWidth - (columns - 1) * 2) / columns;
        final px = (tile * MediaQuery.devicePixelRatioOf(context))
            .round()
            .clamp(120, 360);
        final rows = _rows(columns);
        return NotificationListener<ScrollNotification>(
          onNotification: (n) {
            if (n.metrics.extentAfter < 1200) unawaited(_more());
            return false;
          },
          child: GestureDetector(
            onLongPressStart: _dragStart,
            onLongPressMoveUpdate: _dragMove,
            onLongPressEnd: (_) => _dragOn = null,
            child: CustomScrollView(
              key: _gridKey,
              scrollCacheExtent: const ScrollCacheExtent.pixels(800),
              slivers: [
                SliverToBoxAdapter(child: _toolbar(t)),
                if (_access == SendMediaAccess.limited)
                  SliverToBoxAdapter(child: _limitedBanner(t)),
                SliverList.builder(
                  itemCount: rows.length,
                  itemBuilder: (context, i) => switch (rows[i]) {
                    _DayRow(:final label, :final assets) => _DayHeader(
                      label: label,
                      assets: assets,
                      kind: _sendKind,
                    ),
                    _TilesRow(:final assets) => Padding(
                      padding: const EdgeInsets.only(bottom: 2),
                      child: SizedBox(
                        height: _photos ? tile : tile,
                        child: Row(
                          children: [
                            for (var k = 0; k < columns; k++) ...[
                              if (k > 0) const SizedBox(width: 2),
                              Expanded(
                                child: k < assets.length
                                    ? _Tile(
                                        asset: assets[k],
                                        kind: _sendKind,
                                        px: px,
                                      )
                                    : const SizedBox.shrink(),
                              ),
                            ],
                          ],
                        ),
                      ),
                    ),
                  },
                ),
                const SliverToBoxAdapter(child: SizedBox(height: 140)),
              ],
            ),
          ),
        );
      },
    );
  }

  Widget _toolbar(AppTokens t) {
    final album = _album;
    final name = album == null || album.isAll
        ? (_photos ? 'compose.all_photos'.tr() : 'compose.all_videos'.tr())
        : album.name;
    return Padding(
      padding: const EdgeInsetsDirectional.fromSTEB(6, 2, 14, 2),
      child: Row(
        children: [
          Material(
            type: MaterialType.transparency,
            child: InkWell(
              borderRadius: BorderRadius.circular(10),
              onTap: _albums.length > 1 ? _pickAlbum : null,
              child: ConstrainedBox(
                constraints: const BoxConstraints(minHeight: 44),
                child: Padding(
                  padding: const EdgeInsets.symmetric(horizontal: 8),
                  child: Row(
                    children: [
                      Text(
                        name,
                        style: AppType.rowStrong.copyWith(
                          fontSize: 14,
                          color: t.text,
                        ),
                      ),
                      if (_albums.length > 1) ...[
                        const SizedBox(width: 2),
                        Transform.rotate(
                          angle: 1.5708,
                          child: AppSvgIcon(
                            AppIcons.chevronRight,
                            size: 16,
                            color: t.text2,
                          ),
                        ),
                      ],
                    ],
                  ),
                ),
              ),
            ),
          ),
          const Spacer(),
          if (album != null)
            Text(
              'compose.n_items'.plural(album.count),
              style: AppType.small.copyWith(color: t.text3),
            ),
        ],
      ),
    );
  }

  Widget _limitedBanner(AppTokens t) => Container(
    margin: const EdgeInsets.fromLTRB(12, 0, 12, 8),
    padding: const EdgeInsetsDirectional.fromSTEB(12, 4, 4, 4),
    decoration: BoxDecoration(
      color: t.sunken,
      borderRadius: BorderRadius.circular(12),
    ),
    child: Row(
      children: [
        AppSvgIcon(AppIcons.permissionShield, size: 20, color: t.text2),
        const SizedBox(width: 10),
        Expanded(
          child: Text(
            'compose.limited'.tr(),
            style: AppType.secondary.copyWith(color: t.text2),
          ),
        ),
        AppButton(
          label: 'compose.manage'.tr(),
          variant: AppButtonVariant.ghost,
          size: AppButtonSize.small,
          onPressed: () async {
            await _lib.chooseMore();
            await _reload();
          },
        ),
      ],
    ),
  );

  Future<void> _pickAlbum() async {
    final picked = await showAppSheet<SendAlbum>(
      context,
      title: 'compose.albums'.tr(),
      builder: (ctx) => Column(
        mainAxisSize: MainAxisSize.min,
        children: [
          for (final a in _albums)
            AppListTile(
              padding: const EdgeInsets.symmetric(vertical: 6),
              leading: ClipRRect(
                borderRadius: BorderRadius.circular(8),
                child: SizedBox.square(
                  dimension: 44,
                  child: a.cover == null
                      ? ColoredBox(color: ctx.tokens.sunken)
                      : Image(
                          image: AssetThumbProvider(a.cover!, px: 132),
                          fit: BoxFit.cover,
                        ),
                ),
              ),
              title: Text(
                a.isAll
                    ? (_photos
                          ? 'compose.all_photos'.tr()
                          : 'compose.all_videos'.tr())
                    : a.name,
              ),
              subtitle: Text('compose.n_items'.plural(a.count)),
              trailing: a.id == _album?.id
                  ? AppSvgIcon(
                      AppIcons.check,
                      size: 20,
                      color: ctx.tokens.accent,
                    )
                  : null,
              onTap: () => Navigator.pop(ctx, a),
            ),
        ],
      ),
    );
    if (picked == null || !mounted) return;
    setState(() => _album = picked);
    await _reset();
  }

  Widget _skeleton() => LayoutBuilder(
    builder: (context, box) {
      final columns = _photos ? 4 : 3;
      return GridView.builder(
        physics: const NeverScrollableScrollPhysics(),
        padding: const EdgeInsets.only(top: 48),
        gridDelegate: SliverGridDelegateWithFixedCrossAxisCount(
          crossAxisCount: columns,
          mainAxisSpacing: 2,
          crossAxisSpacing: 2,
        ),
        itemCount: columns * 6,
        itemBuilder: (context, i) => ColoredBox(color: context.tokens.sunken),
      );
    },
  );

  Widget _askAccess() => ListView(
    children: [
      AppEmptyState(
        icon: _photos ? AppIcons.image : AppIcons.fileVideo,
        title: 'compose.access_title'.tr(),
        message: _photos
            ? 'compose.access_body_photo'.tr()
            : 'compose.access_body_video'.tr(),
        action: Column(
          children: [
            AppButton(
              label: 'compose.allow'.tr(),
              onPressed: () async {
                await _check(ask: true);
                if (_access == SendMediaAccess.none) await _lib.openSettings();
              },
            ),
            const SizedBox(height: 6),
            AppButton(
              label: 'compose.system_picker'.tr(),
              variant: AppButtonVariant.ghost,
              onPressed: context.read<TrayCubit>().pickMedia,
            ),
          ],
        ),
      ),
    ],
  );

  Widget _pickerFallback() => ListView(
    children: [
      AppEmptyState(
        icon: _photos ? AppIcons.image : AppIcons.fileVideo,
        title: 'compose.picker_title'.tr(),
        message: 'compose.picker_body'.tr(),
        action: AppButton(
          label: _photos
              ? 'receive.choose_photos'.tr()
              : 'remote.choose_photo_video'.tr(),
          icon: AppIcons.image,
          onPressed: context.read<TrayCubit>().pickMedia,
        ),
      ),
    ],
  );
}

/// "Today · Select": a day's label and the button that selects (or
/// unselects) every photo of that day.
class _DayHeader extends StatelessWidget {
  const _DayHeader({
    required this.label,
    required this.assets,
    required this.kind,
  });

  final String label;
  final List<AssetEntity> assets;
  final SendKind kind;

  @override
  Widget build(BuildContext context) {
    final t = context.tokens;
    return Padding(
      padding: const EdgeInsetsDirectional.fromSTEB(14, 10, 4, 4),
      child: Row(
        children: [
          Expanded(
            child: Semantics(
              header: true,
              child: Text(
                label,
                style: AppType.rowStrong.copyWith(fontSize: 14, color: t.text),
              ),
            ),
          ),
          BlocSelector<SendSelectionCubit, SendSelection, bool>(
            selector: (s) => assets.every((a) => s.contains('a:${a.id}')),
            builder: (context, all) => AppButton(
              label: all ? 'compose.deselect'.tr() : 'compose.select'.tr(),
              variant: AppButtonVariant.ghost,
              size: AppButtonSize.small,
              onPressed: () => context.read<SendSelectionCubit>().setAssets(
                assets,
                kind,
                !all,
              ),
            ),
          ),
        ],
      ),
    );
  }
}

class _Tile extends StatelessWidget {
  const _Tile({required this.asset, required this.kind, required this.px});

  final AssetEntity asset;
  final SendKind kind;
  final int px;

  @override
  Widget build(BuildContext context) {
    final video = asset.type == AssetType.video;
    final when = DateFormat.yMMMd(
      context.locale.toLanguageTag(),
    ).format(asset.createDateTime);
    return MetaData(
      metaData: asset,
      behavior: HitTestBehavior.opaque,
      child: BlocSelector<SendSelectionCubit, SendSelection, int?>(
        selector: (s) => s.orderOf('a:${asset.id}'),
        builder: (context, order) => AppMediaTile(
          image: Image(
            image: AssetThumbProvider(asset, px: px),
            fit: BoxFit.cover,
            gaplessPlayback: true,
            filterQuality: FilterQuality.low,
            errorBuilder: (_, _, _) => ColoredBox(color: context.tokens.sunken),
          ),
          semanticLabel:
              '${video ? 'compose.tab_video'.tr() : 'home.photos'.tr()}, $when',
          selected: order != null,
          order: order,
          durationSeconds: video ? asset.duration : null,
          onTap: () =>
              context.read<SendSelectionCubit>().toggleAsset(asset, kind),
        ),
      ),
    );
  }
}
