import 'package:dio/dio.dart';
import 'package:nubia_core/src/network/api_client.dart';
import 'package:nubia_data/src/remote/search/search_dto.dart';

class SearchApi {
  final Dio _dio;

  SearchApi(ApiClient client) : _dio = client.dio;

  Future<List<ProviderResultDto>> searchProviders({
    required String query,
  }) async {
    final response = await _dio.get<List<dynamic>>(
      '/search/providers',
      queryParameters: {'q': query},
    );
    return (response.data!)
        .map((e) => ProviderResultDto.fromJson(e as Map<String, dynamic>))
        .toList();
  }

  Future<List<SlotDto>> searchSlots({
    required String providerId,
    DateTime? from,
    DateTime? to,
  }) async {
    final params = <String, dynamic>{'provider_id': providerId};
    if (from != null) params['from'] = from.toIso8601String();
    if (to != null) params['to'] = to.toIso8601String();

    final response = await _dio.get<List<dynamic>>(
      '/search/slots',
      queryParameters: params,
    );
    return (response.data!)
        .map((e) => SlotDto.fromJson(e as Map<String, dynamic>))
        .toList();
  }

  Future<SlotDto> holdSlot(String slotId) async {
    final response = await _dio.post<Map<String, dynamic>>(
      '/slots/$slotId/hold',
    );
    return SlotDto.fromJson(response.data!);
  }
}
