import 'dart:io';
import 'dart:typed_data';

import 'package:easy_localization/easy_localization.dart';
import 'package:flutter/material.dart';
import 'package:mime/mime.dart';

import '../../../../core/di/locator.dart';
import '../../../../core/storage/app_database.dart';
import '../../../../core/ui/app_ui.dart';
import '../../data/vault_downloads.dart';
import '../../data/vault_thumbs.dart';
import 'drive_format.dart';

/// A Drive file beside the list on an open iPhone Duo: the file large (fetched
/// quietly into the preview cache), its name, size and date, and the same
/// actions as its menu. [onOpen] shows it full screen; [onClose] gives the
/// list the whole width again.
class DrivePreviewPane extends StatefulWidget {
  const DrivePreviewPane({
    super.key,
    required this.object,
    required this.actions,
    required this.onOpen,
    required this.onClose,
  });

  final VaultObject object;
  final List<AppMenuAction> actions;
  final VoidCallback onOpen;
  final VoidCallback onClose;

  @override
  State<DrivePreviewPane> createState() => _DrivePreviewPaneState();
}

class _DrivePreviewPaneState extends State<DrivePreviewPane> {
  Future<File?>? _file;

  /// The small picture the Drive already keeps, shown until the file is in
  /// (and instead of it when it cannot be fetched).
  Future<Uint8List?>? _thumb;

  @override
  void initState() {
    super.initState();
    _load();
  }

  @override
  void didUpdateWidget(DrivePreviewPane old) {
    super.didUpdateWidget(old);
    if (old.object.id != widget.object.id) _load();
  }

  /// Only photos are fetched for the preview; other files show their kind
  /// until opened (a document or video may be large).
  void _load() {
    final o = widget.object;
    _file = _isImage(o) ? _fetch(o) : null;
    _thumb = _isImage(o) ? getIt<VaultThumbs>().load(o) : null;
  }

  static bool _isImage(VaultObject o) =>
      (o.mime ?? lookupMimeType(o.name) ?? '').startsWith('image/');

  Future<File?> _fetch(VaultObject o) async {
    final dir = await VaultDownloads.cacheFor('open', o.id);
    final target = File('${dir.path}/${safeFileName(o.name)}');
    if (await target.exists() && await target.length() == (o.size ?? -1)) {
      return target;
    }
    await dir.create(recursive: true);
    return getIt<VaultDownloads>().file(o, target, listed: false);
  }

  @override
  Widget build(BuildContext context) {
    final t = context.tokens;
    final o = widget.object;
    final mime = o.mime ?? lookupMimeType(o.name) ?? 'application/octet-stream';
    final when = DateFormat.yMMMd(
      context.locale.toLanguageTag(),
    ).add_Hm().format(DateTime.fromMillisecondsSinceEpoch(o.mtime));
    return DecoratedBox(
      decoration: BoxDecoration(
        color: t.surface,
        border: BorderDirectional(start: BorderSide(color: t.line)),
      ),
      child: ListView(
        key: ValueKey(o.id),
        padding: const EdgeInsets.fromLTRB(16, 8, 16, 24),
        children: [
          Align(
            alignment: AlignmentDirectional.centerEnd,
            child: AppIconButton(
              icon: AppIcons.close,
              tooltip: 'send.close'.tr(),
              onPressed: widget.onClose,
            ),
          ),
          AspectRatio(
            aspectRatio: 4 / 3,
            child: ClipRRect(
              borderRadius: BorderRadius.circular(14),
              child: Material(
                color: t.sunken,
                child: InkWell(
                  onTap: widget.onOpen,
                  child: FutureBuilder<File?>(
                    future: _file,
                    builder: (context, snap) {
                      final file = snap.data;
                      if (_file != null &&
                          snap.connectionState != ConnectionState.done) {
                        return _small(mime, loading: true);
                      }
                      if (file != null) {
                        return LayoutBuilder(
                          builder: (context, box) => Image.file(
                            file,
                            fit: BoxFit.contain,
                            cacheWidth:
                                (box.maxWidth *
                                        MediaQuery.devicePixelRatioOf(context))
                                    .round(),
                            errorBuilder: (_, _, _) => _kind(mime),
                          ),
                        );
                      }
                      return _small(mime);
                    },
                  ),
                ),
              ),
            ),
          ),
          const SizedBox(height: 14),
          Text(
            o.name,
            maxLines: 2,
            overflow: TextOverflow.ellipsis,
            style: AppType.title.copyWith(color: t.text),
          ),
          const SizedBox(height: 2),
          Text(
            [if (o.size != null) formatBytes(o.size!), when].join(' · '),
            style: AppType.secondary.copyWith(color: t.text2),
          ),
          const SizedBox(height: 12),
          AppSheetGroup(
            first: true,
            children: [
              for (final a in widget.actions)
                AppSheetAction(
                  icon: a.icon,
                  label: a.label,
                  destructive: a.destructive,
                  onTap: a.onTap,
                ),
            ],
          ),
        ],
      ),
    );
  }

  /// The thumbnail, if there is one; a spinner over it while [loading].
  Widget _small(String mime, {bool loading = false}) {
    final t = context.tokens;
    return FutureBuilder<Uint8List?>(
      future: _thumb,
      builder: (context, snap) {
        final bytes = snap.data;
        return Stack(
          fit: StackFit.expand,
          children: [
            if (bytes != null)
              Image.memory(bytes, fit: BoxFit.contain, gaplessPlayback: true)
            else if (!loading)
              _kind(mime),
            if (loading)
              Center(
                child: SizedBox.square(
                  dimension: 22,
                  child: CircularProgressIndicator(
                    strokeWidth: 2,
                    color: t.accent,
                  ),
                ),
              ),
          ],
        );
      },
    );
  }

  Widget _kind(String mime) =>
      Center(child: MediaThumb(path: null, mime: mime, size: 96, radius: 18));
}
