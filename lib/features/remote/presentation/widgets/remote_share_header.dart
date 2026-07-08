import 'package:easy_localization/easy_localization.dart';
import 'package:flutter/material.dart';
import 'package:go_router/go_router.dart';
import 'package:shadcn_ui/shadcn_ui.dart';

import '../../../../core/ui/app_ui.dart';

class RemoteShareHeader extends StatelessWidget {
  const RemoteShareHeader({super.key, required this.showBack});
  final bool showBack;

  @override
  Widget build(BuildContext context) {
    final cs = ShadTheme.of(context).colorScheme;
    return Padding(
      padding: const EdgeInsets.fromLTRB(8, 8, 16, 0),
      child: Row(
        children: [
          AppIconButton(icon: AppIcons.close, onPressed: () => context.pop()),
          const SizedBox(width: 4),
          Text(
            'remote.title'.tr(),
            style: TextStyle(
              fontSize: 18,
              fontWeight: FontWeight.w700,
              color: cs.foreground,
            ),
          ),
        ],
      ),
    );
  }
}
