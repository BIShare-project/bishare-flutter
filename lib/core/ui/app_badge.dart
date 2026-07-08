import 'package:flutter/material.dart';
import 'package:shadcn_ui/shadcn_ui.dart';

/// A small tinted tag (e.g. a transport label like "TCP"). Defaults to the
/// theme primary; pass [color] to override.
class AppBadge extends StatelessWidget {
  const AppBadge(this.label, {super.key, this.color});

  final String label;
  final Color? color;

  @override
  Widget build(BuildContext context) {
    final c = color ?? ShadTheme.of(context).colorScheme.primary;
    return Container(
      padding: const EdgeInsets.symmetric(horizontal: 7, vertical: 2),
      decoration: BoxDecoration(
        color: c.withValues(alpha: 0.14),
        borderRadius: BorderRadius.circular(6),
      ),
      child: Text(
        label,
        style: TextStyle(
          fontSize: 10,
          fontWeight: FontWeight.w800,
          letterSpacing: 0.3,
          color: c,
        ),
      ),
    );
  }
}

/// A pill with a leading status dot (e.g. "Online"). Defaults to iOS green.
class AppStatusPill extends StatelessWidget {
  const AppStatusPill(
    this.label, {
    super.key,
    this.color = const Color(0xFF34C759),
  });

  final String label;
  final Color color;

  @override
  Widget build(BuildContext context) {
    return Container(
      padding: const EdgeInsets.symmetric(horizontal: 10, vertical: 5),
      decoration: BoxDecoration(
        color: color.withValues(alpha: 0.14),
        borderRadius: BorderRadius.circular(20),
      ),
      child: Row(
        mainAxisSize: MainAxisSize.min,
        children: [
          Container(
            width: 8,
            height: 8,
            decoration: BoxDecoration(color: color, shape: BoxShape.circle),
          ),
          const SizedBox(width: 6),
          Text(
            label,
            style: TextStyle(
              fontSize: 12,
              fontWeight: FontWeight.w600,
              color: color,
            ),
          ),
        ],
      ),
    );
  }
}
