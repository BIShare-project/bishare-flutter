import 'package:flutter/material.dart';

import '../theme/app_tokens.dart';

/// The loading look for content that is on its way (a gallery, a list): one
/// soft band of light sweeps across [child], a skeleton of plain boxes. One
/// ShaderMask over the whole skeleton, not one per box, inside its own
/// repaint boundary. Still when the platform asks for reduced motion.
class AppShimmer extends StatefulWidget {
  const AppShimmer({super.key, required this.child});

  final Widget child;

  @override
  State<AppShimmer> createState() => _AppShimmerState();
}

class _AppShimmerState extends State<AppShimmer>
    with SingleTickerProviderStateMixin {
  late final AnimationController _sweep = AnimationController(
    vsync: this,
    duration: const Duration(milliseconds: 1400),
  );

  @override
  void didChangeDependencies() {
    super.didChangeDependencies();
    if (MediaQuery.disableAnimationsOf(context)) {
      _sweep.stop();
    } else if (!_sweep.isAnimating) {
      _sweep.repeat();
    }
  }

  @override
  void dispose() {
    _sweep.dispose();
    super.dispose();
  }

  @override
  Widget build(BuildContext context) {
    final t = context.tokens;
    final base = t.sunken;
    final light = Color.lerp(t.sunken, t.isDark ? t.line : t.surface, 0.9)!;
    return RepaintBoundary(
      child: AnimatedBuilder(
        animation: _sweep,
        child: widget.child,
        builder: (context, child) {
          // The band travels from beyond the start edge to beyond the end.
          final x = _sweep.value * 3 - 1;
          return ShaderMask(
            blendMode: BlendMode.srcATop,
            shaderCallback: (rect) => LinearGradient(
              begin: Alignment(x - 1, -0.3),
              end: Alignment(x + 1, 0.3),
              colors: [base, light, base],
              stops: const [0.35, 0.5, 0.65],
            ).createShader(rect),
            child: child,
          );
        },
      ),
    );
  }
}

/// A plain box for skeletons inside [AppShimmer].
class AppSkeletonBox extends StatelessWidget {
  const AppSkeletonBox({super.key, this.width, this.height, this.radius = 0});

  final double? width;
  final double? height;
  final double radius;

  @override
  Widget build(BuildContext context) => Container(
    width: width,
    height: height,
    decoration: BoxDecoration(
      color: context.tokens.sunken,
      borderRadius: BorderRadius.circular(radius),
    ),
  );
}
