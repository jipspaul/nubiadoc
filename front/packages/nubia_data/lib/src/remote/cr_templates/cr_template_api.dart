import 'package:dio/dio.dart';
import 'package:nubia_core/src/network/api_client.dart';
import 'package:nubia_data/src/remote/cr_templates/cr_template_dto.dart';

class CrTemplateApi {
  final Dio _dio;

  CrTemplateApi(ApiClient client) : _dio = client.dio;

  /// GET /v1/cabinet/cr-templates (#4124).
  Future<List<CrTemplateDto>> listCrTemplates() async {
    final response = await _dio.get<List<dynamic>>('/cabinet/cr-templates');
    return (response.data ?? [])
        .map((e) => CrTemplateDto.fromJson(e as Map<String, dynamic>))
        .toList();
  }
}
