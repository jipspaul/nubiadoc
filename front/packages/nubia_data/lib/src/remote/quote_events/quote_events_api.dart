import 'package:dio/dio.dart';
import 'package:nubia_core/src/network/api_client.dart';
import 'package:nubia_data/src/remote/quote_events/quote_events_dto.dart';

class QuoteEventsApi {
  final Dio _dio;

  QuoteEventsApi(ApiClient client) : _dio = client.dio;

  Future<List<QuoteEventDto>> listCabinetEvents(String quoteId) async {
    final response = await _dio
        .get<Map<String, dynamic>>('/cabinet/quotes/$quoteId/events');
    final data = response.data?['data'] as List<dynamic>? ?? const [];
    return data
        .map((e) => QuoteEventDto.fromJson(e as Map<String, dynamic>))
        .toList();
  }
}
