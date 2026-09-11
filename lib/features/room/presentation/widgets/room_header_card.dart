import 'package:easy_localization/easy_localization.dart';
import 'package:flutter/material.dart';
import 'package:shadcn_ui/shadcn_ui.dart';

import '../../../../core/ui/app_ui.dart';
import '../../domain/room_models.dart';
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
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Row(
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
                    padding: const EdgeInsets.symmetric(
                      horizontal: 8,
                      vertical: 2,
                    ),
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
                    'room.n_connected'.tr(
                      namedArgs: {'count': '${state.members.length}'},
                    ),
                    style: TextStyle(fontSize: 11.5, color: cs.mutedForeground),
                  ),
                ],
              ),
            ],
          ),
          if (state.security != RoomSecurity.unknown) ...[
            const SizedBox(height: 10),
            _SecurityLine(security: state.security),
          ],
        ],
      ),
    );
  }
}

/// Whether the room's files are end-to-end encrypted on this device.
class _SecurityLine extends StatelessWidget {
  const _SecurityLine({required this.security});
  final RoomSecurity security;

  @override
  Widget build(BuildContext context) {
    final cs = ShadTheme.of(context).colorScheme;
    final (Widget icon, String text, Color color) = switch (security) {
      RoomSecurity.encrypted => (
        AppSvgIcon(AppIcons.passwordLock, size: 14, color: kOnlineGreen),
        'room.e2e_on'.tr(),
        kOnlineGreen,
      ),
      RoomSecurity.waitingForKey => (
        SizedBox(
          width: 12,
          height: 12,
          child: CircularProgressIndicator(
            strokeWidth: 1.6,
            valueColor: AlwaysStoppedAnimation(cs.mutedForeground),
          ),
        ),
        'room.e2e_waiting'.tr(),
        cs.mutedForeground,
      ),
      _ => (
        const Icon(Icons.lock_open_rounded, size: 14, color: Color(0xFFD97706)),
        'room.e2e_off'.tr(),
        const Color(0xFFD97706),
      ),
    };
    return Row(
      children: [
        icon,
        const SizedBox(width: 6),
        Expanded(
          child: Text(
            text,
            maxLines: 2,
            overflow: TextOverflow.ellipsis,
            style: TextStyle(
              fontSize: 12,
              fontWeight: FontWeight.w600,
              color: color,
            ),
          ),
        ),
      ],
    );
  }
}
