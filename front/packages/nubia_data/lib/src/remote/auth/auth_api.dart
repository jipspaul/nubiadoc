import 'package:dio/dio.dart';
import 'package:nubia_core/src/network/api_client.dart';
import 'package:nubia_data/src/remote/auth/auth_dto.dart';

class AuthApi {
  final Dio _dio;

  AuthApi(ApiClient client) : _dio = client.dio;

  Future<AuthResponseDto> login({
    required String email,
    required String password,
  }) async {
    final response = await _dio.post<Map<String, dynamic>>(
      '/auth/login',
      data: {'email': email, 'password': password},
    );
    return AuthResponseDto.fromJson(response.data!);
  }

  Future<AuthResponseDto> register({
    required String email,
    required String password,
    required String inviteToken,
  }) async {
    final response = await _dio.post<Map<String, dynamic>>(
      '/auth/register',
      data: {
        'email': email,
        'password': password,
        'invite_token': inviteToken,
      },
    );
    return AuthResponseDto.fromJson(response.data!);
  }

  Future<PatientAccountDto> getMe() async {
    final response = await _dio.get<Map<String, dynamic>>('/account/me');
    return PatientAccountDto.fromJson(response.data!);
  }

  Future<TokenResponseDto> refresh({required String refreshToken}) async {
    final response = await _dio.post<Map<String, dynamic>>(
      '/auth/refresh',
      data: {'refresh_token': refreshToken},
    );
    return TokenResponseDto.fromJson(response.data!);
  }
}
