import 'dart:async';
import 'dart:io';

import 'package:easy_localization/easy_localization.dart';
import 'package:flutter/material.dart';
import 'package:flutter_bloc/flutter_bloc.dart';
import 'package:mime/mime.dart';
import 'package:photo_manager/photo_manager.dart';
import 'package:shadcn_ui/shadcn_ui.dart';

import '../../../core/apps/installed_apps_channel.dart';
import '../../../core/storage/app_database.dart';
import '../../../core/ui/app_ui.dart';
import '../../inbox/presentation/inbox_cubit.dart';
import '../../send/data/send_media_library.dart';
import '../../send/presentation/send_selection_cubit.dart';
import '../../send/presentation/tray_cubit.dart';
import '../../send/presentation/voice_recorder_sheet.dart';
import 'drive_interest_card.dart';

/// A selectable list row of the Send tab: leading art, title, meta, the round
/// check with the pick order. Rebuilds only when its own order changes.
class _PickRow extends StatelessWidget {
  const _PickRow({
    required this.selKey,
    required this.leading,
    required this.title,
    required this.meta,
    required this.onTap,
    this.trailingNote,
  });

  final String selKey;
  final Widget leading;
  final String title;
  final String meta;
  final VoidCallback onTap;
  final Widget? trailingNote;

  @override
  Widget build(BuildContext context) {
    return BlocSelector<SendSelectionCubit, SendSelection, int?>(
      selector: (s) => selKey.startsWith('path:')
          ? s.orderOfPath(selKey.substring(5))
          : s.orderOf(selKey),
      builder: (context, order) => Semantics(
        selected: order != null,
        child: ColoredBox(
          color: order != null ? context.tokens.accentSoft : Colors.transparent,
          child: AppListTile(
            leading: leading,
            title: Text(title, maxLines: 1, overflow: TextOverflow.ellipsis),
            subtitle: Text(meta, maxLines: 1, overflow: TextOverflow.ellipsis),
            trailing: Row(
              mainAxisSize: MainAxisSize.min,
              children: [
                ?trailingNote,
                AppRowCheck(selected: order != null, order: order),
              ],
            ),
            onTap: onTap,
          ),
        ),
      ),
    );
  }
}

/// A file-type tile for list rows.
class _FileArt extends StatelessWidget {
  const _FileArt(this.icon);
  final String icon;

  @override
  Widget build(BuildContext context) {
    final t = context.tokens;
    return Container(
      width: 44,
      height: 44,
      decoration: BoxDecoration(
        color: t.sunken,
        borderRadius: BorderRadius.circular(11),
      ),
      alignment: Alignment.center,
      child: AppSvgIcon(icon, size: 22, color: t.text2),
    );
  }
}

String _mime(String name) => lookupMimeType(name) ?? 'application/octet-stream';

bool _onDisk(TransferRecord r) =>
    r.savedPath != null && File(r.savedPath!).existsSync();

String _when(BuildContext context, DateTime t) =>
    DateFormat.MMMd(context.locale.toLanguageTag()).format(t);

/// Received files of a kind, as Send tab rows (Audio on iOS, Documents).
List<Widget> _receivedRows(
  BuildContext context,
  List<TransferRecord> records,
  SendKind kind,
) => [
  for (final r in records)
    _PickRow(
      selKey: 'path:${r.savedPath}',
      leading: _FileArt(fileIcon(_mime(r.fileName))),
      title: r.fileName,
      meta:
          '${'inbox.from'.tr(namedArgs: {'alias': r.deviceAlias})} · ${_when(context, r.timestamp)} · ${formatBytes(r.fileSize)}',
      onTap: () =>
          context.read<SendSelectionCubit>().toggleFile(r.savedPath!, kind),
    ),
];

/// The Audio tab (redesign-plan.md 3.4). Android lists the device's audio
/// (READ_MEDIA_AUDIO, outside the photo and video policy). iOS cannot read
/// the music library, so it shows audio received in BIShare, choosing from
/// Files, and recording.
class SendAudioTab extends StatefulWidget {
  const SendAudioTab({super.key});

  @override
  State<SendAudioTab> createState() => _SendAudioTabState();
}

class _SendAudioTabState extends State<SendAudioTab>
    with AutomaticKeepAliveClientMixin {
  final _lib = SendMediaLibrary.instance;
  SendMediaAccess _access = SendMediaAccess.unknown;
  List<AssetEntity> _audio = const [];
  AppLifecycleListener? _life;

  @override
  bool get wantKeepAlive => true;

  @override
  void initState() {
    super.initState();
    if (Platform.isAndroid) {
      unawaited(_check(false));
      _life = AppLifecycleListener(
        onResume: () {
          if (_access != SendMediaAccess.full) unawaited(_check(false));
        },
      );
    }
  }

  @override
  void dispose() {
    _life?.dispose();
    super.dispose();
  }

  Future<void> _check(bool ask) async {
    final a = await _lib.access(SendMediaKind.audio, ask: ask);
    if (!mounted) return;
    setState(() => _access = a);
    if (a == SendMediaAccess.none) return;
    final albums = await _lib.albums(SendMediaKind.audio);
    final all = albums.where((x) => x.isAll).firstOrNull ?? albums.firstOrNull;
    final list = all == null ? <AssetEntity>[] : await _lib.page(all, 0, 500);
    if (mounted) setState(() => _audio = list);
  }

  static String _clock(int s) =>
      '${s ~/ 60}:${(s % 60).toString().padLeft(2, '0')}';

  @override
  Widget build(BuildContext context) {
    super.build(context);
    final received = context
        .watch<InboxCubit>()
        .state
        .where((r) => _mime(r.fileName).startsWith('audio/') && _onDisk(r))
        .toList();
    return ListView(
      padding: const EdgeInsets.only(bottom: 140),
      children: [
        _Picks(
          first: (
            'compose.pick_from_files'.tr(),
            AppIcons.fileAudio,
            () {
              context.read<SendSelectionCubit>().hintNext(SendKind.audio);
              context.read<TrayCubit>().pickFiles();
            },
          ),
          second: (
            'compose.record'.tr(),
            AppIcons.mic,
            () async {
              final path = await showVoiceRecorder(context);
              if (path == null || !context.mounted) return;
              context.read<SendSelectionCubit>().hintNext(SendKind.audio);
              await context.read<TrayCubit>().addDropped([path]);
            },
          ),
        ),
        if (Platform.isAndroid) ...[
          if (_access == SendMediaAccess.none)
            AppEmptyState(
              icon: AppIcons.fileAudio,
              title: 'compose.access_title'.tr(),
              message: 'compose.access_body_audio'.tr(),
              action: AppButton(
                label: 'compose.allow'.tr(),
                onPressed: () => _check(true),
              ),
            )
          else ...[
            AppSectionHeader('compose.all_audio'.tr()),
            for (final a in _audio)
              _PickRow(
                selKey: 'a:${a.id}',
                leading: const _FileArt(AppIcons.fileAudio),
                title: a.title ?? '',
                meta: _clock(a.duration),
                onTap: () => context.read<SendSelectionCubit>().toggleAsset(
                  a,
                  SendKind.audio,
                ),
              ),
          ],
        ],
        AppSectionHeader('compose.audio_received'.tr()),
        if (received.isEmpty)
          Padding(
            padding: const EdgeInsets.fromLTRB(18, 0, 18, 12),
            child: Text(
              'compose.audio_empty'.tr(),
              style: AppType.secondary.copyWith(color: context.tokens.text2),
            ),
          )
        else
          ..._receivedRows(context, received, SendKind.audio),
      ],
    );
  }
}

/// Two actions at the top of a list tab, as full-width rows so a long label
/// never truncates in any language.
class _Picks extends StatelessWidget {
  const _Picks({required this.first, required this.second});

  final (String, String, VoidCallback) first;
  final (String, String, VoidCallback) second;

  @override
  Widget build(BuildContext context) {
    return Padding(
      padding: const EdgeInsets.only(top: 6),
      child: Column(
        children: [
          AppValueRow(icon: first.$2, title: first.$1, onTap: first.$3),
          const AppRowDivider(indent: 52),
          AppValueRow(icon: second.$2, title: second.$1, onTap: second.$3),
          const AppRowDivider(indent: 0),
        ],
      ),
    );
  }
}

/// The Apps tab (Android, redesign-plan.md 3.5): launcher apps from the
/// package manager, staged as APKs only when sending.
class SendAppsTab extends StatefulWidget {
  const SendAppsTab({super.key});

  @override
  State<SendAppsTab> createState() => _SendAppsTabState();
}

class _SendAppsTabState extends State<SendAppsTab>
    with AutomaticKeepAliveClientMixin {
  List<InstalledApp>? _apps;
  String _q = '';

  @override
  bool get wantKeepAlive => true;

  @override
  void initState() {
    super.initState();
    InstalledAppsChannel.list().then((apps) {
      if (mounted) setState(() => _apps = apps);
    });
  }

  @override
  Widget build(BuildContext context) {
    super.build(context);
    final t = context.tokens;
    final apps = _apps;
    if (apps == null) {
      return const Center(child: CircularProgressIndicator(strokeWidth: 2.4));
    }
    final q = _q.trim().toLowerCase();
    final shown = q.isEmpty
        ? apps
        : apps.where((a) => a.name.toLowerCase().contains(q)).toList();
    return CustomScrollView(
      slivers: [
        SliverToBoxAdapter(
          child: Padding(
            padding: const EdgeInsets.fromLTRB(14, 10, 14, 6),
            child: ShadInput(
              placeholder: Text('home.apps_search'.tr()),
              leading: AppSvgIcon(AppIcons.search, size: 18, color: t.text3),
              onChanged: (v) => setState(() => _q = v),
            ),
          ),
        ),
        if (shown.isEmpty)
          SliverToBoxAdapter(
            child: AppEmptyState(
              icon: AppIcons.gridView,
              title: 'home.apps_empty'.tr(),
              message: '',
            ),
          ),
        SliverList.builder(
          itemCount: shown.length,
          itemBuilder: (context, i) {
            final app = shown[i];
            final meta = [
              if (app.version.isNotEmpty) app.version,
              formatBytes(app.sizeBytes),
            ].join(' · ');
            return _PickRow(
              selKey: 'p:${app.packageName}',
              leading: ClipRRect(
                borderRadius: BorderRadius.circular(11),
                child: SizedBox.square(
                  dimension: 44,
                  child: app.icon == null
                      ? const _FileArt(AppIcons.gridView)
                      : Image.memory(
                          app.icon!,
                          fit: BoxFit.cover,
                          gaplessPlayback: true,
                          cacheWidth: 132,
                        ),
                ),
              ),
              title: app.name,
              meta: meta,
              trailingNote: app.isSplit
                  ? Padding(
                      padding: const EdgeInsetsDirectional.only(end: 8),
                      child: AppBadge('home.apps_split'.tr()),
                    )
                  : null,
              onTap: () => context.read<SendSelectionCubit>().toggleApp(app),
            );
          },
        ),
        const SliverToBoxAdapter(child: SizedBox(height: 140)),
      ],
    );
  }
}

/// The kinds the Documents tab filters by.
enum DocKind { all, pdf, word, excel, slides, archive, apk }

DocKind? docKindOf(String name) {
  final n = name.toLowerCase();
  if (n.endsWith('.pdf')) return DocKind.pdf;
  if (RegExp(r'\.(docx?|odt|rtf|pages|txt|md)$').hasMatch(n)) {
    return DocKind.word;
  }
  if (RegExp(r'\.(xlsx?|ods|csv|numbers)$').hasMatch(n)) return DocKind.excel;
  if (RegExp(r'\.(pptx?|odp|key)$').hasMatch(n)) return DocKind.slides;
  if (RegExp(r'\.(zip|rar|7z|tar|gz|tgz)$').hasMatch(n)) return DocKind.archive;
  if (RegExp(r'\.(apks?)$').hasMatch(n)) return DocKind.apk;
  return null;
}

/// The Documents tab (redesign-plan.md 3.6): choose from Files, send a folder
/// (zipped), and the documents already received in BIShare by kind.
class SendDocsTab extends StatefulWidget {
  const SendDocsTab({super.key});

  @override
  State<SendDocsTab> createState() => _SendDocsTabState();
}

class _SendDocsTabState extends State<SendDocsTab>
    with AutomaticKeepAliveClientMixin {
  DocKind _kind = DocKind.all;

  @override
  bool get wantKeepAlive => true;

  @override
  Widget build(BuildContext context) {
    super.build(context);
    final t = context.tokens;
    final kinds = [
      (DocKind.all, 'compose.doc_all'.tr()),
      (DocKind.pdf, 'compose.doc_pdf'.tr()),
      (DocKind.word, 'compose.doc_word'.tr()),
      (DocKind.excel, 'compose.doc_excel'.tr()),
      (DocKind.slides, 'compose.doc_slides'.tr()),
      (DocKind.archive, 'compose.doc_archive'.tr()),
      if (Platform.isAndroid) (DocKind.apk, 'compose.doc_apk'.tr()),
    ];
    final docs = context.watch<InboxCubit>().state.where((r) {
      final k = docKindOf(r.fileName);
      return k != null && (_kind == DocKind.all || k == _kind) && _onDisk(r);
    }).toList();
    final picked = context
        .watch<SendSelectionCubit>()
        .state
        .entries
        .whereType<FileEntry>()
        .where(
          (e) =>
              e.kind == SendKind.doc &&
              !docs.any((r) => r.savedPath == e.file.path),
        )
        .toList();
    return ListView(
      padding: const EdgeInsets.only(bottom: 140),
      children: [
        _Picks(
          first: (
            'compose.pick_from_files'.tr(),
            AppIcons.fileDocument,
            () {
              context.read<SendSelectionCubit>().hintNext(SendKind.doc);
              context.read<TrayCubit>().pickFiles();
            },
          ),
          second: (
            'compose.send_folder'.tr(),
            AppIcons.folder,
            () {
              context.read<SendSelectionCubit>().hintNext(SendKind.doc);
              context.read<TrayCubit>().pickFolder();
            },
          ),
        ),
        AppChips<DocKind>(
          value: _kind,
          options: kinds,
          onChanged: (k) => setState(() => _kind = k),
        ),
        if (picked.isNotEmpty) ...[
          AppSectionHeader('compose.added'.tr()),
          for (final e in picked)
            _PickRow(
              selKey: e.key,
              leading: _FileArt(fileIcon(e.file.mimeType)),
              title: e.file.name,
              meta: formatBytes(e.file.size),
              onTap: () => context.read<SendSelectionCubit>().remove(e),
            ),
        ],
        AppSectionHeader('compose.docs_received'.tr()),
        if (docs.isEmpty)
          Padding(
            padding: const EdgeInsets.fromLTRB(18, 0, 18, 12),
            child: Text(
              'compose.docs_empty'.tr(),
              style: AppType.secondary.copyWith(color: t.text2),
            ),
          )
        else
          ..._receivedRows(context, docs, SendKind.doc),
      ],
    );
  }
}

/// The More tab: text, contact, voice, paste, and what they added.
class SendMoreTab extends StatelessWidget {
  const SendMoreTab({super.key});

  @override
  Widget build(BuildContext context) {
    final added = context
        .watch<SendSelectionCubit>()
        .state
        .entries
        .whereType<FileEntry>()
        .where((e) => e.kind == SendKind.more)
        .toList();
    final tiles = [
      (
        AppIcons.note,
        'home.text'.tr(),
        'compose.more_text_sub'.tr(),
        () => composeTextNote(context),
      ),
      if (Platform.isAndroid || Platform.isIOS)
        (
          AppIcons.user,
          'home.contacts'.tr(),
          'compose.more_contact_sub'.tr(),
          () => composeContact(context),
        ),
      (
        AppIcons.mic,
        'home.voice'.tr(),
        'compose.more_voice_sub'.tr(),
        () => composeVoice(context),
      ),
      (
        AppIcons.clipboardPaste,
        'home.paste'.tr(),
        'compose.more_paste_sub'.tr(),
        () => composePaste(context),
      ),
    ];
    final t = context.tokens;
    return ListView(
      padding: const EdgeInsets.fromLTRB(14, 14, 14, 140),
      children: [
        // The one-time paid-storage question, while its flag is on.
        const DriveInterestCard(),
        GridView.count(
          crossAxisCount: 2,
          shrinkWrap: true,
          physics: const NeverScrollableScrollPhysics(),
          mainAxisSpacing: 10,
          crossAxisSpacing: 10,
          childAspectRatio: 1.45,
          children: [
            for (final (icon, title, sub, onTap) in tiles)
              Material(
                color: t.sunken,
                borderRadius: BorderRadius.circular(14),
                child: InkWell(
                  borderRadius: BorderRadius.circular(14),
                  onTap: () {
                    tapHaptic();
                    onTap();
                  },
                  child: Padding(
                    padding: const EdgeInsets.all(14),
                    child: Column(
                      crossAxisAlignment: CrossAxisAlignment.start,
                      mainAxisAlignment: MainAxisAlignment.spaceBetween,
                      children: [
                        AppSvgIcon(icon, size: 24, color: t.text),
                        Column(
                          crossAxisAlignment: CrossAxisAlignment.start,
                          children: [
                            Text(
                              title,
                              style: AppType.rowStrong.copyWith(color: t.text),
                            ),
                            Text(
                              sub,
                              maxLines: 2,
                              overflow: TextOverflow.ellipsis,
                              style: AppType.small.copyWith(
                                fontWeight: FontWeight.w400,
                                color: t.text2,
                              ),
                            ),
                          ],
                        ),
                      ],
                    ),
                  ),
                ),
              ),
          ],
        ),
        if (added.isNotEmpty) ...[
          const SizedBox(height: 8),
          AppSectionHeader('compose.added'.tr()),
          for (final e in added)
            _PickRow(
              selKey: e.key,
              leading: _FileArt(fileIcon(e.file.mimeType)),
              title: e.file.name,
              meta: formatBytes(e.file.size),
              onTap: () => context.read<SendSelectionCubit>().remove(e),
            ),
        ],
      ],
    );
  }
}

// ---- More-tab actions (moved from the old source grid) -----------------------

Future<void> composeContact(BuildContext context) async {
  context.read<SendSelectionCubit>().hintNext(SendKind.more);
  final ok = await context.read<TrayCubit>().pickContact();
  if (!ok && context.mounted) toast(context, 'home.no_contact_added'.tr());
}

Future<void> composeVoice(BuildContext context) async {
  final path = await showVoiceRecorder(context);
  if (path == null || !context.mounted) return;
  context.read<SendSelectionCubit>().hintNext(SendKind.more);
  await context.read<TrayCubit>().addDropped([path]);
}

Future<void> composePaste(BuildContext context) async {
  context.read<SendSelectionCubit>().hintNext(SendKind.more);
  final ok = await context.read<TrayCubit>().pasteClipboard();
  if (!ok && context.mounted) toast(context, 'home.clipboard_empty'.tr());
}

Future<void> composeTextNote(BuildContext context) async {
  final controller = TextEditingController();
  final text = await showAppSheet<String>(
    context,
    title: 'home.text_note'.tr(),
    subtitle: 'home.text_note_subtitle'.tr(),
    builder: (ctx) => Column(
      mainAxisSize: MainAxisSize.min,
      children: [
        ShadInput(
          controller: controller,
          autofocus: true,
          maxLines: 4,
          placeholder: Text('home.type_something'.tr()),
        ),
        const SizedBox(height: 14),
        AppButton(
          label: 'home.add'.tr(),
          fullWidth: true,
          onPressed: () => Navigator.pop(ctx, controller.text),
        ),
      ],
    ),
  );
  if (text == null || text.trim().isEmpty || !context.mounted) return;
  context.read<SendSelectionCubit>().hintNext(SendKind.more);
  await context.read<TrayCubit>().addText(text);
}
