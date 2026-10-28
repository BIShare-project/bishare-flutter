import 'package:easy_localization/easy_localization.dart';
import 'package:flutter/material.dart';

import '../../../../core/ui/app_ui.dart';
import '../../domain/managed_file.dart';

/// How the received files split by kind: the count and size, one bar, and a
/// legend with each kind's share.
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
    final t = context.tokens;
    final byCat = <String, int>{};
    for (final f in files) {
      byCat[f.category] = (byCat[f.category] ?? 0) + f.size;
    }
    final total = totalBytes == 0 ? 1 : totalBytes;
    final percent = NumberFormat.percentPattern(context.locale.toLanguageTag());
    return AppCard(
      margin: const EdgeInsets.fromLTRB(14, 10, 14, 0),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Row(
            children: [
              Expanded(
                child: Text(
                  'inbox.n_files'.plural(files.length),
                  style: AppType.label.copyWith(fontSize: 14, color: t.text),
                ),
              ),
              Text(
                formatBytes(totalBytes),
                style: AppType.secondary.copyWith(
                  color: t.text2,
                  fontFeatures: const [FontFeature.tabularFigures()],
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
            spacing: 14,
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
                      const SizedBox(width: 6),
                      Text(
                        '${categoryLabel(cat)} · '
                        '${percent.format(byCat[cat]! / total)}',
                        style: AppType.secondary.copyWith(
                          fontSize: 12.5,
                          color: t.text2,
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
