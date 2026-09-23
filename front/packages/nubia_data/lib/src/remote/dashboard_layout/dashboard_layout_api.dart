import 'package:dio/dio.dart';
import 'package:nubia_core/src/network/api_client.dart';

/// `GET/PUT /v1/me/dashboard-layout` (#7161) — réponse `{"widgets": [...]}`,
/// assez simple pour être lue/écrite directement, pas de DTO dédié.
class DashboardLayoutApi {
  final Dio _dio;

  DashboardLayoutApi(ApiClient client) : _dio = client.dio;

  Future<List<String>> getLayout() async {
    final response =
        await _dio.get<Map<String, dynamic>>('/me/dashboard-layout');
    return (response.data?['widgets'] as List<dynamic>? ?? [])
        .cast<String>();
  }

  Future<List<String>> updateLayout(List<String> widgetIds) async {
    final response = await _dio.put<Map<String, dynamic>>(
      '/me/dashboard-layout',
      data: {'widgets': widgetIds},
    );
    return (response.data?['widgets'] as List<dynamic>? ?? [])
        .cast<String>();
  }
}
