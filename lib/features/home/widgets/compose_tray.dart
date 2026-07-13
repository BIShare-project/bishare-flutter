import 'package:easy_localization/easy_localization.dart';
import 'package:flutter/material.dart';
import 'package:flutter_bloc/flutter_bloc.dart';
import 'package:shadcn_ui/shadcn_ui.dart';

import '../../../core/ui/app_ui.dart';
import '../../send/domain/sendable_file.dart';
import '../../send/presentation/tray_cubit.dart';
import 'source_grid.dart';
import 'tray_chip.dart';

class ComposeTray extends StatelessWidget {
  const ComposeTray({super.key});

  @override
  Widget build(BuildContext context) {
    final cs = ShadTheme.of(context).colorScheme;
    return BlocBuilder<TrayCubit, List<SendableFile>>(
      builder: (context, items) {
        final tray = context.read<TrayCubit>();
        return Padding(
          padding: const EdgeInsets.fromLTRB(14, 10, 14, 2),
          child: Column(
            crossAxisAlignment: CrossAxisAlignment.start,
            children: [
              const SourceGrid(),
              if (items.isNotEmpty) ...[
                Padding(
                  padding: const EdgeInsets.only(top: 12, bottom: 2),
                  child: Row(
                    children: [
                      Text(
                        'home.tray_summary'.plural(
                          items.length,
                          namedArgs: {'size': formatBytes(tray.totalBytes)},
                        ),
                        style: TextStyle(
                          fontSize: 12.5,
                          fontWeight: FontWeight.w600,
                          color: cs.mutedForeground,
                        ),
                      ),
                      const Spacer(),
                      GestureDetector(
                        onTap: tray.clear,
                        child: Text(
                          'home.clear'.tr(),
                          style: TextStyle(
                            fontSize: 12.5,
                            fontWeight: FontWeight.w600,
                            color: cs.primary,
                          ),
                        ),
                      ),
                    ],
                  ),
                ),
                SizedBox(
                  height: 52,
                  child: ListView.separated(
                    scrollDirection: Axis.horizontal,
                    padding: const EdgeInsets.only(top: 6),
                    itemCount: items.length,
                    separatorBuilder: (_, _) => const SizedBox(width: 8),
                    itemBuilder: (context, i) => TrayChip(
                      file: items[i],
                      onRemove: () => tray.remove(items[i]),
                      onTap: () => showFilePreview(
                        context,
                        path: items[i].path,
                        name: items[i].name,
                        mimeType: items[i].mimeType,
                        size: items[i].size,
                      ),
                    ),
                  ),
                ),
              ],
            ],
          ),
        );
      },
    );
  }
}
