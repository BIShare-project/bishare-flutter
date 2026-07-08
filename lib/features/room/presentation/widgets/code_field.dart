import 'package:flutter/material.dart';
import 'package:flutter/services.dart';
import 'package:shadcn_ui/shadcn_ui.dart';

/// Four large monospaced code boxes backed by a hidden input.
class CodeField extends StatefulWidget {
  const CodeField({
    super.key,
    required this.controller,
    required this.onComplete,
  });
  final TextEditingController controller;
  final ValueChanged<String> onComplete;

  @override
  State<CodeField> createState() => _CodeFieldState();
}

class _CodeFieldState extends State<CodeField> {
  final FocusNode _focus = FocusNode();

  @override
  void initState() {
    super.initState();
    WidgetsBinding.instance.addPostFrameCallback((_) => _focus.requestFocus());
  }

  @override
  void dispose() {
    _focus.dispose();
    super.dispose();
  }

  @override
  Widget build(BuildContext context) {
    final cs = ShadTheme.of(context).colorScheme;
    final code = widget.controller.text;
    return GestureDetector(
      onTap: () => _focus.requestFocus(),
      child: Stack(
        alignment: Alignment.center,
        children: [
          Row(
            mainAxisAlignment: MainAxisAlignment.center,
            children: List.generate(4, (i) {
              final filled = i < code.length;
              final active = i == code.length;
              return Container(
                width: 52,
                height: 60,
                margin: const EdgeInsets.symmetric(horizontal: 5),
                alignment: Alignment.center,
                decoration: BoxDecoration(
                  color: cs.muted.withValues(alpha: 0.4),
                  borderRadius: BorderRadius.circular(12),
                  border: Border.all(
                    color: active || filled
                        ? cs.primary
                        : cs.border.withValues(alpha: 0.8),
                    width: active ? 2 : 1,
                  ),
                ),
                child: Text(
                  filled ? code[i] : '',
                  style: TextStyle(
                    fontSize: 26,
                    fontWeight: FontWeight.w800,
                    color: cs.foreground,
                  ),
                ),
              );
            }),
          ),
          Opacity(
            opacity: 0,
            child: SizedBox(
              width: 240,
              child: TextField(
                controller: widget.controller,
                focusNode: _focus,
                autofocus: true,
                maxLength: 4,
                textCapitalization: TextCapitalization.characters,
                keyboardType: TextInputType.text,
                inputFormatters: [
                  UpperCaseFormatter(),
                  FilteringTextInputFormatter.allow(RegExp('[A-Z0-9]')),
                ],
                onChanged: (v) {
                  setState(() {});
                  if (v.length == 4) widget.onComplete(v);
                },
              ),
            ),
          ),
        ],
      ),
    );
  }
}

/// Uppercases input as it's typed.
class UpperCaseFormatter extends TextInputFormatter {
  @override
  TextEditingValue formatEditUpdate(
    TextEditingValue oldValue,
    TextEditingValue newValue,
  ) => newValue.copyWith(text: newValue.text.toUpperCase());
}
