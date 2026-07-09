import 'package:easy_localization/easy_localization.dart';
import 'package:flutter/material.dart';
import 'package:flutter_bloc/flutter_bloc.dart';
import 'package:shadcn_ui/shadcn_ui.dart';

import '../../../../core/ui/app_ui.dart';
import '../room_cubit.dart';
import 'how_it_works.dart';
import 'join_sheet.dart';

class Lobby extends StatelessWidget {
  const Lobby({super.key, required this.state});
  final RoomState state;

  @override
  Widget build(BuildContext context) {
    final cs = ShadTheme.of(context).colorScheme;
    return SingleChildScrollView(
      padding: const EdgeInsets.fromLTRB(24, 24, 24, 24),
      child: Column(
        children: [
          const AppResponsivePane(maxWidth: 480, child: SizedBox.shrink()),
          Container(
            width: 92,
            height: 92,
            decoration: BoxDecoration(
              gradient: LinearGradient(
                begin: Alignment.topLeft,
                end: Alignment.bottomRight,
                colors: [
                  cs.primary,
                  Color.lerp(cs.primary, Colors.black, 0.22)!,
                ],
              ),
              shape: BoxShape.circle,
              boxShadow: [
                BoxShadow(
                  color: cs.primary.withValues(alpha: 0.35),
                  blurRadius: 24,
                  offset: const Offset(0, 10),
                ),
              ],
            ),
            child: AppSvgIcon(
              AppIcons.teamGroup,
              size: 38,
              color: cs.primaryForeground,
            ),
          ),
          const SizedBox(height: 20),
          Text(
            'room.title'.tr(),
            style: TextStyle(
              fontSize: 22,
              fontWeight: FontWeight.w800,
              letterSpacing: -0.3,
              color: cs.foreground,
            ),
          ),
          const SizedBox(height: 8),
          Text(
            'room.subtitle'.tr(),
            textAlign: TextAlign.center,
            style: TextStyle(
              fontSize: 14,
              height: 1.35,
              color: cs.mutedForeground,
            ),
          ),
          const SizedBox(height: 28),
          // Primary action buttons in 2x2 grid
          Row(
            children: [
              Expanded(
                child: _CompactActionCard(
                  icon: AppIcons.wifi,
                  label: 'room.local_room'.tr(),
                  description: 'room.local_desc'.tr(),
                  color: cs.primary,
                  onPressed: () =>
                      context.read<RoomCubit>().createRoom(local: true),
                ),
              ),
              const SizedBox(width: 10),
              Expanded(
                child: _CompactActionCard(
                  icon: AppIcons.globePublic,
                  label: 'room.remote_room'.tr(),
                  description: 'room.remote_desc'.tr(),
                  color: cs.primary,
                  onPressed: () =>
                      context.read<RoomCubit>().createRoom(local: false),
                ),
              ),
            ],
          ),
          const SizedBox(height: 10),
          // Join button with outline style (full width)
          AppButton(
            label: 'room.join_with_code'.tr(),
            icon: AppIcons.logIn,
            variant: AppButtonVariant.outline,
            size: AppButtonSize.medium,
            fullWidth: true,
            onPressed: () => _showJoin(context),
          ),
          const SizedBox(height: 28),
          HowItWorks(),
        ],
      ),
    );
  }

  void _showJoin(BuildContext context) {
    final cubit = context.read<RoomCubit>();
    showGlassModal<void>(
      context,
      builder: (ctx) => JoinSheet(
        onJoin: (code) {
          Navigator.pop(ctx);
          cubit.joinRoom(code);
        },
      ),
    );
  }
}

/// Premium compact action card with gradient and icon.
class _CompactActionCard extends StatefulWidget {
  const _CompactActionCard({
    required this.icon,
    required this.label,
    required this.description,
    required this.color,
    required this.onPressed,
  });

  final String icon;
  final String label;
  final String description;
  final Color color;
  final VoidCallback onPressed;

  @override
  State<_CompactActionCard> createState() => _CompactActionCardState();
}

class _CompactActionCardState extends State<_CompactActionCard>
    with SingleTickerProviderStateMixin {
  late AnimationController _controller;
  late Animation<double> _scale;

  @override
  void initState() {
    super.initState();
    _controller = AnimationController(
      vsync: this,
      duration: const Duration(milliseconds: 150),
    );
    _scale = Tween<double>(begin: 1.0, end: 0.97).animate(
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
    final cs = ShadTheme.of(context).colorScheme;
    final isDark = Theme.of(context).brightness == Brightness.dark;

    return ScaleTransition(
      scale: _scale,
      child: GestureDetector(
        onTapDown: _handleTapDown,
        onTapUp: (details) {
          _handleTapUp(details);
          tapHaptic();
          widget.onPressed();
        },
        onTapCancel: _handleTapCancel,
        child: Container(
          height: 56,
          decoration: BoxDecoration(
            borderRadius: BorderRadius.circular(14),
            gradient: LinearGradient(
              begin: Alignment(-1.0, -0.5),
              end: Alignment(1.0, 0.5),
              colors: [
                widget.color.withValues(alpha: 0.92),
                widget.color.withValues(alpha: 0.86),
              ],
            ),
            boxShadow: [
              BoxShadow(
                color: widget.color.withValues(alpha: 0.28),
                blurRadius: 20,
                offset: const Offset(0, 8),
                spreadRadius: -4,
              ),
              BoxShadow(
                color: Colors.black.withValues(alpha: isDark ? 0.12 : 0.06),
                blurRadius: 12,
                offset: const Offset(0, 4),
              ),
            ],
          ),
          child: ClipRRect(
            borderRadius: BorderRadius.circular(14),
            child: Stack(
              children: [
                // Glass shine effect
                Positioned(
                  top: -40,
                  right: -40,
                  child: Container(
                    width: 120,
                    height: 120,
                    decoration: BoxDecoration(
                      shape: BoxShape.circle,
                      gradient: RadialGradient(
                        colors: [
                          cs.background.withValues(alpha: 0.18),
                          cs.background.withValues(alpha: 0),
                        ],
                      ),
                    ),
                  ),
                ),
                // Content
                Padding(
                  padding: const EdgeInsets.symmetric(horizontal: 14),
                  child: Row(
                    children: [
                      // Icon container
                      Container(
                        width: 36,
                        height: 36,
                        decoration: BoxDecoration(
                          color: cs.background.withValues(alpha: 0.20),
                          borderRadius: BorderRadius.circular(10),
                        ),
                        child: Center(
                          child: AppSvgIcon(
                            widget.icon,
                            size: 18,
                            color: cs.primaryForeground,
                          ),
                        ),
                      ),
                      const SizedBox(width: 12),
                      // Text content
                      Expanded(
                        child: Column(
                          mainAxisAlignment: MainAxisAlignment.center,
                          crossAxisAlignment: CrossAxisAlignment.start,
                          children: [
                            Text(
                              widget.label,
                              style: TextStyle(
                                fontSize: 14,
                                fontWeight: FontWeight.w700,
                                color: cs.primaryForeground,
                                letterSpacing: 0.1,
                                height: 1.2,
                              ),
                              maxLines: 1,
                              overflow: TextOverflow.ellipsis,
                            ),
                            const SizedBox(height: 1),
                            Text(
                              widget.description,
                              style: TextStyle(
                                fontSize: 11,
                                fontWeight: FontWeight.w500,
                                color: cs.primaryForeground
                                    .withValues(alpha: 0.80),
                                height: 1.2,
                              ),
                              maxLines: 1,
                              overflow: TextOverflow.ellipsis,
                            ),
                          ],
                        ),
                      ),
                      // Arrow indicator
                      AppSvgIcon(
                        AppIcons.chevronRight,
                        size: 16,
                        color: cs.primaryForeground.withValues(alpha: 0.7),
                      ),
                    ],
                  ),
                ),
                // Subtle inner border
                Positioned.fill(
                  child: Container(
                    decoration: BoxDecoration(
                      borderRadius: BorderRadius.circular(14),
                      border: Border.all(
                        color: cs.background.withValues(alpha: 0.25),
                        width: 1.5,
                      ),
                    ),
                  ),
                ),
              ],
            ),
          ),
        ),
      ),
    );
  }
}
