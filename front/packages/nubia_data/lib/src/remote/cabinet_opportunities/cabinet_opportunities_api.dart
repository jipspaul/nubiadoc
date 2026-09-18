import 'package:dio/dio.dart';
import 'package:nubia_core/src/network/api_client.dart';
import 'package:nubia_data/src/remote/cabinet_opportunities/opportunity_category_dto.dart';

class CabinetOpportunitiesApi {
  final Dio _dio;

  CabinetOpportunitiesApi(ApiClient client) : _dio = client.dio;

  /// GET /cabinet/opportunities (#7213/#7214). Réponse `{ categories: [...] }`.
  Future<List<OpportunityCategoryDto>> getOpportunities() async {
    final response =
        await _dio.get<Map<String, dynamic>>('/cabinet/opportunities');
    final data = (response.data?['categories'] as List<dynamic>?) ?? [];
    return data
        .map((e) => OpportunityCategoryDto.fromJson(e as Map<String, dynamic>))
        .toList();
  }
}
