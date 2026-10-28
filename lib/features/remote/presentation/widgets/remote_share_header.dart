import 'package:easy_localization/easy_localization.dart';
import 'package:flutter/material.dart';
import 'package:go_router/go_router.dart';

import '../../../../core/ui/app_ui.dart';

/// Secure Link's title row: the kit's pushed-page header (back, title).
class RemoteShareHeader extends StatelessWidget {
  const RemoteShareHeader({super.key, required this.showBack});
  final bool showBack;

  @override
  Widget build(BuildContext context) =>
      AppScreenHeader(title: 'remote.title'.tr(), onBack: () => context.pop());
}
