import 'package:flutter/material.dart';
import 'package:flutter/services.dart';

import '../theme/app_tokens.dart';
import '../theme/app_type.dart';

/// A text input for sheets (a device name, a PIN): a 44 pt field on the
/// sunken colour, no border, an accent ring while focused, and an optional
/// [error] line under it.
class AppTextField extends StatelessWidget {
  const AppTextField({
    super.key,
    required this.controller,
    this.hint,
    this.error,
    this.autofocus = false,
    this.obscure = false,
    this.keyboardType,
    this.inputFormatters,
    this.maxLength,
    this.onChanged,
    this.onSubmitted,
    this.minLines,
    this.maxLines = 1,
    this.autocorrect = true,
    this.enableSuggestions = true,
    this.textCapitalization = TextCapitalization.none,
    this.style,
    this.textInputAction,
  });

  final TextEditingController controller;
  final String? hint;
  final String? error;
  final bool autofocus;
  final bool obscure;
  final TextInputType? keyboardType;
  final List<TextInputFormatter>? inputFormatters;
  final int? maxLength;
  final ValueChanged<String>? onChanged;
  final ValueChanged<String>? onSubmitted;
  final int? minLines;
  final int? maxLines;
  final bool autocorrect;
  final bool enableSuggestions;
  final TextCapitalization textCapitalization;

  /// Merged over the body style (a monospace phrase, a code).
  final TextStyle? style;
  final TextInputAction? textInputAction;

  @override
  Widget build(BuildContext context) {
    final t = context.tokens;
    OutlineInputBorder border(Color c, double w) => OutlineInputBorder(
      borderRadius: BorderRadius.circular(12),
      borderSide: w == 0 ? BorderSide.none : BorderSide(color: c, width: w),
    );
    return TextField(
      controller: controller,
      autofocus: autofocus,
      obscureText: obscure,
      keyboardType: keyboardType,
      inputFormatters: [
        ...?inputFormatters,
        if (maxLength != null) LengthLimitingTextInputFormatter(maxLength),
      ],
      onChanged: onChanged,
      onSubmitted: onSubmitted,
      cursorColor: t.accent,
      minLines: minLines,
      maxLines: obscure ? 1 : maxLines,
      autocorrect: autocorrect,
      enableSuggestions: enableSuggestions,
      textCapitalization: textCapitalization,
      textInputAction: textInputAction,
      style: AppType.body.copyWith(color: t.text).merge(style),
      decoration: InputDecoration(
        isDense: true,
        filled: true,
        fillColor: t.sunken,
        contentPadding: const EdgeInsets.symmetric(
          horizontal: 14,
          vertical: 12,
        ),
        hintText: hint,
        hintStyle: AppType.body.copyWith(color: t.text3),
        errorText: error,
        errorStyle: AppType.secondary.copyWith(fontSize: 13, color: t.danger),
        border: border(t.line, 0),
        enabledBorder: border(t.line, 0),
        focusedBorder: border(t.accent, 1.5),
        errorBorder: border(t.danger, 1.5),
        focusedErrorBorder: border(t.danger, 1.5),
      ),
    );
  }
}
