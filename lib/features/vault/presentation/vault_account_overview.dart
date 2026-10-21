import 'dart:async';
import 'dart:math';

import 'package:easy_localization/easy_localization.dart';
import 'package:flutter/material.dart';
import 'package:go_router/go_router.dart';
import 'package:shadcn_ui/shadcn_ui.dart';

import '../../../core/di/locator.dart';
import '../../../core/storage/app_database.dart';
import '../../../core/storage/vault_tables.dart';
import '../../../core/ui/app_ui.dart';
import '../../settings/presentation/widgets/glyph.dart';
import '../data/vault_account.dart';
import '../data/vault_photo_backup.dart';
import '../data/vault_upload_batch.dart';
import '../data/vault_uploader.dart';
import 'drive/drive_format.dart';
import 'drive/drive_page.dart' show storageByKind;
import 'drive/drive_widgets.dart';

/// The top of the Drive account page (owner 2026-10-21: "data harus lengkap
/// storage sisa dll dan ada progress juga"): what is stored against the
/// quota, by kind, what is left, the plan and where the files live; then
/// what is going up right now and how far photo backup has come.
class VaultAccountOverview extends StatefulWidget {
  const VaultAccountOverview({super.key, required this.account});

  final VaultAccount account;

  @override
  State<VaultAccountOverview> createState() => _VaultAccountOverviewState();
}

class _VaultAccountOverviewState extends State<VaultAccountOverview> {
  final VaultDao _dao = getIt<AppDatabase>().vaultDao;
  late final Stream<List<VaultObject>> _live = _dao.watchLive();
  late final Stream<List<VaultObject>> _trash = _dao.watchTrash();
  late final Stream<List<VaultTransfer>> _transfers = _dao.watchTransfers();

  /// Photo backup, on phones and tablets with a photo library.
  final VaultPhotoBackup? _backup = getIt.isRegistered<VaultPhotoBackup>()
      ? getIt<VaultPhotoBackup>()
      : null;

  final VaultUploader _uploader = getIt<VaultUploader>();
  final OneWayProgress _bar = OneWayProgress();

  VaultAccount get _account => widget.account;

  @override
  Widget build(BuildContext context) {
    return StreamBuilder<List<VaultObject>>(
      stream: _live,
      builder: (context, live) => StreamBuilder<List<VaultObject>>(
        stream: _trash,
        builder: (context, trash) => StreamBuilder<List<VaultTransfer>>(
          stream: _transfers,
          builder: (context, transfers) {
            final backup = _backup;
            return Column(
              crossAxisAlignment: CrossAxisAlignment.stretch,
              children: [
                AppSectionHeader('vault.storage'.tr()),
                _storage(
                  context,
                  live.data ?? const [],
                  trash.data ?? const [],
                ),
                AppSectionHeader('vault.activity'.tr()),
                AppGroup(
                  child: Column(
                    children: [
                      _uploads(context, transfers.data ?? const []),
                      if (backup != null && backup.available) ...[
                        const AppRowDivider(indent: 58),
                        ListenableBuilder(
                          listenable: backup,
                          builder: (context, _) => _photos(context, backup),
                        ),
                      ],
                    ],
                  ),
                ),
              ],
            );
          },
        ),
      ),
    );
  }

  // ---- storage -----------------------------------------------------------------

  Widget _storage(
    BuildContext context,
    List<VaultObject> live,
    List<VaultObject> trash,
  ) {
    final cs = ShadTheme.of(context).colorScheme;
    final muted = TextStyle(fontSize: 13, color: cs.mutedForeground);
    final byKind = storageByKind(live, trash);
    final quota = _account.quotaBytes;
    final used =
        _account.usedBytes ?? byKind.values.fold<int>(0, (a, b) => a + b);
    final files = live.where((o) => o.kind == 'file').length;
    final folders = live.length - files;
    final known = _account.infoLoaded && quota != null && quota > 0;
    final left = known ? max(0, quota - used) : null;
    final percent = known ? used * 100 / quota : null;
    final full = known && used >= quota;

    String percentText(double p) =>
        p > 0 && p < 1 ? '<1' : p.clamp(0, 100).round().toString();

    return AppGroup(
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.stretch,
        children: [
          Padding(
            padding: const EdgeInsets.fromLTRB(16, 16, 16, 14),
            child: Column(
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                Row(
                  crossAxisAlignment: CrossAxisAlignment.end,
                  children: [
                    Expanded(
                      child: Text.rich(
                        TextSpan(
                          children: [
                            TextSpan(
                              text: decimalBytes(used),
                              style: TextStyle(
                                fontSize: 24,
                                fontWeight: FontWeight.w800,
                                color: cs.foreground,
                              ),
                            ),
                            if (known)
                              TextSpan(
                                text: '  /  ${decimalBytes(quota)}',
                                style: muted.copyWith(fontSize: 14),
                              ),
                          ],
                        ),
                      ),
                    ),
                    if (percent != null)
                      Text(
                        'vault.storage_percent'.tr(
                          namedArgs: {'percent': percentText(percent)},
                        ),
                        style: muted.copyWith(
                          fontWeight: FontWeight.w600,
                          color: full ? cs.destructive : cs.mutedForeground,
                        ),
                      ),
                  ],
                ),
                const SizedBox(height: 12),
                DriveStorageBar(
                  used: _account.usedBytes,
                  quota: quota,
                  byKind: byKind,
                  height: 10,
                ),
                const SizedBox(height: 12),
                Wrap(
                  spacing: 14,
                  runSpacing: 6,
                  children: [
                    for (final k in DriveStorageCard.colors.keys)
                      if ((byKind[k] ?? 0) > 0)
                        Row(
                          mainAxisSize: MainAxisSize.min,
                          children: [
                            Container(
                              width: 9,
                              height: 9,
                              decoration: BoxDecoration(
                                color: DriveStorageCard.colors[k],
                                shape: BoxShape.circle,
                              ),
                            ),
                            const SizedBox(width: 6),
                            Text(
                              '${'vault.kind_$k'.tr()} · '
                              '${decimalBytes(byKind[k]!)}',
                              style: muted.copyWith(fontSize: 12),
                            ),
                          ],
                        ),
                  ],
                ),
                if (full) ...[
                  const SizedBox(height: 10),
                  Text(
                    'vault.storage_full'.tr(),
                    style: muted.copyWith(color: cs.destructive),
                  ),
                ],
              ],
            ),
          ),
          Divider(height: 1, color: cs.border),
          IntrinsicHeight(
            child: Row(
              children: [
                _Stat(
                  value: left == null ? '…' : decimalBytes(left),
                  label: 'vault.stat_left'.tr(),
                  strong: true,
                ),
                VerticalDivider(width: 1, color: cs.border),
                _Stat(value: '$files', label: 'vault.stat_files'.tr()),
                VerticalDivider(width: 1, color: cs.border),
                _Stat(value: '$folders', label: 'vault.stat_folders'.tr()),
                VerticalDivider(width: 1, color: cs.border),
                _Stat(
                  value: decimalBytes(byKind['trash'] ?? 0),
                  label: 'vault.kind_trash'.tr(),
                ),
              ],
            ),
          ),
          Divider(height: 1, color: cs.border),
          AppListTile(
            leading: const Glyph(AppIcons.starFavorite),
            title: Text('vault.plan'.tr()),
            trailing: Text(_planText(quota), style: muted),
          ),
          if (_account.region != null) ...[
            const AppRowDivider(indent: 58),
            AppListTile(
              leading: const Glyph(AppIcons.globePublic),
              title: Text('vault.region_title'.tr()),
              trailing: Text(
                'vault.region_${_account.region}'.tr(),
                style: muted,
              ),
            ),
          ],
          const AppRowDivider(indent: 58),
          AppListTile(
            leading: const Glyph(AppIcons.storageUsage),
            title: Text('vault.storage_details'.tr()),
            trailing: AppSvgIcon(
              AppIcons.chevronRight,
              size: 16,
              color: cs.mutedForeground,
            ),
            onTap: () => context.push('/drive-storage'),
          ),
        ],
      ),
    );
  }

  String _planText(int? quota) {
    if (!_account.infoLoaded || quota == null) return '…';
    final size = decimalBytes(quota);
    if ((_account.plan ?? 'free') == 'free') {
      return 'vault.plan_free_size'.tr(namedArgs: {'size': size});
    }
    final ends = _account.planEnds;
    if (ends == null) return size;
    return 'vault.plan_until'.tr(
      namedArgs: {
        'size': size,
        'date': DateFormat.yMMMd(context.locale.toLanguageTag()).format(ends),
      },
    );
  }

  // ---- activity ----------------------------------------------------------------

  Widget _uploads(BuildContext context, List<VaultTransfer> transfers) {
    final cs = ShadTheme.of(context).colorScheme;
    final muted = TextStyle(fontSize: 12.5, color: cs.mutedForeground);
    return ListenableBuilder(
      // The file being sent reports every few kilobytes.
      listenable: _uploader,
      builder: (context, _) {
        final batch = UploadBatch.of(transfers, _uploader);
        final bar = _bar.of(batch);
        final running = batch?.running ?? const <VaultTransfer>[];
        final stopped = batch?.stopped ?? 0;
        return AppListTile(
          leading: const Glyph(AppIcons.uploadFile),
          title: Text('vault.uploads'.tr()),
          subtitle: Column(
            crossAxisAlignment: CrossAxisAlignment.start,
            children: [
              Text(
                running.isEmpty
                    ? 'vault.uploads_idle'.tr()
                    : '${'vault.uploading_n'.plural(running.length)} · '
                          '${'vault.uploads_bytes'.tr(namedArgs: {'done': decimalBytes(batch!.bytesDone), 'total': decimalBytes(batch.bytes)})}',
                style: muted,
              ),
              if (running.isNotEmpty) ...[
                const SizedBox(height: 7),
                _Progress(value: bar),
                if (batch!.current != null) ...[
                  const SizedBox(height: 4),
                  Text(
                    batch.current!.name,
                    maxLines: 1,
                    overflow: TextOverflow.ellipsis,
                    style: muted.copyWith(fontSize: 11.5),
                  ),
                ],
              ],
              if (stopped > 0) ...[
                const SizedBox(height: 4),
                Text(
                  'vault.uploads_stopped'.plural(stopped),
                  style: muted.copyWith(color: cs.destructive),
                ),
              ],
            ],
          ),
          trailing: AppSvgIcon(
            AppIcons.chevronRight,
            size: 16,
            color: cs.mutedForeground,
          ),
          onTap: () => context.push('/drive-transfers'),
        );
      },
    );
  }

  Widget _photos(BuildContext context, VaultPhotoBackup backup) {
    final cs = ShadTheme.of(context).colorScheme;
    final muted = TextStyle(fontSize: 12.5, color: cs.mutedForeground);
    final left = backup.left;
    final total = backup.total;
    final String status;
    if (!backup.on) {
      status = 'vault.backup_off'.tr();
    } else if (backup.noRoom) {
      status = 'vault.backup_no_room'.tr();
    } else if (left == null) {
      status = 'vault.backup_counting'.tr();
    } else {
      status = 'vault.backup_left'.plural(left);
    }
    final progress = backup.on && left != null && total != null && total > 0
        ? (total - min(left, total)) / total
        : null;
    return AppListTile(
      leading: const Glyph(AppIcons.cloudSync),
      title: Text('vault.backup_title'.tr()),
      subtitle: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Text(status, style: muted),
          if (progress != null) ...[
            const SizedBox(height: 7),
            _Progress(value: progress),
            const SizedBox(height: 4),
            Text(
              'vault.backup_done_of'.tr(
                namedArgs: {
                  'done': '${total! - min(left!, total)}',
                  'total': '$total',
                },
              ),
              style: muted.copyWith(fontSize: 11.5),
            ),
          ],
        ],
      ),
      trailing: ShadSwitch(
        value: backup.on,
        onChanged: (v) async {
          final ok = await backup.setOn(v);
          if (!ok && context.mounted) {
            toast(
              context,
              'vault.backup_access_denied'.tr(),
              type: ToastType.error,
            );
          }
        },
      ),
    );
  }
}

class _Stat extends StatelessWidget {
  const _Stat({required this.value, required this.label, this.strong = false});

  final String value;
  final String label;
  final bool strong;

  @override
  Widget build(BuildContext context) {
    final cs = ShadTheme.of(context).colorScheme;
    return Expanded(
      child: Padding(
        padding: const EdgeInsets.symmetric(vertical: 12, horizontal: 6),
        child: Column(
          children: [
            Text(
              value,
              maxLines: 1,
              overflow: TextOverflow.ellipsis,
              style: TextStyle(
                fontSize: 14.5,
                fontWeight: FontWeight.w700,
                color: strong ? cs.primary : cs.foreground,
              ),
            ),
            const SizedBox(height: 2),
            Text(
              label,
              maxLines: 1,
              overflow: TextOverflow.ellipsis,
              style: TextStyle(fontSize: 11.5, color: cs.mutedForeground),
            ),
          ],
        ),
      ),
    );
  }
}

class _Progress extends StatelessWidget {
  const _Progress({required this.value});

  /// Null while the size is not known yet.
  final double? value;

  @override
  Widget build(BuildContext context) {
    final cs = ShadTheme.of(context).colorScheme;
    return ClipRRect(
      borderRadius: BorderRadius.circular(3),
      child: LinearProgressIndicator(
        value: value,
        minHeight: 6,
        backgroundColor: cs.muted,
        color: cs.primary,
      ),
    );
  }
}
