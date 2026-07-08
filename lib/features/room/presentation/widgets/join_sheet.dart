import 'package:easy_localization/easy_localization.dart';
import 'package:flutter/material.dart';
import 'package:shadcn_ui/shadcn_ui.dart';

import '../../../../core/ui/app_svg_icon.dart';
import 'code_field.dart';

class JoinSheet extends StatefulWidget {
  const JoinSheet({super.key, required this.onJoin});
  final ValueChanged<String> onJoin;

  @override
  State<JoinSheet> createState() => _JoinSheetState();
}

class _JoinSheetState extends State<JoinSheet> {
  final TextEditingController _controller = TextEditingController();

  @override
  void dispose() {
    _controller.dispose();
    super.dispose();
  }

  @override
  Widget build(BuildContext context) {
    final cs = ShadTheme.of(context).colorScheme;
    return Padding(
      padding: const EdgeInsets.fromLTRB(24, 24, 24, 16),
      child: Column(
        mainAxisSize: MainAxisSize.min,
        children: [
          Container(
            width: 64,
            height: 64,
            decoration: BoxDecoration(
              color: cs.primary.withValues(alpha: 0.12),
              shape: BoxShape.circle,
            ),
            child: AppSvgIcon(AppIcons.logIn, color: cs.primary, size: 28),
          ),
          const SizedBox(height: 16),
          Text(
            'room.join_a_room'.tr(),
            style: TextStyle(
              fontSize: 19,
              fontWeight: FontWeight.w700,
              color: cs.foreground,
            ),
          ),
          const SizedBox(height: 6),
          Text(
            'room.enter_code_hint'.tr(),
            style: TextStyle(fontSize: 13.5, color: cs.mutedForeground),
          ),
          const SizedBox(height: 20),
          CodeField(controller: _controller, onComplete: widget.onJoin),
          const SizedBox(height: 20),
          SizedBox(
            width: double.infinity,
            child: ShadButton(
              size: ShadButtonSize.lg,
              onPressed: () => widget.onJoin(_controller.text),
              child: Text('room.join_room'.tr()),
            ),
          ),
        ],
      ),
    );
  }
}
