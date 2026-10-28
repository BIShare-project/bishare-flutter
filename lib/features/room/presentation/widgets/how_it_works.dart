import 'package:easy_localization/easy_localization.dart';
import 'package:flutter/material.dart';

import '../../../../core/ui/app_ui.dart';

/// "How it works", in a sheet from the lobby: three short steps.
Future<void> showHowItWorks(BuildContext context) => showAppSheet<void>(
  context,
  icon: AppIcons.teamGroup,
  title: 'room.how_it_works'.tr(),
  builder: (ctx) {
    final t = ctx.tokens;
    final steps = ['room.step_1'.tr(), 'room.step_2'.tr(), 'room.step_3'.tr()];
    return Column(
      mainAxisSize: MainAxisSize.min,
      children: [
        for (var i = 0; i < steps.length; i++)
          Padding(
            padding: const EdgeInsets.symmetric(vertical: 8),
            child: Row(
              children: [
                Container(
                  width: 28,
                  height: 28,
                  alignment: Alignment.center,
                  decoration: BoxDecoration(
                    color: t.accentSoft,
                    shape: BoxShape.circle,
                  ),
                  child: Text(
                    '${i + 1}',
                    style: AppType.label.copyWith(color: t.accent),
                  ),
                ),
                const SizedBox(width: 12),
                Expanded(
                  child: Text(
                    steps[i],
                    style: AppType.body.copyWith(color: t.text),
                  ),
                ),
              ],
            ),
          ),
      ],
    );
  },
);
