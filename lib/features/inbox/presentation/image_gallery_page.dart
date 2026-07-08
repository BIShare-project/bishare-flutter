import 'dart:io';

import 'package:easy_localization/easy_localization.dart';
import 'package:flutter/material.dart';
import 'package:photo_view/photo_view.dart';
import 'package:photo_view/photo_view_gallery.dart';
import 'package:share_plus/share_plus.dart';

import '../../../core/storage/app_database.dart';
import '../../../core/ui/app_svg_icon.dart';

/// A full-screen, swipeable, pinch-zoom image viewer for received photos.
class ImageGalleryPage extends StatefulWidget {
  const ImageGalleryPage({
    super.key,
    required this.images,
    required this.startIndex,
  });

  final List<TransferRecord> images;
  final int startIndex;

  @override
  State<ImageGalleryPage> createState() => _ImageGalleryPageState();
}

class _ImageGalleryPageState extends State<ImageGalleryPage> {
  late final PageController _controller;
  late int _index;

  @override
  void initState() {
    super.initState();
    _index = widget.startIndex;
    _controller = PageController(initialPage: widget.startIndex);
  }

  @override
  void dispose() {
    _controller.dispose();
    super.dispose();
  }

  @override
  Widget build(BuildContext context) {
    final current = widget.images[_index];
    return Scaffold(
      backgroundColor: Colors.black,
      body: Stack(
        children: [
          PhotoViewGallery.builder(
            pageController: _controller,
            itemCount: widget.images.length,
            onPageChanged: (i) => setState(() => _index = i),
            backgroundDecoration: const BoxDecoration(color: Colors.black),
            loadingBuilder: (_, _) =>
                const Center(child: CircularProgressIndicator()),
            builder: (context, i) {
              final r = widget.images[i];
              return PhotoViewGalleryPageOptions(
                imageProvider: FileImage(File(r.savedPath!)),
                minScale: PhotoViewComputedScale.contained,
                maxScale: PhotoViewComputedScale.covered * 3,
                initialScale: PhotoViewComputedScale.contained,
                heroAttributes: PhotoViewHeroAttributes(tag: r.id),
                errorBuilder: (_, _, _) => const Center(
                  child: AppSvgIcon(
                    AppIcons.imageOff,
                    color: Colors.white54,
                    size: 48,
                  ),
                ),
              );
            },
          ),
          SafeArea(
            child: Container(
              padding: const EdgeInsets.symmetric(horizontal: 6, vertical: 4),
              decoration: const BoxDecoration(
                gradient: LinearGradient(
                  begin: Alignment.topCenter,
                  end: Alignment.bottomCenter,
                  colors: [Colors.black54, Colors.transparent],
                ),
              ),
              child: Row(
                children: [
                  IconButton(
                    icon: const AppSvgIcon(AppIcons.close, color: Colors.white),
                    onPressed: () => Navigator.pop(context),
                  ),
                  Expanded(
                    child: Column(
                      children: [
                        Text(
                          current.fileName,
                          maxLines: 1,
                          overflow: TextOverflow.ellipsis,
                          textAlign: TextAlign.center,
                          style: const TextStyle(
                            color: Colors.white,
                            fontWeight: FontWeight.w600,
                          ),
                        ),
                        Text(
                          'inbox.image_index'.tr(
                            namedArgs: {
                              'current': '${_index + 1}',
                              'total': '${widget.images.length}',
                            },
                          ),
                          style: const TextStyle(
                            color: Colors.white70,
                            fontSize: 12,
                          ),
                        ),
                      ],
                    ),
                  ),
                  IconButton(
                    icon: const AppSvgIcon(AppIcons.shareLink, color: Colors.white),
                    onPressed: () => SharePlus.instance.share(
                      ShareParams(files: [XFile(current.savedPath!)]),
                    ),
                  ),
                ],
              ),
            ),
          ),
        ],
      ),
    );
  }
}
