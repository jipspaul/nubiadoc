import 'package:dio/dio.dart';
import 'package:nubia_core/src/network/api_client.dart';
import 'package:nubia_data/src/remote/questionnaire_templates/questionnaire_template_dto.dart';

class QuestionnaireTemplateApi {
  final Dio _dio;

  QuestionnaireTemplateApi(ApiClient client) : _dio = client.dio;

  /// `GET /v1/cabinet/questionnaire-templates`.
  Future<List<QuestionnaireTemplateDto>> list() async {
    final response =
        await _dio.get<List<dynamic>>('/cabinet/questionnaire-templates');
    return (response.data ?? [])
        .map(
          (e) => QuestionnaireTemplateDto.fromJson(e as Map<String, dynamic>),
        )
        .toList();
  }

  /// `POST /v1/cabinet/questionnaire-templates`.
  Future<({String id, int version})> create({
    required String title,
    required List<QuestionnaireQuestionDto> schema,
  }) async {
    final response = await _dio.post<Map<String, dynamic>>(
      '/cabinet/questionnaire-templates',
      data: {
        'title': title,
        'schema': schema.map((q) => q.toJson()).toList(),
      },
    );
    final data = response.data!;
    return (id: data['id'] as String, version: data['version'] as int);
  }

  /// `PATCH /v1/cabinet/questionnaire-templates/:id`.
  Future<({String id, int version})> patch(
    String id, {
    String? title,
    List<QuestionnaireQuestionDto>? schema,
  }) async {
    final response = await _dio.patch<Map<String, dynamic>>(
      '/cabinet/questionnaire-templates/$id',
      data: {
        if (title != null) 'title': title,
        if (schema != null) 'schema': schema.map((q) => q.toJson()).toList(),
      },
    );
    final data = response.data!;
    return (id: data['id'] as String, version: data['version'] as int);
  }

  /// `DELETE /v1/cabinet/questionnaire-templates/:id`.
  Future<void> delete(String id) async {
    await _dio.delete<void>('/cabinet/questionnaire-templates/$id');
  }
}
