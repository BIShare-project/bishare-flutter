/// BIShare Drive (code name "vault"): fixed identifiers.
///
/// The Google OAuth client ids belong to Google Cloud project "bishare"
/// (made 2026-10-21, drive-plan.md task 3.11). They are public by nature:
/// every app that signs in with Google ships its client ids. The server
/// accepts ID tokens for exactly these audiences (`VAULT_GOOGLE_AUDIENCES` in
/// bishare-api's wrangler.jsonc).
///
/// Android has no client id in code: Google matches the app by package name
/// and signing certificate (an Android client in the same project), and the
/// ID token's audience is [googleWebClientId], passed as the server client id.
library;

class VaultConfig {
  VaultConfig._();

  /// The web client: drive.bishare.app, and Android's server client id.
  static const String googleWebClientId =
      '975128452930-fm802bjoiu2046junboko4ucb64gkboo.apps.googleusercontent.com';

  /// The iOS client, shared by the Mac app (same bundle id, com.bishare.app).
  /// Its reversed form is the URL scheme in both Info.plist files.
  static const String googleAppleClientId =
      '975128452930-pav8rlui8upmgve3fntfsvj8eaprhoru.apps.googleusercontent.com';

  /// The desktop client (Windows, Linux loopback flow, task 3.4).
  static const String googleDesktopClientId =
      '975128452930-1bordn6lu4pi8rtgumevojn4jiu0cu96.apps.googleusercontent.com';

  /// The one Google Drive scope Drive asks for: a hidden folder only this app
  /// can see, where the key copy lives (drive-plan.md "Where the key copy
  /// lives"). No other file in the person's Google Drive is visible to it.
  static const String driveAppDataScope =
      'https://www.googleapis.com/auth/drive.appdata';
}
