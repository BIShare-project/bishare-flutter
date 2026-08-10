import 'package:easy_localization/easy_localization.dart';
import 'package:flutter/material.dart';
import 'package:flutter_bloc/flutter_bloc.dart';
import 'package:shadcn_ui/shadcn_ui.dart';
import 'package:url_launcher/url_launcher.dart';

import '../../../core/ui/app_sheet.dart';
import 'room_cubit.dart';
import 'widgets/connecting_view.dart';
import 'widgets/in_room.dart';
import 'widgets/lobby.dart';

/// Transfer Rooms — a shared space where everyone can drop files and download
/// each other's. Ports the native `RoomView`: a lobby to create/join, then an
/// in-room view with live members + a shared-files list.
class RoomPage extends StatelessWidget {
  const RoomPage({super.key});

  @override
  Widget build(BuildContext context) {
    final cs = ShadTheme.of(context).colorScheme;
    return Scaffold(
      backgroundColor: cs.background,
      body: SafeArea(
        child: BlocConsumer<RoomCubit, RoomState>(
          // The code is a browser-hosted (WebRTC) room the app can't join
          // without a TURN relay — explain it in a sheet rather than fail.
          listenWhen: (prev, curr) => curr.webRoomHint && !prev.webRoomHint,
          listener: (context, state) {
            final cubit = context.read<RoomCubit>();
            showAppSheet<void>(
              context,
              title: 'room.web_room_title'.tr(),
              subtitle: 'room.web_room_body'.tr(),
              builder: (ctx) => Column(
                mainAxisSize: MainAxisSize.min,
                children: [
                  SizedBox(
                    width: double.infinity,
                    child: ShadButton(
                      onPressed: () {
                        final code = state.webRoomCode ?? '';
                        launchUrl(
                          Uri.parse('https://bishare.app/rooms?code=$code&mode=local'),
                          mode: LaunchMode.externalApplication,
                        );
                        Navigator.pop(ctx);
                      },
                      child: Text('room.web_room_open'.tr()),
                    ),
                  ),
                  const SizedBox(height: 8),
                  SizedBox(
                    width: double.infinity,
                    child: ShadButton.outline(
                      onPressed: () => Navigator.pop(ctx),
                      child: Text('room.web_room_ok'.tr()),
                    ),
                  ),
                ],
              ),
            ).then((_) => cubit.dismissWebRoomHint());
          },
          builder: (context, state) => switch (state.status) {
            RoomStatus.inRoom => InRoom(state: state),
            RoomStatus.connecting => ConnectingView(
              label: state.connectingLabel,
            ),
            RoomStatus.lobby || RoomStatus.error => Lobby(state: state),
          },
        ),
      ),
    );
  }
}
