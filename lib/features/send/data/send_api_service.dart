import 'package:dio/dio.dart';
import 'package:retrofit/retrofit.dart';

import '../../../core/constants/protocol.dart';
import '../../../core/protocol/device_info.dart';
import '../../../core/protocol/goodbye_request.dart';

part 'send_api_service.g.dart';

/// Retrofit client for the idempotent JSON endpoints (info / cancel / goodbye).
/// The non-idempotent, nonce-sensitive `upload` stays on raw Dio with a manual
/// fresh-nonce retry (see `TransferClient`).
@RestApi()
abstract class SendApiService {
  factory SendApiService(Dio dio, {String? baseUrl}) = _SendApiService;

  @GET(BIShareApi.info)
  Future<DeviceInfo> getInfo();

  @POST(BIShareApi.cancel)
  Future<void> cancel(@Query('sessionId') String sessionId);

  @POST(BIShareApi.goodbye)
  Future<void> goodbye(@Body() GoodbyeRequest request);
}
