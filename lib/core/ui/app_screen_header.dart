import 'package:flutter/material.dart';

import '../theme/app_tokens.dart';
import '../theme/app_type.dart';
import 'app_icon_button.dart';
import 'app_svg_icon.dart';

/// A tab's title bar: the title, an optional [subtitle] and trailing
/// [actions]. Pass [onBack] on a pushed page to show a back button.
class AppScreenHeader extends StatelessWidget {
  const AppScreenHeader({
    super.key,
    required this.title,
    this.subtitle,
    this.actions = const [],
    this.onBack,
  });

  final String title;
  final String? subtitle;
  final List<Widget> actions;

  /// When non-null, a leading back button is shown that calls this.
  final VoidCallback? onBack;

  @override
  Widget build(BuildContext context) {
    final t = context.tokens;
    final pushed = onBack != null;
    return Padding(
      padding: EdgeInsetsDirectional.fromSTEB(pushed ? 6 : 18, 8, 8, 6),
      child: Row(
        children: [
          if (pushed)
            AppIconButton(
              icon: AppIcons.chevronLeft,
              size: 22,
              tooltip: MaterialLocalizations.of(context).backButtonTooltip,
              onPressed: onBack!,
            ),
          Expanded(
            child: Column(
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                Semantics(
                  header: true,
                  child: Text(
                    title,
                    maxLines: pushed ? 1 : 2,
                    overflow: TextOverflow.ellipsis,
                    style: (pushed ? AppType.pageTitle : AppType.title)
                        .copyWith(color: t.text),
                  ),
                ),
                if (subtitle != null && subtitle!.isNotEmpty)
                  Padding(
                    padding: const EdgeInsets.only(top: 2),
                    child: Text(
                      subtitle!,
                      style: AppType.secondary.copyWith(color: t.text2),
                    ),
                  ),
              ],
            ),
          ),
          ...actions,
        ],
      ),
    );
  }
}
