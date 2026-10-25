import 'package:flutter/material.dart';

import '../theme/app_tokens.dart';
import '../theme/app_type.dart';

/// A section label in sentence case, above a group of rows.
class AppSectionHeader extends StatelessWidget {
  const AppSectionHeader(this.label, {super.key, this.trailing});

  final String label;
  final Widget? trailing;

  @override
  Widget build(BuildContext context) {
    final t = context.tokens;
    return Padding(
      padding: const EdgeInsetsDirectional.fromSTEB(18, 22, 18, 6),
      child: Row(
        children: [
          Expanded(
            child: Semantics(
              header: true,
              child: Text(label, style: AppType.label.copyWith(color: t.text2)),
            ),
          ),
          if (trailing != null)
            DefaultTextStyle.merge(
              style: AppType.label.copyWith(
                fontWeight: FontWeight.w500,
                color: t.text2,
              ),
              child: trailing!,
            ),
        ],
      ),
    );
  }
}

/// Groups rows. Flat by default: the rows sit on the screen background and
/// [AppRowDivider] hairlines separate them (redesign-plan.md "Space, shape,
/// depth"). [card] draws the old inset card for the one block a screen
/// emphasises.
class AppGroup extends StatelessWidget {
  const AppGroup({
    super.key,
    required this.child,
    this.margin,
    this.card = false,
  });

  final Widget child;
  final EdgeInsetsGeometry? margin;
  final bool card;

  @override
  Widget build(BuildContext context) {
    if (!card) {
      return Padding(padding: margin ?? EdgeInsets.zero, child: child);
    }
    final t = context.tokens;
    return Container(
      margin: margin ?? const EdgeInsets.symmetric(horizontal: 14),
      decoration: BoxDecoration(
        color: t.surface,
        borderRadius: BorderRadius.circular(16),
        border: Border.all(color: t.line),
      ),
      clipBehavior: Clip.antiAlias,
      child: child,
    );
  }
}

/// A hairline between [AppGroup] rows, inset to clear a leading glyph.
class AppRowDivider extends StatelessWidget {
  const AppRowDivider({super.key, this.indent = 74});

  final double indent;

  @override
  Widget build(BuildContext context) {
    return Padding(
      padding: EdgeInsetsDirectional.only(start: indent),
      child: Divider(height: 1, thickness: 1, color: context.tokens.line),
    );
  }
}
