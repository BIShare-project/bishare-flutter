// GENERATED CODE - DO NOT MODIFY BY HAND

part of 'transfer_response.dart';

// **************************************************************************
// JsonSerializableGenerator
// **************************************************************************

UploadResponse _$UploadResponseFromJson(Map<String, dynamic> json) =>
    UploadResponse(
      success: json['success'] as bool,
      verified: json['verified'] as bool?,
      encrypted: json['encrypted'] as bool?,
      message: json['message'] as String?,
    );

Map<String, dynamic> _$UploadResponseToJson(UploadResponse instance) =>
    <String, dynamic>{
      'success': instance.success,
      'verified': ?instance.verified,
      'encrypted': ?instance.encrypted,
      'message': ?instance.message,
    };

ErrorResponse _$ErrorResponseFromJson(Map<String, dynamic> json) =>
    ErrorResponse(message: json['message'] as String);

Map<String, dynamic> _$ErrorResponseToJson(ErrorResponse instance) =>
    <String, dynamic>{'message': instance.message};
