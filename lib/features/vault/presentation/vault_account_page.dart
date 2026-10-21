import 'dart:async';
import 'dart:io' show Platform;

import 'package:easy_localization/easy_localization.dart';
import 'package:flutter/material.dart';
import 'package:go_router/go_router.dart';
import 'package:shadcn_ui/shadcn_ui.dart';

import '../../../core/desktop/desktop_service.dart';
import '../../../core/di/locator.dart';
import '../../../core/platform/device_lock.dart';
import '../../../core/ui/app_ui.dart';
import '../../scanner/presentation/qr_camera.dart';
import '../../settings/presentation/widgets/glyph.dart';
import '../data/vault_account.dart';
import '../data/vault_api.dart';
import '../data/vault_key_copy.dart';
import '../data/vault_signin.dart';

/// The Drive account on this device (drive-plan.md tasks 3.7, 3.8, 3.9):
/// where the key is, the ways back in, the key for a new device by QR code
/// or phrase, sign-out and deleting the account.
class VaultAccountPage extends StatefulWidget {
  const VaultAccountPage({super.key});

  @override
  State<VaultAccountPage> createState() => _VaultAccountPageState();
}

class _VaultAccountPageState extends State<VaultAccountPage> {
  final VaultAccount _account = getIt<VaultAccount>();
  bool _busy = false;

  @override
  void initState() {
    super.initState();
    unawaited(_refresh());
  }

  Future<void> _refresh() async {
    try {
      await _account.refreshInfo();
    } on VaultApiException catch (e) {
      debugPrint('[vault] account info: $e');
    }
  }

  void _say(String key) {
    if (!mounted) return;
    ScaffoldMessenger.maybeOf(
      context,
    )?.showSnackBar(SnackBar(content: Text(key.tr())));
  }

  String _errorKey(VaultApiException e) => switch (e.code) {
    'NETWORK' => 'vault.error_network',
    'VAULT_IDENTITY_IN_USE' => 'vault.error_identity_in_use',
    'VAULT_PROVIDER_LINKED' => 'vault.error_provider_linked',
    'VAULT_KEY_MISMATCH' => 'vault.error_key_mismatch',
    'VAULT_PHRASE_INVALID' => 'vault.error_phrase_invalid',
    'VAULT_PAIR_NOT_FOUND' => 'vault.error_pair_expired',
    'VAULT_PAIR_TAKEN' => 'vault.error_pair_expired',
    'VAULT_SIGNIN' => 'vault.error_signin_again',
    _ => 'vault.error_generic',
  };

  /// Run [step] with the page busy; errors become a short message.
  Future<void> _run(Future<void> Function() step) async {
    if (_busy) return;
    setState(() => _busy = true);
    try {
      await step();
    } on VaultApiException catch (e) {
      debugPrint('[vault] $e');
      _say(_errorKey(e));
    } on VaultSigninException catch (e) {
      debugPrint('[vault] $e');
      _say('vault.error_generic');
    } on FormatException {
      _say('vault.error_not_a_code');
    } finally {
      if (mounted) setState(() => _busy = false);
    }
  }

  // ---- ways back in ------------------------------------------------------------

  Future<void> _link(String provider) => _run(() async {
    if (await _account.link(provider)) _say('vault.linked');
  });

  Future<void> _showPhrase() async {
    final lock = await DeviceLock.confirm(
      title: 'vault.phrase_title'.tr(),
      reason: 'vault.phrase_lock_reason'.tr(),
    );
    if (!mounted || lock == DeviceLockResult.cancelled) return;
    if (lock != DeviceLockResult.ok) {
      // No screen lock to ask for: say what that means, and let the person
      // decide.
      final go = await showAppSheet<bool>(
        context,
        icon: AppIcons.circleAlert,
        title: 'vault.phrase_no_lock_title'.tr(),
        subtitle: 'vault.phrase_no_lock_body'.tr(),
        builder: (ctx) => _Buttons(
          primary: 'vault.phrase_show_anyway'.tr(),
          onPrimary: () => Navigator.pop(ctx, true),
          secondary: 'vault.cancel'.tr(),
          onSecondary: () => Navigator.pop(ctx, false),
        ),
      );
      if (go != true || !mounted) return;
    }
    final phrase = await _account.phrase();
    if (phrase == null || !mounted) return;
    await showAppSheet<void>(
      context,
      icon: AppIcons.passwordLock,
      title: 'vault.phrase_title'.tr(),
      subtitle: 'vault.phrase_body'.tr(),
      builder: (ctx) => _PhraseWords(words: phrase.split(' ')),
    );
  }

  // ---- the key for this device ---------------------------------------------------

  Future<void> _showCode() => _run(() async {
    final pairing = await _account.startPairing();
    if (!mounted) return;
    var closed = false;
    final wait = _account.awaitGrant(pairing, cancelled: () => closed);
    final sheet = showAppSheet<void>(
      context,
      icon: AppIcons.qrShare,
      title: 'vault.code_title'.tr(),
      subtitle: 'vault.code_body'.tr(),
      builder: (ctx) {
        unawaited(
          wait.then((ok) {
            if (ok && ctx.mounted) Navigator.pop(ctx);
          }, onError: (_) {}),
        );
        return Column(
          mainAxisSize: MainAxisSize.min,
          children: [
            BiShareQr(data: pairing.code, size: 232),
            const SizedBox(height: 14),
            const SizedBox(
              width: 18,
              height: 18,
              child: CircularProgressIndicator(strokeWidth: 2),
            ),
          ],
        );
      },
    );
    await sheet;
    closed = true;
    if (await wait.catchError((Object _) => false)) {
      _say('vault.key_received');
    }
  });

  Future<void> _enterPhrase() async {
    final controller = TextEditingController();
    final phrase = await showAppSheet<String>(
      context,
      icon: AppIcons.keyboard,
      title: 'vault.enter_phrase_title'.tr(),
      subtitle: 'vault.enter_phrase_body'.tr(),
      builder: (ctx) => Column(
        mainAxisSize: MainAxisSize.min,
        children: [
          ShadInput(
            controller: controller,
            autofocus: true,
            minLines: 3,
            maxLines: 5,
            autocorrect: false,
            enableSuggestions: false,
            placeholder: Text('vault.enter_phrase_hint'.tr()),
          ),
          const SizedBox(height: 14),
          SizedBox(
            width: double.infinity,
            child: ShadButton(
              onPressed: () => Navigator.pop(ctx, controller.text),
              child: Text('vault.continue'.tr()),
            ),
          ),
        ],
      ),
    );
    controller.dispose();
    if (phrase == null || phrase.trim().isEmpty) return;
    await _run(() async {
      await _account.acceptPhrase(phrase);
      _say('vault.key_received');
    });
  }

  // ---- giving the key to a new device ----------------------------------------------

  Future<void> _addDevice() async {
    final code = await context.push<String>('/drive-account/scan');
    if (code == null || !mounted) return;
    final ok = await showAppSheet<bool>(
      context,
      icon: AppIcons.permissionShield,
      title: 'vault.grant_title'.tr(),
      subtitle: 'vault.grant_body'.tr(),
      builder: (ctx) => _Buttons(
        primary: 'vault.grant_confirm'.tr(),
        onPrimary: () => Navigator.pop(ctx, true),
        secondary: 'vault.cancel'.tr(),
        onSecondary: () => Navigator.pop(ctx, false),
      ),
    );
    if (ok != true) return;
    await _run(() async {
      await _account.grantTo(code);
      _say('vault.key_sent');
    });
  }

  // ---- the account -------------------------------------------------------------------

  Future<void> _delete() async {
    final providers = [
      for (final p in _account.linkedProviders)
        if (_canSignIn(p)) p,
    ];
    final provider = await showAppSheet<String>(
      context,
      icon: AppIcons.trashDelete,
      iconColor: ShadTheme.of(context).colorScheme.destructive,
      title: 'vault.delete_title'.tr(),
      subtitle: providers.isEmpty
          ? 'vault.delete_no_signin'.tr()
          : 'vault.delete_body'.tr(),
      builder: (ctx) => Column(
        mainAxisSize: MainAxisSize.min,
        children: [
          for (final p in providers)
            AppSheetAction(
              icon: AppIcons.trashDelete,
              label: 'vault.delete_confirm_$p'.tr(),
              destructive: true,
              onTap: () => Navigator.pop(ctx, p),
            ),
          AppSheetAction(
            icon: AppIcons.close,
            label: 'vault.cancel'.tr(),
            onTap: () => Navigator.pop(ctx),
          ),
        ],
      ),
    );
    if (provider == null) return;
    await _run(() async {
      final left = await _account.deleteAccount(provider);
      if (left == null) return;
      if (!mounted) return;
      if (left.contains('google')) {
        await showAppSheet<void>(
          context,
          icon: AppIcons.circleAlert,
          title: 'vault.deleted'.tr(),
          subtitle: 'vault.deleted_google_left'.tr(),
          builder: (ctx) => _Buttons(
            primary: 'vault.ok'.tr(),
            onPrimary: () => Navigator.pop(ctx),
          ),
        );
      } else {
        _say('vault.deleted');
      }
      if (mounted) Navigator.of(context).maybePop();
    });
  }

  Future<void> _signOut() async {
    await _account.signOut();
    if (mounted) Navigator.of(context).maybePop();
  }

  static bool _canSignIn(String provider) => switch (provider) {
    'google' => VaultSignin.googleAvailable,
    'apple' => VaultSignin.appleAvailable,
    _ => false,
  };

  // ---- build -----------------------------------------------------------------------

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
                title: 'vault.account_title'.tr(),
                onBack: () => Navigator.of(context).maybePop(),
              ),
              Expanded(
                child: ListenableBuilder(
                  listenable: Listenable.merge([_account, _account.keyCopy]),
                  builder: (context, _) => ListView(
                    padding: const EdgeInsets.only(top: 8, bottom: 28),
                    children: _sections(context),
                  ),
                ),
              ),
            ],
          ),
        ),
      ),
    );
  }

  List<Widget> _sections(BuildContext context) {
    final muted = ShadTheme.of(context).textTheme.muted.copyWith(fontSize: 12);
    final status = _account.status;
    final ready = status == VaultStatus.ready;
    Widget note(String key) => Padding(
      padding: const EdgeInsets.fromLTRB(28, 8, 28, 4),
      child: Text(key.tr(), style: muted),
    );

    return [
      AppGroup(
        child: AppListTile(
          leading: const Glyph(AppIcons.passwordLock),
          title: Text('vault.title'.tr()),
          subtitle: Text(switch (status) {
            VaultStatus.ready => 'vault.ready'.tr(),
            VaultStatus.needsKey => 'vault.needs_key'.tr(),
            VaultStatus.pendingApproval => 'vault.pending'.tr(),
            VaultStatus.signedOut => 'vault.signed_out'.tr(),
          }),
        ),
      ),
      if (status == VaultStatus.needsKey) ...[
        AppSectionHeader('vault.get_key'.tr()),
        AppGroup(
          child: Column(
            children: [
              AppListTile(
                leading: const Glyph(AppIcons.qrShare),
                title: Text('vault.show_code'.tr()),
                trailing: const _Chevron(),
                onTap: _busy ? null : _showCode,
              ),
              const AppRowDivider(indent: 58),
              AppListTile(
                leading: const Glyph(AppIcons.keyboard),
                title: Text('vault.enter_phrase'.tr()),
                trailing: const _Chevron(),
                onTap: _busy ? null : _enterPhrase,
              ),
            ],
          ),
        ),
        note(
          Platform.isIOS || Platform.isMacOS
              ? 'vault.get_key_note_apple'
              : 'vault.get_key_note',
        ),
      ],
      if (ready) ...[
        AppSectionHeader('vault.ways_back'.tr()),
        AppGroup(child: Column(children: _waysBack())),
        note('vault.ways_back_note'),
        // Giving the key to a new device needs a camera to read its code.
        if (supportsCameraScan) ...[
          AppSectionHeader('vault.devices'.tr()),
          AppGroup(
            child: AppListTile(
              leading: const Glyph(AppIcons.scanDocument),
              title: Text('vault.add_device'.tr()),
              subtitle: Text('vault.add_device_body'.tr()),
              trailing: const _Chevron(),
              onTap: _busy ? null : _addDevice,
            ),
          ),
        ],
      ],
      AppSectionHeader('vault.account'.tr()),
      AppGroup(
        child: Column(
          children: [
            AppListTile(
              leading: const Glyph(AppIcons.close),
              title: Text('vault.sign_out'.tr()),
              onTap: _busy ? null : _signOut,
            ),
            const AppRowDivider(indent: 58),
            AppListTile(
              leading: const Glyph(AppIcons.trashDelete),
              title: Text('vault.delete'.tr()),
              onTap: _busy ? null : _delete,
            ),
          ],
        ),
      ),
    ];
  }

  List<Widget> _waysBack() {
    final linked = _account.linkedProviders;
    final copy = _account.keyCopy;
    final rows = <Widget>[];
    void add(Widget w) {
      if (rows.isNotEmpty) rows.add(const AppRowDivider(indent: 58));
      rows.add(w);
    }

    for (final p in const ['google', 'apple']) {
      final isLinked = linked.contains(p);
      if (!isLinked && !_canSignIn(p)) continue;
      final holder = p == 'google' ? 'google' : 'icloud';
      final where = copy.holders.contains(holder)
          ? copy.stateOf(holder)
          : KeyCopyState.unreachable;
      add(
        AppListTile(
          leading: Glyph(isLinked ? AppIcons.verifiedCheck : AppIcons.logIn),
          title: Text('vault.way_$p'.tr()),
          subtitle: Text(
            !isLinked
                ? 'vault.way_not_linked'.tr()
                : switch (where) {
                    KeyCopyState.saved => 'vault.copy_saved_$holder'.tr(),
                    KeyCopyState.unreachable => 'vault.copy_elsewhere'.tr(),
                    KeyCopyState.failed => 'vault.copy_failed'.tr(),
                    KeyCopyState.missing ||
                    KeyCopyState.unknown => 'vault.copy_checking'.tr(),
                  },
          ),
          trailing: !isLinked && _canSignIn(p)
              ? AppButton(
                  label: 'vault.link'.tr(),
                  variant: AppButtonVariant.outline,
                  onPressed: _busy ? null : () => _link(p),
                )
              : null,
        ),
      );
    }
    add(
      AppListTile(
        leading: const Glyph(AppIcons.eyePreview),
        title: Text('vault.phrase_row'.tr()),
        subtitle: Text('vault.phrase_row_body'.tr()),
        trailing: const _Chevron(),
        onTap: _busy ? null : _showPhrase,
      ),
    );
    return rows;
  }
}

class _Buttons extends StatelessWidget {
  const _Buttons({
    required this.primary,
    required this.onPrimary,
    this.secondary,
    this.onSecondary,
  });

  final String primary;
  final VoidCallback onPrimary;
  final String? secondary;
  final VoidCallback? onSecondary;

  @override
  Widget build(BuildContext context) => Column(
    mainAxisSize: MainAxisSize.min,
    children: [
      SizedBox(
        width: double.infinity,
        child: ShadButton(onPressed: onPrimary, child: Text(primary)),
      ),
      if (secondary != null) ...[
        const SizedBox(height: 8),
        SizedBox(
          width: double.infinity,
          child: ShadButton.outline(
            onPressed: onSecondary,
            child: Text(secondary!),
          ),
        ),
      ],
    ],
  );
}

/// The 24 words, numbered, in two columns; selectable text is off so the
/// phrase does not land in the clipboard by accident.
class _PhraseWords extends StatelessWidget {
  const _PhraseWords({required this.words});

  final List<String> words;

  @override
  Widget build(BuildContext context) {
    final theme = ShadTheme.of(context);
    final half = (words.length / 2).ceil();
    Widget column(int from, int to) => Expanded(
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          for (var i = from; i < to; i++)
            Padding(
              padding: const EdgeInsets.symmetric(vertical: 3),
              child: Text.rich(
                TextSpan(
                  children: [
                    TextSpan(
                      text: '${i + 1}'.padLeft(2),
                      style: theme.textTheme.muted.copyWith(
                        fontFeatures: const [FontFeature.tabularFigures()],
                      ),
                    ),
                    TextSpan(
                      text: '  ${words[i]}',
                      style: theme.textTheme.p.copyWith(
                        fontWeight: FontWeight.w600,
                      ),
                    ),
                  ],
                ),
              ),
            ),
        ],
      ),
    );
    return Row(
      crossAxisAlignment: CrossAxisAlignment.start,
      children: [column(0, half), column(half, words.length)],
    );
  }
}

/// The camera, for a Drive pairing code only; pops with its text.
class VaultPairScanPage extends StatefulWidget {
  const VaultPairScanPage({super.key});

  @override
  State<VaultPairScanPage> createState() => _PairScanPageState();
}

class _PairScanPageState extends State<VaultPairScanPage> {
  final QrCameraController _controller = QrCameraController();
  bool _done = false;

  @override
  void dispose() {
    _controller.dispose();
    super.dispose();
  }

  void _onCode(String raw) {
    if (_done || !raw.startsWith('BSVP1.')) return;
    _done = true;
    tapHaptic();
    context.pop(raw);
  }

  @override
  Widget build(BuildContext context) {
    return Scaffold(
      backgroundColor: Colors.black,
      body: Stack(
        fit: StackFit.expand,
        children: [
          QrCamera(
            controller: _controller,
            onCode: _onCode,
            denied: Center(
              child: Padding(
                padding: const EdgeInsets.all(32),
                child: Text(
                  'vault.scan_no_camera'.tr(),
                  textAlign: TextAlign.center,
                  style: const TextStyle(color: Colors.white),
                ),
              ),
            ),
          ),
          SafeArea(
            child: Column(
              children: [
                Align(
                  alignment: Alignment.topLeft,
                  child: IconButton(
                    color: Colors.white,
                    icon: const Icon(Icons.close),
                    onPressed: () => context.pop(),
                  ),
                ),
                const Spacer(),
                Padding(
                  padding: const EdgeInsets.fromLTRB(24, 0, 24, 32),
                  child: Text(
                    'vault.scan_hint'.tr(),
                    textAlign: TextAlign.center,
                    style: const TextStyle(color: Colors.white, fontSize: 15),
                  ),
                ),
              ],
            ),
          ),
        ],
      ),
    );
  }
}

class _Chevron extends StatelessWidget {
  const _Chevron();

  @override
  Widget build(BuildContext context) => AppSvgIcon(
    AppIcons.chevronRight,
    size: 18,
    color: ShadTheme.of(
      context,
    ).colorScheme.mutedForeground.withValues(alpha: 0.6),
  );
}
