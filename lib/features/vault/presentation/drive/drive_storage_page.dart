import 'dart:async';

import 'package:easy_localization/easy_localization.dart';
import 'package:flutter/material.dart';
import 'package:shadcn_ui/shadcn_ui.dart';

import '../../../../core/di/locator.dart';
import '../../../../core/storage/app_database.dart';
import '../../../../core/storage/vault_tables.dart';
import '../../../../core/ui/app_ui.dart';
import '../../data/vault_account.dart';
import 'drive_format.dart';
import 'drive_page.dart' show storageByKind;
import 'drive_widgets.dart';

/// What the Drive holds, by kind, against the plan's quota.
class DriveStoragePage extends StatefulWidget {
  const DriveStoragePage({super.key});

  @override
  State<DriveStoragePage> createState() => _DriveStoragePageState();
}

class _DriveStoragePageState extends State<DriveStoragePage> {
  final VaultAccount _account = getIt<VaultAccount>();
  final VaultDao _dao = getIt<AppDatabase>().vaultDao;
  late final Stream<List<VaultObject>> _live = _dao.watchLive();
  late final Stream<List<VaultObject>> _trash = _dao.watchTrash();

  @override
  void initState() {
    super.initState();
    unawaited(_account.refreshInfo().catchError((Object _) {}));
  }

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
                title: 'vault.storage'.tr(),
                onBack: () => Navigator.of(context).maybePop(),
              ),
              Expanded(
                child: StreamBuilder<List<VaultObject>>(
                  stream: _live,
                  builder: (context, live) => StreamBuilder<List<VaultObject>>(
                    stream: _trash,
                    builder: (context, trash) => ListenableBuilder(
                      listenable: _account,
                      builder: (context, _) {
                        final liveItems = live.data ?? const <VaultObject>[];
                        final by = storageByKind(
                          liveItems,
                          trash.data ?? const [],
                        );
                        final files = liveItems
                            .where((o) => o.kind == 'file')
                            .length;
                        final folders = liveItems.length - files;
                        return ListView(
                          padding: const EdgeInsets.only(top: 4, bottom: 28),
                          children: [
                            DriveStorageCard(
                              used: _account.usedBytes,
                              quota: _account.quotaBytes,
                              byKind: by,
                            ),
                            AppGroup(
                              child: Column(
                                children: [
                                  for (final k
                                      in DriveStorageCard.colors.keys) ...[
                                    if (k != DriveStorageCard.colors.keys.first)
                                      const AppRowDivider(indent: 46),
                                    AppListTile(
                                      leading: Container(
                                        width: 14,
                                        height: 14,
                                        margin: const EdgeInsets.symmetric(
                                          horizontal: 8,
                                        ),
                                        decoration: BoxDecoration(
                                          color: DriveStorageCard.colors[k],
                                          shape: BoxShape.circle,
                                        ),
                                      ),
                                      title: Text('vault.kind_$k'.tr()),
                                      trailing: Text(
                                        decimalBytes(by[k] ?? 0),
                                        style: TextStyle(
                                          color: cs.mutedForeground,
                                        ),
                                      ),
                                    ),
                                  ],
                                ],
                              ),
                            ),
                            Padding(
                              padding: const EdgeInsets.fromLTRB(28, 12, 28, 0),
                              child: Text(
                                'vault.storage_note'.tr(
                                  namedArgs: {
                                    'files': '$files',
                                    'folders': '$folders',
                                  },
                                ),
                                style: ShadTheme.of(
                                  context,
                                ).textTheme.muted.copyWith(fontSize: 12),
                              ),
                            ),
                          ],
                        );
                      },
                    ),
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
