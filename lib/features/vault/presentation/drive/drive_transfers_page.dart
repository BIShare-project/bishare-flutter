import 'package:easy_localization/easy_localization.dart';
import 'package:flutter/material.dart';
import 'package:shadcn_ui/shadcn_ui.dart';

import '../../../../core/di/locator.dart';
import '../../../../core/storage/app_database.dart';
import '../../../../core/ui/app_ui.dart';
import '../../../settings/presentation/widgets/glyph.dart';
import '../../data/vault_downloads.dart';
import '../../data/vault_uploader.dart';
import 'drive_format.dart';

/// Uploads and downloads of the Drive, with progress, retry and cancel.
class DriveTransfersPage extends StatefulWidget {
  const DriveTransfersPage({super.key});

  @override
  State<DriveTransfersPage> createState() => _DriveTransfersPageState();
}

class _DriveTransfersPageState extends State<DriveTransfersPage> {
  final dao = getIt<AppDatabase>().vaultDao;
  final uploader = getIt<VaultUploader>();
  final downloads = getIt<VaultDownloads>();
  late final Stream<List<VaultTransfer>> _transfers = dao.watchTransfers();

  @override
  Widget build(BuildContext context) {
    final cs = ShadTheme.of(context).colorScheme;
    return Scaffold(
      backgroundColor: cs.background,
      body: SafeArea(
        child: AppResponsivePane(
          maxWidth: 720,
          child: Column(
            children: [
              AppScreenHeader(
                title: 'vault.transfers'.tr(),
                onBack: () => Navigator.of(context).maybePop(),
                actions: [
                  AppIconButton(
                    icon: AppIcons.trashDelete,
                    onPressed: () async {
                      await dao.clearFinishedTransfers();
                      downloads.clearFinished();
                    },
                  ),
                ],
              ),
              Expanded(
                child: StreamBuilder<List<VaultTransfer>>(
                  stream: _transfers,
                  builder: (context, snap) => ListenableBuilder(
                    listenable: Listenable.merge([uploader, downloads]),
                    builder: (context, _) {
                      final ups = [
                        for (final t in snap.data ?? const <VaultTransfer>[])
                          if (t.direction == 'up' && t.state != 'cancelled') t,
                      ];
                      final downs = downloads.jobs;
                      if (ups.isEmpty && downs.isEmpty) {
                        return AppEmptyState(
                          icon: AppIcons.transferP2p,
                          title: 'vault.transfers_empty'.tr(),
                          message: 'vault.transfers_empty_body'.tr(),
                        );
                      }
                      return ListView(
                        padding: const EdgeInsets.only(top: 4, bottom: 28),
                        children: [
                          if (ups.isNotEmpty) ...[
                            AppSectionHeader('vault.uploads'.tr()),
                            AppGroup(
                              child: Column(
                                children: [
                                  for (var i = 0; i < ups.length; i++) ...[
                                    if (i > 0) const AppRowDivider(indent: 58),
                                    _UploadRow(t: ups[i], uploader: uploader),
                                  ],
                                ],
                              ),
                            ),
                          ],
                          if (downs.isNotEmpty) ...[
                            AppSectionHeader('vault.downloads'.tr()),
                            AppGroup(
                              child: Column(
                                children: [
                                  for (var i = 0; i < downs.length; i++) ...[
                                    if (i > 0) const AppRowDivider(indent: 58),
                                    _DownloadRow(
                                      job: downs[i],
                                      downloads: downloads,
                                    ),
                                  ],
                                ],
                              ),
                            ),
                          ],
                        ],
                      );
                    },
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

class _UploadRow extends StatelessWidget {
  const _UploadRow({required this.t, required this.uploader});

  final VaultTransfer t;
  final VaultUploader uploader;

  @override
  Widget build(BuildContext context) {
    final cs = ShadTheme.of(context).colorScheme;
    final p = uploader.progressOf(t.id);
    final failed = t.state == 'failed';
    final done = t.state == 'done';
    final status = done
        ? 'vault.uploaded'.tr()
        : failed
        ? switch (t.error) {
            'STORAGE_LIMIT_EXCEEDED' => 'vault.error_full'.tr(),
            'MISSING' => 'vault.error_missing'.tr(),
            'VAULT_READ_ONLY' => 'vault.error_read_only'.tr(),
            _ => 'vault.upload_failed'.tr(),
          }
        : t.error == 'NETWORK'
        ? 'vault.waiting_network'.tr()
        : switch (t.state) {
            'sealing' => 'vault.sealing'.tr(),
            'sending' || 'finishing' => 'vault.sending'.tr(),
            _ => 'vault.queued'.tr(),
          };
    final fraction = p != null && p.total > 0 ? p.done / p.total : null;
    return AppListTile(
      leading: const Glyph(AppIcons.uploadFile),
      title: Text(t.name, maxLines: 1, overflow: TextOverflow.ellipsis),
      subtitle: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Text(
            done || failed ? status : '$status · ${decimalBytes(t.size)}',
            style: TextStyle(color: failed ? cs.destructive : null),
          ),
          if (!done && !failed && p != null)
            Padding(
              padding: const EdgeInsets.only(top: 6),
              child: LinearProgressIndicator(value: fraction, minHeight: 3),
            ),
        ],
      ),
      trailing: done
          ? null
          : Row(
              mainAxisSize: MainAxisSize.min,
              children: [
                // Stopped for good, or waiting for the connection: try now.
                if (failed || t.error == 'NETWORK')
                  IconButton(
                    tooltip: 'vault.retry'.tr(),
                    onPressed: () => uploader.retry(t.id),
                    icon: AppSvgIcon(
                      AppIcons.refreshSync,
                      size: 18,
                      color: cs.primary,
                    ),
                  ),
                IconButton(
                  tooltip: 'vault.cancel'.tr(),
                  onPressed: () => uploader.cancel(t.id),
                  icon: AppSvgIcon(
                    AppIcons.close,
                    size: 16,
                    color: cs.mutedForeground,
                  ),
                ),
              ],
            ),
    );
  }
}

class _DownloadRow extends StatelessWidget {
  const _DownloadRow({required this.job, required this.downloads});

  final VaultDownloadJob job;
  final VaultDownloads downloads;

  @override
  Widget build(BuildContext context) {
    final cs = ShadTheme.of(context).colorScheme;
    final status = switch (job.state) {
      VaultJobState.running =>
        job.isFolder
            ? 'vault.files_of'.tr(
                namedArgs: {
                  'done': '${job.filesDone}',
                  'total': '${job.filesTotal}',
                },
              )
            : 'vault.downloading'.tr(),
      VaultJobState.done => 'vault.downloaded'.tr(),
      VaultJobState.failed => 'vault.download_failed'.tr(),
      VaultJobState.cancelled => 'vault.cancelled'.tr(),
    };
    return AppListTile(
      leading: Glyph(job.isFolder ? AppIcons.folder : AppIcons.downloadFile),
      title: Text(job.name, maxLines: 1, overflow: TextOverflow.ellipsis),
      subtitle: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Text(
            status,
            style: TextStyle(
              color: job.state == VaultJobState.failed ? cs.destructive : null,
            ),
          ),
          if (job.state == VaultJobState.running)
            Padding(
              padding: const EdgeInsets.only(top: 6),
              child: LinearProgressIndicator(value: job.fraction, minHeight: 3),
            ),
        ],
      ),
      trailing: job.state == VaultJobState.running
          ? IconButton(
              tooltip: 'vault.cancel'.tr(),
              onPressed: () => downloads.cancel(job),
              icon: AppSvgIcon(
                AppIcons.close,
                size: 16,
                color: cs.mutedForeground,
              ),
            )
          : null,
    );
  }
}
