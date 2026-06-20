import 'package:dio/dio.dart';
import 'package:nubia_core/src/network/api_client.dart';
import 'package:nubia_data/src/remote/cabinet_dashboard/cabinet_dashboard_dto.dart';

class CabinetDashboardApi {
  final Dio _dio;

  CabinetDashboardApi(ApiClient client) : _dio = client.dio;

  Future<CabinetDashboardDto> getSummary() async {
    final response = await _dio.get<Map<String, dynamic>>(
      '/cabinet/dashboard',
    );
    return CabinetDashboardDto.fromJson(response.data!);
  }
}
