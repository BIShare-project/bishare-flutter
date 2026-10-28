import 'package:easy_localization/easy_localization.dart';
import 'package:flutter/material.dart';
import 'package:flutter_bloc/flutter_bloc.dart';

import '../../../../core/ui/app_showcase.dart';
import '../../../../core/ui/app_ui.dart';
import '../room_cubit.dart';
import 'how_it_works.dart';

/// The Rooms lobby (redesign-plan.md 7.1): start a room over the internet
/// or on this Wi-Fi, or join one by typing its four-letter code right here.
/// "How it works" opens in a sheet; a failed create or join says so above
/// the choices.
class Lobby extends StatefulWidget {
  const Lobby({super.key, required this.state});
  final RoomState state;

  @override
  State<Lobby> createState() => _LobbyState();
}

class _LobbyState extends State<Lobby> {
  final TextEditingController _code = TextEditingController();

  @override
  void dispose() {
    _code.dispose();
    super.dispose();
  }

  void _join(String code) {
    if (code.trim().length < 4) return;
    FocusScope.of(context).unfocus();
    context.read<RoomCubit>().joinRoom(code);
  }

  @override
  Widget build(BuildContext context) {
    final t = context.tokens;
    final cubit = context.read<RoomCubit>();
    final failed =
        widget.state.status == RoomStatus.error &&
        widget.state.error.isNotEmpty;
    return Column(
      children: [
        AppScreenHeader(
          title: 'room.title'.tr(),
          subtitle: 'room.subtitle'.tr(),
        ),
        Expanded(
          child: AppResponsivePane(
            maxWidth: 560,
            child: ListView(
              padding: const EdgeInsets.only(bottom: 120),
              children: [
                if (failed)
                  Container(
                    margin: const EdgeInsets.fromLTRB(14, 4, 14, 8),
                    padding: const EdgeInsetsDirectional.fromSTEB(
                      12,
                      10,
                      12,
                      10,
                    ),
                    decoration: BoxDecoration(
                      color: t.danger.withValues(alpha: 0.1),
                      borderRadius: BorderRadius.circular(12),
                    ),
                    child: Row(
                      children: [
                        AppSvgIcon(
                          AppIcons.circleAlert,
                          size: 18,
                          color: t.danger,
                        ),
                        const SizedBox(width: 10),
                        Expanded(
                          child: Text(
                            widget.state.error,
                            style: AppType.secondary.copyWith(color: t.danger),
                          ),
                        ),
                      ],
                    ),
                  ),
                AppSectionHeader('room.start_room'.tr()),
                AppShowcase(
                  showcaseKey: ShowcaseKeys.roomCreate,
                  title: 'showcase.room_create_title'.tr(),
                  description: 'showcase.room_create_body'.tr(),
                  targetRadius: 16,
                  child: Column(
                    children: [
                      _Choice(
                        icon: AppIcons.globePublic,
                        title: 'room.remote_room'.tr(),
                        subtitle: 'room.remote_desc'.tr(),
                        onTap: () => cubit.createRoom(local: false),
                      ),
                      const AppRowDivider(indent: 70),
                      _Choice(
                        icon: AppIcons.wifi,
                        title: 'room.local_room'.tr(),
                        subtitle: 'room.local_desc'.tr(),
                        onTap: () => cubit.createRoom(local: true),
                      ),
                    ],
                  ),
                ),
                const SizedBox(height: 12),
                AppSectionHeader('room.join_with_code'.tr()),
                AppShowcase(
                  showcaseKey: ShowcaseKeys.roomJoin,
                  title: 'showcase.room_join_title'.tr(),
                  description: 'showcase.room_join_body'.tr(),
                  targetRadius: 14,
                  child: Padding(
                    padding: const EdgeInsets.fromLTRB(14, 2, 14, 0),
                    child: Column(
                      crossAxisAlignment: CrossAxisAlignment.stretch,
                      children: [
                        AppCodeBoxes(
                          controller: _code,
                          length: 4,
                          onComplete: _join,
                        ),
                        const SizedBox(height: 12),
                        ListenableBuilder(
                          listenable: _code,
                          builder: (context, _) => AppButton(
                            label: 'room.join_room'.tr(),
                            icon: AppIcons.logIn,
                            size: AppButtonSize.large,
                            fullWidth: true,
                            disabled: _code.text.trim().length < 4,
                            onPressed: () => _join(_code.text),
                          ),
                        ),
                      ],
                    ),
                  ),
                ),
                const SizedBox(height: 20),
                AppValueRow(
                  icon: AppIcons.teamGroup,
                  title: 'room.how_it_works'.tr(),
                  onTap: () => showHowItWorks(context),
                ),
              ],
            ),
          ),
        ),
      ],
    );
  }
}

/// A way to start a room: a round icon, what it is, how it shares.
class _Choice extends StatelessWidget {
  const _Choice({
    required this.icon,
    required this.title,
    required this.subtitle,
    required this.onTap,
  });

  final String icon;
  final String title;
  final String subtitle;
  final VoidCallback onTap;

  @override
  Widget build(BuildContext context) {
    final t = context.tokens;
    return Material(
      type: MaterialType.transparency,
      child: InkWell(
        onTap: () {
          tapHaptic();
          onTap();
        },
        child: ConstrainedBox(
          constraints: const BoxConstraints(minHeight: 68),
          child: Padding(
            padding: const EdgeInsetsDirectional.fromSTEB(14, 10, 12, 10),
            child: Row(
              children: [
                Container(
                  width: 44,
                  height: 44,
                  alignment: Alignment.center,
                  decoration: BoxDecoration(
                    color: t.accentSoft,
                    shape: BoxShape.circle,
                  ),
                  child: AppSvgIcon(icon, size: 21, color: t.accent),
                ),
                const SizedBox(width: 12),
                Expanded(
                  child: Column(
                    crossAxisAlignment: CrossAxisAlignment.start,
                    children: [
                      Text(
                        title,
                        style: AppType.rowStrong.copyWith(color: t.text),
                      ),
                      const SizedBox(height: 2),
                      Text(
                        subtitle,
                        style: AppType.secondary.copyWith(color: t.text2),
                      ),
                    ],
                  ),
                ),
                AppSvgIcon(AppIcons.chevronRight, size: 18, color: t.text3),
              ],
            ),
          ),
        ),
      ),
    );
  }
}
