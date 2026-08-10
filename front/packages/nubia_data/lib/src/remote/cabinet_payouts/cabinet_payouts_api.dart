import 'package:dio/dio.dart';
import 'package:nubia_core/src/network/api_client.dart';
import 'package:nubia_data/src/remote/cabinet_payouts/cabinet_payout_dto.dart';

class CabinetPayoutsApi {
  final Dio _dio;

  CabinetPayoutsApi(ApiClient client) : _dio = client.dio;

  /// GET /cabinet/payouts (#4129). Réponse `{ data: [...] }`.
  Future<List<CabinetPayoutDto>> getPayouts() async {
    final response = await _dio.get<Map<String, dynamic>>('/cabinet/payouts');
    final data = (response.data?['data'] as List<dynamic>?) ?? [];
    return data
        .map((e) => CabinetPayoutDto.fromJson(e as Map<String, dynamic>))
        .toList();
  }
}
