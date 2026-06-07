import 'package:dio/dio.dart';
import 'package:injectable/injectable.dart';
import 'package:nubia_patient/core/network/api_constants.dart';
import 'package:nubia_patient/core/network/auth_interceptor.dart';

@lazySingleton
class ApiClient {
  late final Dio dio;

  ApiClient(AuthInterceptor authInterceptor) {
    dio = Dio(
      BaseOptions(
        baseUrl: ApiConstants.baseUrl,
        connectTimeout: ApiConstants.connectTimeout,
        receiveTimeout: ApiConstants.receiveTimeout,
        headers: {
          'Content-Type': ApiConstants.contentType,
          'Accept-Language': ApiConstants.acceptLanguage,
        },
      ),
    )..interceptors.addAll([
        authInterceptor,
        LogInterceptor(requestBody: false, responseBody: false),
      ]);
    // Give the interceptor a reference to this Dio so refresh/retry
    // calls reuse the same HttpClientAdapter (critical for tests).
    authInterceptor.setDio(dio);
  }
}
