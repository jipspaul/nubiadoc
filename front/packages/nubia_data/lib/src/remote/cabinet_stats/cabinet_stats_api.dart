import 'package:dio/dio.dart';
import 'package:nubia_core/src/network/api_client.dart';
import 'package:nubia_data/src/remote/cabinet_stats/cabinet_activity_stat_dto.dart';
import 'package:nubia_data/src/remote/cabinet_stats/cabinet_billing_stats_dto.dart';

class CabinetStatsApi {
  final Dio _dio;

  CabinetStatsApi(ApiClient client) : _dio = client.dio;

  /// GET /cabinet/stats/activity (#4153). Réponse `{ data: [...] }`.
  Future<List<CabinetActivityStatDto>> getActivityStats() async {
    final response =
        await _dio.get<Map<String, dynamic>>('/cabinet/stats/activity');
    final data = (response.data?['data'] as List<dynamic>?) ?? [];
    return data
        .map((e) => CabinetActivityStatDto.fromJson(e as Map<String, dynamic>))
        .toList();
  }

  /// GET /cabinet/stats/billing (#4153). Réponse un objet plat (pas de wrapper).
  Future<CabinetBillingStatsDto> getBillingStats() async {
    final response =
        await _dio.get<Map<String, dynamic>>('/cabinet/stats/billing');
    return CabinetBillingStatsDto.fromJson(response.data!);
  }
}
