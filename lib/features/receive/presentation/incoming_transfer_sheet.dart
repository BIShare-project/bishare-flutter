import 'package:easy_localization/easy_localization.dart';
import 'package:flutter/material.dart';
import 'package:shadcn_ui/shadcn_ui.dart';

import '../../../core/server/transfer_types.dart';
import '../../../core/ui/app_ui.dart';

/// A premium incoming-transfer prompt: sender avatar, the file manifest, an
/// encryption badge, and Accept/Decline. Adaptive glass dialog/sheet. Returns
/// true if accepted.
Future<bool> showIncomingTransfer(
  BuildContext context,
  PendingTransfer pending,
) async {
  final accepted = await showGlassModal<bool>(
    context,
    builder: (ctx) => _IncomingContent(pending: pending),
  );
  return accepted ?? false;
}

class _IncomingContent extends StatelessWidget {
  const _IncomingContent({required this.pending});
  final PendingTransfer pending;

  @override
  Widget build(BuildContext context) {
    final cs = ShadTheme.of(context).colorScheme;
    final files = pending.files.values.toList();
    final n = files.length;
    final encrypted = pending.session.encrypted;

    return Padding(
      padding: const EdgeInsets.fromLTRB(20, 20, 20, 16),
      child: Column(
        mainAxisSize: MainAxisSize.min,
        children: [
          Stack(
            clipBehavior: Clip.none,
            children: [
              AppAvatar(
                icon: iconForDevice(pending.sender.deviceType ?? 'mobile'),
                size: 66,
              ),
              Positioned(
                right: -4,
                bottom: -4,
                child: Container(
                  padding: const EdgeInsets.all(5),
                  decoration: BoxDecoration(
                    color: cs.primary,
                    shape: BoxShape.circle,
                    border: Border.all(color: cs.background, width: 2.5),
                  ),
                  child: AppSvgIcon(
                    AppIcons.downloadFile,
                    size: 14,
                    color: cs.primaryForeground,
                  ),
                ),
              ),
            ],
          ),
          const SizedBox(height: 14),
          Text(
            pending.sender.alias,
            maxLines: 1,
            overflow: TextOverflow.ellipsis,
            style: TextStyle(
              fontSize: 20,
              fontWeight: FontWeight.w700,
              color: cs.foreground,
            ),
          ),
          const SizedBox(height: 2),
          Text(
            'receive.wants_to_send'.tr(),
            style: TextStyle(fontSize: 14, color: cs.mutedForeground),
          ),
          // P0.5: warn when this device's security key differs from the one we
          // pinned — a replaced device, or a possible impersonator (MITM).
          if (pending.keyChanged) ...[
            const SizedBox(height: 14),
            Container(
              padding: const EdgeInsets.symmetric(horizontal: 12, vertical: 10),
              decoration: BoxDecoration(
                color: cs.destructive.withValues(alpha: 0.10),
                borderRadius: BorderRadius.circular(12),
                border: Border.all(color: cs.destructive.withValues(alpha: 0.35)),
              ),
              child: Row(
                crossAxisAlignment: CrossAxisAlignment.start,
                children: [
                  Icon(Icons.gpp_maybe_outlined, size: 18, color: cs.destructive),
                  const SizedBox(width: 8),
                  Expanded(
                    child: Text(
                      'receive.key_changed_warning'.tr(),
                      style: TextStyle(
                        fontSize: 12.5,
                        height: 1.35,
                        color: cs.destructive,
                      ),
                    ),
                  ),
                ],
              ),
            ),
          ],
          const SizedBox(height: 16),
          Container(
            constraints: const BoxConstraints(maxHeight: 210),
            decoration: BoxDecoration(
              color: cs.muted,
              borderRadius: BorderRadius.circular(16),
              border: Border.all(color: cs.border.withValues(alpha: 0.7)),
            ),
            child: ClipRRect(
              borderRadius: BorderRadius.circular(16),
              child: ListView.separated(
                shrinkWrap: true,
                padding: EdgeInsets.zero,
                physics: const ClampingScrollPhysics(),
                itemCount: n,
                separatorBuilder: (_, _) =>
                    Divider(height: 1, color: cs.border.withValues(alpha: 0.6)),
                itemBuilder: (context, i) {
                  final f = files[i];
                  return Padding(
                    padding: const EdgeInsets.symmetric(
                      horizontal: 12,
                      vertical: 10,
                    ),
                    child: Row(
                      children: [
                        AppSvgIcon(
                          fileIcon(f.fileType),
                          size: 20,
                          color: cs.mutedForeground,
                        ),
                        const SizedBox(width: 12),
                        Expanded(
                          child: Text(
                            f.fileName,
                            maxLines: 1,
                            overflow: TextOverflow.ellipsis,
                            style: TextStyle(
                              fontSize: 14,
                              fontWeight: FontWeight.w500,
                              color: cs.foreground,
                            ),
                          ),
                        ),
                        const SizedBox(width: 10),
                        Text(
                          formatBytes(f.size),
                          style: TextStyle(
                            fontSize: 12.5,
                            color: cs.mutedForeground,
                          ),
                        ),
                      ],
                    ),
                  );
                },
              ),
            ),
          ),
          const SizedBox(height: 12),
          Row(
            mainAxisAlignment: MainAxisAlignment.center,
            children: [
              Text(
                'receive.n_files_size'.plural(
                  n,
                  namedArgs: {'size': formatBytes(pending.totalBytes)},
                ),
                style: TextStyle(
                  fontSize: 13,
                  fontWeight: FontWeight.w600,
                  color: cs.mutedForeground,
                ),
              ),
              if (encrypted) ...[
                const SizedBox(width: 10),
                Row(
                  mainAxisSize: MainAxisSize.min,
                  children: [
                    const AppSvgIcon(
                      AppIcons.passwordLock,
                      size: 12,
                      color: kOnlineGreen,
                    ),
                    const SizedBox(width: 4),
                    Text(
                      'receive.encrypted'.tr(),
                      style: TextStyle(
                        fontSize: 12.5,
                        fontWeight: FontWeight.w600,
                        color: kOnlineGreen,
                      ),
                    ),
                  ],
                ),
              ],
            ],
          ),
          const SizedBox(height: 18),
          Row(
            children: [
              Expanded(
                child: ShadButton.outline(
                  size: ShadButtonSize.lg,
                  onPressed: () => Navigator.pop(context, false),
                  child: Text('receive.decline'.tr()),
                ),
              ),
              const SizedBox(width: 12),
              Expanded(
                child: ShadButton(
                  size: ShadButtonSize.lg,
                  onPressed: () => Navigator.pop(context, true),
                  leading: const AppSvgIcon(AppIcons.check, size: 18),
                  child: Text('receive.accept'.tr()),
                ),
              ),
            ],
          ),
        ],
      ),
    );
  }
}
