import 'package:dio/dio.dart';
import 'package:nubia_core/src/network/api_client.dart';
import 'package:nubia_domain/src/repositories/pro_register_repository.dart';

class ProRegisterResponseDto {
  final String accountId;
  final String cabinetId;
  final String providerId;
  final String accessToken;

  const ProRegisterResponseDto({
    required this.accountId,
    required this.cabinetId,
    required this.providerId,
    required this.accessToken,
  });

  factory ProRegisterResponseDto.fromJson(Map<String, dynamic> json) =>
      ProRegisterResponseDto(
        accountId: json['account_id'] as String,
        cabinetId: json['cabinet_id'] as String,
        providerId: json['provider_id'] as String,
        accessToken: json['access_token'] as String,
      );
}

class ProRegisterApi {
  final Dio _dio;

  ProRegisterApi(ApiClient client) : _dio = client.dio;

  Future<ProRegisterResponseDto> register(ProRegisterRequest request) async {
    final response = await _dio.post<Map<String, dynamic>>(
      '/pro/register',
      data: {
        'email': request.email,
        'password': request.password,
        'cabinet': {
          'raison_sociale': request.cabinet.raisonSociale,
          if (request.cabinet.siret != null) 'siret': request.cabinet.siret,
          'specialite': request.cabinet.specialite,
        },
        'practitioner': {
          'first_name': request.practitioner.firstName,
          'last_name': request.practitioner.lastName,
          if (request.practitioner.rpps != null)
            'rpps': request.practitioner.rpps,
          if (request.practitioner.adeli != null)
            'adeli': request.practitioner.adeli,
        },
      },
    );
    return ProRegisterResponseDto.fromJson(response.data!);
  }
}
