import 'package:dio/dio.dart';
import 'package:nubia_core/src/network/api_client.dart';
import 'package:nubia_data/src/remote/cabinet_correspondents/cabinet_correspondent_dto.dart';

class CabinetCorrespondentsApi {
  final Dio _dio;

  CabinetCorrespondentsApi(ApiClient client) : _dio = client.dio;

  Future<List<CabinetCorrespondentDto>> list() async {
    final response =
        await _dio.get<List<dynamic>>('/cabinet/correspondents');
    return (response.data ?? [])
        .map((e) => CabinetCorrespondentDto.fromJson(e as Map<String, dynamic>))
        .toList();
  }

  Future<CabinetCorrespondentDto> create({
    required String displayName,
    String? specialty,
    String? email,
    String? phone,
    String? address,
    String? rpps,
    String? notes,
  }) async {
    final response = await _dio.post<Map<String, dynamic>>(
      '/cabinet/correspondents',
      data: {
        'display_name': displayName,
        if (specialty != null) 'specialty': specialty,
        if (email != null) 'email': email,
        if (phone != null) 'phone': phone,
        if (address != null) 'address': address,
        if (rpps != null) 'rpps': rpps,
        if (notes != null) 'notes': notes,
      },
    );
    return CabinetCorrespondentDto.fromJson(response.data!);
  }

  Future<CabinetCorrespondentDto> update(
    String id, {
    String? displayName,
    String? specialty,
    String? email,
    String? phone,
    String? address,
    String? rpps,
    String? notes,
  }) async {
    final response = await _dio.patch<Map<String, dynamic>>(
      '/cabinet/correspondents/$id',
      data: {
        if (displayName != null) 'display_name': displayName,
        if (specialty != null) 'specialty': specialty,
        if (email != null) 'email': email,
        if (phone != null) 'phone': phone,
        if (address != null) 'address': address,
        if (rpps != null) 'rpps': rpps,
        if (notes != null) 'notes': notes,
      },
    );
    return CabinetCorrespondentDto.fromJson(response.data!);
  }

  Future<void> delete(String id) async {
    await _dio.delete<void>('/cabinet/correspondents/$id');
  }

  Future<CorrespondentStatsDto> getStats(String id) async {
    final response = await _dio
        .get<Map<String, dynamic>>('/cabinet/correspondents/$id/stats');
    return CorrespondentStatsDto.fromJson(response.data!);
  }
}
