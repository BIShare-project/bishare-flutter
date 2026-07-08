import 'package:flutter/material.dart';
import 'package:flutter_bloc/flutter_bloc.dart';
import 'package:shadcn_ui/shadcn_ui.dart';

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
        child: BlocBuilder<RoomCubit, RoomState>(
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
