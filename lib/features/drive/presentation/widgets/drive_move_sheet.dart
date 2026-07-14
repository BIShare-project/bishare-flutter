import 'package:easy_localization/easy_localization.dart';
import 'package:flutter/material.dart';
import 'package:shadcn_ui/shadcn_ui.dart';

import '../../../../core/ui/app_ui.dart';
import '../../data/drive_service.dart';
import '../../domain/drive_models.dart';

/// A destination-folder picker: browse the folder tree and tap "Move here".
/// Returns the chosen folder id (never root — the contract has no move-to-root),
/// or null if cancelled. [excludeFolderId] hides the folder being moved so it
/// can't be dropped into itself.
Future<({String id})?> showDriveMoveSheet(
  BuildContext context, {
  required DriveService service,
  String? excludeFolderId,
}) {
  return showGlassModal<({String id})>(
    context,
    builder: (ctx) =>
        _MoveSheet(service: service, excludeFolderId: excludeFolderId),
  );
}

class _MoveSheet extends StatefulWidget {
  const _MoveSheet({required this.service, this.excludeFolderId});

  final DriveService service;
  final String? excludeFolderId;

  @override
  State<_MoveSheet> createState() => _MoveSheetState();
}

class _MoveSheetState extends State<_MoveSheet> {
  final List<DriveFolder> _stack = []; // current path (root when empty)
  List<DriveFolder> _folders = const [];
  bool _loading = true;

  DriveFolder? get _current => _stack.isEmpty ? null : _stack.last;

  @override
  void initState() {
    super.initState();
    _load();
  }

  Future<void> _load() async {
    setState(() => _loading = true);
    try {
      final list = await widget.service.folders(parentId: _current?.id);
      if (!mounted) return;
      setState(() {
        _folders = [
          for (final f in list)
            if (f.id != widget.excludeFolderId) f,
        ];
        _loading = false;
      });
    } on Object {
      if (mounted) setState(() => _loading = false);
    }
  }

  void _enter(DriveFolder f) {
    setState(() => _stack.add(f));
    _load();
  }

  void _up() {
    setState(() => _stack.removeLast());
    _load();
  }

  @override
  Widget build(BuildContext context) {
    final cs = ShadTheme.of(context).colorScheme;
    final canMoveHere = _current != null;
    return Padding(
      padding: const EdgeInsets.fromLTRB(16, 18, 16, 8),
      child: Column(
        mainAxisSize: MainAxisSize.min,
        crossAxisAlignment: CrossAxisAlignment.stretch,
        children: [
          Row(
            children: [
              if (_stack.isNotEmpty)
                AppIconOnlyButton(
                  icon: AppIcons.chevronLeft,
                  size: AppButtonSize.small,
                  onPressed: _up,
                ),
              Expanded(
                child: Text(
                  _current?.name ?? 'drive.move_to'.tr(),
                  maxLines: 1,
                  overflow: TextOverflow.ellipsis,
                  style: TextStyle(
                    fontSize: 17,
                    fontWeight: FontWeight.w700,
                    color: cs.foreground,
                  ),
                ),
              ),
            ],
          ),
          const SizedBox(height: 12),
          ConstrainedBox(
            constraints: const BoxConstraints(maxHeight: 320),
            child: _loading
                ? const Padding(
                    padding: EdgeInsets.symmetric(vertical: 40),
                    child: Center(child: CircularProgressIndicator()),
                  )
                : _folders.isEmpty
                ? Padding(
                    padding: const EdgeInsets.symmetric(vertical: 32),
                    child: Text(
                      'drive.no_subfolders'.tr(),
                      textAlign: TextAlign.center,
                      style: TextStyle(
                        fontSize: 13.5,
                        color: cs.mutedForeground,
                      ),
                    ),
                  )
                : SingleChildScrollView(
                    child: AppGroup(
                      margin: EdgeInsets.zero,
                      child: Column(
                        children: [
                          for (var i = 0; i < _folders.length; i++) ...[
                            if (i > 0) const AppRowDivider(indent: 62),
                            AppListTile(
                              leading: AppSvgIcon(
                                AppIcons.folder,
                                size: 30,
                                color: cs.primary,
                              ),
                              title: Text(
                                _folders[i].name,
                                maxLines: 1,
                                overflow: TextOverflow.ellipsis,
                              ),
                              trailing: AppSvgIcon(
                                AppIcons.chevronRight,
                                size: 18,
                                color: cs.mutedForeground.withValues(
                                  alpha: 0.6,
                                ),
                              ),
                              onTap: () => _enter(_folders[i]),
                            ),
                          ],
                        ],
                      ),
                    ),
                  ),
          ),
          const SizedBox(height: 14),
          AppButton(
            label: 'drive.move_here'.tr(),
            icon: AppIcons.moveFile,
            fullWidth: true,
            disabled: !canMoveHere,
            onPressed: canMoveHere
                ? () => Navigator.pop(context, (id: _current!.id))
                : null,
          ),
          const SizedBox(height: 4),
        ],
      ),
    );
  }
}
