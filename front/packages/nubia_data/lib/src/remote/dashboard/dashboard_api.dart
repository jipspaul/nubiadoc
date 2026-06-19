import 'package:dio/dio.dart';
import 'package:nubia_core/src/network/api_client.dart';
import 'package:nubia_data/src/remote/dashboard/dashboard_dto.dart';

class DashboardApi {
  final Dio _dio;

  DashboardApi(ApiClient client) : _dio = client.dio;

  Future<DashboardDto> getSummary() async {
    final response = await _dio.get<Map<String, dynamic>>(
      '/account/dashboard',
    );
    return DashboardDto.fromJson(response.data!);
  }
}
