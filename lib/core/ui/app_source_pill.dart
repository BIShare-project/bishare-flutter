import 'package:flutter/material.dart';

import 'app_format.dart';
import 'app_svg_icon.dart';

/// A premium compact tinted source button (icon + label) for the Home share
/// grid — mirrors native iOS's pickerPill with modern glass styling. Designed
/// for a 3-column grid.
class AppSourcePill extends StatefulWidget {
  const AppSourcePill({
    super.key,
    required this.icon,
    required this.label,
    required this.color,
    required this.onTap,
    this.onLongPress,
  });

  final String icon;
  final String label;
  final Color color;
  final VoidCallback onTap;
  final VoidCallback? onLongPress;

  @override
  State<AppSourcePill> createState() => _AppSourcePillState();
}

class _AppSourcePillState extends State<AppSourcePill>
    with SingleTickerProviderStateMixin {
  late AnimationController _controller;
  late Animation<double> _scale;

  @override
  void initState() {
    super.initState();
    _controller = AnimationController(
      vsync: this,
      duration: const Duration(milliseconds: 160),
    );
    _scale = Tween<double>(begin: 1.0, end: 0.94).animate(
      CurvedAnimation(parent: _controller, curve: Curves.easeOutCubic),
    );
  }

  @override
  void dispose() {
    _controller.dispose();
    super.dispose();
  }

  void _handleTapDown(TapDownDetails details) {
    _controller.forward();
  }

  void _handleTapUp(TapUpDetails details) {
    _controller.reverse();
  }

  void _handleTapCancel() {
    _controller.reverse();
  }

  @override
  Widget build(BuildContext context) {
    final isDark = Theme.of(context).brightness == Brightness.dark;

    return ScaleTransition(
      scale: _scale,
      child: GestureDetector(
        onTapDown: _handleTapDown,
        onTapUp: (details) {
          _handleTapUp(details);
          tapHaptic();
          widget.onTap();
        },
        onTapCancel: _handleTapCancel,
        onLongPress: widget.onLongPress == null
            ? null
            : () {
                tapHaptic();
                widget.onLongPress!();
              },
        child: Container(
          padding: const EdgeInsets.symmetric(vertical: 8, horizontal: 6),
          decoration: BoxDecoration(
            gradient: LinearGradient(
              begin: Alignment.topLeft,
              end: Alignment.bottomRight,
              colors: [
                widget.color.withValues(alpha: 0.13),
                widget.color.withValues(alpha: 0.08),
              ],
            ),
            borderRadius: BorderRadius.circular(11),
            border: Border.all(
              color: widget.color.withValues(alpha: 0.20),
              width: 0.8,
            ),
            boxShadow: [
              BoxShadow(
                color: widget.color.withValues(alpha: 0.10),
                blurRadius: 6,
                offset: const Offset(0, 2),
                spreadRadius: -2,
              ),
              BoxShadow(
                color: Colors.black.withValues(alpha: isDark ? 0.06 : 0.03),
                blurRadius: 4,
                offset: const Offset(0, 1),
              ),
            ],
          ),
          child: Row(
            mainAxisAlignment: MainAxisAlignment.center,
            children: [
              AppSvgIcon(widget.icon, size: 15, color: widget.color),
              const SizedBox(width: 6),
              Flexible(
                child: Text(
                  widget.label,
                  maxLines: 1,
                  overflow: TextOverflow.ellipsis,
                  style: TextStyle(
                    fontSize: 12,
                    fontWeight: FontWeight.w700,
                    color: widget.color,
                    letterSpacing: 0.1,
                    height: 1.1,
                  ),
                ),
              ),
            ],
          ),
        ),
      ),
    );
  }
}
