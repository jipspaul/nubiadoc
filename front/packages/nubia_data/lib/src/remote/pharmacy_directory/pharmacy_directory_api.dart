import 'package:dio/dio.dart';
import 'package:nubia_core/src/network/api_client.dart';
import 'package:nubia_data/src/remote/pharmacy_directory/pharmacy_dto.dart';

class PharmacyDirectoryApi {
  final Dio _dio;

  PharmacyDirectoryApi(ApiClient client) : _dio = client.dio;

  /// GET /v1/pharmacies — annuaire public.
  Future<List<PharmacyDto>> search({
    String? query,
    double? lat,
    double? lng,
    double? radiusKm,
  }) async {
    final response = await _dio.get<dynamic>(
      '/pharmacies',
      queryParameters: {
        if (query != null && query.isNotEmpty) 'q': query,
        if (lat != null) 'lat': lat,
        if (lng != null) 'lng': lng,
        if (radiusKm != null) 'radius_km': radiusKm,
      },
    );
    final raw = response.data;
    final data = raw is List
        ? raw
        : ((raw as Map<String, dynamic>?)?['data'] as List<dynamic>? ??
            const []);
    return data
        .map((e) => PharmacyDto.fromJson(e as Map<String, dynamic>))
        .toList();
  }

  /// GET /v1/cabinet/patients/{id}/pharmacy — null si 204 (aucune déclarée).
  Future<PharmacyDto?> getPatientPharmacy(String patientId) async {
    final response = await _dio.get<Map<String, dynamic>>(
      '/cabinet/patients/$patientId/pharmacy',
    );
    final data = response.data;
    if (data == null || data.isEmpty) return null;
    return PharmacyDto.fromJson(data);
  }
}
