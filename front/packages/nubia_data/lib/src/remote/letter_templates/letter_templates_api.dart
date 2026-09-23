import 'package:dio/dio.dart';
import 'package:nubia_core/src/network/api_client.dart';
import 'package:nubia_data/src/remote/letter_templates/letter_template_dto.dart';
import 'package:nubia_data/src/remote/letter_templates/letter_template_import_result_dto.dart';

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

  /// `POST /v1/letter-templates/import` (#7157) — multipart `name`/`kind`/
  /// `file` (`.docx`). Renvoie `{template_id, placeholders}`.
  Future<LetterTemplateImportResultDto> import({
    required String name,
    required String kind,
    required List<int> bytes,
    required String filename,
  }) async {
    final formData = FormData.fromMap({
      'name': name,
      'kind': kind,
      'file': MultipartFile.fromBytes(
        bytes,
        filename: filename,
        contentType: DioMediaType.parse(
          'application/vnd.openxmlformats-officedocument.wordprocessingml.document',
        ),
      ),
    });
    final response = await _dio.post<Map<String, dynamic>>(
      '/letter-templates/import',
      data: formData,
    );
    return LetterTemplateImportResultDto.fromJson(response.data!);
  }
}
