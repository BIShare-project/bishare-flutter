import 'dart:async';
import 'dart:io';

import 'package:easy_localization/easy_localization.dart';
import 'package:file_picker/file_picker.dart';
import 'package:flutter/material.dart';
import 'package:flutter/services.dart';
import 'package:gal/gal.dart';
import 'package:mime/mime.dart';
import 'package:shadcn_ui/shadcn_ui.dart';
import 'package:share_plus/share_plus.dart';

import '../../../../core/config/feature_flags.dart';
import '../../../../core/di/locator.dart';
import '../../../../core/io/media_picker.dart';
import '../../../../core/server/transfer_server.dart';
import '../../../../core/storage/app_database.dart';
import '../../../../core/storage/vault_tables.dart';
import '../../../../core/ui/app_ui.dart';
import '../../data/vault_account.dart';
import '../../data/vault_api.dart';
import '../../data/vault_downloads.dart';
import '../../data/vault_files.dart';
import '../../data/vault_keys.dart';
import '../../data/vault_meta.dart';
import '../../data/vault_shares.dart';
import '../../data/vault_uploader.dart';
import 'drive_controller.dart';
import 'drive_format.dart';

/// Everything a Drive item can have done to it, with the sheets and messages
/// that go with it (drive-plan.md tasks 4.7, 4.8, 4.10).
class DriveActions {
  DriveActions(this.context, this.ctrl);

  final BuildContext context;
  final DriveController ctrl;

  VaultDao get _dao => getIt<AppDatabase>().vaultDao;
  VaultFiles get _files => getIt<VaultFiles>();
  VaultUploader get _uploader => getIt<VaultUploader>();
  VaultDownloads get _downloads => getIt<VaultDownloads>();

  static bool get _phone => Platform.isAndroid || Platform.isIOS;

  void _say(
    String key, {
    ToastType type = ToastType.info,
    Map<String, String>? args,
  }) {
    if (context.mounted) toast(context, key.tr(namedArgs: args), type: type);
  }

  String _errorKey(Object e) => switch (e is VaultApiException ? e.code : '') {
    'NETWORK' => 'vault.error_network',
    'VAULT_BAD_NAME' => 'vault.error_bad_name',
    'VAULT_MOVE_INTO_ITSELF' => 'vault.error_move_into_itself',
    'STORAGE_LIMIT_EXCEEDED' => 'vault.error_full',
    'VAULT_READ_ONLY' => 'vault.error_read_only',
    'TRANSFER_TOO_LARGE' => 'vault.error_too_large_to_share',
    'TRANSFER_RATE_LIMITED' => 'vault.error_rate_limited',
    _ => 'vault.error_generic',
  };

  Future<bool> _guard(Future<void> Function() step) async {
    try {
      await step();
      return true;
    } on Object catch (e) {
      debugPrint('[vault] $e');
      _say(_errorKey(e), type: ToastType.error);
      return false;
    }
  }

  // ---- adding ------------------------------------------------------------------------

  Future<void> addFiles() async {
    final res = await FilePicker.platform.pickFiles(allowMultiple: true);
    final paths = res?.paths.whereType<String>().toList() ?? const [];
    await _enqueue(paths);
  }

  Future<void> addMedia() async => _enqueue(await pickMediaPaths());

  /// Desktop: a whole folder, with its folders.
  Future<void> addFolder() async {
    final path = await FilePicker.platform.getDirectoryPath();
    if (path == null) return;
    await _guard(() async {
      final n = await _uploader.enqueueFolder(
        Directory(path),
        _files,
        parent: ctrl.folder,
      );
      _say('vault.queued_n', args: {'count': '$n'});
    });
  }

  /// Files and folders dropped on the window (desktop).
  Future<void> dropped(List<String> paths) async {
    if (!ctrl.canAdd) {
      _say('vault.drop_only_in_folders');
      return;
    }
    final files = <String>[];
    for (final p in paths) {
      if (await FileSystemEntity.isDirectory(p)) {
        await _guard(() async {
          await _uploader.enqueueFolder(
            Directory(p),
            _files,
            parent: ctrl.folder,
          );
        });
      } else {
        files.add(p);
      }
    }
    await _enqueue(files);
  }

  Future<void> _enqueue(List<String> paths) async {
    if (paths.isEmpty) return;
    await _guard(() async {
      await _uploader.enqueue([
        for (final p in paths) File(p),
      ], parent: ctrl.folder);
      _say('vault.queued_n', args: {'count': '${paths.length}'});
    });
  }

  /// The "+" menu.
  Future<void> addMenu() async {
    final pick = await showAppSheet<String>(
      context,
      icon: AppIcons.uploadFile,
      title: 'vault.add_title'.tr(),
      builder: (ctx) => Column(
        mainAxisSize: MainAxisSize.min,
        children: [
          if (_phone)
            AppSheetAction(
              icon: AppIcons.image,
              label: 'vault.add_media'.tr(),
              onTap: () => Navigator.pop(ctx, 'media'),
            ),
          AppSheetAction(
            icon: AppIcons.fileDocument,
            label: 'vault.add_files'.tr(),
            onTap: () => Navigator.pop(ctx, 'files'),
          ),
          if (!_phone)
            AppSheetAction(
              icon: AppIcons.folderOpen,
              label: 'vault.add_folder'.tr(),
              onTap: () => Navigator.pop(ctx, 'folder'),
            ),
          AppSheetAction(
            icon: AppIcons.newFolder,
            label: 'vault.new_folder'.tr(),
            onTap: () => Navigator.pop(ctx, 'mkdir'),
          ),
        ],
      ),
    );
    switch (pick) {
      case 'media':
        await addMedia();
      case 'files':
        await addFiles();
      case 'folder':
        await addFolder();
      case 'mkdir':
        await newFolder();
    }
  }

  Future<void> newFolder() async {
    final name = await askName(
      title: 'vault.new_folder'.tr(),
      initial: '',
      action: 'vault.create'.tr(),
    );
    if (name == null) return;
    await _guard(() => _files.mkdir(name, parent: ctrl.folder));
  }

  Future<String?> askName({
    required String title,
    required String initial,
    required String action,
  }) async {
    final controller = TextEditingController(text: initial);
    // Select the name without its extension, as file managers do.
    final dot = initial.lastIndexOf('.');
    controller.selection = TextSelection(
      baseOffset: 0,
      extentOffset: dot > 0 ? dot : initial.length,
    );
    final name = await showAppSheet<String>(
      context,
      icon: AppIcons.renameEdit,
      title: title,
      builder: (ctx) {
        void submit() => Navigator.pop(ctx, controller.text.trim());
        return Column(
          mainAxisSize: MainAxisSize.min,
          children: [
            ShadInput(
              controller: controller,
              autofocus: true,
              placeholder: Text('vault.name_hint'.tr()),
              onSubmitted: (_) => submit(),
            ),
            const SizedBox(height: 14),
            SizedBox(
              width: double.infinity,
              child: ShadButton(onPressed: submit, child: Text(action)),
            ),
          ],
        );
      },
    );
    controller.dispose();
    return name == null || name.isEmpty || name == initial ? null : name;
  }

  // ---- opening and getting files out ----------------------------------------------------

  Future<void> open(VaultObject o) async {
    if (o.kind == 'dir') {
      if (ctrl.view == DriveView.trash) return;
      if (ctrl.view != DriveView.files || ctrl.searching) {
        await ctrl.reveal(o.id);
      } else {
        ctrl.open(o);
      }
      return;
    }
    final f = await fetch(o, purpose: 'open');
    if (f == null || !context.mounted) return;
    await showFilePreview(
      context,
      path: f.path,
      name: o.name,
      mimeType: o.mime ?? lookupMimeType(o.name) ?? 'application/octet-stream',
      size: o.size,
    );
  }

  /// [o] in a cache folder (reused while it is there), with a progress sheet
  /// that can cancel. Null when cancelled or failed.
  Future<File?> fetch(VaultObject o, {required String purpose}) async {
    final dir = await VaultDownloads.cacheFor(purpose, o.id);
    final target = File('${dir.path}/${safeFileName(o.name)}');
    if (await target.exists() && await target.length() == (o.size ?? -1)) {
      return target;
    }
    await dir.create(recursive: true);
    if (!context.mounted) return null;
    var cancelled = false;
    VaultDownloadJob? job;
    BuildContext? sheetContext;
    final sheet = showAppSheet<void>(
      context,
      icon: AppIcons.downloadFile,
      title: o.name,
      subtitle: 'vault.getting'.tr(),
      dismissible: false,
      builder: (ctx) {
        sheetContext = ctx;
        return Column(
          mainAxisSize: MainAxisSize.min,
          children: [
            ListenableBuilder(
              listenable: _downloads,
              builder: (_, _) => LinearProgressIndicator(value: job?.fraction),
            ),
            const SizedBox(height: 14),
            AppSheetAction(
              icon: AppIcons.close,
              label: 'vault.cancel'.tr(),
              onTap: () {
                cancelled = true;
                final j = job;
                if (j != null) _downloads.cancel(j);
                Navigator.pop(ctx);
              },
            ),
          ],
        );
      },
    );
    final run = _downloads.file(o, target);
    job = _downloads.jobs.isEmpty ? null : _downloads.jobs.first;
    final file = await run;
    final ctx = sheetContext;
    if (!cancelled && ctx != null && ctx.mounted) Navigator.pop(ctx);
    await sheet;
    if (file == null && !cancelled) {
      _say(_errorKey(job?.error ?? Object()), type: ToastType.error);
    }
    return cancelled ? null : file;
  }

  /// The system share sheet with the files of [items] (folders are skipped).
  Future<void> share(List<VaultObject> items) async {
    final files = <XFile>[];
    for (final o in items.where((o) => o.kind == 'file')) {
      final f = await fetch(o, purpose: 'open');
      if (f == null) return;
      files.add(XFile(f.path, mimeType: o.mime));
    }
    if (files.isEmpty) {
      _say('vault.share_only_files');
      return;
    }
    await SharePlus.instance.share(ShareParams(files: files));
  }

  /// Phones: photos and videos into the photo library.
  Future<void> saveToPhotos(List<VaultObject> items) async {
    var n = 0;
    for (final o in items.where((o) => isMedia(o.mime))) {
      final f = await fetch(o, purpose: 'open');
      if (f == null) return;
      final ok = await _guard(() async {
        if ((o.mime ?? '').startsWith('video/')) {
          await Gal.putVideo(f.path);
        } else {
          await Gal.putImage(f.path);
        }
      });
      if (ok) n++;
    }
    if (n > 0) {
      _say(
        'vault.saved_n_to_photos',
        type: ToastType.success,
        args: {'count': '$n'},
      );
    }
  }

  /// Computers: files and whole folders into the receive folder, or a folder
  /// the person picks ([choose]).
  Future<void> download(List<VaultObject> items, {bool choose = false}) async {
    Directory dir = getIt<TransferServer>().saveDirectory;
    if (choose) {
      final picked = await FilePicker.platform.getDirectoryPath();
      if (picked == null) return;
      dir = Directory(picked);
    }
    _say('vault.downloading_n', args: {'count': '${items.length}'});
    var ok = 0;
    for (final o in items) {
      if (o.kind == 'dir') {
        if (await _downloads.folder(o, dir) != null) ok++;
      } else {
        final out = freeLocalFile(dir, safeFileName(o.name));
        if (await _downloads.file(o, out) != null) ok++;
      }
    }
    if (ok > 0) {
      _say(
        'vault.saved_to',
        type: ToastType.success,
        args: {'folder': dir.path},
      );
    }
  }

  // ---- changing things --------------------------------------------------------------------

  Future<void> rename(VaultObject o) async {
    final name = await askName(
      title: 'vault.rename'.tr(),
      initial: o.name,
      action: 'vault.rename'.tr(),
    );
    if (name == null) return;
    await _guard(() => _files.rename(o.id, name));
  }

  Future<void> moveOrCopy(List<VaultObject> items, {required bool copy}) async {
    final target = await pickFolder(
      title: (copy ? 'vault.copy_to' : 'vault.move_to').tr(),
      action: (copy ? 'vault.copy_here' : 'vault.move_here').tr(),
      exclude: {
        for (final o in items)
          if (o.kind == 'dir') o.id,
      },
      start: ctrl.folder,
    );
    if (target == null) return;
    final parent = target.isEmpty ? null : target;
    final ids = [for (final o in items) o.id];
    final done = await _guard(() async {
      if (copy) {
        await _files.copy(ids, parent);
      } else {
        await _files.move(ids, parent);
      }
    });
    if (done) {
      ctrl.clearSelection();
      _say(copy ? 'vault.copied' : 'vault.moved', type: ToastType.success);
    }
  }

  Future<void> trash(List<VaultObject> items) async {
    final done = await _guard(
      () => _files.trash([for (final o in items) o.id]),
    );
    if (done) {
      ctrl.clearSelection();
      _say('vault.moved_to_trash', type: ToastType.success);
    }
  }

  Future<void> restore(List<VaultObject> items) async {
    final done = await _guard(
      () => _files.restore([for (final o in items) o.id]),
    );
    if (done) {
      ctrl.clearSelection();
      _say('vault.restored', type: ToastType.success);
    }
  }

  Future<void> deleteForGood(
    List<VaultObject> items, {
    bool all = false,
  }) async {
    final cs = ShadTheme.of(context).colorScheme;
    final ok = await showAppSheet<bool>(
      context,
      icon: AppIcons.trashDelete,
      iconColor: cs.destructive,
      title: all
          ? 'vault.empty_trash_title'.tr()
          : items.length == 1
          ? 'vault.delete_for_good_one'.tr(
              namedArgs: {'name': items.single.name},
            )
          : 'vault.delete_for_good_n'.tr(
              namedArgs: {'count': '${items.length}'},
            ),
      subtitle: 'vault.delete_for_good_body'.tr(),
      builder: (ctx) => Column(
        mainAxisSize: MainAxisSize.min,
        children: [
          AppSheetAction(
            icon: AppIcons.trashDelete,
            label: 'vault.delete_for_good'.tr(),
            destructive: true,
            onTap: () => Navigator.pop(ctx, true),
          ),
          AppSheetAction(
            icon: AppIcons.close,
            label: 'vault.cancel'.tr(),
            onTap: () => Navigator.pop(ctx, false),
          ),
        ],
      ),
    );
    if (ok != true) return;
    final done = await _guard(
      () => _files.deleteForGood([for (final o in items) o.id]),
    );
    if (done) ctrl.clearSelection();
  }

  // ---- information and links ------------------------------------------------------------

  Future<void> details(VaultObject o) async {
    final path = o.parent == null
        ? <VaultObject>[]
        : await _dao.pathTo(o.parent!);
    final location = [
      'vault.drive'.tr(),
      for (final p in path) p.name,
    ].join(' / ');
    final same = o.blobId == null ? 0 : await _dao.countWithBlob(o.blobId!) - 1;
    VaultMeta? meta;
    try {
      final keys = getIt<VaultKeyStore>();
      final vaultId = await keys.vaultId();
      final vk = await keys.vaultKey();
      if (vaultId != null && vk != null) {
        meta = VaultMetaCodec.open(vk, vaultId, o.id, o.encMeta);
      }
    } on Object {
      meta = null;
    }
    final counts = o.kind == 'dir'
        ? (await _dao.liveChildren(o.id)).length
        : null;
    if (!context.mounted) return;
    final locale = context.locale.toLanguageTag();
    String when(int ms) => DateFormat.yMMMd(
      locale,
    ).add_jm().format(DateTime.fromMillisecondsSinceEpoch(ms));
    final rows = <(String, String)>[
      (
        'vault.info_kind'.tr(),
        o.kind == 'dir' ? 'vault.folder'.tr() : kindLabel(o),
      ),
      if (o.kind == 'file') ('vault.info_size'.tr(), decimalBytes(o.size ?? 0)),
      if (o.kind == 'file' && o.blobSize != null)
        (
          'vault.info_stored'.tr(),
          meta?.compression == 'deflate'
              ? 'vault.info_stored_compressed'.tr(
                  namedArgs: {'size': decimalBytes(o.blobSize!)},
                )
              : decimalBytes(o.blobSize!),
        ),
      if (counts != null) ('vault.info_items'.tr(), '$counts'),
      ('vault.info_location'.tr(), location),
      ('vault.info_modified'.tr(), when(o.mtime)),
      ('vault.info_added'.tr(), when(o.createdAt)),
      if (same > 0)
        ('vault.info_same'.tr(), 'vault.info_same_value'.plural(same)),
    ];
    final muted = ShadTheme.of(context).textTheme.muted;
    await showAppSheet<void>(
      context,
      icon: o.kind == 'dir' ? AppIcons.folder : AppIcons.fileDocument,
      title: o.name,
      builder: (ctx) => Column(
        mainAxisSize: MainAxisSize.min,
        children: [
          for (final (k, v) in rows)
            Padding(
              padding: const EdgeInsets.symmetric(vertical: 6),
              child: Row(
                crossAxisAlignment: CrossAxisAlignment.start,
                children: [
                  SizedBox(width: 120, child: Text(k, style: muted)),
                  Expanded(child: SelectableText(v)),
                ],
              ),
            ),
          const SizedBox(height: 6),
          Text('vault.info_private'.tr(), style: muted.copyWith(fontSize: 12)),
        ],
      ),
    );
  }

  Future<void> shareLink(VaultObject o) async {
    final hours = ValueNotifier<int>(12);
    final oneTime = ValueNotifier<bool>(false);
    final go = await showAppSheet<bool>(
      context,
      icon: AppIcons.shareLink,
      title: 'vault.link_title'.tr(),
      subtitle: 'vault.link_body'.tr(namedArgs: {'name': o.name}),
      builder: (ctx) => Column(
        mainAxisSize: MainAxisSize.min,
        children: [
          ValueListenableBuilder<int>(
            valueListenable: hours,
            builder: (_, h, _) => Row(
              children: [
                for (final v in const [6, 12, 24])
                  Expanded(
                    child: Padding(
                      padding: const EdgeInsets.symmetric(horizontal: 4),
                      child: v == h
                          ? ShadButton(
                              onPressed: () {},
                              child: Text(
                                'vault.link_hours'.tr(namedArgs: {'h': '$v'}),
                              ),
                            )
                          : ShadButton.outline(
                              onPressed: () => hours.value = v,
                              child: Text(
                                'vault.link_hours'.tr(namedArgs: {'h': '$v'}),
                              ),
                            ),
                    ),
                  ),
              ],
            ),
          ),
          const SizedBox(height: 10),
          ValueListenableBuilder<bool>(
            valueListenable: oneTime,
            builder: (_, v, _) => ShadCheckbox(
              value: v,
              onChanged: (x) => oneTime.value = x,
              label: Text('vault.link_one_time'.tr()),
            ),
          ),
          const SizedBox(height: 14),
          SizedBox(
            width: double.infinity,
            child: ShadButton(
              onPressed: () => Navigator.pop(ctx, true),
              child: Text('vault.link_create'.tr()),
            ),
          ),
        ],
      ),
    );
    if (go != true) {
      hours.dispose();
      oneTime.dispose();
      return;
    }
    ({String url, DateTime? expiresAt, bool viaUpload})? made;
    await _guard(() async {
      made = await getIt<VaultShares>().share(
        o.id,
        hours: hours.value,
        oneTime: oneTime.value,
      );
    });
    hours.dispose();
    oneTime.dispose();
    final link = made;
    if (link == null || !context.mounted) return;
    await showAppSheet<void>(
      context,
      icon: AppIcons.linkCopy,
      title: 'vault.link_ready'.tr(),
      subtitle: link.expiresAt == null
          ? null
          : 'vault.link_until'.tr(
              namedArgs: {
                'when': DateFormat.MMMd(
                  context.locale.toLanguageTag(),
                ).add_jm().format(link.expiresAt!.toLocal()),
              },
            ),
      builder: (ctx) => Column(
        mainAxisSize: MainAxisSize.min,
        children: [
          BiShareQr(data: link.url, size: 200),
          const SizedBox(height: 12),
          SelectableText(link.url, maxLines: 2, textAlign: TextAlign.center),
          const SizedBox(height: 14),
          AppSheetAction(
            icon: AppIcons.copyDuplicate,
            label: 'vault.link_copy'.tr(),
            onTap: () async {
              await Clipboard.setData(ClipboardData(text: link.url));
              if (ctx.mounted) Navigator.pop(ctx);
              _say('vault.link_copied', type: ToastType.success);
            },
          ),
          AppSheetAction(
            icon: AppIcons.shareLink,
            label: 'vault.link_share'.tr(),
            onTap: () {
              Navigator.pop(ctx);
              SharePlus.instance.share(ShareParams(text: link.url));
            },
          ),
        ],
      ),
    );
  }

  // ---- the folder picker ----------------------------------------------------------------

  /// A folder of the Drive, browsed from [start]; '' for the top. Folders in
  /// [exclude] (the ones being moved) cannot be entered or chosen.
  Future<String?> pickFolder({
    required String title,
    required String action,
    Set<String> exclude = const {},
    String? start,
  }) async {
    final path = start == null ? <VaultObject>[] : await _dao.pathTo(start);
    if (!context.mounted) return null;
    return showAppSheet<String>(
      context,
      icon: AppIcons.moveFile,
      title: title,
      builder: (ctx) => _FolderPicker(
        initial: path,
        exclude: exclude,
        action: action,
        onNewFolder: (parent) async {
          final name = await askName(
            title: 'vault.new_folder'.tr(),
            initial: '',
            action: 'vault.create'.tr(),
          );
          if (name == null) return null;
          String? id;
          await _guard(
            () async => id = await _files.mkdir(name, parent: parent),
          );
          return id;
        },
      ),
    );
  }
}

/// Whether "Save to Drive" belongs on this device now: Drive is on for it
/// (the vault_enabled flag) and it holds the key.
bool get driveReady =>
    getIt.isRegistered<FeatureFlags>() &&
    getIt<FeatureFlags>().vaultVisible &&
    getIt.isRegistered<VaultAccount>() &&
    getIt<VaultAccount>().status == VaultStatus.ready;

/// "Save to Drive" from outside the Drive screens (a received file in Inbox,
/// files shared into the app): choose a folder, then the files join the
/// upload queue. False when the person closed the picker.
Future<bool> saveToDrive(BuildContext context, List<String> paths) async {
  if (paths.isEmpty) return false;
  final actions = DriveActions(
    context,
    DriveController(getIt<AppDatabase>().vaultDao),
  );
  final target = await actions.pickFolder(
    title: 'vault.save_to_drive'.tr(),
    action: 'vault.save_here'.tr(),
  );
  if (target == null) return false;
  try {
    await getIt<VaultUploader>().enqueue([
      for (final p in paths) File(p),
    ], parent: target.isEmpty ? null : target);
  } on Object catch (e) {
    debugPrint('[vault] save to Drive: $e');
    if (context.mounted) {
      toast(context, 'vault.error_generic'.tr(), type: ToastType.error);
    }
    return false;
  }
  if (context.mounted) {
    toast(
      context,
      'vault.queued_n'.tr(namedArgs: {'count': '${paths.length}'}),
      type: ToastType.success,
    );
  }
  return true;
}

class _FolderPicker extends StatefulWidget {
  const _FolderPicker({
    required this.initial,
    required this.exclude,
    required this.action,
    required this.onNewFolder,
  });

  final List<VaultObject> initial;
  final Set<String> exclude;
  final String action;
  final Future<String?> Function(String? parent) onNewFolder;

  @override
  State<_FolderPicker> createState() => _FolderPickerState();
}

class _FolderPickerState extends State<_FolderPicker> {
  late final List<VaultObject> _path = [
    for (final p in widget.initial)
      if (!widget.exclude.contains(p.id)) p,
  ];
  final VaultDao _dao = getIt<AppDatabase>().vaultDao;

  String? get _here => _path.isEmpty ? null : _path.last.id;

  @override
  Widget build(BuildContext context) {
    final muted = ShadTheme.of(context).textTheme.muted;
    return Column(
      mainAxisSize: MainAxisSize.min,
      crossAxisAlignment: CrossAxisAlignment.stretch,
      children: [
        Text(
          ['vault.drive'.tr(), for (final p in _path) p.name].join(' / '),
          style: muted,
          maxLines: 2,
          overflow: TextOverflow.ellipsis,
        ),
        const SizedBox(height: 8),
        ConstrainedBox(
          constraints: BoxConstraints(
            maxHeight: MediaQuery.of(context).size.height * 0.42,
          ),
          child: StreamBuilder<List<VaultObject>>(
            stream: _dao.watchChildren(_here),
            builder: (context, snap) {
              final folders = (snap.data ?? const <VaultObject>[])
                  .where(
                    (o) => o.kind == 'dir' && !widget.exclude.contains(o.id),
                  )
                  .toList();
              return ListView(
                shrinkWrap: true,
                children: [
                  if (_path.isNotEmpty)
                    AppSheetAction(
                      icon: AppIcons.chevronLeft,
                      label: _path.length > 1
                          ? _path[_path.length - 2].name
                          : 'vault.top_of_drive'.tr(),
                      onTap: () => setState(_path.removeLast),
                    ),
                  for (final f in folders)
                    AppSheetAction(
                      icon: AppIcons.folder,
                      label: f.name,
                      onTap: () => setState(() => _path.add(f)),
                    ),
                  if (snap.hasData && folders.isEmpty)
                    Padding(
                      padding: const EdgeInsets.symmetric(vertical: 12),
                      child: Text(
                        'vault.no_folders_here'.tr(),
                        style: muted,
                        textAlign: TextAlign.center,
                      ),
                    ),
                ],
              );
            },
          ),
        ),
        const SizedBox(height: 10),
        Row(
          children: [
            Expanded(
              child: ShadButton.outline(
                onPressed: () async {
                  final id = await widget.onNewFolder(_here);
                  if (id == null || !mounted) return;
                  final made = await _dao.object(id);
                  if (made != null && mounted) setState(() => _path.add(made));
                },
                child: Text('vault.new_folder'.tr()),
              ),
            ),
            const SizedBox(width: 8),
            Expanded(
              child: ShadButton(
                onPressed: () => Navigator.pop(context, _here ?? ''),
                child: Text(widget.action),
              ),
            ),
          ],
        ),
      ],
    );
  }
}
