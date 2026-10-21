import 'dart:io';

import 'package:google_sign_in/google_sign_in.dart';
import 'package:sign_in_with_apple/sign_in_with_apple.dart';

import 'vault_config.dart';

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

/// The native provider flows (drive-plan.md task 3.2): Apple and Google on
/// iOS and macOS, Google on Android. Apple on Android, and both on Windows and
/// Linux, come with tasks 3.3 and 3.4.
///
/// Nothing is asked for but the sign-in itself: no email, no name, no profile
/// scope. The server keeps only a keyed hash of the account id.
///
/// Every token carries [nonce], which the server recomputes from the device
/// public key sent with it, so a token taken from one device cannot enrol
/// another (VAULT-SPEC "Sign-in nonce").
class VaultSignin {
  /// One nonce per installation: the device key never changes, and
  /// `GoogleSignIn.initialize` may run only once.
  String? _googleNonce;

  static bool get googleAvailable =>
      Platform.isAndroid || Platform.isIOS || Platform.isMacOS;

  static bool get appleAvailable => Platform.isIOS || Platform.isMacOS;

  /// Null when the person closes the sheet.
  Future<ProviderToken?> google(String nonce) async {
    final google = GoogleSignIn.instance;
    try {
      if (_googleNonce == null) {
        await google.initialize(
          // The token's audience on Android; iOS and macOS pass their own client.
          serverClientId: VaultConfig.googleWebClientId,
          clientId: Platform.isIOS || Platform.isMacOS
              ? VaultConfig.googleAppleClientId
              : null,
          nonce: nonce,
        );
        _googleNonce = nonce;
      } else if (_googleNonce != nonce) {
        throw const VaultSigninException(
          'device key changed; restart the app to sign in',
        );
      }
      final account = await google.authenticate();
      final idToken = account.authentication.idToken;
      if (idToken == null || idToken.isEmpty) {
        throw const VaultSigninException('Google returned no ID token');
      }
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

  /// Google's sign-in state on this device is not needed after the token is
  /// exchanged; signing out of it keeps the account picker fresh next time.
  Future<void> forgetGoogle() async {
    if (_googleNonce == null) return;
    try {
      await GoogleSignIn.instance.signOut();
    } on Object {
      // Nothing to forget.
    }
  }
}
