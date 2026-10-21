import 'dart:io';

import 'package:flutter/foundation.dart';
import 'package:google_sign_in/google_sign_in.dart';
import 'package:google_sign_in_platform_interface/google_sign_in_platform_interface.dart';
import 'package:sign_in_with_apple/sign_in_with_apple.dart';

import 'google_app_data.dart';
import 'vault_config.dart';
import 'vault_google_desktop.dart';
import 'vault_keys.dart';

/// An ID token from Apple or Google, bound to this device's key by its nonce.
class ProviderToken {
  const ProviderToken({
    required this.provider,
    required this.idToken,
    this.appleCode,
  });

  /// "apple" or "google".
  final String provider;
  final String idToken;

  /// Apple's one-time authorization code; the server swaps it for the refresh
  /// token it needs to revoke the sign-in when the account is deleted.
  final String? appleCode;
}

class VaultSigninException implements Exception {
  const VaultSigninException(this.message);
  final String message;
  @override
  String toString() => 'VaultSigninException: $message';
}

/// The provider flows: Apple and Google on iOS and macOS, Google on Android
/// (task 3.2), Google on Windows and Linux through the browser (task 3.4,
/// [VaultGoogleDesktop]). Apple on Android, Windows and Linux comes with task
/// 3.3 and the rest of 3.4.
///
/// Nothing is asked for but the sign-in itself: no email, no name, no profile
/// scope. The server keeps only a keyed hash of the account id.
///
/// Every token carries [nonce], which the server recomputes from the device
/// public key sent with it, so a token taken from one device cannot enrol
/// another (VAULT-SPEC "Sign-in nonce").
class VaultSignin {
  VaultSignin(this._keys) : _desktop = VaultGoogleDesktop(_keys);

  final VaultKeyStore _keys;
  final VaultGoogleDesktop _desktop;

  /// One nonce per installation: the device key never changes, and
  /// `GoogleSignIn.initialize` may run only once.
  String? _googleNonce;
  GoogleSignInAccount? _googleAccount;

  static bool get _googleNative =>
      Platform.isAndroid || Platform.isIOS || Platform.isMacOS;

  static bool get googleAvailable =>
      _googleNative || VaultGoogleDesktop.available;

  static bool get appleAvailable => Platform.isIOS || Platform.isMacOS;

  /// The Drive app-data tokens of whichever Google flow this platform uses,
  /// for the key copy.
  GoogleDriveAccess get googleDrive =>
      _googleNative ? _NativeGoogleDrive(this) : _desktop;

  /// Null when the person closes the sheet.
  Future<ProviderToken?> google(String nonce) async {
    if (!_googleNative) {
      final idToken = await _desktop.signIn(nonce);
      if (idToken == null) return null;
      await _keys.setGoogleHere(true);
      return ProviderToken(provider: 'google', idToken: idToken);
    }
    try {
      await _initGoogle(nonce);
      // The Drive scope as a hint: platforms that can ask for it in the same
      // sheet do, the others ask when the key copy is first written.
      final account = await GoogleSignIn.instance.authenticate(
        scopeHint: const [VaultConfig.driveAppDataScope],
      );
      final idToken = account.authentication.idToken;
      if (idToken == null || idToken.isEmpty) {
        throw const VaultSigninException('Google returned no ID token');
      }
      _googleAccount = account;
      await _keys.setGoogleHere(true);
      if (Platform.isAndroid) await _keys.saveGoogleEmail(account.email);
      return ProviderToken(provider: 'google', idToken: idToken);
    } on GoogleSignInException catch (e) {
      if (e.code == GoogleSignInExceptionCode.canceled) return null;
      throw VaultSigninException(
        e.description ?? 'Google sign-in failed (${e.code.name})',
      );
    }
  }

  /// Null when the person closes the sheet.
  Future<ProviderToken?> apple(String nonce) async {
    try {
      final credential = await SignInWithApple.getAppleIDCredential(
        // No email, no name: Drive does not want them.
        scopes: const [],
        nonce: nonce,
      );
      final idToken = credential.identityToken;
      if (idToken == null || idToken.isEmpty) {
        throw const VaultSigninException('Apple returned no ID token');
      }
      return ProviderToken(
        provider: 'apple',
        idToken: idToken,
        appleCode: credential.authorizationCode,
      );
    } on SignInWithAppleAuthorizationException catch (e) {
      if (e.code == AuthorizationErrorCode.canceled) return null;
      throw VaultSigninException(e.message);
    }
  }

  Future<void> _initGoogle(String nonce) async {
    if (_googleNonce == nonce) return;
    if (_googleNonce != null) {
      throw const VaultSigninException(
        'device key changed; restart the app to sign in',
      );
    }
    await GoogleSignIn.instance.initialize(
      // The token's audience on Android; iOS and macOS pass their own client.
      serverClientId: VaultConfig.googleWebClientId,
      clientId: Platform.isIOS || Platform.isMacOS
          ? VaultConfig.googleAppleClientId
          : null,
      nonce: nonce,
    );
    _googleNonce = nonce;
  }

  /// The Google account this device signed in with, restored without any
  /// sheet after a restart. Null when this device never signed in with
  /// Google for Drive, or Google wants the person.
  Future<GoogleSignInAccount?> _restoreGoogle() async {
    if (_googleAccount != null) return _googleAccount;
    if (!await _keys.googleHere()) return null;
    try {
      await _initGoogle(await _keys.signinNonce());
      return _googleAccount = await GoogleSignIn.instance
          .attemptLightweightAuthentication(reportAllExceptions: false);
    } on Object catch (e) {
      debugPrint('[vault] Google restore failed: $e');
      return null;
    }
  }

  /// Android: the app-data token straight from Google's authorization API,
  /// for the account this device signed in with. The sign-in itself is not
  /// run again: on Android even its quiet form (Credential Manager) shows a
  /// "signing in" sheet, which came up at every start while the key copy was
  /// checked. Without [interactive], null when Google would need the person.
  Future<String?> _androidDriveToken(
    List<String> scopes, {
    required bool interactive,
  }) async {
    if (!await _keys.googleHere()) return null;
    await _initGoogle(await _keys.signinNonce());
    final data = await GoogleSignInPlatform.instance
        .clientAuthorizationTokensForScopes(
          ClientAuthorizationTokensForScopesParameters(
            request: AuthorizationRequestDetails(
              scopes: scopes,
              userId: null,
              // Signed in before this was kept: Google picks the account,
              // or asks when [interactive].
              email: await _keys.googleEmail(),
              promptIfUnauthorized: interactive,
            ),
          ),
        );
    return data?.accessToken;
  }

  /// Sign-out of Drive: forget this device's Google sign-in for Drive (and on
  /// Windows and Linux revoke its grant), so nothing Google stays behind.
  Future<void> forgetGoogle() async {
    await _keys.setGoogleHere(false);
    _googleAccount = null;
    if (!_googleNative) {
      await _desktop.forget();
      return;
    }
    try {
      // Signing out needs Google set up on this run, even when this run never
      // signed in (the nonce is this device's, as at any sign-in).
      await _initGoogle(await _keys.signinNonce());
      await GoogleSignIn.instance.signOut();
    } on Object {
      // Nothing to forget.
    }
  }
}

/// google_sign_in's authorization client, for the `drive.appdata` scope.
class _NativeGoogleDrive implements GoogleDriveAccess {
  _NativeGoogleDrive(this._signin);

  final VaultSignin _signin;

  static const _scopes = [VaultConfig.driveAppDataScope];

  @override
  Future<String?> accessToken({bool interactive = false}) async {
    if (Platform.isAndroid) {
      try {
        return await _signin._androidDriveToken(
          _scopes,
          interactive: interactive,
        );
      } on GoogleSignInException catch (e) {
        if (e.code == GoogleSignInExceptionCode.canceled) return null;
        rethrow;
      }
    }
    final account = await _signin._restoreGoogle();
    if (account == null) return null;
    final client = account.authorizationClient;
    try {
      final authz =
          await client.authorizationForScopes(_scopes) ??
          (interactive ? await client.authorizeScopes(_scopes) : null);
      return authz?.accessToken;
    } on GoogleSignInException catch (e) {
      if (e.code == GoogleSignInExceptionCode.canceled) return null;
      rethrow;
    }
  }

  @override
  Future<void> invalidate(String token) => GoogleSignIn
      .instance
      .authorizationClient
      .clearAuthorizationToken(accessToken: token);
}
