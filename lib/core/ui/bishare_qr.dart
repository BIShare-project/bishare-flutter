import 'package:flutter/material.dart';
import 'package:qr_flutter/qr_flutter.dart';
import 'package:shadcn_ui/shadcn_ui.dart';

import 'app_svg_icon.dart';

/// The app-wide styled QR card — a native-style code with a gradient accent
/// border, accent finder eyes, and the BIShare mark in the centre (drawn at
/// error-correction H so the logo never breaks scanning). Used for browser
/// access, remote transfers and rooms.
class BiShareQr extends StatelessWidget {
  const BiShareQr({super.key, required this.data, this.size = 208});

  final String data;
  final double size;

  @override
  Widget build(BuildContext context) {
    final cs = ShadTheme.of(context).colorScheme;
    return Container(
      padding: const EdgeInsets.all(3),
      decoration: BoxDecoration(
        gradient: LinearGradient(
          begin: Alignment.topLeft,
          end: Alignment.bottomRight,
          colors: [cs.primary, cs.primary.withValues(alpha: 0.3)],
        ),
        borderRadius: BorderRadius.circular(24),
      ),
      child: Container(
        padding: const EdgeInsets.all(16),
        decoration: BoxDecoration(
          color: Colors.white,
          borderRadius: BorderRadius.circular(21),
        ),
        child: Stack(
          alignment: Alignment.center,
          children: [
            QrImageView(
              data: data,
              size: size,
              backgroundColor: Colors.white,
              errorCorrectionLevel: QrErrorCorrectLevel.H,
              eyeStyle: QrEyeStyle(
                eyeShape: QrEyeShape.square,
                color: cs.primary,
              ),
              dataModuleStyle: const QrDataModuleStyle(
                dataModuleShape: QrDataModuleShape.square,
                color: Colors.black,
              ),
            ),
            Container(
              width: size * 0.22,
              height: size * 0.22,
              decoration: const BoxDecoration(
                color: Colors.white,
                shape: BoxShape.circle,
                border: Border.fromBorderSide(
                  BorderSide(color: Colors.white, width: 4),
                ),
              ),
              child: Container(
                decoration: BoxDecoration(
                  gradient: LinearGradient(
                    begin: Alignment.topLeft,
                    end: Alignment.bottomRight,
                    colors: [
                      cs.primary,
                      Color.lerp(cs.primary, Colors.black, 0.24)!,
                    ],
                  ),
                  shape: BoxShape.circle,
                ),
                child: AppSvgIcon(
                  AppIcons.send,
                  size: size * 0.1,
                  color: Colors.white,
                ),
              ),
            ),
          ],
        ),
      ),
    );
  }
}
