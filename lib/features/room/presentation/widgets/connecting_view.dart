import 'package:flutter/material.dart';

import '../../../../core/ui/app_ui.dart';

/// The room "connecting" state (redesign-plan.md 7.2): a spinner inside a
/// soft circle and the label (e.g. "Looking for a room"). The spinner is the
/// only motion.
class ConnectingView extends StatelessWidget {
  const ConnectingView({super.key, required this.label});

  final String label;

  @override
  Widget build(BuildContext context) {
    final t = context.tokens;
    return Center(
      child: Column(
        mainAxisSize: MainAxisSize.min,
        children: [
          Container(
            width: 72,
            height: 72,
            padding: const EdgeInsets.all(20),
            decoration: BoxDecoration(
              color: t.accentSoft,
              shape: BoxShape.circle,
            ),
            child: CircularProgressIndicator(strokeWidth: 3, color: t.accent),
          ),
          const SizedBox(height: 18),
          Text(
            '$label…',
            textAlign: TextAlign.center,
            style: AppType.rowStrong.copyWith(color: t.text),
          ),
        ],
      ),
    );
  }
}
