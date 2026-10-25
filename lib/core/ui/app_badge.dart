import 'package:flutter/material.dart';

import '../theme/app_tokens.dart';
import '../theme/app_type.dart';

/// A small tag for a real label (a transport such as "TCP", "Penyedia").
/// Neutral by default; pass [color] for a status tint.
class AppBadge extends StatelessWidget {
  const AppBadge(this.label, {super.key, this.color});

  final String label;
  final Color? color;

  @override
  Widget build(BuildContext context) {
    final t = context.tokens;
    final c = color;
    return Container(
      padding: const EdgeInsets.symmetric(horizontal: 7, vertical: 2),
      decoration: BoxDecoration(
        color: c == null ? t.sunken : c.withValues(alpha: 0.12),
        borderRadius: BorderRadius.circular(6),
      ),
      child: Text(
        label,
        style: AppType.small.copyWith(
          fontSize: 11,
          fontWeight: FontWeight.w600,
          color: c ?? t.text2,
        ),
      ),
    );
  }
}

/// A status dot with its label (e.g. "Online"). The ok colour by default.
class AppStatusPill extends StatelessWidget {
  const AppStatusPill(this.label, {super.key, this.color});

  final String label;
  final Color? color;

  @override
  Widget build(BuildContext context) {
    final t = context.tokens;
    final c = color ?? t.ok;
    return Row(
      mainAxisSize: MainAxisSize.min,
      children: [
        Container(
          width: 8,
          height: 8,
          decoration: BoxDecoration(color: c, shape: BoxShape.circle),
        ),
        const SizedBox(width: 6),
        Text(
          label,
          style: AppType.small.copyWith(fontSize: 13, color: t.text2),
        ),
      ],
    );
  }
}
