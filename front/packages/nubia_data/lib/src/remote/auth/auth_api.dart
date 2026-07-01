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
    required bool acceptCgu,
    required String cguVersion,
    String? inviteToken,
  }) async {
    final response = await _dio.post<Map<String, dynamic>>(
      '/auth/register',
      data: {
        'email': email,
        'password': password,
        'accept_cgu': acceptCgu,
        'cgu_version': cguVersion,
        if (inviteToken != null) 'invitation_token': inviteToken,
      },
    );
    return AuthResponseDto.fromJson(response.data!);
  }

  Future<PatientAccountDto> getMe() async {
    final response = await _dio.get<Map<String, dynamic>>('/me');
    return PatientAccountDto.fromJson(response.data!);
  }

  Future<ProRegisterResponseDto> registerPro({
    required String email,
    required String password,
    required String firstName,
    required String lastName,
    String? rpps,
    String? adeli,
    required String raisonSociale,
    String? siret,
    required String specialite,
  }) async {
    final response = await _dio.post<Map<String, dynamic>>(
      '/pro/register',
      data: {
        'email': email,
        'password': password,
        'practitioner': {
          'first_name': firstName,
          'last_name': lastName,
          if (rpps != null) 'rpps': rpps,
          if (adeli != null) 'adeli': adeli,
        },
        'cabinet': {
          'raison_sociale': raisonSociale,
          if (siret != null) 'siret': siret,
          'specialite': specialite,
        },
      },
    );
    return ProRegisterResponseDto.fromJson(response.data!);
  }

  Future<TokenResponseDto> refresh({required String refreshToken}) async {
    final response = await _dio.post<Map<String, dynamic>>(
      '/auth/refresh',
      data: {'refresh_token': refreshToken},
    );
    return TokenResponseDto.fromJson(response.data!);
  }

  /// Réponse neutre (204) que l'email existe ou non — anti-énumération.
  Future<void> forgotPassword({required String email}) async {
    await _dio.post<void>(
      '/auth/password/forgot',
      data: {'email': email},
    );
  }

  Future<void> resetPassword({
    required String token,
    required String newPassword,
  }) async {
    await _dio.post<void>(
      '/auth/password/reset',
      data: {'token': token, 'new_password': newPassword},
    );
  }
}
