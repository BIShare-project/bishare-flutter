import 'package:flutter/material.dart';

import '../../../../core/ui/app_rows.dart';

/// A settings switch row: the shared [AppSwitchRow].
class SwitchRow extends StatelessWidget {
  const SwitchRow({
    super.key,
    required this.icon,
    required this.title,
    required this.subtitle,
    required this.value,
    required this.onChanged,
  });

  final String icon;
  final String title;
  final String subtitle;
  final bool value;
  final ValueChanged<bool> onChanged;

  @override
  Widget build(BuildContext context) => AppSwitchRow(
    icon: icon,
    title: title,
    subtitle: subtitle,
    value: value,
    onChanged: onChanged,
  );
}
