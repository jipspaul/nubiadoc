import 'package:dio/dio.dart';
import 'package:nubia_core/src/network/api_client.dart';
import 'package:nubia_data/src/remote/patient_tags/patient_tag_dto.dart';

class PatientTagsApi {
  final Dio _dio;

  PatientTagsApi(ApiClient client) : _dio = client.dio;

  Future<List<PatientTagDto>> list(String patientId) async {
    final response = await _dio
        .get<Map<String, dynamic>>('/cabinet/patients/$patientId/tags');
    final data = (response.data!['data'] as List<dynamic>?) ?? [];
    return data
        .map((e) => PatientTagDto.fromJson(e as Map<String, dynamic>))
        .toList();
  }

  Future<PatientTagDto> create(
    String patientId, {
    required String label,
    String? color,
  }) async {
    final response = await _dio.post<Map<String, dynamic>>(
      '/cabinet/patients/$patientId/tags',
      data: {
        'label': label,
        if (color != null) 'color': color,
      },
    );
    return PatientTagDto.fromJson(response.data!);
  }

  Future<void> delete(String patientId, String tagId) async {
    await _dio.delete<void>('/cabinet/patients/$patientId/tags/$tagId');
  }
}
