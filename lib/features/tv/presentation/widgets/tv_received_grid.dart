import 'dart:io';

import 'package:flutter/material.dart';
import 'package:shadcn_ui/shadcn_ui.dart';

import '../../../../core/storage/app_database.dart';
import 'tv_file_viewer.dart';
import 'tv_focusable.dart';

/// D-pad-navigable grid of received files. Arrow keys move the highlight; OK
/// opens a full-screen viewer that itself pages left/right with the remote.
class TvReceivedGrid extends StatelessWidget {
  const TvReceivedGrid({super.key, required this.items});

  final List<TransferRecord> items;

  @override
  Widget build(BuildContext context) {
    return GridView.builder(
      padding: EdgeInsets.zero,
      gridDelegate: const SliverGridDelegateWithFixedCrossAxisCount(
        crossAxisCount: 4,
        mainAxisSpacing: 18,
        crossAxisSpacing: 18,
        childAspectRatio: 1,
      ),
      itemCount: items.length,
      itemBuilder: (context, i) => TvFocusable(
        autofocus: i == 0,
        onSelect: () => _open(context, i),
        builder: (context, focused) => _Tile(record: items[i], focused: focused),
      ),
    );
  }

  void _open(BuildContext context, int index) {
    Navigator.of(context).push(
      MaterialPageRoute<void>(
        builder: (_) => TvFileViewer(items: items, startIndex: index),
      ),
    );
  }
}

bool isImageRecord(TransferRecord r) =>
    (r.fileType?.startsWith('image/') ?? false) && r.savedPath != null;

class _Tile extends StatelessWidget {
  const _Tile({required this.record, required this.focused});

  final TransferRecord record;
  final bool focused;

  @override
  Widget build(BuildContext context) {
    final cs = ShadTheme.of(context).colorScheme;
    final isImage = isImageRecord(record);

    return AnimatedScale(
      scale: focused ? 1.06 : 1.0,
      duration: const Duration(milliseconds: 140),
      curve: Curves.easeOut,
      child: AnimatedContainer(
        duration: const Duration(milliseconds: 140),
        decoration: BoxDecoration(
          color: cs.card,
          borderRadius: BorderRadius.circular(14),
          border: Border.all(
            color: focused ? cs.primary : cs.border,
            width: focused ? 3 : 1,
          ),
          boxShadow: focused
              ? [
                  BoxShadow(
                    color: cs.primary.withValues(alpha: 0.35),
                    blurRadius: 22,
                    spreadRadius: 1,
                  ),
                ]
              : null,
        ),
        clipBehavior: Clip.antiAlias,
        child: isImage
            ? Image.file(
                File(record.savedPath!),
                fit: BoxFit.cover,
                errorBuilder: (context, error, stack) =>
                    _FileFallback(record: record),
              )
            : _FileFallback(record: record),
      ),
    );
  }
}

class _FileFallback extends StatelessWidget {
  const _FileFallback({required this.record});
  final TransferRecord record;

  @override
  Widget build(BuildContext context) {
    final cs = ShadTheme.of(context).colorScheme;
    final type = record.fileType ?? '';
    final icon = type.startsWith('video/')
        ? Icons.play_circle_outline
        : type.startsWith('audio/')
            ? Icons.music_note_outlined
            : Icons.insert_drive_file_outlined;
    return Padding(
      padding: const EdgeInsets.all(14),
      child: Column(
        mainAxisAlignment: MainAxisAlignment.center,
        children: [
          Icon(icon, size: 44, color: cs.mutedForeground),
          const SizedBox(height: 12),
          Text(
            record.fileName,
            maxLines: 2,
            textAlign: TextAlign.center,
            overflow: TextOverflow.ellipsis,
            style: TextStyle(color: cs.foreground, fontSize: 14),
          ),
        ],
      ),
    );
  }
}
