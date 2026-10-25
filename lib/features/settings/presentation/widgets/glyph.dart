import 'package:flutter/widgets.dart';

import '../../../../core/ui/app_rows.dart';

/// A settings row glyph: the shared [AppGlyph].
class Glyph extends StatelessWidget {
  const Glyph(this.icon, {super.key});
  final String icon;

  @override
  Widget build(BuildContext context) => AppGlyph(icon);
}
