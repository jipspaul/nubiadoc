import 'package:dio/dio.dart';
import 'package:nubia_core/src/network/api_client.dart';
import 'package:nubia_data/src/remote/search/search_dto.dart';

class SearchApi {
  final Dio _dio;

  SearchApi(ApiClient client) : _dio = client.dio;

  /// GET /v1/search/providers → { data: [ProviderItem], facets, page }.
  /// `q` vide/absent = annuaire par défaut (praticiens listés).
  Future<List<ProviderResultDto>> searchProviders({
    required String query,
  }) async {
    final trimmed = query.trim();
    final response = await _dio.get<Map<String, dynamic>>(
      '/search/providers',
      queryParameters: {if (trimmed.isNotEmpty) 'q': trimmed},
    );
    final data = (response.data?['data'] as List<dynamic>? ?? []);
    return data
        .map((e) => ProviderResultDto.fromJson(e as Map<String, dynamic>))
        .toList();
  }

  /// GET /v1/providers/:id/availability → { data: [AvailabilitySlotItem] }.
  /// 50 prochains créneaux ouverts du praticien.
  Future<List<SlotDto>> searchSlots({
    required String providerId,
    DateTime? from,
    DateTime? to,
  }) async {
    final response = await _dio.get<Map<String, dynamic>>(
      '/providers/$providerId/availability',
    );
    final data = (response.data?['data'] as List<dynamic>? ?? []);
    return data
        .map((e) => SlotDto.fromAvailabilityJson(e as Map<String, dynamic>))
        .toList();
  }

  /// POST /v1/slots/:id/hold → { hold_token, expires_at }.
  Future<String> holdSlot(String slotId) async {
    final response = await _dio.post<Map<String, dynamic>>(
      '/slots/$slotId/hold',
    );
    return response.data!['hold_token'] as String;
  }
}
