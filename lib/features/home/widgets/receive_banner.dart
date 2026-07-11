import 'package:easy_localization/easy_localization.dart';
import 'package:flutter/material.dart';
import 'package:flutter_bloc/flutter_bloc.dart';

import '../../../core/ui/app_svg_icon.dart';
import '../../receive/presentation/receive_cubit.dart';
import '../../settings/domain/settings.dart' show AccentColors;
import '../../settings/presentation/settings_cubit.dart';
import 'transfer_card.dart';

class ReceiveBanner extends StatelessWidget {
  const ReceiveBanner({super.key});

  @override
  Widget build(BuildContext context) {
    return BlocBuilder<ReceiveCubit, ReceiveState>(
      builder: (context, state) {
        final p = state.progress;
        if (p == null) return const SizedBox.shrink();
        return TransferCard(
          icon: AppIcons.downloadFile,
          title: 'home.receiving_from'.tr(
            namedArgs: {'alias': p.senderAlias},
          ),
          subtitle: p.currentFileName.isEmpty
              ? 'home.starting'.tr()
              : p.currentFileName,
          fraction: p.fraction,
          speed: state.speed,
          etaSeconds: state.etaSeconds,
          // Mirror the sender's live badge: show the transport actually
          // delivering this session (QUIC receives used to mislabel as "TCP").
          transport: p.transport,
          accentColor: AccentColors.of(
            context.read<SettingsCubit>().state.receiveAccent,
            Theme.of(context).brightness,
          ),
        );
      },
    );
  }
}
