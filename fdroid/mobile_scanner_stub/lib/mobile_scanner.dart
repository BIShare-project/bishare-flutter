/// Inert stand-in for package:mobile_scanner (see pubspec.yaml for why).
/// Mirrors exactly the API surface BIShare uses; nothing here touches a
/// camera. If the stub widget is ever built despite the supportsCameraScan
/// gate, it renders the caller's errorBuilder — the same "camera denied"
/// UI the real package would show.
library;

import 'package:flutter/widgets.dart';

enum TorchState { auto, off, on, unavailable }

enum BarcodeFormat { all, qrCode, unknown }

enum DetectionSpeed { noDuplicates, normal, unrestricted }

class Barcode {
  const Barcode({this.rawValue});
  final String? rawValue;
}

class BarcodeCapture {
  const BarcodeCapture({this.barcodes = const []});
  final List<Barcode> barcodes;
}

class MobileScannerException implements Exception {
  const MobileScannerException({this.message = 'Camera scanning unavailable'});
  final String message;
  @override
  String toString() => 'MobileScannerException: $message';
}

class MobileScannerState {
  const MobileScannerState({this.torchState = TorchState.unavailable});
  final TorchState torchState;
}

class MobileScannerController extends ValueNotifier<MobileScannerState> {
  MobileScannerController({
    List<BarcodeFormat> formats = const [],
    DetectionSpeed detectionSpeed = DetectionSpeed.normal,
    bool autoStart = true,
  }) : super(const MobileScannerState());

  Future<void> start() async {}
  Future<void> stop() async {}
  Future<void> toggleTorch() async {}
}

class MobileScanner extends StatelessWidget {
  const MobileScanner({
    super.key,
    required this.controller,
    this.onDetect,
    this.errorBuilder,
    this.fit = BoxFit.cover,
  });

  final MobileScannerController controller;
  final void Function(BarcodeCapture capture)? onDetect;
  final Widget Function(BuildContext context, MobileScannerException error)?
      errorBuilder;
  final BoxFit fit;

  @override
  Widget build(BuildContext context) {
    return errorBuilder?.call(context, const MobileScannerException()) ??
        const SizedBox.shrink();
  }
}
