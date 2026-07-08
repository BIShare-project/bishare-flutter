import 'package:easy_localization/easy_localization.dart';
import 'package:flutter/material.dart';
import 'package:shadcn_ui/shadcn_ui.dart';

import '../../../../core/ui/app_ui.dart';

class UploadingView extends StatelessWidget {
  UploadingView({
    super.key,
    required this.fraction,
    required this.name,
    required this.size,
    String? title,
  }) : title = title ?? 'remote.uploading_to_secure_link'.tr();

  final double fraction;
  final String name;
  final int size;
  final String title;

  @override
  Widget build(BuildContext context) {
    final cs = ShadTheme.of(context).colorScheme;
    final pct = (fraction * 100).clamp(0, 100).toInt();
    return Center(
      child: Column(
        mainAxisSize: MainAxisSize.min,
        children: [
          SizedBox(
            width: 84,
            height: 84,
            child: Stack(
              alignment: Alignment.center,
              children: [
                SizedBox(
                  width: 84,
                  height: 84,
                  child: CircularProgressIndicator(
                    value: fraction == 0 ? null : fraction,
                    strokeWidth: 6,
                    backgroundColor: cs.muted,
                    valueColor: AlwaysStoppedAnimation(cs.primary),
                  ),
                ),
                Text(
                  '$pct%',
                  style: TextStyle(
                    fontSize: 16,
                    fontWeight: FontWeight.w700,
                    color: cs.foreground,
                  ),
                ),
              ],
            ),
          ),
          const SizedBox(height: 20),
          Text(
            title,
            style: TextStyle(
              fontSize: 16,
              fontWeight: FontWeight.w600,
              color: cs.foreground,
            ),
          ),
          const SizedBox(height: 6),
          Padding(
            padding: const EdgeInsets.symmetric(horizontal: 32),
            child: Text(
              '$name · ${formatBytes(size)}',
              maxLines: 1,
              overflow: TextOverflow.ellipsis,
              style: TextStyle(fontSize: 13, color: cs.mutedForeground),
            ),
          ),
        ],
      ),
    );
  }
}
