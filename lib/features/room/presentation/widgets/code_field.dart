import 'package:flutter/material.dart';

import '../../../../core/ui/app_code_boxes.dart';

/// The four room-code boxes: the shared [AppCodeBoxes].
class CodeField extends StatelessWidget {
  const CodeField({
    super.key,
    required this.controller,
    required this.onComplete,
  });
  final TextEditingController controller;
  final ValueChanged<String> onComplete;

  @override
  Widget build(BuildContext context) =>
      AppCodeBoxes(controller: controller, length: 4, onComplete: onComplete);
}
