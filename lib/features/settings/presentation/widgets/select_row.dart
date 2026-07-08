import 'package:flutter/material.dart';
import 'package:shadcn_ui/shadcn_ui.dart';

import '../../../../core/ui/app_ui.dart';
import 'glyph.dart';

/// A settings row whose value is chosen from an inline [ShadSelect] popover.
class SelectRow<T> extends StatelessWidget {
  const SelectRow({super.key,
    required this.icon,
    required this.title,
    required this.value,
    required this.values,
    required this.label,
    required this.onChanged,
    this.description,
  });

  final String icon;
  final String title;
  final T value;
  final List<T> values;
  final String Function(T) label;
  final ValueChanged<T> onChanged;

  /// Optional one-line explanation shown under each option in the popover, so the
  /// user understands the choice while picking (e.g. what each Transport does).
  final String Function(T)? description;

  @override
  Widget build(BuildContext context) {
    final theme = ShadTheme.of(context);
    return AppListTile(
      leading: Glyph(icon),
      title: Text(title),
      trailing: ShadSelect<T>(
        // Re-key on external change so the control reflects the current value.
        key: ValueKey(value),
        initialValue: value,
        minWidth: 150,
        // Widen when options carry a description so the explanation wraps nicely.
        maxWidth: description != null ? 300 : 210,
        selectedOptionBuilder: (context, v) => Text(label(v)),
        options: [
          for (final o in values)
            ShadOption(
              value: o,
              child: description == null
                  ? Text(label(o))
                  : Column(
                      crossAxisAlignment: CrossAxisAlignment.start,
                      mainAxisSize: MainAxisSize.min,
                      children: [
                        Text(label(o)),
                        const SizedBox(height: 2),
                        Text(
                          description!(o),
                          style: theme.textTheme.muted.copyWith(fontSize: 12),
                        ),
                      ],
                    ),
            ),
        ],
        onChanged: (v) {
          if (v != null) onChanged(v);
        },
      ),
    );
  }
}
