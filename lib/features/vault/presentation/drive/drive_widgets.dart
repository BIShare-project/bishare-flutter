import 'dart:math';
import 'dart:typed_data';

import 'package:easy_localization/easy_localization.dart';
import 'package:flutter/material.dart';
import 'package:shadcn_ui/shadcn_ui.dart';

import '../../../../core/di/locator.dart';
import '../../../../core/storage/app_database.dart';
import '../../../../core/ui/app_ui.dart';
import '../../data/vault_thumbs.dart';
import 'drive_controller.dart';
import 'drive_format.dart';

// ---- pictures ------------------------------------------------------------------------

/// A Drive item's picture: the folder glyph, the photo or video thumbnail
/// when there is one, or the type icon.
class DriveThumb extends StatefulWidget {
  const DriveThumb({
    super.key,
    required this.object,
    this.size = 34,
    this.radius = 9,
  });

  final VaultObject object;
  final double size;
  final double radius;

  @override
  State<DriveThumb> createState() => _DriveThumbState();
}

class _DriveThumbState extends State<DriveThumb> {
  Uint8List? _jpeg;

  @override
  void initState() {
    super.initState();
    _load();
  }

  @override
  void didUpdateWidget(DriveThumb old) {
    super.didUpdateWidget(old);
    if (old.object.id != widget.object.id ||
        old.object.hasThumb != widget.object.hasThumb) {
      _jpeg = null;
      _load();
    }
  }

  Future<void> _load() async {
    final o = widget.object;
    if (o.kind != 'file' || !o.hasThumb) return;
    final bytes = await getIt<VaultThumbs>().load(o);
    if (mounted && bytes != null && widget.object.id == o.id) {
      setState(() => _jpeg = bytes);
    }
  }

  @override
  Widget build(BuildContext context) {
    final o = widget.object;
    if (o.kind == 'dir') {
      // The same square as a file's, so rows line up.
      final t = context.tokens;
      return Container(
        width: widget.size,
        height: widget.size,
        alignment: Alignment.center,
        decoration: BoxDecoration(
          color: t.sunken,
          borderRadius: BorderRadius.circular(widget.radius),
        ),
        child: AppSvgIcon(
          AppIcons.folder,
          size: widget.size * 0.5,
          color: t.accent,
        ),
      );
    }
    final jpeg = _jpeg;
    if (jpeg != null) {
      return ClipRRect(
        borderRadius: BorderRadius.circular(widget.radius),
        child: Image.memory(
          jpeg,
          width: widget.size,
          height: widget.size,
          fit: BoxFit.cover,
          gaplessPlayback: true,
        ),
      );
    }
    return MediaThumb(
      path: null,
      mime: o.mime,
      size: widget.size,
      radius: widget.radius,
    );
  }
}

// ---- one item ----------------------------------------------------------------------------

String _subtitle(BuildContext context, VaultObject o, int? items) {
  final when = shortWhen(o.mtime, context.locale.toLanguageTag());
  if (o.kind == 'dir') {
    return items == null ? when : '${'vault.items_n'.plural(items)} · $when';
  }
  return '${decimalBytes(o.size ?? 0)} · $when';
}

class _Check extends StatelessWidget {
  const _Check({required this.on});
  final bool on;

  @override
  Widget build(BuildContext context) {
    final cs = ShadTheme.of(context).colorScheme;
    return AnimatedContainer(
      duration: const Duration(milliseconds: 140),
      width: 22,
      height: 22,
      decoration: BoxDecoration(
        shape: BoxShape.circle,
        color: on ? cs.primary : cs.background.withValues(alpha: 0.85),
        border: Border.all(
          color: on ? cs.primary : cs.mutedForeground,
          width: 1.6,
        ),
      ),
      child: on
          ? const Icon(Icons.check_rounded, size: 15, color: Colors.white)
          : null,
    );
  }
}

/// A row of the list layout.
class DriveListRow extends StatelessWidget {
  const DriveListRow({
    super.key,
    required this.object,
    required this.selected,
    required this.selecting,
    required this.onTap,
    required this.onLongPress,
    required this.onMore,
    this.items,
    this.location,
  });

  final VaultObject object;
  final bool selected;
  final bool selecting;
  final VoidCallback onTap;
  final VoidCallback onLongPress;
  final VoidCallback onMore;

  /// Folders: how many things are inside.
  final int? items;

  /// Search, Recent and the type views: where the item lives.
  final String? location;

  @override
  Widget build(BuildContext context) {
    final t = context.tokens;
    final o = object;
    final sub = _subtitle(context, o, items);
    return Material(
      color: selected ? t.accentSoft : Colors.transparent,
      child: InkWell(
        onTap: onTap,
        onLongPress: onLongPress,
        child: ConstrainedBox(
          constraints: const BoxConstraints(minHeight: 64),
          child: Padding(
            padding: const EdgeInsetsDirectional.fromSTEB(14, 8, 4, 8),
            child: Row(
              children: [
                DriveThumb(object: o, size: 44, radius: 11),
                const SizedBox(width: 12),
                Expanded(
                  child: Column(
                    crossAxisAlignment: CrossAxisAlignment.start,
                    children: [
                      Text(
                        o.name,
                        maxLines: 1,
                        overflow: TextOverflow.ellipsis,
                        style: AppType.row.copyWith(color: t.text),
                      ),
                      const SizedBox(height: 2),
                      Text(
                        location == null ? sub : '$location · $sub',
                        maxLines: 1,
                        overflow: TextOverflow.ellipsis,
                        style: AppType.secondary.copyWith(color: t.text2),
                      ),
                    ],
                  ),
                ),
                if (selecting)
                  Padding(
                    padding: const EdgeInsetsDirectional.only(
                      start: 10,
                      end: 10,
                    ),
                    child: AppRowCheck(selected: selected),
                  )
                else
                  AppIconButton(
                    icon: AppIcons.moreMenu,
                    tooltip: 'inbox.more'.tr(),
                    onPressed: onMore,
                  ),
              ],
            ),
          ),
        ),
      ),
    );
  }
}

/// A tile of the grid layout.
class DriveGridCard extends StatelessWidget {
  const DriveGridCard({
    super.key,
    required this.object,
    required this.selected,
    required this.selecting,
    required this.onTap,
    required this.onLongPress,
    required this.onMore,
    this.items,
  });

  final VaultObject object;
  final bool selected;
  final bool selecting;
  final VoidCallback onTap;
  final VoidCallback onLongPress;
  final VoidCallback onMore;
  final int? items;

  @override
  Widget build(BuildContext context) {
    final cs = ShadTheme.of(context).colorScheme;
    final o = object;
    final picture = o.kind == 'file' && o.hasThumb;
    return Material(
      color: Colors.transparent,
      child: InkWell(
        borderRadius: BorderRadius.circular(12),
        onTap: onTap,
        onLongPress: onLongPress,
        child: Container(
          clipBehavior: Clip.antiAlias,
          decoration: BoxDecoration(
            color: selected ? cs.primary.withValues(alpha: 0.10) : cs.card,
            borderRadius: BorderRadius.circular(12),
            border: Border.all(
              color: selected ? cs.primary : cs.border.withValues(alpha: 0.8),
              width: selected ? 1.6 : 1,
            ),
          ),
          child: Column(
            crossAxisAlignment: CrossAxisAlignment.start,
            children: [
              // The picture to the card's edges; an icon on a quiet ground.
              Expanded(
                child: Stack(
                  fit: StackFit.expand,
                  children: [
                    LayoutBuilder(
                      builder: (context, c) => picture
                          ? FittedBox(
                              fit: BoxFit.cover,
                              clipBehavior: Clip.hardEdge,
                              child: DriveThumb(
                                object: o,
                                size: c.biggest.longestSide,
                                radius: 0,
                              ),
                            )
                          : ColoredBox(
                              color: cs.muted.withValues(alpha: 0.35),
                              child: Center(
                                child: DriveThumb(
                                  object: o,
                                  size: c.biggest.shortestSide * 0.5,
                                ),
                              ),
                            ),
                    ),
                    if (selecting)
                      Positioned(top: 6, left: 6, child: _Check(on: selected)),
                    if (!selecting)
                      Positioned(
                        top: 2,
                        right: 2,
                        child: IconButton(
                          onPressed: onMore,
                          visualDensity: VisualDensity.compact,
                          style: picture
                              ? IconButton.styleFrom(
                                  backgroundColor: Colors.black.withValues(
                                    alpha: 0.38,
                                  ),
                                  minimumSize: const Size(28, 28),
                                  padding: EdgeInsets.zero,
                                )
                              : null,
                          icon: AppSvgIcon(
                            AppIcons.moreMenu,
                            size: 16,
                            color: picture ? Colors.white : cs.mutedForeground,
                          ),
                        ),
                      ),
                  ],
                ),
              ),
              Padding(
                padding: const EdgeInsets.fromLTRB(9, 7, 9, 8),
                child: Column(
                  crossAxisAlignment: CrossAxisAlignment.start,
                  children: [
                    Text(
                      o.name,
                      maxLines: 1,
                      overflow: TextOverflow.ellipsis,
                      style: TextStyle(
                        fontSize: 13,
                        fontWeight: FontWeight.w600,
                        color: cs.foreground,
                      ),
                    ),
                    Text(
                      o.kind == 'dir'
                          ? (items == null
                                ? 'vault.folder'.tr()
                                : 'vault.items_n'.plural(items!))
                          : decimalBytes(o.size ?? 0),
                      maxLines: 1,
                      style: TextStyle(
                        fontSize: 11.5,
                        color: cs.mutedForeground,
                      ),
                    ),
                  ],
                ),
              ),
            ],
          ),
        ),
      ),
    );
  }
}

class DriveMediaTile extends StatelessWidget {
  const DriveMediaTile({
    super.key,
    required this.image,
    required this.selected,
    required this.selecting,
    required this.onTap,
    required this.onLongPress,
    this.video = false,
    this.durationS,
    this.badge,
    this.label,
  });

  final Widget image;
  final bool selected;
  final bool selecting;
  final VoidCallback onTap;
  final VoidCallback onLongPress;
  final bool video;

  /// Shown as m:ss when known.
  final int? durationS;
  final Widget? badge;

  /// For screen readers (the tile shows no name).
  final String? label;

  static String _length(int s) =>
      '${s ~/ 60}:${(s % 60).toString().padLeft(2, '0')}';

  @override
  Widget build(BuildContext context) {
    final cs = ShadTheme.of(context).colorScheme;
    return Semantics(
      label: label,
      selected: selected,
      button: true,
      child: GestureDetector(
        onTap: onTap,
        onLongPress: onLongPress,
        child: ClipRRect(
          borderRadius: BorderRadius.circular(4),
          child: Stack(
            fit: StackFit.expand,
            children: [
              ColoredBox(color: cs.muted, child: image),
              if (video)
                Positioned(
                  left: 0,
                  right: 0,
                  bottom: 0,
                  child: Container(
                    padding: const EdgeInsets.fromLTRB(6, 10, 6, 4),
                    decoration: const BoxDecoration(
                      gradient: LinearGradient(
                        begin: Alignment.topCenter,
                        end: Alignment.bottomCenter,
                        colors: [Color(0x00000000), Color(0x8C000000)],
                      ),
                    ),
                    child: Row(
                      children: [
                        const Icon(
                          Icons.play_arrow_rounded,
                          size: 14,
                          color: Colors.white,
                        ),
                        if (durationS != null && durationS! > 0)
                          Text(
                            _length(durationS!),
                            style: const TextStyle(
                              fontSize: 11,
                              fontWeight: FontWeight.w600,
                              color: Colors.white,
                            ),
                          ),
                      ],
                    ),
                  ),
                ),
              if (selected)
                ColoredBox(color: cs.primary.withValues(alpha: 0.28)),
              // Check at the start, badge at the end: the video length
              // (a row from the start) stays clear in right-to-left too.
              if (selecting)
                PositionedDirectional(
                  top: 4,
                  start: 4,
                  child: _Check(on: selected),
                ),
              if (badge != null)
                PositionedDirectional(end: 4, bottom: 4, child: badge!),
            ],
          ),
        ),
      ),
    );
  }
}

// ---- finding your way ------------------------------------------------------------------

/// "Drive › Photos › 2024", each part a way back.
class DriveBreadcrumb extends StatelessWidget {
  const DriveBreadcrumb({super.key, required this.ctrl});

  final DriveController ctrl;

  @override
  Widget build(BuildContext context) {
    final t = context.tokens;
    final path = ctrl.path;
    if (path.isEmpty) return const SizedBox.shrink();
    Widget crumb(String label, VoidCallback? onTap, {bool last = false}) =>
        InkWell(
          borderRadius: BorderRadius.circular(8),
          onTap: onTap,
          child: Padding(
            padding: const EdgeInsets.symmetric(horizontal: 4, vertical: 10),
            child: Text(
              label,
              style: AppType.row.copyWith(
                fontSize: 14,
                fontWeight: last ? FontWeight.w600 : FontWeight.w400,
                color: last ? t.text : t.text2,
              ),
            ),
          ),
        );
    Widget sep() => AppSvgIcon(AppIcons.chevronRight, size: 14, color: t.text3);
    return Row(
      children: [
        // Up one folder (the header has no back arrow at the top level).
        AppIconButton(
          icon: AppIcons.chevronLeft,
          tooltip: MaterialLocalizations.of(context).backButtonTooltip,
          onPressed: () => ctrl.up(),
        ),
        Expanded(
          child: SizedBox(
            height: 44,
            child: ListView(
              scrollDirection: Axis.horizontal,
              reverse: true,
              padding: const EdgeInsetsDirectional.only(end: 12),
              children: [
                // Reversed so the current folder is in view when the path is
                // long.
                for (var i = path.length - 1; i >= 0; i--) ...[
                  crumb(
                    path[i].name,
                    i == path.length - 1 ? null : () => ctrl.goTo(i + 1),
                    last: i == path.length - 1,
                  ),
                  sep(),
                ],
                crumb('vault.drive'.tr(), () => ctrl.goTo(0)),
              ],
            ),
          ),
        ),
      ],
    );
  }
}

/// Search, sort and layout.
class DriveToolbar extends StatelessWidget {
  const DriveToolbar({
    super.key,
    required this.ctrl,
    required this.search,
    required this.searchFocus,
    this.trailing = const [],
  });

  final DriveController ctrl;
  final TextEditingController search;
  final FocusNode searchFocus;
  final List<Widget> trailing;

  Future<void> _sortMenu(BuildContext context) async {
    final pick = await showAppSheet<DriveSort>(
      context,
      icon: AppIcons.sort,
      title: 'vault.sort_by'.tr(),
      builder: (ctx) => Column(
        mainAxisSize: MainAxisSize.min,
        children: [
          for (final s in DriveSort.values)
            AppSheetAction(
              icon: s == ctrl.sort
                  ? (ctrl.ascending ? AppIcons.arrowUp : AppIcons.arrowDown)
                  : AppIcons.circle,
              label: 'vault.sort_${s.name}'.tr(),
              onTap: () => Navigator.pop(ctx, s),
            ),
        ],
      ),
    );
    if (pick != null) ctrl.setSort(pick);
  }

  @override
  Widget build(BuildContext context) {
    final t = context.tokens;
    // Recent is newest first, always.
    final canSort = ctrl.view != DriveView.recent || ctrl.searching;
    return Padding(
      padding: const EdgeInsetsDirectional.fromSTEB(0, 2, 6, 2),
      child: Row(
        children: [
          Expanded(
            child: AppSearchField(
              hint: 'vault.search'.tr(),
              controller: search,
              focusNode: searchFocus,
              onChanged: ctrl.setQuery,
              margin: const EdgeInsetsDirectional.fromSTEB(14, 4, 4, 4),
            ),
          ),
          Material(
            type: MaterialType.transparency,
            child: InkWell(
              borderRadius: BorderRadius.circular(10),
              onTap: canSort ? () => _sortMenu(context) : null,
              child: ConstrainedBox(
                constraints: const BoxConstraints(minHeight: 44),
                child: Padding(
                  padding: const EdgeInsets.symmetric(horizontal: 8),
                  child: Row(
                    mainAxisSize: MainAxisSize.min,
                    children: [
                      AppSvgIcon(
                        AppIcons.sort,
                        size: 18,
                        color: canSort ? t.text : t.text3,
                      ),
                      const SizedBox(width: 4),
                      Text(
                        'vault.sort_${ctrl.sort.name}'.tr(),
                        style: AppType.secondary.copyWith(
                          color: canSort ? t.text : t.text3,
                          fontWeight: FontWeight.w500,
                        ),
                      ),
                    ],
                  ),
                ),
              ),
            ),
          ),
          AppIconButton(
            icon: ctrl.grid ? AppIcons.listView : AppIcons.gridView,
            tooltip: (ctrl.grid ? 'vault.list_view' : 'vault.grid_view').tr(),
            onPressed: () => ctrl.setGrid(!ctrl.grid),
          ),
          ...trailing,
        ],
      ),
    );
  }
}

/// The File tab's kinds (redesign-plan.md 6.1): everything, documents,
/// audio. Photos and videos have their own tab.
class DriveKindChips extends StatelessWidget {
  const DriveKindChips({super.key, required this.ctrl});

  final DriveController ctrl;

  @override
  Widget build(BuildContext context) => AppChips<DriveView>(
    value: ctrl.view,
    options: [
      (DriveView.files, 'vault.kind_all'.tr()),
      (DriveView.documents, driveViewLabel(DriveView.documents)),
      (DriveView.audio, driveViewLabel(DriveView.audio)),
    ],
    onChanged: ctrl.setView,
  );
}

/// Drive's account, with a ring around it that fills as the Drive does
/// (red when full). The words are in its tooltip and for screen readers.
class DriveAccountButton extends StatelessWidget {
  const DriveAccountButton({
    super.key,
    required this.used,
    required this.quota,
    required this.onTap,
  });

  final int? used;
  final int? quota;
  final VoidCallback onTap;

  @override
  Widget build(BuildContext context) {
    final t = context.tokens;
    final u = used, q = quota;
    final known = u != null && q != null && q > 0;
    final share = known ? (u / q).clamp(0.0, 1.0) : 0.0;
    final words = known
        ? 'vault.quota_line'.tr(
            namedArgs: {'used': decimalBytes(u), 'quota': decimalBytes(q)},
          )
        : null;
    final label = ['vault.account_title'.tr(), ?words].join(', ');
    return Tooltip(
      message: label,
      child: Semantics(
        button: true,
        label: label,
        excludeSemantics: true,
        child: InkResponse(
          onTap: onTap,
          radius: 24,
          child: SizedBox.square(
            dimension: 44,
            child: Center(
              child: SizedBox.square(
                dimension: 32,
                child: Stack(
                  alignment: Alignment.center,
                  children: [
                    if (known)
                      SizedBox.expand(
                        child: CircularProgressIndicator(
                          value: share,
                          strokeWidth: 2.5,
                          backgroundColor: t.line,
                          color: share >= 1 ? t.danger : t.accent,
                        ),
                      ),
                    AppSvgIcon(AppIcons.user, size: 18, color: t.text),
                  ],
                ),
              ),
            ),
          ),
        ),
      ),
    );
  }
}

String driveViewLabel(DriveView v) => switch (v) {
  DriveView.files => 'vault.view_files',
  DriveView.recent => 'vault.view_recent',
  DriveView.media => 'vault.view_media',
  DriveView.documents => 'vault.view_documents',
  DriveView.audio => 'vault.view_audio',
  DriveView.trash => 'vault.view_trash',
}.tr();

String driveViewIcon(DriveView v) => switch (v) {
  DriveView.files => AppIcons.folder,
  DriveView.recent => AppIcons.clock,
  DriveView.media => AppIcons.image,
  DriveView.documents => AppIcons.fileDocument,
  DriveView.audio => AppIcons.fileAudio,
  DriveView.trash => AppIcons.trashDelete,
};

/// The views, as a sidebar (computers and tablets), with storage at the
/// bottom.
class DriveSidebar extends StatelessWidget {
  const DriveSidebar({
    super.key,
    required this.ctrl,
    required this.storage,
    required this.onTransfers,
    required this.onAccount,
    required this.transfersBusy,
  });

  final DriveController ctrl;
  final Widget storage;
  final VoidCallback onTransfers;
  final VoidCallback onAccount;
  final bool transfersBusy;

  @override
  Widget build(BuildContext context) {
    final cs = ShadTheme.of(context).colorScheme;
    Widget item(
      String label,
      String icon,
      bool on,
      VoidCallback onTap, {
      Widget? trailing,
    }) => Padding(
      padding: const EdgeInsets.symmetric(horizontal: 10, vertical: 1),
      child: Material(
        color: on ? cs.primary.withValues(alpha: 0.12) : Colors.transparent,
        borderRadius: BorderRadius.circular(10),
        child: InkWell(
          borderRadius: BorderRadius.circular(10),
          onTap: onTap,
          child: Padding(
            padding: const EdgeInsets.symmetric(horizontal: 12, vertical: 9),
            child: Row(
              children: [
                AppSvgIcon(
                  icon,
                  size: 17,
                  color: on ? cs.primary : cs.mutedForeground,
                ),
                const SizedBox(width: 12),
                Expanded(
                  child: Text(
                    label,
                    style: TextStyle(
                      fontSize: 14,
                      fontWeight: on ? FontWeight.w600 : FontWeight.w500,
                      color: on ? cs.primary : cs.foreground,
                    ),
                  ),
                ),
                ?trailing,
              ],
            ),
          ),
        ),
      ),
    );
    return SizedBox(
      width: 236,
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.stretch,
        children: [
          const SizedBox(height: 8),
          for (final v in DriveView.values)
            item(
              driveViewLabel(v),
              driveViewIcon(v),
              ctrl.view == v && !ctrl.searching,
              () => ctrl.setView(v),
            ),
          const SizedBox(height: 10),
          Divider(color: cs.border, indent: 18, endIndent: 18),
          item(
            'vault.transfers'.tr(),
            AppIcons.transferP2p,
            false,
            onTransfers,
            trailing: transfersBusy
                ? const SizedBox(
                    width: 12,
                    height: 12,
                    child: CircularProgressIndicator(strokeWidth: 2),
                  )
                : null,
          ),
          item('vault.account_title'.tr(), AppIcons.settings, false, onAccount),
          const Spacer(),
          storage,
        ],
      ),
    );
  }
}

/// Used of quota, with the share of each kind of file.
class DriveStorageCard extends StatelessWidget {
  const DriveStorageCard({
    super.key,
    required this.used,
    required this.quota,
    required this.byKind,
    this.onTap,
  });

  final int? used;
  final int? quota;

  /// Stored bytes per kind ('media', 'documents', 'audio', 'other', 'trash').
  final Map<String, int> byKind;
  final VoidCallback? onTap;

  static const colors = {
    'media': Color(0xFF0A84FF),
    'documents': Color(0xFFFF9F0A),
    'audio': Color(0xFFFF375F),
    'other': Color(0xFF8E8E93),
    'trash': Color(0xFF636366),
  };

  @override
  Widget build(BuildContext context) {
    final cs = ShadTheme.of(context).colorScheme;
    final q = quota ?? 0;
    final u = used ?? byKind.values.fold<int>(0, (a, b) => a + b);
    return InkWell(
      onTap: onTap,
      borderRadius: BorderRadius.circular(14),
      child: Container(
        margin: const EdgeInsets.fromLTRB(12, 8, 12, 12),
        padding: const EdgeInsets.all(12),
        decoration: BoxDecoration(
          color: cs.card,
          borderRadius: BorderRadius.circular(14),
          border: Border.all(color: cs.border.withValues(alpha: 0.8)),
        ),
        child: Column(
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            Text(
              q > 0
                  ? 'vault.quota_line'.tr(
                      namedArgs: {
                        'used': decimalBytes(u),
                        'quota': decimalBytes(q),
                      },
                    )
                  : decimalBytes(u),
              style: TextStyle(
                fontSize: 13,
                fontWeight: FontWeight.w600,
                color: cs.foreground,
              ),
            ),
            const SizedBox(height: 8),
            DriveStorageBar(used: used, quota: quota, byKind: byKind),
          ],
        ),
      ),
    );
  }
}

/// The quota as one bar, coloured by kind ([DriveStorageCard.colors]).
class DriveStorageBar extends StatelessWidget {
  const DriveStorageBar({
    super.key,
    required this.used,
    required this.quota,
    required this.byKind,
    this.height = 7,
  });

  final int? used;
  final int? quota;
  final Map<String, int> byKind;
  final double height;

  @override
  Widget build(BuildContext context) {
    final colors = DriveStorageCard.colors;
    final q = quota ?? 0;
    final u = used ?? byKind.values.fold<int>(0, (a, b) => a + b);
    return ClipRRect(
      borderRadius: BorderRadius.circular(height / 2),
      child: SizedBox(
        height: height,
        child: LayoutBuilder(
          builder: (context, c) {
            // Over the quota (read-only after a plan ended) the bar
            // is simply full.
            final total = max(q, u) > 0 ? max(q, u) : 1;
            // The index knows the kinds, the server knows the total
            // (thumbnails, uploads in progress): scale one to the other.
            final known = byKind.values.fold<int>(0, (a, b) => a + b);
            final scale = known > 0 && used != null ? u / known : 1.0;
            final widths = {
              for (final k in colors.keys)
                if ((byKind[k] ?? 0) > 0)
                  k: max(1.5, c.maxWidth * (byKind[k]! * scale / total)),
            };
            final sum = widths.values.fold<double>(0, (a, b) => a + b);
            final fit = sum > c.maxWidth ? c.maxWidth / sum : 1.0;
            return Stack(
              children: [
                // The line colour: muted vanishes on a dark card.
                Container(color: context.tokens.line),
                Row(
                  children: [
                    for (final e in widths.entries)
                      Container(width: e.value * fit, color: colors[e.key]),
                  ],
                ),
              ],
            );
          },
        ),
      ),
    );
  }
}

/// The actions for what is selected: the app's one selection bar (the
/// same as in Send and the Inbox), with the count and a way out.
class DriveSelectionBar extends StatelessWidget {
  const DriveSelectionBar({
    super.key,
    required this.count,
    required this.onClear,
    required this.actions,
  });

  final int count;
  final VoidCallback onClear;

  /// (icon, label, action, destructive). Destructive actions ask first in
  /// DriveActions; on the bar they read like the others.
  final List<(String, String, VoidCallback, bool)> actions;

  @override
  Widget build(BuildContext context) => SafeArea(
    top: false,
    child: AppSelectionBar(
      visible: true,
      onClear: onClear,
      summary: AppSelectionSummary(
        title: 'vault.n_selected'.tr(namedArgs: {'count': '$count'}),
      ),
      actions: [
        for (final (icon, label, onTap, _) in actions)
          AppBarAction(icon: icon, label: label, onTap: onTap),
      ],
    ),
  );
}
