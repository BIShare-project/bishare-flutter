import 'package:camera/camera.dart' show FlashMode;
import 'package:flutter/material.dart';
import 'package:flutter_zxing/flutter_zxing.dart';

/// Torch state + control for a [QrCamera]. The camera itself is owned by the
/// reader widget, which recreates it on app resume, so the handle is re-attached
/// on every (re)initialization and the torch starts off again each time.
class QrCameraController extends ValueNotifier<bool> {
  QrCameraController() : super(false);

  CameraController? _camera;

  void _attach(CameraController? camera) {
    _camera = camera;
    value = false;
  }

  Future<void> toggleTorch() async {
    final camera = _camera;
    if (camera == null) return;
    final on = !value;
    try {
      await camera.setFlashMode(on ? FlashMode.torch : FlashMode.off);
      value = on;
    } catch (_) {
      // No flash unit (front-only devices, some tablets): leave the torch off.
    }
  }
}

/// Live camera QR reader shared by the scanner and QR Beam receive pages:
/// zxing-cpp decoding over the `camera` plugin, with the reader's own chrome
/// hidden so each page draws its own frame, torch and cards on top.
///
/// Camera scanning exists on Android and iOS only — gate entry points on
/// `supportsCameraScan`.
class QrCamera extends StatefulWidget {
  const QrCamera({
    super.key,
    required this.controller,
    required this.onCode,
    required this.denied,
    this.continuous = false,
  });

  final QrCameraController controller;

  /// Called with the text of every decoded QR code.
  final ValueChanged<String> onCode;

  /// Shown instead of the preview when the camera can't be opened (usually a
  /// denied permission).
  final Widget denied;

  /// Decode frames back to back with no pause, even right after a hit. QR Beam
  /// needs this: its sender cycles frames and every one of them counts.
  final bool continuous;

  @override
  State<QrCamera> createState() => _QrCameraState();
}

class _QrCameraState extends State<QrCamera> {
  bool _failed = false;

  @override
  Widget build(BuildContext context) {
    if (_failed) return widget.denied;
    return ReaderWidget(
      codeFormat: Format.qrCode,
      // Scan the largest centred square rather than the default half-size one:
      // the page's frame is only a guide, and a code held off-centre should
      // still read.
      cropPercent: 1,
      scanDelay: widget.continuous ? Duration.zero : const Duration(milliseconds: 100),
      scanDelaySuccess: widget.continuous ? Duration.zero : const Duration(seconds: 1),
      showScannerOverlay: false,
      showFlashlight: false,
      showToggleCamera: false,
      showGallery: false,
      onControllerCreated: (camera, error) {
        // The reader reports a failed init even after it was torn down, by
        // which point the page has disposed the controller.
        if (!mounted) return;
        widget.controller._attach(camera);
        if (error != null) setState(() => _failed = true);
      },
      onScan: (code) {
        final text = code.text;
        if (code.isValid && text != null) widget.onCode(text);
      },
    );
  }
}
