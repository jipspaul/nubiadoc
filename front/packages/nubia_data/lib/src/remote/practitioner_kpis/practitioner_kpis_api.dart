import 'package:dio/dio.dart';
import 'package:nubia_core/src/network/api_client.dart';
import 'package:nubia_data/src/remote/practitioner_kpis/practitioner_kpis_dto.dart';

class PractitionerKpisApi {
  final Dio _dio;

  PractitionerKpisApi(ApiClient client) : _dio = client.dio;

  /// GET /me/kpis?period=YYYY-MM (#7189).
  Future<PractitionerKpisDto> getMyKpis({String? period}) async {
    final response = await _dio.get<Map<String, dynamic>>(
      '/me/kpis',
      queryParameters: {if (period != null) 'period': period},
    );
    return PractitionerKpisDto.fromJson(response.data!);
  }
}
