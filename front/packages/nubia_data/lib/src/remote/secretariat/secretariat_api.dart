import 'package:dio/dio.dart';
import 'package:nubia_core/src/network/api_client.dart';
import 'package:nubia_data/src/remote/secretariat/secretariat_dto.dart';
import 'package:nubia_domain/src/entities/secretariat.dart';

class SecretariatApi {
  final Dio _dio;

  SecretariatApi(ApiClient client) : _dio = client.dio;

  Future<List<SecretariatDto>> list() async {
    final response = await _dio.get<List<dynamic>>('/cabinet/secretariats');
    return (response.data!)
        .map((e) => SecretariatDto.fromJson(e as Map<String, dynamic>))
        .toList();
  }

  Future<SecretariatDto> getById(String id) async {
    final response =
        await _dio.get<Map<String, dynamic>>('/cabinet/secretariats/$id');
    return SecretariatDto.fromJson(response.data!);
  }

  Future<SecretariatDto> create(Secretariat secretariat) async {
    final dto = SecretariatDto(
      id: '',
      cabinetId: secretariat.cabinetId,
      name: secretariat.name,
      email: secretariat.email,
      phone: secretariat.phone,
      isActive: secretariat.isActive,
      createdAt: secretariat.createdAt.toIso8601String(),
    );
    final response = await _dio.post<Map<String, dynamic>>(
      '/cabinet/secretariats',
      data: dto.toJson(),
    );
    return SecretariatDto.fromJson(response.data!);
  }

  Future<SecretariatDto> update(Secretariat secretariat) async {
    final dto = SecretariatDto(
      id: secretariat.id,
      cabinetId: secretariat.cabinetId,
      name: secretariat.name,
      email: secretariat.email,
      phone: secretariat.phone,
      isActive: secretariat.isActive,
      createdAt: secretariat.createdAt.toIso8601String(),
    );
    final response = await _dio.patch<Map<String, dynamic>>(
      '/cabinet/secretariats/${secretariat.id}',
      data: dto.toJson(),
    );
    return SecretariatDto.fromJson(response.data!);
  }

  /// Crée le secrétariat (POST /cabinet/secretariats {name}) puis
  /// provisionne le premier membre (POST .../:id/staff {email, role}) —
  /// le back envoie le mail d'invitation.
  Future<SecretariatDto> invite({
    required String name,
    required String email,
  }) async {
    final created = await _dio.post<Map<String, dynamic>>(
      '/cabinet/secretariats',
      data: {'name': name},
    );
    final dto = SecretariatDto.fromJson(created.data!);
    await _dio.post<Map<String, dynamic>>(
      '/cabinet/secretariats/${dto.id}/staff',
      data: {'email': email, 'role': 'secretary'},
    );
    return dto;
  }
}
