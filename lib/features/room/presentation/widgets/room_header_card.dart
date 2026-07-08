import 'package:easy_localization/easy_localization.dart';
import 'package:flutter/material.dart';
import 'package:shadcn_ui/shadcn_ui.dart';

import '../room_cubit.dart';

class RoomHeaderCard extends StatelessWidget {
  const RoomHeaderCard({super.key, required this.state});
  final RoomState state;

  @override
  Widget build(BuildContext context) {
    final cs = ShadTheme.of(context).colorScheme;
    final session = state.session!;
    return Container(
      padding: const EdgeInsets.all(14),
      decoration: BoxDecoration(
        color: cs.card,
        borderRadius: BorderRadius.circular(16),
        border: Border.all(color: cs.border.withValues(alpha: 0.8)),
      ),
      child: Row(
        children: [
          for (final ch in session.code.split(''))
            Container(
              width: 36,
              height: 42,
              margin: const EdgeInsets.only(right: 6),
              alignment: Alignment.center,
              decoration: BoxDecoration(
                color: cs.primary.withValues(alpha: 0.1),
                borderRadius: BorderRadius.circular(8),
              ),
              child: Text(
                ch,
                style: TextStyle(
                  fontSize: 22,
                  fontWeight: FontWeight.w800,
                  color: cs.primary,
                ),
              ),
            ),
          const Spacer(),
          Column(
            crossAxisAlignment: CrossAxisAlignment.end,
            children: [
              Container(
                padding: const EdgeInsets.symmetric(horizontal: 8, vertical: 2),
                decoration: BoxDecoration(
                  color: cs.primary.withValues(alpha: 0.1),
                  borderRadius: BorderRadius.circular(20),
                ),
                child: Text(
                  session.isHost ? 'room.host'.tr() : 'room.member'.tr(),
                  style: TextStyle(
                    fontSize: 11.5,
                    fontWeight: FontWeight.w700,
                    color: cs.primary,
                  ),
                ),
              ),
              const SizedBox(height: 3),
              Text(
                'room.n_connected'.tr(namedArgs: {'count': '${state.members.length}'}),
                style: TextStyle(fontSize: 11.5, color: cs.mutedForeground),
              ),
            ],
          ),
        ],
      ),
    );
  }
}
