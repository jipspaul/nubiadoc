import 'package:dio/dio.dart';
import 'package:nubia_core/src/network/api_client.dart';
import 'package:nubia_data/src/remote/treatment_plans/treatment_plans_dto.dart';

class TreatmentPlansApi {
  final Dio _dio;

  TreatmentPlansApi(ApiClient client) : _dio = client.dio;

  Future<List<TreatmentPlanDto>> list(String patientId) async {
    final response = await _dio.get<Map<String, dynamic>>(
      '/cabinet/patients/$patientId/treatment-plans',
    );
    final data = response.data!['data'] as List<dynamic>;
    return data
        .map((p) => TreatmentPlanDto.fromJson(p as Map<String, dynamic>))
        .toList();
  }

  /// Retourne l'id du plan créé.
  Future<String> create(String patientId, String title) async {
    final response = await _dio.post<Map<String, dynamic>>(
      '/cabinet/treatment-plans',
      data: {'patient_id': patientId, 'title': title},
    );
    return response.data!['plan_id'] as String;
  }

  /// Retourne l'id de la phase créée.
  Future<String> createPhase(String planId, String title, int position) async {
    final response = await _dio.post<Map<String, dynamic>>(
      '/cabinet/treatment-plans/$planId/phases',
      data: {'title': title, 'position': position},
    );
    return response.data!['phase_id'] as String;
  }
}
