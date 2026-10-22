import 'dart:async';

import 'package:easy_localization/easy_localization.dart';
import 'package:flutter/material.dart';
import 'package:shadcn_ui/shadcn_ui.dart';

import '../../../core/di/locator.dart';
import '../../../core/ui/app_ui.dart';
import '../data/vault_account.dart';
import '../data/vault_api.dart';

/// Windows and Linux open the Drive without a sign-in of their own (owner,
/// 2026-10-22): this computer shows a code, and BIShare on a phone, tablet
/// or Mac of the Drive approves it, as it approves a browser. The sheet looks
/// every two seconds and closes once the computer holds the key; a code
/// lives five minutes and is renewed on a tap.
Future<void> showVaultDesktopPairing(BuildContext context) async {
  final connected = await showAppSheet<bool>(
    context,
    icon: AppIcons.qrShare,
    title: 'vault.pair_title'.tr(),
    subtitle: 'vault.pair_body'.tr(
      namedArgs: {'manage': 'vault.manage'.tr(), 'open': 'vault.web_open'.tr()},
    ),
    builder: (ctx) => const VaultDesktopPairingPanel(),
  );
  if (connected == true && context.mounted) {
    toast(context, 'vault.pair_done'.tr(), type: ToastType.success);
  }
}

/// The code and its state: the sheet's body (and the screenshots').
class VaultDesktopPairingPanel extends StatefulWidget {
  const VaultDesktopPairingPanel({super.key});

  @override
  State<VaultDesktopPairingPanel> createState() =>
      _VaultDesktopPairingPanelState();
}

class _VaultDesktopPairingPanelState extends State<VaultDesktopPairingPanel> {
  final VaultAccount _account = getIt<VaultAccount>();
  VaultDesktopPairing? _pairing;
  Timer? _timer;
  String? _error;
  bool _expired = false;
  bool _looking = false;
  bool _done = false;

  @override
  void initState() {
    super.initState();
    unawaited(_start());
  }

  @override
  void dispose() {
    _timer?.cancel();
    final p = _pairing;
    if (p != null && !_done) unawaited(_account.cancelDesktopPairing(p));
    super.dispose();
  }

  /// A new code; the one shown before can no longer be approved.
  Future<void> _start() async {
    _timer?.cancel();
    final old = _pairing;
    if (old != null) unawaited(_account.cancelDesktopPairing(old));
    setState(() {
      _pairing = null;
      _error = null;
      _expired = false;
    });
    try {
      final p = await _account.startDesktopPairing();
      if (!mounted) {
        unawaited(_account.cancelDesktopPairing(p));
        return;
      }
      setState(() => _pairing = p);
      _timer = Timer.periodic(
        const Duration(seconds: 2),
        (_) => unawaited(_look()),
      );
    } on VaultApiException catch (e) {
      if (mounted) setState(() => _error = _errorText(e.code));
    } on Object catch (e) {
      debugPrint('[vault] pairing: $e');
      if (mounted) setState(() => _error = 'vault.error_failed'.tr());
    }
  }

  Future<void> _look() async {
    final p = _pairing;
    if (p == null || _looking || _done) return;
    if (p.expired) {
      _timer?.cancel();
      setState(() => _expired = true);
      return;
    }
    _looking = true;
    try {
      if (await _account.checkDesktopPairing(p)) {
        _done = true;
        _timer?.cancel();
        if (mounted) Navigator.of(context).pop(true);
      }
    } on VaultApiException catch (e) {
      // Offline for a moment: keep looking until the code runs out.
      if (e.code != 'NETWORK') {
        _timer?.cancel();
        if (mounted) {
          setState(() {
            if (e.code == 'VAULT_PAIR_NOT_FOUND') {
              _expired = true;
            } else {
              _error = _errorText(e.code);
            }
          });
        }
      }
    } finally {
      _looking = false;
    }
  }

  String _errorText(String code) => switch (code) {
    'NETWORK' => 'vault.error_network'.tr(),
    'VAULT_UNAVAILABLE' => 'vault.error_unavailable'.tr(),
    _ => 'vault.error_failed'.tr(),
  };

  @override
  Widget build(BuildContext context) {
    final cs = ShadTheme.of(context).colorScheme;
    final muted = TextStyle(
      fontSize: 13,
      height: 1.4,
      color: cs.mutedForeground,
    );
    final p = _pairing;
    if (_error != null) {
      return Column(
        mainAxisSize: MainAxisSize.min,
        children: [
          Text(_error!, textAlign: TextAlign.center, style: muted),
          const SizedBox(height: 14),
          AppButton(
            label: 'vault.pair_new_code'.tr(),
            fullWidth: true,
            onPressed: () => unawaited(_start()),
          ),
        ],
      );
    }
    if (p == null) {
      return const Padding(
        padding: EdgeInsets.all(40),
        child: Center(child: CircularProgressIndicator.adaptive()),
      );
    }
    return Column(
      mainAxisSize: MainAxisSize.min,
      children: [
        Center(
          child: AnimatedOpacity(
            duration: const Duration(milliseconds: 200),
            opacity: _expired ? 0.2 : 1,
            child: BiShareQr(data: p.qr),
          ),
        ),
        const SizedBox(height: 14),
        Text(
          'vault.pair_letters'.tr(),
          textAlign: TextAlign.center,
          style: muted,
        ),
        const SizedBox(height: 4),
        Text(
          VaultWebPairing.showCode(p.code),
          textAlign: TextAlign.center,
          style: TextStyle(
            fontFeatures: const [FontFeature.tabularFigures()],
            fontSize: 24,
            fontWeight: FontWeight.w700,
            letterSpacing: 3,
            color: _expired ? cs.mutedForeground : cs.foreground,
          ),
        ),
        const SizedBox(height: 16),
        if (_expired) ...[
          Text(
            'vault.pair_expired'.tr(),
            textAlign: TextAlign.center,
            style: muted,
          ),
          const SizedBox(height: 10),
          AppButton(
            label: 'vault.pair_new_code'.tr(),
            fullWidth: true,
            onPressed: () => unawaited(_start()),
          ),
        ] else
          Row(
            mainAxisAlignment: MainAxisAlignment.center,
            children: [
              SizedBox.square(
                dimension: 14,
                child: CircularProgressIndicator(
                  strokeWidth: 2,
                  color: cs.mutedForeground,
                ),
              ),
              const SizedBox(width: 8),
              Flexible(child: Text('vault.pair_waiting'.tr(), style: muted)),
            ],
          ),
      ],
    );
  }
}
