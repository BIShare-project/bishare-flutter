/// The reverse flow: a device asks another to SEND it files.
///
/// The requester POSTs a [FileRequestMessage] to the target's `/api/v1/request`;
/// the target surfaces a prompt, picks files, and (on accept) sends them back to
/// `requesterHost:requesterPort` via the normal transfer path. The held HTTP
/// response carries a [FileRequestResponse]. Byte-compatible with the native app.
class FileRequestMessage {
  const FileRequestMessage({
    required this.requestId,
    required this.requesterAlias,
    required this.requesterFingerprint,
    required this.requesterHost,
    required this.requesterPort,
    this.message,
    this.requestedTypes,
  });

  factory FileRequestMessage.fromJson(Map<String, dynamic> json) =>
      FileRequestMessage(
        requestId: json['requestId'] as String,
        requesterAlias: json['requesterAlias'] as String? ?? 'Unknown',
        requesterFingerprint: json['requesterFingerprint'] as String? ?? '',
        requesterHost: json['requesterHost'] as String? ?? '',
        requesterPort: (json['requesterPort'] as num?)?.toInt() ?? 58317,
        message: json['message'] as String?,
        requestedTypes: (json['requestedTypes'] as List?)?.cast<String>(),
      );

  final String requestId;
  final String requesterAlias;
  final String requesterFingerprint;
  final String requesterHost;
  final int requesterPort;
  final String? message;
  final List<String>? requestedTypes;

  Map<String, dynamic> toJson() => {
    'requestId': requestId,
    'requesterAlias': requesterAlias,
    'requesterFingerprint': requesterFingerprint,
    'requesterHost': requesterHost,
    'requesterPort': requesterPort,
    'message': message,
    'requestedTypes': requestedTypes,
  };
}

/// The held-connection reply to a [FileRequestMessage].
class FileRequestResponse {
  const FileRequestResponse({required this.requestId, required this.accepted});

  factory FileRequestResponse.fromJson(Map<String, dynamic> json) =>
      FileRequestResponse(
        requestId: json['requestId'] as String? ?? '',
        accepted: json['accepted'] as bool? ?? false,
      );

  final String requestId;
  final bool accepted;

  Map<String, dynamic> toJson() => {
    'requestId': requestId,
    'accepted': accepted,
  };
}
