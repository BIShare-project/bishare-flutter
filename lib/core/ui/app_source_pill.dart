import 'package:flutter/material.dart';

import 'app_format.dart';
import 'app_svg_icon.dart';

/// A compact tinted source button (icon + label) for the Home share grid —
/// mirrors native iOS's pickerPill. Designed for a 3-column grid.
class AppSourcePill extends StatelessWidget {
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
  Widget build(BuildContext context) {
    return Material(
      color: Colors.transparent,
      child: InkWell(
        onTap: () {
          tapHaptic();
          onTap();
        },
        onLongPress: onLongPress == null
            ? null
            : () {
                tapHaptic();
                onLongPress!();
              },
        borderRadius: BorderRadius.circular(12),
        child: Container(
          padding: const EdgeInsets.symmetric(vertical: 10, horizontal: 6),
          decoration: BoxDecoration(
            color: color.withValues(alpha: 0.12),
            borderRadius: BorderRadius.circular(10),
          ),
          child: Row(
            mainAxisAlignment: MainAxisAlignment.center,
            children: [
              AppSvgIcon(icon, size: 15, color: color),
              const SizedBox(width: 6),
              Flexible(
                child: Text(
                  label,
                  maxLines: 1,
                  overflow: TextOverflow.ellipsis,
                  style: TextStyle(
                    fontSize: 12.5,
                    fontWeight: FontWeight.w600,
                    color: color,
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
