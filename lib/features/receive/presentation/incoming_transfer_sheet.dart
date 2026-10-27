import 'dart:convert';
import 'dart:typed_data';

import 'package:easy_localization/easy_localization.dart';
import 'package:flutter/material.dart';
import 'package:flutter_bloc/flutter_bloc.dart';

import '../../../core/server/transfer_types.dart';
import '../../../core/storage/app_database.dart';
import '../../../core/ui/app_ui.dart';
import '../../favorites/presentation/favorites_cubit.dart';

/// One file in an offer; [thumb] is the small JPEG a sender may include.
typedef OfferFile = ({String name, int size, String type, Uint8List? thumb});

/// Files with a thumbnail first, in their order, so the pictures are not
/// hidden behind "+n more".
List<OfferFile> _thumbsFirst(List<OfferFile> files) => [
  ...files.where((f) => f.thumb != null),
  ...files.where((f) => f.thumb == null),
];

Uint8List? _decodeThumb(String? b64) {
  if (b64 == null || b64.isEmpty) return null;
  try {
    return base64Decode(b64);
  } on FormatException {
    return null;
  }
}

/// What someone wants to send: from a device on the network, or from a
/// browser (Web Nearby). One sheet shows both (redesign-plan.md 4.1, 4.5).
class IncomingOffer {
  const IncomingOffer({
    required this.alias,
    required this.icon,
    required this.files,
    this.encrypted = false,
    this.keyChanged = false,
    this.fingerprint,
    this.decided,
  });

  /// A LAN transfer waiting in [TransferServer].
  factory IncomingOffer.fromPending(PendingTransfer p) => IncomingOffer(
    alias: p.sender.alias,
    icon: iconForDevice(p.sender.deviceType ?? 'mobile'),
    files: _thumbsFirst([
      for (final f in p.files.values)
        (
          name: f.fileName,
          size: f.size,
          type: f.fileType,
          thumb: _decodeThumb(f.preview),
        ),
    ]),
    encrypted: p.session.encrypted,
    keyChanged: p.keyChanged,
    fingerprint: p.sender.fingerprint,
    decided: p.decision.future,
  );

  final String alias;
  final String icon;
  final List<OfferFile> files;
  final bool encrypted;

  /// The device's key differs from the one trusted before.
  final bool keyChanged;

  /// Set for a LAN device: the sheet can turn on auto-accept for it.
  final String? fingerprint;

  /// Completes when the offer is settled elsewhere (the 30 s timeout), so the
  /// sheet closes instead of offering a dead Accept.
  final Future<void>? decided;

  int get totalBytes => files.fold(0, (s, f) => s + f.size);
}

/// Shows the offer; true if accepted. Closing it any other way declines.
Future<bool> showOffer(BuildContext context, IncomingOffer offer) async {
  final accepted = await showGlassModal<bool>(
    context,
    builder: (ctx) => ReceiveTone(child: _Offer(offer: offer)),
  );
  return accepted ?? false;
}

/// The LAN prompt: true if accepted.
Future<bool> showIncomingTransfer(
  BuildContext context,
  PendingTransfer pending,
) => showOffer(context, IncomingOffer.fromPending(pending));

class _Offer extends StatefulWidget {
  const _Offer({required this.offer});

  final IncomingOffer offer;

  @override
  State<_Offer> createState() => _OfferState();
}

class _OfferState extends State<_Offer> {
  bool _all = false;

  @override
  void initState() {
    super.initState();
    widget.offer.decided?.then((_) {
      if (!mounted) return;
      final route = ModalRoute.of(context);
      if (route != null && route.isCurrent) Navigator.of(context).pop();
    });
  }

  @override
  Widget build(BuildContext context) {
    final t = context.tokens;
    final o = widget.offer;
    final files = o.files;
    final shown = _all ? files : files.take(3).toList();
    final more = files.length - shown.length;
    final fp = o.fingerprint;
    return Column(
      mainAxisSize: MainAxisSize.min,
      crossAxisAlignment: CrossAxisAlignment.stretch,
      children: [
        Align(
          alignment: AlignmentDirectional.centerEnd,
          child: Padding(
            padding: const EdgeInsetsDirectional.only(end: 6),
            child: AppIconButton(
              icon: AppIcons.close,
              color: t.text2,
              tooltip: 'receive.decline'.tr(),
              onPressed: () => Navigator.pop(context, false),
            ),
          ),
        ),
        // The sheet scrolls as a whole when the list is long.
        Padding(
          padding: const EdgeInsets.symmetric(horizontal: 20),
          child: Column(
            mainAxisSize: MainAxisSize.min,
            crossAxisAlignment: CrossAxisAlignment.stretch,
            children: [
              Center(
                child: Container(
                  width: 72,
                  height: 72,
                  alignment: Alignment.center,
                  decoration: BoxDecoration(
                    shape: BoxShape.circle,
                    color: t.receiveSoft,
                  ),
                  child: AppSvgIcon(o.icon, size: 32, color: t.receive),
                ),
              ),
              const SizedBox(height: 12),
              Semantics(
                header: true,
                child: Text(
                  'receive.offer_title'.tr(namedArgs: {'alias': o.alias}),
                  textAlign: TextAlign.center,
                  maxLines: 2,
                  overflow: TextOverflow.ellipsis,
                  style: AppType.sheetTitle.copyWith(color: t.text),
                ),
              ),
              const SizedBox(height: 3),
              Text(
                'receive.n_files_size'.plural(
                  files.length,
                  namedArgs: {'size': formatBytes(o.totalBytes)},
                ),
                textAlign: TextAlign.center,
                style: AppType.body.copyWith(
                  color: t.text2,
                  fontFeatures: const [FontFeature.tabularFigures()],
                ),
              ),
              if (o.encrypted) ...[
                const SizedBox(height: 8),
                Row(
                  mainAxisAlignment: MainAxisAlignment.center,
                  children: [
                    AppSvgIcon(AppIcons.passwordLock, size: 16, color: t.ok),
                    const SizedBox(width: 6),
                    Text(
                      'receive.encrypted'.tr(),
                      style: AppType.small.copyWith(color: t.ok),
                    ),
                  ],
                ),
              ],
              const SizedBox(height: 14),
              for (var i = 0; i < shown.length; i++) ...[
                if (i > 0) const AppRowDivider(indent: 52),
                _FileRow(file: shown[i]),
              ],
              if (more > 0)
                Align(
                  alignment: AlignmentDirectional.centerStart,
                  child: AppButton(
                    label: 'receive.more_count'.tr(
                      namedArgs: {'count': '$more'},
                    ),
                    variant: AppButtonVariant.ghost,
                    size: AppButtonSize.small,
                    onPressed: () => setState(() => _all = true),
                  ),
                ),
              if (o.keyChanged) ...[
                const SizedBox(height: 12),
                Container(
                  padding: const EdgeInsets.all(12),
                  decoration: BoxDecoration(
                    color: t.warn.withValues(alpha: 0.12),
                    borderRadius: BorderRadius.circular(12),
                  ),
                  child: Row(
                    crossAxisAlignment: CrossAxisAlignment.start,
                    children: [
                      AppSvgIcon(AppIcons.circleAlert, size: 20, color: t.warn),
                      const SizedBox(width: 10),
                      Expanded(
                        child: Text(
                          'receive.key_changed_warning'.tr(),
                          style: AppType.secondary.copyWith(color: t.text),
                        ),
                      ),
                    ],
                  ),
                ),
              ],
              // Auto-accept only for a device whose key is still trusted:
              // the server would ignore it for a changed key anyway.
              if (fp != null && !o.keyChanged) ...[
                const SizedBox(height: 12),
                AppGroup(
                  card: true,
                  margin: EdgeInsets.zero,
                  child:
                      BlocSelector<
                        FavoritesCubit,
                        Map<String, FavoriteDevice>,
                        bool
                      >(
                        selector: (m) => m[fp]?.autoAccept ?? false,
                        builder: (context, on) => AppSwitchRow(
                          title: 'receive.auto_accept_from'.tr(
                            namedArgs: {'alias': o.alias},
                          ),
                          subtitle: 'receive.auto_accept_hint'.tr(),
                          value: on,
                          onChanged: (v) => context
                              .read<FavoritesCubit>()
                              .setAutoAcceptFingerprint(fp, v, name: o.alias),
                        ),
                      ),
                ),
              ],
            ],
          ),
        ),
        Padding(
          padding: const EdgeInsets.fromLTRB(20, 16, 20, 4),
          child: Row(
            children: [
              Expanded(
                child: AppButton(
                  label: 'receive.decline'.tr(),
                  variant: AppButtonVariant.secondary,
                  size: AppButtonSize.large,
                  onPressed: () => Navigator.pop(context, false),
                ),
              ),
              const SizedBox(width: 10),
              Expanded(
                child: AppButton(
                  label: 'receive.accept'.tr(),
                  size: AppButtonSize.large,
                  onPressed: () => Navigator.pop(context, true),
                ),
              ),
            ],
          ),
        ),
      ],
    );
  }
}

class _FileRow extends StatelessWidget {
  const _FileRow({required this.file});

  final OfferFile file;

  @override
  Widget build(BuildContext context) {
    final t = context.tokens;
    return Padding(
      padding: const EdgeInsets.symmetric(vertical: 8),
      child: Row(
        children: [
          ClipRRect(
            borderRadius: BorderRadius.circular(10),
            child: SizedBox.square(
              dimension: 40,
              child: file.thumb == null
                  ? ColoredBox(
                      color: t.sunken,
                      child: Center(
                        child: AppSvgIcon(
                          fileIcon(file.type),
                          size: 20,
                          color: t.text2,
                        ),
                      ),
                    )
                  : Image.memory(
                      file.thumb!,
                      fit: BoxFit.cover,
                      cacheWidth: (40 * MediaQuery.devicePixelRatioOf(context))
                          .round(),
                      gaplessPlayback: true,
                      errorBuilder: (_, _, _) => ColoredBox(color: t.sunken),
                    ),
            ),
          ),
          const SizedBox(width: 12),
          Expanded(
            child: Text(
              file.name,
              maxLines: 1,
              overflow: TextOverflow.ellipsis,
              style: AppType.row.copyWith(color: t.text),
            ),
          ),
          const SizedBox(width: 10),
          Text(
            formatBytes(file.size),
            style: AppType.secondary.copyWith(color: t.text2),
          ),
        ],
      ),
    );
  }
}
