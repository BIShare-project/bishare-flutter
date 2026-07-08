import 'package:easy_localization/easy_localization.dart';
import 'package:flutter/material.dart';
import 'package:flutter_bloc/flutter_bloc.dart';
import 'package:shadcn_ui/shadcn_ui.dart';

import '../../../../core/ui/app_ui.dart';
import '../../domain/room_models.dart';
import '../room_cubit.dart';

class RoomTopBar extends StatelessWidget {
  const RoomTopBar({super.key, required this.session});
  final RoomSession session;

  @override
  Widget build(BuildContext context) {
    final cs = ShadTheme.of(context).colorScheme;
    return Padding(
      padding: const EdgeInsets.fromLTRB(16, 8, 8, 4),
      child: Row(
        children: [
          Container(
            width: 8,
            height: 8,
            decoration: const BoxDecoration(
              color: kOnlineGreen,
              shape: BoxShape.circle,
            ),
          ),
          const SizedBox(width: 8),
          Text(
            session.code,
            style: TextStyle(
              fontSize: 17,
              fontWeight: FontWeight.w800,
              letterSpacing: 2,
              fontFeatures: const [FontFeature.tabularFigures()],
              color: cs.foreground,
            ),
          ),
          const SizedBox(width: 8),
          Container(
            padding: const EdgeInsets.symmetric(horizontal: 8, vertical: 2),
            decoration: BoxDecoration(
              color: cs.primary.withValues(alpha: 0.12),
              borderRadius: BorderRadius.circular(20),
            ),
            child: Text(
              session.remote ? 'room.remote'.tr() : 'room.local'.tr(),
              style: TextStyle(
                fontSize: 11,
                fontWeight: FontWeight.w700,
                color: cs.primary,
              ),
            ),
          ),
          const Spacer(),
          ShadButton.ghost(
            onPressed: () => context.read<RoomCubit>().leave(),
            child: Text('room.leave'.tr(), style: TextStyle(color: cs.destructive)),
          ),
        ],
      ),
    );
  }
}
