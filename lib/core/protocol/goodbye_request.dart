import 'package:json_annotation/json_annotation.dart';

part 'goodbye_request.g.dart';

/// Body for `POST /api/v1/goodbye` — announces a peer is going offline.
@JsonSerializable()
class GoodbyeRequest {
  const GoodbyeRequest({required this.fingerprint});

  factory GoodbyeRequest.fromJson(Map<String, dynamic> json) =>
      _$GoodbyeRequestFromJson(json);

  final String fingerprint;

  Map<String, dynamic> toJson() => _$GoodbyeRequestToJson(this);
}
