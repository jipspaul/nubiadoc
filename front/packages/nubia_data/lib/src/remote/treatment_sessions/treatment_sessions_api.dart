import 'package:dio/dio.dart';
import 'package:nubia_core/src/network/api_client.dart';
import 'package:nubia_data/src/remote/treatment_sessions/treatment_sessions_dto.dart';

class TreatmentSessionsApi {
  final Dio _dio;

  TreatmentSessionsApi(ApiClient client) : _dio = client.dio;

  Future<List<TreatmentSessionDto>> proposeSessions(
    String planId, {
    int? defaultDurationMin,
  }) async {
    final response = await _dio.post<Map<String, dynamic>>(
      '/cabinet/treatment-plans/$planId/sessions/propose',
      data: {
        if (defaultDurationMin != null)
          'default_duration_min': defaultDurationMin,
      },
    );
    final data = response.data!['sessions'] as List<dynamic>;
    return data
        .map((s) => TreatmentSessionDto.fromJson(s as Map<String, dynamic>))
        .toList();
  }

  Future<List<ProposedSlotDto>> proposeSlots(
    String planId,
    String sessionId,
  ) async {
    final response = await _dio.post<Map<String, dynamic>>(
      '/cabinet/treatment-plans/$planId/sessions/$sessionId/slots',
      data: <String, dynamic>{},
    );
    final data = response.data!['slots'] as List<dynamic>;
    return data
        .map((s) => ProposedSlotDto.fromJson(s as Map<String, dynamic>))
        .toList();
  }

  /// Retourne l'id du RDV créé.
  Future<String> scheduleSession(
    String planId,
    String sessionId,
    String slotId,
  ) async {
    final response = await _dio.post<Map<String, dynamic>>(
      '/cabinet/treatment-plans/$planId/sessions/$sessionId/schedule',
      data: {'slot_id': slotId},
    );
    return response.data!['appointment_id'] as String;
  }
}
