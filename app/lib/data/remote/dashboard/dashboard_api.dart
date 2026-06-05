import 'package:dio/dio.dart';
import 'package:injectable/injectable.dart';
import 'package:nubia_patient/core/network/api_client.dart';
import 'package:nubia_patient/data/remote/dashboard/dashboard_dto.dart';

@injectable
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
