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

  /// POST /v1/search/parse → { query:{...}, interpretation, source }.
  /// Interprète une recherche en langage naturel (spécialité, lieu, secteur…).
  Future<ParsedSearchDto> parseSearch(String query) async {
    final response = await _dio.post<Map<String, dynamic>>(
      '/search/parse',
      data: {'q': query.trim()},
    );
    return ParsedSearchDto.fromJson(response.data ?? const {});
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
  Future<SlotHoldDto> holdSlot(String slotId) async {
    final response = await _dio.post<Map<String, dynamic>>(
      '/slots/$slotId/hold',
    );
    final data = response.data!;
    return SlotHoldDto(
      token: data['hold_token'] as String,
      expiresAt: DateTime.parse(data['expires_at'] as String),
    );
  }

  /// POST /v1/bookings → { appointment_id }. Confirme la réservation d'un
  /// créneau tenu via [holdSlot] (contrat `docs/12-api-reference.md` §12.3).
  Future<String> confirmBooking({
    required String slotId,
    required String holdToken,
    required String motif,
    required String idempotencyKey,
    String? onBehalfOf,
  }) async {
    final response = await _dio.post<Map<String, dynamic>>(
      '/bookings',
      data: {
        'slot_id': slotId,
        'hold_token': holdToken,
        'motif': motif,
        if (onBehalfOf != null) 'on_behalf_of': onBehalfOf,
      },
      options: Options(headers: {'Idempotency-Key': idempotencyKey}),
    );
    return response.data!['appointment_id'] as String;
  }
}
