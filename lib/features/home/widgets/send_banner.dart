import 'package:easy_localization/easy_localization.dart';
import 'package:flutter/material.dart';
import 'package:flutter_bloc/flutter_bloc.dart';

import '../../../core/ui/app_svg_icon.dart';
import '../../send/presentation/send_cubit.dart';
import 'transfer_card.dart';

class SendBanner extends StatelessWidget {
  const SendBanner({super.key});

  @override
  Widget build(BuildContext context) {
    return BlocBuilder<SendCubit, SendState>(
      builder: (context, state) {
        final cubit = context.read<SendCubit>();
        if (state.status == SendStatus.sending) {
          return TransferCard(
            icon: AppIcons.uploadFile,
            title: 'home.sending_to'.tr(
              namedArgs: {'alias': state.deviceAlias},
            ),
            subtitle: state.fileName.isEmpty
                ? 'home.preparing'.tr()
                : state.fileName,
            fraction: state.fraction,
            speed: state.speed,
            etaSeconds: state.etaSeconds,
            transport: state.transport,
            onCancel: cubit.cancel,
          );
        }
        if (state.status == SendStatus.error) {
          return TransferCard(
            icon: AppIcons.circleAlert,
            title: 'home.send_failed_to'.tr(
              namedArgs: {'alias': state.deviceAlias},
            ),
            subtitle: state.message,
            fraction: 0,
            isError: true,
            onRetry: cubit.retryLast,
            onCancel: cubit.reset,
          );
        }
        return const SizedBox.shrink();
      },
    );
  }
}
