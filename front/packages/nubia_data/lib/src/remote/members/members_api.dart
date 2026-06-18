import 'package:dio/dio.dart';
import 'package:nubia_core/src/network/api_client.dart';
import 'package:nubia_data/src/remote/members/members_dto.dart';
import 'package:nubia_domain/src/entities/member.dart';

class MembersApi {
  final Dio _dio;

  MembersApi(ApiClient client) : _dio = client.dio;

  Future<List<MemberDto>> list() async {
    final response = await _dio.get<List<dynamic>>('/cabinet/members');
    return (response.data!)
        .map((e) => MemberDto.fromJson(e as Map<String, dynamic>))
        .toList();
  }

  Future<MemberDto> getById(String id) async {
    final response =
        await _dio.get<Map<String, dynamic>>('/cabinet/members/$id');
    return MemberDto.fromJson(response.data!);
  }

  Future<MemberDto> create(Member member) async {
    final dto = MemberDto(
      id: '',
      cabinetId: member.cabinetId,
      firstName: member.firstName,
      lastName: member.lastName,
      email: member.email,
      role: member.role.name,
      specialty: member.specialty,
      isActive: member.isActive,
      joinedAt: member.joinedAt.toIso8601String(),
    );
    final response = await _dio.post<Map<String, dynamic>>(
      '/cabinet/members',
      data: dto.toJson(),
    );
    return MemberDto.fromJson(response.data!);
  }

  Future<MemberDto> update(Member member) async {
    final dto = MemberDto(
      id: member.id,
      cabinetId: member.cabinetId,
      firstName: member.firstName,
      lastName: member.lastName,
      email: member.email,
      role: member.role.name,
      specialty: member.specialty,
      isActive: member.isActive,
      joinedAt: member.joinedAt.toIso8601String(),
    );
    final response = await _dio.patch<Map<String, dynamic>>(
      '/cabinet/members/${member.id}',
      data: dto.toJson(),
    );
    return MemberDto.fromJson(response.data!);
  }

  Future<MemberDto> invite(String email, MemberRole role) async {
    final response = await _dio.post<Map<String, dynamic>>(
      '/cabinet/members',
      data: {'email': email, 'role': role.name},
    );
    return MemberDto.fromJson(response.data!);
  }

  Future<MemberDto> updateRole(String id, MemberRole role) async {
    final response = await _dio.patch<Map<String, dynamic>>(
      '/cabinet/members/$id',
      data: {'role': role.name},
    );
    return MemberDto.fromJson(response.data!);
  }
}
