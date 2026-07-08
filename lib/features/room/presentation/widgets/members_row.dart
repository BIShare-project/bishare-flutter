import 'package:flutter/material.dart';
import 'package:shadcn_ui/shadcn_ui.dart';

import '../../../../core/ui/app_ui.dart';
import '../../domain/room_models.dart';

class MembersRow extends StatelessWidget {
  const MembersRow({super.key, required this.members});
  final List<RoomMember> members;

  @override
  Widget build(BuildContext context) {
    if (members.isEmpty) return const SizedBox.shrink();
    return SizedBox(
      height: 74,
      child: ListView.separated(
        scrollDirection: Axis.horizontal,
        itemCount: members.length,
        separatorBuilder: (_, _) => const SizedBox(width: 14),
        itemBuilder: (context, i) => MemberAvatar(member: members[i]),
      ),
    );
  }
}

class MemberAvatar extends StatelessWidget {
  const MemberAvatar({super.key, required this.member});
  final RoomMember member;

  @override
  Widget build(BuildContext context) {
    final cs = ShadTheme.of(context).colorScheme;
    return SizedBox(
      width: 60,
      child: Column(
        children: [
          Container(
            width: 46,
            height: 46,
            decoration: BoxDecoration(
              color: cs.primary.withValues(alpha: 0.85),
              shape: BoxShape.circle,
            ),
            child: AppSvgIcon(
              iconForDevice(member.deviceType),
              size: 20,
              color: cs.primaryForeground,
            ),
          ),
          const SizedBox(height: 5),
          Text(
            member.alias,
            maxLines: 1,
            overflow: TextOverflow.ellipsis,
            style: TextStyle(
              fontSize: 11.5,
              fontWeight: FontWeight.w500,
              color: cs.foreground,
            ),
          ),
        ],
      ),
    );
  }
}
