import 'dart:io' show Platform;

/// External BIShare URLs and contact info surfaced in Settings → About.
///
/// The canonical marketing/legal site is https://bishare.app — the Privacy
/// Policy and Terms of Service live there. Product support is handled by the
/// Billion Group team at [supportEmail].
class AppLinks {
  AppLinks._();

  static const String website = 'https://bishare.app';
  static const String privacy = 'https://bishare.app/privacy';
  static const String terms = 'https://bishare.app/terms';
  static const String help = 'https://bishare.app/how-it-works';
  static const String supportEmail = 'support@billiongroup.net';

  /// Android application id — used to build the Play Store rating link.
  static const String androidPackage = 'com.bishare.app';

  /// A pre-filled `mailto:` for the support inbox.
  static Uri get supportMailto =>
      Uri(scheme: 'mailto', path: supportEmail, query: 'subject=BIShare Support');

  /// The store (or website) URL to open for "Rate BIShare".
  ///
  /// Android points at the Play Store listing; every other platform falls back
  /// to the website until per-store listings exist.
  static String get rateUrl => Platform.isAndroid
      ? 'https://play.google.com/store/apps/details?id=$androidPackage'
      : website;

  /// The message shared by "Share BIShare".
  static const String shareMessage =
      'Check out BIShare — share files between your devices, no internet needed. $website';
}
