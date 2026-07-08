import 'package:easy_localization/easy_localization.dart';
import 'package:flutter/material.dart';
import 'package:flutter_bloc/flutter_bloc.dart';
import 'package:shadcn_ui/shadcn_ui.dart';

import '../../../../core/ui/app_ui.dart';
import '../room_cubit.dart';
import 'how_it_works.dart';
import 'join_sheet.dart';

class Lobby extends StatelessWidget {
  const Lobby({super.key, required this.state});
  final RoomState state;

  @override
  Widget build(BuildContext context) {
    final cs = ShadTheme.of(context).colorScheme;
    return SingleChildScrollView(
      padding: const EdgeInsets.fromLTRB(24, 24, 24, 24),
      child: Column(
        children: [
          const AppResponsivePane(maxWidth: 480, child: SizedBox.shrink()),
          Container(
            width: 92,
            height: 92,
            decoration: BoxDecoration(
              gradient: LinearGradient(
                begin: Alignment.topLeft,
                end: Alignment.bottomRight,
                colors: [
                  cs.primary,
                  Color.lerp(cs.primary, Colors.black, 0.22)!,
                ],
              ),
              shape: BoxShape.circle,
              boxShadow: [
                BoxShadow(
                  color: cs.primary.withValues(alpha: 0.35),
                  blurRadius: 24,
                  offset: const Offset(0, 10),
                ),
              ],
            ),
            child: AppSvgIcon(
              AppIcons.teamGroup,
              size: 38,
              color: cs.primaryForeground,
            ),
          ),
          const SizedBox(height: 20),
          Text(
            'room.title'.tr(),
            style: TextStyle(
              fontSize: 22,
              fontWeight: FontWeight.w800,
              letterSpacing: -0.3,
              color: cs.foreground,
            ),
          ),
          const SizedBox(height: 8),
          Text(
            'room.subtitle'.tr(),
            textAlign: TextAlign.center,
            style: TextStyle(
              fontSize: 14,
              height: 1.35,
              color: cs.mutedForeground,
            ),
          ),
          const SizedBox(height: 28),
          SizedBox(
            width: double.infinity,
            child: ShadButton(
              size: ShadButtonSize.lg,
              leading: const AppSvgIcon(AppIcons.wifi, size: 18),
              onPressed: () =>
                  context.read<RoomCubit>().createRoom(local: true),
              child: Text('room.local_room'.tr()),
            ),
          ),
          const SizedBox(height: 10),
          SizedBox(
            width: double.infinity,
            child: ShadButton(
              size: ShadButtonSize.lg,
              leading: const AppSvgIcon(AppIcons.globePublic, size: 18),
              onPressed: () =>
                  context.read<RoomCubit>().createRoom(local: false),
              child: Text('room.remote_room'.tr()),
            ),
          ),
          const SizedBox(height: 10),
          SizedBox(
            width: double.infinity,
            child: ShadButton.outline(
              size: ShadButtonSize.lg,
              leading: const AppSvgIcon(AppIcons.logIn, size: 18),
              onPressed: () => _showJoin(context),
              child: Text('room.join_with_code'.tr()),
            ),
          ),
          const SizedBox(height: 28),
          HowItWorks(),
        ],
      ),
    );
  }

  void _showJoin(BuildContext context) {
    final cubit = context.read<RoomCubit>();
    showGlassModal<void>(
      context,
      builder: (ctx) => JoinSheet(
        onJoin: (code) {
          Navigator.pop(ctx);
          cubit.joinRoom(code);
        },
      ),
    );
  }
}
