import 'package:flutter/material.dart';
import 'package:shadcn_ui/shadcn_ui.dart';

/// The room "connecting" state: a spinner and the label (e.g. "Looking for a
/// local room"). The spinner is the only motion; the label no longer animates
/// an ellipsis, which rebuilt the text four times a second.
class ConnectingView extends StatelessWidget {
  const ConnectingView({super.key, required this.label});

  final String label;

  @override
  Widget build(BuildContext context) {
    final cs = ShadTheme.of(context).colorScheme;
    return Center(
      child: Column(
        mainAxisSize: MainAxisSize.min,
        children: [
          SizedBox(
            width: 40,
            height: 40,
            child: CircularProgressIndicator(
              strokeWidth: 3,
              valueColor: AlwaysStoppedAnimation(cs.primary),
            ),
          ),
          const SizedBox(height: 20),
          Text(
            '$label…',
            style: TextStyle(
              fontSize: 15,
              fontWeight: FontWeight.w600,
              color: cs.foreground,
            ),
          ),
        ],
      ),
    );
  }
}
