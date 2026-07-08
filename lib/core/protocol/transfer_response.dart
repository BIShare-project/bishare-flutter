import 'package:json_annotation/json_annotation.dart';

part 'transfer_response.g.dart';

/// Response body from `POST /api/v1/upload`. Mirrors native `UploadResponse`.
@JsonSerializable(includeIfNull: false)
class UploadResponse {
  const UploadResponse({
    required this.success,
    this.verified,
    this.encrypted,
    this.message,
  });

  factory UploadResponse.fromJson(Map<String, dynamic> json) =>
      _$UploadResponseFromJson(json);

  final bool success;
  final bool? verified;
  final bool? encrypted;
  final String? message;

  Map<String, dynamic> toJson() => _$UploadResponseToJson(this);
}

/// Standard error response body: `{ "message": "..." }`.
@JsonSerializable()
class ErrorResponse {
  const ErrorResponse({required this.message});

  factory ErrorResponse.fromJson(Map<String, dynamic> json) =>
      _$ErrorResponseFromJson(json);

  final String message;

  Map<String, dynamic> toJson() => _$ErrorResponseToJson(this);
}
