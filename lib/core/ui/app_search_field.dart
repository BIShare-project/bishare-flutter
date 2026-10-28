import 'package:flutter/material.dart';

import '../theme/app_tokens.dart';
import '../theme/app_type.dart';
import 'app_svg_icon.dart';

/// A search box on a sunken field, the same in every list that filters as
/// you type (History, Apps, Browse files). 44 high, so it is a full tap
/// target; the accent ring shows focus.
class AppSearchField extends StatefulWidget {
  const AppSearchField({
    super.key,
    required this.hint,
    required this.onChanged,
    this.margin = const EdgeInsets.fromLTRB(14, 6, 14, 4),
    this.controller,
    this.focusNode,
  });

  final String hint;
  final ValueChanged<String> onChanged;
  final EdgeInsetsGeometry margin;

  /// The page's own, when it also changes the text or the focus (Drive's
  /// shortcuts); otherwise the field keeps its own.
  final TextEditingController? controller;
  final FocusNode? focusNode;

  @override
  State<AppSearchField> createState() => _AppSearchFieldState();
}

class _AppSearchFieldState extends State<AppSearchField> {
  late final FocusNode _focus = widget.focusNode ?? FocusNode();
  late final TextEditingController _text =
      widget.controller ?? TextEditingController();

  void _changed() => setState(() {});

  @override
  void initState() {
    super.initState();
    _focus.addListener(_changed);
    _text.addListener(_changed);
  }

  @override
  void dispose() {
    _focus.removeListener(_changed);
    _text.removeListener(_changed);
    if (widget.focusNode == null) _focus.dispose();
    if (widget.controller == null) _text.dispose();
    super.dispose();
  }

  @override
  Widget build(BuildContext context) {
    final t = context.tokens;
    return Padding(
      padding: widget.margin,
      child: Container(
        constraints: const BoxConstraints(minHeight: 44),
        padding: const EdgeInsetsDirectional.only(start: 12, end: 4),
        decoration: BoxDecoration(
          color: t.sunken,
          borderRadius: BorderRadius.circular(12),
          border: Border.all(
            color: _focus.hasFocus ? t.accent : Colors.transparent,
            width: 1.5,
          ),
        ),
        child: Row(
          children: [
            AppSvgIcon(AppIcons.search, size: 19, color: t.text2),
            const SizedBox(width: 8),
            Expanded(
              child: TextField(
                controller: _text,
                focusNode: _focus,
                onChanged: widget.onChanged,
                textInputAction: TextInputAction.search,
                style: AppType.row.copyWith(
                  color: t.text,
                  fontWeight: FontWeight.w400,
                ),
                decoration: InputDecoration(
                  isDense: true,
                  border: InputBorder.none,
                  hintText: widget.hint,
                  hintStyle: AppType.row.copyWith(
                    color: t.text3,
                    fontWeight: FontWeight.w400,
                  ),
                ),
              ),
            ),
            if (_text.text.isNotEmpty)
              IconButton(
                tooltip: MaterialLocalizations.of(context).deleteButtonTooltip,
                icon: AppSvgIcon(AppIcons.close, size: 16, color: t.text2),
                onPressed: () {
                  _text.clear();
                  widget.onChanged('');
                },
              ),
          ],
        ),
      ),
    );
  }
}
