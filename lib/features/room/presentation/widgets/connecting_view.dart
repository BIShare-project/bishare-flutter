import 'package:flutter/material.dart';
import 'package:shadcn_ui/shadcn_ui.dart';

/// The room "connecting" state: a spinner + a label with an animated ellipsis
/// (e.g. "Looking for a local room…") so the local-first search feels alive.
class ConnectingView extends StatefulWidget {
  const ConnectingView({super.key, required this.label});

  final String label;

  @override
  State<ConnectingView> createState() => _ConnectingViewState();
}

class _ConnectingViewState extends State<ConnectingView>
    with SingleTickerProviderStateMixin {
  late final AnimationController _controller = AnimationController(
    vsync: this,
    duration: const Duration(milliseconds: 1400),
  )..repeat();

  @override
  void dispose() {
    _controller.dispose();
    super.dispose();
  }

  @override
  Widget build(BuildContext context) {
    final cs = ShadTheme.of(context).colorScheme;
    return Center(
      child: Column(
        mainAxisSize: MainAxisSize.min,
        children: [
          SizedBox(
            width: 46,
            height: 46,
            child: CircularProgressIndicator(
              strokeWidth: 4,
              valueColor: AlwaysStoppedAnimation(cs.primary),
            ),
          ),
          const SizedBox(height: 20),
          AnimatedBuilder(
            animation: _controller,
            builder: (context, _) {
              final dots = '.' * (((_controller.value * 4).floor()) % 4);
              return Text(
                '${widget.label}$dots',
                style: TextStyle(
                  fontSize: 15,
                  fontWeight: FontWeight.w600,
                  color: cs.foreground,
                ),
              );
            },
          ),
        ],
      ),
    );
  }
}
