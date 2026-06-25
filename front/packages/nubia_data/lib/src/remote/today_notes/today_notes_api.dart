import 'package:dio/dio.dart';
import 'package:nubia_core/src/network/api_client.dart';

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
