import 'dart:async';

import 'package:equatable/equatable.dart';
import 'package:flutter_bloc/flutter_bloc.dart';

import '../../../core/identity/device_identity.dart';
import '../data/auth_models.dart';
import '../data/auth_service.dart';
import '../data/authed_dio.dart';
import '../data/oauth_service.dart';
import '../data/token_store.dart';

/// The four conceptual auth states, per the Fase A spec:
/// * [unknown] — bootstrap; reading the persisted session.
/// * [unauthenticated] — no session (the email-entry step).
/// * [codeSent] — a code was emailed (the code-entry step; carries the email).
/// * [authenticated] — signed in (carries the [AuthUser] + [AuthState.tier]).
enum AuthStatus { unknown, unauthenticated, codeSent, authenticated }

/// A single immutable auth state (the app's convention — cf. `DevicesState`,
/// `ClipboardState`). The `error` state is surfaced via a transient [errorKey]
/// overlaid on the current step, so a failed verify keeps the code the user is
/// entering instead of dropping them back to the email step.
class AuthState extends Equatable {
  const AuthState({
    required this.status,
    this.user,
    this.email = '',
    this.submitting = false,
    this.errorKey,
  });

  final AuthStatus status;

  /// Present only when [status] is [AuthStatus.authenticated].
  final AuthUser? user;

  /// The email a code was sent to (kept for the code step + resend).
  final String email;

  /// A request is in flight (drives button spinners + disables inputs).
  final bool submitting;

  /// Localization key for a transient error, or null. Represents the "error"
  /// state without discarding the current step's context.
  final String? errorKey;

  /// The current account tier (`free` when signed out).
  String get tier => user?.tier ?? 'free';

  bool get isAuthenticated => status == AuthStatus.authenticated;

  AuthState copyWith({
    AuthStatus? status,
    AuthUser? user,
    String? email,
    bool? submitting,
    String? errorKey,
    bool clearError = false,
  }) => AuthState(
    status: status ?? this.status,
    user: user ?? this.user,
    email: email ?? this.email,
    submitting: submitting ?? this.submitting,
    errorKey: clearError ? null : (errorKey ?? this.errorKey),
  );

  @override
  List<Object?> get props => [status, user, email, submitting, errorKey];
}

/// Drives the magic-link flow (request → verify) and session lifecycle. Provided
/// app-wide (see `app.dart`) so Settings and, later, the Drive tab can read the
/// signed-in [AuthState.user] / [AuthState.tier].
class AuthCubit extends Cubit<AuthState> {
  AuthCubit(
    this._service,
    this._oauth,
    this._tokens,
    this._authedDio,
    this._identity,
  ) : super(const AuthState(status: AuthStatus.unknown)) {
    // A failed silent refresh downstream clears the session — reflect it.
    _expiredSub = _authedDio.sessionExpired.listen((_) {
      if (!isClosed) emit(const AuthState(status: AuthStatus.unauthenticated));
    });
    unawaited(_restore());
  }

  final AuthService _service;
  final OauthService _oauth;
  final TokenStore _tokens;
  final AuthedDio _authedDio;
  final DeviceIdentity _identity;
  late final StreamSubscription<void> _expiredSub;

  static final _emailRegExp = RegExp(r'^[^\s@]+@[^\s@]+\.[^\s@]+$');

  /// Restore a persisted session on launch.
  Future<void> _restore() async {
    final user = await _tokens.user();
    if (await _tokens.hasSession() && user != null) {
      emit(AuthState(status: AuthStatus.authenticated, user: user));
    } else {
      emit(const AuthState(status: AuthStatus.unauthenticated));
    }
  }

  /// Step 1 — request a sign-in code for [email]. Advances to [codeSent] on 200.
  Future<void> requestCode(String email) async {
    final normalized = email.trim();
    if (!_emailRegExp.hasMatch(normalized)) {
      emit(state.copyWith(errorKey: 'auth.error_email', submitting: false));
      return;
    }
    emit(state.copyWith(submitting: true, clearError: true));
    try {
      await _service.requestMagicLink(normalized);
      emit(AuthState(status: AuthStatus.codeSent, email: normalized));
    } on AuthException catch (e) {
      emit(state.copyWith(submitting: false, errorKey: _messageKey(e)));
    }
  }

  /// Re-send the code to the same email (only meaningful on the code step).
  Future<void> resendCode() async {
    if (state.status != AuthStatus.codeSent || state.email.isEmpty) return;
    await requestCode(state.email);
  }

  /// Step 2 — verify the [code] and establish a session.
  Future<void> verifyCode(String code) async {
    if (state.status != AuthStatus.codeSent) return;
    final normalized = code.trim().toUpperCase();
    if (normalized.length != 6) {
      emit(state.copyWith(errorKey: 'auth.error_code', submitting: false));
      return;
    }
    emit(state.copyWith(submitting: true, clearError: true));
    try {
      final tokens = await _service.verifyMagicLink(
        email: state.email,
        code: normalized,
        deviceName: _identity.alias,
        deviceId: _identity.fingerprint,
      );
      await _tokens.saveSession(tokens);
      emit(AuthState(status: AuthStatus.authenticated, user: tokens.user));
    } on AuthException catch (e) {
      emit(state.copyWith(submitting: false, errorKey: _messageKey(e)));
    }
  }

  /// Google sign-in — runs the native provider flow, then establishes a session
  /// through the exact same persist/emit path as magic-link verify.
  Future<void> signInWithGoogle() => _signInWithProvider(_oauth.signInWithGoogle);

  /// Apple sign-in (iOS/macOS only — see [OauthService.appleAvailable]).
  Future<void> signInWithApple() => _signInWithProvider(_oauth.signInWithApple);

  /// Shared OAuth flow: a null result means the user canceled the provider
  /// sheet — quietly return to the idle step with no error banner.
  Future<void> _signInWithProvider(Future<AuthTokens?> Function() run) async {
    if (state.submitting) return;
    emit(state.copyWith(submitting: true, clearError: true));
    try {
      final tokens = await run();
      if (tokens == null) {
        emit(state.copyWith(submitting: false));
        return;
      }
      await _tokens.saveSession(tokens);
      emit(AuthState(status: AuthStatus.authenticated, user: tokens.user));
    } on AuthException catch (e) {
      emit(state.copyWith(submitting: false, errorKey: _messageKey(e)));
    }
  }

  /// Return to the email step (keeps the typed email as a convenience).
  void backToEmail() =>
      emit(AuthState(status: AuthStatus.unauthenticated, email: state.email));

  /// Clear any transient error (e.g. when the user edits a field).
  void clearError() {
    if (state.errorKey != null) emit(state.copyWith(clearError: true));
  }

  /// Best-effort server revoke, then wipe the local session.
  Future<void> logout() async {
    final access = await _tokens.accessToken();
    final refresh = await _tokens.refreshToken();
    if (access != null && access.isNotEmpty) {
      await _service.logout(accessToken: access, refreshToken: refresh);
    }
    await _tokens.clear();
    emit(const AuthState(status: AuthStatus.unauthenticated));
  }

  /// Map a backend error code to a localization key.
  String _messageKey(AuthException e) => switch (e.code) {
    'INVALID_TOKEN' => 'auth.error_invalid_code',
    'ACCOUNT_DISABLED' => 'auth.error_disabled',
    'VALIDATION_ERROR' => 'auth.error_generic',
    'NETWORK' => 'auth.error_network',
    'OAUTH' => 'auth.error_oauth',
    _ => 'auth.error_generic',
  };

  @override
  Future<void> close() async {
    await _expiredSub.cancel();
    return super.close();
  }
}
