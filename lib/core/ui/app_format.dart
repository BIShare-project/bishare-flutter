import 'package:compact_toast/compact_toast.dart';
import 'package:flutter/material.dart';
import 'package:flutter/services.dart' show HapticFeedback;

import 'app_svg_icon.dart';

export 'package:compact_toast/compact_toast.dart' show ToastType;

/// Amber used for the favorite star across the app.
const Color kAmber = Color(0xFFF5A623);

/// A light tap tick — fired by every interactive kit component on tap so the
/// whole app has consistent haptic feedback (no-op on desktop).
void tapHaptic() => HapticFeedback.selectionClick();

/// iOS system green used for online / success accents.
const Color kOnlineGreen = Color(0xFF34C759);

/// A compact floating toast — the app-wide lightweight notice. Rendered by
/// `compact_toast` at the bottom of the screen. Pass [type] for success/error/
/// warning styling; defaults to a neutral info toast.
void toast(
  BuildContext context,
  String message, {
  ToastType type = ToastType.info,
}) {
  CompactToast.show(
    context,
    message: message,
    type: type,
    position: ToastPosition.bottom,
  );
}

String formatBytes(int bytes) {
  if (bytes < 1024) return '$bytes B';
  if (bytes < 1024 * 1024) return '${(bytes / 1024).toStringAsFixed(1)} KB';
  if (bytes < 1024 * 1024 * 1024) {
    return '${(bytes / (1024 * 1024)).toStringAsFixed(1)} MB';
  }
  return '${(bytes / (1024 * 1024 * 1024)).toStringAsFixed(2)} GB';
}

String fmtSpeed(double bytesPerSec) {
  final mb = bytesPerSec / (1024 * 1024);
  if (mb >= 1) return '${mb.toStringAsFixed(1)} MB/s';
  return '${(bytesPerSec / 1024).toStringAsFixed(0)} KB/s';
}

String fmtEta(double secs) {
  if (secs < 60) return '${secs.toInt()}s left';
  final m = secs ~/ 60;
  final s = (secs % 60).toInt();
  return '${m}m ${s}s left';
}

/// The [AppIcons] name for a device type (used by [AppAvatar]).
String iconForDevice(String deviceType) => switch (deviceType) {
  'desktop' => AppIcons.monitor,
  'tablet' => AppIcons.tablet,
  _ => AppIcons.smartphone,
};

/// The [AppIcons] name for a file's MIME type.
String fileIcon(String mime) {
  if (mime.startsWith('image/')) return AppIcons.image;
  if (mime.startsWith('video/')) return AppIcons.fileVideo;
  if (mime.startsWith('audio/')) return AppIcons.fileAudio;
  if (mime.contains('pdf')) return AppIcons.filePdf;
  if (mime.startsWith('text/')) return AppIcons.fileDocument;
  if (mime.contains('zip') || mime.contains('archive')) {
    return AppIcons.fileArchive;
  }
  return AppIcons.fileDocument;
}
