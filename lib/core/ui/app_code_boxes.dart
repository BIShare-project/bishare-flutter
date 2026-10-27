import 'package:flutter/material.dart';
import 'package:flutter/services.dart';

import '../theme/app_tokens.dart';
import '../theme/app_type.dart';

/// Letter-and-digit code boxes over one hidden input, so typing, deleting and
/// pasting a whole code all work. Used for a room code (4), a transfer code
/// (6) and a Drive browser code (8). Always left to right, even in Arabic: a
/// Latin code must not read reversed.
class AppCodeBoxes extends StatefulWidget {
  const AppCodeBoxes({
    super.key,
    required this.controller,
    required this.length,
    this.maxLength,
    this.onComplete,
    this.onSubmitted,
    this.autofocus = true,
    this.error = false,
  });

  final TextEditingController controller;
  final int length;

  /// A longer code that is still accepted (a live-transfer code falls back
  /// to 8 when 6 collide): the extra boxes appear once typing passes
  /// [length]. [onComplete] then never fires; submit with a button.
  final int? maxLength;

  /// Called once the last box is filled.
  final ValueChanged<String>? onComplete;

  /// Called on the keyboard's done key.
  final ValueChanged<String>? onSubmitted;
  final bool autofocus;

  /// Draws every box in the danger colour (a wrong code).
  final bool error;

  @override
  State<AppCodeBoxes> createState() => _AppCodeBoxesState();
}

class _AppCodeBoxesState extends State<AppCodeBoxes> {
  final FocusNode _focus = FocusNode();

  @override
  void initState() {
    super.initState();
    widget.controller.addListener(_changed);
    _focus.addListener(_changed);
    if (widget.autofocus) {
      WidgetsBinding.instance.addPostFrameCallback((_) {
        if (mounted) _focus.requestFocus();
      });
    }
  }

  void _changed() {
    if (mounted) setState(() {});
  }

  @override
  void dispose() {
    widget.controller.removeListener(_changed);
    _focus.dispose();
    super.dispose();
  }

  @override
  Widget build(BuildContext context) {
    final t = context.tokens;
    final code = widget.controller.text;
    final focused = _focus.hasFocus;
    final max = widget.maxLength ?? widget.length;
    final count = code.length > widget.length ? max : widget.length;
    final box = count > 6 ? 36.0 : 46.0;
    return Directionality(
      textDirection: TextDirection.ltr,
      child: GestureDetector(
        onTap: _focus.requestFocus,
        child: Stack(
          alignment: Alignment.center,
          children: [
            Row(
              mainAxisSize: MainAxisSize.min,
              children: List.generate(count, (i) {
                final filled = i < code.length;
                final active = focused && i == code.length.clamp(0, count - 1);
                final border = widget.error
                    ? t.danger
                    : active
                    ? t.accent
                    : filled
                    ? t.text3
                    : t.line;
                return Container(
                  width: box,
                  height: box + 8,
                  margin: EdgeInsets.symmetric(horizontal: count > 6 ? 3 : 4),
                  alignment: Alignment.center,
                  decoration: BoxDecoration(
                    color: t.surface,
                    borderRadius: BorderRadius.circular(12),
                    border: Border.all(color: border, width: active ? 2 : 1),
                  ),
                  child: Text(
                    filled ? code[i] : '•',
                    style: AppType.sheetTitle.copyWith(
                      fontSize: count > 6 ? 18 : 21,
                      color: filled ? t.text : t.text3.withValues(alpha: 0.6),
                      fontFeatures: const [FontFeature.tabularFigures()],
                    ),
                  ),
                );
              }),
            ),
            // The real input: invisible, on top, taking the whole row.
            Positioned.fill(
              child: Opacity(
                opacity: 0,
                child: TextField(
                  controller: widget.controller,
                  focusNode: _focus,
                  maxLength: max,
                  showCursor: false,
                  enableInteractiveSelection: false,
                  autocorrect: false,
                  enableSuggestions: false,
                  textCapitalization: TextCapitalization.characters,
                  keyboardType: TextInputType.visiblePassword,
                  textInputAction: TextInputAction.done,
                  inputFormatters: [
                    _UpperCase(),
                    FilteringTextInputFormatter.allow(RegExp('[A-Z0-9]')),
                  ],
                  decoration: const InputDecoration(
                    counterText: '',
                    border: InputBorder.none,
                  ),
                  onChanged: (v) {
                    if (widget.maxLength == null && v.length == widget.length) {
                      widget.onComplete?.call(v);
                    }
                  },
                  onSubmitted: widget.onSubmitted,
                ),
              ),
            ),
          ],
        ),
      ),
    );
  }
}

class _UpperCase extends TextInputFormatter {
  @override
  TextEditingValue formatEditUpdate(
    TextEditingValue oldValue,
    TextEditingValue newValue,
  ) => newValue.copyWith(text: newValue.text.toUpperCase());
}
