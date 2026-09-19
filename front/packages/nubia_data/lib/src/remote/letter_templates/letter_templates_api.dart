import 'package:dio/dio.dart';
import 'package:nubia_core/src/network/api_client.dart';
import 'package:nubia_data/src/remote/letter_templates/letter_template_dto.dart';

class LetterTemplatesApi {
  final Dio _dio;

  LetterTemplatesApi(ApiClient client) : _dio = client.dio;

  /// Le back renvoie un tableau nu `[LetterTemplateDto]` (pas de wrapper
  /// `{data}`) — même convention que `GET /v1/cabinet/quotes`.
  Future<List<LetterTemplateDto>> list() async {
    final response = await _dio.get<List<dynamic>>('/letter-templates');
    final data = response.data ?? const [];
    return data
        .map((e) => LetterTemplateDto.fromJson(e as Map<String, dynamic>))
        .toList();
  }
}
