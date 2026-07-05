import 'package:dio/dio.dart';
import 'package:nubia_core/src/network/api_client.dart';

/// Notes du jour du dashboard praticien (`GET /v1/cabinet/today-notes`, #3368).
class TodayNotesApi {
  final Dio _dio;

  TodayNotesApi(ApiClient client) : _dio = client.dio;

  Future<List<Map<String, dynamic>>> getTodayNotes() async {
    final response = await _dio.get<Map<String, dynamic>>(
      '/cabinet/today-notes',
    );
    final data = (response.data!['data'] as List<dynamic>?) ?? [];
    return data.cast<Map<String, dynamic>>();
  }
}
