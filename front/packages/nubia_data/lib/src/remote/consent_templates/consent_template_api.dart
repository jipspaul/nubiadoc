import 'package:dio/dio.dart';
import 'package:nubia_core/src/network/api_client.dart';
import 'package:nubia_data/src/remote/consent_templates/consent_template_dto.dart';
import 'package:nubia_data/src/remote/consent_templates/rendered_consent_template_dto.dart';

class ConsentTemplateApi {
  final Dio _dio;

  ConsentTemplateApi(ApiClient client) : _dio = client.dio;

  /// `GET /v1/cabinet/consent-templates`.
  Future<List<ConsentTemplateDto>> list() async {
    final response =
        await _dio.get<List<dynamic>>('/cabinet/consent-templates');
    return (response.data ?? [])
        .map((e) => ConsentTemplateDto.fromJson(e as Map<String, dynamic>))
        .toList();
  }

  /// `POST /v1/cabinet/consent-templates`.
  Future<({String id, int version})> create({
    required String actCategory,
    required String title,
    required String bodyMarkdown,
  }) async {
    final response = await _dio.post<Map<String, dynamic>>(
      '/cabinet/consent-templates',
      data: {
        'act_category': actCategory,
        'title': title,
        'body_markdown': bodyMarkdown,
      },
    );
    final data = response.data!;
    return (id: data['id'] as String, version: data['version'] as int);
  }

  /// `PATCH /v1/cabinet/consent-templates/:id`.
  Future<({String id, int version})> patch(
    String id, {
    String? actCategory,
    String? title,
    String? bodyMarkdown,
  }) async {
    final response = await _dio.patch<Map<String, dynamic>>(
      '/cabinet/consent-templates/$id',
      data: {
        if (actCategory != null) 'act_category': actCategory,
        if (title != null) 'title': title,
        if (bodyMarkdown != null) 'body_markdown': bodyMarkdown,
      },
    );
    final data = response.data!;
    return (id: data['id'] as String, version: data['version'] as int);
  }

  /// `POST /v1/consent-templates/:id/render`.
  Future<RenderedConsentTemplateDto> render(
    String id, {
    required String quoteId,
  }) async {
    final response = await _dio.post<Map<String, dynamic>>(
      '/consent-templates/$id/render',
      data: {'quote_id': quoteId},
    );
    return RenderedConsentTemplateDto.fromJson(response.data!);
  }
}
