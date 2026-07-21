import 'package:dio/dio.dart';
import 'package:nubia_core/src/network/api_client.dart';
import 'package:nubia_data/src/remote/periodontal_chart/periodontal_chart_dto.dart';

class PeriodontalChartApi {
  final Dio _dio;

  PeriodontalChartApi(ApiClient client) : _dio = client.dio;

  Future<PeriodontalChartDto> get(String patientId) async {
    final response = await _dio.get<Map<String, dynamic>>(
      '/cabinet/patients/$patientId/periodontal-chart',
    );
    return PeriodontalChartDto.fromJson(response.data!);
  }

  Future<PeriodontalChartDto> put(
    String patientId,
    PeriodontalChartDto dto,
  ) async {
    final response = await _dio.put<Map<String, dynamic>>(
      '/cabinet/patients/$patientId/periodontal-chart',
      data: dto.toJson(),
    );
    return PeriodontalChartDto.fromJson(response.data!);
  }
}
