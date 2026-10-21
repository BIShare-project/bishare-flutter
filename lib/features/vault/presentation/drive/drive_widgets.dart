import 'dart:math';
import 'dart:typed_data';

import 'package:easy_localization/easy_localization.dart';
import 'package:flutter/material.dart';
import 'package:shadcn_ui/shadcn_ui.dart';

import '../../../../core/di/locator.dart';
import '../../../../core/storage/app_database.dart';
import '../../../../core/ui/app_ui.dart';
import '../../../settings/presentation/widgets/glyph.dart';
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
      return SizedBox(
        width: widget.size,
        height: widget.size,
        child: FittedBox(child: const Glyph(AppIcons.folder)),
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
    final cs = ShadTheme.of(context).colorScheme;
    final o = object;
    final sub = _subtitle(context, o, items);
    return Material(
      color: selected ? cs.primary.withValues(alpha: 0.09) : Colors.transparent,
      child: InkWell(
        onTap: onTap,
        onLongPress: onLongPress,
        child: Padding(
          padding: const EdgeInsets.symmetric(horizontal: 14, vertical: 9),
          child: Row(
            children: [
              if (selecting) ...[
                _Check(on: selected),
                const SizedBox(width: 12),
              ],
              DriveThumb(object: o, size: 38),
              const SizedBox(width: 12),
              Expanded(
                child: Column(
                  crossAxisAlignment: CrossAxisAlignment.start,
                  children: [
                    Text(
                      o.name,
                      maxLines: 1,
                      overflow: TextOverflow.ellipsis,
                      style: TextStyle(
                        fontSize: 15,
                        fontWeight: FontWeight.w600,
                        color: cs.foreground,
                      ),
                    ),
                    const SizedBox(height: 2),
                    Text(
                      location == null ? sub : '$location · $sub',
                      maxLines: 1,
                      overflow: TextOverflow.ellipsis,
                      style: TextStyle(
                        fontSize: 12.5,
                        color: cs.mutedForeground,
                      ),
                    ),
                  ],
                ),
              ),
              if (!selecting)
                IconButton(
                  onPressed: onMore,
                  visualDensity: VisualDensity.compact,
                  icon: AppSvgIcon(
                    AppIcons.moreMenu,
                    size: 18,
                    color: cs.mutedForeground,
                  ),
                ),
            ],
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
    return Material(
      color: Colors.transparent,
      child: InkWell(
        borderRadius: BorderRadius.circular(14),
        onTap: onTap,
        onLongPress: onLongPress,
        child: Container(
          decoration: BoxDecoration(
            color: selected ? cs.primary.withValues(alpha: 0.10) : cs.card,
            borderRadius: BorderRadius.circular(14),
            border: Border.all(
              color: selected ? cs.primary : cs.border.withValues(alpha: 0.8),
              width: selected ? 1.6 : 1,
            ),
          ),
          padding: const EdgeInsets.all(8),
          child: Column(
            crossAxisAlignment: CrossAxisAlignment.start,
            children: [
              Expanded(
                child: Stack(
                  children: [
                    Positioned.fill(
                      child: LayoutBuilder(
                        builder: (context, c) => Center(
                          child: o.kind == 'file' && o.hasThumb
                              ? DriveThumb(
                                  object: o,
                                  size: c.biggest.shortestSide,
                                  radius: 10,
                                )
                              : DriveThumb(
                                  object: o,
                                  size: c.biggest.shortestSide * 0.55,
                                ),
                        ),
                      ),
                    ),
                    if (selecting)
                      Positioned(top: 2, left: 2, child: _Check(on: selected)),
                    if (!selecting)
                      Positioned(
                        top: -4,
                        right: -4,
                        child: IconButton(
                          onPressed: onMore,
                          visualDensity: VisualDensity.compact,
                          icon: AppSvgIcon(
                            AppIcons.moreMenu,
                            size: 16,
                            color: cs.mutedForeground,
                          ),
                        ),
                      ),
                  ],
                ),
              ),
              const SizedBox(height: 6),
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
                style: TextStyle(fontSize: 11.5, color: cs.mutedForeground),
              ),
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
    final cs = ShadTheme.of(context).colorScheme;
    final path = ctrl.path;
    if (path.isEmpty) return const SizedBox.shrink();
    Widget crumb(String label, VoidCallback? onTap, {bool last = false}) =>
        InkWell(
          borderRadius: BorderRadius.circular(8),
          onTap: onTap,
          child: Padding(
            padding: const EdgeInsets.symmetric(horizontal: 6, vertical: 4),
            child: Text(
              label,
              style: TextStyle(
                fontSize: 13,
                fontWeight: last ? FontWeight.w600 : FontWeight.w500,
                color: last ? cs.foreground : cs.primary,
              ),
            ),
          ),
        );
    Widget sep() =>
        Icon(Icons.chevron_right_rounded, size: 16, color: cs.mutedForeground);
    return SizedBox(
      height: 34,
      child: ListView(
        scrollDirection: Axis.horizontal,
        reverse: true,
        padding: const EdgeInsets.symmetric(horizontal: 12),
        children: [
          // Reversed so the current folder is in view when the path is long.
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
    final cs = ShadTheme.of(context).colorScheme;
    return Padding(
      padding: const EdgeInsets.fromLTRB(14, 4, 14, 6),
      child: Row(
        children: [
          Expanded(
            child: ShadInput(
              controller: search,
              focusNode: searchFocus,
              placeholder: Text('vault.search'.tr()),
              leading: const Padding(
                padding: EdgeInsets.only(right: 4),
                child: AppSvgIcon(AppIcons.search, size: 16),
              ),
              trailing: ctrl.searching
                  ? GestureDetector(
                      onTap: () {
                        search.clear();
                        ctrl.setQuery('');
                      },
                      child: AppSvgIcon(
                        AppIcons.close,
                        size: 14,
                        color: cs.mutedForeground,
                      ),
                    )
                  : null,
              onChanged: ctrl.setQuery,
            ),
          ),
          const SizedBox(width: 6),
          ShadButton.ghost(
            size: ShadButtonSize.sm,
            // Recent is newest first, always.
            onPressed: ctrl.view == DriveView.recent && !ctrl.searching
                ? null
                : () => _sortMenu(context),
            leading: AppSvgIcon(AppIcons.sort, size: 16, color: cs.foreground),
            child: Text('vault.sort_${ctrl.sort.name}'.tr()),
          ),
          ShadIconButton.ghost(
            onPressed: () => ctrl.setGrid(!ctrl.grid),
            icon: AppSvgIcon(
              ctrl.grid ? AppIcons.listView : AppIcons.gridView,
              size: 18,
            ),
          ),
          ...trailing,
        ],
      ),
    );
  }
}

/// The views, as chips (phones).
class DriveViewChips extends StatelessWidget {
  const DriveViewChips({super.key, required this.ctrl});

  final DriveController ctrl;

  @override
  Widget build(BuildContext context) {
    final cs = ShadTheme.of(context).colorScheme;
    return SizedBox(
      height: 38,
      child: ListView(
        scrollDirection: Axis.horizontal,
        padding: const EdgeInsets.symmetric(horizontal: 14),
        children: [
          for (final v in DriveView.values)
            Padding(
              padding: const EdgeInsets.only(right: 6, bottom: 4),
              child: _Chip(
                label: driveViewLabel(v),
                icon: driveViewIcon(v),
                on: ctrl.view == v && !ctrl.searching,
                onTap: () => ctrl.setView(v),
                cs: cs,
              ),
            ),
        ],
      ),
    );
  }
}

class _Chip extends StatelessWidget {
  const _Chip({
    required this.label,
    required this.icon,
    required this.on,
    required this.onTap,
    required this.cs,
  });

  final String label;
  final String icon;
  final bool on;
  final VoidCallback onTap;
  final ShadColorScheme cs;

  @override
  Widget build(BuildContext context) => InkWell(
    borderRadius: BorderRadius.circular(20),
    onTap: () {
      tapHaptic();
      onTap();
    },
    child: AnimatedContainer(
      duration: const Duration(milliseconds: 150),
      padding: const EdgeInsets.symmetric(horizontal: 12),
      decoration: BoxDecoration(
        color: on ? cs.primary : cs.card,
        borderRadius: BorderRadius.circular(20),
        border: Border.all(color: on ? cs.primary : cs.border),
      ),
      child: Row(
        mainAxisSize: MainAxisSize.min,
        children: [
          AppSvgIcon(
            icon,
            size: 14,
            color: on ? Colors.white : cs.mutedForeground,
          ),
          const SizedBox(width: 6),
          Text(
            label,
            style: TextStyle(
              fontSize: 13,
              fontWeight: FontWeight.w600,
              color: on ? Colors.white : cs.foreground,
            ),
          ),
        ],
      ),
    ),
  );
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
            ClipRRect(
              borderRadius: BorderRadius.circular(4),
              child: SizedBox(
                height: 7,
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
                          k: max(
                            1.5,
                            c.maxWidth * (byKind[k]! * scale / total),
                          ),
                    };
                    final sum = widths.values.fold<double>(0, (a, b) => a + b);
                    final fit = sum > c.maxWidth ? c.maxWidth / sum : 1.0;
                    return Stack(
                      children: [
                        Container(color: cs.muted),
                        Row(
                          children: [
                            for (final e in widths.entries)
                              Container(
                                width: e.value * fit,
                                color: colors[e.key],
                              ),
                          ],
                        ),
                      ],
                    );
                  },
                ),
              ),
            ),
          ],
        ),
      ),
    );
  }
}

/// The actions for what is selected, at the bottom.
class DriveSelectionBar extends StatelessWidget {
  const DriveSelectionBar({super.key, required this.actions});

  /// (icon, label, action, destructive)
  final List<(String, String, VoidCallback, bool)> actions;

  @override
  Widget build(BuildContext context) {
    final cs = ShadTheme.of(context).colorScheme;
    return Container(
      decoration: BoxDecoration(
        color: cs.card,
        border: Border(top: BorderSide(color: cs.border)),
      ),
      padding: const EdgeInsets.fromLTRB(6, 6, 6, 8),
      child: SafeArea(
        top: false,
        child: Row(
          children: [
            for (final (icon, label, onTap, destructive) in actions)
              Expanded(
                child: InkWell(
                  borderRadius: BorderRadius.circular(10),
                  onTap: () {
                    tapHaptic();
                    onTap();
                  },
                  child: Padding(
                    padding: const EdgeInsets.symmetric(vertical: 6),
                    child: Column(
                      mainAxisSize: MainAxisSize.min,
                      children: [
                        AppSvgIcon(
                          icon,
                          size: 20,
                          color: destructive ? cs.destructive : cs.foreground,
                        ),
                        const SizedBox(height: 4),
                        Text(
                          label,
                          maxLines: 1,
                          overflow: TextOverflow.ellipsis,
                          style: TextStyle(
                            fontSize: 11.5,
                            fontWeight: FontWeight.w500,
                            color: destructive ? cs.destructive : cs.foreground,
                          ),
                        ),
                      ],
                    ),
                  ),
                ),
              ),
          ],
        ),
      ),
    );
  }
}
