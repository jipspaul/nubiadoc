import 'package:dio/dio.dart';
import 'package:nubia_core/src/network/api_client.dart';
import 'package:nubia_data/src/remote/cash_collection/cash_collection_summary_dto.dart';

class CashCollectionApi {
  final Dio _dio;

  CashCollectionApi(ApiClient client) : _dio = client.dio;

  /// GET /cabinet/cash-collection/today (#5382). Réponse un objet plat (pas
  /// de wrapper), même contrat que `CabinetStatsApi.getBillingStats`.
  Future<CashCollectionSummaryDto> getTodaySummary() async {
    final response =
        await _dio.get<Map<String, dynamic>>('/cabinet/cash-collection/today');
    return CashCollectionSummaryDto.fromJson(response.data!);
  }
}
