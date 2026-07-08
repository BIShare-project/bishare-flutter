import 'package:equatable/equatable.dart';

/// Domain-level failure. Use cases return `Either<Failure, T>` so the
/// presentation layer never sees raw exceptions.
sealed class Failure extends Equatable {
  const Failure(this.message);
  final String message;

  @override
  List<Object?> get props => [message];
}

/// The peer could not be reached (connection refused / timeout / offline).
class NetworkFailure extends Failure {
  const NetworkFailure([super.message = 'Network unreachable']);
}

/// A PIN is required to send to this device (HTTP 401).
class PinRequiredFailure extends Failure {
  const PinRequiredFailure([super.message = 'PIN required']);
}

/// The provided PIN was wrong (HTTP 403 on prepare).
class WrongPinFailure extends Failure {
  const WrongPinFailure([super.message = 'Wrong PIN']);
}

/// The receiver rejected the transfer (HTTP 403).
class RejectedFailure extends Failure {
  const RejectedFailure([super.message = 'Transfer rejected']);
}

/// The receiver is busy with another transfer (HTTP 409).
class BusyFailure extends Failure {
  const BusyFailure([super.message = 'Device busy']);
}

/// The user cancelled the transfer.
class CancelledFailure extends Failure {
  const CancelledFailure([super.message = 'Transfer cancelled']);
}

/// Integrity check failed (SHA-256 mismatch) or decryption failed.
class IntegrityFailure extends Failure {
  const IntegrityFailure([super.message = 'Integrity check failed']);
}

/// A generic server-side error (HTTP 5xx / malformed response).
class ServerFailure extends Failure {
  const ServerFailure([super.message = 'Server error']);
}

/// Anything unclassified.
class UnknownFailure extends Failure {
  const UnknownFailure([super.message = 'Unknown error']);
}
