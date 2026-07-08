import 'package:flutter/material.dart';
import 'package:shadcn_ui/shadcn_ui.dart';

class StatCard extends StatelessWidget {
  const StatCard({super.key, required this.label, required this.value});
  final String label;
  final int value;

  @override
  Widget build(BuildContext context) {
    final cs = ShadTheme.of(context).colorScheme;
    return Container(
      padding: const EdgeInsets.symmetric(vertical: 10),
      decoration: BoxDecoration(
        color: cs.card,
        borderRadius: BorderRadius.circular(14),
        border: Border.all(color: cs.border.withValues(alpha: 0.8)),
      ),
      child: Column(
        children: [
          Text(
            '$value',
            style: TextStyle(
              fontSize: 18,
              fontWeight: FontWeight.w700,
              color: cs.foreground,
            ),
          ),
          Text(
            label,
            style: TextStyle(fontSize: 11.5, color: cs.mutedForeground),
          ),
        ],
      ),
    );
  }
}
