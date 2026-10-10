import 'package:easy_localization/easy_localization.dart';
import 'package:flutter/material.dart';
import 'package:shadcn_ui/shadcn_ui.dart';
import 'package:shared_preferences/shared_preferences.dart';

import '../../../core/config/feature_flags.dart';
import '../../../core/di/locator.dart';
import '../../../core/telemetry/telemetry_service.dart';
import '../../../core/ui/app_ui.dart';

/// One question, asked once per install at the bottom of Home: would this
/// person use encrypted storage at a stated price, only if it were free, or not
/// at all?
///
/// It is a question, not an offer. Nothing is sold here, the three answers have
/// the same weight, and the card says that sending stays free. Each answer adds
/// one to an anonymous tally ([TelemetryService.recordInterest]); the answer
/// itself stays on the device so the question is never asked twice.
///
/// Shown only when the remote flag is on, usage statistics are on (a card that
/// cannot be counted is not worth showing) and this is not the first launch.
class DriveInterestCard extends StatefulWidget {
  const DriveInterestCard({super.key, this.prefs, this.flags, this.telemetry});

  /// Taken from the locator when null; tests pass their own.
  final SharedPreferences? prefs;
  final FeatureFlags? flags;
  final TelemetryService? telemetry;

  /// What this install answered: 'yes_paid', 'yes_free', 'no' or 'dismiss'.
  static const answerKey = 'driveInterestAnswer';

  /// Set once the question has been counted as shown.
  static const seenKey = 'driveInterestSeen';

  /// App launches that reached Home, counted from the version that added this.
  static const launchesKey = 'driveInterestLaunches';

  /// Not on the first launch: a new install is still in onboarding, and an
  /// updated one has just opened the app for something else.
  static const minLaunches = 2;

  @visibleForTesting
  static bool shouldShow({
    required bool flagOn,
    required bool telemetryOn,
    required int launches,
    required String? answer,
  }) => flagOn && telemetryOn && launches >= minLaunches && answer == null;

  @override
  State<DriveInterestCard> createState() => _DriveInterestCardState();
}

class _DriveInterestCardState extends State<DriveInterestCard> {
  /// One count per run of the app, however often Home is rebuilt.
  static bool _launchCounted = false;

  // Null when a host (a widget test of Home, the store screenshots) has not
  // registered them: the card then stays out of the way instead of throwing.
  SharedPreferences? _prefs;
  FeatureFlags? _flags;
  TelemetryService? _telemetry;

  bool _thanks = false;

  static T? _find<T extends Object>() => getIt.isRegistered<T>() ? getIt<T>() : null;

  @override
  void initState() {
    super.initState();
    _prefs = widget.prefs ?? _find<SharedPreferences>();
    _flags = widget.flags ?? _find<FeatureFlags>();
    _telemetry = widget.telemetry ?? _find<TelemetryService>();
    final prefs = _prefs;
    if (prefs != null && !_launchCounted) {
      _launchCounted = true;
      prefs.setInt(
        DriveInterestCard.launchesKey,
        (prefs.getInt(DriveInterestCard.launchesKey) ?? 0) + 1,
      );
    }
    _flags?.addListener(_onFlags);
  }

  @override
  void dispose() {
    _flags?.removeListener(_onFlags);
    super.dispose();
  }

  void _onFlags() {
    if (mounted) setState(() {});
  }

  bool get _visible {
    final prefs = _prefs, flags = _flags, telemetry = _telemetry;
    if (prefs == null || flags == null || telemetry == null) return false;
    return DriveInterestCard.shouldShow(
      flagOn: flags.driveInterestEnabled,
      telemetryOn: telemetry.enabled,
      launches: prefs.getInt(DriveInterestCard.launchesKey) ?? 0,
      answer: prefs.getString(DriveInterestCard.answerKey),
    );
  }

  void _countView() {
    final prefs = _prefs;
    if (prefs == null || (prefs.getBool(DriveInterestCard.seenKey) ?? false)) return;
    prefs.setBool(DriveInterestCard.seenKey, true);
    _telemetry?.recordInterest('view');
  }

  void _answer(String event) {
    _prefs?.setString(DriveInterestCard.answerKey, event);
    _telemetry?.recordInterest(event);
    setState(() => _thanks = event != 'dismiss');
  }

  @override
  Widget build(BuildContext context) {
    final cs = ShadTheme.of(context).colorScheme;

    if (_thanks) {
      return AppCard(
        child: Text(
          'interest.thanks'.tr(),
          textAlign: TextAlign.center,
          style: TextStyle(fontSize: 13, color: cs.mutedForeground),
        ),
      );
    }
    if (!_visible) return const SizedBox.shrink();

    WidgetsBinding.instance.addPostFrameCallback((_) => _countView());

    return AppCard(
      padding: const EdgeInsetsDirectional.fromSTEB(14, 6, 6, 14),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Row(
            children: [
              Expanded(
                child: Text(
                  'interest.eyebrow'.tr().toUpperCase(),
                  maxLines: 1,
                  overflow: TextOverflow.ellipsis,
                  style: TextStyle(
                    fontSize: 11,
                    fontWeight: FontWeight.w600,
                    letterSpacing: 0.8,
                    color: cs.mutedForeground,
                  ),
                ),
              ),
              Semantics(
                label: 'interest.close'.tr(),
                button: true,
                child: ShadIconButton.ghost(
                  icon: AppSvgIcon(AppIcons.close, size: 18, color: cs.mutedForeground),
                  onPressed: () => _answer('dismiss'),
                ),
              ),
            ],
          ),
          Padding(
            padding: const EdgeInsetsDirectional.only(end: 8),
            child: Column(
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                Text(
                  'interest.title'.tr(),
                  style: TextStyle(
                    fontSize: 16,
                    fontWeight: FontWeight.w700,
                    color: cs.foreground,
                  ),
                ),
                const SizedBox(height: 4),
                Text(
                  'interest.body'.tr(),
                  style: TextStyle(fontSize: 13, height: 1.4, color: cs.mutedForeground),
                ),
                const SizedBox(height: 12),
                Wrap(
                  spacing: 8,
                  runSpacing: 8,
                  children: [
                    AppButton(
                      label: 'interest.yes_paid'.tr(),
                      variant: AppButtonVariant.outline,
                      size: AppButtonSize.small,
                      onPressed: () => _answer('yes_paid'),
                    ),
                    AppButton(
                      label: 'interest.yes_free'.tr(),
                      variant: AppButtonVariant.outline,
                      size: AppButtonSize.small,
                      onPressed: () => _answer('yes_free'),
                    ),
                    AppButton(
                      label: 'interest.no'.tr(),
                      variant: AppButtonVariant.outline,
                      size: AppButtonSize.small,
                      onPressed: () => _answer('no'),
                    ),
                  ],
                ),
              ],
            ),
          ),
        ],
      ),
    );
  }
}
