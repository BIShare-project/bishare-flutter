import 'package:flutter/material.dart';
import 'package:shadcn_ui/shadcn_ui.dart';

import '../../../../core/ui/app_ui.dart';
import '../../domain/managed_file.dart';

class StorageBar extends StatelessWidget {
  const StorageBar({super.key, required this.files, required this.totalBytes});
  final List<ManagedFile> files;
  final int totalBytes;

  static const _order = [
    ('Images', Color(0xFF0A84FF)),
    ('Videos', Color(0xFFBF5AF2)),
    ('Audio', Color(0xFFFF375F)),
    ('Documents', Color(0xFFFF9F0A)),
    ('Archives', Color(0xFF30D158)),
    ('Other', Color(0xFF8E8E93)),
  ];

  @override
  Widget build(BuildContext context) {
    final cs = ShadTheme.of(context).colorScheme;
    final byCat = <String, int>{};
    for (final f in files) {
      byCat[f.category] = (byCat[f.category] ?? 0) + f.size;
    }
    final total = totalBytes == 0 ? 1 : totalBytes;
    return Container(
      margin: const EdgeInsets.fromLTRB(14, 6, 14, 2),
      padding: const EdgeInsets.all(14),
      decoration: BoxDecoration(
        color: cs.card,
        borderRadius: BorderRadius.circular(16),
        border: Border.all(color: cs.border.withValues(alpha: 0.8)),
      ),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Row(
            children: [
              Text(
                '${files.length} file${files.length == 1 ? '' : 's'}',
                style: TextStyle(
                  fontSize: 14,
                  fontWeight: FontWeight.w700,
                  color: cs.foreground,
                ),
              ),
              const Spacer(),
              Text(
                formatBytes(totalBytes),
                style: TextStyle(
                  fontSize: 13,
                  fontWeight: FontWeight.w600,
                  color: cs.mutedForeground,
                ),
              ),
            ],
          ),
          const SizedBox(height: 10),
          ClipRRect(
            borderRadius: BorderRadius.circular(4),
            child: Row(
              children: [
                for (final (cat, color) in _order)
                  if ((byCat[cat] ?? 0) > 0)
                    Expanded(
                      flex: byCat[cat]!,
                      child: Container(height: 8, color: color),
                    ),
              ],
            ),
          ),
          const SizedBox(height: 10),
          Wrap(
            spacing: 12,
            runSpacing: 6,
            children: [
              for (final (cat, color) in _order)
                if ((byCat[cat] ?? 0) > 0)
                  Row(
                    mainAxisSize: MainAxisSize.min,
                    children: [
                      Container(
                        width: 8,
                        height: 8,
                        decoration: BoxDecoration(
                          color: color,
                          shape: BoxShape.circle,
                        ),
                      ),
                      const SizedBox(width: 5),
                      Text(
                        '$cat · ${((byCat[cat]! / total) * 100).round()}%',
                        style: TextStyle(
                          fontSize: 11.5,
                          color: cs.mutedForeground,
                        ),
                      ),
                    ],
                  ),
            ],
          ),
        ],
      ),
    );
  }
}
