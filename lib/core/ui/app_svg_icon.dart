import 'package:flutter/widgets.dart';
import 'package:shadcn_ui/shadcn_ui.dart';

/// Semantic names for the custom BIShare SVG icon set (`assets/icon/svg/*.svg`).
///
/// Use these with [AppSvgIcon] instead of Lucide / Material icons so the whole
/// app shares one hand-drawn icon language: the line work follows the ambient
/// icon color while a fixed indigo brand accent gives each glyph a subtle
/// duotone lift.
class AppIcons {
  AppIcons._();

  static const bookmark = 'bookmark';
  static const cloudSync = 'cloud-sync';
  static const comment = 'comment';
  static const copyDuplicate = 'copy-duplicate';
  static const downloadFile = 'download-file';
  static const expiryTimer = 'expiry-timer';
  static const externalLink = 'external-link';
  static const eyeOff = 'eye-off';
  static const eyePreview = 'eye-preview';
  static const fileArchive = 'file-archive';
  static const fileAudio = 'file-audio';
  static const fileCode = 'file-code';
  static const fileDocument = 'file-document';
  static const fileImage = 'file-image';
  static const filePdf = 'file-pdf';
  static const fileSpreadsheet = 'file-spreadsheet';
  static const fileVideo = 'file-video';
  static const filter = 'filter';
  static const folderShared = 'folder-shared';
  static const globePublic = 'globe-public';
  static const gridView = 'grid-view';
  static const history = 'history';
  static const inviteUser = 'invite-user';
  static const linkCopy = 'link-copy';
  static const listView = 'list-view';
  static const mailSend = 'mail-send';
  static const moreMenu = 'more-menu';
  static const moveFile = 'move-file';
  static const newFolder = 'new-folder';
  static const notification = 'notification';
  static const passwordLock = 'password-lock';
  static const permissionShield = 'permission-shield';
  static const print = 'print';
  static const qrShare = 'qr-share';
  static const refreshSync = 'refresh-sync';
  static const renameEdit = 'rename-edit';
  static const scanDocument = 'scan-document';
  static const search = 'search';
  static const settings = 'settings';
  static const shareLink = 'share-link';
  static const sort = 'sort';
  static const starFavorite = 'star-favorite';
  static const storageUsage = 'storage-usage';
  static const successSent = 'success-sent';
  static const tagLabel = 'tag-label';
  static const teamGroup = 'team-group';
  static const transferP2p = 'transfer-p2p';
  static const trashDelete = 'trash-delete';
  static const uploadFile = 'upload-file';
  static const verifiedCheck = 'verified-check';

  // --- Added for the app-wide rollout (drawn in the same style) ---
  static const arrowDown = 'arrow-down';
  static const arrowRightCircle = 'arrow-right-circle';
  static const arrowUp = 'arrow-up';
  static const cameraOff = 'camera-off';
  static const check = 'check';
  static const chevronLeft = 'chevron-left';
  static const chevronRight = 'chevron-right';
  static const circle = 'circle';
  static const circleAlert = 'circle-alert';
  static const clipboard = 'clipboard';
  static const clipboardPaste = 'clipboard-paste';
  static const clock = 'clock';
  static const close = 'close';
  static const flame = 'flame';
  static const flashlight = 'flashlight';
  static const flashlightOff = 'flashlight-off';
  static const folder = 'folder';
  static const folderOpen = 'folder-open';
  static const hand = 'hand';
  static const image = 'image';
  static const imageDown = 'image-down';
  static const imageOff = 'image-off';
  static const keyboard = 'keyboard';
  static const logIn = 'log-in';
  static const mic = 'mic';
  static const monitor = 'monitor';
  static const note = 'note';
  static const paintbrush = 'paintbrush';
  static const play = 'play';
  static const send = 'send';
  static const smartphone = 'smartphone';
  static const squareCheck = 'square-check';
  static const sunMoon = 'sun-moon';
  static const tablet = 'tablet';
  static const user = 'user';
  static const wifi = 'wifi';
  static const zap = 'zap';
}

/// Remaps the SVGs' authored brand accent (indigo `#6366F1`) to a runtime
/// [accent] so the duotone accent follows the active shadcn theme instead of a
/// hardcoded color.
class _AccentColorMapper extends ColorMapper {
  const _AccentColorMapper(this.accent);

  final Color accent;

  /// The indigo baked into every glyph in `assets/icon/svg/`.
  static const int _brandAccent = 0xFF6366F1;

  @override
  Color substitute(
    String? id,
    String elementName,
    String attributeName,
    Color color,
  ) => color.toARGB32() == _brandAccent ? accent : color;

  @override
  bool operator ==(Object other) =>
      other is _AccentColorMapper && other.accent == accent;

  @override
  int get hashCode => accent.hashCode;
}

/// Renders a BIShare SVG icon by its [AppIcons] name.
///
/// The stroke work is tinted with [color] (mapped to the SVG's `currentColor`),
/// while the duotone brand accent follows the active theme's primary color. When
/// [color] is null the ambient [IconTheme] / text color is used, matching how a
/// Material [Icon] inherits its color.
class AppSvgIcon extends StatelessWidget {
  const AppSvgIcon(this.name, {super.key, this.size = 24, this.color});

  /// One of the [AppIcons] constants (the file name without extension).
  final String name;
  final double size;
  final Color? color;

  /// Our glyphs fill the 24-unit viewBox nearly edge-to-edge, whereas Material /
  /// Lucide icons carry built-in optical padding. We render the artwork slightly
  /// smaller than its [size] slot (but keep the slot at [size] so layout spacing
  /// is unchanged) so an [AppSvgIcon] reads at the same weight as the old icons.
  static const double _glyphScale = 0.90;

  @override
  Widget build(BuildContext context) {
    // Inherit color the way a Material [Icon] does: explicit color first, then
    // the ambient IconTheme (set by ShadIconButton, list tiles, etc.), then the
    // default text color.
    final tint = color ??
        IconTheme.of(context).color ??
        DefaultTextStyle.of(context).style.color ??
        const Color(0xFF000000);
    final accent = ShadTheme.of(context).colorScheme.primary;
    return SizedBox(
      width: size,
      height: size,
      child: Center(
        child: SvgPicture.asset(
          'assets/icon/svg/$name.svg',
          width: size * _glyphScale,
          height: size * _glyphScale,
          theme: SvgTheme(currentColor: tint),
          colorMapper: _AccentColorMapper(accent),
        ),
      ),
    );
  }
}
