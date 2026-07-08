import 'package:flutter/material.dart';
import 'package:shadcn_ui/shadcn_ui.dart';

/// An uppercase, tracked-out grouped-list section label (iOS Settings style).
class AppSectionHeader extends StatelessWidget {
  const AppSectionHeader(this.label, {super.key, this.trailing});

  final String label;
  final Widget? trailing;

  @override
  Widget build(BuildContext context) {
    final cs = ShadTheme.of(context).colorScheme;
    return Padding(
      padding: const EdgeInsets.fromLTRB(22, 16, 22, 8),
      child: Row(
        children: [
          Text(
            label.toUpperCase(),
            style: TextStyle(
              fontSize: 11.5,
              fontWeight: FontWeight.w700,
              letterSpacing: 0.7,
              color: cs.mutedForeground,
            ),
          ),
          const Spacer(),
          if (trailing != null)
            DefaultTextStyle.merge(
              style: TextStyle(
                fontSize: 11.5,
                fontWeight: FontWeight.w600,
                color: cs.mutedForeground,
              ),
              child: trailing!,
            ),
        ],
      ),
    );
  }
}

/// A rounded, hairline-bordered container that groups list rows (iOS inset
/// card). Children are clipped to the corner radius.
class AppGroup extends StatelessWidget {
  const AppGroup({super.key, required this.child, this.margin});

  final Widget child;
  final EdgeInsetsGeometry? margin;

  @override
  Widget build(BuildContext context) {
    final cs = ShadTheme.of(context).colorScheme;
    return Container(
      margin: margin ?? const EdgeInsets.symmetric(horizontal: 14),
      decoration: BoxDecoration(
        color: cs.card,
        borderRadius: BorderRadius.circular(18),
        border: Border.all(color: cs.border.withValues(alpha: 0.8)),
      ),
      clipBehavior: Clip.antiAlias,
      child: child,
    );
  }
}

/// A hairline divider between [AppGroup] rows, inset to clear a leading avatar.
class AppRowDivider extends StatelessWidget {
  const AppRowDivider({super.key, this.indent = 74});

  final double indent;

  @override
  Widget build(BuildContext context) {
    final cs = ShadTheme.of(context).colorScheme;
    return Padding(
      padding: EdgeInsets.only(left: indent),
      child: Divider(
        height: 1,
        thickness: 1,
        color: cs.border.withValues(alpha: 0.6),
      ),
    );
  }
}
