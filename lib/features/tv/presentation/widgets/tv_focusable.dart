import 'package:flutter/material.dart';

/// A D-pad-friendly focusable wrapper for TV. Arrow keys move focus between
/// siblings (Flutter's default directional traversal); the OK / center / Enter
/// button fires [onSelect] (mapped to [ActivateIntent] by the default TV
/// shortcuts). [builder] gets the current focus state so the child can render a
/// visible highlight — essential on a 10-foot UI with no cursor.
class TvFocusable extends StatefulWidget {
  const TvFocusable({
    super.key,
    required this.builder,
    required this.onSelect,
    this.autofocus = false,
  });

  final Widget Function(BuildContext context, bool focused) builder;
  final VoidCallback onSelect;
  final bool autofocus;

  @override
  State<TvFocusable> createState() => _TvFocusableState();
}

class _TvFocusableState extends State<TvFocusable> {
  bool _focused = false;

  @override
  Widget build(BuildContext context) {
    return FocusableActionDetector(
      autofocus: widget.autofocus,
      onShowFocusHighlight: (v) {
        if (v != _focused) setState(() => _focused = v);
      },
      actions: <Type, Action<Intent>>{
        ActivateIntent: CallbackAction<ActivateIntent>(
          onInvoke: (_) {
            widget.onSelect();
            return null;
          },
        ),
      },
      child: GestureDetector(
        onTap: widget.onSelect,
        child: widget.builder(context, _focused),
      ),
    );
  }
}
