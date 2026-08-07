import 'dart:io';

import 'package:easy_localization/easy_localization.dart';
import 'package:flutter/material.dart';
import 'package:flutter/services.dart';

import '../../../../core/storage/app_database.dart';
import 'tv_received_grid.dart' show isImageRecord;

/// Full-screen viewer for a received file on the big screen. The D-pad
/// left/right pages through the received items; Back (or Esc) closes. Images
/// fill the screen; other file types show a centered card.
class TvFileViewer extends StatefulWidget {
  const TvFileViewer({super.key, required this.items, required this.startIndex});

  final List<TransferRecord> items;
  final int startIndex;

  @override
  State<TvFileViewer> createState() => _TvFileViewerState();
}

class _TvFileViewerState extends State<TvFileViewer> {
  late final PageController _controller =
      PageController(initialPage: widget.startIndex);
  late int _index = widget.startIndex;

  void _go(int delta) {
    final next = _index + delta;
    if (next < 0 || next >= widget.items.length) return;
    _controller.animateToPage(
      next,
      duration: const Duration(milliseconds: 220),
      curve: Curves.easeOut,
    );
  }

  KeyEventResult _onKey(FocusNode node, KeyEvent event) {
    if (event is! KeyDownEvent && event is! KeyRepeatEvent) {
      return KeyEventResult.ignored;
    }
    switch (event.logicalKey) {
      case LogicalKeyboardKey.arrowRight:
        _go(1);
        return KeyEventResult.handled;
      case LogicalKeyboardKey.arrowLeft:
        _go(-1);
        return KeyEventResult.handled;
      case LogicalKeyboardKey.escape:
      case LogicalKeyboardKey.goBack:
        Navigator.of(context).maybePop();
        return KeyEventResult.handled;
    }
    return KeyEventResult.ignored;
  }

  @override
  void dispose() {
    _controller.dispose();
    super.dispose();
  }

  @override
  Widget build(BuildContext context) {
    final total = widget.items.length;
    return Scaffold(
      backgroundColor: Colors.black,
      body: Focus(
        autofocus: true,
        onKeyEvent: _onKey,
        child: Stack(
          children: [
            PageView.builder(
              controller: _controller,
              onPageChanged: (i) => setState(() => _index = i),
              itemCount: total,
              itemBuilder: (context, i) => _Page(record: widget.items[i]),
            ),
            // Caption + hint bar.
            Positioned(
              left: 0,
              right: 0,
              bottom: 0,
              child: Container(
                padding: const EdgeInsets.fromLTRB(56, 24, 56, 32),
                decoration: BoxDecoration(
                  gradient: LinearGradient(
                    begin: Alignment.bottomCenter,
                    end: Alignment.topCenter,
                    colors: [
                      Colors.black.withValues(alpha: 0.75),
                      Colors.transparent,
                    ],
                  ),
                ),
                child: Row(
                  children: [
                    Expanded(
                      child: Text(
                        widget.items[_index].fileName,
                        maxLines: 1,
                        overflow: TextOverflow.ellipsis,
                        style: const TextStyle(
                          color: Colors.white,
                          fontSize: 20,
                          fontWeight: FontWeight.w600,
                        ),
                      ),
                    ),
                    const SizedBox(width: 24),
                    Text(
                      '${_index + 1} / $total   ◀ ▶ ${'tv.viewer_hint'.tr()}',
                      style: const TextStyle(
                        color: Colors.white70,
                        fontSize: 15,
                      ),
                    ),
                  ],
                ),
              ),
            ),
          ],
        ),
      ),
    );
  }
}

class _Page extends StatelessWidget {
  const _Page({required this.record});
  final TransferRecord record;

  @override
  Widget build(BuildContext context) {
    if (isImageRecord(record)) {
      return InteractiveViewer(
        child: Center(
          child: Image.file(
            File(record.savedPath!),
            fit: BoxFit.contain,
            errorBuilder: (context, error, stack) => _NonImage(record: record),
          ),
        ),
      );
    }
    return _NonImage(record: record);
  }
}

class _NonImage extends StatelessWidget {
  const _NonImage({required this.record});
  final TransferRecord record;

  @override
  Widget build(BuildContext context) {
    final type = record.fileType ?? '';
    final icon = type.startsWith('video/')
        ? Icons.movie_outlined
        : type.startsWith('audio/')
            ? Icons.music_note_outlined
            : Icons.insert_drive_file_outlined;
    return Center(
      child: Column(
        mainAxisSize: MainAxisSize.min,
        children: [
          Icon(icon, size: 96, color: Colors.white70),
          const SizedBox(height: 24),
          Text(
            record.fileName,
            textAlign: TextAlign.center,
            style: const TextStyle(color: Colors.white, fontSize: 24),
          ),
          const SizedBox(height: 8),
          Text(
            'tv.saved_to_device'.tr(),
            style: TextStyle(color: Colors.white.withValues(alpha: 0.6)),
          ),
        ],
      ),
    );
  }
}
