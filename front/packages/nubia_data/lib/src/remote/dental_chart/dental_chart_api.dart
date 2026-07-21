import 'package:dio/dio.dart';
import 'package:nubia_core/src/network/api_client.dart';
import 'package:nubia_data/src/remote/dental_chart/dental_chart_dto.dart';

class DentalChartApi {
  final Dio _dio;

  DentalChartApi(ApiClient client) : _dio = client.dio;

  Future<DentalChartDto> get(String patientId) async {
    final response = await _dio
        .get<Map<String, dynamic>>('/cabinet/patients/$patientId/dental-chart');
    return DentalChartDto.fromJson(response.data!);
  }

  Future<DentalChartDto> put(String patientId, DentalChartDto dto) async {
    final response = await _dio.put<Map<String, dynamic>>(
      '/cabinet/patients/$patientId/dental-chart',
      data: dto.toJson(),
    );
    return DentalChartDto.fromJson(response.data!);
  }
}
