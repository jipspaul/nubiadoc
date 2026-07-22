import 'package:dio/dio.dart';
import 'package:nubia_core/src/network/api_client.dart';
import 'package:nubia_data/src/remote/sterilization/sterilization_cycle_dto.dart';

class SterilizationApi {
  final Dio _dio;

  SterilizationApi(ApiClient client) : _dio = client.dio;

  /// GET /cabinet/sterilization-cycles (#4138).
  Future<List<SterilizationCycleDto>> listCycles() async {
    final response =
        await _dio.get<List<dynamic>>('/cabinet/sterilization-cycles');
    return (response.data ?? [])
        .map((e) => SterilizationCycleDto.fromJson(e as Map<String, dynamic>))
        .toList();
  }

  /// POST /cabinet/sterilization-cycles/:id/pouches (#4138/#4139). Renvoie
  /// l'id de la pochette créée.
  Future<String> addPouch(
    String cycleId, {
    required String code,
    String? consultationActId,
  }) async {
    final response = await _dio.post<Map<String, dynamic>>(
      '/cabinet/sterilization-cycles/$cycleId/pouches',
      data: {
        'code': code,
        if (consultationActId != null) 'consultation_act_id': consultationActId,
      },
    );
    return response.data!['pouch_id'] as String;
  }
}
