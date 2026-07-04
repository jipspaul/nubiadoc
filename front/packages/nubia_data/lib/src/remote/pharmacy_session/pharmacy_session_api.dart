import 'package:dio/dio.dart';
import 'package:nubia_core/src/network/api_client.dart';
import 'package:nubia_data/src/remote/pharmacy_session/pharmacy_session_dto.dart';

/// Session pharmacie : appartenances (`GET /v1/me`) et sélection du contexte
/// tenant (`POST /v1/auth/select-pharmacy-context`, JWT `kind:"pharma"`).
class PharmacySessionApi {
  final Dio _dio;

  PharmacySessionApi(ApiClient client) : _dio = client.dio;

  /// GET /v1/me → `pharmacy_memberships` (vide pour un token patient).
  Future<List<PharmacyMembershipDto>> myMemberships() async {
    final response = await _dio.get<Map<String, dynamic>>('/me');
    final raw =
        response.data?['pharmacy_memberships'] as List<dynamic>? ?? const [];
    return raw
        .map((e) => PharmacyMembershipDto.fromJson(e as Map<String, dynamic>))
        .toList();
  }

  /// POST /v1/auth/select-pharmacy-context
  Future<SelectPharmacyContextDto> selectContext(String pharmacyId) async {
    final response = await _dio.post<Map<String, dynamic>>(
      '/auth/select-pharmacy-context',
      data: {'pharmacy_id': pharmacyId},
    );
    return SelectPharmacyContextDto.fromJson(response.data!);
  }
}
