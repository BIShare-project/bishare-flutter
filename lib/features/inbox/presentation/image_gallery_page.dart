import 'dart:io';

import 'package:easy_localization/easy_localization.dart';
import 'package:flutter/material.dart';
import 'package:flutter/services.dart';
import 'package:photo_view/photo_view.dart';
import 'package:photo_view/photo_view_gallery.dart';

import '../../../core/storage/app_database.dart';
import '../../../core/ui/app_ui.dart';
import '../../instant_share/presentation/instant_share_sheet.dart';
import '../../vault/presentation/drive/drive_actions.dart';
import '../domain/inbox_groups.dart';
import 'inbox_cubit.dart';
import 'widgets/received_actions.dart';

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
    // Dark full-screen page: light status-bar icons whatever the app theme.
    return AnnotatedRegion<SystemUiOverlayStyle>(
      value: SystemUiOverlayStyle.light,
      child: Scaffold(
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
                      tooltip: MaterialLocalizations.of(
                        context,
                      ).closeButtonTooltip,
                      icon: const AppSvgIcon(
                        AppIcons.close,
                        color: Colors.white,
                      ),
                      onPressed: () => Navigator.pop(context),
                    ),
                    Expanded(
                      child: Column(
                        mainAxisSize: MainAxisSize.min,
                        children: [
                          Text(
                            shownName(current),
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
                    const SizedBox(width: 48),
                  ],
                ),
              ),
            ),
            // What to do with this photo, along the bottom (5.3).
            Positioned(
              left: 0,
              right: 0,
              bottom: 0,
              child: SafeArea(
                top: false,
                child: Container(
                  padding: const EdgeInsets.fromLTRB(8, 18, 8, 6),
                  decoration: const BoxDecoration(
                    gradient: LinearGradient(
                      begin: Alignment.bottomCenter,
                      end: Alignment.topCenter,
                      colors: [Colors.black54, Colors.transparent],
                    ),
                  ),
                  child: Column(
                    mainAxisSize: MainAxisSize.min,
                    children: [
                      Text(
                        [
                          formatBytes(current.fileSize),
                          'inbox.from'.tr(
                            namedArgs: {'alias': current.deviceAlias},
                          ),
                        ].join(' · '),
                        style: const TextStyle(
                          color: Color(0xFFB8BEC6),
                          fontSize: 12.5,
                          fontFeatures: [FontFeature.tabularFigures()],
                        ),
                      ),
                      const SizedBox(height: 6),
                      Row(
                        mainAxisAlignment: MainAxisAlignment.spaceAround,
                        children: [
                          if (InboxCubit.canSaveToPhotos)
                            _Action(
                              icon: AppIcons.imageDown,
                              label: 'inbox.save'.tr(),
                              onTap: () => savePhotos(context, [current]),
                            ),
                          _Action(
                            icon: AppIcons.shareLink,
                            label: 'inbox.share'.tr(),
                            onTap: () => shareReceived([current]),
                          ),
                          if (driveReady)
                            _Action(
                              icon: AppIcons.cloudSync,
                              label: 'vault.drive'.tr(),
                              onTap: () =>
                                  saveToDrive(context, [current.savedPath!]),
                            ),
                          _Action(
                            icon: AppIcons.qrShare,
                            label: 'inbox.via_qr'.tr(),
                            onTap: () => showInstantShare(
                              context,
                              path: current.savedPath!,
                              fileName: current.fileName,
                              mimeType: current.fileType ?? 'image/jpeg',
                            ),
                          ),
                          _Action(
                            icon: AppIcons.trashDelete,
                            label: 'inbox.delete'.tr(),
                            onTap: () async {
                              if (await deleteReceived(context, [current]) &&
                                  context.mounted) {
                                Navigator.pop(context);
                              }
                            },
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
      ),
    );
  }
}

/// One action on the viewer's bottom bar: an icon over a short label.
class _Action extends StatelessWidget {
  const _Action({required this.icon, required this.label, required this.onTap});

  final String icon;
  final String label;
  final VoidCallback onTap;

  @override
  Widget build(BuildContext context) {
    return Material(
      type: MaterialType.transparency,
      child: InkWell(
        borderRadius: BorderRadius.circular(10),
        onTap: onTap,
        child: ConstrainedBox(
          constraints: const BoxConstraints(minWidth: 64, minHeight: 52),
          child: Column(
            mainAxisAlignment: MainAxisAlignment.center,
            children: [
              AppSvgIcon(icon, size: 22, color: Colors.white),
              const SizedBox(height: 3),
              Text(
                label,
                style: const TextStyle(color: Colors.white, fontSize: 11.5),
              ),
            ],
          ),
        ),
      ),
    );
  }
}
