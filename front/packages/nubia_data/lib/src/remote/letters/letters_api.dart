import 'package:dio/dio.dart';
import 'package:nubia_core/src/network/api_client.dart';
import 'package:nubia_data/src/remote/letters/generated_letter_dto.dart';

class LettersApi {
  final Dio _dio;

  LettersApi(ApiClient client) : _dio = client.dio;

  Future<GeneratedLetterDto> generate(
    String patientId, {
    required String templateId,
    Map<String, String> overrides = const {},
  }) async {
    final response = await _dio.post<Map<String, dynamic>>(
      '/patients/$patientId/letters',
      data: {
        'template_id': templateId,
        'overrides': overrides,
      },
    );
    return GeneratedLetterDto.fromJson(response.data!);
  }
}
