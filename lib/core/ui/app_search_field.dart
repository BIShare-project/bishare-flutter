import 'package:easy_localization/easy_localization.dart';
import 'package:flutter/material.dart';

import '../theme/app_tokens.dart';
import '../theme/app_type.dart';
import 'app_button.dart';
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
    // iOS-sized: a 36 pt pill, no focus ring, a small round clear button.
    return Padding(
      padding: widget.margin,
      child: Container(
        height: 36,
        padding: const EdgeInsetsDirectional.only(start: 10, end: 6),
        decoration: BoxDecoration(
          color: t.sunken,
          borderRadius: BorderRadius.circular(10),
        ),
        child: Row(
          children: [
            AppSvgIcon(AppIcons.search, size: 16, color: t.text3),
            const SizedBox(width: 6),
            Expanded(
              child: TextField(
                controller: _text,
                focusNode: _focus,
                onChanged: widget.onChanged,
                textInputAction: TextInputAction.search,
                cursorHeight: 18,
                style: AppType.body.copyWith(color: t.text, height: 1.2),
                decoration: InputDecoration(
                  isDense: true,
                  contentPadding: EdgeInsets.zero,
                  border: InputBorder.none,
                  hintText: widget.hint,
                  hintStyle: AppType.body.copyWith(color: t.text3, height: 1.2),
                ),
              ),
            ),
            if (_text.text.isNotEmpty)
              Semantics(
                button: true,
                label: MaterialLocalizations.of(context).deleteButtonTooltip,
                child: GestureDetector(
                  behavior: HitTestBehavior.opaque,
                  onTap: () {
                    _text.clear();
                    widget.onChanged('');
                  },
                  child: Padding(
                    padding: const EdgeInsets.all(4),
                    child: Container(
                      width: 18,
                      height: 18,
                      alignment: Alignment.center,
                      decoration: BoxDecoration(
                        color: t.text3,
                        shape: BoxShape.circle,
                      ),
                      child: AppSvgIcon(AppIcons.close, size: 11, color: t.bg),
                    ),
                  ),
                ),
              ),
          ],
        ),
      ),
    );
  }
}

/// The search row a phone screen opens from the magnifier in its header
/// (History, Drive, Devices): the iOS-size field, focused at once, and a
/// Cancel button that closes it.
class AppSearchRow extends StatefulWidget {
  const AppSearchRow({
    super.key,
    required this.hint,
    required this.onChanged,
    required this.onCancel,
    this.initial = '',
    this.controller,
    this.focusNode,
  });

  final String hint;
  final ValueChanged<String> onChanged;

  /// Clears the query and closes the row; the screen does both.
  final VoidCallback onCancel;

  /// The query already in force, when the row reopens.
  final String initial;

  /// The screen's own, when it also changes the text or the focus (Drive's
  /// shortcuts); otherwise the row keeps its own.
  final TextEditingController? controller;
  final FocusNode? focusNode;

  @override
  State<AppSearchRow> createState() => _AppSearchRowState();
}

class _AppSearchRowState extends State<AppSearchRow> {
  late final TextEditingController _text =
      widget.controller ?? TextEditingController(text: widget.initial);
  late final FocusNode _focus = widget.focusNode ?? FocusNode();

  @override
  void initState() {
    super.initState();
    WidgetsBinding.instance.addPostFrameCallback((_) {
      if (mounted) _focus.requestFocus();
    });
  }

  @override
  void dispose() {
    if (widget.controller == null) _text.dispose();
    if (widget.focusNode == null) _focus.dispose();
    super.dispose();
  }

  @override
  Widget build(BuildContext context) {
    return Padding(
      padding: const EdgeInsetsDirectional.fromSTEB(0, 6, 4, 2),
      child: Row(
        children: [
          Expanded(
            child: AppSearchField(
              hint: widget.hint,
              controller: _text,
              focusNode: _focus,
              onChanged: widget.onChanged,
              margin: const EdgeInsetsDirectional.fromSTEB(16, 0, 2, 0),
            ),
          ),
          AppButton(
            label: 'common.cancel'.tr(),
            variant: AppButtonVariant.ghost,
            size: AppButtonSize.small,
            onPressed: widget.onCancel,
          ),
        ],
      ),
    );
  }
}
